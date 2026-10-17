#!/usr/bin/env bash
# Mika World is a Godot project: no Three.js code, libraries or pages may ever be added (the old Three.js world lives
# only in the separate archive repository). Exit 1 and list the offenders when anything Three.js-like is tracked.
cd "$(dirname "$0")/.."
SELF="tools/check_no_threejs.sh"
files=$(git ls-files | grep -vx "$SELF" | grep -iE '(^|/)three(\.module|\.core|\.min)?\.js$|(^|/)three/|three[._-]?js')
code=$(git grep -l -I -iE "from ['\"]three['\"]|import \* as THREE|three\.module\.js|new THREE\.|three\.js|threejs" -- . ":!$SELF")
hits=$(printf '%s\n%s\n' "$files" "$code" | grep -v '^$' | sort -u)
if [ -n "$hits" ]; then echo "Three.js found (not allowed in Mika World):"; echo "$hits"; exit 1; fi
echo "no Three.js: OK"
