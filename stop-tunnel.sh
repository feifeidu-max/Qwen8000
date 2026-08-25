#!/bin/bash
# 关闭到 rtx8000 的 SSH 隧道
PIDFILE="$HOME/RTX8000/tunnel.pid"
if [ -f "$PIDFILE" ]; then
    PID=$(cat "$PIDFILE")
    pkill -TERM -g "$PID" 2>/dev/null || kill "$PID" 2>/dev/null
    rm -f "$PIDFILE"
fi
# 兜底：按命令特征清理
pkill -f "ssh -N .*-L 8000:127.0.0.1:8000 rtx8000" 2>/dev/null
sleep 1
if ss -tln 2>/dev/null | grep -q ":8000 "; then
    echo "STILL_LISTENING — 请手动检查: ss -tln | grep 8000"
    exit 1
fi
echo "TUNNEL_STOPPED"
