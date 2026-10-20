#!/bin/bash
# Blender render through the shared GPU lock (Selwyn 2026-10-20): refuses while the stream is live, waits its
# turn on the godot lock so Mika Main and this session never render at the same time, 10 minute cap per run.
if pgrep -x gamescope-wl >/dev/null || pgrep -x obs >/dev/null || pgrep -f "tools/godot-stag[e].sh" >/dev/null; then
  echo "LIVE, no GPU work"; exit 3
fi
exec flock -w 1800 "$HOME/.cache/mika_qa/godot.lock" timeout 600 blender -b --factory-startup "$@"
