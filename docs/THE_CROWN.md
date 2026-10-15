# Rising Air and the Crown (Level 100)

The Level 100 gate in `data/mages.json` has one requirement: *hear all nine rings (the Crown)*. Until now nothing in
the world could satisfy it. This is the content that does: a learned levitation spell, and nine bells you can only
reach by it.

## Rising Air: a learned levitation

Like the Fold Step, it is never given. It is learned in two steps:

1. **The founders' notes.** A real four-page book (`data/books.json` → `founders_notes`) on the mentor's desk at the
   foot of the Mentor's Tower. Reading it teaches the theory (`lore:rising_air`) and tells of the bells
   (`clue:crown_bells`).
2. **The word.** The last page, *Aer, tolle me!* ("Air, lift me!"), only appears once she understands that "magic
   follows the body". That is Master Aldric's lesson on footing at the Academy (`fact:magic_follows_body`). With
   both, `incantation:rising_air` is hers.

How it works (`MagicSystem.rise_to(caster, to)`):

* **Reach**: 6 m across (+4 per mastery) and 8.5 m up (+3 per mastery).
* **Sight**: she must see where she will set down. That can be from the ground, from the air once risen, or from
  above the spot as she floats out over an edge.
* **Open air**: a body-sized capsule is swept along the whole way and must be clear, with room to stand at the end.
* **The flight**: straight up, across at the higher level with 0.9 m clearance, then down. She moves at about
  1.1-1.6 m/s, eased, so TeleportGuard sees ordinary motion and never a jump.
* **On screen**: she pushes off (UAL Jump_Start), holds her hands out for the whole flight (Spell_Simple_Idle) and
  lands softly (Jump_Land). For Mika, a ring of leaves lifts round her feet (dusk motes for Luna), with a soft
  light and a low up-draught.
* `WorldCharacter.lifted` hands her body to the spell while she is in the air: no gravity and no walking.

## The Crown

The Mentor's Tower now has a crown walk (the top of its stone, round a slimmer turret) with no stair to it.
Round the turret hang **nine bronze bells** on an iron ring (`CrownChime`, `scripts/world/crown_chime.gd`), one per
Warden. Each bell sounds only for a mage who has "heard" that Warden's ring somewhere in the world
(`data/crown.json`, any one key):

| ring | Warden | heard by |
|---|---|---|
| 1 | Aelis | Master Aldric's first lesson, the breath before the word |
| 2 | Thane of the Deep Waters | sitting still and listening to the rain (`listened_to_rain`, see `docs/WEATHER.md`) |
| 3 | Verdance | the story of the forest grown in one night |
| 4 | Umbra | the lamplighter's story |
| 5 | Emberhart | the burning mountain |
| 6 | the Stonefather | the song that turned rock to crystal |
| 7 | the Weaver of Ways | a Fold Step made and crossed |
| 8 | the Mirror Queen | a ward that held (Leaf Ward / Gilded Mirror / Aldric's lesson on timing) |
| 9 | the Skyborn Twins | the ninth gate, opened together under the Twin Lights (Level 90) |

**The listening, at night only:**

1. The night wind comes over the tower (`bell_crown_wind`) and every bell starts to swing.
2. The ones she has heard ring one after another, each a different pitch. They are original synthesized bronze
   bells (`tools/audio/synth_bells.py`) in D-minor pentatonic, so any combination stays consonant. A glint rises
   off each bell as it sounds.
3. A bell she has not heard swings in silence, and she hears the gap.
4. **If all nine sound**, they ring together and a ring of light lifts off the bell-ring and hangs over the tower
   like a crown. This records `crown:heard_all_nine`, which opens the Level 100 gate.
5. Otherwise she remembers which rings are still silent (`crown:silent_N`). That is something to seek.

## In her own planner

`SanctuaryBrain` gets an **ascend** option, built from the area's `rise_spots()`. It appears only when all of these
hold:

* she can cast Rising Air;
* she has read about the bells;
* it is night;
* she has not yet heard all nine;
* she has not already been up tonight.

The walk:

1. She walks to the grass below the gallery.
2. She rises in two lifts: onto the gallery (6.8 m), then up to the crown (7.5 m). That is 14.3 m in all.
3. She listens to the bells.
4. She drifts back down the same way.

The tower's spiral stair turned out to be scenery only. Its first tread was 0.6 m off the grass (a short ramp of
steps now leads up to it), but higher up the walkway is too narrow for the navmesh, and its last two metres run
under the full-ring gallery floor with no headroom. So the gallery is reached by Rising Air too.

## Test

`--mktest=crown` (disposable save), PASS:

1. She cannot rise at first.
2. She reads the notes: the theory and the bells, but no word yet.
3. After the lesson she reads the last page: the spell is hers.
4. By day she has no reason to go up. At 22:30 her planner offers to.
5. With six rings heard: up 14.3 m in two lifts; six bells sound, three swing silent. She remembers which, and drifts
   back down.
6. With the rest heard (a fold, a ward, the ninth gate): all nine sound, `crown:heard_all_nine` is recorded, and the
   **Level 100 gate is open**.
7. Throughout: zero TeleportGuard violations.

Screenshots: `screenshots/mktest/crown_crown_{rising,bells,of_light}.png`.
