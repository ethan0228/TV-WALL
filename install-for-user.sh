#!/bin/bash
#
# 安裝 Chrome kiosk 到指定的 macOS 使用者帳號（預設 user）。
# 用法：sudo ./install-for-user.sh [目標使用者]

set -euo pipefail

TARGET_USER="${1:-user}"
TARGET_GROUP="staff"
SOURCE_DIR="$(cd "$(dirname "$0")" && pwd)"

if [[ $EUID -ne 0 ]]; then
    echo "請使用 sudo 執行此安裝程式。" >&2
    exit 1
fi

if ! TARGET_UID="$(id -u "$TARGET_USER" 2>/dev/null)"; then
    echo "找不到使用者：$TARGET_USER" >&2
    exit 1
fi
TARGET_HOME="$(dscl . -read "/Users/$TARGET_USER" NFSHomeDirectory | awk '{print $2}')"
TARGET_SUPPORT="$TARGET_HOME/Library/Application Support/Chrome Kiosk"
TARGET_AGENTS="$TARGET_HOME/Library/LaunchAgents"
TARGET_APPS="$TARGET_HOME/Applications"
TARGET_PLIST="$TARGET_AGENTS/com.example.chrome-kiosk.plist"
TARGET_PLAYER_APP="$TARGET_APPS/Chrome Kiosk Player.app"

install -d -o "$TARGET_USER" -g "$TARGET_GROUP" "$TARGET_SUPPORT" "$TARGET_AGENTS" "$TARGET_APPS"
install -o "$TARGET_USER" -g "$TARGET_GROUP" -m 755 "$SOURCE_DIR/chrome-kiosk.sh" "$TARGET_SUPPORT/chrome-kiosk.sh"
install -o "$TARGET_USER" -g "$TARGET_GROUP" -m 755 "$SOURCE_DIR/kiosk-cdp.rb" "$TARGET_SUPPORT/kiosk-cdp.rb"
# 舊版的偵測腳本已改名為 kiosk-cdp.rb。
rm -f "$TARGET_SUPPORT/detect-canva-duration.rb"

# plist 不能用 ~，安裝時把範本裡的 __TARGET_HOME__ 換成目標使用者的家目錄。
sed "s#__TARGET_HOME__#$TARGET_HOME#g" "$SOURCE_DIR/com.example.chrome-kiosk.plist" >"$TARGET_PLIST"
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
echo "請到「系統設定 → 隱私權與安全性 → 輔助使用」允許 $TARGET_PLAYER_APP（重新安裝後可能需要先移除再加入）。"
