# Road ambushes by human rivals (2026-10-15)

The developer's request:

> "add some adventurers or groups that tried to rob them … assassins, using sword techniques, different kinds of
> black magic, fast movements, like in real anime … with some conversations … thugs are talking about them, tried
> to going incircle them."

## The band (data/monsters.json `rival_*`, models in assets/creatures/rivals)
| rival | style | attacks |
|---|---|---|
| **Garran the Cutthroat** (leader) | brawler with a notched machete | sweeping cuts, a rushing dash strike (afterimages), thrown knives |
| **Vex the Shade** | assassin with two daggers | **blink**: a very fast physical run to the target's flank with afterimages, then the cut; quick combos; thrown knives |
| **Kaito the Ronin** | sword techniques (katana) | heavy combo sweeps, a **sword wave** (a crescent of cutting light thrown from the blade tip), an iaido dash |
| **Morrow the Hexer** | black magic | **hex bolts** (a knot of darkness bleeding smoke and cinders), **curse circles** marked on the ground under the target |

**Models.** Each model is built from Quaternius CC0 kits that share the UAL skeleton: Modular Outfits plus a Base
Character head and hair, with Universal Animation Library 1+2 clips (sword combos, dashes, ninja jumps, slides,
spell casting, throws, hits, falls, get-up). See `tools/models/build_rival.py`. The weapons are Poly Haven props on
a hand bone. The models were slimmed from 230 MB to 29 MB (`tools/models/slim_glb.py`).

**Wind-ups.** Every attack is still telegraphed, so a quick mage can dodge. Each wind-up plays the first part of
its clip slowly, and the strike plays the rest fast, so the motion is continuous.

**Nobody is killed.** At zero health a human rival is knocked out: they fall, lie still, get up and walk off. The
Hexer never stays to lose: badly hurt, he runs with a threat.

## The scene (scripts/combat/ambush_director.gd, data/ambush.json)
1. **Watch.** The band waits in cover about 22 m off. Over the leader's shoulder, through a long lens, they talk
   about the girls and their storage rings.
2. **Encircle.** They step out and walk round the girls, closing a ring that covers more than half the circle.
   The girls turn back to back and take their stance. The leader makes his demand, the girls answer, and the band
   taunts. Each line gets a speaker-driven over-the-shoulder shot that is collision-safe: no rock or third person in
   the way.
3. **Fight.** Each rival fights in his own style. Each girl's own planner fights back (spells, wards, dodges), and
   the trailer camera covers it with barks on both sides.
4. **Break.** When the leader is badly hurt or two rivals are down, the leader yields: he kneels and his weapon
   falls to the ground as a real prop. The others run off on foot, gone.
5. **After.** Mika and Luna check on each other and talk about the Hexer's interest in Luna's ring.
   `WorldState.rivals` remembers him: how often they met, how it ended, and what he wants. When he comes back, he
   opens with his own lines.

**Voices.** The rivals use free Edge neural voices (`data/voices.json`). Mika and Luna speak only in their own
voice identities (docs/VOICES.md).

**No teleportation.** Rivals walk in from cover and run out of sight; TeleportGuard watches the whole scene.

## Test
`--mktest=ambush` checks:
* the four rivals are present;
* thug lines ≥ 6 and girl lines ≥ 3;
* the ring covers more than π;
* the beat order: watch → encircle → standoff → fight → break;
* at least 3 attack styles are used, and afterimages appear;
* the band yields or flees;
* the Hexer is remembered;
* the trailer camera cuts;
* nobody teleports;
* Mika and Luna speak only in their own voices.
