#!/bin/bash

set -euo pipefail

TARGET_USER="user"
TARGET_GROUP="staff"
TARGET_UID="$(id -u "$TARGET_USER")"
SOURCE_DIR="/Users/ethan/Desktop/SCREEN"
SOURCE_PLAYER_APP="/Users/ethan/Applications/Chrome Kiosk Player.app"
TARGET_HOME="/Users/user"
TARGET_SUPPORT="$TARGET_HOME/Library/Application Support/Chrome Kiosk"
TARGET_AGENTS="$TARGET_HOME/Library/LaunchAgents"
TARGET_APPS="$TARGET_HOME/Applications"
TARGET_PLIST="$TARGET_AGENTS/com.example.chrome-kiosk.plist"

if [[ $EUID -ne 0 ]]; then
    echo "請使用 sudo 執行此安裝程式。" >&2
    exit 1
fi

install -d -o "$TARGET_USER" -g "$TARGET_GROUP" "$TARGET_SUPPORT" "$TARGET_AGENTS" "$TARGET_APPS"
install -o "$TARGET_USER" -g "$TARGET_GROUP" -m 755 "$SOURCE_DIR/chrome-kiosk.sh" "$TARGET_SUPPORT/chrome-kiosk.sh"
install -o "$TARGET_USER" -g "$TARGET_GROUP" -m 755 "$SOURCE_DIR/detect-canva-duration.rb" "$TARGET_SUPPORT/detect-canva-duration.rb"
install -o "$TARGET_USER" -g "$TARGET_GROUP" -m 644 "$SOURCE_DIR/com.example.chrome-kiosk.plist" "$TARGET_PLIST"

rm -rf "$TARGET_APPS/Chrome Kiosk Player.app"
ditto "$SOURCE_PLAYER_APP" "$TARGET_APPS/Chrome Kiosk Player.app"
chown -R "$TARGET_USER:$TARGET_GROUP" "$TARGET_APPS/Chrome Kiosk Player.app"

# 如果 user 已有 GUI 登入工作階段，立即載入；否則會在下次登入時由 macOS 自動載入。
if launchctl print "gui/$TARGET_UID" >/dev/null 2>&1; then
    launchctl bootout "gui/$TARGET_UID" "$TARGET_PLIST" >/dev/null 2>&1 || true
    launchctl bootstrap "gui/$TARGET_UID" "$TARGET_PLIST"
fi

echo "安裝完成：$TARGET_USER 登入後會自動啟動 Chrome kiosk。"
echo "首次登入後，請允許 $TARGET_APPS/Chrome Kiosk Player.app 使用輔助功能。"
