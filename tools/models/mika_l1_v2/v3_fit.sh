#!/bin/bash
# Mika L1 outfit v2 rework (trim kit): build, rig and export, then into anime-proof as the test asset with its
# textures (VRAM compressed, high quality, mipmaps; set in their .import files) and import it. The Godot import goes
# through the shared GPU lock with a test save and a dead live link.
set -e
L=/home/selwyn/Downloads/Mika-Transformation-Lab; V=$L/l1_v2; P=/home/selwyn/Downloads/Mika-Godot-Dev-Anime
G=/home/selwyn/Downloads/Godot-Engine/Godot_v4.7.2-stable_linux.x86_64
T=$P/assets/characters/mika/tests/l1v2_tex
cd $L
blender -b -t 2 --python l1_v2/tools/v3_place.py 2>&1 | grep -E "PLACED|Traceback|Error"
blender -b -t 2 --python l1_v2/tools/v3_rig.py 2>&1 | grep -E "RIG DONE|springs|Traceback|Error"
cp $V/fit3/export/MikaCelestial_L1v2.vrm $P/assets/characters/mika/tests/
cp $V/tex3/trim.png $T/L1_v2_Trim_BaseColor.png
cp $V/tex3/pattern.png $T/L1_v2_Pattern_BaseColor.png
cp $V/tex3/decals.png $T/L1_v2_Decal_BaseColor.png
cp $V/bake/MIKA_L1_bodice_core.png $T/L1_v2_Bodice_BaseColor.png
cp $V/bake/MIKA_L1_bow.png $T/L1_v2_Bow_BaseColor.png
cp $V/bake/MIKA_L1_brooch.png $T/L1_v2_Brooch_BaseColor.png
for k in trim:Trim pattern:Pattern decals:Decal trim:TrimOut pattern:PatternOut trim:Lining; do cp $V/tex3/${k%%:*}_ILM.png $V/look/maps/L1_v2_${k##*:}_ILM.png; done
cd $P
flock -w 1800 ~/.cache/mika_qa/godot.lock timeout 900 $G --headless --path . --import -- --no-bridge \
  --save-path=user://test_import_l1v2.json --live-link=ws://127.0.0.1:9/test-none 2>&1 | grep -E "Import VRM|l1v2|ERROR" | head
