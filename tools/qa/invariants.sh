#!/bin/bash
# Live-ready v1 invariant suite: runs every automated check headless (through the shared Godot lock) and prints one
# pass/fail table. Usage: tools/qa/invariants.sh [mode ...]   (default: all). Logs: ~/.cache/mika_qa/invariants/<stamp>/
# A check whose test file is not there yet is reported as SKIP. Test saves only (user://test_regress_*), the dummy
# live-link, never the live stream.
G=/home/selwyn/Downloads/Godot-Engine/Godot_v4.7.2-stable_linux.x86_64
P=$(cd "$(dirname "$0")/../.." && pwd)
L=/home/selwyn/.cache/mika_qa/godot.lock
OUT=/home/selwyn/.cache/mika_qa/invariants/$(date +%Y%m%d_%H%M%S)
mkdir -p "$OUT"
MODES=("$@")
[ ${#MODES[@]} -eq 0 ] && MODES=(mat_probe foot_slide hand_check boat_cloth persist_boat persist_dance viewer_lantern lake_path goal_overlay hair_check tear_check)
cd "$P"
flock "$L" sh -c "timeout 600 '$G' --headless --path . --import > '$OUT/import.log' 2>&1"
printf "%-16s %-6s %s\n" CHECK RESULT DETAIL > "$OUT/summary.txt"
for m in "${MODES[@]}"; do
  if [ ! -f "scripts/tests/ext/$m.gd" ] && ! grep -q "\"$m\": await" scripts/tests/milestone_k_test.gd; then
    printf "%-16s %-6s %s\n" "$m" SKIP "no test yet" >> "$OUT/summary.txt"; continue
  fi
  flock "$L" sh -c "timeout 900 '$G' --headless --path . -- --profile=stream --no-bridge --luna --no-scene-light --mktest=$m --save-path=user://test_regress_inv_$m.json --live-link=ws://127.0.0.1:9/test-none > '$OUT/$m.log' 2>&1"
  if grep -q "Parse Error\|Compile Error" "$OUT/$m.log"; then r=BUILD; d=$(grep -m1 -A1 "Parse Error\|Compile Error" "$OUT/$m.log" | tr '\n' ' ' | cut -c1-120)
  elif grep -q "\[mktest\] PASS" "$OUT/$m.log"; then r=PASS; d=$(grep -m1 -E "SUMMARY|worst|PASS" "$OUT/$m.log" | cut -c1-120)
  elif grep -q "\[mktest\] FAIL" "$OUT/$m.log"; then r=FAIL; d=$(grep -m1 "FAIL" "$OUT/$m.log" | cut -c1-120)
  else r=ERROR; d="no verdict (timeout or crash)"; fi
  printf "%-16s %-6s %s\n" "$m" "$r" "$d" >> "$OUT/summary.txt"
done
cat "$OUT/summary.txt"
echo "logs: $OUT"
