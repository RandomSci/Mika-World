# Level-based appearances (2026-10-15)

**Celestial Mage (Mika)** and **Celestial Oracle (Luna)** are the Level 1–10 looks. They are not permanent: future
milestone forms (Levels 20…100) slot into the same registry later. No Level 20–100 models were made in this
milestone.

## How it works
* `data/appearances.json`: every mage has her own ordered stages:

  | stage | levels | requires | model |
  |---|---|---|---|
  | `celestial` / `oracle` | 1–10 | level ≥ 1 | `assets/characters/mika/stages/l01_celestial/MikaCelestial.vrm`, `assets/characters/luna/stages/l01_oracle/LunaOracle.vrm` |
  | `bloom` / `eclipse` | 10–19 | level ≥ 10 **and** the form taken | `assets/characters/*/forms/*_Level10.vrm` (unchanged) |
  | `l20` … `l100` | 20–100 | level ≥ N | *planned* (empty slots) |

  `archive` keeps the previous default looks (`Mika.vrm`, `Luna_Level01.vrm`) for rollback and comparison. They are
  never chosen automatically.
* **The existing Level 10 behaviour is untouched.** Reaching Level 10 unlocks the form, the full transformation
  cinematic plays once, and the form becomes her saved `progress.appearance`. The registry reads exactly that. Until
  the cinematic has played, she keeps the Level 1–10 look.
* `AppearanceRegistry` (`scripts/characters/appearance_registry.gd`) picks the highest-order **ready** stage whose
  requirements hold.
  * A planned or missing model is skipped, so a mage past the last available stage keeps her latest look.
  * If nothing is ready, she falls back to the first ready stage, then to the old `base_avatar`.
  * `TransformationDirector.avatar_for()` delegates to it, so spawning, area loads, the transformation and its
    preview all agree.
* **Progress is never touched by appearance.** Identity, memories, knowledge, skills, inventory, XP, relationships
  and journals live in the mage's mind; a swap only rebuilds the rig. `--mktest=appearances` checks knowledge, skill
  and XP counts before and after.
* **Developer preview:** `AppearanceRegistry.preview(who, stage_id)` (any stage or archived look), then
  `swap_avatar(avatar_for(who))`. It never touches progress; `preview(who, "")` clears it.
* **Per-stage profile:**
  * `face` (FaceController settings)
  * `springs` (per-chain stiffness, drag, gravity)
  * `hair` (natural hair shading)
  * `motion` (body-language profile in `data/motion_profiles.json`)

  Registering a Level 20 look is a data entry: a model path, `"status": "ready"`, and its profile. No code changes.

## What had to be fixed for the Blender-built models in Godot
1. **Dark hair.** The labs' hair renders navy (Mika) and black (Luna) in Godot. MToon's outline is an inverted hull,
   and on open double-sided strand ribbons that hull sits in front of the visible face. The outline pass is now
   removed from double-sided surfaces at render time; the VRM files are untouched.
   See `docs/screenshots/appearances/hair_before_outline_fix.jpg`.
2. **Expressions.** The rebuilt faces keep the VRoid morphs but with a mesh prefix
   (`Face.M_F00_000_00_Fcl_BRW_Joy`). FaceController now matches by suffix: 30 components bind on Mika, 28 on Luna,
   and all emotions plus lip sync work.
3. **Springs.** The lab's authored springs are soft (stiffness ≈ 0.5, drag ≈ 0.4). In the real-time solver the long
   hair trailed behind at walking pace. Per-chain tuning makes the hair firm and weighted with some swing.
4. **The "brows through the fringe" overlay** drew lash fragments over Mika's new bangs, so it is off for these
   stages.

## Visual improvements
* **Natural hair** (`shaders/characters/natural_hair.gdshader`), following the developer's photo references
  (`das.jpeg`, `sas.jpeg`, `as.webp`):
  * fine fibres along every lock, darker roots and a per-lock tone;
  * a soft anisotropic sheen band in the same light key as the face;
  * feathered tips.

  The hairstyles (geometry, colours, ornaments) are unchanged.
