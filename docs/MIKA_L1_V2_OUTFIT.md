# Mika Level 1 outfit v2 (test build, anime-proof only)

Selwyn's jobs of 2026-10-20:
1. The 9 Meshy parts of MIKA_L1_v2_parts, cleaned, baked to a face budget and fitted.
2. The rework with Mika_Trim_Kit_v1. The simple parts are rebuilt as clean geometry with designed trims, a pattern and decals.

Nothing in the stream build changes. Stage data, shared scripts, shaders and the VRM importer are untouched. The build sits beside the current outfit as a test asset.

## Where things are

| What | Path |
|---|---|
| Test VRM | `assets/characters/mika/tests/MikaCelestial_L1v2.vrm` |
| Its textures | `assets/characters/mika/tests/l1v2_tex/`. VRAM compressed (BPTC), high quality, mipmaps. A post import script on this VRM alone (`l1v2_post_import.gd`) points the outfit materials at them, because the VRM importer embeds textures uncompressed. |
| Test scene | `scenes/tests/mika_look_lab.tscn` with `--avatar=res://assets/characters/mika/tests/MikaCelestial_L1v2.vrm --maps=<lab>/l1_v2/look/maps --l1tex=<lab>/l1_v2/look/flat` |
| Test scene options | `--texcheck` checks the textures. `--trimshots` adds the four trim close ups. |
| Tools (copies, run from the lab) | `tools/models/mika_l1_v2/` |
| Lab | `~/Downloads/Mika-Transformation-Lab/l1_v2` |
| Sheets | `docs/screenshots/l1_v2/` |

## The rework (trim kit)

- **Meshy parts kept.** Only the bodice, the front bow and the brooch are Meshy. They are baked low poly (`v2_budget.sh`) and placed as before.
- **Bodice trims.** Engraved band strips (trim sheet band 3) run along the bodice's gold trims, on centre lines found by `v3_engrave.py`.
- **Built as clean geometry** (`v3_place.py`, like the rebuilt panel):

| Part | Build |
|---|---|
| Sash, collar | Closed bands of the star row (band 2). The sash wraps over the panel tops. |
| Underskirt | Flared, softly pleated, white with panel_pattern_tile, a filigree hem strip (band 1). |
| Panels | Six round the waist to mid calf, with a gap at the front. They overlap a little, odd ones on top. White pattern front, navy back. Filigree strips on both long edges and the slanted bottom, front and back. A filigree corner decal on each tip. |
| Sleeves | Long and flowing, hanging from the upper arm. White pattern outside, navy lining 0.4 mm inside on the same grid. Filigree outer hem, cloud embroidery (band 4) inner hem, an engraved gold cuff, a star decal near the hem. |
| Back bow | Knot, loops and two long tails of the cloud ribbon (band 4) on her hair. It replaces the Meshy back bow. |
| Decals | Opaque meshes cut to each ornament's outline, with no alpha. Filigree corners on the panel tips, a star on each sleeve, the crest on the back of the sash. |

- **Sleeve and panel layers.** The outside and the lining are one sided materials (`L1_v2_PatternOut`, `L1_v2_TrimOut`, `L1_v2_Lining`). With the same weights and grid, they can't cross, and the lining can't show through from outside.
- **Textures.** `v3_textures.py` builds them from the kit:
  - trim sheet at 4096 wide, the white gaps filled from each band's edge rows so mipmaps never pull white into a trim
  - pattern tile, about 16 cm per tile
  - decal atlas
  - look prototype ILMs
- **Compression.** Checked in game against the source pngs. No texel is off by more than 26 of 255. Compressed and uncompressed close ups look the same, so the trim sheet stays compressed.
- **Rig** (`v3_rig.py`, from v2_rig, itself from o12_rig):
  - torso weights on bodice, sash and collar
  - 12 underskirt chains, one chain per panel, bow tail and back ribbon chains
  - sleeve drape chains on the forearm, soft and heavy
  - decals follow the cloth under them
  - every spring starts clear of its colliders (0 rest penetrations)

## Face budget, everything counted

271,023 triangles.

| Part | Triangles |
|---|---|
| Bodice with its strips | 36,986 |
| Bow | 25,995 |
| Panels | 14,208 |
| Sleeves | 11,040 |
| Underskirt | 9,280 |
| Brooch | 7,995 |
| Decals | 3,532 |
| Sash | 2,048 |
| Collar | 1,536 |
| Back bow | 316 |
| Kept pieces (hair, shoes, bracelets, flower) | 146,865 |
| Body, face and blush | 11,222 |

## Known issues

- Hands raised. The long sleeves fall against her chest and open toward the camera, so their navy linings fill the close up, and inside the opening the white outside of the wrist tube shows.
- The crest on the back of the sash is under her long hair in most views.
- At the front, her right front panel's navy back shows through the gap below the underskirt.
