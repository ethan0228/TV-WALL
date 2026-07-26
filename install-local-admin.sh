#!/bin/bash

set -euo pipefail

LABEL="com.tvwall.admin"
SOURCE_ROOT="$(cd "$(dirname "$0")" && pwd)"
ADMIN_SOURCE="$SOURCE_ROOT/admin"
SUPPORT_ROOT="${TVWALL_ADMIN_HOME:-$HOME/Library/Application Support/TV-WALL Admin}"
APP_DIR="$SUPPORT_ROOT/app"
CONFIG_DIR="$SUPPORT_ROOT/config"
CONFIG_FILE="$CONFIG_DIR/.dev.vars"
DATA_DIR="$SUPPORT_ROOT/data"
LOG_DIR="$SUPPORT_ROOT/logs"
LAUNCH_AGENT="$HOME/Library/LaunchAgents/$LABEL.plist"
PORT="${TVWALL_ADMIN_PORT:-3100}"
PUBLIC_URL="${TVWALL_PUBLIC_URL:-}"
ADMIN_USERNAME="${TVWALL_ADMIN_USERNAME:-}"
OPEN_AFTER_INSTALL=1

usage() {
    cat <<'USAGE'
用法：./install-local-admin.sh [選項]

  --port 3100                  本機服務連接埠
  --public-url http://IP:3100  電視牆裝置連回這台 Mac 的區網網址
  --username admin             本機管理帳號
  --no-open                    安裝完成後不要自動開啟瀏覽器
USAGE
}

while (( $# > 0 )); do
    case "$1" in
        --port)
            PORT="${2:-}"
            shift 2
            ;;
        --public-url)
            PUBLIC_URL="${2:-}"
            shift 2
            ;;
        --username)
            ADMIN_USERNAME="${2:-}"
            shift 2
            ;;
        --no-open)
            OPEN_AFTER_INSTALL=0
            shift
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            echo "未知選項：$1" >&2
            usage >&2
            exit 2
            ;;
    esac
done

if [[ "$(uname -s)" != "Darwin" ]]; then
    echo "本機管理後台安裝程式目前支援 macOS。" >&2
    exit 2
fi
if [[ $EUID -eq 0 ]]; then
    echo "請用要執行管理後台的一般使用者執行，不要使用 sudo。" >&2
    exit 2
fi
if ! [[ "$PORT" =~ ^[0-9]+$ ]] || (( PORT < 1024 || PORT > 65534 )); then
    echo "連接埠必須是 1024 到 65534 的整數。" >&2
    exit 2
fi
if [[ ! -d "$ADMIN_SOURCE" ]]; then
    echo "找不到 admin 專案資料夾，請在完整 TV-WALL 專案內執行。" >&2
    exit 2
fi

NODE_BIN="$(command -v node || true)"
NPM_BIN="$(command -v npm || true)"
if [[ -x "$SUPPORT_ROOT/runtime/bin/node" && -x "$SUPPORT_ROOT/runtime/bin/npm" ]]; then
    NODE_BIN="$SUPPORT_ROOT/runtime/bin/node"
    NPM_BIN="$SUPPORT_ROOT/runtime/bin/npm"
fi
NODE_MAJOR=0
if [[ -n "$NODE_BIN" ]]; then
    NODE_MAJOR="$("$NODE_BIN" -p 'Number(process.versions.node.split(".")[0])' 2>/dev/null || echo 0)"
fi

if [[ -z "$NODE_BIN" || -z "$NPM_BIN" || "$NODE_MAJOR" -lt 22 ]]; then
    NODE_VERSION="v24.14.0"
    case "$(uname -m)" in
        arm64) NODE_ARCH="arm64" ;;
        x86_64) NODE_ARCH="x64" ;;
        *)
            echo "不支援的 Mac 處理器：$(uname -m)" >&2
            exit 3
            ;;
    esac
    NODE_PACKAGE="node-$NODE_VERSION-darwin-$NODE_ARCH"
    NODE_ARCHIVE="$NODE_PACKAGE.tar.gz"
    RUNTIME_DIR="$SUPPORT_ROOT/runtime"
    DOWNLOAD_DIR="$(mktemp -d "${TMPDIR:-/tmp}/tvwall-node.XXXXXX")"
    cleanup_download() {
        /bin/rm -rf "$DOWNLOAD_DIR"
    }
    trap cleanup_download EXIT

    echo "找不到合適的 Node.js，正在安裝 TV-WALL 專用 Node.js $NODE_VERSION…"
    /usr/bin/curl -fL --retry 3 \
        "https://nodejs.org/dist/$NODE_VERSION/$NODE_ARCHIVE" \
        -o "$DOWNLOAD_DIR/$NODE_ARCHIVE"
    /usr/bin/curl -fL --retry 3 \
        "https://nodejs.org/dist/$NODE_VERSION/SHASUMS256.txt" \
        -o "$DOWNLOAD_DIR/SHASUMS256.txt"
    (
        cd "$DOWNLOAD_DIR"
        /usr/bin/grep "  $NODE_ARCHIVE\$" SHASUMS256.txt > TVWALL-SHASUMS256.txt
        /usr/bin/shasum -a 256 -c TVWALL-SHASUMS256.txt
    )

    /bin/rm -rf "$RUNTIME_DIR"
    mkdir -p "$RUNTIME_DIR"
    /usr/bin/tar -xzf "$DOWNLOAD_DIR/$NODE_ARCHIVE" \
        -C "$RUNTIME_DIR" --strip-components=1
    NODE_BIN="$RUNTIME_DIR/bin/node"
    NPM_BIN="$RUNTIME_DIR/bin/npm"
    trap - EXIT
    cleanup_download
