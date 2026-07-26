#!/bin/bash

set -euo pipefail

LABEL="com.example.chrome-kiosk"
DEFAULT_URL="https://www.canva.com/design/DAHOJXEvb9o/x3tAF2xvq3cvdreokETpfA/watch"
URL="${1:-$DEFAULT_URL}"
REFRESH_SECONDS="${2:-200}"
CONTROL_URL="${3:-}"
DEVICE_API_KEY="${4:-}"
SOURCE_DIR="$(cd "$(dirname "$0")" && pwd)"
CHROME_BINARY="/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"

if [[ $EUID -ne 0 ]]; then
    echo "請使用 sudo 執行：sudo ./install-for-user.sh [Canva網址] [備援秒數] [管理後台網址] [裝置API金鑰]" >&2
    exit 1
fi

TARGET_USER="${SUDO_USER:-}"
if [[ -z "$TARGET_USER" || "$TARGET_USER" == "root" ]]; then
    echo "無法辨識要安裝的登入使用者；請從該使用者的終端機使用 sudo 執行。" >&2
    exit 1
fi

TARGET_UID="$(id -u "$TARGET_USER")"
TARGET_GID="$(id -g "$TARGET_USER")"
TARGET_HOME="$(/usr/bin/dscl . -read "/Users/$TARGET_USER" NFSHomeDirectory | /usr/bin/sed 's/^NFSHomeDirectory: //')"
TARGET_SUPPORT="$TARGET_HOME/Library/Application Support/Chrome Kiosk"
TARGET_AGENTS="$TARGET_HOME/Library/LaunchAgents"
TARGET_APPS="$TARGET_HOME/Applications"
TARGET_APP="$TARGET_APPS/Chrome Kiosk Player.app"
TARGET_PLIST="$TARGET_AGENTS/$LABEL.plist"

if [[ ! "$URL" =~ ^https:// ]]; then
    echo "網址必須以 https:// 開頭。" >&2
    exit 2
fi
if ! [[ "$REFRESH_SECONDS" =~ ^[0-9]+$ ]] || (( REFRESH_SECONDS < 15 )); then
    echo "備援秒數必須是至少 15 的整數。" >&2
    exit 2
fi
if [[ -n "$CONTROL_URL" || -n "$DEVICE_API_KEY" ]]; then
    if [[ -z "$CONTROL_URL" || -z "$DEVICE_API_KEY" || ! "$CONTROL_URL" =~ ^https:// ]]; then
        echo "管理後台網址與裝置 API 金鑰必須一起提供，且網址必須使用 https://。" >&2
        exit 2
    fi
fi
if [[ ! -x "$CHROME_BINARY" ]]; then
    echo "找不到 Google Chrome。請先將 Google Chrome 安裝至 /Applications。" >&2
    exit 3
fi

for required_file in chrome-kiosk.sh detect-canva-duration.rb com.example.chrome-kiosk.plist "Chrome Kiosk Player.applescript"; do
    if [[ ! -f "$SOURCE_DIR/$required_file" ]]; then
        echo "安裝檔不完整，缺少：$required_file" >&2
        exit 4
    fi
done

install -d -o "$TARGET_UID" -g "$TARGET_GID" "$TARGET_SUPPORT" "$TARGET_AGENTS" "$TARGET_APPS"
install -o "$TARGET_UID" -g "$TARGET_GID" -m 755 "$SOURCE_DIR/chrome-kiosk.sh" "$TARGET_SUPPORT/chrome-kiosk.sh"
install -o "$TARGET_UID" -g "$TARGET_GID" -m 755 "$SOURCE_DIR/detect-canva-duration.rb" "$TARGET_SUPPORT/detect-canva-duration.rb"
install -o "$TARGET_UID" -g "$TARGET_GID" -m 600 "$SOURCE_DIR/com.example.chrome-kiosk.plist" "$TARGET_PLIST"

/usr/bin/rm -rf "$TARGET_APP"
/usr/bin/osacompile -o "$TARGET_APP" "$SOURCE_DIR/Chrome Kiosk Player.applescript"
/usr/sbin/chown -R "$TARGET_UID:$TARGET_GID" "$TARGET_APP"

/usr/libexec/PlistBuddy -c "Set :ProgramArguments:0 $TARGET_SUPPORT/chrome-kiosk.sh" "$TARGET_PLIST"
/usr/libexec/PlistBuddy -c "Set :ProgramArguments:1 $URL" "$TARGET_PLIST"
/usr/libexec/PlistBuddy -c "Set :ProgramArguments:2 $REFRESH_SECONDS" "$TARGET_PLIST"
/usr/libexec/PlistBuddy -c "Set :ProgramArguments:3 ${CONTROL_URL%/}" "$TARGET_PLIST"
/usr/libexec/PlistBuddy -c "Set :ProgramArguments:4 $DEVICE_API_KEY" "$TARGET_PLIST"
/usr/sbin/chown "$TARGET_UID:$TARGET_GID" "$TARGET_PLIST"
/usr/bin/plutil -lint "$TARGET_PLIST" >/dev/null

# 若使用者已有 GUI 工作階段則立即載入，否則 macOS 會在下次登入時載入。
if /bin/launchctl print "gui/$TARGET_UID" >/dev/null 2>&1; then
    /bin/launchctl bootout "gui/$TARGET_UID" "$TARGET_PLIST" >/dev/null 2>&1 || true
    /bin/launchctl bootstrap "gui/$TARGET_UID" "$TARGET_PLIST"
fi

echo "安裝完成：$TARGET_USER 登入後會自動啟動 Chrome kiosk。"
echo "播放網址：$URL"
if [[ -n "$CONTROL_URL" ]]; then
    echo "管理後台：${CONTROL_URL%/}"
fi
echo "首次執行後，請依 README 開啟輔助使用與自動化權限。"
