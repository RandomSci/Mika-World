# Impacts, falls and getting up (V3 continuation, 2026-10-15)

The developer: "Characters must never instantly snap from a knocked-down position into a standing pose ...
Impact → loss of balance → stumble or fall → settling → recovery effort → standing → regaining balance → resume."

## What was wrong
`WorldCharacter.take_hit(heavy)` played `Hit_Knockback` through the single gesture slot. The clip throws her onto her
back, and the slot then faded back to the idle loop in 0.35 s, which snapped her from lying to standing. A fixed 1.1 m
push was the only physical effect.

## The system
* **`BodyReaction`** (`scripts/characters/body_reaction.gd`, one per mage): severity picks a tier and a sequence of
  real clips, crossfaded through a new **reaction state machine** in her AnimationTree (`react_sm`, mixed over
  everything by `react_mix`):
  | tier | severity | sequence |
  |---|---|---|
  | notice | < 0.12 | head turns, surprised face |
  | flinch | < 0.35 | Hit_Chest / Hit_Head, a half-step push, balance back |
  | stagger | < 0.62 | front: Idle_Shield_Break (stumbles back, catches herself) → steady; behind: Jump_Land (thrown forward, crouches, arms out) |
  | down, front | ≥ 0.62 | Death01 0-1.3 s (stumbles back, falls) or Hit_Knockback when ≥ 0.9 (thrown) → lying (held, dazed) → LayToIdle 0-0.62 (sits up, hand on the ground) → **steady**: sits catching her breath, then LayToIdle 0.62-1.5 (feet under her, stands) / **agile**: Slide_Exit (springs up) → steadying → blend out |
  | down, behind | ≥ 0.62 | Mixamo Standing React Death Forward 0-1.45 s (pitched onto her knees) → kneeling (held) → Fixing_Kneeling 4.3-5.17 s (kneel to stand) → steadying |
* **Root motion**: the fall clips play in place; their own hip travel (sampled at import, `WorldCharacter.root_curves`)
  moves the body through `move_and_slide`, with the blast's push (friction on the ground). Collision, floor and slopes
  are real.
* **Slopes**: while she is down, the avatar is laid along the ground normal under her (eased in and out).
* **Pace**: lying time and rising speed follow the blow, her **body profile** (`data/mages.json` → `body`: Mika
  `steady`, balance 1.0, recovery 1.0; Luna `agile`, balance 0.9, recovery 1.2), her vigor and how often she was knocked
  down in the last two minutes. Actions (walking, casting, gestures, dodges) are refused while she is down.
* **Face and voice**: surprised → hurt → dazed while down → hurt while rising → determined (Mika) / concerned (Luna).
  New reaction sounds in each mage's own production voice (`data/voices.json` clips `oof`, `breath`, `effort`).
* **`ImpactDirector`** (`scripts/combat/impact_director.gd`, `main.impacts`): `blast(at, strength, radius, opts)`.
  Severity is `strength × (1 − d/r)^1.3`, then:
  * × 0.35 behind solid cover (a raycast);
  * × 0.25 if her ward faces the blast;
  * × 0.6 if she braced;
  * divided by her balance.

  Friendly fire is non-lethal: it costs vigor only, never below 8 %. Each mage remembers who struck her in her own mind
  (`struck_by:<source>`, `struck_last`).
* **Aftermath AI**:
  * A companion within 25 m runs to the fallen one, kneels (Crouch_Idle) and reaches out a hand (Interact) as she
    rises. If the companion was flinching herself, she goes after she recovers.
  * Once up, **protective** Mika faces the danger in her combat stance.
  * **Evasive** Luna backs ~5 m out of its reach, then watches it.
  * In a fight, their own tactics take over again. Luna keeps 2 m more distance from then on (`keep_distance_bonus`
    in CombatTactics).
  * Lines are in `data/impacts.json`.
* Wired in:
  * **Oriel's** attacks (`Phoenix.shock` → `blast`).
  * **Monster** blows: severity scales with the attack's strength. A light swipe is a flinch; a brute's heavy blow can
    put her down.
  * The **slam** shockwave throws anyone else near.
  * Training duel touches stay flinches.

## Verified
* `res://scenes/tools/reaction_lab.tscn` (`--lab=suite`, always on a disposable save) measures every body every frame:
  * sinking below the ground;
  * hip speed over 0.1 s windows (snaps);
  * hip height while lying (floating).

  All ten cases pass: flinch, stagger, front, behind, blown, a 14° slope, behind cover, Luna front, Luna behind, and
  both together, where Mika runs to Luna and helps her up. Max hip speed is 0.1-5 m/s, sinking is ≤ 5 cm (hands and
  feet resting on the ground), and the lying hips sit 4-9 cm up.
* Reel: `screenshots/reaction_reel/mika_luna_impact_recovery_reel.mp4` (Movie Maker, captioned); stills in
  `docs/screenshots/v3_continuation/`.