fi

existing_setting() {
    local key="$1"
    [[ -f "$CONFIG_FILE" ]] || return 0
    /usr/bin/sed -n "s/^${key}='\\(.*\\)'$/\\1/p" "$CONFIG_FILE" | /usr/bin/head -n 1
}

EXISTING_USERNAME="$(existing_setting LOCAL_ADMIN_USERNAME)"
EXISTING_PASSWORD_HASH="$(existing_setting LOCAL_ADMIN_PASSWORD_HASH)"
EXISTING_SESSION_SECRET="$(existing_setting LOCAL_SESSION_SECRET)"
EXISTING_DEVICE_SECRET="$(existing_setting DEVICE_CREDENTIAL_SECRET)"
KEEP_EXISTING=0

if [[ -n "$EXISTING_USERNAME" && -n "$EXISTING_PASSWORD_HASH" ]]; then
    answer=""
    if [[ -t 0 ]]; then
        read -r -p "已安裝過本機後台，保留原本管理帳號與密碼？[Y/n] " answer
    fi
    if [[ -z "$answer" || "$answer" =~ ^[Yy]$ ]]; then
        KEEP_EXISTING=1
        ADMIN_USERNAME="$EXISTING_USERNAME"
        PASSWORD_HASH="$EXISTING_PASSWORD_HASH"
    fi
fi

