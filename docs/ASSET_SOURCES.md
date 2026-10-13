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
