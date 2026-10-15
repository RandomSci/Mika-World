#!/usr/bin/env bash
# Launch Mika World 2.0 (DEV). Independent of the production Three.js stream.
#   ./run.sh                  ADAPTIVE 60 (default): 60 FPS held by measured quality steps, Forward+ (Vulkan)
#   ./run.sh cinematic        CINEMATIC, fixed full quality (heavy scenes fall below 60)
#   ./run.sh live             LIVE_OPTIMIZED (use while OBS + the live stream share this laptop)
#   ./run.sh ultra            ULTRA (stronger GPUs: SDFGI, 4 shadow cascades, MSAA)
#   ./run.sh compat           Compatibility/OpenGL fallback (LIVE_OPTIMIZED settings)
#   ./run.sh night            CINEMATIC at night
#   ./run.sh tour [live]      automated screenshots + measurements -> screenshots/, then quits
#   ./run.sh editor           open the Godot editor on this project
# Extra Godot user args may follow, e.g. ./run.sh live --no-bridge
set -eu
cd "$(dirname "$0")"
GODOT="${GODOT:-$HOME/Downloads/Godot-Engine/Godot_v4.7.2-stable_linux.x86_64}"
mode="${1:-adaptive}"; shift || true
case "$mode" in
  adaptive)  exec "$GODOT" --path . -- --profile=adaptive "$@" ;;
  cinematic) exec "$GODOT" --path . -- --profile=cinematic "$@" ;;
  live)      exec "$GODOT" --path . -- --profile=live "$@" ;;
  ultra)     exec "$GODOT" --path . -- --profile=ultra "$@" ;;
  night)     exec "$GODOT" --path . -- --profile=cinematic --night "$@" ;;
  compat)    exec "$GODOT" --path . --rendering-method gl_compatibility -- --profile=live "$@" ;;
  tour)      p="${1:-cinematic}"; shift || true
             exec "$GODOT" --path . --resolution 1600x900 -- --tour --no-bridge --profile="$p" "$@" ;;
  editor)    exec "$GODOT" --path . -e ;;
  *) echo "unknown mode: $mode" >&2; exit 2 ;;
esac
