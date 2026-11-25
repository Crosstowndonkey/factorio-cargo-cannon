#!/bin/bash
# Opens a real Factorio window for about half a minute on a throwaway save and saves screenshots of the mod at work
# (tests/dc-screens): the panels beside the game's windows, firing, landing, a crash and its message.
# Never touches ~/.factorio. Usage: tools/run_screens.sh   SCREENS_DIR=/folder keeps the files there.
set -e
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
FACTORIO="${FACTORIO:-/mnt/GamingSSD/SteamLibrary/steamapps/common/Factorio/bin/x64/factorio}"
WORK="${SCREENS_DIR:-$(mktemp -d)}"
mkdir -p "$WORK/mods" "$WORK/write"
ln -sfn "$ROOT/cargo-cannon" "$WORK/mods/cargo-cannon"
rm -rf "$WORK/mods/dc-screens"
cp -r "$ROOT/tests/dc-screens" "$WORK/mods/dc-screens"
cp "$ROOT/tests/dc-tests/common.lua" "$WORK/mods/dc-screens/common.lua"
cat > "$WORK/mods/mod-list.json" <<JSON
{"mods":[{"name":"base","enabled":true},{"name":"space-age","enabled":true},{"name":"quality","enabled":true},
{"name":"elevated-rails","enabled":true},{"name":"recycler","enabled":true},{"name":"cargo-cannon","enabled":true},
{"name":"dc-screens","enabled":true}]}
JSON
printf '[path]\nread-data=__PATH__system-read-data__\nwrite-data=%s\n[graphics]\nfull-screen=false\n' "$WORK/write" > "$WORK/config.ini"
run() { "$FACTORIO" -c "$WORK/config.ini" --mod-directory "$WORK/mods" "$@"; }
run --create "$WORK/screens.zip" --map-gen-settings "$ROOT/tests/map-gen-settings.json" > "$WORK/create.log" 2>&1 || { cat "$WORK/create.log"; exit 1; }
export SteamAppId=427520 SteamGameId=427520
run --benchmark-graphics "$WORK/screens.zip" --benchmark-ticks 900 > "$WORK/run.log" 2>&1 || true
grep -E "^STA|Error while|non-recoverable" -A4 "$WORK/run.log" | head -40
echo "Screenshots: $WORK/write/script-output/dc-screens"
