#!/usr/bin/env bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

mkdir -p "$ROOT_DIR/vendor"

if [ ! -d "$ROOT_DIR/vendor/NWWebSocket" ]; then
    echo "Cloning NWWebSocket into vendor/NWWebSocket..."
    git clone --depth 1 https://github.com/pusher/NWWebSocket.git "$ROOT_DIR/vendor/NWWebSocket"
else
    echo "vendor/NWWebSocket already exists."
fi

echo "Vendor dependencies ready!"
