# Asset sources — Milestone H (two mages, combat, transformations)

Everything added in this milestone is either the developer's own work, or original procedural content
made for Mika World. **No third-party asset was downloaded.** The existing project assets keep the
licences documented in `ASSETS.md`.

| Asset | Source | Licence / usage notes | Placed at |
|---|---|---|---|
| Mika Level 10 form | Developer's own VRoid export `MikaV3_LEVEL10_.vrm` (`~/Documents/Open-LLM-VTuber/avatar-authoring/mika_vroid/final/`, copied — original untouched) | VRM 1.0 meta: author "pixiv VRoid Project" (VRoid default), licence `vrm.dev/licenses/1.0`, **commercial usage: personalNonProfit** | `assets/characters/mika/forms/Mika_Level10.vrm` |
| Luna base form | Developer's own VRoid export `Luna_V3_LVL1.vrm` (same folder, copied) | VRM 1.0 meta: author "Selwyn", **personalNonProfit** | `assets/characters/luna/forms/Luna_Level01.vrm` |
| Luna Level 10 form | Developer's own VRoid export `Luna_level_10.vrm` (same folder, copied) | VRM 1.0 meta: author "Selwyn", **personalNonProfit** | `assets/characters/luna/forms/Luna_Level10.vrm` |
| Creatures (Gloomwisp, Thornback, Hollow Sentinel) | Original procedural meshes built in code (`scripts/combat/monster.gd`) | Original to Mika World | — |
| Loot pickups | Original procedural meshes (`scripts/combat/loot_pickup.gd`) | Original | — |
| Shaders `shockwave`, `umbral_core`, `aura_column`, `orbit_ring` | Written for this project | Original | `shaders/magic/` |
| Umbral Lance / combat / creature / loot / level-up / fusion sounds | Synthesised by `tools/audio/synth_milestone_h.py` (numpy; no samples) | Original | `assets/audio/synth/*.ogg` |
| Transformation music cues (Mika: D-lydian "bloom"; Luna: C-phrygian "gilded eclipse"; full + short) | Composed procedurally in `tools/audio/synth_milestone_h.py`; motifs written for Mika World; reveal hit lands on the flash time in `data/transformations.json` | Original; no existing melody used | `assets/audio/synth/transform_*.ogg` |
| Luna's voice | Local Kokoro-82M blend `af_kore:0.6,af_sky:0.4` via the existing DEV voice service (models read from `~/Documents/Mika-Live/models/kokoro`, never modified) | Kokoro-82M is Apache-2.0 | `scripts/audio/voice_service.gd` (VOICES) |
| Incantations (Latin) | Written for this project: "Umbra, perfora!", "Flos lucis, aperi te!", "Umbra aurea, surge mecum!" | Original | `data/spells.json`, `data/transformations.json`, `data/pronunciations.json` |

## Inspirations (tone only)
The brief named a magical-girl series, a cultivation-style progression novel and *The Great Mage Returns
After 4000 Years* as **tonal** references. Nothing from them was copied: the transformation language (Aether
Orbit sigil, aura column, hand light, lift, flash, orbit ring, finishing pose), the Ten Aether Orbits, the
creatures, the spells and all music are original designs.

## Sources inspected but not used
Mixamo, VRoid Hub, Poly Haven, Quaternius, OpenGameArt and Kenney were **not** downloaded from in this
milestone: procedural creatures and original audio covered the needs without new licences or project bloat.
Hit-reaction / dodge animations would be the most useful future Mixamo addition (raw Mixamo FBX stay
local-only, as documented in `ASSETS.md`).

