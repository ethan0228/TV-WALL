#!/bin/bash

# 要開啟的網址：可直接修改這一行，或用第一個參數覆寫
URL="${1:-https://www.canva.com/design/DAHOJXEvb9o/x3tAF2xvq3cvdreokETpfA/watch?utm_content=DAHOJXEvb9o&utm_campaign=designshare&utm_medium=link2&utm_source=uniquelinks&utlId=he38cf48331}"
DEFAULT_REFRESH_SECONDS="${2:-200}"
POST_PLAY_DELAY_SECONDS=5
CHROME_BINARY="/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"
INSTALL_DIR="${HOME}/Library/Application Support/Chrome Kiosk"
# Chrome 設定檔放在子資料夾，不和腳本混在一起。
KIOSK_PROFILE="${INSTALL_DIR}/profile"
PLAYER_APP="${HOME}/Applications/Chrome Kiosk Player.app"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
CDP_HELPER="$SCRIPT_DIR/kiosk-cdp.rb"
# 記錄檔放在各使用者自己的 ~/Library/Logs，避免多個帳號搶同一個 /tmp 檔案。
LOG_DIR="${HOME}/Library/Logs/Chrome Kiosk"
# 遠端除錯埠依 UID 區分（例如 UID 501 → 9723），多個帳號同時登入時不會互相操作到對方的 Chrome。
export KIOSK_CDP_PORT="${KIOSK_CDP_PORT:-$((9222 + $(id -u) % 1000))}"

if ! [[ "$DEFAULT_REFRESH_SECONDS" =~ ^[0-9]+$ ]] || (( DEFAULT_REFRESH_SECONDS < 15 )); then
    echo "DEFAULT_REFRESH_SECONDS 必須是至少 15 的整數。" >&2
    exit 2
fi

cdp() {
    /usr/bin/ruby "$CDP_HELPER" "$@"
}

# 關閉 kiosk 設定檔的殘留程序，避免 Chrome 恢復到先前的編輯分頁。
# 比對安裝目錄前綴，舊版（設定檔直接放在安裝目錄）留下的程序也會一併關閉。
pkill -f -- "--user-data-dir=$INSTALL_DIR" 2>/dev/null || true
sleep 2
mkdir -p "$LOG_DIR"

# 除錯埠若被別的程式（例如其他帳號的 Chrome）佔用，kiosk-cdp.rb 會操作到錯的瀏覽器，因此直接停止。
if /usr/bin/nc -z 127.0.0.1 "$KIOSK_CDP_PORT" 2>/dev/null; then
    echo "連接埠 $KIOSK_CDP_PORT 已被其他程式使用，請設定 KIOSK_CDP_PORT 換一個埠。" >&2
    exit 1
fi

# 使用獨立設定檔啟動真正的 kiosk 模式，隱藏網址列、分頁列和工具列。
# autoplay-policy 允許 Canva 簡報中的影音與動畫不需手動點擊即可播放。
"$CHROME_BINARY" \
    --user-data-dir="$KIOSK_PROFILE" \
    --kiosk \
    --no-first-run \
    --incognito \
    --disable-session-crashed-bubble \
    --autoplay-policy=no-user-gesture-required \
    --remote-debugging-address=127.0.0.1 \
    --remote-debugging-port="$KIOSK_CDP_PORT" \
    "$URL" >>"$LOG_DIR/chrome.log" 2>&1 &
CHROME_PID=$!
SLEEP_PID=""

# 結束腳本時，同步關閉這次啟動的 kiosk Chrome，避免背景程序繼續輸出。
cleanup() {
    trap - EXIT
    [[ -n "$SLEEP_PID" ]] && kill "$SLEEP_PID" 2>/dev/null
    if kill -0 "$CHROME_PID" 2>/dev/null; then
        kill "$CHROME_PID"
        wait "$CHROME_PID" 2>/dev/null
    fi
}
trap cleanup EXIT
# 收到訊號就真的結束（EXIT trap 會負責清理），不要清理完又回到迴圈。
trap 'exit 130' INT
trap 'exit 143' TERM

# 可被訊號立即中斷的 sleep：launchd 停止服務時不必等整段播放時間結束。
interruptible_sleep() {
    sleep "$1" &
    SLEEP_PID=$!
    wait "$SLEEP_PID"
    SLEEP_PID=""
}

ensure_chrome_alive() {
    # Chrome 崩潰或被關閉時直接結束腳本，交給 launchd（KeepAlive）重新啟動整套流程。
    if ! kill -0 "$CHROME_PID" 2>/dev/null; then
        echo "kiosk Chrome 已結束，退出讓 launchd 重新啟動。" >&2
        exit 1
    fi
}

start_playback() {
    # Player App 會等待頁面載入 5 秒、確認全螢幕，再送出播放鍵。
    # -W 會等到 App 送出播放鍵並退出，之後才開始計算播放時間。
    open -W -gja "$PLAYER_APP"

    # 空白鍵是「播放／暫停」切換：若 Canva 本來就在自動播放，剛才那一下反而會暫停。
    # 確定是暫停狀態才再按一次；無法判斷（unknown）時不動作，避免把播放中的簡報暫停。
    local state
    state="$(cdp state)" || state="unknown"
    echo "播放狀態：$state"
    if [[ "$state" == "paused" ]]; then
        echo "簡報處於暫停狀態，再送一次播放鍵。"
        cdp press-space || echo "送出播放鍵失敗。" >&2
    fi
}

while true; do
    # 先讓 Canva 建立播放器，再讀取媒體長度；仍會在播放前完成偵測。
    interruptible_sleep 10
    ensure_chrome_alive

    if DETECTED_DURATION="$(cdp duration 30)"; then
        echo "偵測到簡報長度：${DETECTED_DURATION} 秒"
    else
        DETECTED_DURATION=""
        echo "無法偵測簡報長度，使用預設時間：${DEFAULT_REFRESH_SECONDS} 秒"
    fi

    start_playback

    if [[ -n "$DETECTED_DURATION" ]]; then
        SLEEP_SECONDS=$((DETECTED_DURATION + POST_PLAY_DELAY_SECONDS))
    else
        SLEEP_SECONDS="$DEFAULT_REFRESH_SECONDS"
    fi

    echo "${SLEEP_SECONDS} 秒後重新載入並重新偵測。"
    interruptible_sleep "$SLEEP_SECONDS"
    ensure_chrome_alive

    # 透過 CDP 重新載入 kiosk 的 Canva 分頁；失敗時才退回 AppleScript。
    if ! cdp reload; then
        echo "CDP 重新載入失敗，改用 AppleScript。" >&2
        osascript -e 'tell application "Google Chrome" to reload active tab of front window'
    fi
done
