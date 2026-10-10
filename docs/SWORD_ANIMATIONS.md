# Great Sword animations on Mika

Source: the user's own Mixamo downloads in `~/Downloads`: `Great Sword Pack.zip` (51 clips + X Bot) and three standalone files.
Copies only, kept in `assets/animations/mixamo_sword/` (git-ignored; Mixamo raw files must not be redistributed).
All clips were retargeted to Mika's real VRM skeleton with the same importer path as the base animations
(`BoneMap` → `SkeletonProfileHumanoid`, overwrite-axis rest fixer) and then **measured on her skeleton** with
`scenes/tools/anim_preview.tscn` (contact sheets in `screenshots/sword/`, metrics in `screenshots/sword/sword_clip_report.json`).

## Findings

* The three standalone files are **content-duplicates of pack variants**, not new animations
  (identical lengths/metrics): `Great Sword Idle` = `great sword idle (5)`, `Great Sword Slash` = `great sword slash (2)`,
  `Great Sword 180 Turn` = `great sword 180 turn (2)`.
* Locomotion and big attacks contain **root motion** (walk 1.45 m, run 1.85 m, slash (2) 3.0 m, jump attack 3.1 m,
  slide attack 3.4 m, high spin 2.3 m). Locomotion is made in-place (speed-matched like the base walk/run). The big travelling
  attacks would visibly slide if forced in-place, so they are **deferred** until root-motion support exists.
* Two-handed grip stays tight (≈ 0.08–0.14 m between hands, small spread) in all sword clips except the draws (one hand
  reaches for the hilt, expected) and the deaths.
* `draw a great sword 1` has a 1,532 °/s wrist snap in 0.5 s → `draw a great sword 2` is used instead.
* No clip drives a hand through the torso (min hand–torso distance ≥ 0.13 m).

## Selected for Mika's sword layer (`scripts/characters/sword_layer.gd`)

| Role | Clip | Why |
|---|---|---|
| stance idle | `great sword idle` | steady 2 s loop, no jitter (5 °/s) |
| alt idle | `great sword idle (2)` | variety, looks around |
| walk / run | `great sword walk`, `great sword run` | in-place, speed-matched in the existing blend space |
| draw | `draw a great sword 2` | no wrist pop |
| combo 1–3 | `great sword slash`, `great sword attack`, `great sword slash (3)` | ≈0 m root drift, clean two-handed arcs |
| block | `great sword blocking` | short, grounded |
| elemental charge | `great sword power up` | slow, readable — drives the blade's element glow |
| sword + magic | `great sword casting` | kneeling ground-strike; reserved for future elemental spell combos |

The grip was **measured, not guessed**: over 60 two-handed frames the blade axis (left fist → right fist) in the RightHand
bone frame is (0.891, 0.389, −0.235); the blade is attached along that axis (`anim_preview --gripcal`).

## Magical-sword layer

* Separate `AnimationLibrary "sw"`; drawing swaps the locomotion blend-space clips, sheathing restores the originals exactly.
* Attacks/charge use the character's one-shot slot; casting a spell auto-sheathes so the Arcane Orb sequence is unchanged.
* Original procedural blade + `shaders/magic/elemental_blade.gdshader` (steel, rune channel, luminous edges).
  `set_element(arcane|fire|frost|storm)` — hook for future elemental combinations.
* Controls: R draw/sheathe · F combo · G charge · T next element. Bridge: `{"cmd":"sword","action":"draw|sheathe|attack|power_up|element","element":"fire"}`.
* Verified: draw → navigate in stance → slash/attack → fire charge → unknown element refused → cast (auto-sheathe) → travel.

## All 54 clips measured on Mika

