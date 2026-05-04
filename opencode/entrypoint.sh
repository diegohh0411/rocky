#!/bin/sh
set -e

DATA_DIR=/home/node/.local/share/opencode

if [ -d "$DATA_DIR" ] && [ "$(stat -c %u "$DATA_DIR")" = "0" ]; then
    chown -R node:node "$DATA_DIR"
fi

if [ -n "$OPENCODE_AUTH_JSON_BASE64" ]; then
    echo "$OPENCODE_AUTH_JSON_BASE64" | base64 -d > "$DATA_DIR/auth.json"
fi

if [ -n "$OPENCODE_MCP_AUTH_JSON_BASE64" ]; then
    echo "$OPENCODE_MCP_AUTH_JSON_BASE64" | base64 -d > "$DATA_DIR/mcp-auth.json"
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