# Mika World V3 — project audit before the "Living Universe" directive (2026-10-14)

Everything here was checked on the machine on 2026-10-14 (`git`, the running processes, the data files, real
Godot runs). Where something is an estimate it says so.

## 1. Repository state

| Item | Finding |
|---|---|
| Branch / checkpoint | `milestone-k`, HEAD `8b281aa` "Milestone K checkpoint K7" (K1 `2be4f3e`, K2 `961ee4a`, K3 `0483732` before it). Milestone J is `5da1871` (`milestone-j`), Milestone I final `649a0d0` (tag `milestone-i-final`). |
| Developer's uncommitted work (preserved, never staged) | `project.godot` (fullscreen), `scripts/areas/arcane_library.gd`, `scripts/world/reading_lectern.gd`, `scripts/world/sanctuary_expansion.gd`, the lectern hunk of `scripts/world/sanctuary.gd` — the reading-lectern work in progress. Commits in this session take only my own hunks (`git apply --cached` of a patch). |
| Other sessions | A second Claude session (cwd `~/Downloads`, with a Character Lab daemon) wrote `phoenix_custom.mp3`, `phoenix_sonia.mp3`, `phoenix_ashley_test.mp3` (0 B) and `phoenix_voice_tests/*.mp3` into this project root between 03:33 and 03:41. Those are Edge-voice auditions, not the confirmed Kore voice; they are left untouched and unstaged. No other session is editing the scripts (every recently modified source file is mine). |
| Real save | `user://mika_world_save.json` untouched; every test uses `user://test_regress_*.json` (the harness refuses anything else). |
| Launchers | `./run.sh` modes `cinematic | live | ultra | night | tour [profile] | compat | editor` (read, unchanged). The directive's `./run.sh live --brain --save-path=...` form works as documented. |
| Code size | 32,083 lines of GDScript across `scripts/`; data in `data/*.json`. |

## 2. Milestone K status (what is real)

