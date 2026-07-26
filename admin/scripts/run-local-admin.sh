#!/bin/bash

set -euo pipefail

SUPPORT_ROOT="${TVWALL_ADMIN_HOME:-$HOME/Library/Application Support/TV-WALL Admin}"
APP_DIR="$SUPPORT_ROOT/app"
PORT_FILE="$SUPPORT_ROOT/config/port"
NODE_FILE="$SUPPORT_ROOT/config/node-path"
CONFIG_FILE="$SUPPORT_ROOT/config/.dev.vars"

if [[ ! -r "$PORT_FILE" || ! -r "$NODE_FILE" || ! -r "$CONFIG_FILE" ]]; then
    echo "TV-WALL 本機管理後台設定不完整，請重新執行 install-local-admin.sh。" >&2
    exit 2
fi

PORT="$(tr -d '[:space:]' < "$PORT_FILE")"
NODE_BIN="$(sed -n '1p' "$NODE_FILE")"

if ! [[ "$PORT" =~ ^[0-9]+$ ]] || (( PORT < 1024 || PORT > 65535 )); then
    echo "TV-WALL 管理後台連接埠設定無效。" >&2
    exit 2
fi
if [[ ! -x "$NODE_BIN" ]]; then
    echo "找不到安裝時使用的 Node.js：$NODE_BIN" >&2
    echo "請重新執行 install-local-admin.sh 更新執行環境。" >&2
    exit 3
fi
if [[ ! -f "$APP_DIR/dist/server/wrangler.json" ]]; then
    echo "找不到已建置的管理後台，請重新執行 install-local-admin.sh。" >&2
    exit 4
fi

ln -sfn "$CONFIG_FILE" "$APP_DIR/dist/server/.dev.vars"
mkdir -p "$SUPPORT_ROOT/data" "$SUPPORT_ROOT/logs"

export NODE_ENV="production"
export WRANGLER_SEND_METRICS="false"
export NO_COLOR="1"

cd "$APP_DIR/dist/server"
exec "$NODE_BIN" "$APP_DIR/node_modules/wrangler/bin/wrangler.js" dev \
    --config "wrangler.json" \
    --local \
    --persist-to "$SUPPORT_ROOT/data" \
    --ip 0.0.0.0 \
    --port "$PORT" \
    --inspector-port "$((PORT + 1))" \
    --log-level warn