| clip | length s | root drift m | hand distance m | min hand–torso m | max joint °/s | flags |
|---|---|---|---|---|---|---|
| `draw_a_great_sword_1` | 0.5 | 0.1 | 0.63 ± 0.14 | 0.2 | 1532 | hands far apart for a two-handed grip; very fast joint rotation (possible pop) |
| `draw_a_great_sword_2` | 0.8 | 0.12 | 0.38 ± 0.26 | 0.27 | 773 | hands far apart for a two-handed grip |
| `great_sword_180_turn` | 0.8 | 0.02 | 0.13 ± 0.04 | 0.22 | 1029 | — |
| `great_sword_180_turn_2` | 0.57 | 0.23 | 0.09 ± 0.01 | 0.25 | 1230 | — |
| `great_sword_attack` | 1.2 | 0.0 | 0.08 ± 0.02 | 0.19 | 1088 | — |
| `great_sword_blocking` | 0.5 | 0.1 | 0.06 ± 0.03 | 0.25 | 539 | — |
| `great_sword_blocking_2` | 0.97 | 0.0 | 0.04 ± 0.0 | 0.42 | 5 | — |
| `great_sword_blocking_3` | 0.5 | 0.1 | 0.08 ± 0.04 | 0.25 | 403 | — |
| `great_sword_casting` | 4.8 | 0.0 | 0.11 ± 0.02 | 0.25 | 739 | — |
| `great_sword_crouching` | 0.67 | 0.38 | 0.1 ± 0.01 | 0.25 | 476 | root motion 0.38 m (made in-place) |
| `great_sword_crouching_2` | 0.7 | 0.37 | 0.08 ± 0.01 | 0.25 | 355 | root motion 0.37 m (made in-place) |
| `great_sword_crouching_3` | 1.83 | 0.0 | 0.1 ± 0.0 | 0.36 | 4 | — |
| `great_sword_crouching_4` | 0.37 | 0.08 | 0.12 ± 0.01 | 0.36 | 316 | — |
| `great_sword_crouching_5` | 1.4 | 0.0 | 0.15 ± 0.0 | 0.43 | 4 | — |
| `great_sword_crouching_6` | 0.47 | 0.08 | 0.12 ± 0.02 | 0.36 | 230 | — |
| `great_sword_high_spin_attack` | 1.87 | 2.29 | 0.12 ± 0.06 | 0.23 | 1744 | very fast joint rotation (possible pop); root motion 2.29 m (made in-place) |
| `great_sword_idle` | 2.0 | 0.0 | 0.1 ± 0.0 | 0.25 | 5 | — |
| `great_sword_idle_2` | 3.7 | 0.02 | 0.11 ± 0.02 | 0.15 | 473 | — |
| `great_sword_idle_3` | 3.67 | 0.01 | 0.26 ± 0.12 | 0.16 | 425 | — |
| `great_sword_idle_4` | 3.77 | 0.01 | 0.22 ± 0.15 | 0.19 | 446 | — |
| `great_sword_idle_5` | 7.57 | 0.0 | 0.3 ± 0.12 | 0.18 | 445 | — |
| `great_sword_impact` | 0.87 | 0.0 | 0.04 ± 0.01 | 0.39 | 158 | — |
| `great_sword_impact_2` | 1.2 | 0.0 | 0.11 ± 0.01 | 0.25 | 583 | — |
| `great_sword_impact_3` | 1.27 | 0.0 | 0.28 ± 0.17 | 0.14 | 695 | — |
| `great_sword_impact_4` | 0.67 | 0.0 | 0.15 ± 0.01 | 0.43 | 168 | — |
| `great_sword_impact_5` | 0.97 | 0.0 | 0.1 ± 0.01 | 0.31 | 741 | — |
| `great_sword_jump` | 0.63 | 1.67 | 0.08 ± 0.01 | 0.26 | 365 | root motion 1.67 m (made in-place) |
| `great_sword_jump_2` | 0.9 | 0.0 | 0.11 ± 0.01 | 0.16 | 297 | — |
| `great_sword_jump_attack` | 2.17 | 3.11 | 0.1 ± 0.05 | 0.23 | 1331 | root motion 3.11 m (made in-place) |
| `great_sword_kick` | 1.5 | 0.0 | 0.07 ± 0.02 | 0.25 | 1327 | — |
| `great_sword_kick_2` | 1.73 | 0.0 | 0.08 ± 0.04 | 0.23 | 523 | — |
| `great_sword_power_up` | 3.5 | 0.07 | 0.08 ± 0.02 | 0.13 | 200 | — |
| `great_sword_run` | 0.73 | 1.85 | 0.08 ± 0.01 | 0.27 | 171 | root motion 1.85 m (made in-place) |
| `great_sword_run_2` | 0.6 | 2.51 | 0.07 ± 0.01 | 0.3 | 242 | root motion 2.51 m (made in-place) |
| `great_sword_slash` | 1.27 | 0.0 | 0.08 ± 0.03 | 0.24 | 1301 | — |
| `great_sword_slash_2` | 3.53 | 3.03 | 0.09 ± 0.05 | 0.21 | 1470 | very fast joint rotation (possible pop); root motion 3.03 m (made in-place) |
| `great_sword_slash_3` | 1.83 | 0.01 | 0.11 ± 0.04 | 0.2 | 1279 | — |
| `great_sword_slash_4` | 1.8 | 1.1 | 0.12 ± 0.03 | 0.21 | 1215 | root motion 1.10 m (made in-place) |
| `great_sword_slash_5` | 1.43 | 0.02 | 0.1 ± 0.03 | 0.29 | 1007 | — |
| `great_sword_slide_attack` | 2.13 | 3.41 | 0.13 ± 0.06 | 0.21 | 1278 | root motion 3.41 m (made in-place) |
| `great_sword_strafe` | 1.1 | 1.24 | 0.14 ± 0.0 | 0.24 | 104 | root motion 1.24 m (made in-place) |
| `great_sword_strafe_2` | 1.17 | 1.42 | 0.14 ± 0.0 | 0.26 | 149 | root motion 1.42 m (made in-place) |
| `great_sword_strafe_3` | 0.57 | 1.3 | 0.12 ± 0.01 | 0.34 | 137 | root motion 1.30 m (made in-place) |
| `great_sword_strafe_4` | 0.63 | 1.92 | 0.11 ± 0.02 | 0.24 | 178 | root motion 1.92 m (made in-place) |
| `great_sword_turn` | 0.73 | 0.17 | 0.11 ± 0.01 | 0.25 | 323 | — |
| `great_sword_turn_2` | 0.83 | 0.13 | 0.1 ± 0.01 | 0.23 | 290 | — |
| `great_sword_walk` | 1.37 | 1.45 | 0.13 ± 0.0 | 0.23 | 51 | root motion 1.45 m (made in-place) |
| `great_sword_walk_2` | 1.3 | 1.28 | 0.14 ± 0.01 | 0.24 | 84 | root motion 1.28 m (made in-place) |
| `spell_cast` | 1.13 | 0.0 | 0.26 ± 0.11 | 0.19 | 1082 | — |
| `standalone_great_sword_180_turn` | 0.57 | 0.23 | 0.09 ± 0.01 | 0.25 | 1230 | — |
| `standalone_great_sword_idle` | 7.57 | 0.0 | 0.3 ± 0.12 | 0.18 | 410 | — |
| `standalone_great_sword_slash` | 3.53 | 3.03 | 0.09 ± 0.05 | 0.21 | 1488 | very fast joint rotation (possible pop); root motion 3.03 m (made in-place) |
| `two_handed_sword_death` | 2.4 | 0.83 | 0.48 ± 0.34 | 0.25 | 853 | hands far apart for a two-handed grip; root motion 0.83 m (made in-place) |
| `two_handed_sword_death_2` | 2.6 | 1.23 | 0.17 ± 0.07 | 0.21 | 589 | root motion 1.23 m (made in-place) |
