# Credits

Third-party assets used by the env-test scenes (see also ASSETS.md and assets/ASSET_MANIFEST.jsonl).

## Starfall Hill (scenes/areas/starfall_hill.tscn)

- **Milky Way panorama** - `assets/sky/eso_milky_way/eso0932a_6000x3000.jpg`
  "The Milky Way panorama", ESO/S. Brunier - https://www.eso.org/public/images/eso0932a/
  License: Creative Commons Attribution 4.0 International (CC BY 4.0) - https://creativecommons.org/licenses/by/4.0/
  Used unmodified (the "large" 6000x3000 JPEG); rotated and brightened at runtime in shaders/starfall/milky_sky.gdshader.
- **Hero tree** - `assets/polyhaven/models/island_tree_01/` (glTF 2k)
  "Island Tree 01", Poly Haven - https://polyhaven.com/a/island_tree_01 - License: CC0 1.0
- Grass texture `leafy_grass` (Poly Haven, CC0), already in the project.
- Scanned ground plants and rock (Poly Haven, CC0 1.0, glTF 1k): `grass_medium_02`, `periwinkle_plant`, `fern_02`,
  `boulder_01` - https://polyhaven.com/a/<name> - in `assets/polyhaven/models/<name>/`.
- Ground textures `forrest_ground_01` and `forest_leaves_02` (Poly Haven, CC0), already in the project.

## Moonbloom Field (scenes/areas/moonbloom_field.tscn)

- `broadleaf_tree_near/far.glb` (Poly Haven `jacaranda_tree`, CC0) and `leafy_grass` (Poly Haven, CC0), already in the project.
- Character animation: UAL (Quaternius, CC0) and the owner's Mixamo clips (local only, not redistributed; see ASSETS.md).

## Anime cinematics (branch anime-proof, 2026-10-18)

Only CC0, MIT or CC BY (with credit) ships to the stream. Each item's license was read before use.

| What | Where in the project | Author / source | License |
|---|---|---|---|
| Phantom Camera v0.11.0.3 (Godot addon) | `addons/phantom_camera/` | Marcus Skov (ramokz) - https://github.com/ramokz/phantom-camera | MIT |
| Godot VFX Library | `addons/vfx_library/` | haowg - https://github.com/haowg/GODOT-VFX-LIBRARY | MIT |
| Hit FX Free (Stylized Hit FX) | `assets/BinbunVFX_Vol2/StylizedHitFX/` | Binbun3D - https://binbun3d.itch.io/hit-fx | CC0 1.0 |
| Electric FX Free | `assets/BinbunVFX_Vol2/ElectricFX/` | Binbun3D - https://binbun3d.itch.io/electric-fx | CC0 1.0 |
| Flame FX Free | `assets/BinbunVFX_Vol2/FlameFX/` | Binbun3D - https://binbun3d.itch.io/flame-fx | CC0 1.0 |
| Explosion FX Free | `assets/BinbunVFX_Vol2/ExplosionFX/` | Binbun3D - https://binbun3d.itch.io/explosion-fx | CC0 1.0 |
| Status FX Free | `assets/BinbunVFX_Vol2/StatusFX/` | Binbun3D - https://binbun3d.itch.io/status-fx | CC0 1.0 |
| Elemental Magic FX Free | `assets/BinbunVFX_Vol2/ElementalMagicFX/` | Binbun3D - https://binbun3d.itch.io/elemental-magic-fx | CC0 1.0 |
| Beam VFX Free | `assets/BinbunVFX/beam_vfx/` | Binbun3D - https://binbun3d.itch.io/beam-vfx | CC0 1.0 (itch.io page) |
| Portal VFX Free | `assets/BinbunVFX/portal_vfx/` | Binbun3D - https://binbun3d.itch.io/godot-portal-vfx | CC0 1.0 (itch.io page) |
| Modular Transitions shader | `shaders/anime/transitions/transition.gdshader` | Binbun3D - https://binbun3d.itch.io/godot-modular-transitions | CC0 1.0 (itch.io page) |
| Brackeys VFX Bundle v1 (particles, pre-drawn sheets; flipbooks converted TGA -> PNG) | `assets/vfx/brackeys/` | Brackeys, repackaging Picster, Kenney, Thomas Iché, CodeManu (see its LICENSE & CREDITS.txt) - https://brackeysgames.itch.io/brackeys-vfx-bundle | CC0 1.0 |
| Anime Style Speedlines (w/ or w/o distortion) | `shaders/anime/ref/speedlines_anime_distortion.gdshader` | ProfesorShader - https://godotshaders.com/?p=16778 | CC0 1.0 |
| Radial Speedlines | `shaders/anime/ref/radial_speedlines.gdshader` | Exuin - https://godotshaders.com/shader/radial-speedlines/ | CC0 1.0 |
| Distortion Speed Lines | `shaders/anime/ref/distortion_speed_lines.gdshader` | xxidbr9 - https://godotshaders.com/shader/distortion-speed-lines/ | MIT |
| Actionlines Comic Anime | `shaders/anime/ref/actionlines_comic_anime.gdshader` | EriNixie - https://godotshaders.com/shader/actionlines-comic-anime/ | CC0 1.0 |
| Toon shader | `shaders/anime/ref/toon_firerabbit.gdshader` | Firerabbit - https://godotshaders.com/shader/toon/ | MIT |

Technique references only (no code copied): Genshin Impact GDC 2021 talk (miHoYo), Kuro Games / Wuthering Waves Unreal
interview, NoiRC256/URPSimpleGenshinShaders (ported as technique: SDF face shadow, ramp, rim).

Tools (not shipped): Blender 4.2 with Rigify (built in, GPL), AnimAide (GPL), Wiggle 2 (GPL), BlendArMocap (GPL; MediaPipe
Apache 2.0). Tool licenses do not apply to the animation data we make with them.

Testing only, never shipped (non-commercial): GVHMR, WHAM, MoMask (SMPL / SMPL-X / AMASS-derived), Bandai Namco
Research Motion Dataset.
