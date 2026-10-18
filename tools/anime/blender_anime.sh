#!/usr/bin/env bash
# Blender 4.2 with the anime-proof add-ons (AnimAide, Wiggle 2, BlendArMocap, Rigify) in its OWN profile:
# Selwyn's normal Blender settings and add-ons are untouched.
export BLENDER_USER_RESOURCES=/home/selwyn/.cache/mika_qa/blender_anime_profile
exec /usr/local/bin/blender "$@"
