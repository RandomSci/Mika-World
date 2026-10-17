#!/usr/bin/env bash
# The Godot world as the Stage (VR_WORLD_RENDERER=godot), started by mika-live.sh and restarted if it ever closes.
#   VR_GODOT_PROJECT   the Godot project (default ~/Downloads/Mika-Godot-Dev)
#   VR_GODOT_BIN       the Godot binary (default ~/Downloads/Godot-Engine/Godot_v4.7.2-stable_linux.x86_64)
#   VR_GODOT_AUDIO_SINK  PipeWire sink its sound goes to (OBS captures only that sink; default MikaWorld)
#   VR_GODOT_NEST      headless (default when gamescope is installed), gamescope (a visible window) or none.
#                      headless: gamescope draws into no window at all; tools/stage_bridge.py copies its PipeWire
#                      stream into the v4l2loopback device VR_STAGE_V4L2 (default /dev/video42) that OBS's "Godot World"
#                      Video Capture Device reads. Nothing for GNOME to throttle when OBS covers the screen (a covered
#                      gamescope window got 1 frame callback a second: Godot stalled 133 ms every second, 21 fps).
#                      gamescope: the restart loop runs INSIDE one gamescope window (1920x1080, 30 Hz) that stays
#                      open when Godot crashes or restarts, so OBS's PipeWire window capture of it never loses its
#                      window (a capture of Godot's own window froze for good the first time Godot restarted).
#                      OBS: one "Window Capture (PipeWire)" source on the gamescope window, chosen once.
#   VR_GODOT_DISPLAY   without gamescope: wayland (default) or x11. Native Wayland: PipeWire window capture gets
#                      whole frames; under XWayland an X window capture read frames mid-swap (~13 frames/min out of
#                      order: heads seemed to twitch).
# It plays in the stream profile (a stable 30 FPS), in viewer mode (nothing operator-only on screen), with both mages
# living their own lives.
set -u
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROJECT="${VR_GODOT_PROJECT:-$HOME/Downloads/Mika-Godot-Dev}"
BIN="${VR_GODOT_BIN:-$HOME/Downloads/Godot-Engine/Godot_v4.7.2-stable_linux.x86_64}"
SINK="${VR_GODOT_AUDIO_SINK:-MikaWorld}"
NEST="${VR_GODOT_NEST:-headless}"
V4L2="${VR_STAGE_V4L2:-/dev/video42}"
command -v gamescope >/dev/null || NEST=none
[ "$NEST" = headless ] && [ ! -e "$V4L2" ] && { echo "$(date +%T) $V4L2 missing (v4l2loopback not loaded): using a visible gamescope window" >> "$LOG"; NEST=gamescope; }
INNER=0
[ "${1:-}" = "--inner" ] && { INNER=1; shift; }
LOG="${1:-$ROOT/logs/godot-stage.log}"
[ -x "$BIN" ] || { echo "Godot not found: $BIN"; exit 1; }
[ -f "$PROJECT/project.godot" ] || { echo "Godot project not found: $PROJECT"; exit 1; }

# its own sound sink (a null sink: nothing plays on the speakers; OBS monitors it)
if [ "$INNER" = 0 ] && command -v pw-cli >/dev/null && ! pw-cli ls Node 2>/dev/null | grep -q "node.name = \"$SINK\""; then
    pw-cli create-node adapter "{ factory.name=support.null-audio-sink node.name=$SINK node.description=\"Mika World (Godot)\" media.class=Audio/Sink object.linger=true audio.position=[FL FR] }" >/dev/null 2>&1 || true
fi

# a log never grows past 50 MB however long the stream runs: copied to <log>.1 (one kept) and emptied in place
# (its writers append, so they carry on in the emptied file)
cap_log() {
    ( while sleep 60; do
          [ -f "$1" ] && [ "$(stat -c %s "$1" 2>/dev/null || echo 0)" -gt 52428800 ] && { cp -f "$1" "$1.1"; : > "$1"; }
      done ) &
}
[ "$INNER" = 0 ] && { cap_log "$LOG"; LOGCAP=$!; trap 'kill $LOGCAP 2>/dev/null' EXIT; }

