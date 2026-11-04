#!/bin/bash
# Runs the test suites headless in a throwaway folder (never touches ~/.factorio).
# Usage: tools/run_tests.sh [suite ...]      suites: main circuit situations saveload (default: all)
# FACTORIO=/path/to/factorio overrides the game binary.
set -e
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
FACTORIO="${FACTORIO:-/mnt/GamingSSD/SteamLibrary/steamapps/common/Factorio/bin/x64/factorio}"
SUITES=("$@")
[ ${#SUITES[@]} -eq 0 ] && SUITES=(main circuit situations saveload)
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
mkdir -p "$WORK/mods" "$WORK/write"
ln -s "$ROOT/cargo-cannon" "$WORK/mods/cargo-cannon"
ln -s "$ROOT/tests/dc-tests" "$WORK/mods/dc-tests"
ln -s "$ROOT/tests/dc-saveload" "$WORK/mods/dc-saveload"
mod_list() {  # mod_list <test mod to enable>
  cat > "$WORK/mods/mod-list.json" <<JSON
{"mods":[{"name":"base","enabled":true},{"name":"space-age","enabled":true},{"name":"quality","enabled":true},
{"name":"elevated-rails","enabled":true},{"name":"recycler","enabled":true},{"name":"cargo-cannon","enabled":true},
{"name":"dc-tests","enabled":$([ "$1" = dc-tests ] && echo true || echo false)},
{"name":"dc-saveload","enabled":$([ "$1" = dc-saveload ] && echo true || echo false)}]}
JSON
}
printf '[path]\nread-data=__PATH__system-read-data__\nwrite-data=%s\n' "$WORK/write" > "$WORK/config.ini"
run() { "$FACTORIO" -c "$WORK/config.ini" --mod-directory "$WORK/mods" "$@"; }
report() {  # report <log>: the STA lines, and any script error
  grep -E "^STA" "$1" || true
  if grep -qE "Error while|non-recoverable|Failed to load|errored" "$1"; then grep -E -A12 "Error while|non-recoverable|Failed to load|errored" "$1" | head -60; fi
}

FAILED=0
for suite in "${SUITES[@]}"; do
  echo "=== $suite"
  if [ "$suite" = saveload ]; then
    # 1: on a headless server, fire capsules with long flights; stopping the server saves the map mid-flight
    mod_list dc-saveload
    run --create "$WORK/sl.zip" --map-gen-settings "$ROOT/tests/map-gen-settings.json" > "$WORK/sl-create.log" 2>&1 || { cat "$WORK/sl-create.log"; exit 1; }
    printf '{"name":"cargo-cannon-test","description":"","tags":[],"max_players":0,"visibility":{"public":false,"lan":false},"require_user_verification":false,"auto_pause":false,"autosave_interval":0,"game_password":""}' > "$WORK/server.json"
    timeout -s INT 25 "$FACTORIO" -c "$WORK/config.ini" --mod-directory "$WORK/mods" --start-server "$WORK/sl.zip" \
      --server-settings "$WORK/server.json" --port 34297 < /dev/null > "$WORK/sl-server.log" 2>&1 || true
    report "$WORK/sl-server.log"
    # 2: load that save and let the capsules land
    run --test-save "$WORK/sl.zip" --test-ticks 6000 > "$WORK/sl-load.log" 2>&1 || true
    report "$WORK/sl-load.log"
    grep -q "STA saveload: .* 0 failed" "$WORK/sl-load.log" || FAILED=1
  else
    mod_list dc-tests
    [ -f "$WORK/map.zip" ] || run --create "$WORK/map.zip" --map-gen-settings "$ROOT/tests/map-gen-settings.json" > "$WORK/create.log" 2>&1 || { cat "$WORK/create.log"; exit 1; }
    \cp -f "$WORK/map.zip" "$WORK/$suite.zip"
    run --test-save "$WORK/$suite.zip" --test-ticks 2000 --test-arg "$suite" > "$WORK/$suite.log" 2>&1 || true
    report "$WORK/$suite.log"
    grep -q "STA $suite: .* 0 failed" "$WORK/$suite.log" || FAILED=1
  fi
done
[ $FAILED = 0 ] && echo "=== ALL PASSED" || { echo "=== SOME FAILED"; exit 1; }
