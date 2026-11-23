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
# 注意：重新編譯後 App 的簽章會改變，macOS 可能需要重新在「輔助使用」允許它。
rm -rf "$TARGET_PLAYER_APP"
osacompile -o "$TARGET_PLAYER_APP" "$SOURCE_DIR/Chrome Kiosk Player.applescript"
chown -R "$TARGET_USER:$TARGET_GROUP" "$TARGET_PLAYER_APP"

# 如果使用者已有 GUI 登入工作階段，立即載入；否則會在下次登入時由 macOS 自動載入。
if launchctl print "gui/$TARGET_UID" >/dev/null 2>&1; then
    launchctl bootout "gui/$TARGET_UID" "$TARGET_PLIST" >/dev/null 2>&1 || true
    launchctl bootstrap "gui/$TARGET_UID" "$TARGET_PLIST"
fi

echo "安裝完成：$TARGET_USER 登入後會自動啟動 Chrome kiosk。"
echo "接下來請以 $TARGET_USER 登入，並在該帳號的畫面上完成："
echo "  1. 「系統設定 → 隱私權與安全性 → 輔助使用」允許 ${TARGET_PLAYER_APP}（重新安裝後可能需要先移除再加入）"
echo "  2. 第一次播放時，允許 Chrome Kiosk Player 控制「Google Chrome」與「System Events」的提示"
echo "記錄檔位置：$TARGET_LOGS"
