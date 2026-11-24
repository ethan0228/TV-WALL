#!/bin/bash
#
# 安裝 Chrome kiosk 到指定的 macOS 使用者帳號（預設 user）。
# 用法：sudo ./install-for-user.sh [目標使用者]

set -euo pipefail

TARGET_USER="${1:-user}"
SOURCE_DIR="$(cd "$(dirname "$0")" && pwd)"

if [[ $EUID -ne 0 ]]; then
    echo "請使用 sudo 執行此安裝程式。" >&2
    exit 1
fi

# 用系統的使用者查詢（和 id 指令相同），涵蓋本機、網路／AD、受管理帳號與別名。
# 不用 `dscl .`：它只查本機目錄節點，非本機帳號會出現 eDSRecordNotFound (-14136)。
# 同時把輸入的名稱換成正式的短名稱，後續 install/chown 一律用它。
if ! USER_INFO="$(/usr/bin/ruby -retc -e '
    pw = Etc.getpwnam(ARGV[0])
    group = (Etc.getgrgid(pw.gid).name rescue pw.gid)
    print pw.name, "\n", pw.uid, "\n", group, "\n", pw.dir
' "$TARGET_USER" 2>/dev/null)"; then
    echo "找不到使用者：${TARGET_USER}（請用帳號的短名稱，可在該帳號下執行 whoami 查看）" >&2
    exit 1
fi
{
    read -r TARGET_USER
    read -r TARGET_UID
    read -r TARGET_GROUP
    IFS= read -r TARGET_HOME
} <<<"$USER_INFO"

# 家目錄要由 macOS 在第一次登入時建立（含 Library 等預設內容）；
# 若由安裝程式先建立，macOS 就不會再補上預設內容，帳號會不完整。
if [[ ! -d "$TARGET_HOME/Library" ]]; then
    echo "$TARGET_USER 的家目錄尚未建立（${TARGET_HOME}）。請先用這個帳號登入一次，再執行安裝。" >&2
    exit 1
fi
TARGET_SUPPORT="$TARGET_HOME/Library/Application Support/Chrome Kiosk"
TARGET_AGENTS="$TARGET_HOME/Library/LaunchAgents"
TARGET_APPS="$TARGET_HOME/Applications"
TARGET_PLIST="$TARGET_AGENTS/com.example.chrome-kiosk.plist"
TARGET_PLAYER_APP="$TARGET_APPS/Chrome Kiosk Player.app"
TARGET_LOGS="$TARGET_HOME/Library/Logs/Chrome Kiosk"

install -d -o "$TARGET_USER" -g "$TARGET_GROUP" "$TARGET_SUPPORT" "$TARGET_AGENTS" "$TARGET_APPS" "$TARGET_LOGS"
install -o "$TARGET_USER" -g "$TARGET_GROUP" -m 755 "$SOURCE_DIR/chrome-kiosk.sh" "$TARGET_SUPPORT/chrome-kiosk.sh"
install -o "$TARGET_USER" -g "$TARGET_GROUP" -m 755 "$SOURCE_DIR/kiosk-cdp.rb" "$TARGET_SUPPORT/kiosk-cdp.rb"
# 舊版的偵測腳本已改名為 kiosk-cdp.rb。
rm -f "$TARGET_SUPPORT/detect-canva-duration.rb"

# plist 不能用 ~，安裝時把範本裡的 __TARGET_HOME__ 換成目標使用者的家目錄。
# 先做 XML 跳脫（plist 是 XML），再跳脫 sed 替換字串中有特殊意義的 \、# 和 &。
ESCAPED_HOME="$(printf '%s' "$TARGET_HOME" | sed -e 's/&/\&amp;/g' -e 's/</\&lt;/g' -e 's/>/\&gt;/g' -e 's/[\\#&]/\\&/g')"
sed "s#__TARGET_HOME__#$ESCAPED_HOME#g" "$SOURCE_DIR/com.example.chrome-kiosk.plist" >"$TARGET_PLIST"
chown "$TARGET_USER:$TARGET_GROUP" "$TARGET_PLIST"
chmod 644 "$TARGET_PLIST"
plutil -lint "$TARGET_PLIST" >/dev/null