| Phase | State | Proof |
|---|---|---|
| K1 expressive faces, affect model, character light balance | **done** | `--mktest=face` 16/16 |
| K2 companions (grounded conversations, invitations, walking together, two-shot/OTS camera) | **done** | `--mktest=companions` PASS on a copy of the real save |
| K3 friendly training duels | **done** | `--mktest=duel` PASS |
| K7 Whispering Woods, one continuous route | **done, visually unfinished** (see §4) | `--mktest=env` 15/15 landmarks reachable; `screenshots/mktest/clips/woods_walk_day.mp4` (179 s, 1080p, real game camera) |
| K4 better monster models | not started (sources evaluated in Milestone J; Ultimate Monsters download was quota-blocked) | — |
| K5/K6 distinct Mika (wind/nature) vs Luna (arcane/umbral) spell VFX | not started; today both use the shared elemental pipeline with per-element layers (8 spells in `data/spells.json`) | — |
| K8 creature territories | not started; creatures still spawn only in the Sanctuary hub from fixed anchors (`scripts/combat/spawner.gd`, `current_id != "sanctuary"` gate) | — |
| K9 learned teleportation / spatial-magic knowledge | not started (the ruins' inscription exists as a prop, not yet as a knowledge clue) | — |
| K10 expeditions, K11 consistency model, K13 wilderness audio (partly: waterfall/stream/den beds exist), K14 controlled benchmark, K15 credits doc, K17 20 demos, K18 report | open | — |

## 3. Systems that exist (do not rebuild)

* **Autonomy**: `scripts/brain/sanctuary_brain.gd` planner with activity kinds research, magic, gather, explore,
  roam, rest, recover, journal, investigate, hunt, alchemy, attune, collect, converse, meet, perform, travel,
  together (explore/rest/spar); separate minds per mage (`WorldState.mind(who)`), knowledge keys, activity logs.
* **Companionship / talk**: `companionship.gd`, `mage_talk.gd`, `follow_companion.gd`.
* **Magic**: `scripts/magic/` — truthful cast pipeline (range, line of sight, projectile sweep, judged hit),
  elemental spells, signature cast (Mika's visuals done; Luna's not), fusion, reactives.
* **Combat**: `Monster` (wander → alert → chase → windup/strike/recover/stagger/rest/retreat), `AttackHazard`
  telegraphs, `CombatTactics` (dodge/brace/retreat/reposition from perception), `TrainingDuel`.
* **Creatures**: Gloomwisp, Thornback (procedural), Hollow Sentinel (original Blender-scripted golem), Emberwing
  (Quaternius CC0 dragon, recoloured). `data/monsters.json`.
* **Characters**: VRM1 avatars, FaceController (57 morphs), HeadPosture, AnimationTree gestures; Mixamo clips incl.
  `stand_to_sit`, `sit_to_stand`, `sitting_idle`, `lying_down`, `picking_up_*`, `putting_down`; UAL combat set.
  Sitting on seats is implemented (`Interactable` sit path); lying down and stargazing are **not**.
* **Camera**: `CameraDirector` (Mika-first stream profile, conversation two-shot + OTS, combat framing, shots).
* **World**: six canonical regions, 14 streamed areas, 25 locations, 8 vista landmarks in `data/world.json`;
  `AreaBase`/`KitArea` streaming with navmesh bake from static colliders; `Vista` distant scenery.
* **Progression**: `data/progression.json` (`max_level` 100, Ten Aether Orbits via `transformations.json`,
  permanent Level 10 forms), trials, ranks, mastery tiers.
* **Knowledge**: 8 books with real pages (`data/books.json`), story clues (`story.json`, chapter "Echoes of the
  Heartstone", 8 clues, 5 stages), journals.
* **NPCs**: 3 travellers (wandering mage, travelling scholar, wandering merchant) with voices; no resident NPCs
  with occupations yet.
* **Voice**: Mika `en-US-AvaNeural` (+25 Hz, +5 %), Luna `ja-JP-NanamiNeural` (+30 Hz, +5 %) through
  `tools/voice/edge_service.py`, Kokoro fallback; bell-free SFX (`tools/audio/synth_milestone_j.py`).
* **Audio**: positional ambience beds per area (`AudioDirector`), footsteps by surface, spell layers.
* **Tests**: `tools/run_regression.sh` (headless suites), `--mjtest=*`, `--mktest=face|companions|duel|env|walk`.

## 4. Identified defects (visual, from the reference comparison grids)

Side-by-side of each reference with the current Godot frame (`scratchpad/k/audit_cmp1.png`, `audit_cmp2.png`):

| Reference | What the reference has | What Godot has today | Defect to fix |
|---|---|---|---|
| 02 Deep enchanted forest | closed green canopy, layered leaves filling the frame, no sky, moss boulders, sun bursting through leaves | open meadow with spaced trees, bare ground, sky everywhere, a few oversized identical plants | **density and canopy closure**; understory layer; forest-floor darkening; fewer/smaller giant plants; moss boulders, logs, roots |
| 03 Waterfall bridge | mossy bridge with balustrade, water pouring beside it, dark lush banks, mist | clean bridge, bare banks, bright flat terrain, oversized parapet cubes | balustrade + moss + vines; riverbank sediment, rocks in water, reeds; mist; smaller parapet |
| 04 Hidden lotus pond | enclosed by weeping willows, a spring fall into the pond, lily pads, mist, cool palette | open sunny pond, blocky rocks, tiny pads | willow curtains, the spring fall (ledge exists), reeds, darker water, mist, enclosure |
| 05 Monster den | root-and-vine hollow, dark purple interior with depth, bright framing leaves | grey dome, grey arch, fog-washed interior | truly dark interior (fog-free material), roots/vines over the mouth, depth cue, framing foliage |
| 06 Forgotten ruins | heavy weathered gate, tree engulfing the ruin, vines, moss, glowing fungi, dense forest behind | clean chamfered blocks, open sky, sparse plants | block erosion/irregularity, ivy, engulfing roots, forest around the plateau |
| 07 Forked stairway | columns with capitals, round arches, worn uneven steps, mist | reads correctly (strongest view) | capitals, moss, mist, trees closer |
| 08 Moonlit forest | readable blue moonlight, large glowing mushrooms, firefly trails, mist | crushed black; a leaf over the lens | night ambient/moon rebalance, a mushroom grove (restrained), fireflies visible, camera clear |
| 09 Frontier road | bleak road, dead trees, fog | trail exists, undressed | dressing later (not on the main route) |
| 10 Crystal valley | far crystals under strange skies | nothing | distant vista landmark (honestly labelled as not explorable) |
| 01 Sanctuary garden path | blossom trees, bright sky, buildings | the hub is unchanged this milestone | blossom-tree pass later |

Non-visual defects: `--mktest=env` FPS 23–26 at 1600×900 with 40 hitches > 50 ms in 150 frames (iGPU, concurrent
render job — not a controlled benchmark); creature spawning is Sanctuary-only; no sitting-on-ground / lying /
stargazing; Luna's signature visuals missing; voice licence and VRM `commercialUsage: personalNonProfit` remain
release blockers (see `docs/RELEASE_CHECKLIST.md`).

## 5. Hardware finding — the GPU is not being used

`lspci -k`: the RTX 5050 (GB207M, Blackwell) lists only `nouveau` as a kernel module, and nouveau is blacklisted
(`/etc/modprobe.d`: `blacklist nouveau`, `modeset=0`). The only NVIDIA packages are the 550.163 **user-space
libraries** (`nvidia-driver-libs`) — no kernel module, and 550 does not support Blackwell anyway (needs ≥ 575).
`vulkaninfo` lists only the Intel iGPU; Godot prints "Using Device #0: Intel". Secure Boot is off, kernel
6.12.111 (Debian 13). **Every FPS figure in this project so far is the integrated GPU.**

To use the RTX 5050 the developer would install `nvidia-driver` ≥ 575 (Debian trixie-backports or NVIDIA's
installer; the DKMS module must build for 6.12.111) and reboot — a system change that interrupts the stream, so it
is a developer decision, not something this session does. Until then, every environment change is budgeted for
the iGPU.

## 6. Voice / API facts

* Phoenix voice confirmed by the developer: **Google Gemini TTS `Kore`** (`gemini-2.5-flash-preview-tts`).
  `GEMINI_API_KEY` is **not** set in this session's environment and is not a key name in `.env` / `.env.dev`
  (key names only were read; values never printed). No `google-genai` package is installed (system Python or
  `.venv-voice`); the REST endpoint needs only `curl` + the key. Integration will be written so it degrades to
  the local fallback when the key is absent, and the live proof needs the developer to provide the key.
* Mika/Luna voices unchanged (`data/voices.json`).

## 7. Tooling available for original assets

Blender 4.2.0 (used for the Hollow Sentinel: `tools/models/build_sentinel.py`), Python 3 with numpy/scipy,
ffmpeg, Godot 4.7.2 headless import. No paid image generation will be used (credits = money).

## 8. Plan (the directive's order), with checkpoints

1. **Environment pass** on the Whispering Woods against §4 (density/canopy, floor, river banks, waterfall, bridge,
   ruins, den, pond, night, vista) with before/after stills and a new route recording → checkpoint.
2. **K8 creature territories** (habitats, out-of-view spawning, patrol/guard/rest/investigate/retreat as real
   state) → checkpoint.
3. **Quiet scenes**: sit on the ground, lie down, stargazing, stand up; props stay attached → checkpoint.
4. Combat / spell identity; 5. Phoenix (Blender-scripted original model, Kore voice); 6. academy & NPC
   occupations; 7. world bible; 8. verification report.
