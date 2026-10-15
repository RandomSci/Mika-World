# Mika Level 1–9 outfit (12 generated 3D pieces): fitting, rigging and materials

Status: built, rigged, registered and tested in the DEV copy, on branch `l1-outfit-v1` in the worktree
`~/Downloads/Mika-Godot-Dev-L1Outfit`.
- The design was not changed: no remodel or recolour.
- Not merged into `milestone-k`, LIVE, or the other session's checkout.

## What was done
| Step | Result |
|---|---|
| Source | `~/Downloads/MIKA_L1_Outfit_3D.zip` (sha256 `888b9ac0…`), unzipped to `l1_outfit_src/`. The original zip is untouched. |
| Base | The shipping `MikaCelestial_hair2.vrm` (the Level 1–10 Celestial look). Face, Face_Blush, Body and the J_Bip/J_Adj skeleton are imported as they are, and so are the 57 face shape keys and the expressions. The bust and ear bones are also kept. |
| Removed | `Outfit_*`, `Acc_*`, `Hair`, `Hair_WolfEars`, `HairCap` meshes, plus the old outfit and hair spring bones. All of these remain in the old VRM, which is archived. |
| Placement | Each piece is rotated, scaled and translated (`tools/o10_place.py`, `l1_outfit/spec_place.json`). The hair is fitted by a scalp-coverage search (scale 0.415). The bodice and skirt use body landmarks. The collar is sized around the bodice's own collar. |
| Duplicates and mirrors | The sleeve is mirrored for the right arm. The pair of bracelets is split, one per wrist, and so are the shoes. Star pendants: one over each of the skirt's own star pendants, with the star size matched. Orb pendants: one on each outer panel tip. |
| Fit | The pieces are pushed out of the body by 1.5–12 mm, with smoothing (`outfit_fit.conform`). The shoe soles are excluded. The shoes are 22% wider and 32% taller to match her high-arched VRoid foot; without this her toes and heel came through the shoe. |
| Weights | Bodice and collar: the body's own torso and neck weights. Sleeve tube: arm weights; the drape hangs on 3 chains per arm. Skirt: 16 chains around the hips. The skirt's built-in thigh garter follows the right thigh. Shoes: foot and toe weights. Bracelets: rigid on the forearm (see the note under Remaining). Hair flower, back bow knot and hair: head. Brooch: spine. |
| Spring bones | Total: 40 springs. Each chain group with its collider groups: <br>• hair: 12 chains, weighted by height (torso, arms, legs) <br>• ears: the existing ear bones, moved into the new ears, so the `EarController` emotions still work <br>• skirt: 16 chains (legs, plus larger hand capsules used only by the skirt) <br>• sleeve drapes: 6 (torso, legs) <br>• back-bow ribbons: 2 (head, torso) <br>• bodice front tassels: 2 (legs) <br>• star pendants: 2, together with the skirt's own star behind each one (legs) |
| Colliders | 19 in total: <br>• head, neck, chest, 2 bust, spine, hips <br>• upper arms, lower arms, hands <br>• thighs, shins <br>• 2 skirt-only hand capsules |
| Materials | 16 MToon 1.0 materials. They use the face's toon settings (toony 0.88, shift −0.10, GI 0.9). The generated textures are the base colour and the shade texture. Hair, skirt, sleeves and back bow are double-sided, with outlines off on double-sided surfaces. |
| Export | `l1_outfit/export/MikaCelestial_L1Outfit.vrm`: VRM 1.0, 36 MB, sha256 `bbeea6eb…` for the first build; the final build differs in spring settings only. |
| Registry | New stage `celestial_l1outfit` (order 2, Level 1–10, uses the same spring tuning profile). The old `celestial` stage stays as order 1, so it is the automatic fallback if the file is missing. It is also archived as `celestial_hair2` for rollback. |

## Godot checks (DEV, LIVE_OPTIMIZED profile, Luna in the scene)
Test: `--outfittest` (new `scripts/tests/outfit_test.gd`, see the commit). Screenshots are in `l1_outfit/review/`:
- grid: `MIKA_L1_godot_front_side_back_idle_walk_sit_cast.jpg`
- face strip: `MIKA_L1_godot_face_expressions_blink_lipsync.jpg`
- `godot_*.jpg` single shots

