#!/usr/bin/env bash
# Mika's livestream, one command:
#
#   ./mika-live.sh              Mika's autonomous 3D world (default)
#   ./mika-live.sh --rehearse   everything prepared, nothing published, never streams
#   ./mika-live.sh --yes        go live as soon as ready (no GO question)
#   ./mika-live.sh --test-stream  an UNLISTED test: its own new broadcast titled [TEST], its own session file, no
#                               playlist, no paid thumbnail, no restart after the limit; goes live without GO
#   ./mika-live.sh --new-session  new title/description/thumbnail session
#
# World flow: server + Kokoro voice + the Godot world start (Godot is the Stage:
# Mika and Luna in Mika World 2.0, tools/godot-stage.sh), title / description / opening chat
# message are written, OBS opens the Stage (NOT streaming), the thumbnail is
# made (GPT Image 2, else the last approved one, else the default), everything
# is applied to the YouTube broadcast, then you are asked to type GO. Only then
# does OBS start streaming: the intro video plays first (OBS scene "Intro"), then
# the world. The opening message is posted once YouTube is live.
# At 11h55m the broadcast ends by itself and the next one starts (new session,
# intro again) without asking (VR_RESTART_AFTER_LIMIT=0 turns that off).
# Ctrl+C: Mika says goodbye, the broadcast ends, OBS stops and closes.
set -u
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PORT=12393
cd "$ROOT" || exit 1

mode=world new=0 renderer=godot          # the stream is the Godot world (no other renderer exists)
for arg in "$@"; do
    case "$arg" in
        --rehearse|--dry-run) export VR_REHEARSAL=1 VR_PRELIVE_DRY_RUN=1 ;;
        --yes) export VR_AUTO_GO_LIVE=1 ;;
        --test-stream) export VR_TEST_STREAM=1 VR_BROADCAST_PRIVACY=unlisted VR_AUTO_GO_LIVE=1 YOUTUBE_AUTO_PLAYLIST=0 \
                              VR_THUMBNAIL_GENERATE=0 VR_RESTART_AFTER_LIMIT=0 VR_PRELIVE_NEW_SESSION=1 ;;
        --new-session) new=1 ;;
        --no-image) export VR_THUMBNAIL_GENERATE=0 ;;
        -h|--help) sed -n 2,17p "$0"; exit 0 ;;
        *) echo "Unknown option: $arg (see --help)"; exit 2 ;;
    esac
done

# One launcher at a time (a second one would race the first before its port is bound).
mkdir -p logs
exec 9>logs/mika-live.lock
if ! flock -n 9; then
    echo "mika-live.sh is already running (logs/mika-live.lock). Stop it with Ctrl+C in its terminal."
    exit 1
fi

if curl -s -o /dev/null --max-time 2 "http://127.0.0.1:${PORT}/"; then
    echo "Port ${PORT} is already in use (another VR Agent server is running). Stop it first."
    exit 1
fi

# ---------------------------------------------------------------- CPU turbo off while live (Selwyn, 2026-10-18)
# Turbo boost spiked the CPU to 97 C on stream (a hardware heat cut at 08:24 that day). It is turned off for the
# stream and turned back on when the launcher exits, only if it was on before. Uses the root-owned helper
# /usr/local/sbin/mika-turbo (on|off, nothing else) through the sudo rule /etc/sudoers.d/mika-turbo; without them the
# stream runs as before, with a warning.
NO_TURBO=/sys/devices/system/cpu/intel_pstate/no_turbo
MIKA_TURBO=/usr/local/sbin/mika-turbo
TURBO_RESTORE=""
turbo_off() {
    [ -e "$NO_TURBO" ] || return 0
    [ "$(cat "$NO_TURBO" 2>/dev/null)" = 0 ] || return 0      # already off (or unknown): leave it as it is
    if sudo -n "$MIKA_TURBO" off >/dev/null 2>&1; then
        TURBO_RESTORE=1
        echo "CPU turbo boost: off for the stream (back on when it stops)"
    else
        echo "WARNING: CPU turbo boost could not be turned off ($MIKA_TURBO / sudo rule mika-turbo missing); continuing"
    fi
}
turbo_restore() {
    [ -n "$TURBO_RESTORE" ] || return 0
    sudo -n "$MIKA_TURBO" on >/dev/null 2>&1 && echo "CPU turbo boost: back on"
    TURBO_RESTORE=""
}
trap turbo_restore EXIT
turbo_off

