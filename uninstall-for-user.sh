#!/bin/bash
#
# 從指定的 macOS 使用者帳號移除 Chrome kiosk（install-for-user.sh 的反向操作）。
# 用法：sudo ./uninstall-for-user.sh [-n|--dry-run] [--keep-logs] [目標使用者]
#
#   -n, --dry-run   只列出會停止與刪除的項目，不實際執行（預覽其他帳號時仍建議加 sudo，才看得到對方的檔案）
#   --keep-logs     保留 ~/Library/Logs/Chrome Kiosk/ 記錄檔

set -euo pipefail

DRY_RUN=0
KEEP_LOGS=0
TARGET_USER=""

while (( $# > 0 )); do
    case "$1" in
        -n|--dry-run) DRY_RUN=1 ;;
        --keep-logs) KEEP_LOGS=1 ;;
        -h|--help)
            sed -n '3,7p' "$0" | sed 's/^# \{0,1\}//'
            exit 0
            ;;
        -*)
            echo "不明的選項：$1" >&2
            exit 2
            ;;
        *)
            if [[ -n "$TARGET_USER" ]]; then
                echo "只能指定一個使用者。" >&2
                exit 2
            fi
            TARGET_USER="$1"
            ;;
    esac
    shift
done
TARGET_USER="${TARGET_USER:-user}"

if (( DRY_RUN == 0 )) && [[ $EUID -ne 0 ]]; then
    echo "請使用 sudo 執行此移除程式（或加上 --dry-run 先預覽）。" >&2
    exit 1
fi

# 和 install-for-user.sh 相同：用系統的使用者查詢（涵蓋本機、網路／AD 帳號與別名），不用 `dscl .`。
if ! USER_INFO="$(/usr/bin/ruby -retc -e '
    pw = Etc.getpwnam(ARGV[0])
    print pw.name, "\n", pw.uid, "\n", pw.dir
' "$TARGET_USER" 2>/dev/null)"; then
    echo "找不到使用者：${TARGET_USER}（請用帳號的短名稱，可在該帳號下執行 whoami 查看）" >&2
    exit 1
fi
{
    read -r TARGET_USER
    read -r TARGET_UID
    IFS= read -r TARGET_HOME
} <<<"$USER_INFO"

LABEL="com.example.chrome-kiosk"
TARGET_SUPPORT="$TARGET_HOME/Library/Application Support/Chrome Kiosk"
TARGET_PLIST="$TARGET_HOME/Library/LaunchAgents/$LABEL.plist"
TARGET_PLAYER_APP="$TARGET_HOME/Applications/Chrome Kiosk Player.app"
TARGET_LOGS="$TARGET_HOME/Library/Logs/Chrome Kiosk"

# 執行或（dry-run 時）只印出指令。
run() {
    if (( DRY_RUN )); then
        printf '  [預覽] %s\n' "$*"
    else
        "$@"
    fi
}

echo "目標帳號：${TARGET_USER}（UID ${TARGET_UID}，家目錄 ${TARGET_HOME}）"
(( DRY_RUN )) && echo "預覽模式：不會實際停止或刪除任何東西。"

# 1. 停止並卸載 LaunchAgent。腳本收到 SIGTERM 時會一併關閉 kiosk Chrome。
echo "停止服務 $LABEL …"
if launchctl print "gui/$TARGET_UID/$LABEL" >/dev/null 2>&1; then
    run launchctl bootout "gui/$TARGET_UID/$LABEL" || true
else
    echo "  服務目前沒有載入。"
fi
# 移除先前用 `launchctl disable` 留下的停用紀錄，日後重新安裝時才會正常啟動。
run launchctl enable "gui/$TARGET_UID/$LABEL" 2>/dev/null || true

# 2. 保險起見，關閉這個帳號殘留的 kiosk Chrome（只比對 kiosk 專用設定檔，不影響一般 Chrome）。
if pgrep -u "$TARGET_UID" -f -- "--user-data-dir=$TARGET_SUPPORT" >/dev/null 2>&1; then
    echo "關閉殘留的 kiosk Chrome …"
    run pkill -u "$TARGET_UID" -f -- "--user-data-dir=$TARGET_SUPPORT" || true
fi

# 3. 刪除安裝的檔案。
remove() {
    if [[ -e "$1" ]]; then
        echo "刪除 $1"
        run rm -rf -- "$1"
    fi
}
remove "$TARGET_PLIST"
remove "$TARGET_SUPPORT"
remove "$TARGET_PLAYER_APP"
if (( KEEP_LOGS )); then
    [[ -e "$TARGET_LOGS" ]] && echo "保留記錄檔：$TARGET_LOGS"
else
    remove "$TARGET_LOGS"
fi

# 舊版把記錄檔寫在 /tmp；只刪除屬於這個帳號的檔案，不動其他帳號的。
if (( ! KEEP_LOGS )); then
    for f in /tmp/chrome-kiosk.log /tmp/chrome-kiosk-error.log /tmp/chrome-kiosk-chrome.log; do
        if [[ -f "$f" && "$(stat -f %u "$f")" == "$TARGET_UID" ]]; then
            remove "$f"
        fi
    done
fi

echo
if (( DRY_RUN )); then
    echo "預覽結束。確認無誤後，去掉 --dry-run 並以 sudo 執行。"
else
    echo "移除完成。"
    # 編譯出的 Player App 沒有 bundle ID，tccutil 無法只針對它重設，只能手動移除。
    echo "最後請到「系統設定 → 隱私權與安全性 → 輔助使用」，把 Chrome Kiosk Player 從清單移除。"
fi
