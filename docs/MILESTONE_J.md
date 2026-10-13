# Milestone J — cinematic combat, Mika-first camera, grand awakenings

Branch `milestone-j` (from the verified Milestone I checkpoint `649a0d0`, tag `milestone-i-final`).
Every claim below was checked in a real Godot run unless it says otherwise; numbers come from
`screenshots/mjtest/*.json` (windowed) and `tools/run_regression.sh` (headless).

## 1. Mika-first stream (camera policy)
* `main.stream_profile` (`--stream-profile=mika|shared`, default **mika**). In the Mika profile the automatic
  camera serves Mika only: the spotlight never cuts to Luna on its own; after any temporary change it returns to
  Mika; a performance is filmed only when it is the stream mage's (Luna performing alone happens off-camera —
  `PerformanceController` no longer takes the director for her). A developer's explicit focus (F3 / bridge /
  tests, `focus_locked`) is respected; Shift+F3 releases it back to Mika.
* Shared scenes: Mika and Luna talking → the existing conversation two-shot; fighting together → the combat shot
  includes the other mage (CombatFraming adds her as a subject).
* `shared` reproduces the Milestone I spotlight for a future multi-subject stream. Separate Luna / shared stream
  outputs are **not** implemented (by request).

## 2. Combat (truthful, tactical, readable)
* **Creatures telegraph every attack** (`Monster` windup → strike → recover) through `AttackHazard`:
  slams / sweeps / charges / dives mark their ground (`shaders/telegraph.gdshader`, outline + fill that grows to
  the moment of impact); bolts and thrown stones are real projectiles in flight. A hazard resolves against where
  each mage actually is at that moment — stepping out of it avoids the blow. Nothing is pre-decided.
* **Mage tactics** (`scripts/brain/combat_tactics.gd`): dodge · brace · retreat · keep distance · approach ·
  reposition (line of sight / room to cast) · cast · assist the other mage · steady. Decided only from what she
  perceives (`AttackHazard.perceived_by`: in range with a clear line), never hidden state. Godot executes:
  `WorldCharacter.dodge()` is real movement through collision (an upright sprint-dash — a roll in a skirt is not stream-safe; the camera frames where she lands);
  `take_hit()` plays a flinch or a heavy knock-back; casts go through the unchanged `MagicSystem` pipeline.
* **Casting in a fight**: spells may use a quicker combat gesture (`clip_combat`, the Arcane Orb's two-handed
  release); the projectile is aimed at RELEASE time at where the creature is, leading its observed motion by a
  mastery-scaled amount (`MagicSystem.lead_aim`; no homing). Damage now applies at the moment of impact.
* **Fair difficulty**: stamina (attacks cost it; out of breath → it backs off), poise (small hits don't break a
  heavy windup), recovery windows with extra damage ("exposed"), resistances, a flyer that keeps its distance,
  strafes and retreats once when badly hurt. No inflated health.

## 3. Creatures (two polished archetypes)
| | Hollow Sentinel (heavy) | Emberwing (agile flyer) |
|---|---|---|
| Body | Original articulated stone golem (Blender script), procedural moss-stone shader, glowing rune seams | Quaternius CC0 "Dragon", ember recolour, its own 5 clips + procedural hover / bank / rear-back |
| Movement | 1.2 m/s, slow turning, heavy alternating gait with footfall dust + thuds | 3.4 m/s, holds ~8 m, circles and changes direction |
| Attacks | slam (marked circle, 1.15 s windup, 1.7 s exposed recovery), backhand sweep (arc), thrown boulder (projectile), ground-shaking charge (marked lane) | ember bolt (projectile), diving swoop (marked lane, exposed landing) |
| Reactions | hit flinch with stone flash, stagger when poise breaks, collapse into tumbling stones on defeat | hit clip, stagger, death clip, then dissolves |
Existing Gloomwisp / Thornback keep their Milestone H behaviour (unchanged data and progression).

## 4. Animation
New retargeted clips (Quaternius Universal Animation Library, CC0): combat stance idle, sprint (evasive dash), chest / head
hits, knock-back, brace, quick casts, victory nod. Retargeting: `assets/animations/ual_bonemap.tres`.

## 5. Magic presentation
* Arcane Orb: readable flight (light trail, slight arc), impact = ground ripple + element-specific shards (the
  camera-facing disc that every spell shared is gone), damage at impact, combat release gesture.
* `ImpactFX`: element identities (arcane light shards, umbral crystal splinters, fire flare, water splash, wind
  dust), ground ring only near the ground, camera jolt reduced.
