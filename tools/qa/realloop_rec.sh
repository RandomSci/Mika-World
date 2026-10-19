#!/bin/bash
# realloop_rec.sh <mktest> <abs outdir> [extra args...]: one combat-v3 test in the REAL game loop (no movie writer, no
# fixed fps: real frame times, capped at 30 fps, physics at its own tick) on the GPU, the Godot window screen recorded
# by ffmpeg (x11grab of its X window, 30 fps) -> rec.mp4 + log.txt. Every wait has a timeout. Never while live.
G=/home/selwyn/Downloads/Godot-Engine/Godot_v4.7.2-stable_linux.x86_64; P=/home/selwyn/Downloads/Mika-Godot-Dev-Combat
T=$1; O=$2; shift 2
if pgrep -x gamescope-wl >/dev/null; then echo "LIVE: no GPU"; exit 1; fi
mkdir -p "$O"; cd "$P" || exit 2
: > "$O/log.txt"
exec 9>/home/selwyn/.cache/mika_qa/godot.lock
timeout 1500 flock 9 || { echo "lock timeout"; exit 3; }
$G --display-driver x11 --resolution 1280x720 --position 0,0 --path . --max-fps 30 -- --profile=stream --no-bridge --luna --mktest=$T --save-path=user://test_regress_${T}.json --live-link=ws://127.0.0.1:9/test-none --realloop "$@" > "$O/log.txt" 2>&1 &
PID=$!
WID=""
for i in $(seq 1 120); do
  WID=$(xdotool search --name "Mika World" 2>/dev/null | tail -1)
  [ -n "$WID" ] && break
  kill -0 $PID 2>/dev/null || break
  sleep 0.5
done
echo "window $WID" >> "$O/log.txt"
if [ -n "$WID" ]; then
  timeout 1500 ffmpeg -v error -y -f x11grab -framerate 30 -window_id $WID -i :0 -c:v h264_nvenc -preset p5 -cq 20 "$O/rec.mp4" &
  FF=$!
fi
timeout 1500 bash -c "while kill -0 $PID 2>/dev/null; do sleep 1; done"
[ -n "$FF" ] && { kill -INT $FF 2>/dev/null; timeout 20 bash -c "while kill -0 $FF 2>/dev/null; do sleep 0.5; done"; }
grep -E "SCRIPT ERROR|mktest\] (PASS|FAIL)" "$O/log.txt" | cut -c1-200
ls -la "$O"
