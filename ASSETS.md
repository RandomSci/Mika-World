# Asset sources & licenses

Every external asset in this project, where it came from, and its license. Machine-readable log: `assets/ASSET_MANIFEST.jsonl` (each download md5-verified against the source API).

## Character

| Asset | Source | License / terms |
|---|---|---|
| `assets/characters/mika/Mika.vrm` | Copied from `~/Documents/Mika-Live/frontend/vr-agent/assets/avatars/Mika.vrm` (= `Mika_World_Edition_v1.vrm`, md5 `a4af8650…`), the user's own VRoid avatar | VRM 1.0 meta: author "Mika", `modification: allowModification`, `allowRedistribution: true`, `commercialUsage: personalNonProfit`, `avatarPermission: onlyAuthor`. Note the **personalNonProfit** flag if the stream is monetized: that's the creator's own setting and can be changed in VRoid. |

## Animation

| Asset | Source | License / terms |
|---|---|---|
| `assets/animations/mixamo/*.fbx` (12 clips) | Copies of the user's lawfully downloaded Adobe Mixamo files in `~/Downloads` | Mixamo FAQ: usable in commercial creative projects; raw files must **not** be redistributed as a standalone pack. They're git-ignored; `tools/setup_local_assets.sh` re-copies them. Import/retarget settings (`.fbx.import`, `mixamo_bonemap.tres`) are tracked. |

## Plugins

| Plugin | Source | License |
|---|---|---|
| `addons/vrm`, `addons/Godot-MToon-Shader` | https://github.com/V-Sekai/godot-vrm @ commit `e15199f9` (2026-07-08, "Update .import files for Godot 4.7"; the v2.1.0 tag predates the 4.7 fixes) | MIT (see each `LICENSE`) |

## Environment (CC0)

| Asset | Kind | Res | Source page | License |
|---|---|---|---|---|
| `kloppenheim_02` | hdri | 2k | https://polyhaven.com/a/kloppenheim_02 | CC0 1.0 (https://polyhaven.com/license) |
| `nature_reserve_forest` | hdri | 2k | https://polyhaven.com/a/nature_reserve_forest | CC0 1.0 (https://polyhaven.com/license) |
| `Lantern_01` | model | 1k | https://polyhaven.com/a/Lantern_01 | CC0 1.0 (https://polyhaven.com/license) |
| `book_encyclopedia_set_01` | model | 1k | https://polyhaven.com/a/book_encyclopedia_set_01 | CC0 1.0 (https://polyhaven.com/license) |
| `boulder_01` | model | 1k | https://polyhaven.com/a/boulder_01 | CC0 1.0 (https://polyhaven.com/license) |
| `brass_candleholders` | model | 1k | https://polyhaven.com/a/brass_candleholders | CC0 1.0 (https://polyhaven.com/license) |
| `dead_tree_trunk` | model | 1k | https://polyhaven.com/a/dead_tree_trunk | CC0 1.0 (https://polyhaven.com/license) |
| `dry_branches_medium_01` | model | 1k | https://polyhaven.com/a/dry_branches_medium_01 | CC0 1.0 (https://polyhaven.com/license) |
| `fern_02` | model | 1k | https://polyhaven.com/a/fern_02 | CC0 1.0 (https://polyhaven.com/license) |
| `gothic_statue` | model | 1k | https://polyhaven.com/a/gothic_statue | CC0 1.0 (https://polyhaven.com/license) |
| `namaqualand_boulder_02` | model | 1k | https://polyhaven.com/a/namaqualand_boulder_02 | CC0 1.0 (https://polyhaven.com/license) |
| `rock_face_01` | model | 1k | https://polyhaven.com/a/rock_face_01 | CC0 1.0 (https://polyhaven.com/license) |
| `rock_face_02` | model | 1k | https://polyhaven.com/a/rock_face_02 | CC0 1.0 (https://polyhaven.com/license) |
| `rock_moss_set_01` | model | 1k | https://polyhaven.com/a/rock_moss_set_01 | CC0 1.0 (https://polyhaven.com/license) |
| `rock_moss_set_02` | model | 1k | https://polyhaven.com/a/rock_moss_set_02 | CC0 1.0 (https://polyhaven.com/license) |
| `root_cluster_01` | model | 1k | https://polyhaven.com/a/root_cluster_01 | CC0 1.0 (https://polyhaven.com/license) |
| `shrub_02` | model | 1k | https://polyhaven.com/a/shrub_02 | CC0 1.0 (https://polyhaven.com/license) |
| `shrub_03` | model | 1k | https://polyhaven.com/a/shrub_03 | CC0 1.0 (https://polyhaven.com/license) |
| `tree_stump_01` | model | 1k | https://polyhaven.com/a/tree_stump_01 | CC0 1.0 (https://polyhaven.com/license) |
| `tree_stump_02` | model | 1k | https://polyhaven.com/a/tree_stump_02 | CC0 1.0 (https://polyhaven.com/license) |
| `forrest_ground_01` | texture | 1k | https://polyhaven.com/a/forrest_ground_01 | CC0 1.0 (https://polyhaven.com/license) |
| `leafy_grass` | texture | 2k | https://polyhaven.com/a/leafy_grass | CC0 1.0 (https://polyhaven.com/license) |
| `monastery_stone_floor` | texture | 2k | https://polyhaven.com/a/monastery_stone_floor | CC0 1.0 (https://polyhaven.com/license) |
| `mossy_rock` | texture | 2k | https://polyhaven.com/a/mossy_rock | CC0 1.0 (https://polyhaven.com/license) |
| `mossy_stone_wall` | texture | 1k | https://polyhaven.com/a/mossy_stone_wall | CC0 1.0 (https://polyhaven.com/license) |
| `sparse_grass` | texture | 1k | https://polyhaven.com/a/sparse_grass | CC0 1.0 (https://polyhaven.com/license) |
| `stony_dirt_path` | texture | 1k | https://polyhaven.com/a/stony_dirt_path | CC0 1.0 (https://polyhaven.com/license) |
| `jacaranda_tree` | model-derivative |  | https://polyhaven.com/a/jacaranda_tree | CC0 1.0 (https://polyhaven.com/license) |
| `Moss002` | texture | 1K-JPG | https://ambientcg.com/view?id=Moss002 | CC0 1.0 (https://docs.ambientcg.com/license/) |

### Derived assets

* `assets/trees/broadleaf_tree_near.glb` (≈151k tris) and `broadleaf_tree_far.glb` (≈44k tris): Poly Haven `jacaranda_tree` (CC0, 3.86M tris). Leaves thinned by whole island with `tools/foliage_thin.py` (near: keep 4.5% ×2.3 grow; far: 1.2% ×3.6), twig islands thinned (50% / 20%), then branches and trunk collapse-decimated in Blender (`tools/blender/decimate_bark.py`).
* `assets/architecture/sanctuary_architecture.glb`: original, generated by `tools/blender/build_sanctuary_architecture.py` (no third-party geometry).

## Code techniques referenced

* Godot official demos (MIT): `3d/visibility_ranges` (HLOD/visibility-range pattern, used for tree LODs), `3d/volumetric_fog`, `3d/graphics_settings` (profile switching), `3d/sky_shaders` (reviewed; its volumetric-cloud sky shader is documented as expensive, so the CC0 HDRI skies are used instead).
* GDQuest `godot-4-new-features`: code is MIT, but **art is CC-BY-NC-SA 4.0**, so no GDQuest textures or models are included.

No paid assets, no assets from commercial games, no generated images.