**Face:** 30 face blend shapes are bound, the same as the current look. Neutral, happy, surprised, sad, blink and the lip-sync mouth were all checked in game.

**Frame rate** (two 20-second windows each, after an 8-second warm-up, Mika and Luna framed, RTX 5050):

| | New look | Current look |
|---|---|---|
| Average fps | 30.0 / 30.0 | 30.0 / 30.0 |
| Frame time p50 / p99 | 33.3 / 34.0–34.1 ms | 33.3 / 33.9–34.0 ms |
| Frames over 50 ms | 0 | 0 |
| Primitives in frame | 2.05–2.08 M | 1.90 M |
| Draw calls | 363–407 | 397 |
| Video memory | 979–1009 MB | 812–836 MB |
| Texture memory | 690 MB | 536 MB |
| Mika triangles | 489,691 | 177,480 |
| Luna triangles | 300,289 | 300,289 |

The world itself occasionally freezes for about 1 second, with either look. It is not caused by the outfit.

**Spring settling** (tip motion relative to the hips; her random idle glances are paused while measuring):

| | New | Current |
|---|---|---|
| Idle (high-frequency mm/frame²) | 0.42 | 0.80 |
| 2–4 s after stopping a walk | 0.21 | 0.19 |
| Seated, settled | 0.31, 0 spiky frames | 0.80, 2 spiky frames |

The new springs settle without jitter.

**Clipping**
- Method: the exact runtime pose of each capture (springs included) is re-skinned in Blender (`tools/o13_clipcheck.py`). It counts body vertices whose skin is visible outside the cloth that should cover them (out of 5,000 body vertices).
- Nothing floats: the shoes, bracelets, collar and bodice stay in contact in every pose.
- Single-frame samples vary from run to run, so the range over runs is shown:

| Pose | New look | Current look |
|---|---|---|
| Idle | 133–158 | 242–263 |
| Walk | 72–214 | 150–188 |
| Run | 90–110 | 100–111 |
| Sit | 69–77 | 73–74 |
| Cast (spell_casting) | 108–118 | 99–140 |
| Cast (wide arm) | 118–170 | 101–129 |

## Remaining (honest list)
1. **Hands in the hip frills.**
   - In the Mixamo idle and walk, her hands and forearms hang where the skirt's flared top layer sits. The fingers sink up to about 2.8 cm into the frill (about 100–140 skin vertices).
   - Tried and not good enough:
     - larger hand colliders: they help a little and stay in;
     - 16 chains with extra hip joints: they flared the skirt sideways like wings, so they were reverted;
     - turning the upper arms out 7° while they hang: the frill is wider than that, so this was reverted.
   - Real fixes need your decision: tuck the frill in slightly at her hands (a small design change), or use a different idle/walk arm pose.
2. **Wide-arm cast.**
   - The lunge puts her shins into the front skirt panels (about 40 vertices).
   - The long hair crosses her arms when they are raised (about 56 vertices). The current look does the same.
3. **Sleeve edges at the elbow.** When the elbow bends, the sleeve's open slit edge sits 1–2.5 cm into the forearm (about 25 vertices).
4. **Bracelets.** They are rigid on the forearm (LowerArm), not the hand: at the wrist position, a hand-parented bangle cut into the wrist whenever the hand bent.
5. **Pendants.**
   - The skirt's own star pendants ride under the detailed star pendants, on the same chain.
   - The hair's built-in flower and bow sit under the separate detailed flower and back bow. These are visible only as extra depth.
   - The separate collar sits around the bodice's built-in collar.
6. **Video memory.** It is about 170 MB higher than the current look, from twelve uncompressed 2K textures. Turning on VRAM compression would roughly quarter that if it ever matters.

## Reuse
The pipeline is generic for the next sets (Luna Levels 1–9, Mika Level 10, Luna Level 10):

| Script | Job |
|---|---|
| `o01`–`o05` | inspect |
| `o10_place.py` + spec | place |
| `o12_rig.py` | fit, rig, materials, export |
| `outfit_test.gd` | Godot QA |
| `o13_clipcheck.py` | clipping check |
| `o14_pose_render.py` | render a runtime pose |
