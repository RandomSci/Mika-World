#!/usr/bin/env bash
# Restart/persistence regression suite (headless, bounded, no API calls, no voice, no bridge).
# Uses only disposable saves (user://test_regress_*.json). The real save is never written; "realcopy" tests a byte copy of it.
#   tools/run_regression.sh            all suites
#   tools/run_regression.sh integrity  one suite: integrity | npc | realcopy | trials | mh | mi | visual (windowed: music, audience, transformation)
# A suite fails on a FAIL line, a non-zero exit, a timeout or ANY "SCRIPT ERROR" in its log.
set -u
cd "$(dirname "$0")/.."
GODOT="${GODOT:-$HOME/Downloads/Godot-Engine/Godot_v4.7.2-stable_linux.x86_64}"
USERDIR="$HOME/.local/share/godot/app_userdata/Mika World 2.0 - Arcane Sanctuary (DEV)"
OUT="screenshots/persisttest"
mkdir -p "$OUT"
COMMON=(--profile=live --no-bridge --no-visitors --no-voice --no-weather)   # a fixed clear sky: a shower would (rightly) send her to shelter mid-suite
fails=0

run() {   # run <name> <timeout_s> <user args...>
  local name="$1" t="$2"; shift 2
  local log="$OUT/$name.log"
  timeout "$t" "$GODOT" --headless --path . -- "${COMMON[@]}" "$@" >"$log" 2>&1
  local code=$?
  local errs; errs=$(grep -c "SCRIPT ERROR" "$log")
  if [ $code -ne 0 ] || [ "$errs" -ne 0 ] || ! grep -qE "^\[(persisttest|mhtest|mitest)\] PASS" "$log"; then
    echo "FAIL  $name (exit $code, script errors $errs) -> $log"
    grep -E "^\[(persisttest|mhtest|mitest)\]   FAIL|SCRIPT ERROR" -A2 "$log" | head -20
    fails=$((fails + 1))
  else
    echo "PASS  $name ($(grep -cE '^\[(persisttest|mhtest|mitest)\]   ok' "$log") checks)"
  fi
}

clean() { rm -f "$USERDIR"/test_regress_"$1"*; }

# windowed suites (real rendering / audio device): music performances, audience, transformation previews.
# They open a 1600x900 window and take keyboard focus (the tests ignore keyboard input).
runw() {
  local name="$1" t="$2"; shift 2
  local log="$OUT/$name.log"
  timeout "$t" "$GODOT" --path . --resolution 1600x900 -- --profile=live --no-bridge --no-visitors --no-weather "$@" >"$log" 2>&1
  local code=$?
  local errs; errs=$(grep -c "SCRIPT ERROR" "$log")
  if [ $code -ne 0 ] || [ "$errs" -ne 0 ] || ! grep -qE "^\[(persisttest|mhtest|mitest)\] PASS" "$log"; then
    echo "FAIL  $name (exit $code, script errors $errs) -> $log"
    grep -E "^\[(persisttest|mhtest|mitest)\]   FAIL|SCRIPT ERROR" -A2 "$log" | head -20
    fails=$((fails + 1))
  else
    echo "PASS  $name ($(grep -cE '^\[(persisttest|mhtest|mitest)\]   ok' "$log") checks)"
  fi
}

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
if [ "$want" = all ] || [ "$want" = mh ]; then
  run mh_progression 120 --mhtest=progression --save-path=user://test_regress_mh.json
  run mh_isolation 120 --mhtest=isolation --luna --save-path=user://test_regress_mh.json
  run mh_vrm 240 --mhtest=vrm --luna --save-path=user://test_regress_mh.json
  clean mhp
  run mh_persist1 120 --mhtest=persist1 --luna --persist --save-path=user://test_regress_mhp.json
  run mh_persist2 120 --mhtest=persist2 --luna --persist --save-path=user://test_regress_mhp.json
  clean mhp
  run mh_combat_luna 300 --mhtest=combat --who=luna --kind=gloomwisp --luna --monsters --save-path=user://test_regress_mh.json
  run mh_combat_mika 300 --mhtest=combat --who=mika --kind=thornback --luna --monsters --no-luna-brain --save-path=user://test_regress_mh.json
  run mh_fusion 300 --mhtest=fusion --luna --monsters --save-path=user://test_regress_mh.json
fi
if [ "$want" = all ] || [ "$want" = mi ]; then
  clean mif
  run mi_form1 180 --mitest=form1 --luna --no-luna-brain --persist --save-path=user://test_regress_mif.json
  run mi_form2 180 --mitest=form2 --luna --no-luna-brain --persist --save-path=user://test_regress_mif.json
  clean mif
  run mi_background 400 --mitest=background --luna --seconds=150 --save-path=user://test_regress_mi.json
  run mi_focus 300 --mitest=focus --luna --save-path=user://test_regress_mi.json
  run mi_luna_read 300 --mitest=luna_read --luna --save-path=user://test_regress_mi.json
  run mi_luna_alchemy 300 --mitest=luna_alchemy --luna --save-path=user://test_regress_mi.json
  clean mi   # a fresh save: places visited by earlier suites must not leak into "unvisited"
  run mi_explore_mika 300 --mitest=explore --who=mika --luna --save-path=user://test_regress_mi.json
  clean mi   # a fresh save: places visited by earlier suites must not leak into "unvisited"
  run mi_explore_luna 300 --mitest=explore --who=luna --luna --save-path=user://test_regress_mi.json
  run mi_collision 240 --mitest=collision --luna --save-path=user://test_regress_mi.json
  run mi_interact 300 --mitest=interact --luna --save-path=user://test_regress_mi.json
  run mi_music_lib 120 --mitest=music_lib --save-path=user://test_regress_mi.json
fi
if [ "$want" = visual ]; then
  runw vis_mh_transform 400 --mhtest=transform --luna --no-luna-brain --save-path=user://test_regress_mh.json
  runw vis_audience 400 --mitest=audience --luna --no-monsters --save-path=user://test_regress_mi.json
  runw vis_perform_mika 360 --mitest=perform --who=mika --mode=casual --no-shots --luna --no-monsters --save-path=user://test_regress_mi.json
  runw vis_perform_luna_special 360 --mitest=perform --who=luna --mode=special --no-shots --luna --no-monsters --save-path=user://test_regress_mi.json
  runw vis_perform_preview 360 --mitest=perform --who=luna --mode=casual --preview --no-shots --luna --no-monsters --save-path=user://test_regress_mi.json
  runw vis_perform_interrupt 300 --mitest=perform_interrupt --luna --save-path=user://test_regress_mi.json
  runw vis_perf_ab 300 --mitest=perf_ab --luna --no-monsters --save-path=user://test_regress_mi.json
fi
echo "regression: $fails failing suite(s)"
exit $((fails > 0))
