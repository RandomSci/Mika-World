# World bible — Mika World V3

Original setting material (no borrowed mythology). Everything here is either already in the game as readable
text (`data/books.json`) and world content, or is marked *planned*. It extends the lore that existed before
(the First Circle, the Heartstone, ley-lines, the Orbit Gates of progression) without changing it.

## Cosmology: the Lumen, the Hush and the Ten Rings

* **The Lumen** — a sea of light without shores. **The Hush** — the stillness light falls into. Where they
  touched they made a ring of ground: **the Orbis**, the world. Every spell is a little of the Lumen asked to
  touch the world again (why the old books say a spell is *a request, not a command*).
* **The Ten Rings of Heaven (the Orbits)** circle the Orbis, one inside the next. A mage climbs them as she grows:
  they are the game's **Orbit Gates** (every tenth level, `data/progression.json`) given a meaning. The first ring
  is learned with the breath; the tenth with the whole of oneself.
* **The Wardens** — each ring was first walked by a mortal who became its Warden, a demigod seen at night as a
  bright knot of stars:

| ring | Warden | who they were | legacy in the world |
|---|---|---|---|
| 1 | **Aelis** | a shepherd who whistled the wind | "breath before the word" (Master Aldric's first lesson) |
| 2 | **Thane of the Deep Waters** | a ferryman who calmed a flood | still water holds the light of signs (the Heartstone's pond) |
| 3 | **Verdance** | grew a forest in one night to hide a village from fire | the **Sylvan** arts (Mika) |
| 4 | **Umbra** | a lamplighter who learned the shapes of shadow | the **Umbral** arts (Luna); Sylvan and Umbral mages are drawn to each other "as root to shade" |
| 5 | **Emberhart** | went into a burning mountain, came out a bird of flame | the phoenixes are his sparks (Oriel) |
| 6 | **the Stonefather** | sang deep rock into crystal | the Crystal Caverns; the **hollow sentinels** are his makers' keepers, not monsters |
| 7 | **the Weaver of Ways** | folded the distance between two places like cloth | the **glyph stones** of the Forgotten Shrine; the only true way to learn teleportation |
| 8 | **the Mirror Queen** | saw the same moment from both sides | the Gilded Mirror ward |
| 9 | **the Skyborn Twins** | sisters who would not climb without each other | the **ninth gate (Level 90) opens only to two mages together**, in the summit temple when the Twin Lights stand overhead |
| 10 | **the Crown** | held by no Warden | held by whoever has heard all nine: the Level 100 Archmage |

## Where the world tells it (readable now)

| text | place | what it gives |
|---|---|---|
| *Atlas of the Ten Rings* | Village Observatory, the star-chart table | the cosmology; a keeper's note about the Twin Lights over the summit |
| *On the Wardens of the Orbits* | Great Library, the central lectern | the ten Wardens; the Weaver's glyphs; the Twins; the Crown |
| *The Founder's Plaque* | Academy courtyard, the fountain statue | Ilvane, last apprentice of the First Circle, founded the Academy |
| *Glyph Stones of the Forgotten Shrine* | Ancient Grove shrine | the Weaver's teaching: places are folds of one cloth (teleport theory 1 and 2) |
| *The Vault Inscription* | Deep Caverns, beside the vault | the vault was sealed by the Stonefather's makers; the sentinels are keepers |
| *Frieze of the Cloud Temple* | Celestial Summit temple | the Twins at the ninth step; "the ninth gate is not opened by one" |
| *Village Notice Board* | Village square | the residents' own notices (Hilde's bread, Bram's lost hammer, Rook's wolf warning, Aldric's open lessons) |

## Cultures and peoples

* **The First Circle** — the mages who cut the circle at the Sanctuary where three ley-lines cross; they left,
  binding the Heartstone to sleep (Aurel's daybook). Their last apprentice, **Ilvane**, founded the Academy so
  that what they knew would be taught in the open.
* **The Academy** — open lessons on the east lawn (visitors at the back), practice round the arena circle, the
  Great Library; teachers like Master Aldric, the librarian Sister Maren, students like Lysa and Corin.
* **The Village** — a market town of stone-and-timber houses: smith, baker, herbalist, woodcutter, the watch.
  Practical people; they trust what they can see the mages do.
* **The woodfolk** — Fernhollow, a hamlet of turf-roofed houses round a sawpit on the old forest track; they sell
  bread and cheese to travellers (the journey system's wayside places).
* **The summit-folk** — keepers of the Cloud Temple; they say the ninth ring can be *heard* on autumn nights.
* **Rivals** — Garran's band of road thieves; Morrow the Hexer, who covets Luna's storage ring and always escapes.

## Creatures (ecology)

* **Gloomwisps** — small knots of the Hush that drift where light is thin; weak, curious, drawn to spellcraft.
* **Thornbacks** — territorial forest beasts; they defend dens, not hunt.
* **Briar imps** — mischievous; thieves of shiny things.
* **Emberwings** — sparks of Emberhart grown into small flame-drakes; they nest on warm rock.
* **Mossbacks** — huge, slow forest giants that come to camps at night for the warmth of the fire.
* **Hollow sentinels** — the Stonefather's makers' keepers; they guard, they do not hate (the vault inscription).
* **Phoenixes** — Emberhart's sparks; Oriel is one.

## Threads waiting to be played (planned)

* **The Weaver's words under the summit** — *implemented*: the stone beneath the Cloud Temple's altar teaches
  the incantation of **the Fold Step** (`MagicSystem.fold_step`); with the glyph stones' theory it becomes castable:
  only to a place she can see, with room to stand, within 12 m (+10 m per mastery). TeleportGuard records each as a
  learned fold. Long-distance folding ("knowing both places") is the next step of the thread.
* **The ninth gate** — a Level 90 milestone that only Mika and Luna *together* can open, at the summit temple
  under the Twin Lights; neither can climb past it alone.
* **The Crown** — Level 100: having heard all nine rings. Nine bells hang on the Mentor's Tower crown, where no
  stair goes; each sounds only for one who has heard its Warden's ring (`docs/THE_CROWN.md`).
