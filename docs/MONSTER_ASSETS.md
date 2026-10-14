# Monster assets — direction (2026-10-14, updated 2026-10-15)

The developer: "Stop relying on overly simple placeholder monsters for hero scenes. Search and import better free
monster assets, prioritizing Quaternius Ultimate Monsters, Quaternius Bestiary Dungeon Monsters Kit, and
higher-quality free downloadable CC monsters/creatures from Sketchfab where appropriate."

## Done
- **Mossback** (2026-10-15, `data/monsters.json` → `mossback`; the prominent Woods encounter): OpenGameArt
  **"Forest Monster"** by Čestmír Dammer (CDmir), https://opengameart.org/content/forest-monster — **CC0** (stated on
  the page and in the archive's own `Licenses.txt`: "License: Creative Commons (CC0)"; textures derived from Rick
  Hoppmann's, relicensed CC0 by the author in 2015). A realistic stone-and-moss troll with a young tree rooted in its
  back: 2.8k-vertex body + leaf cards, 2048² diffuse / normal / specular / baked AO, a 76-bone rig and its own
  animations (idle, walk, melee hold, attack with charge/strike/cooldown sub-ranges, dying).
  `tools/models/build_forest_monster.py` rebuilds PBR materials from its textures (AO multiplied into the colour,
  roughness from the specular map, alpha-clipped leaves), drops the rig helpers and exports the game's clip set
  (idle, walk, alert, windup, strike, recover, hit, death) to `assets/creatures/mossback/mossback.glb` (~3.6 m tall in
  game). Attacks: a heavy claw sweep and a ground slam whose shockwave throws anyone else near (ImpactDirector).
  Verified in Godot: `--mktest=mossback` (the Woods, Mika and Luna fighting it with their own tactics).
- **Briar Imp** (`data/monsters.json` → `briar_imp`): Quaternius **Bestiary – Dungeon Monsters Kit** (free Standard tier,
  QAL licence: free in games, no credit required, the raw assets may not be redistributed as assets). A sculpted,
  PBR-textured creature (base colour, normal, ORM, emissive eyes) on the Unreal-style skeleton; it ships without
  animations, so `tools/models/build_bestiary.py` bakes nine Universal Animation Library clips (CC0; rotations only + the
  pelvis's own motion) into `assets/creatures/bestiary/imp.glb`: idle (Zombie_Idle), run, alert, windup (Zombie_Scratch),
  strike (Melee_Hook), hit, knockback, death. Driven by `ClipRig` in its new `ground` mode (no flyer bob/bank/rear) with
  `keep_materials` (the model's PBR is kept; its emissive eyes survive hurt flashes). Attacks: a claw sweep and a
  lunging charge. It replaces the procedural placeholder (`thornback`, legacy body) in the Phoenix hero scenes
  (`--mktest=phoenix`, `--mktest=phoenix_reel`).
- The kit's second free creature, the **Puglin**, is downloaded (`~/.cache/mika_dl/bestiary`) and builds the same way
  (`build_bestiary.py ... Puglin.glb ...`) — a candidate for a small skirmisher species.

## Candidates checked 2026-10-15
| Candidate | Licence | Downloadable without an account? | Rig / animation | Verdict |
|---|---|---|---|---|
| OpenGameArt Forest Monster | CC0 | yes | rigged, 5 animations | **imported (Mossback)** |
| Quaternius Ultimate Monsters | CC0 | Google Drive only - "Quota exceeded" again on 2026-10-15; the official page has no other link | animated | blocked; stylized low-poly anyway (background creatures only) |
| Quaternius Bestiary (Imp, Puglin) | QAL (no standalone redistribution) | yes | rigged, no animations (UAL baked) | Imp in use; Puglin ready to build |
| Sketchfab Faceless Bonewing Horror Beast | CC BY 4.0 | needs a Sketchfab login | not stated | blocked; 767k triangles - far over a livestream budget |
| Sketchfab Realistic Monster Game-Ready Animated | no licence named; sold via ArtStation | no download button | 6 animations | rejected (not free) |
| Sketchfab Free Creature Character | CC BY 4.0 (author: no credit needed) | needs a Sketchfab login | not stated | blocked (account) - 122k tris, armoured humanoid |
| Sketchfab Undead Horror Creature | CC BY 4.0 | needs a Sketchfab login | not stated | blocked; 963k triangles - too heavy |
| Sketchfab Chinese Dragon | CC BY 4.0 | needs a Sketchfab login | rigged + animated | blocked (account) - the best future candidate (50k tris) |
| DreamKit Monster Pack | CC0 | free tier: 5 models | rigged, no animations | rejected for hero scenes (low-poly gradient style) |

To unblock Sketchfab the developer would need to download the file by hand while signed in (never by sharing
credentials with the build); the import path is then the same as the Mossback's.

## Blocked / next (2026-10-14)
- **Quaternius Ultimate Monsters** (CC0, 50 animated): its only download is a Google Drive folder; Drive refused the
  files ("Too many users have viewed or downloaded this file recently") on 2026-10-14. The 247 file ids are saved in
  `~/.cache/mika_dl/ultimate_monsters_file_ids.txt` for a retry. Note it is flat-shaded low-poly (one colour atlas):
  good for distant/ambient creatures, not a step up for hero close-ups.
- **Sketchfab**: downloads need a logged-in account (or an API token) — not available to the build. Candidates to check
  by hand (licence and rig must be confirmed on each page before import; prefer CC0 / CC-BY, never NC/ND for the game):
  "Faceless Bonewing Horror Beast" (listed CC-BY; rig unknown), DreamKit Monster Pack (itch.io, CC0, 5 free, rigged).
- The Bestiary **Source** tier (paid) has all 7 monsters (werewolf, goblin, skeletons, golem, armoured demon): the
  clearest upgrade path for the remaining species (gloomwisp, thornback) with the same build tool.
