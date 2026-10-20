#!/bin/bash
# Mika L1 outfit v2: the look lab's six shots of the current outfit (old) or the v2 test build (new) in one light.
#   l1_v2/tools/v2_shots.sh old|new|newunc day|night [extra lab options]
# new: the build's own VRAM compressed outfit textures; newunc: the same bakes loaded uncompressed (A/B), into <light>_unc
L=/home/selwyn/Downloads/Mika-Transformation-Lab; R=$L/l1_v2/godot
W=$1; LT=$2; shift 2
OUTD=$R/${W}_$LT
case $W in
  new) X="--avatar=res://assets/characters/mika/tests/MikaCelestial_L1v2.vrm --maps=$L/l1_v2/look/maps --l1tex=$L/l1_v2/look/flat";;
  newunc) X="--avatar=res://assets/characters/mika/tests/MikaCelestial_L1v2.vrm --maps=$L/l1_v2/look/maps --l1tex=$L/l1_v2/look/flat_unc";;
esac
bash $L/l1_flat/work/gpu_render.sh $OUTD res://scenes/tests/mika_look_lab.tscn --light=$LT --look=proto $X "$@" 2>&1 | grep -E "exit|ERROR|DONE|texcheck"
