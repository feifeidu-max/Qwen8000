#!/bin/bash
# Qwen3.8-27B 双卡 TP=2 + MTP3 守护进程（含启动竞态自动重试）
FLAG=/mnt/sdc/work/.qwen38_manual_stop
echo "[supervisor-tp2] started at $(date)"
while true; do
    rm -f "$FLAG"
    echo "[supervisor-tp2] launching at $(date)"
    bash /mnt/sdc/work/restart_qwen38_awq_tp2.sh
    if ! ss -tln 2>/dev/null | grep -q ":8000 "; then
        echo "[supervisor-tp2] startup failed/hung, cleaning and retrying in 30s"
        pkill -9 -f "vllm.entrypoints.openai.api_server" 2>/dev/null
        pkill -9 -f "VLLM:" 2>/dev/null
        pkill -9 -f "multiprocessing.resource_tracker" 2>/dev/null
        LEFT=$(nvidia-smi --query-compute-apps=pid --format=csv,noheader)
        [ -n "$LEFT" ] && { for pid in $LEFT; do kill -9 "$pid" 2>/dev/null; done; }
        sleep 30
        continue
    fi
    echo "[supervisor-tp2] model UP, watching"
    while ss -tln 2>/dev/null | grep -q ":8000 "; do
        sleep 15
    done
    if [ -f "$FLAG" ]; then
        echo "[supervisor-tp2] MANUAL STOP -> exiting at $(date)"
        exit 0
    fi
    echo "[supervisor-tp2] CRASH detected at $(date), restarting in 15s"
    pkill -9 -f "vllm.entrypoints.openai.api_server" 2>/dev/null
    pkill -9 -f "VLLM:" 2>/dev/null
    sleep 15
done