if (( KEEP_EXISTING == 0 )); then
    if [[ -z "$ADMIN_USERNAME" ]]; then
        read -r -p "設定管理帳號 [admin]：" ADMIN_USERNAME
        ADMIN_USERNAME="${ADMIN_USERNAME:-admin}"
    fi
    if ! [[ "$ADMIN_USERNAME" =~ ^[A-Za-z0-9._-]{3,64}$ ]]; then
        echo "管理帳號只能包含英文字母、數字、句點、底線或連字號，長度 3–64。" >&2
        exit 2
    fi

    if [[ -n "${TVWALL_ADMIN_PASSWORD:-}" ]]; then
        ADMIN_PASSWORD="$TVWALL_ADMIN_PASSWORD"
    else
        read -r -s -p "設定管理密碼（至少 10 個字元）：" ADMIN_PASSWORD </dev/tty
        echo
        read -r -s -p "再次輸入管理密碼：" ADMIN_PASSWORD_CONFIRM </dev/tty
        echo
        if [[ "$ADMIN_PASSWORD" != "$ADMIN_PASSWORD_CONFIRM" ]]; then
            echo "兩次密碼不一致。" >&2
            exit 2
        fi
    fi
    if (( ${#ADMIN_PASSWORD} < 10 )); then
        echo "管理密碼至少需要 10 個字元。" >&2
        exit 2
    fi
    PASSWORD_HASH="$(printf '%s' "$ADMIN_PASSWORD" | "$NODE_BIN" "$ADMIN_SOURCE/scripts/hash-password.mjs")"
    unset ADMIN_PASSWORD ADMIN_PASSWORD_CONFIRM TVWALL_ADMIN_PASSWORD
fi

if [[ -z "$PUBLIC_URL" ]]; then
    LAN_IP="$(/usr/sbin/ipconfig getifaddr en0 2>/dev/null || true)"
    [[ -n "$LAN_IP" ]] || LAN_IP="$(/usr/sbin/ipconfig getifaddr en1 2>/dev/null || true)"
    SUGGESTED_URL="http://${LAN_IP:-127.0.0.1}:$PORT"
    if [[ -t 0 ]]; then
        read -r -p "裝置連線網址 [$SUGGESTED_URL]：" PUBLIC_URL
    fi
    PUBLIC_URL="${PUBLIC_URL:-$SUGGESTED_URL}"
fi
if ! "$NODE_BIN" -e '
  const value = new URL(process.argv[1]);
  if (!["http:", "https:"].includes(value.protocol)) process.exit(1);
  if (value.username || value.password || value.pathname !== "/" || value.search || value.hash) process.exit(1);
' "$PUBLIC_URL"; then
    echo "裝置連線網址必須是 http://IP:連接埠 或 https://主機:連接埠。" >&2
    exit 2
fi
PUBLIC_URL="${PUBLIC_URL%/}"

SESSION_SECRET="${EXISTING_SESSION_SECRET:-$(/usr/bin/openssl rand -hex 32)}"
DEVICE_SECRET="${EXISTING_DEVICE_SECRET:-$(/usr/bin/openssl rand -hex 32)}"

echo "安裝 TV-WALL 本機管理後台到：$SUPPORT_ROOT"
mkdir -p "$APP_DIR" "$CONFIG_DIR" "$DATA_DIR" "$LOG_DIR" "$HOME/Library/LaunchAgents"

/usr/bin/rsync -a --delete \
    --exclude node_modules \
    --exclude dist \
    --exclude .next \
    --exclude .wrangler \
    "$ADMIN_SOURCE/" "$APP_DIR/"

printf '%s\n' "$NODE_BIN" > "$CONFIG_DIR/node-path"
printf '%s\n' "$PORT" > "$CONFIG_DIR/port"
cat > "$CONFIG_FILE" <<VARS
LOCAL_ADMIN_USERNAME='$ADMIN_USERNAME'
LOCAL_ADMIN_PASSWORD_HASH='$PASSWORD_HASH'
LOCAL_SESSION_SECRET='$SESSION_SECRET'
DEVICE_CREDENTIAL_SECRET='$DEVICE_SECRET'
PUBLIC_CONTROL_URL='$PUBLIC_URL'
VARS
chmod 600 "$CONFIG_FILE" "$CONFIG_DIR/node-path" "$CONFIG_DIR/port"

export PATH="$(dirname "$NODE_BIN"):$PATH"
cd "$APP_DIR"
"$NPM_BIN" exec --yes pnpm@11.9.0 -- install --frozen-lockfile
"$NPM_BIN" exec --yes pnpm@11.9.0 -- run build
ln -sfn "$CONFIG_FILE" "$APP_DIR/dist/server/.dev.vars"

cat > "$LAUNCH_AGENT" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>$LABEL</string>
    <key>ProgramArguments</key>
    <array>
        <string>/bin/bash</string>
        <string>$APP_DIR/scripts/run-local-admin.sh</string>
    </array>
    <key>RunAtLoad</key>
    <true/>
    <key>KeepAlive</key>
    <true/>
    <key>ThrottleInterval</key>
    <integer>10</integer>
    <key>StandardOutPath</key>
    <string>$LOG_DIR/admin.log</string>
    <key>StandardErrorPath</key>
    <string>$LOG_DIR/admin-error.log</string>
</dict>
</plist>
PLIST
chmod 600 "$LAUNCH_AGENT"
/usr/bin/plutil -lint "$LAUNCH_AGENT" >/dev/null

USER_UID="$(id -u)"
/bin/launchctl bootout "gui/$USER_UID" "$LAUNCH_AGENT" >/dev/null 2>&1 || true
/bin/launchctl bootstrap "gui/$USER_UID" "$LAUNCH_AGENT"

LOCAL_URL="http://127.0.0.1:$PORT"
READY=0
for _ in {1..30}; do
    if /usr/bin/curl -fsS "$LOCAL_URL/login" >/dev/null 2>&1; then
        READY=1
        break
    fi
    sleep 1
done

echo
if (( READY == 1 )); then
    echo "TV-WALL 本機管理後台已啟動。"
else
    echo "服務已安裝但尚未回應，請查看：$LOG_DIR/admin-error.log"
fi
echo "本機管理網址：$LOCAL_URL"
echo "裝置連線網址：$PUBLIC_URL"
echo "管理帳號：$ADMIN_USERNAME"
echo "資料位置：$DATA_DIR"
echo
echo "第一次啟動時，macOS 可能詢問是否允許 Node 接受連入連線，請選擇「允許」。"
echo "若裝置位於其他電腦，請確認它和這台 Mac 在同一個可信任區域網路。"

if (( OPEN_AFTER_INSTALL == 1 && READY == 1 )); then
    /usr/bin/open "$LOCAL_URL"
fi