* **Character body language** (`data/motion_profiles.json`):
  * **Mika:** quick curious glances, snappier turns, a livelier tempo, and **wolf-ear expressions**
    (`EarController`): perked, drooped, flattened, cocked, plus twitches.
  * **Luna:** UAL's formal walk, slow deliberate head and body turns, calmer gestures, and rare, slow glances.

## Measurements (RTX 5050 Laptop, 1600×900, LIVE profile, 30 fps cap)
| | triangles | surfaces | materials (MToon) |
|---|---|---|---|
| Mika Celestial | 177,480 | 59 | 59 (59) |
| Luna Oracle | 291,220 | 40 | 40 (40) |
| old Mika / old Luna | 55,041 / 50,280 | 22 / 19 | 22 / 19 |

Both new looks together in the Whispering Woods, with autonomous planners running: **29.6 fps** (the cap),
**GPU 9.2 ms/frame**, **VRAM 1.17 GB**. That is plenty of headroom, so no LOD was needed yet. The p95 frame time is
33.4 ms.

## Tests
`--mktest=appearances` (PASS) covers:
* stage selection rules (levels 1, 9, 10, 25, 100; forms taken or not);
* the live avatars and their bound faces;
* a Level 15 save with Bloom, with identity preserved;
* the Level 27 fallback;
* the developer preview;
* the Level 10 transformation (Celestial → Bloom → back);
* both mages together in the Woods.

`res://scenes/tools/avatar_lab.tscn --lab=lineup|faces|walk|ears|sit|all` produces the visual comparisons and
metrics.

## Hair refinement (2026-10-15, the developer: "Their hair looks so messy! Fix it ... use Blender")
Diagnosis by A/B renders (`screenshots/avatar_lab*`): the mess was **not** the hairstyle. It came from shading on
top of it:
1. **Per-clump normals.** The lab's strand clumps keep 25 % of their own faceted normal. Under a sharp toon ramp,
   neighbouring clumps break into hard light/dark shards.
2. **The anisotropic sheen followed each clump's own direction.** In curls, every clump caught the light
   differently, giving jagged bright and dark stripes (confirmed: with the sheen off, the shards vanished).
3. **The darker under-layer paint** showed through the gaps between clumps as dark wedges.
4. My first natural-hair shader added more: alpha-cut tips, dark clump roots and per-lock tone bands.

Fixes:
* **Blender** (`tools/models/refine_hair.py`, run on the labs' read-only `*_export_ready.blend`, exporting new DEV
  VRMs `MikaCelestial_hair2.vrm` / `LunaOracle_hair2.vrm`):
  * clump edges relaxed (roots pinned);
  * one smooth normal field for the whole hairdo (density-gradient "volume" normals, blurred in a 3D grid);
  * for Luna, a smooth inner **shell** of the hair volume, skinned to the same bones, under the clumps.

  Every clump's shape, the colours and the ornaments are unchanged. The originals are archived as stage `v1`.
* **Shader** (`natural_hair.gdshader` v2):
  * the highlight follows one smooth flow over the hairdo (a continuous "angel ring");
  * one clean mass colour with a little of the painted strand detail;
  * the under-layer and cap use the outer texture;
  * no alpha-cut tips;
  * soft self-shadowing.

## Remaining visual defects (honest)
* **Luna's curls** still show a mild "staircase" where rows of clump tips sit on the curl surface. Removing it
  needs the curls regenerated in the lab's hair generator (a geometry rebuild with re-rigging).
* **Hair geometry:** close up, Mika's bangs and side locks are still broad ribbons with jagged edges. Luna's waves
  break into separate clumps on head turns. The shading helps, but only a geometry pass (more and narrower clumps)
  fixes it. That would be Blender work on DEV copies of the masters.
* **Mika's walking hair** still lifts a little more than ideal at her brisk pace.
* **Luna's gown when sitting:** the train spreads flat but the front panels intersect the legs slightly.
* **Luna's sleeves in combat casts** have not been reviewed frame by frame yet.
* **Proportions** stay VRoid-like, as the labs' reports note.
