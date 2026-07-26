#!/bin/bash

set -euo pipefail

LABEL="com.tvwall.admin"
SUPPORT_ROOT="${TVWALL_ADMIN_HOME:-$HOME/Library/Application Support/TV-WALL Admin}"
LAUNCH_AGENT="$HOME/Library/LaunchAgents/$LABEL.plist"
PURGE=0

if [[ "${1:-}" == "--purge" ]]; then
    PURGE=1
elif (( $# > 0 )); then
    echo "用法：./uninstall-local-admin.sh [--purge]" >&2
    exit 2
fi
if [[ $EUID -eq 0 ]]; then
    echo "請用安裝本機後台的一般使用者執行，不要使用 sudo。" >&2
    exit 2
fi

/bin/launchctl bootout "gui/$(id -u)" "$LAUNCH_AGENT" >/dev/null 2>&1 || true
/bin/rm -f "$LAUNCH_AGENT"

if (( PURGE == 1 )); then
    /bin/rm -rf "$SUPPORT_ROOT"
    echo "已完整移除 TV-WALL 本機管理後台、設定、金鑰、記錄與資料庫。"
    echo "此操作無法從程式內復原；若有 Time Machine 備份仍可由備份還原。"
else
    /bin/rm -rf "$SUPPORT_ROOT/app"
    echo "已移除 TV-WALL 本機管理程式，資料與設定仍保留在："
    echo "$SUPPORT_ROOT"
    echo "重新執行 install-local-admin.sh 即可沿用原資料。"
fi
