# Visual quality report — the Whispering Woods environment pass (2026-10-14)

Before/after proof: `docs/screenshots/milestone_k/` — `woods_k7_before_*.jpg` (checkpoint `8b281aa`),
`refs_vs_k7_*.jpg` (each reference beside the K7 frame), `woods_k7b_after_*_live.jpg` (this pass, live profile),
`woods_k7b_after_cinematic.jpg` (cinematic profile). Full-resolution stills: `screenshots/mktest/env_*.png`.

## What changed, against the audit's defect list (`docs/V3_AUDIT.md` §4)

| Reference | Defect found in K7 | What this pass did | Honest state now |
|---|---|---|---|
| 02 Deep enchanted forest | open meadow, bare ground, sky everywhere, oversized identical plants | forest zones; canopy density ×2.5 with crowns leaning over the trail; a new understory layer; ferns/big leaves only framing the deep trail; darker leaf-litter floor; logs, stumps, roots, moss boulders; drifting leaves; light shafts only under dense canopy | reads as a closed, layered wood with the trail arching through it (`after_main_route_live.jpg`); still less lush than the painting at the floor level (the kit has no moss mats or hanging epiphytes) |
| 03 Waterfall bridge | clean bridge, bare banks, parapet cubes | balustrade (curb, posts, rail), riverbank sediment, half-submerged stones (the water foams round them), reeds, pond/river water sheen, wet stones at the lip | the bridge and falls read as one landmark from the viewpoint; the river banks still want more rock shaping |
| 04 Hidden lotus pond | open sunny pond, blocky rocks, tiny pads | three weeping willows (original curtain geometry) leaning over the water, the spring fall from the ledge with foam and mist, reeds, bigger lily pads and lotus (glow at night), night mist and a cool fill | the night shot is close to the reference's mood; by day the water is still a flat turquoise (no reflections in the live tier) |
| 05 Monster den | grey dome, fog-washed grey arch | self-shaded cave interior (fog-free shader), a twisted tree on the outcrop with roots draped over the mouth, vines across it, a nest of dry grass and old bones, one light shaft, a dim fill light | reads as a dark hollow with depth; the vines over it use the dark palette and read drab; no scratches/decals yet |
| 06 Forgotten ruins | clean toy-cube blocks, open sky | block chamfer/size variation, ivy mats on walls and piers, vines from the gate and the arches, the engulfing tree scaled up with exposed roots, column capitals, a half-open ruin court with trees | overgrown and weathered; still cleaner than the painting (no broken-corner blocks, no rubble piles) |
| 07 Forked stairway | strongest view already | vines on the arches, capitals, trees closer | good |
| 08 Moonlit forest | crushed black | blue moon (0.55, cool), lifted night ambient, thinner night fog, the mushroom grove (the only glowing fungi), fireflies, pond mist | readable and atmospheric (`after_night_live.jpg`) |
| 09 Frontier road | undressed | pines and dead trees by zone | still lightly dressed (not on the main route) |
| 10 Crystal valley | nothing | the Crystal Vale scenic landmark (violet crystal spires, east), fog thinned so distant scenery exists | a faint distant reveal from the viewpoint; **not explorable, labelled so** |

## Measurements (stream machine, Intel iGPU, 1600×900, other jobs running — not a controlled benchmark)

Per-view GPU time from `RenderingServer.viewport_get_measured_render_time_gpu`, live profile:
entry 36 ms · walking forest 50 · canopy trail 42 · crossroads 37 · bridge 27 · pond 30 · den 17–22 · ruins 25 ·
stairway 36 · viewpoint 32 · waterfall 27 · grove 35 · crystal vale 30. Most views sit at the 30 fps cap; the deep
forest views run 18–22 fps. Cinematic profile: 42–96 ms (10–23 fps).

What the measurements decided (each change was measured in isolation on the heaviest view):
foliage shadows 31 ms → ~1 ms (shadow blobs); 64 m → 24 m vegetation chunks −12 ms; SSAO −7 ms (off in this area
for the live profile); understory ~8 ms (kept, with its own LOD); light shafts, hard shadow filtering and a
closer LOD swap changed nothing measurable.

## Still open (environment)

* A real GPU driver (`docs/V3_AUDIT.md` §5) is the only route to the cinematic tier on this machine.
* Lily pads render black under the cinematic post-processing stack (material issue, being fixed).
* Frontier road dressing, monster-territory identity (tracks, bones outside the den), river bank rock shaping,
  rubble in the ruins, day-time water reflections, wildlife beyond birdsong/fireflies.
* The Sanctuary hub itself (reference 01's blossom trees) is untouched this pass.