# ---------------------------------------------------------------- the world show
export VR_MODE=world VR_CLASS_MODE=0 VR_MINECRAFT_MODE=0 VR_ROOM_CAST=mika
export VR_PRELIVE=1 VR_WORLD_HOLD_SPEECH=1 OBS_STAGE_SCENE="${OBS_STAGE_SCENE:-Mika World}"
export VR_WORLD_RENDERER="$renderer"
# the world's clock: the developer's own time (the Godot world follows it too; it is never named on stream)
export MIKA_TIMEZONE="${MIKA_TIMEZONE:-Asia/Manila}"
export YOUTUBE_AUTO_CHANNEL_DESCRIPTION=0   # the channel About text is not rewritten
export VR_BRAIN_MODEL="${VR_BRAIN_MODEL:-gpt-5.4-mini}"   # Mika's conversational brain (rollback: gpt-4o-mini)
export VR_BRAIN_REASONING="${VR_BRAIN_REASONING:-none}"
export VR_FEATURE_MAGIC="${VR_FEATURE_MAGIC:-1}" VR_FEATURE_CODING="${VR_FEATURE_CODING:-0}"
[ "$new" = 1 ] && export VR_PRELIVE_NEW_SESSION=1
PY="$ROOT/.venv/bin/python"
[ -x "$PY" ] || { echo "Python environment missing: $PY"; exit 1; }
[ -x tools/kokoro/.venv/bin/python ] || { echo "Kokoro not set up: run tools/kokoro/setup.sh"; exit 1; }
mkdir -p logs
LOG="logs/mika-live-$(date +%Y%m%d-%H%M%S).log"
# a log never grows past 50 MB however long the stream runs: copied to <log>.1 (one kept) and emptied in place
# (its writers append, so they carry on in the emptied file)
cap_log() {
    ( while sleep 60; do
          [ -f "$1" ] && [ "$(stat -c %s "$1" 2>/dev/null || echo 0)" -gt 52428800 ] && { cp -f "$1" "$1.1"; : > "$1"; }
      done ) &
}
cap_log "$LOG"; LOGCAP=$!
echo "Mika's world: log in $LOG"
[ "${VR_REHEARSAL:-0}" = 1 ] && echo "REHEARSAL: nothing is published and the stream is never started."
[ "${VR_TEST_STREAM:-0}" = 1 ] && echo "TEST STREAM: a new UNLISTED broadcast ([TEST] title); the show's session is not touched."

# Server with automatic restart after a crash (the stream session resumes;
# nothing is regenerated and no second broadcast is made).
(
    # A handler (not "ignore"): the server must keep its normal SIGINT handling
    # so the stop below gets a goodbye, the broadcast ended and OBS closed.
    trap 'true' INT
    while true; do
        # Own session: Ctrl+C in this terminal reaches only the launcher, which
        # then stops the server in order (never mistaken for a crash).
        setsid "$PY" run_server.py >>"$LOG" 2>&1 < /dev/null 9>&- &
        echo $! > logs/mika-live-server.pid
        # a new session only for the first start after the limit (a crash restart resumes it)
        [ -n "${LIMIT_NEW:-}" ] && { unset VR_PRELIVE_NEW_SESSION; LIMIT_NEW=""; }
        wait $!
        code=$?
        [ -f logs/mika-live-stop ] && break
        if [ "$code" -eq 0 ] && [ -f logs/mika-live-limit ] && [ "${VR_RESTART_AFTER_LIMIT:-1}" = 1 ] && [ "${VR_REHEARSAL:-0}" != 1 ]; then
            # the 11h55m end: the next broadcast starts by itself (new session, the intro again, no GO question)
            rm -f logs/mika-live-limit
            export VR_PRELIVE_NEW_SESSION=1 VR_AUTO_GO_LIVE=1
            LIMIT_NEW=1
            touch logs/mika-live-autogo
            echo "$(date +%T) the broadcast reached its limit; the next one starts in 30 s" | tee -a "$LOG"
            sleep 30
            continue
        fi
        [ "$code" -eq 0 ] && break
        # a crash restart resumes the SAME session (--new-session / --test-stream asked for a new one only at the
        # start: kept, it made a second session and posted the welcome message again - 2026-10-16 test stream)
        unset VR_PRELIVE_NEW_SESSION
        echo "$(date +%T) server stopped (exit $code), restarting in 5 s" | tee -a "$LOG"
        sleep 5
    done
) 9>&- &
LOOP=$!
rm -f logs/mika-live-stop logs/mika-live-limit logs/mika-live-autogo

