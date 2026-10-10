# Asset sources & licenses

Every external asset in this project, where it came from, and its license. Machine-readable log with md5-verified file lists: `assets/ASSET_MANIFEST.jsonl`.

## Character

| Asset | Source | License / terms |
|---|---|---|
| `assets/characters/mika/Mika.vrm` | Copy of `~/Documents/Mika-Live/frontend/vr-agent/assets/avatars/Mika.vrm` (= `Mika_World_Edition_v1.vrm`), the user's own VRoid avatar | VRM 1.0 meta: `modification: allowModification`, `allowRedistribution: true`, **`commercialUsage: personalNonProfit`**, `avatarPermission: onlyAuthor`. Do **not** assume it is cleared for monetised/commercial use — that is the creator's setting to review. |

## Animation (Adobe Mixamo — not redistributed)

| Asset | Source | Terms |
|---|---|---|
| `assets/animations/mixamo/*.fbx` (13, incl. Sitting Idle for seats) | user's Mixamo downloads in `~/Downloads` | Usable in projects; raw files must not be redistributed → git-ignored; `tools/setup_local_assets.sh` re-copies them. |
| `assets/animations/mixamo_sword/*.fbx` (51 + 3) | `~/Downloads/Great Sword Pack.zip` and standalone Great Sword files | same; git-ignored. Selection/analysis: `docs/SWORD_ANIMATIONS.md`. |

## Plugins

| Plugin | Source | License |
|---|---|---|
| `addons/vrm`, `addons/Godot-MToon-Shader` | https://github.com/V-Sekai/godot-vrm @ `e15199f9` (Godot 4.7 fixes) | MIT. **Local modification:** `mtoon_common.gdshaderinc` gains an opt-in `_Vrm1Lighting` mode (see `docs/FACE_SHADING_FIX.md`). |

## Environment (all CC0)