# 從 repo 裡的 AppleScript 原始碼編譯 Player App。
# 注意：重新編譯後 App 的簽章會改變，必須重新授權（見安裝完成後的提示）。
rm -rf "$TARGET_PLAYER_APP"
# osacompile 每次都會印出「replacing existing signature」（重新做 ad-hoc 簽章），屬正常訊息，過濾掉；
# 真的編譯失敗時才把完整輸出印出來。
if ! COMPILE_OUTPUT="$(osacompile -o "$TARGET_PLAYER_APP" "$SOURCE_DIR/Chrome Kiosk Player.applescript" 2>&1)"; then
    echo "$COMPILE_OUTPUT" >&2
    echo "編譯 Chrome Kiosk Player.app 失敗。" >&2
    exit 1
fi
grep -v 'replacing existing signature' <<<"$COMPILE_OUTPUT" >&2 || true
chown -R "$TARGET_USER:$TARGET_GROUP" "$TARGET_PLAYER_APP"

LABEL="com.example.chrome-kiosk"
SERVICE="gui/$TARGET_UID/$LABEL"

# 清掉先前 `launchctl disable` 留下的停用紀錄。服務被停用時，bootstrap 只會回報
# 「Bootstrap failed: 5: Input/output error」，登入時也不會自動啟動。
launchctl enable "$SERVICE" 2>/dev/null || true

# 如果使用者已有 GUI 登入工作階段，立即載入；否則會在下次登入時由 macOS 自動載入。
if launchctl print "gui/$TARGET_UID" >/dev/null 2>&1; then
    if launchctl print "$SERVICE" >/dev/null 2>&1; then
        launchctl bootout "$SERVICE" 2>/dev/null || true
        # bootout 不會等舊程序完全結束；舊的還在時立刻 bootstrap 同樣會得到錯誤 5，所以最多等 15 秒。
        for _ in $(seq 1 30); do
            launchctl print "$SERVICE" >/dev/null 2>&1 || break
            sleep 0.5
        done
    fi
    if ! launchctl bootstrap "gui/$TARGET_UID" "$TARGET_PLIST"; then
        echo "載入 LaunchAgent 失敗。檔案已安裝完成，可先查看：" >&2
        echo "  launchctl print-disabled gui/$TARGET_UID | grep $LABEL   # 是否被停用" >&2
        echo "  launchctl print $SERVICE                                  # 是否仍在載入中" >&2
        echo "  plutil -lint \"$TARGET_PLIST\"" >&2
        echo "或登出再登入 ${TARGET_USER}，讓 macOS 自動載入。" >&2
        exit 1
    fi
fi

# 「控制電腦」權限清單的名稱：macOS 27 起叫「裝置控制和資料取用」，之前叫「輔助使用」。
if (( $(sw_vers -productVersion | cut -d. -f1) >= 27 )); then
    DEVICE_CONTROL_PANE="裝置控制和資料取用"
else
    DEVICE_CONTROL_PANE="輔助使用"
fi

echo "安裝完成：$TARGET_USER 登入後會自動啟動 Chrome kiosk。"
echo "接下來請以 $TARGET_USER 登入，並在該帳號的畫面上完成："
echo "  1. 「系統設定 → 隱私權與安全性 → ${DEVICE_CONTROL_PANE}」加入並打開 ${TARGET_PLAYER_APP}"
echo "     （重新安裝後，清單上的舊項目已失效，請先用「－」移除再重新加入）"
echo "  2. 第一次播放時，跳出「想要有控制『System Events』的權限」請按「允許」"
echo "     （若按了不允許：「系統設定 → 隱私權與安全性 → 自動化」打開 Chrome Kiosk Player 底下的項目）"
echo "  3. 建議設定自動登入、閒置時關閉顯示器設為「永不」等，詳見 README.md 的「系統設定」"
echo "記錄檔位置：$TARGET_LOGS"
echo "要移除時執行：sudo ./uninstall-for-user.sh $TARGET_USER"
