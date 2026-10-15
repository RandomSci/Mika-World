# Town life — the people who live in the Village and the Academy

The master directive asks for a living civilization: villages with professions, an academy with real students,
teachers and researchers, NPC schedules. `TownLife` (`scripts/npc/town_life.gd`) and `Resident`
(`scripts/npc/resident.gd`) are that layer; `data/residents.json` is who lives where.

## Who lives there

| area | resident | role | look (Quaternius CC0 kit) | voice (Edge) |
|---|---|---|---|---|
| Village | Bram | the blacksmith | male peasant, buzzed hair, beard, darker skin | en-AU-William |
| Village | Hilde | the baker, with a market stall | female peasant, buns | en-GB-Hollie |
| Village | Wenna | the herbalist, grows what she sells | female peasant (green), long dark hair | en-IE-Emily |
| Village | Odo | farmer and woodcutter | male peasant, parted hair, beard | en-GB-Oliver |
| Village | Captain Rook | the village watch | ranger (steel) | en-GB-Alfie |
| Academy | Master Aldric | teacher of the elemental arts | ranger (violet), grey hair, beard | en-GB-Elliot |
| Academy | Sister Maren | the librarian | female peasant (wine), grey buns | en-GB-Bella |
| Academy | Lysa | second-year student | ranger (academy blue), fair long hair | en-AU-Natasha |
| Academy | Corin | first-year student | peasant (academy blue) | en-IE-Connor |

The characters are built by `tools/models/build_rival.py ... '{"clipset": "townsfolk"}'` (outfit + base-character
head + hair + 37 Universal Animation Library clips: walk, formal walk, carry, chair sitting, talking, farming,
chopping, kneeling repair, lantern, leaning, spell practice, nods, a dance) and slimmed with `slim_glb.py`
(46 MB for all nine).

## A day

Each resident has a schedule of `[hour, activity, anchor]` blocks. Anchors are places the area registers
(`AreaBase.add_anchor`): house doors (`home:N`, from `HouseBuilder.doors`), stalls (`stall:N` behind the counter,
`stall_front:N` for customers), the forge / workbench / woodpile, benches (`bench_seat:N`, `seat:N`, real benches
at chair height built by `AreaBase.seat_bench`), the well, conversation spots on the square, gardens, street
lamps, the academy's quarters, lecture spot, practice spots round the arena circle, the library door.

Activities: **sleep** (they go in at their door and are gone until morning), **work** (their trade's clips with
the tool in hand: Odo's axe, Bram's hammer, Rook's lantern, Wenna's bucket), **vend** (behind the counter),
**shop** (at a stall front), **draw_water** (at the well, then carried home), **eat** (sitting on a bench; they
talk if someone sits near), **socialize** (face whoever is near, talk, nod), **patrol / watch** (lamp to lamp
with a lantern at night), **teach** (talking, demonstrating a small spell), **attend** (sitting in the class),
**practice** (enter, hold, cast, exit: a small orb of light flies), **study** (into the library), **stroll**.

## No cost off-camera, no drift

Nothing is simulated while an area is not loaded. When the Village or the Academy becomes active, every resident
is placed where their own schedule puts them at the current hour (already working, already inside for the
night) and lives on from there. They move only by walking the navmesh at walking pace (`--mktest=town` checks
that no one ever moves faster than a walk could carry them); a person who went in at the library comes out of the
library.

## The mages

Residents notice Mika and Luna: within ~4.5 m they turn to her and nod; once a day each, and only when no one
else in town has spoken in the last 20 s, they say something from their own lines (`greet`, `night`, a
teacher's `teach`) in their own voice. She glances back. Each meeting is remembered in
`WorldState.npc_state["res:<id>"]` (`noticed_<mage>` = the day, `met_<mage>` = how often).

## Talking with them

Each resident has a few things to say to the mages (`talk` in `data/residents.json`): Hilde presses a warm loaf on
her, Wenna explains moonpetal, Bram has lost his hammer, Rook has seen lights on the observatory hill, Master Aldric
gives advice, Sister Maren points to the Wardens' grimoire, Lysa and Corin want to practise together. A "chat"
option appears in the mages' own planners for a resident she can see, at their place, with something new to say
(weighed by her social need); she walks up, they turn to her and speak in their own voice, she answers, and what
they told or gave her is hers (`talked:<id>:<topic>`, items, clues that can start expeditions).

## Tests

`--mktest=town` (disposable save): the Village at 10:00 (each at their place, the watch asleep), Odo chopping
with an axe in hand, noon to evening at 2 world minutes per second (they walk to their next places; no jumps),
Mika walks up to someone (noticed, glance back), night (indoors, the watch out with his lantern), the Academy at
9:00 (a lesson: the teacher standing, two students on the benches) and 11:00 (spell practice in the arena).
Screenshots in `screenshots/mktest/town_*.png`.
