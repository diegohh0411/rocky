#!/bin/sh
set -e

# Trust all directories so git works on host-mounted repos (root in container
# vs host user ownership triggers git's safe.directory check since 2.35).
git config --global --add safe.directory '*'

BASE=/root/.config/opencode/opencode.base.jsonc
LOCAL=/root/.config/opencode/opencode.local.jsonc
OUT=/root/.config/opencode/opencode.jsonc

if [ -f "$LOCAL" ]; then
    jq -s '.[0] * .[1]' "$BASE" "$LOCAL" > "$OUT"
else
    cp "$BASE" "$OUT"
fi

exec "$@"
