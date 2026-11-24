#!/bin/bash

CANVA_DESIGN_RE='^https://(www\.)?canva\.com/design/'
RESOLVE_ATTEMPTS="${RESOLVE_ATTEMPTS:-12}"   # 展開短網址失敗時的重試次數（每次間隔 5 秒）

# 把 Canva 網址整理成 kiosk 要用的形式：
#   1. 展開短網址（公開檢視連結複製到的是 canva.link/…，部分地區網域不同），一路跟著轉址直到 canva.com/design/
#   2. 把 /view（要自己翻頁）改成 /watch（像影片一樣自動播放，播放器上有時間可偵測長度）
# 成功時輸出整理後的網址；網路不通、短網址打錯或連結已刪除時回傳 1。
resolve_canva_url() {
    local url="$1" next
    local hop
    for hop in 1 2 3 4 5; do
        [[ "$url" =~ $CANVA_DESIGN_RE ]] && break
        next="$(curl -s -o /dev/null --max-time 10 -w '%{redirect_url}' -- "$url")" || return 1
        [[ -n "$next" ]] || return 1
        url="$next"
    done
    [[ "$url" =~ $CANVA_DESIGN_RE ]] || return 1
    printf '%s\n' "$url" | sed -E 's~^(https://(www\.)?canva\.com/design/[^/?#]+/[^/?#]+)/view([?#]|$)~\1/watch\3~'
}

# 供安裝程式檢查網址用：只輸出整理後的網址，不啟動 kiosk。
if [[ "${1:-}" == "--resolve-only" ]]; then
    resolve_canva_url "${2:-}"
    exit
fi

# 記錄訊息時加上時間，方便對照 Chrome 何時結束、何時重新啟動。
log() { printf '%s %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*"; }
err() { log "$@" >&2; }

# 要開啟的網址：可直接修改這一行，或用第一個參數覆寫。
# 可以是 Canva 的短網址（canva.link/…）或完整網址，/view 會自動改成 /watch。
URL="${1:-https://www.canva.com/design/DAHOJXEvb9o/x3tAF2xvq3cvdreokETpfA/watch?utm_content=DAHOJXEvb9o&utm_campaign=designshare&utm_medium=link2&utm_source=uniquelinks&utlId=he38cf48331}"
DEFAULT_REFRESH_SECONDS="${2:-200}"
POST_PLAY_DELAY_SECONDS=5
CHROME_BINARY="${CHROME_BINARY:-/Applications/Google Chrome.app/Contents/MacOS/Google Chrome}"
INSTALL_DIR="${HOME}/Library/Application Support/Chrome Kiosk"
# Chrome 設定檔放在子資料夾，不和腳本混在一起。
KIOSK_PROFILE="${INSTALL_DIR}/profile"
PLAYER_APP="${HOME}/Applications/Chrome Kiosk Player.app"
PLAYER_TIMEOUT_SECONDS="${PLAYER_TIMEOUT_SECONDS:-30}"   # Player App 正常約 10 秒結束；超過就強制關閉
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
CDP_HELPER="$SCRIPT_DIR/kiosk-cdp.rb"
# 記錄檔放在各使用者自己的 ~/Library/Logs，避免多個帳號搶同一個 /tmp 檔案。
LOG_DIR="${HOME}/Library/Logs/Chrome Kiosk"
# 遠端除錯埠依 UID 區分（例如 UID 501 → 9723），多個帳號同時登入時不會互相操作到對方的 Chrome。
export KIOSK_CDP_PORT="${KIOSK_CDP_PORT:-$((9222 + $(id -u) % 1000))}"

if ! [[ "$DEFAULT_REFRESH_SECONDS" =~ ^[0-9]+$ ]] || (( DEFAULT_REFRESH_SECONDS < 15 )); then
    err "DEFAULT_REFRESH_SECONDS 必須是至少 15 的整數。"
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
    err "連接埠 $KIOSK_CDP_PORT 已被其他程式使用，請設定 KIOSK_CDP_PORT 換一個埠。"
    exit 1
fi

# 展開短網址並改成 /watch。開機時網路可能還沒好，所以失敗會重試（預設最多約 60 秒）。
PLAY_URL=""
for (( attempt = 1; attempt <= RESOLVE_ATTEMPTS; attempt++ )); do
    PLAY_URL="$(resolve_canva_url "$URL")" && break
    PLAY_URL=""
    (( attempt < RESOLVE_ATTEMPTS )) && sleep 5
done
if [[ -n "$PLAY_URL" ]]; then
    [[ "$PLAY_URL" != "$URL" ]] && log "播放網址：$PLAY_URL"
else
    err "無法展開播放網址（網路未連線、短網址打錯或連結已刪除），直接開啟原網址：$URL"
    PLAY_URL="$URL"
fi
case "$PLAY_URL" in
    */edit|*/edit\?*)
        err "警告：這是 Canva 的編輯連結，需要登入才能開啟。請改用「分享 → 公開檢視連結」。"
        ;;
