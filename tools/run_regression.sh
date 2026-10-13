#!/usr/bin/env bash
# Restart/persistence regression suite (headless, bounded, no API calls, no voice, no bridge).
# Uses only disposable saves (user://test_regress_*.json). The real save is never written; "realcopy" tests a byte copy of it.
#   tools/run_regression.sh            all suites
#   tools/run_regression.sh integrity  one suite: integrity | npc | realcopy | trials
# A suite fails on a FAIL line, a non-zero exit, a timeout or ANY "SCRIPT ERROR" in its log.
set -u
cd "$(dirname "$0")/.."
GODOT="${GODOT:-$HOME/Downloads/Godot-Engine/Godot_v4.7.2-stable_linux.x86_64}"
USERDIR="$HOME/.local/share/godot/app_userdata/Mika World 2.0 - Arcane Sanctuary (DEV)"
OUT="screenshots/persisttest"
mkdir -p "$OUT"
COMMON=(--profile=live --no-bridge --no-visitors --no-voice)
fails=0

run() {   # run <name> <timeout_s> <user args...>
  local name="$1" t="$2"; shift 2
  local log="$OUT/$name.log"
  timeout "$t" "$GODOT" --headless --path . -- "${COMMON[@]}" "$@" >"$log" 2>&1
  local code=$?
  local errs; errs=$(grep -c "SCRIPT ERROR" "$log")
  if [ $code -ne 0 ] || [ "$errs" -ne 0 ] || ! grep -q "^\[persisttest\] PASS" "$log"; then
    echo "FAIL  $name (exit $code, script errors $errs) -> $log"
    grep -E "^\[persisttest\]   FAIL|SCRIPT ERROR" -A2 "$log" | head -20
    fails=$((fails + 1))
  else
    echo "PASS  $name ($(grep -c '^\[persisttest\]   ok' "$log") checks)"
  fi
}

clean() { rm -f "$USERDIR"/test_regress_"$1"*; }

want="${1:-all}"
if [ "$want" = all ] || [ "$want" = integrity ]; then
  run integrity 120 --persisttest=integrity --save-path=user://test_regress_integrity.json
fi
if [ "$want" = all ] || [ "$want" = npc ]; then
  clean npc
  run npc1_session 240 --persisttest=npc1 --persist --save-path=user://test_regress_npc.json
  run npc2_restart 240 --persisttest=npc2 --persist --save-path=user://test_regress_npc.json
  clean npc
fi
if [ "$want" = all ] || [ "$want" = realcopy ]; then
  if [ -f "$USERDIR/mika_world_save.json" ]; then   # read-only use of the real save: test a byte copy
    clean realcopy
    cp "$USERDIR/mika_world_save.json" "$USERDIR/test_regress_realcopy.json"
    run realcopy 120 --persisttest=realcopy --persist --save-path=user://test_regress_realcopy.json
    clean realcopy
  fi
fi
if [ "$want" = all ] || [ "$want" = trials ]; then
  run trials 420 --persisttest=trials --save-path=user://test_regress_trials.json
fi
echo "regression: $fails failing suite(s)"
exit $((fails > 0))
