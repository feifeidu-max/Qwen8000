#!/bin/bash
# 同步本仓库到 GitHub: ./sync_github.sh "修改说明"
cd "$HOME/RTX8000" || exit 1
MSG=${1:-"update: $(date '+%Y-%m-%d %H:%M') 配置同步"}
git add -A
if git diff --cached --quiet; then
    echo "没有需要同步的修改"
    exit 0
fi
git commit -m "$MSG" || exit 1
git push origin main && echo "✅ 已推送到 github.com/feifeidu-max/Qwen8000"
