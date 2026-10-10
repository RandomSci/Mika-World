# Mika World 2.0 — streamed fantasy world (Godot 4.7.2, DEV)

The real Mika (her VroidStudio VRM, MToon shading, expressions, spring bones) lives in a **streamed world of 6 regions,
13 areas and 24 playable locations**. Only the area she is in is loaded; neighbouring areas preload on worker threads as
she approaches a route, and travel is a short masked transition. She walks, runs, casts the Arcane Orb, draws a magical
great-sword, does real activities that change world state, and can be driven by an external AI over an isolated
localhost bridge. Fully separate from the production Three.js stream, OBS, YouTube and production services.

![village observatory](docs/screenshots/world/live_optimized_village_observatory_view1.jpg)

## Launch

```bash
cd ~/Downloads/Mika-Godot-Dev
./run.sh live                 # LIVE_OPTIMIZED (recommended default; Forward+/Vulkan, 30 FPS cap)
./run.sh                      # CINEMATIC
./run.sh compat               # OpenGL Compatibility fallback
./run.sh live --start=village_square     # start at any of the 24 location ids (see data/world.json)
```
Exact command: `~/Downloads/Godot-Engine/Godot_v4.7.2-stable_linux.x86_64 --path ~/Downloads/Mika-Godot-Dev -- --profile=live`

Fresh clone: run `tools/setup_local_assets.sh` (re-copies git-ignored Mixamo files), then open the editor once or run
`--headless --import`.

### Controls
| Input | Action |
|---|---|
| WASD / Shift | move / run (camera-relative) |
| Mouse (click to capture, Esc release), wheel | orbit, zoom |
| Space | cast Arcane Orb |
| E | perform the nearby activity shown on screen |
| R / F / G / T | sword: draw-sheathe / 3-hit combo / elemental charge / next element |
| walk into a route (path end, crypt stair, bridge road, cave mouth, portal…) | travel to the neighbouring area |
| N · P · H · F12 | day-night · profile · HUD · screenshot |

## World

| Region | Area (streaming unit) | Locations |
|---|---|---|
| Arcane Sanctuary | sanctuary | A1 Ritual Sanctuary · A2 Mage Training Grounds |
| | arcane_library (interior) | A3 Ancient Spell Library |
| | mentor_tower | A4 Mentor's Tower (walkable spiral stair + lookout) |
| Enchanted Forest | ancient_grove | B1 Ancient Grove · B4 Forgotten Forest Shrine |
| | river_valley | B2 Luminous River · B3 Waterfall Crossing (walkable arched bridge) |
| Fantasy Village | village | C1 Village Square · C2 Lantern Market · C3 Craft Workshop |
| | observatory_hill | C4 Village Observatory |
| Crystal Caverns | crystal_caverns | D1 Crystal Entrance · D2 Luminous Crystal Hall |
| | deep_caverns (interior) | D3 Underground Lake · D4 Ancient Vault |
| Celestial Highlands | highland_path | E1 Mountain Path · E2 Cliff Overlook |
| | celestial_summit | E3 Celestial Observatory · E4 Cloud Temple |
| Grand Academy | academy | F1 Academy Courtyard · F3 Advanced Magic Arena · F4 Academy Gardens |
| | great_library (interior) | F2 Great Library |

All 24 locations have their own geometry, landmark, navigation and at least one real activity (study, meditate, practise,
collect, craft, trade, observe, pray…) whose effects are recorded in `WorldState` (skills, knowledge, inventory, discovered
locations). Some activities have requirements (e.g. the vault seal needs a crystal shard; brewing needs luminous water).

Routes (`data/world.json` → `connections`) are physical: forest path through the north arch, crypt stairway under the west
ruins, east trail, a ley-line portal (only between the two schools of magic), forest track, the waterfall bridge road,
hill stairway, quarry road and cave mouth, descending tunnel, mountain road, summit stairway, library doors.

Landmarks are honest: the vista places impostors (Cloud Temple peak, Academy spires, Mentor's Tower, village lights,
observatory dome) in their **true world-map direction** from the current area. The registry marks each as `destination`
(with its playable location), `scenic` (Dragon Peaks, Floating Sky Spire — never reachable) or `unfinished`
(Sunken Citadel — visible, planned, refused by `travel_to`).

## Architecture

```
data/world.json                      registry: regions, areas, 24 locations, routes, landmarks (stable ids)
scripts/core/world_state.gd          authoritative state: discovered/visited, activity log, skills, inventory, routing
scripts/world/world_streaming_manager.gd  threaded 2-phase preload (scene → declared resources), LRU cache (3 areas),
                                     validated swap, unload + cache release, budgeted activation, async nav bake, metrics
scripts/world/travel_controller.gd   journeys: walk to the gate of each hop (next area preloads meanwhile) or fast travel
                                     on visited routes; player gate crossings; proximity preloading
scripts/world/area_base.gd           per-area environment/day-night, locations, gates, interactables, nav bake
scripts/world/kit.gd, kit_area.gd    shared CC0 PBR materials, bevelled architecture primitives, props, scatter, terrain
scripts/world/vista.gd               honest landmark impostors (+ optional cloud sea)
scripts/areas/*.gd, scenes/areas/*.tscn   the 13 areas (sanctuary.gd is the original sanctuary, now streamed)
scripts/characters/world_character.gd     Mika (any VRM humanoid): movement, step-up, actions, expressions, VRM1 MToon fix
scripts/characters/sword_layer.gd    optional magical great-sword layer (docs/SWORD_ANIMATIONS.md)
scripts/bridge/action_bridge.gd      isolated JSON bridge on 127.0.0.1:47651
tools/mock_brain.py                  autonomous traversal over the bridge (no keyboard)
scripts/world_tour.gd, face_test.gd, tools/anim_preview.gd   verification tools
```

## AI bridge (DEV only, 127.0.0.1:47651)

Commands: `observe`, `list_regions`, `list_locations{filter}`, `travel_to{location, mode: walk|fast}`, `transition_state`,
`navigate_to{target, run}`, `look_at|face{target}`, `nearby_interactables{radius}`, `interact{object}`, `cast_spell`,
`start_training`, `sword{action, element}`, `landmarks`, `world_state`, `set_time{night}`, `stop`, `probe_space` (debug).
Events: `journey_started/progress/finished`, `area_activated` (with transition metrics), `action_started/finished`,
`cast_phase`, `activity_done`, `player_crossed`.
Every result comes from the engine: refused actions say why (unknown/unfinished location, unreachable, too far,
requirements unmet, transition in progress, not enough space to cast).

```bash
./run.sh live &   python3 tools/mock_brain.py      # chooses, travels to and acts at every location autonomously
```

## Tests and measurements

See **docs/WORLD_REPORT.md** (performance per location in LIVE and CINEMATIC, casting, transitions, memory cycles,
autonomous traversal results). Face fix: docs/FACE_SHADING_FIX.md. Sword animations: docs/SWORD_ANIMATIONS.md.
Assets and licenses: ASSETS.md (all environment assets CC0; Mixamo files local only; Mika.vrm licence notes).

## Adding an area
1. Add the area + its locations + a connection to `data/world.json`.
2. Write `scripts/areas/<area>.gd` (`extends KitArea`; `resources()`, `env_preset()`, `build_steps()`, `add_location`,
   `add_gate`, `add_interactable`), run `python3 tools/make_area_scenes.py` and `--headless --import`.
3. Add the matching gate in the neighbour area; verify with `tools/mock_brain.py`.
