# Weather: rain, storms and shelter

The V3 directive asks for "an unexpected storm" and "listening to rain beneath shelter". `WeatherSystem`
(`scripts/world/weather_system.gd`) is one sky for the whole world, saved in `WorldState.weather`.

## The sky

* **Kinds**: clear, overcast, rain and storm. Each lasts some world hours. The next one is drawn from the region's
  leanings (`REGION_BIAS`): the highlands brew storms and the forests get showers. Caves and interiors stay dry
  (`sheltered_area()`).
* **Light**: weather is drawn on top of the area's own hour-by-hour light, never instead of it. `_mod` multiplies
  each property over the area's current value and re-bases whenever the area writes a new one. Under cloud:
  * the sun dims (storm: 3.10 to 0.98) and its shadows go soft (`shadow_opacity`);
  * the sky light mostly stays, which is what makes it read as overcast rather than dusk;
  * the haze thickens.
* **Rain**: 6000 GPU particles round the camera, drawn as soft streaks (transparent at the ends and edges) that keep
  vertical and fade near the lens.
  * A `GPUParticlesCollisionHeightField3D` follows the camera, so drops stop on roofs, canopies and arches and burst
    into tiny splashes. It does not rain under a roof.
* **Sound**: synthesized originals from `tools/audio/synth_weather.py`:
  * rain on leaves, or muffled on a roof when Mika is under one;
  * near and far thunder, which arrives as many seconds after the flash as the strike is far (about 340 m/s).
* **The first drops**: now and then one of the mages remarks on them.

## Shelter

`shelter_spots(p)` lists places to wait out the rain, nearest first, all on the walkable navmesh:

* **Doorsteps.** Every village house door now has a slated **door hood** on two timber brackets. It projects 1.3 m,
  so a person on the doorstep stands dry.
* **Stalls, the library and the quarters.**
* **The lee of a big tree.** These come from the area's trunk colliders (radius 0.3 m or more).

Roofs and door hoods carry a thin collider on their own physics layer (`HouseBuilder.ROOF_LAYER`, layer 10). Only
the "is something overhead" test sees it, so nobody walks on it and the navmesh never bakes onto a roof.
`sheltered_at(p)` is true under something solid, or close in under a big tree.

## What the mages do

Both mages' planners (`SanctuaryBrain`) have two options that apply to everyone, whatever their activity list:

| option | when | what happens |
|---|---|---|
| `shelter` | raining (more than 0.35), she is out in it, and a spot is near | Utility 0.7 + rain × 0.5, which beats nearly anything that is not urgent. She says "Over here - it's dry under here!" (Luna: "Under here. Move."), walks there, steps right in and turns to look out. |
| `listen_rain` | dry, with the rain all round, once per area per shower | Under a roof she sits down on the dry ground; under a tree she stands against the trunk. She listens for 22-40 s and says a quiet line ("I could fall asleep to this." / Luna: "I used to listen to this as a child."). It rests her, and the count is remembered (`listened_to_rain`). |

## Test

`--mktest=weather` (disposable save):

1. Waits for a clear sky, then a storm sets in. Checks the rain falls, the sun is dimmed, the rain is heard, and
   there is lightning and thunder.
2. In the **Whispering Woods** and then the **Village**, out in the rain, getting under cover is her top-ranked
   option. She ends up dry (a big tree, then a doorstep's hood) and listens: standing for 28 s in the woods, sitting
   for 37 s in the village.
3. The sky clears and the sun returns to its clear value.

Screenshots: `screenshots/mktest/weather_weather_{clear,storm,listen_whispering_woods,listen_village}.png`.
