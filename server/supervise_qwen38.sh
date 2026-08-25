#!/bin/bash
# Qwen3.8-27B 守护进程：崩溃自动重启，人工关闭则退出
# 用法: setsid nohup bash supervise_qwen38.sh > supervisor.log 2>&1 < /dev/null &
FLAG=/mnt/sdc/work/.qwen38_manual_stop
LOGDIR=/mnt/sdc/work/vllm-2080ti/run-logs

echo "[supervisor] started at $(date)"
rm -f "$FLAG"
CYCLE=0
while true; do
    CYCLE=$((CYCLE+1))
    rm -f "$FLAG"                      # 每次启动前清除人工停止标记
    echo "[supervisor] cycle $CYCLE launching model at $(date)"
    bash /mnt/sdc/work/restart_qwen38_awq.sh
    if ! ss -tln 2>/dev/null | grep -q ":8000 "; then
        echo "[supervisor] startup FAILED this cycle, retrying in 60s"
        pkill -9 -f "vllm.entrypoints.openai.api_server" 2>/dev/null
        pkill -9 -f "VLLM::EngineCore" 2>/dev/null
        sleep 60
        continue
    fi
    echo "[supervisor] model UP, watching (poll 15s)"
    while ss -tln 2>/dev/null | grep -q ":8000 "; do
        sleep 15
    done
    # 走到这里说明端口掉了
    if [ -f "$FLAG" ]; then
        echo "[supervisor] MANUAL STOP detected -> supervisor exiting at $(date)"
        exit 0
    fi
    echo "[supervisor] CRASH detected at $(date), cleaning and restarting in 15s"
    pkill -9 -f "vllm.entrypoints.openai.api_server" 2>/dev/null
    pkill -9 -f "VLLM::EngineCore" 2>/dev/null
    pkill -9 -f "multiprocessing.resource_tracker" 2>/dev/null
    LEFT=$(nvidia-smi --query-compute-apps=pid --format=csv,noheader -i 1)
    [ -n "$LEFT" ] && { for pid in $LEFT; do kill -9 "$pid" 2>/dev/null; done; }
    sleep 15
done
