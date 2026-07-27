#!/bin/bash

set -euo pipefail

LABEL="com.example.chrome-kiosk"

if [[ $EUID -ne 0 ]]; then
    echo "請使用 sudo 執行：sudo ./uninstall-for-user.sh" >&2
    exit 1
fi

TARGET_USER="${SUDO_USER:-}"
if [[ -z "$TARGET_USER" || "$TARGET_USER" == "root" ]]; then
    echo "無法辨識要移除的登入使用者；請從該使用者的終端機使用 sudo 執行。" >&2
    exit 1
fi

TARGET_UID="$(id -u "$TARGET_USER")"
TARGET_HOME="$(/usr/bin/dscl . -read "/Users/$TARGET_USER" NFSHomeDirectory | /usr/bin/sed 's/^NFSHomeDirectory: //')"
TARGET_PLIST="$TARGET_HOME/Library/LaunchAgents/$LABEL.plist"
TARGET_SUPPORT="$TARGET_HOME/Library/Application Support/Chrome Kiosk"
TARGET_APP="$TARGET_HOME/Applications/Chrome Kiosk Player.app"

/bin/launchctl bootout "gui/$TARGET_UID" "$TARGET_PLIST" >/dev/null 2>&1 || true
/usr/bin/pkill -u "$TARGET_UID" -f -- "--user-data-dir=$TARGET_SUPPORT" 2>/dev/null || true
/usr/bin/rm -rf "$TARGET_PLIST" "$TARGET_SUPPORT" "$TARGET_APP"

echo "已移除 $TARGET_USER 的 Chrome Kiosk。"
