# The Whispering Woods (Milestone K)

The Arcane Sanctuary's wild hinterland, through the Sanctuary's north arch. An **original** 280 × 280 m area,
art-directed from the developer's ten reference images (used for mood only; nothing imported).

Code: `scripts/areas/whispering_woods.gd` (terrain, water, routes), `whispering_woods_dressing.gd` (vegetation,
cliffs, atmosphere), `whispering_woods_landmarks.gd` (built stonework, bridge, waterfall),
`scripts/world/nature_kit.gd` (stylized vegetation placement), `scripts/world/stone_builder.gd` (block-built
stonework), shaders in `shaders/nature/`.

## Art direction — what was taken from each reference

| Ref | Mood / motif | Where it lives |
|---|---|---|
| 01 Sanctuary garden path | soft painted sky, bright meadows, a dirt path leading the eye | the entry glade and arch, the painted sky |
| 02 Deep enchanted forest | layered greens, oversized leaves leaning over the trail, sun pouring through | the forest trail (entry → crossroads): giant leaf plants on the trail edges, ferns, twisted trees, light shafts |
| 03 Waterfall bridge | arched stone bridge in front of falling water, mist | the falls and the Old Bridge |
| 04 Hidden lotus pond | still water, willows, fireflies | the pond (west); fireflies over it at night — *lilies / willows still to do* |
| 05 Monster den | a cave mouth behind roots and leaves | east of the bridge — *den facade still to do* |
| 06 Forgotten ruins | a gate in overgrown walls, a tree grown into the ruin | the ruins plateau |
| 07 Forked stairway | stairs climbing under ruined arches, a side flight | the stairway and the alcove fork |
| 08 Moonlit forest | blue night, glowing life | night palette, fireflies — *glowing mushrooms still to do* |
| 09 Frontier road | a bleak road out | the frontier ridge road (NW) — *dressing still to do* |
| 10 Crystal valley | far-off crystals under strange skies | the inscription ("crystal vale") — *a distant vista still to do* |

## The route (verified on foot, recorded)

Entry arch → winding forest trail (canopy, giant leaves, light shafts) → **crossroads** (waymarker, stone lantern)
→ **forked stairway** (three pointed arches, one fallen; left fork climbs to the hidden **alcove**) → **ruins**
gate → colonnade → **inscription stone** → **viewpoint** terrace over the **waterfall**, the plunge pool and the
**Old Bridge**. From the crossroads the east trail reaches the bridge (bank path under its west arch) and continues
to monster territory; the west trail reaches the pond; from the ruins the frontier road climbs NW.

`--mktest=env` checks every landmark is reachable on the real navmesh (14/14) and takes the proof views;
`--mktest=walk` walks the whole route with Luna beside Mika under the game's own camera (used for the footage).

## Technical notes

* Water is carved out of the navmesh (`NavigationObstacle3D.affect_navigation_mesh`), so nobody wades through
  the river; the bridge deck is the crossing. River beds are level so water surfaces sit in them.
* Vegetation: ~550 trees, ~5.5k undergrowth, ~28k grass tufts, ~700 rocks, all chunked MultiMeshes with
  visibility ranges (grass 36 m, undergrowth 55–90 m, trees 170 m). Trees and big boulders have colliders; a
  boulder near a path is always too small to block it.
* Stonework is one mesh per structure (~1,500 blocks total) with a handful of box colliders.
* The stream machine currently renders on the **Intel iGPU** (the NVIDIA driver is not loaded), which caps this
  area at roughly 24–29 FPS in tests run while other jobs were active. Not a controlled benchmark.