# The Godot world (the Stage), restarted if it ever closes
GODOT_LOOP=""
if [ "$renderer" = godot ]; then
    echo "The Godot world starts (log logs/godot-stage.log)"
    tools/godot-stage.sh "$ROOT/logs/godot-stage.log" 9>&- &
    GODOT_LOOP=$!
fi

stop_all() {
    echo
    echo "Stopping: goodbye, end of broadcast, OBS closes (this takes up to a minute)"
    touch logs/mika-live-stop
    pid="$(cat logs/mika-live-server.pid 2>/dev/null)"
    [ -n "$pid" ] && kill -INT "$pid" 2>/dev/null
    for _ in $(seq 1 120); do kill -0 "$pid" 2>/dev/null || break; sleep 1; done
    kill -0 "$pid" 2>/dev/null && kill -TERM "$pid" 2>/dev/null
    wait "$LOOP" 2>/dev/null
    if [ -n "$GODOT_LOOP" ]; then
        gpid="$(cat logs/godot-stage.pid 2>/dev/null)"
        [ -n "$gpid" ] && kill -TERM "$gpid" 2>/dev/null
        for _ in $(seq 1 20); do kill -0 "$GODOT_LOOP" 2>/dev/null || break; sleep 0.5; done
        kill -0 "$GODOT_LOOP" 2>/dev/null && kill -TERM "$GODOT_LOOP" 2>/dev/null
    fi
    rm -f logs/mika-live-stop logs/mika-live-server.pid logs/mika-live-autogo
    kill "$LOGCAP" 2>/dev/null
    turbo_restore
    echo "Stopped."
    exit 0
}
trap stop_all INT TERM

status() { curl -s --max-time 3 "http://127.0.0.1:${PORT}/prelive/status"; }
show() {
    python3 - "$1" <<'PY'
import json, sys
try:
    s = json.loads(sys.argv[1])
except Exception:
    print("  (server starting)"); sys.exit()
p = s.get("prepared") or {}
t = s.get("thumbnail") or {}
print(f"  session {s.get('session')}  state {s.get('state')}  ready {s.get('ready')}" + ("  [dry run]" if s.get("dry_run") else ""))
print(f"  title:     {p.get('title')}")
print(f"  comment:   {p.get('opening_comment')}")
print(f"  thumbnail: {t.get('source')}  {t.get('path')}  ({t.get('note')})")
print(f"  broadcast: {s.get('broadcast_id')}   services: {s.get('services')}")
if s.get("missing"): print(f"  waiting for: {', '.join(s['missing'])}")
if s.get("last_failure") and not s.get("ready"): print(f"  last problem: {s['last_failure']}")
PY
}

last=""
while true; do
    st="$(status)"
    if [ -n "$st" ]; then
        cur="$(printf '%s' "$st" | python3 -c 'import json,sys;s=json.load(sys.stdin);print(s.get("state"),s.get("ready"),s.get("missing"),(s.get("prepared") or {}).get("title"),(s.get("thumbnail") or {}).get("source"))' 2>/dev/null)"
        if [ "$cur" != "$last" ]; then echo "$(date +%T) pre-live:"; show "$st"; last="$cur"; fi
        ready="$(printf '%s' "$st" | python3 -c 'import json,sys;print(json.load(sys.stdin).get("ready"))' 2>/dev/null)"
        confirmed="$(printf '%s' "$st" | python3 -c 'import json,sys;print(json.load(sys.stdin).get("confirmed"))' 2>/dev/null)"
        if [ "$ready" = True ] && [ "$confirmed" != True ]; then
            if [ "${VR_REHEARSAL:-0}" = 1 ]; then
                echo; echo "REHEARSAL READY. Everything above would be published. Ctrl+C to stop."
                while true; do sleep 3600 9>&- & wait $!; done
            fi
            if [ "${VR_AUTO_GO_LIVE:-0}" != 1 ] && [ ! -f logs/mika-live-autogo ]; then
                echo
                echo "READY. OBS shows the Stage but is NOT streaming yet."
                read -r -p "Type GO to start the public stream (Ctrl+C to stop): " answer
                if [ "$answer" = GO ]; then
                    curl -s -X POST "http://127.0.0.1:${PORT}/prelive/go"; echo
                    echo "Going live. The opening chat message is posted when YouTube shows the stream live."
                fi
            fi
        fi
    fi
    kill -0 "$LOOP" 2>/dev/null || { echo "The server loop ended. See $LOG"; exit 1; }
    sleep 3 9>&- & wait $!
done
