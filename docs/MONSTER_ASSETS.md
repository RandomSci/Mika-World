# Monster assets — direction (2026-10-14)

The developer: "Stop relying on overly simple placeholder monsters for hero scenes. Search and import better free
monster assets, prioritizing Quaternius Ultimate Monsters, Quaternius Bestiary Dungeon Monsters Kit, and
higher-quality free downloadable CC monsters/creatures from Sketchfab where appropriate."

## Done
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

## Blocked / next
- **Quaternius Ultimate Monsters** (CC0, 50 animated): its only download is a Google Drive folder; Drive refused the
  files ("Too many users have viewed or downloaded this file recently") on 2026-10-14. The 247 file ids are saved in
  `~/.cache/mika_dl/ultimate_monsters_file_ids.txt` for a retry. Note it is flat-shaded low-poly (one colour atlas):
  good for distant/ambient creatures, not a step up for hero close-ups.
- **Sketchfab**: downloads need a logged-in account (or an API token) — not available to the build. Candidates to check
  by hand (licence and rig must be confirmed on each page before import; prefer CC0 / CC-BY, never NC/ND for the game):
  "Faceless Bonewing Horror Beast" (listed CC-BY; rig unknown), DreamKit Monster Pack (itch.io, CC0, 5 free, rigged).
- The Bestiary **Source** tier (paid) has all 7 monsters (werewolf, goblin, skeletons, golem, armoured demon): the
  clearest upgrade path for the remaining species (gloomwisp, thornback) with the same build tool.