esac

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
    "$PLAY_URL" >>"$LOG_DIR/chrome.log" 2>&1 &
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
        local code=0 how
        wait "$CHROME_PID" 2>/dev/null || code=$?
        if (( code > 128 )); then
            how="被訊號 $(kill -l $(( code - 128 )) 2>/dev/null || echo $(( code - 128 ))) 終止"
        else
            how="結束代碼 ${code}"
        fi
        err "kiosk Chrome 已結束（${how}），退出讓 launchd 重新啟動。"
        exit 1
    fi
}

# 等待期間每 5 秒確認一次 Chrome 還在。簡報可能長達十幾分鐘，
# 若只在等待結束後才檢查，Chrome 中途關閉時畫面會停在桌面很久才恢復。
watched_sleep() {
    local remaining="$1" chunk
    while (( remaining > 0 )); do
        chunk=$(( remaining < 5 ? remaining : 5 ))
        interruptible_sleep "$chunk"
        remaining=$(( remaining - chunk ))
        ensure_chrome_alive
    done
}

start_playback() {
    # Player App 會等待頁面載入 5 秒、把 Chrome 帶到最前面並確認全螢幕，再按空白鍵（需要「控制電腦」權限）。
    # 用 -W 等它結束，但最多等 PLAYER_TIMEOUT_SECONDS 秒：第一次執行時的權限提示（或任何對話框）
    # 會讓 App 停住不結束，不能讓整個播放循環跟著卡住。
    open -W -gja "$PLAYER_APP" &
    local open_pid=$! waited=0
    while kill -0 "$open_pid" 2>/dev/null && (( waited < PLAYER_TIMEOUT_SECONDS )); do
        sleep 1
        (( waited++ ))
    done
    if kill -0 "$open_pid" 2>/dev/null; then
        err "Player App 超過 ${PLAYER_TIMEOUT_SECONDS} 秒沒有結束（可能停在權限提示或錯誤對話框），已強制關閉。"
        pkill -f -- "$PLAYER_APP/Contents/MacOS/" 2>/dev/null || true
        kill "$open_pid" 2>/dev/null || true
    fi
    wait "$open_pid" 2>/dev/null || true

    # Canva 的 /watch 播放器不會自動播放，而 Player App 的空白鍵需要「控制電腦」權限和鍵盤焦點，不一定送得到。
    # 所以再透過 CDP 確認：沒在播就直接點播放器的「播放」鈕，並確認時間開始前進（以狀態為準，不會把播放中的簡報暫停）。
    local result state
    result="$(cdp play)" || result="failed"
    case "$result" in
        already-playing) log "播放狀態：已在播放" ;;
        started)         log "播放狀態：已點「播放」開始播放" ;;
        clicked)         log "播放狀態：已點「播放」（頁面上沒有時間可確認）" ;;
        *)
            # 找不到「播放」鈕或點了沒反應（診斷資訊已寫進 kiosk-error.log）。
            # 空白鍵是切換，只有確定是暫停時才按，避免把其實在播放的簡報按成暫停。
            err "播放狀態：無法用「播放」鈕開始（${result}）。"
            state="$(cdp state)" || state="unknown"
            if [[ "$state" == "paused" ]]; then
                err "播放狀態：確定是暫停，改送空白鍵。"
                cdp press-space || err "送出空白鍵失敗。"
                state="$(cdp state)" || state="unknown"
            fi
            log "播放狀態：$state"
            [[ "$state" == "playing" ]] || err "簡報仍未開始播放，請把 kiosk-error.log 的「播放診斷」那一行提供給維護人員。"
            ;;
    esac
}

while true; do
    # 先讓 Canva 建立播放器，再讀取媒體長度；仍會在播放前完成偵測。
    watched_sleep 10

    if DETECTED_DURATION="$(cdp duration 30)"; then
        log "偵測到簡報長度：${DETECTED_DURATION} 秒"
    else
        DETECTED_DURATION=""
        log "無法偵測簡報長度，使用預設時間：${DEFAULT_REFRESH_SECONDS} 秒"
    fi

    ensure_chrome_alive
    start_playback
    ensure_chrome_alive

    if [[ -n "$DETECTED_DURATION" ]]; then
        SLEEP_SECONDS=$((DETECTED_DURATION + POST_PLAY_DELAY_SECONDS))
    else
        SLEEP_SECONDS="$DEFAULT_REFRESH_SECONDS"
    fi

    log "${SLEEP_SECONDS} 秒後重新載入並重新偵測。"
    watched_sleep "$SLEEP_SECONDS"

    # 透過 CDP 重新載入 kiosk 的 Canva 分頁；失敗時才退回 AppleScript。
    if ! cdp reload; then
        err "CDP 重新載入失敗，改用 AppleScript。"
        osascript -e 'tell application "Google Chrome" to reload active tab of front window'
    fi
done
