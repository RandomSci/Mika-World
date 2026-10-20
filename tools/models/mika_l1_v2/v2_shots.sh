#!/bin/bash
# Mika L1 outfit v2: the look lab's six shots of the current outfit (old) or the v2 test build (new) in one light.
#   l1_v2/tools/v2_shots.sh old|new day|night
L=/home/selwyn/Downloads/Mika-Transformation-Lab; R=$L/l1_v2/godot
if [ "$1" = new ]; then
  X="--avatar=res://assets/characters/mika/tests/MikaCelestial_L1v2.vrm --maps=$L/l1_v2/look/maps --l1tex=$L/l1_v2/look/flat"
fi
bash $L/l1_flat/work/gpu_render.sh $R/$1_$2 res://scenes/tests/mika_look_lab.tscn --light=$2 --look=proto $X 2>&1 | grep -E "exit|ERROR|DONE"