## Open licence question for the developer
All three new VRMs carry `commercialUsage: personalNonProfit` in their VRM metadata (VRoid's default).
If the channel is monetised, re-export them from VRoid Studio with the intended licence settings.


# Milestone I additions

| Asset | Source | Licence / usage notes | Placed at |
|---|---|---|---|
| ミカの魔法世界！ (song) | Developer's file `~/Downloads/ミカの魔法世界！.mp3` (copied, original untouched). Embedded tags: "made with suno", created 2026-10-12 | **Rights unconfirmed**: depends on the Suno plan it was generated under. Kept local (git-ignored), not uploaded anywhere | `assets/audio/music/library/mika_magical_world/original.mp3` |
| Song timing / metadata | Measured by `tools/audio/analyze_song.py`; facts from the file's tags | Derived data | `.../metadata.json`, `.../timing.json` |
| Mixamo clips: Step / Snake / Booty Hip Hop Dance, Belly Dance, Stand To Sit, Sit To Stand, Lying Down, Picking Up (floor / chest), Putting Down, Pointing, Arm / Neck Stretching, Waking | Developer's Mixamo downloads in `~/Downloads` (copied) | Adobe Mixamo: use in projects; raw FBX not redistributed (git-ignored; `tools/setup_local_assets.sh` re-copies) | `assets/animations/mixamo/` |
| Gatherable plants (Moonpetal, Embercap) | Procedural meshes in `scripts/world/gather_node.gd` | Original | — |

Not used: Macarena / YMCA / Chicken dance clips (recognisable meme choreography, not suited to original performances).


# Milestone J additions

| Asset | Source | Licence / usage notes | Placed at |
|---|---|---|---|
| Emberwing creature (mesh, rig, 5 clips: Flying, Attack, Attack2, Hit, Death) | Quaternius **LowPoly Animated Monsters** — "Dragon" — https://quaternius.itch.io/lowpoly-animated-monsters (free download, 2026-10-13); listed as CC0 at https://quaternius.com/packs/animatedmonster.html | **CC0 1.0** (public domain dedication; no attribution required — credited anyway). Converted FBX → GLB in Blender (actions as NLA tracks); recoloured in-game (ember palette) | `assets/creatures/emberwing/emberwing.glb` (+ `LICENSE_CC0.txt`) |
| Hollow Sentinel (articulated stone golem) | **Original** — modelled by script in Blender (`tools/models/build_sentinel.py`): rigid rune-stones on named joint pivots; procedural stone material `shaders/creature_stone.gdshader`; animation is authored joint poses + springs in `scripts/combat/sentinel_rig.gd` | Original | `assets/creatures/sentinel/hollow_sentinel.glb` |
| Combat animation clips: Roll, Hit_Chest, Hit_Head, Hit_Knockback, Spell_Simple_Enter / Idle / Shoot / Exit, Sword_Block, Idle_Shield(+Break), Yes, Idle_FoldArms, Jump_Start/Land, Sprint | Quaternius **Universal Animation Library** 1 & 2 (Standard), https://quaternius.itch.io/universal-animation-library and …-2 (free downloads, 2026-10-13); also listed on store.godotengine.org | **CC0 1.0** (the packs' own `License.txt`, copied to `assets/animations/ual/LICENSE_UAL_CC0.txt`). Only the 16 needed clips were extracted (no mannequin mesh) into one 1 MB GLB; retargeted onto the VRMs through `assets/animations/ual_bonemap.tres` (UE-mannequin bone names → Godot humanoid profile) | `assets/animations/ual/ual_combat.glb` |
| All new / replaced sound (spell layers, impacts, cues, gather hums, Level 10 awakening scores) | **Original** procedural synthesis: `tools/audio/synth_milestone_j.py` (originals backed up to `.backups/audio_pre_milestone_j/`) | Original | `assets/audio/synth/` |
| Mika's and Luna's speaking voices | Microsoft Edge neural voices **en-US-AvaNeural** (Mika, +25 Hz, +5 %) and **ja-JP-NanamiNeural** (Luna, +30 Hz, +5 %) as confirmed by the developer in Mika-Voice-Lab, generated at runtime through the `edge-tts` package (7.2.8, LGPL-3.0, local venv `.venv-voice`, not committed) | **Usage terms not confirmed for a monetised stream**: `edge-tts` uses the consumer "Read Aloud" endpoint; Microsoft's licensed route for these exact voices is Azure AI Speech. Text of new lines is sent to Microsoft's service; audio is cached locally (`~/.cache/mika-godot-dev/edge_voice`), nothing is committed. Kokoro remains the automatic fallback | `tools/voice/edge_service.py`, `data/voices.json` |
| Laugh / giggle reactions | Rendered at runtime in each mage's own Edge voice from short non-word syllables (`data/voices.json` → reactions) | As above; **candidates for the developer to audition** | (runtime cache only) |

## Inspected but not used (Milestone J)
* **Quaternius Ultimate Monsters** (CC0, 50 animated monsters, https://quaternius.com/packs/ultimatemonsters.html):
  the best visual match (incl. a golem, ghost and mushroom king), but its only download is a Google Drive folder
  that returned "Quota exceeded" on every attempt today. Worth retrying later; nothing from it is in the project.
* **Quaternius Cute Animated Monsters** (CC0): same Drive-hosted download; not obtained.
* **Quaternius Bestiary Dungeon Monsters Kit**: licensed under Quaternius' own "QAL" licence with paid source
  tiers and humanoid weapon-wielding enemies — not CC0; not used.
* **LowPoly Animated Monsters** Bat / Skeleton / Slime: CC0 and downloaded with the Dragon, but older flat style
  (Slime/Skeleton read as cartoon filler next to the VRMs) — not imported.
* **Sketchfab** animated-monster listings: per-model licences vary (many CC-BY / editorial / paid) and downloads
  need an account — not used. **OpenGameArt**: only CC0 *laugh* packs of other people's voices were found;
  rejected because they would not match Mika's or Luna's voice.
* **Mixamo**: needs an Adobe login (not available to the agent); the developer's existing Mixamo clips were
  reused. No new Mixamo downloads.


# Milestone K additions (Whispering Woods)

| Asset | Source | Licence / usage notes | Placed at |
|---|---|---|---|
| Stylized trees (Common, Twisted, Pine, Dead), bushes, ferns, giant leafy plants, clover, flowers, petals, grass tufts, mushrooms, rocks, pebbles, rock-path stones — 68 models + their textures | Quaternius **Stylized Nature MegaKit — FREE edition** (68 of the 116 models), https://quaternius.itch.io/stylized-nature-megakit (free download, 2026-10-14); also https://quaternius.com | **CC0 1.0** (the pack's own `License.txt`, copied to `assets/nature/snm/LICENSE_CC0.txt`; no attribution required — credited anyway). Textures downscaled to ≤1024 px. **The pack's materials are not used**: every surface is re-shaded by our own shaders (`shaders/nature/`) and placed by script | `assets/nature/snm/` |
| Rest / quiet-scene clips: Sitting_Enter / Idle / Talking / Exit (floor sitting), LayToIdle (held at frame 0 = lying; reversed = lying down), Crouch_Idle, Idle_Talking, Fixing_Kneeling | Quaternius **Universal Animation Library** 2 (Standard), https://quaternius.itch.io/universal-animation-library-2 (free download, 2026-10-14) | **CC0 1.0** (same licence file as the combat set, `assets/animations/ual/LICENSE_UAL_CC0.txt`). Only the 8 clips were extracted (no mannequin mesh) into one GLB; retargeted through `assets/animations/ual_bonemap.tres` | `assets/animations/ual/ual_rest.glb` |
| Stylized shaders: foliage (spherised normals, crown gradient, translucency, wind), grass, bark, rock, terrain, stone, water, waterfall, foam, light shafts, painted sky | **Original** (Milestone K) | Original | `shaders/nature/` |
| Spell-family shaders (V3 Part XIII): spiral ribbon, leaf wreath, umbral rift, gilded mirror, root seam; the root cages, leaf rings and helix ribbons are generated geometry (the kit's leaf atlas and bark texture, re-shaded) | **Original** (Milestone K5/K6) | Original | `shaders/magic/spiral_ribbon.gdshader`, `leaf_ring.gdshader`, `umbral_rift.gdshader`, `gilded_mirror.gdshader`, `root_seam.gdshader`; `scripts/magic/sylvan_spell.gd`, `umbral_spell.gd`, `ward.gd` |
| Spell-family sounds: the `nature` element set (7 layers), wards, roots, rifts (17 files) | **Original** synthesis, no samples (`tools/audio/synth_v3_magic.py`, deterministic; 0.000 on `bell_check`) | Original | `assets/audio/synth/spell_nature_*.ogg`, `ward_*.ogg`, `roots_*.ogg`, `rift_*.ogg` |
| Ruins, stairway, arches, bridge, viewpoint terrace, waymarker, lantern | **Original** — built block by block at load time (`scripts/world/stone_builder.gd`, `scripts/areas/whispering_woods_landmarks.gd`) | Original | (generated) |
| Terrain grain textures `forrest_ground_01`, `rock_wall_10`, `leafy_grass` | Poly Haven (already in the project since Milestone H) | CC0 — used only for luminance detail under painted colours | `assets/polyhaven/textures/` |

The ten environment reference images supplied by the developer were used **only as art direction** (read, never
imported, never shipped). The Woods borrow moods and motifs from them (an arched bridge below a waterfall, a
stairway climbing under ruined arches, a gate in overgrown walls, fireflies over a pond) but no imagery.


# Milestone K6 additions (V3 Part X — Oriel, the Phoenix)

| Asset | Source | Licence / usage notes | Placed at |
|---|---|---|---|
| The Phoenix, true form (rigged, skinned, 25 authored clips) | **Original** — generated from nothing by `tools/models/build_phoenix.py` (Blender 4.2, headless; feathers, armature, poses and clips are all code) | Original to Mika World | `assets/creatures/phoenix/phoenix_true.glb` |
| The Phoenix, human form (rigged, skinned, humanoid-profile skeleton) | **Original** — `tools/models/build_phoenix_humanoid.py` (Blender's Skin modifier over a scripted stick figure; garments, hair, ornaments are code) | Original | `assets/characters/phoenix/phoenix_humanoid.glb` |
| Feather atlas, iris, fabric detail | **Original** — drawn procedurally by `tools/models/phoenix_textures.py` (numpy) | Original | `assets/creatures/phoenix/feather_atlas.png`, `iris.png`, `fabric.png` |
| Painted face frames (eyes ×6, mouth ×5) | **Original** — `tools/models/phoenix_face.py` (numpy) | Original | `assets/characters/phoenix/face_eyes.png`, `face_mouth.png` |
| Shaders: feather, feather card (particles), fire core, face card | **Original** | Original | `shaders/phoenix/` |
| Sounds: wing beat, wing fold, land, takeoff, cry, ember loop, flare cast/impact, transformation (short, long), reform (11 files) | **Original** synthesis, no samples (`tools/audio/synth_phoenix.py`; all 0.000 on `bell_check`) | Original | `assets/audio/synth/phoenix_*.ogg` |
| Oriel's human body (visual pass 2): **Zahra** VRM | The developer's own avatar from the Character Lab (`~/Downloads/Mika-New-Character-Lab/assets/characters/Zahra_DesertDancer.vrm`, VRM meta author: the developer), **copied** at the developer's request (source untouched). The file is used unmodified (its meta marks modification prohibited / no redistribution for third parties); all restyling is runtime material overrides | The developer's own asset; keep it out of any public redistribution of the project | `assets/characters/phoenix/Zahra_DesertDancer.vrm` |
| Oriel's restyle textures (hood, veil, top, collar, skirt, hair, iris, body arm-silk) | Derived by script from Zahra's own textures (`tools/textures/oriel_zahra_recolor.py`, numpy recolour) | Derivative of the developer's asset | `assets/characters/phoenix/oriel_zahra_tex/` |
| MToon reveal include | Generated by `tools/shaders/make_mtoon_reveal.py` from `addons/Godot-MToon-Shader/mtoon_common.gdshaderinc` (MIT, V-Sekai contributors / Masataka SUMI) with Oriel's reveal injected; the addon is not modified | MIT (attribution kept in the file header) | `shaders/phoenix/mtoon_reveal.gdshaderinc` |
| Phoenix pass-2 shaders: flame tongues, aura halo, fire/spark sprites, reveal mask, light-body pass, flame ribbon | **Original** | Original | `shaders/phoenix/` |
| Phoenix pass-2 sounds: nova charge / release / impact; re-timed transformation (long 10.4 s, short 4.2 s) and reform (9 s) | **Original** synthesis (`tools/audio/synth_phoenix.py`) | Original | `assets/audio/synth/phoenix_*.ogg` |
| Simulated fire, explosion, burst, smoke and fire-tornado flipbooks (cinematic pass) | **Original** — Blender 4.2 Mantaflow gas simulations rendered in Cycles by `tools/vfx/fire_flipbooks.py`, packed by `tools/vfx/pack_flipbooks.py` (fire light / lit smoke / coverage layers) | Original | `assets/vfx/fire/*_fire.png`, `*_smoke.png`, `flipbooks.json` |
| Wind-blown leaf particles | ambientCG **LeafSet009** scanned leaves, cut into a 3×2 atlas by `tools/textures/leaf_particles.py` | CC0 1.0 (ambientcg.com) | `assets/nature/real/leaf_particles.png` |
| Cinematic-pass shaders: flipbook fire/smoke, heat haze / shock ring, gusts (plant bending), tumbling leaf, scanned-plant sway | **Original** | Original | `shaders/vfx/`, `shaders/nature/gust.gdshaderinc`, `leaf_particle.gdshader`, `shaders/real/real_plant.gdshader` |
| Phoenix cinematic sounds (wing gust, nova charge/release/impact, battle scream, burning-fire loop, ring of fire, fire tornado, transformation burst, sparkles, wings of fire) and the 11 s orchestral transformation cue | **ElevenLabs** Sound Effects v2 / Music v2.5 (instrumental), generated in the developer's own ElevenLabs workspace at the developer's request (flow `AB3RHA6aUSXccKmf8aq2`, 2026-10-14); best of four variations picked by measurement; mixed in stereo and mastered by `tools/audio/phoenix_cine_sfx.py` | Generated output under the developer's ElevenLabs plan terms; raw sources kept in `assets/audio/elevenlabs/phoenix/px_*.mp3` | `assets/audio/synth/phoenix_wing_gust.ogg`, `phoenix_nova_*.ogg`, `phoenix_scream.ogg`, `phoenix_fire_burn_loop.ogg`, `phoenix_tf_*.ogg` |
| Briar Imp creature (hero-scene monster): Imp model with its PBR textures | Quaternius **Bestiary – Dungeon Monsters Kit** (free Standard tier), https://quaternius.itch.io/bestiary-dungeon-monsters-kit (2026-10-14); clips baked from the Universal Animation Library 1 & 2 (CC0) by `tools/models/build_bestiary.py` | **Quaternius Asset License (QAL) v1.0** — free in games, no attribution required; the assets must not be redistributed on their own as assets | `assets/creatures/bestiary/imp.glb` |
| Her lines (text) | Written for this project (`data/phoenix.json`) | Original | `data/phoenix.json` |
| Her spoken lines (pre-rendered) | Google Gemini TTS, voice **Kore** (`gemini-2.5-flash-preview-tts`), generated once with the developer's own key during the verification runs (`tools/voice/ship_phoenix_lines.py`) | Generated output under the developer's Gemini API terms; no key or account data is in the files | `assets/voice/phoenix/*.wav` + `manifest.json` |
| Kokoro fallback blend `af_aoede:0.55,bf_lily:0.45` | Kokoro-82M (Apache-2.0), existing DEV service | Apache-2.0 | `data/voices.json` |
| Mossback creature (prominent Woods encounter): body, leaf cards, textures, rig and its own animations | OpenGameArt **"Forest Monster"** by Čestmír Dammer (CDmir), https://opengameart.org/content/forest-monster (archive `forest-monster_0.7z`, downloaded 2026-10-15); rebuilt by `tools/models/build_forest_monster.py` | **CC0** (page + bundled `Licenses.txt`) | `assets/creatures/mossback/mossback.glb` |
| Impact / fall / recovery and camp-life clips: Death01, Hit_Knockback, Idle_Shield_Break, Jump_Land, Slide_Exit, Roll, Crouch_Idle, Interact, Consume, PickUp_Table, Walk_Carry, Farm_Harvest, Chest_Open, TreeChopping, OverhandThrow, Walk, Idle_No, NinjaJump_Land | Quaternius **Universal Animation Library** 1 + 2 (Standard), https://quaternius.itch.io/universal-animation-library (+ `-2`) | **CC0 1.0** | `assets/animations/ual/ual_react.glb` (built by `tools/models/ual_extract.py`) |
| Voice auditions (Mika: Leda + Zephyr / Autonoe / Laomedeia; Luna: Achernar + Vindemiatrix / Aoede / Despina) | Google **Gemini TTS** (`gemini-3.8-flash-tts`), generated with the project's own key 2026-10-15 by `tools/voice/gemini_audition.py` | Google Gemini API terms (generated audio, the developer's account) | `assets/voice/auditions/` (not used in production) |
