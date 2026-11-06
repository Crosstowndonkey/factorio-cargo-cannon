#!/bin/bash
# Opens a real Factorio window on a throwaway save with the live test bench (tests/dc-live). Never touches ~/.factorio.
# Usage: tools/run_live.sh [selftest]    selftest = build every test headless and stop
# LIVE_DIR=/some/folder keeps the throwaway files there (default: a new temp folder); notes are in
# <folder>/write/script-output/cargo-cannon-live-notes.txt
set -e
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
FACTORIO="${FACTORIO:-/mnt/GamingSSD/SteamLibrary/steamapps/common/Factorio/bin/x64/factorio}"
WORK="${LIVE_DIR:-$(mktemp -d)}"
mkdir -p "$WORK/mods" "$WORK/write"
ln -sfn "$ROOT/cargo-cannon" "$WORK/mods/cargo-cannon"
rm -rf "$WORK/mods/dc-live"
cp -r "$ROOT/tests/dc-live" "$WORK/mods/dc-live"
cp "$ROOT/tests/dc-tests/common.lua" "$WORK/mods/dc-live/common.lua"
cat > "$WORK/mods/mod-list.json" <<JSON
{"mods":[{"name":"base","enabled":true},{"name":"space-age","enabled":true},{"name":"quality","enabled":true},
{"name":"elevated-rails","enabled":true},{"name":"recycler","enabled":true},{"name":"cargo-cannon","enabled":true},
{"name":"dc-live","enabled":true}]}
JSON
printf '[path]\nread-data=__PATH__system-read-data__\nwrite-data=%s\n[graphics]\nfull-screen=false\n' "$WORK/write" > "$WORK/config.ini"
run() { "$FACTORIO" -c "$WORK/config.ini" --mod-directory "$WORK/mods" "$@"; }
[ -f "$WORK/live.zip" ] || run --create "$WORK/live.zip" --map-gen-settings "$ROOT/tests/map-gen-settings.json" > "$WORK/create.log" 2>&1 || { cat "$WORK/create.log"; exit 1; }
if [ "$1" = selftest ]; then
  \cp -f "$WORK/live.zip" "$WORK/self.zip"
  run --test-save "$WORK/self.zip" --test-ticks 200 --test-arg selftest > "$WORK/self.log" 2>&1 || true
  grep -E "^STA|Error while|non-recoverable|Failed to load" -A6 "$WORK/self.log" | grep -vE "^--" | head -70
  exit 0
fi
export SteamAppId=427520 SteamGameId=427520
echo "Notes: $WORK/write/script-output/cargo-cannon-live-notes.txt"
run --load-game "$WORK/live.zip"
