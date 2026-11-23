#!/bin/bash

# 要開啟的網址：可直接修改這一行，或用第一個參數覆寫
URL="${1:-https://www.canva.com/design/DAHOJXEvb9o/x3tAF2xvq3cvdreokETpfA/watch?utm_content=DAHOJXEvb9o&utm_campaign=designshare&utm_medium=link2&utm_source=uniquelinks&utlId=he38cf48331}"
DEFAULT_REFRESH_SECONDS="${2:-200}"
POST_PLAY_DELAY_SECONDS=5
CHROME_BINARY="/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"
KIOSK_PROFILE="${HOME}/Library/Application Support/Chrome Kiosk"
PLAYER_APP="${HOME}/Applications/Chrome Kiosk Player.app"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
DURATION_HELPER="$SCRIPT_DIR/detect-canva-duration.rb"

if ! [[ "$DEFAULT_REFRESH_SECONDS" =~ ^[0-9]+$ ]] || (( DEFAULT_REFRESH_SECONDS < 15 )); then
    echo "DEFAULT_REFRESH_SECONDS 必須是至少 15 的整數。" >&2
    exit 2
fi

# 關閉同一 kiosk 設定檔的殘留程序，避免 Chrome 恢復到先前的編輯分頁。
pkill -f -- "--user-data-dir=$KIOSK_PROFILE" 2>/dev/null || true
sleep 2

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
    --remote-debugging-port=9222 \
    "$URL" >>/tmp/chrome-kiosk-chrome.log 2>&1 &
CHROME_PID=$!

# 結束腳本時，同步關閉這次啟動的 kiosk Chrome，避免背景程序繼續輸出。
cleanup() {
    trap - INT TERM EXIT
    if kill -0 "$CHROME_PID" 2>/dev/null; then
        kill "$CHROME_PID"
        wait "$CHROME_PID" 2>/dev/null
    fi
}
trap cleanup INT TERM EXIT

start_playback() {
    # Player App 會等待頁面載入 5 秒，再送出播放鍵。
    # -W 會等到 App 送出播放鍵並退出，之後才開始計算播放時間。
    open -W -gja "$PLAYER_APP"
}

ensure_chrome_alive() {
    # Chrome 崩潰或被關閉時直接結束腳本，交給 launchd（KeepAlive）重新啟動整套流程。
    if ! kill -0 "$CHROME_PID" 2>/dev/null; then
        echo "kiosk Chrome 已結束，退出讓 launchd 重新啟動。" >&2
        exit 1
    fi
}

while true; do
    # 先讓 Canva 建立播放器，再讀取媒體長度；仍會在播放前完成偵測。
    sleep 10
    ensure_chrome_alive

    if DETECTED_DURATION="$(/usr/bin/ruby "$DURATION_HELPER" 30)"; then
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
    sleep "$SLEEP_SECONDS"
    ensure_chrome_alive
    osascript -e 'tell application "Google Chrome" to reload active tab of front window'
done
