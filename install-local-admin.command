#!/bin/bash

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

clear
echo "TV-WALL 本機管理後台安裝程式"
echo "================================"
echo

/bin/bash "$SCRIPT_DIR/install-local-admin.sh"
STATUS=$?

echo
if (( STATUS == 0 )); then
    echo "安裝流程已完成。"
else
    echo "安裝未完成，錯誤代碼：$STATUS"
fi
read -r -p "按 Enter 關閉視窗…"
exit "$STATUS"
