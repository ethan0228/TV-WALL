#!/bin/bash

# 要開啟的網址：可直接修改這一行，或用第一個參數覆寫
URL="${1:-https://www.canva.com/design/DAHOJXEvb9o/x3tAF2xvq3cvdreokETpfA/watch?utm_content=DAHOJXEvb9o&utm_campaign=designshare&utm_medium=link2&utm_source=uniquelinks&utlId=he38cf48331}"
DEFAULT_REFRESH_SECONDS="${2:-200}"
CONTROL_URL="${3:-}"
DEVICE_API_KEY="${4:-}"
POST_PLAY_DELAY_SECONDS=5
APP_VERSION="1.2.0"
CHROME_BINARY="/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"
KIOSK_PROFILE="${HOME}/Library/Application Support/Chrome Kiosk"
PLAYER_APP="${HOME}/Applications/Chrome Kiosk Player.app"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
DURATION_HELPER="$SCRIPT_DIR/detect-canva-duration.rb"

if ! [[ "$DEFAULT_REFRESH_SECONDS" =~ ^[0-9]+$ ]] || (( DEFAULT_REFRESH_SECONDS < 15 )); then
    echo "DEFAULT_REFRESH_SECONDS 必須是至少 15 的整數。" >&2
    exit 2
fi
if [[ -n "$CONTROL_URL" || -n "$DEVICE_API_KEY" ]]; then
    if [[ -z "$CONTROL_URL" || -z "$DEVICE_API_KEY" || ! "$CONTROL_URL" =~ ^https?:// ]]; then
        echo "管理後台網址與裝置 API 金鑰必須一起提供，且網址必須使用 http:// 或 https://。" >&2
        exit 2
    fi
fi

CONTROL_URL="${CONTROL_URL%/}"
REMOTE_ENABLED=1
CONFIG_CHANGED=0
OS_VERSION="$(/usr/bin/sw_vers -productName) $(/usr/bin/sw_vers -productVersion)"
STARTED_AT="$(date +%s)"

navigate_to() {
    local target_url="$1"
    /usr/bin/osascript - "$target_url" <<'APPLESCRIPT'
on run argv
    tell application "Google Chrome"
        if (count of windows) > 0 then
            set URL of active tab of front window to item 1 of argv
        end if
    end tell
end run
APPLESCRIPT
}

sync_control() {
    local status="${1:-playing}"
    local error_message="${2:-}"
    local response parsed enabled encoded_url new_url new_fallback uptime

    CONFIG_CHANGED=0
    [[ -n "$CONTROL_URL" && -n "$DEVICE_API_KEY" ]] || return 0
    uptime=$(( $(date +%s) - STARTED_AT ))

    response="$(/usr/bin/curl -fsS --max-time 10 \
        -H "Authorization: Bearer $DEVICE_API_KEY" \
        --data-urlencode "status=$status" \
        --data-urlencode "current_url=$URL" \
        --data-urlencode "app_version=$APP_VERSION" \
        --data-urlencode "os_version=$OS_VERSION" \
        --data-urlencode "uptime_seconds=$uptime" \
        --data-urlencode "error_message=$error_message" \
        "$CONTROL_URL/api/agent/heartbeat" 2>/dev/null)" || return 0

    parsed="$(printf '%s' "$response" | /usr/bin/ruby -rjson -rbase64 -e '
      body = JSON.parse(STDIN.read)
      config = body.fetch("configuration")
      puts(config["enabled"] ? "1" : "0")
      puts(Base64.strict_encode64(config.fetch("playbackUrl").to_s))
      puts(config.fetch("fallbackSeconds").to_i)
    ' 2>/dev/null)" || return 0

    enabled="$(printf '%s\n' "$parsed" | /usr/bin/sed -n '1p')"
    encoded_url="$(printf '%s\n' "$parsed" | /usr/bin/sed -n '2p')"
    new_fallback="$(printf '%s\n' "$parsed" | /usr/bin/sed -n '3p')"
    new_url="$(printf '%s' "$encoded_url" | /usr/bin/base64 -D 2>/dev/null)" || return 0

    REMOTE_ENABLED="$enabled"
    if [[ -n "$new_url" && "$new_url" != "$URL" ]]; then
        URL="$new_url"
        CONFIG_CHANGED=1
    fi
    if [[ "$new_fallback" =~ ^[0-9]+$ ]] && (( new_fallback >= 15 )); then
        DEFAULT_REFRESH_SECONDS="$new_fallback"
    fi
}

wait_with_control() {
    local remaining="$1"
    local step
    while (( remaining > 0 )); do
        if (( remaining > 30 )); then step=30; else step="$remaining"; fi
        sleep "$step"
        remaining=$((remaining - step))
        sync_control "playing"
        [[ "$REMOTE_ENABLED" == "1" ]] || return 2
        (( CONFIG_CHANGED == 0 )) || return 3
    done
}

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
    sync_control "offline" || true
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

while true; do
    sync_control "loading"
    if [[ "$REMOTE_ENABLED" != "1" ]]; then
        navigate_to "about:blank" || true
        echo "此節點已由管理後台停用，等待重新啟用。"
        while [[ "$REMOTE_ENABLED" != "1" ]]; do
            sleep 30
            sync_control "disabled"
        done
        navigate_to "$URL" || true
        sleep 10
    elif (( CONFIG_CHANGED == 1 )); then
        navigate_to "$URL" || true
        sleep 10
    fi

    # 先讓 Canva 建立播放器，再讀取媒體長度；仍會在播放前完成偵測。
    sleep 10

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
    WAIT_RESULT=0
    wait_with_control "$SLEEP_SECONDS" || WAIT_RESULT=$?
    if (( WAIT_RESULT == 2 )); then
        continue
    elif (( WAIT_RESULT == 3 )); then
        navigate_to "$URL" || true
        continue
    fi
    osascript -e 'tell application "Google Chrome" to reload active tab of front window'
done
