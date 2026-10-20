#!/bin/bash
# Mika L1 v2 parts, face budget (Selwyn 2026-10-20): one part from Meshy shape to baked game part and its sheet.
#   tools/v2_budget.sh <part> <target tris> <size cm> <zoom mm> [azimuths]
set -e
cd "$(dirname "$0")/.."
p=$1; tgt=$2; cm=$3; zm=$4; az=${5:-30,210}
PY="/home/selwyn/anaconda3/bin/python3 -I"
M=MIKA_L1_$p
mkdir -p low bake final renders_bake/$p review/bake
blender -b --factory-startup -P tools/v2_lowpoly.py -- src/MIKA_L1_v2_parts/$M.glb low $tgt 2>&1 | grep LOWPOLY
.venv/bin/python -I tools/v2_uv.py low/${M}_uv.npz low/${M}_xa.npz 8
$PY tools/v2_uvcheck.py low/${M}_xa.npz $cm
$PY tools/v2_bake_nearest.py low/${M}_xa.npz built_txf/$M.glb bake/${M}_raw.png $cm | grep BAKED
$PY tools/v2_snap.py bake/${M}_raw.png low/${M}_xa.npz bake/$M.png
$PY tools/v2_bakecheck.py clean_tx/$M.npz low/${M}_xa.npz bake/$M.png review/bake/${p}_check.png
blender -b --factory-startup -P tools/v2_final.py -- low/$M.blend low/${M}_xa.npz bake/$M.png final 2>&1 | grep FINAL
cp renders_txf/$p/targets.json renders_bake/$p/
tools/gpu_blender.sh -P tools/v2_render.py -- $p built_txf/$M.glb final/$M.glb renders_bake/$p --size-cm $cm --zoom-mm $zm --zooms 4 --azimuths $az --modes MATERIAL,TEXTURE 2>&1 | grep RENDERED
