# The Whispering Woods (Milestone K)

The Arcane Sanctuary's wild hinterland, through the Sanctuary's north arch. An **original** 280 × 280 m area,
art-directed from the developer's ten reference images (used for mood only; nothing imported).

Code: `scripts/areas/whispering_woods.gd` (terrain, water, routes), `whispering_woods_dressing.gd` (zones,
canopy, understory, ground layer, grass, rocks, cliffs, atmosphere), `whispering_woods_features.gd` (forest-floor
features, the grove, banks, the pond's identity, the den hollow, the overgrown ruins),
`whispering_woods_landmarks.gd` (built stonework, bridge, waterfall), `scripts/world/nature_kit.gd` (stylized
vegetation, LOD and shadow stand-ins, vegetation colliders), `scripts/world/foliage_builder.gd` (vines, ivy,
willow curtains, roots, stumps, drifting leaves), `scripts/world/stone_builder.gd` (block-built stonework),
shaders in `shaders/nature/`.

## Art direction — what was taken from each reference

| Ref | Mood / motif | Where it lives |
|---|---|---|
| 01 Sanctuary garden path | soft painted sky, bright meadows, a dirt path leading the eye | the entry glade and arch, the painted sky |
| 02 Deep enchanted forest | closed canopy, layered greens, big leaves over the trail, sun through leaves | the DEEP zone (entry → crossroads): canopy trees lean over the trail, understory, ferns and big leaves at the trail edge, light shafts, drifting leaves |
| 03 Waterfall bridge | arched stone bridge with a balustrade before falling water, mist | the falls and the Old Bridge (balustrade of posts and rails, vines) |
| 04 Hidden lotus pond | willows over still water, a spring fall, lily pads, fireflies, mist | the pond: three weeping willows leaning over the water, the spring fall from the ledge with foam and mist, lily pads and lotus (glow at night), reeds, night mist |
| 05 Monster den | a root-and-vine hollow, dark with depth | the den: a twisted tree on the outcrop whose roots drape over the mouth, vines across it, a self-shaded cave interior, a nest of dry grass and old bones inside, one shaft of light |
| 06 Forgotten ruins | a gate in overgrown walls, a tree grown into the ruin, ivy | the ruins: ivy mats on walls and piers, vines from the gate, the engulfing tree with exposed roots, column capitals |
| 07 Forked stairway | stairs climbing under ruined arches | the stairway (vines on the arches) and the alcove fork |
| 08 Moonlit forest | readable blue moonlight, glowing fungi, fireflies | the night palette (blue moon, lifted ambient), the MUSHROOM GROVE beside the pond path (the only place fungi glow), fireflies |
| 09 Frontier road | a bleak road out | the FRONTIER zone: pines and dead trees on the ridge — *still lightly dressed* |
| 10 Crystal valley | far crystals under strange skies | the CRYSTAL VALE: a scenic landmark of giant violet spires on the eastern horizon (`data/world.json` → `crystal_vale`), seen from the viewpoint. **Not explorable** |

## The forest as an ecosystem

Zones (`WoodsDressing.zone`): glade · deep · clearing · ancient_path · grove · pond · streamside · falls_approach
· ruin_court · monster · frontier · wood. Each has its own species mix, density, floor and light.

Layers: **canopy** (~1,370 trees; Common, Twisted, Pine, Dead; trees within 6 m of a trail lean over it),
**understory** (~1,950 young trees, saplings, bushes), **ground** (~6,000 ferns, big leaves, clover, flowers,
small plants, mushrooms), **grass** (~12,700 tufts in the live profile), **features** (35 fallen trees, 33 stumps,
~150 exposed-root clusters at the biggest trees, moss boulders, riverbank stones and reeds, 21 light shafts,
27 drifting-leaf emitters, 82 grove mushrooms).

## The route (verified on foot, recorded)

Entry arch → winding forest trail → **crossroads** (waymarker, stone lantern) → **forked stairway** (three pointed
arches, one fallen) → **ruins** gate → colonnade → **inscription stone** → **viewpoint** terrace over the
**waterfall**, the plunge pool and the **Old Bridge**. Branches: the pond (west), the den (east, over the bridge),
the frontier road (north-west).

`--mktest=env`: every landmark reachable on the real navmesh (15/15) + proof views (`screenshots/mktest/env_*.png`,
cinematic copies in `screenshots/mktest/cinematic/`); `--mktest=walk`: the whole route walked with Luna beside
Mika under the game's own camera (the footage in `screenshots/mktest/clips/`).

## Technical notes

* **LOD**: every tree, young tree and bush has a far version (a lumpy crown blob + trunk, ~1/20 of the triangles,
  same palette and shaders) that cross-fades in at 62 m (canopy) / 36–38 m (understory, bushes).
* **Shadows**: crowns cast from a shadow-only blob punched with noise holes (`canopy_shadow.gdshader`) instead of
  their leaf cards — measured 31 ms → ~1 ms on the iGPU — and the sun uses one orthogonal split.
* **Vegetation colliders** sit on physics layer 3 (characters collide with it) and carve the navmesh through
  `NavigationObstacle3D` prisms; parsing 1,400 cylinders as geometry left tiny cap polygons that overflowed the
  navmesh edge-merge rasterizer.
* **Path search limit**: Godot's `NavigationServer3D.map_get_path` and `NavigationAgent3D` stop after 4,096
  polygons by default; a 13,000-polygon forest made the frontier "unreachable". All paths go through
  `NavQuery` / agents configured with a 200,000-polygon limit.
* Water is carved out of the navmesh (river, plunge pool, pond); the bridge deck is the crossing.
* **Quality tiers** (measured on the stream machine's Intel iGPU, 1600×900, other jobs running — not a controlled
  benchmark): live profile (0.75 scale, SSAO off in this area, 24 m vegetation chunks) 17–50 ms GPU per view,
  most views at the 30 fps cap, the deep forest 18–22 fps; cinematic profile 42–96 ms (10–23 fps). The RTX 5050
  in the machine has no working driver (`docs/V3_AUDIT.md` §5).
