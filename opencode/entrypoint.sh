#!/bin/sh
set -e

# One-time migration: named volume was previously written as root; chown to node
DATA_DIR=/home/node/.local/share/opencode
if [ -d "$DATA_DIR" ] && [ "$(stat -c %u "$DATA_DIR")" = "0" ]; then
    chown -R node:node "$DATA_DIR"
fi

BASE=/home/node/.config/opencode/opencode.base.jsonc
LOCAL=/home/node/.config/opencode/opencode.local.jsonc
OUT=/home/node/.config/opencode/opencode.jsonc

if [ -f "$LOCAL" ]; then
    jq -s '.[0] * .[1]' "$BASE" "$LOCAL" > "$OUT"
else
    cp "$BASE" "$OUT"
fi

exec gosu node "$@"