# the Godot restart loop (inside gamescope, or straight on the desktop)
run_loop() {
    local driver="$1"
    while true; do
        [ -f "$ROOT/logs/mika-live-stop" ] && break
        echo "$(date +%T) Godot Stage starting ($PROJECT, $driver, nest $NEST)" >> "$LOG"
        PULSE_SINK="$SINK" "$BIN" --display-driver "$driver" --path "$PROJECT" --resolution 1920x1080 --position 0,0 -- \
            --profile=stream --viewer --brain --live-link --no-bridge --launch-days="$ROOT/data/launch_days.json" >> "$LOG" 2>&1 < /dev/null &
        local gp=$!
        echo $gp > "$ROOT/logs/godot-stage.pid"
        if [ "$INNER" = 1 ] && command -v xdotool >/dev/null; then
            # gamescope keeps presenting only the window it first focused: a Godot started after a crash got ~1 fps
            # and never reached the screen until its new window is activated inside gamescope's own X server
            ( for _ in $(seq 1 60); do
                  w=$(xdotool search --pid $gp 2>/dev/null | tail -1)
                  [ -n "$w" ] && { sleep 3; xdotool windowactivate --sync "$w" >/dev/null 2>&1; xdotool windowfocus "$w" >/dev/null 2>&1;
                                   echo "$(date +%T) Godot window $w activated in gamescope" >> "$LOG"; break; }
                  sleep 1
              done ) &
        fi
        wait $gp
        code=$?
        [ -f "$ROOT/logs/mika-live-stop" ] && break
        echo "$(date +%T) Godot Stage closed (exit $code), restarting in 5 s" >> "$LOG"
        sleep 5
    done
}

if [ "$INNER" = 1 ]; then
    run_loop x11                       # gamescope's own X server: never the desktop's Wayland
    exit 0
fi

if [ "$NEST" = gamescope ] || [ "$NEST" = headless ]; then
    BACKEND=""
    if [ "$NEST" = headless ]; then
        BACKEND="--backend headless"
        ( while [ ! -f "$ROOT/logs/mika-live-stop" ]; do        # the bridge, brought back if it ever stops
              /usr/bin/python3 "$ROOT/tools/stage_bridge.py" "$V4L2" "$LOG" >/dev/null 2>&1 < /dev/null
              sleep 2
          done ) &
        BRIDGE=$!
        echo $BRIDGE > "$ROOT/logs/stage-bridge.pid"
        trap 'kill $BRIDGE ${LOGCAP:-} 2>/dev/null; pkill -f "^/usr/bin/python3 $ROOT/tools/stage_bridge.py" 2>/dev/null' EXIT
    fi
    # one gamescope for the whole session; only if gamescope itself ever closes is a new one started
    while true; do
        [ -f "$ROOT/logs/mika-live-stop" ] && break
        echo "$(date +%T) gamescope starting (${NEST}, 1920x1080, 30 Hz)" >> "$LOG"
        # composited on the RTX (it picked the Intel iGPU by itself: every frame copied between GPUs), 30 Hz focused
        # or not (the operator works in other windows while it streams)
        GPU="${VR_GAMESCOPE_GPU:-$(lspci -nn 2>/dev/null | grep -i nvidia | grep -o '10de:[0-9a-f]\{4\}' | head -1)}"
        env -u WAYLAND_DISPLAY gamescope $BACKEND -W 1920 -H 1080 -w 1920 -h 1080 -r 30 -o 30 ${GPU:+--prefer-vk-device $GPU} -b -- \
            "$ROOT/tools/godot-stage.sh" --inner "$LOG" >> "$LOG" 2>&1 < /dev/null &
        NESTPID=$!
        echo $NESTPID > "$ROOT/logs/godot-stage-nest.pid"
        if [ "$NEST" = headless ]; then
            # watchdog: frames must keep reaching OBS. gamescope's PipeWire side can die while gamescope runs on; no
            # frame through the bridge for 30 s (after its first minute) -> gamescope (and Godot in it) restarted
            ( started=$(date +%s); while kill -0 $NESTPID 2>/dev/null; do
                  sleep 5
                  [ $(( $(date +%s) - started )) -lt 60 ] && continue
                  beat=$(stat -c %Y "$ROOT/logs/stage-bridge.alive" 2>/dev/null || echo 0)
                  if [ $(( $(date +%s) - beat )) -gt 30 ] && [ ! -f "$ROOT/logs/mika-live-stop" ]; then
                      echo "$(date +%T) no frames reached OBS for 30 s: restarting gamescope" >> "$LOG"
                      kill $NESTPID 2>/dev/null; break
                  fi
              done ) &
        fi
        wait $NESTPID
        [ -f "$ROOT/logs/mika-live-stop" ] && break
        echo "$(date +%T) gamescope window closed, opening it again in 5 s (OBS: choose the new window once)" >> "$LOG"
        sleep 5
    done
    rm -f "$ROOT/logs/godot-stage.pid" "$ROOT/logs/godot-stage-nest.pid" "$ROOT/logs/stage-bridge.pid"
    exit 0
fi

DISPLAY_DRIVER="${VR_GODOT_DISPLAY:-wayland}"
[ -n "${WAYLAND_DISPLAY:-}" ] || DISPLAY_DRIVER=x11
run_loop "$DISPLAY_DRIVER"
rm -f "$ROOT/logs/godot-stage.pid"
