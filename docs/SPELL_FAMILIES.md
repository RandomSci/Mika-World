# The two spell families (V3 Part XIII — Milestone K5/K6)

Mika's magic is wind that curves and things that grow; Luna's is precise shadow edged in gold. They differ in
geometry, casting posture, energy behaviour, timing, motion, impact, sound and defensive interaction — not in
colour. Everything below runs through the same truthful pipeline as before (`MagicSystem.cast`: prerequisites,
range, line of sight, the animation's real phase times, judged outcomes, mastery only for what really happened).
Verified in Godot by `--mktest=spells` (44 checks) and `--mktest=duel`; stills in `screenshots/mktest/spells_*.png`.

## Mika — the Sylvan family (`scripts/magic/sylvan_spell.gd`)

| Technique | Posture | Formation | Motion | Impact / effect | Learned |
|---|---|---|---|---|---|
| **Gale Spiral** (signature) | a two-handed sweep (`wide_arm_spell`; the quicker `magic_attack_2h` in a fight) | wind arcs under her, leaves lifting off the ground round her feet, a small spiral of air forming between her hands | leaves as a **weaving helix**: two braided ribbons drawn along the path the gust has really flown, shedding leaves | bursts into leaves, air and dust; **shoves the creature back** (`push`, real displacement clamped to walkable ground); wind resistances apply | known from the start |
| **Verdant Bind** | hands lowered (`spell_casting`) | a wreath of leaves unfolds under her | a green **seam races along the ground** to the mark (aimed when it leaves, leading a moving creature) | **roots erupt** in a cage round whatever stands there (grown tubes, leaf tips, sway, then wither): a ground creature is **held** — no moving, no attacking — for `bind_s`; a creature that moved on is not caught; a flyer high up is out of reach | after the spiral is practised (Apprentice + practical understanding) |
| **Leaf Ward** | a brace (`brace`, ~0.3 s to come up) | — | a **ring of leaves orbits her and moves with her** | stops the next two light bolts (one heavy) **from any side**; scatters when spent; each bolt stopped is practice | known from the start |

## Luna — the Umbral family (`scripts/magic/umbral_spell.gd`, lance in `combat_spell.gd`)

| Technique | Posture | Formation | Motion | Impact / effect | Learned |
|---|---|---|---|---|---|
| **Umbral Lance** (signature, Milestone J) | one-handed thrust | five-point sigil, shadow motes into the hand | a dark crystal shaft, fast and straight, with a gold rim | shards; pierces | known from the start |
| **Umbral Rift** | one-handed (`spell_casting` / `magic_attack_1h`) | a six-sided sigil wakes under her; shadow drawn **into** her palm (a dark core with a gold rim) with three crystal shards circling it | the shards fly to the mark; a **gold line snaps** along the ground; a hexagonal rift opens | 0.42 s later **dark crystal spikes erupt** through it: damage and a **daze** (`daze_s`) to whatever stands inside (hovering creatures within reach); the rift cools into a **scar** that stays ~25 s | after the lance is practised (Apprentice + practical understanding) |
| **Gilded Mirror** | a brace | — | a **hexagonal pane of dark glass** with a gold rim held before her | stops one bolt **from the front only** (a bolt from behind still lands); once practised (Adept) it **throws a light bolt back** at whoever sent it — a mage across the training ground, or the creature | known from the start |

## Rules that make them real (not video)

* **Target reactions are the creature's** (`Monster.react`): a hit applies the spell's data — `bind_s` → `bind()`
  (state `bound`: struggle, no attack; poise shortens it; flyers immune), `daze_s` → `daze()`, `push` → `push()`.
* **Wards are judged by the bolt** (`AttackHazard` → `Ward.intercepts/covers/absorb`): the bolt's real path must
  cross the ward, from a side the ward covers. A reflected bolt belongs to the reflector and can touch the sender.
* **Tactics choose them from the moment** (`CombatTactics`): Mika holds a ground creature pressing in on her with
  roots, then keeps her distance and throws spirals; Luna opens a rift under a creature standing exposed
  (recovering, staggered, held) and lances it while it moves. A bolt coming with time to spare is warded when she
  is short of vigor or chooses to hold her ground; otherwise dodged (real movement); a bolt with no time left is
  braced (nothing is halved — the bolt decides). Cooldowns per technique (`cooldown_s`, game time).
* **Training duels** (`TrainingDuel`): each mage's spar bolt is in her own language — Mika's a weaving spiral
  from a two-handed sweep (slower, readable), Luna's a dark crystal shard from a one-handed snap (quicker,
  straight). Wards are real there too (breath cost, cooldown); a practised mirror's reflection can score a touch.
* **Progression**: the advanced techniques need the signature practised (`requires_knowledge:
  practical:<signature>` + `requires_mastery` Apprentice). Nothing is granted early; fixtures only in disposable
  test saves. Wards grow with the ward's own mastery (charges, duration, reflection at Adept).
* **Sound** (`tools/audio/synth_v3_magic.py`, original, bell-free: all 0.000 on `bell_check`): a `nature` element
  set (leaves, creaking wood, earth) and one-shots for wards, roots and rifts; Luna's rift in glass and crystal.
* **Fusions**: two new recipes when the families meet on one creature — Veiled Tempest (wind + umbral) and
  Thorned Night (nature + umbral).

Mika's first lesson, the Arcane Orb, stays hers (story leads, the circle, the H/J tests); her signature is now the
Gale Spiral, so her fights read as wind and growth from the first cast.

## Verification

`--mktest=spells` (PASS, 44 checks, windowed 1600×900): catalogue (families known from the start, advanced
techniques refused), Gale Spiral (phases from the clip, SylvanSpell node, helix of two ribbons + leaves, hit,
push 1.13 m measured, 42.8 damage), Verdant Bind (unlocked by practice, seam + roots, creature held 2 s with no
movement and no attack, released on wither), Leaf Ward (two bolts stopped from front and behind, the third lands,
mastery from real stops), Umbral Rift (UmbralSpell node, hit at eruption, dazed 1.0 s, 7 spikes, 45 damage, scar),
Gilded Mirror (front stopped, behind lands, Adept reflection flies back and strikes the emberwing), tactics (bind
for a crawler pressing in, spiral for a flyer, rift for an exposed creature, lance while moving, each mage's ward),
two real planner fights (Mika: 2 spirals + 1 bind → defeated; Luna: 3 lances + 1 rift → defeated), sounds.

`--mktest=duel` (PASS 12/12): a 70 s bout, Mika 2 – 2 Luna, 32 family bolts, 11 real dodges, 10 wards cast and 8
bolts really stopped (Mika's ring 7, Luna's mirror 1; one bolt came round the mirror's front, two missed anyway),
camera two-shot 2208/2209 frames. `--mjtest=signature --who=mika` (PASS 10/10) with the Gale Spiral as her signature.

Stills: `screenshots/mktest/spells_*.png`, grids `docs/screenshots/milestone_k/spells_k5_mika_sylvan.jpg` and
`spells_k5_luna_umbral.jpg`. Real game footage (Movie Maker, live profile, 1600×900 — the project's viewport size):
`screenshots/mktest/clips/spells_k5.mp4` (72 s, the whole spells test) and `duel_k5.mp4` (90 s, invitation → bout
→ aftermath).

Known limits: the rift's scar is a flat pane (readable from above, hidden by tall grass at grazing angles; a decal
would fix it); creature bodies are still the Milestone J ones (K4); no NPC spell languages yet.