| Asset | Kind | Res | Source page | License |
|---|---|---|---|---|
| `belfast_sunset_puresky` | hdri | 2k | https://polyhaven.com/a/belfast_sunset_puresky | CC0 1.0 (https://polyhaven.com/license) |
| `kloppenheim_02` | hdri | 2k | https://polyhaven.com/a/kloppenheim_02 | CC0 1.0 (https://polyhaven.com/license) |
| `kloppenheim_06_puresky` | hdri | 2k | https://polyhaven.com/a/kloppenheim_06_puresky | CC0 1.0 (https://polyhaven.com/license) |
| `nature_reserve_forest` | hdri | 2k | https://polyhaven.com/a/nature_reserve_forest | CC0 1.0 (https://polyhaven.com/license) |
| `Barrel_01` | model | 1k | https://polyhaven.com/a/Barrel_01 | CC0 1.0 (https://polyhaven.com/license) |
| `Chandelier_02` | model | 1k | https://polyhaven.com/a/Chandelier_02 | CC0 1.0 (https://polyhaven.com/license) |
| `GothicCabinet_01` | model | 1k | https://polyhaven.com/a/GothicCabinet_01 | CC0 1.0 (https://polyhaven.com/license) |
| `Lantern_01` | model | 1k | https://polyhaven.com/a/Lantern_01 | CC0 1.0 (https://polyhaven.com/license) |
| `bench_vice_01` | model | 1k | https://polyhaven.com/a/bench_vice_01 | CC0 1.0 (https://polyhaven.com/license) |
| `book_encyclopedia_set_01` | model | 1k | https://polyhaven.com/a/book_encyclopedia_set_01 | CC0 1.0 (https://polyhaven.com/license) |
| `boulder_01` | model | 1k | https://polyhaven.com/a/boulder_01 | CC0 1.0 (https://polyhaven.com/license) |
| `brass_candleholders` | model | 1k | https://polyhaven.com/a/brass_candleholders | CC0 1.0 (https://polyhaven.com/license) |
| `brass_vase_01` | model | 1k | https://polyhaven.com/a/brass_vase_01 | CC0 1.0 (https://polyhaven.com/license) |
| `ceramic_vase_01` | model | 1k | https://polyhaven.com/a/ceramic_vase_01 | CC0 1.0 (https://polyhaven.com/license) |
| `chemistry_set` | model | 1k | https://polyhaven.com/a/chemistry_set | CC0 1.0 (https://polyhaven.com/license) |
| `cross_pein_hammer` | model | 1k | https://polyhaven.com/a/cross_pein_hammer | CC0 1.0 (https://polyhaven.com/license) |
| `dead_tree_trunk` | model | 1k | https://polyhaven.com/a/dead_tree_trunk | CC0 1.0 (https://polyhaven.com/license) |
| `dead_tree_trunk_02` | model | 1k | https://polyhaven.com/a/dead_tree_trunk_02 | CC0 1.0 (https://polyhaven.com/license) |
| `dry_branches_medium_01` | model | 1k | https://polyhaven.com/a/dry_branches_medium_01 | CC0 1.0 (https://polyhaven.com/license) |
| `fern_02` | model | 1k | https://polyhaven.com/a/fern_02 | CC0 1.0 (https://polyhaven.com/license) |
| `flower_empodium` | model | 1k | https://polyhaven.com/a/flower_empodium | CC0 1.0 (https://polyhaven.com/license) |
| `flower_gazania` | model | 1k | https://polyhaven.com/a/flower_gazania | CC0 1.0 (https://polyhaven.com/license) |
| `flower_ursinia` | model | 1k | https://polyhaven.com/a/flower_ursinia | CC0 1.0 (https://polyhaven.com/license) |
| `folding_wooden_stool` | model | 1k | https://polyhaven.com/a/folding_wooden_stool | CC0 1.0 (https://polyhaven.com/license) |
| `gothic_statue` | model | 1k | https://polyhaven.com/a/gothic_statue | CC0 1.0 (https://polyhaven.com/license) |
| `hand_plane_no4` | model | 1k | https://polyhaven.com/a/hand_plane_no4 | CC0 1.0 (https://polyhaven.com/license) |
| `handsaw_wood` | model | 1k | https://polyhaven.com/a/handsaw_wood | CC0 1.0 (https://polyhaven.com/license) |
| `hatchet` | model | 1k | https://polyhaven.com/a/hatchet | CC0 1.0 (https://polyhaven.com/license) |
| `lantern_chandelier_01` | model | 1k | https://polyhaven.com/a/lantern_chandelier_01 | CC0 1.0 (https://polyhaven.com/license) |
| `large_castle_door` | model | 1k | https://polyhaven.com/a/large_castle_door | CC0 1.0 (https://polyhaven.com/license) |
| `magnifying_glass_01` | model | 1k | https://polyhaven.com/a/magnifying_glass_01 | CC0 1.0 (https://polyhaven.com/license) |
| `moon_rock_01` | model | 1k | https://polyhaven.com/a/moon_rock_01 | CC0 1.0 (https://polyhaven.com/license) |
| `moon_rock_03` | model | 1k | https://polyhaven.com/a/moon_rock_03 | CC0 1.0 (https://polyhaven.com/license) |
| `moon_rock_05` | model | 1k | https://polyhaven.com/a/moon_rock_05 | CC0 1.0 (https://polyhaven.com/license) |
| `mountainside` | model | 1k | https://polyhaven.com/a/mountainside | CC0 1.0 (https://polyhaven.com/license) |
| `namaqualand_boulder_02` | model | 1k | https://polyhaven.com/a/namaqualand_boulder_02 | CC0 1.0 (https://polyhaven.com/license) |
| `namaqualand_cliff_01` | model | 1k | https://polyhaven.com/a/namaqualand_cliff_01 | CC0 1.0 (https://polyhaven.com/license) |
| `planter_box_01` | model | 1k | https://polyhaven.com/a/planter_box_01 | CC0 1.0 (https://polyhaven.com/license) |
| `potted_plant_01` | model | 1k | https://polyhaven.com/a/potted_plant_01 | CC0 1.0 (https://polyhaven.com/license) |
| `rock_face_01` | model | 1k | https://polyhaven.com/a/rock_face_01 | CC0 1.0 (https://polyhaven.com/license) |
| `rock_face_02` | model | 1k | https://polyhaven.com/a/rock_face_02 | CC0 1.0 (https://polyhaven.com/license) |
| `rock_moss_set_01` | model | 1k | https://polyhaven.com/a/rock_moss_set_01 | CC0 1.0 (https://polyhaven.com/license) |
| `rock_moss_set_02` | model | 1k | https://polyhaven.com/a/rock_moss_set_02 | CC0 1.0 (https://polyhaven.com/license) |
| `root_cluster_01` | model | 1k | https://polyhaven.com/a/root_cluster_01 | CC0 1.0 (https://polyhaven.com/license) |
| `shrub_02` | model | 1k | https://polyhaven.com/a/shrub_02 | CC0 1.0 (https://polyhaven.com/license) |
| `shrub_03` | model | 1k | https://polyhaven.com/a/shrub_03 | CC0 1.0 (https://polyhaven.com/license) |
| `stone_fire_pit` | model | 1k | https://polyhaven.com/a/stone_fire_pit | CC0 1.0 (https://polyhaven.com/license) |
| `treasure_chest` | model | 1k | https://polyhaven.com/a/treasure_chest | CC0 1.0 (https://polyhaven.com/license) |
| `tree_stump_01` | model | 1k | https://polyhaven.com/a/tree_stump_01 | CC0 1.0 (https://polyhaven.com/license) |
| `tree_stump_02` | model | 1k | https://polyhaven.com/a/tree_stump_02 | CC0 1.0 (https://polyhaven.com/license) |
| `wicker_basket_01` | model | 1k | https://polyhaven.com/a/wicker_basket_01 | CC0 1.0 (https://polyhaven.com/license) |
| `wooden_barrels_01` | model | 1k | https://polyhaven.com/a/wooden_barrels_01 | CC0 1.0 (https://polyhaven.com/license) |
| `wooden_bucket_01` | model | 1k | https://polyhaven.com/a/wooden_bucket_01 | CC0 1.0 (https://polyhaven.com/license) |
| `wooden_crate_01` | model | 1k | https://polyhaven.com/a/wooden_crate_01 | CC0 1.0 (https://polyhaven.com/license) |
| `bark_brown_02` | texture | 1k | https://polyhaven.com/a/bark_brown_02 | CC0 1.0 (https://polyhaven.com/license) |
| `castle_wall_slates` | texture | 1k | https://polyhaven.com/a/castle_wall_slates | CC0 1.0 (https://polyhaven.com/license) |
| `cliff_side` | texture | 2k | https://polyhaven.com/a/cliff_side | CC0 1.0 (https://polyhaven.com/license) |
| `cobblestone_floor_08` | texture | 2k | https://polyhaven.com/a/cobblestone_floor_08 | CC0 1.0 (https://polyhaven.com/license) |
| `dark_wooden_planks` | texture | 1k | https://polyhaven.com/a/dark_wooden_planks | CC0 1.0 (https://polyhaven.com/license) |
| `fabric_pattern_05` | texture | 1k | https://polyhaven.com/a/fabric_pattern_05 | CC0 1.0 (https://polyhaven.com/license) |
| `forrest_ground_01` | texture | 1k | https://polyhaven.com/a/forrest_ground_01 | CC0 1.0 (https://polyhaven.com/license) |
| `herringbone_parquet` | texture | 1k | https://polyhaven.com/a/herringbone_parquet | CC0 1.0 (https://polyhaven.com/license) |
| `large_grey_tiles` | texture | 1k | https://polyhaven.com/a/large_grey_tiles | CC0 1.0 (https://polyhaven.com/license) |
| `leafy_grass` | texture | 2k | https://polyhaven.com/a/leafy_grass | CC0 1.0 (https://polyhaven.com/license) |
| `marble_01` | texture | 1k | https://polyhaven.com/a/marble_01 | CC0 1.0 (https://polyhaven.com/license) |
| `monastery_stone_floor` | texture | 2k | https://polyhaven.com/a/monastery_stone_floor | CC0 1.0 (https://polyhaven.com/license) |
| `mossy_rock` | texture | 2k | https://polyhaven.com/a/mossy_rock | CC0 1.0 (https://polyhaven.com/license) |
| `plastered_wall_02` | texture | 1k | https://polyhaven.com/a/plastered_wall_02 | CC0 1.0 (https://polyhaven.com/license) |
| `rock_wall_10` | texture | 1k | https://polyhaven.com/a/rock_wall_10 | CC0 1.0 (https://polyhaven.com/license) |
| `rocky_terrain_02` | texture | 1k | https://polyhaven.com/a/rocky_terrain_02 | CC0 1.0 (https://polyhaven.com/license) |
| `roof_slates_02` | texture | 1k | https://polyhaven.com/a/roof_slates_02 | CC0 1.0 (https://polyhaven.com/license) |
| `snow_02` | texture | 1k | https://polyhaven.com/a/snow_02 | CC0 1.0 (https://polyhaven.com/license) |
| `sparse_grass` | texture | 1k | https://polyhaven.com/a/sparse_grass | CC0 1.0 (https://polyhaven.com/license) |
| `stony_dirt_path` | texture | 1k | https://polyhaven.com/a/stony_dirt_path | CC0 1.0 (https://polyhaven.com/license) |
| `wood_table_001` | texture | 1k | https://polyhaven.com/a/wood_table_001 | CC0 1.0 (https://polyhaven.com/license) |
| `jacaranda_tree` | model-derivative |  | https://polyhaven.com/a/jacaranda_tree | CC0 1.0 (https://polyhaven.com/license) |
| `Moss002` | texture | 1K-JPG | https://ambientcg.com/view?id=Moss002 | CC0 1.0 (https://docs.ambientcg.com/license/) |