* **Signature cast** (`SignatureCast`, prototype: Mika's Arcane Orb): only at Adept mastery or better, costs
  energy + vigor, 75 s cooldown, +0.3 power; a deliberate stance, an outer ground formation and an upright sigil
  in front of her hands, fuller orb; camera beats stance → push-in on face/hands → over-shoulder release →
  hold on the impact → back to the fight (~5–7 s). First use recorded in her memory. Luna's Umbral Lance can be
  channelled the same way (camera beats + power) but has no dedicated signature visuals yet.

## 6. Level 10 awakening (first unlock, 11.6 s)
Five stages (`data/transformations.json` → `versions.full.stages`, `scripts/transform/awakening_fx.gd`):
1. awakening — she glances at her hands; motes drift in from all around;
2. build-up — three orbit frames rise and turn around her, she lifts off and speaks her words;
3. clothing reveal — eight helical ribbons of light wrap her feet-to-head; a brief luminous veil seals while
   the VRM changes; the ribbons unravel head-to-feet so the outfit appears progressively;
4. Aether Orbit — arc segments and beads fly in from scattered positions and lock into her first orbit;
5. final reveal — landing, finishing pose on the musical climax, clear full-body shot, title.
New stage-synced original scores (`synth_milestone_j.py transform`). Lights moved off her body (no washed-out
outfit). Permanent appearance, previews and Orbit Surges are unchanged from Milestone I.

## 7. Audio
* Bell / chime removed from ordinary gameplay: 62 files rebuilt from non-tonal elemental material (air, breath,
  sub thumps, crackle, water, grit). Verified with `tools/audio/bell_check.py` (sustained narrow tonal peaks
  600–6000 Hz): every spell, combat and cue file scores **0.000**. Still tonal by design: ambience (Heartstone
  hum), the fox, crystal shatter, the travel portal and the rare transformation scores.
* Progress cues are rate-limited (one per 4 s) and levelling has a single low, non-bell cue (only for the mage
  the stream follows).

## 8. Voices
`data/voices.json`: Mika = Edge `en-US-AvaNeural` (+25 Hz, +5 %), Luna = Edge `ja-JP-NanamiNeural` (+30 Hz,
+5 %) — the Mika-Voice-Lab choices — through `tools/voice/edge_service.py` (local venv `.venv-voice`, port 12472,
disk cache). Per-line Kokoro fallback; Latin incantations stay on Kokoro IPA. Laugh tokens never spoken: a short
laugh / giggle in her own voice plays instead (candidates — please audition).

## Tests (verified 2026-10-13/14)
Windowed (`--mjtest=…`, disposable saves, screenshots + clips in `screenshots/mjtest/`, git-ignored):
| Test | Result |
|---|---|
| encounter, Emberwing | PASS — won after 4 casts / 3 hits, 5 real dodges (4 avoided the blow, 0 failed), intents approach/dodge/reposition/cast; camera on Mika 100 % of frames, combat framing while the creature lived |
| encounter, Hollow Sentinel | PASS — won after 6 casts / 6 hits, 3 dodges (all avoided), charge + slam telegraphs, exposed recovery hits |
| signature (Mika) | PASS — refused below Adept, allowed at Adept, hit for 124 damage, beats awaken → gather → release → impact in ~6.7 s, 75 s cooldown, first use in memory |
| awaken Mika / Luna | PASS — 10.6–11.6 s; cocoon closed and sealed before the VRM changed; progressive reveal; orbit locked after the reveal; camera never blocked; preview changed no progress |
| policy | PASS — 2250/2250 frames on Mika while Luna performed a full song off-camera; explicit Luna focus respected and released back to Mika |
| voices | PASS — Mika `en-US-AvaNeural` (+25 Hz, +5 %), Luna `ja-JP-NanamiNeural` (+30 Hz, +5 %) via Edge; Latin via Kokoro IPA; laugh tokens become reactions |
| aftermath | PASS — after a fight: camera leaves combat, no hazards left, stance off, a music performance and dialogue work |
Headless `tools/run_regression.sh all`: **24/24 suites, 182 checks** (incl. both mages' permanent forms across a
restart, `mi_form1/2`).
Clips (Godot Movie Maker, 30 fps, with game audio; bell detector on the mixed audio 0.000–0.037):
`emberwing_fight.mp4`, `sentinel_fight.mp4`, `signature_cast.mp4`, `awakening_mika.mp4`, `awakening_luna.mp4`.

## Performance — honest status
A controlled benchmark was NOT possible: during the whole verification an unrelated rendering job (chrome
processes, load average 35–39, CPU at ~90 °C) occupied the machine; it was not stopped. Under that load:
fights 26–29 FPS average (p50 33–37 ms), the awakening ~23–27 FPS, a 90 s life sample 27.2 FPS, with 100–150 ms
hitches on first use of new effects (shader compilation). The Milestone I baseline on the same machine without
that load (AC power) was 29.2–30.1 FPS. Repeat `--brainrun=600` on an idle machine before release.
