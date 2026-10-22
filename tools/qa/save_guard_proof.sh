#!/usr/bin/env bash
# Proof that the save guard (WorldState, fail closed, 23 Oct) keeps every non-stage run off the real save.
# Every run here points Godot's user folder at a throwaway copy (XDG_DATA_HOME), so the real save is never at risk
# even if the guard were broken. The copied real save's sha256 is compared before and after each dangerous run.
set -u
W=${1:-/home/selwyn/Downloads/Mika-Godot-Dev-Fix}
G=/home/selwyn/Downloads/Godot-Engine/Godot_v4.7.2-stable_linux.x86_64
REAL="$HOME/.local/share/godot/app_userdata/Mika World 2.0 - Arcane Sanctuary (DEV)/mika_world_save.json"
T=$(mktemp -d /tmp/claude-1000/save_guard_XXXX 2>/dev/null || mktemp -d)
export XDG_DATA_HOME="$T/xdg"
U="$XDG_DATA_HOME/godot/app_userdata/Mika World 2.0 - Arcane Sanctuary (DEV)"
mkdir -p "$U"
cp "$REAL" "$U/mika_world_save.json"          # (a read of the real save, nothing more)
H0=$(sha256sum "$U/mika_world_save.json" | cut -d' ' -f1)
REALH0=$(sha256sum "$REAL" | cut -d' ' -f1)
pass=0; fail=0
check() {  # <name> <log>
  local h; h=$(sha256sum "$U/mika_world_save.json" | cut -d' ' -f1)
  local extra; extra=$(ls "$U" | grep -E "^mika_world_save\.(bak|tmp)" | head -3 | tr '\n' ' ')
  if [ "$h" = "$H0" ] && [ -z "$extra" ]; then echo "PASS  $1  (save untouched, no backup written)"; pass=$((pass+1))
  else echo "FAIL  $1  (save hash changed or backups written: $extra)"; fail=$((fail+1)); fi
  grep -E "\[guardprobe\]|\[save\] guard" "$2" | head -3 | sed 's/^/      /'
}
cd "$W" || exit 1
echo "user folder for this proof: $U"
# A. today's incident: a headless --script check with no flags, then saving forced on by hand
timeout 120 "$G" --headless --path . --script res://scripts/tests/save_guard_probe.gd > "$T/a.log" 2>&1
check "A  headless --script, no flags, saving forced on" "$T/a.log"
# B. a bare run of the game, no flags at all (headless, 50 s: past the 30 s periodic save)
timeout 50 "$G" --headless --path . > "$T/b.log" 2>&1
check "B  bare run, no flags" "$T/b.log"
# C. --persist without a save file of its own
timeout 50 "$G" --headless --path . -- --persist > "$T/c.log" 2>&1
check "C  --persist, no --save-path" "$T/c.log"
# D. the stage's own arguments, but headless (a script imitating the stage)
timeout 50 "$G" --headless --path . -- --profile=stream --viewer --brain --live-link --no-bridge --launch-days=/dev/null > "$T/d.log" 2>&1
check "D  the stage's arguments, headless" "$T/d.log"
# E. control: a test with its own save file still saves there
timeout 50 "$G" --headless --path . -- --persist --save-path=user://test_guard_control.json > "$T/e.log" 2>&1
if [ -s "$U/test_guard_control.json" ]; then echo "PASS  E  control: --persist with its own --save-path writes its own file"; pass=$((pass+1))
else echo "FAIL  E  control: the test's own save was not written"; fail=$((fail+1)); fi
REALH1=$(sha256sum "$REAL" | cut -d' ' -f1)
[ "$REALH0" = "$REALH1" ] && echo "PASS  the real save on disk is byte for byte unchanged" && pass=$((pass+1)) || { echo "FAIL  the real save changed during the proof"; fail=$((fail+1)); }
echo "$pass passed, $fail failed (logs in $T)"
[ $fail -eq 0 ]