### Derived / original assets

* `assets/trees/broadleaf_tree_near.glb` / `_far.glb`: LODs of Poly Haven `jacaranda_tree` (CC0) via `tools/foliage_thin.py` + `tools/blender/decimate_bark.py`.
* `assets/architecture/sanctuary_architecture.glb`: original (`tools/blender/build_sanctuary_architecture.py`).
* All other region architecture (houses, towers, temple, academy, vault, bridge, cave shells, crystals, telescope, armillary sphere, magical blade) is original geometry generated in code (`scripts/world/kit*.gd`, `scripts/areas/*.gd`).

## References only (not shipped)

* The 8 reference images in `~/Downloads` (Ancient Forest Ruins, Mystical Grove, Cinematic Fantasy Village, Crystal Caverns, Enchanted Waterfall Valley, Celestial Mountain Temple, Grand Arcane Library, Forgotten Runic Ruins) were used as art direction only; no pixels or textures from them are in the project.
* Godot demo projects (MIT) — patterns only (visibility ranges/HLOD, volumetric fog, graphics settings). GDQuest demos: code MIT, **art CC-BY-NC-SA** → no GDQuest art used.

No paid assets, no assets extracted from commercial games, no generated images.

### Arcane Sanctuary mini-region (2026-10 pass)
No new downloads. The sub-areas reuse the CC0 Poly Haven models/textures listed above (flowers, shrub_03, vases,
candle holders, stool, lantern, book set, mossy rocks) plus procedural geometry (masonry, lathe columns, stairs, pond,
rune targets, light shafts, birds/butterflies/fireflies) written in `scripts/world/sanctuary_expansion.gd`,
`scripts/world/ambient_life.gd`, `shaders/light_shaft.gdshader`, `shaders/ambient_creature.gdshader`.
The only new animation is Mixamo "Sitting Idle" (local only, git-ignored, re-copied by `tools/setup_local_assets.sh`).
