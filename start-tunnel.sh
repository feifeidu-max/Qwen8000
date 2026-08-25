#!/bin/bash
# 建立 WSL -> rtx8000 的 SSH 隧道，把远程 vLLM (127.0.0.1:8000) 映射到本地 8000
# 幂等：已在运行则直接退出
PORT=8000
PIDFILE="$HOME/RTX8000/tunnel.pid"
LOG="$HOME/RTX8000/logs/tunnel.log"

if ss -tln 2>/dev/null | grep -q ":${PORT} "; then
    echo "TUNNEL_ALREADY_UP (port ${PORT} listening)"
    exit 0
fi
if [ -f "$PIDFILE" ] && kill -0 "$(cat "$PIDFILE")" 2>/dev/null; then
    echo "STALE_PIDFILE but port free, restarting"
    rm -f "$PIDFILE"
fi

mkdir -p "$HOME/RTX8000/logs"
setsid nohup ssh -N -o BatchMode=yes \
    -o ServerAliveInterval=30 -o ServerAliveCountMax=6 \
    -o ExitOnForwardFailure=yes \
    -L ${PORT}:127.0.0.1:${PORT} rtx8000 >> "$LOG" 2>&1 &
echo $! > "$PIDFILE"
for i in $(seq 1 10); do
    sleep 2
    if ss -tln 2>/dev/null | grep -q ":${PORT} "; then
        echo "TUNNEL_UP pid=$(cat "$PIDFILE")"
        exit 0
    fi
done
echo "TUNNEL_FAILED — 查看 $LOG"; tail -5 "$LOG"; exit 1
