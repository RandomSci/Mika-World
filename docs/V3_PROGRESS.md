# Mika World V3 — progress against the "Living Universe" directive

Running record. Every item below says how it was verified; anything not verified in Godot is marked as such.
Companion documents: `docs/V3_AUDIT.md` (the audit), `docs/V3_VISUAL_REPORT.md` (environment before/after),
`docs/WHISPERING_WOODS.md` (the area), `docs/ASSET_SOURCES.md` (licences).

## Checkpoints (branch `milestone-k`)

| Commit | What |
|---|---|
| `8b281aa` | K7: the Whispering Woods route (blockout + first dressing) |
| `5bccd29` | K7b: the environment pass (forest ecosystem, water, den, ruins, pond, night, vista, LOD/shadow stand-ins, navigation fixes) |
| `4ef0a27` | K8 creature territories + quiet scenes (ground sitting, lying down, stargazing together) |
| *(next)* | K5/K6 the two spell families, wards, creature control effects, family training duels (V3 Part XIII) |

## 1. Environment (directive Part III) — see `docs/V3_VISUAL_REPORT.md`

Done and photographed: forest layers and zones, river banks and half-submerged stones, the waterfall with mist,
the balustraded bridge, the lotus pond with willows and its spring fall, the den as a root-and-vine hollow with a
dark interior, the overgrown ruins, the glowing grove and a readable moonlit night, a distant Crystal Vale.
Open: frontier-road dressing, rubble in the ruins, daytime water reflections, wildlife beyond birdsong and
fireflies, lily pads black under the cinematic post-process stack, the Sanctuary hub's own polish.

## 2. Creature territories (directive Part XII / K8) — `data/habitats.json`, `scripts/combat/territory.gd`

Habitats own populations: species mix, max alive, day/night activity, respawn delays lengthened by defeats
(persisted in the save under `habitats`, recovering over game time), spawn points inside the habitat only, never
in a safe zone, never within 14 m of a mage, never where the camera could watch them appear (frustum + line of
sight). Creatures live in their territory through real states in `Monster`: **patrol** (navmesh paths round
trunks and boulders, pauses, looking about), **guard** (the lair's post, scanning, a wider alert radius),
**rest** (lair / perch by day for night creatures, slow healing, half perception), **investigate** (walk to a
noise — a spell, running steps, a fight — look around, return), **withdraw** (a badly hurt lair creature breaks
off and goes home to rest; it fights again if followed in). Perception needs a clear line of sight. A mage who
*sees* a creature remembers it (bestiary knowledge) without fighting.

Verified by `--mktest=territory` (5 game-minutes, PASS 13/13): 7 spawns, none visible to the camera, none near
the route, all inside their habitats; routines observed: patrol / rest / investigate / withdraw → rest; day 2 →
night 6 creatures; a defeat recorded and saved. Stills of creature behaviour: `screenshots/mktest/territory_creature_*.png`.
Not done: new creature models (K4), territory sounds, tracks/bones outside the den.

## 3. Quiet scenes (directive Part VII) — `scripts/brain/companionship.gd::_stargaze_together`

* New clips (Quaternius UAL, CC0, second pack `assets/animations/ual/ual_rest.glb`): floor sitting (enter /
  idle / talking / exit), the get-up from lying (held at frame 0 = the lying pose; played backwards = lying
  down), crouch idle, talking idle, kneeling.
* Ground sitting: the clip is authored at chair height, so the visual root lowers 0.33 m and `PoseAdjust`
  raises the thighs and solves each knee so the heel rests on the floor. Lying: the held pose with procedural
  breathing (chest/spine), root raised 8 cm so the head and heels rest on the grass.
  `WorldCharacter.lie_down()` / `get_up()`.
* The stargazing joint activity: Mika's planner can invite Luna at night (`together:stargaze`); they walk to
  the area's `stargaze_spot` (data), settle 1.3 m apart, lie down one after the other, look up, speak a few
  short lines with real pauses (heads turn to whoever speaks, then back to the sky), lie quietly, get up.
  Each keeps her own memory. The camera's `stargaze` mode alternates a close high three-quarter (faces) and a
  low side view (bodies, the sky over the trees); never from the feet (a skirt).

Verified by `--mktest=rest` (pose metrics on the skeleton) and `--mktest=stargaze` (the real invitation →
scene, PASS 9/9: both lay 60 s on their backs, 11 lines, camera on the stargaze framing with no violations,
both stood up, both remember). Stills: `screenshots/mktest/rest_*.png`, `screenshots/mktest/stargaze_*.png`.
Not done: reading with a physical book (the developer's lectern work in progress covers reading), sunset-by-a-
lake and the other scenic moments, hair/skirt behaviour on uneven ground.

## 4. Recording artefact fixed

Movie Maker recording runs real time much slower than game time; three timers used real time (the companion walk
timeout, the training duel, the character's action deadline). All are on game clocks now, so recorded scenes
behave exactly like live ones.

## 5. Spell identity and defence (directive Part XIII) — see `docs/SPELL_FAMILIES.md`

Two families, different in geometry, posture, energy, timing, motion, impact, sound and defence:
**Mika / Sylvan** — Gale Spiral (her signature now: a two-handed sweep, leaves lifting round her feet, a weaving
helix of two ribbons shedding leaves, a burst that shoves the creature back), Verdant Bind (a seam along the ground,
a cage of grown roots that holds a ground creature — no moving, no attacking — then withers), Leaf Ward (a ring of
leaves orbiting her that really stops the next two bolts from any side). **Luna / Umbral** — her lance, Umbral Rift
(shadow drawn into her palm with circling shards, a gold line that snaps to the mark, a hexagonal rift, dark crystal
spikes that erupt and daze, a scar that stays) and the Gilded Mirror (a hex pane that stops one bolt from the front
only and, once practised, throws it back). Creatures carry the effects (`Monster.bind / daze / push`), wards are
judged by the bolt's real path (`Ward`, `AttackHazard`), the tactics pick the technique from the moment
(`CombatTactics.family_spell / ward_spell`, cooldowns), training duels throw family bolts and use wards. Original
sounds for the nature element, wards, roots and rifts (bell-free). The Arcane Orb stays Mika's first lesson.

Verified by `--mktest=spells` (PASS, 44 checks: phases from the clip, real push / hold / daze / scar, wards stopping
real bolts with honest limits — spent after two, front-only mirror, reflection only at Adept — tactics choices, two
planner fights using the techniques, the sounds), `--mktest=duel` (PASS 12/12: 70 s bout, 10 wards cast, 8 bolts
really stopped, camera two-shot 2208/2209) and `--mjtest=signature --who=mika` (PASS 10/10 with the new signature).
Stills: `screenshots/mktest/spells_*.png`, grids `docs/screenshots/milestone_k/spells_k5_*.jpg`; footage
`screenshots/mktest/clips/spells_k5.mp4` (72 s) and `duel_k5.mp4` (90 s), real game camera, live profile, 1600×900 (the project's viewport; Movie Maker records the window size).
Not done: creature-side spell languages for shamans / demons / demigods (no such NPCs yet), levitation / flight /
spatial travel (Part 62-63), Luna's signature visuals beyond the lance, a skirt-safe roll, a decal for the rift scar.

## Still open from the directive (in order)

the Phoenix (Part X), academy and NPC occupations (Part V, VIII), the world bible (Part IV), mythology (Part XVII),
advanced magic (Part 62-63: shields beyond wards, counterspell combinations, levitation, teleportation as a learned
spell), the Sanctuary hub polish, the GPU driver (hardware).
