#!/bin/bash
# Kill/resume proof: phase 1 runs the activity until it prints READY_FOR_KILL, then this shell SIGKILLs it (no clean
# shutdown); phase 2 starts a new process on the SAME save and checks the resume.
# Run it under the shared lock:  flock /home/selwyn/.cache/mika_qa/godot.lock bash persist_run.sh <mode> <name> [gpu]
set -u
MODE=$1
NAME=$2
GPU=${3:-}
PROJ=/home/selwyn/Downloads/Mika-Godot-Dev-Anime
GODOT=/home/selwyn/Downloads/Godot-Engine/Godot_v4.7.2-stable_linux.x86_64
STAMP=$(date +%m%d_%H%M%S)
SAVE="user://test_regress_${NAME}_${STAMP}.json"
OUT="/home/selwyn/.cache/mika_qa/persist_${NAME}_${STAMP}"
mkdir -p "$OUT"
echo "out dir: $OUT"
echo "save:    $SAVE"
COMMON=(--profile=stream --no-bridge --luna --no-scene-light "--mktest=$MODE" "--save-path=$SAVE"
	--live-link=ws://127.0.0.1:9/test-none --persist --game-clock)
cd "$PROJ" || exit 2

disp() {   # $1 = phase
	if [ "$GPU" = "gpu" ]; then
		echo "--display-driver x11 --resolution 1920x1080 --write-movie $OUT/phase$1.avi --fixed-fps 30"
	else
		echo "--headless"
	fi
}
extra=()
if [ "$GPU" = "gpu" ]; then extra=("--persist-shots=$OUT"); fi

# ---- phase 1: start the activity, wait for READY_FOR_KILL, then SIGKILL
# shellcheck disable=SC2046
timeout -s KILL 480 "$GODOT" $(disp 1) --path . -- "${COMMON[@]}" "${extra[@]}" --persist-phase=1 > "$OUT/phase1.log" 2>&1 &
TPID=$!
killed=0
while kill -0 "$TPID" 2>/dev/null; do
	if grep -q "READY_FOR_KILL" "$OUT/phase1.log"; then
		sleep 4
		GPID=$(pgrep -P "$TPID" -f Godot_v4.7.2 | head -1)
		echo "READY seen; SIGKILL godot pid ${GPID:-?} at $(date +%T.%N | cut -c1-12)"
		[ -n "${GPID:-}" ] && kill -KILL "$GPID"
		killed=1
		break
	fi
	sleep 0.5
done
wait "$TPID"
echo "phase 1 exit code: $? (137 = killed by SIGKILL), killed by this shell: $killed"
grep -E "^\[mktest\]|^\[persist|^\[resume\]|^\[save\]|SCRIPT ERROR|^ERROR" "$OUT/phase1.log" | grep -v "^\[mktest\] fps" | head -60
SAVEFILE="$HOME/.local/share/godot/app_userdata/Mika World 2.0 - Arcane Sanctuary (DEV)/$(basename "$SAVE")"
echo "save on disk after the kill: $(ls -la "$SAVEFILE" 2>&1)"
ls "$(dirname "$SAVEFILE")" | grep "test_regress_${NAME}_${STAMP}" | sed 's/^/    /'
if [ -f "$OUT/phase1.avi" ]; then rm -f -- "$OUT/phase1.avi"; echo "deleted $OUT/phase1.avi"; fi

# ---- phase 2: same save, resume and verify
# shellcheck disable=SC2046
timeout 420 "$GODOT" $(disp 2) --path . -- "${COMMON[@]}" "${extra[@]}" --persist-phase=2 > "$OUT/phase2.log" 2>&1
echo "phase 2 exit code: $?"
grep -E "^\[mktest\]|^\[persist|^\[resume\]|^\[boat\] resumed|^\[save\]|^\[lakeritual\]|SCRIPT ERROR|^ERROR" "$OUT/phase2.log" | grep -v "^\[mktest\] fps" | head -90
if [ -f "$OUT/phase2.avi" ]; then rm -f -- "$OUT/phase2.avi"; echo "deleted $OUT/phase2.avi"; fi
ls -la "$OUT"
