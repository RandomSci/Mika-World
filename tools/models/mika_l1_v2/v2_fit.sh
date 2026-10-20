#!/bin/bash
# Mika L1 outfit v2 (Selwyn 2026-10-20): place, rig and export, then into anime-proof as a test asset and import it.
# The Godot import goes through the shared GPU lock with a test save and a dead live link.
set -e
L=/home/selwyn/Downloads/Mika-Transformation-Lab; P=/home/selwyn/Downloads/Mika-Godot-Dev-Anime
G=/home/selwyn/Downloads/Godot-Engine/Godot_v4.7.2-stable_linux.x86_64
cd $L
blender -b -t 2 --python l1_v2/tools/v2_place.py 2>&1 | grep -E "PLACED|Traceback|Error"
blender -b -t 2 --python l1_v2/tools/v2_rig.py 2>&1 | grep -E "RIG DONE|springs|Traceback|Error"
cp l1_v2/fit/export/MikaCelestial_L1v2.vrm $P/assets/characters/mika/tests/
cd $P
flock -w 1800 ~/.cache/mika_qa/godot.lock timeout 900 $G --headless --path . --import -- --no-bridge \
  --save-path=user://test_import_l1v2.json --live-link=ws://127.0.0.1:9/test-none 2>&1 | grep -E "Import VRM|ERROR" | head
