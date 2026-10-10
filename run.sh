#!/usr/bin/env bash
set -eu
cd "$(dirname "$0")"
if command -v godot >/dev/null 2>&1; then exec godot --path .; fi
if command -v godot4 >/dev/null 2>&1; then exec godot4 --path .; fi
if command -v godot-mono >/dev/null 2>&1; then exec godot-mono --path .; fi
printf 'Godot 4 was not found on PATH. Get the Linux editor from https://godotengine.org/download/linux/\nThen import project.godot, and press F5.\n' >&2
exit 1
