# World scale, travel and the no-teleport rule (V3 continuation, 2026-10-15)

## Audit: what the world was
* **6 canonical regions** (`data/world.json`): Arcane Sanctuary, Enchanted Forest, Fantasy Village, Crystal Caverns,
  Celestial Highlands, Grand Academy. **14 playable areas**, each a 60–280 m pocket (the Whispering Woods is the
  largest at 280 m). Only one area is loaded at a time; other mages live in an abstract background simulation.
* **Travel** = walk to an area's gate, then a masked streaming load into the neighbour. From Sanctuary to the Celestial
  Summit was 4 gate hops, about 5 minutes. Region-to-region distance was in practice the width of two pockets.
* **Global positions** (`global_pos`, landmark impostors) put the regions only 0.5–3.5 km apart.
* **Teleport paths found**:
  * travel mode `"fast"`: a masked jump along visited routes;
  * the `sanctuary ↔ academy` "ley-line portal" connection: a free landmark hop;
  * `PhoenixManager.bring_luna()`: placed Luna beside Mika when Oriel came;
  * test and tour utilities (developer only).
* **No calendar**: only a night on/off flag (`WorldState.night`). Nothing could take "several days".

## Done in this pass (no teleportation)
* `"fast"` travel is refused unless the game runs with `--dev-fast-travel` (tests / tools only). The action bridge no
  longer offers it.
* The ley-line gate is **sealed** (`connections[...][3].sealed`, `WorldState.is_sealed`, never routed, its gate
  trigger ignored). Reopening such a gate is spatial magic to be *discovered* later (see below).
* `PhoenixManager.call_luna()` replaces `bring_luna()`:
  * Luna in the same area hears Oriel and **walks** over;
  * Luna in another area **stays there**, and the encounter goes on without her.
* `TeleportGuard` (`main.teleport_guard`) watches every visible mage every physics frame. A jump over 1.5 m outside an
  area load or explicit developer staging is recorded as a violation.
* Proof: `--mktest=no_teleport`, 7/7 checks:
  * instant travel is refused, and the portal is no route;
  * Luna stays in the village;
  * Luna walks 31 m with a largest step of 7 cm per frame;
  * 60 s of autonomous life with both planners shows 0 violations over 5,381 frames.

## Plan: an enormous world that takes days to cross
Distances below are the canonical overland routes between the existing areas (names kept; waypoints are new places
along them). Walking pace is ~4 km/h for ~7 h a day on roads, less on climbs and bad ground.

| route (existing connection) | km | terrain | days | along the way |
|---|---|---|---|---|
| Whispering Woods → Ancient Grove ("the old forest track west") | 46 | deep forest | 2 | Fernhollow (woodcutters' hamlet, safe), Mossfall Ford, campsites; Mossback territory |
| Ancient Grove → River Valley ("forest track down to the river") | 22 | forest, descent | 1 | the Shrine Steps, river meadows |
| River Valley → Village ("the waterfall bridge road") | 31 | river road | 1–2 | Waterfall Bridge, the Millbrook inn |
| Village → Crystal Caverns ("quarry road to the cave mouth") | 26 | quarry road | 1 | quarry camps |
| Village → Highland Path ("mountain road") | 38 | climbing road | 2 | Shepherd's Hut (shelter), switchbacks |
| Highland Path → Celestial Summit ("summit stairway") | 9 (+1,400 m) | stairs, thin air | 1 | the Cloud Gate |
| Whispering Woods → Highland Path ("the frontier road over the north-west ridge") | 64 | ridge, pass | 3 | the Cairn shelter, the Ridge Pass (dangerous in weather) |
| Village → Grand Academy ("the old academy road east"; connected 2026-10-15: gates on the Village's south road and the Academy's south lawn - before that the Academy could only be reached through the sealed portal) | 72 | lowland farms | 3 | Thornwick (farming village), Greywater Bridge, the Lantern inn |

So Sanctuary → Grand Academy, overland, is about 7–8 days. The local links inside a region (Sanctuary ↔ library,
tower and Woods; caverns ↔ deep caverns; village ↔ observatory) stay walkable pockets.

**How it will be played (next):**
* A persistent **world clock** (days and hours, saved, with catch-up after a restart).
* A persistent **journey state**: destination, purpose, route legs, km done, day, party, condition, supplies, events,
  discoveries and unfinished business.
* **Wayside** pockets generated per leg, seeded by route and km, in the leg's biome: the places where the party stops
  to camp, meet someone or meet something.
* Between stops the time passes at road pace, with the overland map and the characters walking. It is never a cut to
  black that moves them.
* Off camera, a journey advances at the same pace in the background simulation.

**Teleportation as a future discipline**: clues in manuscripts, spatial anomalies, professors and ruins; separate study
records per mage; trials, failures and partial techniques. Not unlocked in this pass.

## Living roads (2026-10-15)

* **Waypoints are places.** When a stretch of road passes a waypoint (`data/overland.json`), the Wayside builds it
  at the roadside where its km falls: hamlets and villages with houses, a woodpile, a garden and their people
  (Garth and Nell at Fernhollow, Ada and Tamsin at Thornwick), inns with a hanging sign, a bench and a keeper (Hob
  at the Millbrook inn, Marta at the Lantern inn), stone shelters, landmarks (the Old Ash; carved stones and
  cairns). Their people live through TownLife (`data/residents.json` "wayside:<id>").
* **Someone on the road** (`data/encounters.json`, `JourneyDirector._road_encounter`): about one stretch in six, in
  daylight, a pedlar, a pilgrim or a lost traveller comes the other way; they meet halfway, talk (their own voice),
  trade (food) and pass on a rumour that becomes the mages' own knowledge - which the expedition planner can turn
  into the next journey. `--mktest=road`: pedlar met, food 6 -> 9, rumour "news:academy_open_lessons" -> an
  expedition option "set out for the academy".
* **Every road is walkable.** `--mktest=navcheck` walks every gate of every area: it found the Highland Path's and
  the Summit's gates cut off from their trails (the region rim and a too-narrow ridge left 40-80 degree steps), the
  Observatory Hill's gate outside its navmesh bake band, and boulder colliders that routes ran into. Fixes: the rim
  opens along every road; trails are graded (no metre steeper than ~23 degrees, cut and fill with gentle sides,
  never filling a stream); the summit stairway follows its ridge's crest on a wider ridge; navmesh bakes span each
  area's real height range; boulders near paths stay scenery; a long walk's deadline follows its length; a party
  that reaches a gate's mouth may cross.
