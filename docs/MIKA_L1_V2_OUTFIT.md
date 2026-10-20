# Mika Level 1 outfit v2 (test build, anime-proof only)

Selwyn's job of 2026-10-20: the 9 Meshy parts of MIKA_L1_v2_parts, cleaned, baked to a face budget, fitted on Mika
in the look lab test scene. Nothing in the stream build changes. Stage data, shared scripts and shaders are untouched.
The build sits beside the current outfit as a test asset.

## Where things are

| What | Path |
|---|---|
| Test VRM | `assets/characters/mika/tests/MikaCelestial_L1v2.vrm` |
| Test scene | `scenes/tests/mika_look_lab.tscn` with `--avatar=res://assets/characters/mika/tests/MikaCelestial_L1v2.vrm --maps=<lab>/l1_v2/look/maps --l1tex=<lab>/l1_v2/look/flat` |
| Tools (copies, run from the lab) | `tools/models/mika_l1_v2/` |
| Lab | `~/Downloads/Mika-Transformation-Lab/l1_v2` |
| Sheets | `docs/screenshots/l1_v2/` |

## Pipeline

1. **Clean** (`v2_clean.py`, `v2_build.py`, `v2_panel.py`).
   - Each Meshy part is split into flat palette colour materials, with no texture.
   - Faces that hold a colour border are refined to 3 texel edges, take the colour of their own texels, and get their border points smoothed.
   - The panel is rebuilt as a thin two sided sheet: white front, navy back, an even 17 mm gold trim.
   - Both peplum curls of the bodice are kept (Selwyn).
2. **Bake** (`v2_budget.sh`). The clean high poly is only the bake source.
   - `v2_lowpoly.py`: the Meshy shape is welded and decimated to the target.
   - `v2_uv.py`: xatlas UVs on one 4K page, packed with at least a 16 px gap and checked by `v2_uvcheck.py`.
   - `v2_bake_nearest.py`: every texel centre takes the colour of the nearest point on the high poly.
   - `v2_snap.py`: snaps to the 4 palette colours and fills the padding.
   - `v2_bakecheck.py`: an independent check of the bake.
   - The Cycles ray bake (`v2_bake.py`) was dropped. Rays along smoothed normals at creases and Meshy's sliver triangles left white combs in the gold.
3. **Fit** (`v2_fit.sh`).
   - `v2_place.py` follows the o10_place.py approach and library, starting from the placement the shipping L1 VRM was rigged from. Her hair, shoes, bracelets, hair flower and back bow are exactly as they ship.
   - `v2_rig.py` is a fork of o12_rig.py. The kept pieces rig with o12's own lines, and the v2 parts get their own sections.

## Face budget

The v2 outfit after duplicates is 264,309 triangles (limit 300k).

| Part | Triangles |
|---|---|
| Bodice | 35,996 |
| Underskirt | 31,991 |
| Sash | 28,000 |
| Bow | 25,995 |
| Collar | 23,990 |
| Brooch | 7,995 |
| Sleeve | 27,999 x 2 |
| Panel | 5,060 x 6 |
| Star | 2,998 x 8 |

The kept hair, shoes, bracelets, flower and back bow add 186,632 triangles, as they ship.

## Rig

- Bodice, sash and collar take the body's torso weights.
- The underskirt has 12 sector chains.
- Each of the 6 panels has one chain.
- The bow knot moves with the chest, and each bow tail has a chain. The brooch moves with the knot.
- The sleeves blend from upper arm to forearm over a wide window round the elbow. Four drape chains hang from the forearm, and the weights are shared along lines running straight out from the arm, so the white shell and the navy lining never cross.
- The stars take the weights of the cloth under them.
- Skirt and panel joints that started inside the hip and thigh colliders were moved out. The 5 rest penetrations left are hair joints, the same as in the shipping build.
- Every v2 part is two sided.

## Known issues

- Folded arm: the right bell sleeve creases at the inside of the elbow when the forearm folds across the waist.
- Bell sleeves are large in the raised hands poses, as the part's shape is a wide bell.
- The underskirt is 50 cm at 4K, about 3.2 texels per mm. Its gold hem shows texel steps in close ups.
- VRAM: seven 4K base colours. Compress them before this goes near the stream.
