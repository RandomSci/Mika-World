# Day 3 update: design

Worktree `~/Downloads/Mika-Godot-Dev-Day3`, branch `day3` (from the merged Day 2 live code). Each piece is committed with
its test; every test runs with the live stage flags (`--profile=stream --viewer --brain`, visitors on). 30 fps holds
throughout (the stream pipeline at 1080p30, measured per test).

## 1 Close-ups and emotional connection

**Why faces looked bad up close.** Measured, not guessed, first: 6 stills per girl at close-up framing (happy,
surprised, sad, laughing, determined, shy) under the stream's day and night light, before any change. Known suspects:
the VRM 1.0 MToon shade conversion was tuned for medium shots (`_fix_vrm1_mtoon_shading`, docs/FACE_SHADING_FIX.md);
faces take 0.15 of cast shadows (`_face_shadows`), so hair and hat shadows still band across them; the outline width
is in screen space and too heavy at close range; no eye highlight or rim light separates the face from the background;
expression blendshapes are driven at fixed weights (some read as dead-eyed, some overshoot).

**Fix (face only, outfits untouched).**
- A *face light rig* that exists only while a close-up is live: a soft key and a low rim, both culled to the face and
  hair meshes (their own visual layer), so the world's lighting never changes.
- MToon tuning for close range: shade shift and toony for the face, a cleaner shade colour, outline width scaled by
  camera distance, face shadow receive near zero while close.
- Eye highlights: the VRM's highlight material brightened, plus a tiny catch-light card per eye that follows the key.
- Expressions: per-emotion presets mixing several blendshapes (mouth, brows, eyes, blush) with eased in and out
  and natural blinks; tuned per character.

**Gate.** The 12 stills (6 per girl) go to the developer, and work **stops there** until he approves. Close-ups stay
off the stream until then; the permanent no-close-up rule is replaced only for emotional moments, only after approval.

**After approval.** The camera director gets an *emotional moment* trigger: a discovery, a joke, a sad moment, a
reunion, a transformation reveal. The close-up holds 2-4 s (face about 25-35 % of the frame), then medium, then
wide. Never during a walk, a fight or a performance; at most one per minute. Expressions and body language follow what
each line says (the line's mood tags drive a preset and a gesture), with idle emotions (glances, small smiles,
thinking, sighs) between lines.

## 2 Dynamic discovery events

A *DiscoveryDirector* replaces fixed placements (data/discoveries.json stays as hand-made content within it).
- **Budget.** About one find an hour on average, as a rate per minute that depends on where they are (off-path, an
  unexplored cell, a new area, night, rain: higher; the sanctuary's dais: lower). Rarity tiers: common 60 %, uncommon
  28 %, rare 10 %, legendary 2 %: most hours a small surprise, some hours something big.
- **Kinds.** Hidden places (a tunnel under the bridge, a hollow behind the waterfall), scenery spots, magical plants
  (colour and particle variants of the existing gatherables), wandering spirits and lost souls (a short encounter and
  a request), region-specific monsters (variants of the existing creatures), rare items, lore fragments, and the
  Phoenix path's clues, which stay in the pool.
- **How they find things.** Exploration gains a *wander off* option; sometimes she takes a wrong turn and is briefly
  lost (no teleports: a real walk back). A find is placed where she actually is, on the navmesh, off the beaten path,
  and is real in the world (a prop, an interactable, a creature).
- **Memory.** Every find is saved (id, where, when, tier, reward), can be revisited, shows on the overlay and gives a
  small reward (an item, spell knowledge, lore, a new place on the map). The same kind never twice in a row; a long
  memory of the last 200 finds keeps them fresh; both mages react and talk about it (it also feeds the close-up
  trigger).

## 3 Viewer comments with memory

Live chat runs through Mika-Live: it reads YouTube chat, picks a message, writes the reply with its LLM and sends
the line to the world. Mika-Live already keeps viewer identity records (`live/viewer_identity.py`).

**This part needs Mika-Live changes.** It belongs in Mika-Live's chat path, not in the Godot world. The plan is a
separate Mika-Live worktree and branch, never the LIVE checkout; it needs the developer's OK first.
- A per-viewer memory: what they said, how they talk (tone, emoji, language), when; entries older than 20 days are
  deleted automatically; small JSON per viewer.
- Returning viewers greeted by name, with a natural reference to an earlier message.
- Spam, harmful or bad-faith questions and repeated junk are ignored, never answered.
- Two-stage reply: a short fitting reply within about 2 s (a fast model and cached speech), then an understanding
  pass that sends a fuller follow-up only when it is needed.

The Godot side only needs the reply's mood tags (part 1) and a greeting gesture.

## 4 A relationship that grows

- **Personalities** sharpened from what is already there (Mika: cheerful, gentle, bookish, a little reckless;
  Luna: proud, dry, competitive, warm underneath), written into every dialogue prompt and line table.
- **Relationship memory** (saved across restarts, per pair): shared moments (date, place, what happened, how it felt),
  trust, warmth, rivalry, and inside jokes (a phrase plus its origin, used again later). Disagreements open and are
  resolved later; comfort after a lost fight or a bad day.
- **Use.** Conversations draw on the memory ("like that night at the lake"), running jokes return at a measured pace,
  and the bond visibly grows day by day: who starts talks, how close they walk, teasing versus comforting.

## Order, tests, deliverables

1. Face stills (6 per girl) → **stop for approval** → face fixes and the emotional close-up camera → test
   `closeups` (face size per shot, at most one per minute, 30 fps).
2. Discovery director → tests `discovery_rate` (simulated hours: the rate and tiers), `discovery_live` (a real find,
   reactions, saved, overlay).
3. Viewer memory → in Mika-Live after the developer's OK; Godot test `viewer_greeting` (mood and gesture).
4. Relationship memory → tests `bond_persist` (saved across a restart), `banter` (a running joke returns).

Clips: a discovery, a close-up emotional moment (after approval), a returning viewer greeting, a Mika and Luna banter
moment.
