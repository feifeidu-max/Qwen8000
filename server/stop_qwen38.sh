#!/bin/bash
# Qwen3.8-27B vLLM 停止脚本（含孤儿进程兜底清理）v2
touch /mnt/sdc/work/.qwen38_manual_stop
echo "== manual stop flag set; sending SIGKILL to vLLM processes =="
pkill -9 -f "vllm.entrypoints.openai.api_server" 2>/dev/null
pkill -9 -f "VLLM::EngineCore" 2>/dev/null
pkill -9 -f "multiprocessing.resource_tracker" 2>/dev/null
pkill -9 -f "VLLM:" 2>/dev/null   # covers ::EngineCore / ::Worker_TP*
sleep 3

# 兜底：直接清理仍占用 GPU1 的计算进程（不影响 GPU0 其他用户）
LEFT=$(nvidia-smi --query-compute-apps=pid --format=csv,noheader -i 1)
if [ -n "$LEFT" ]; then
    echo "== orphan GPU procs remain, killing PIDs: $LEFT =="
    for pid in $LEFT; do kill -9 "$pid" 2>/dev/null; done
    sleep 2
    LEFT2=$(nvidia-smi --query-compute-apps=pid --format=csv,noheader -i 1)
    [ -n "$LEFT2" ] && echo "WARNING still alive: $LEFT2"
fi

MEM=$(nvidia-smi --query-gpu=memory.used --format=csv,noheader -i 1)
echo "DONE. GPU1 memory now: $MEM"
