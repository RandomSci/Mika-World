# Progression — Levels 1–100 and the Ten Aether Orbits

Data: `data/progression.json` (XP rules, curve), `data/mages.json` (per-mage orbit gates, forms, orbits),
`data/transformations.json` (form sequences). Code: `scripts/core/progression.gd`.

## Principles
* **Verified only.** XP is derived from the changes the engine actually recorded (`WorldState.record_activity`),
  per mage. The planner, the LLM and the HUD can never grant XP.
* **Firsts matter.** A new magical reaction, clue, lore page, incantation, trial, rank, place, mastery tier or
  the first victory over a creature kind pays full value **once** (keyed in `progress.awarded`; survives
  restarts, so nothing is paid twice).
* **Repeats decay.** Practice casts and later victories pay `base / (1 + decay·n)`; easy creatures pay half
  again once a mage has outgrown them (`outgrown_at`).
* **Milestones gate the orbits.** Cumulative XP to reach level L is `40 · (L−1)^1.75` (L10 ≈ 1 870 XP,
  L20 ≈ 6 360, L50 ≈ 36 900, L100 ≈ 124 900). XP alone stops at 9, 19, 29…; crossing a tenth level needs that
  mage's **Orbit Gate** (real deeds, defined per mage).

## Levels 1–10 (implemented)
| Source | XP |
|---|---|
| first magical reaction observed | 30 |
| first practical success with a spell | 25 |
| lore page / fact / clue / incantation / recipe | 15 / 20 / 40 / 35 / 30 |
| attunement, survey, alchemy discovery, fusion | 40, 30, 25, 80 |
| first page of a book, first talk | 6, 15 |
| trial, rank | 100, 150 |
| new location | 25 |
| mastery tier (Novice → Master) | 10 · 30 · 60 · 100 · 160 |
| first victory: Gloomwisp / Thornback / Hollow Sentinel | 50 / 120 / 260 (repeats 10 / 22 / 45, decaying) |
| practice cast repeat | 4 → decaying |

**Orbit Gate 10**
* Mika: rank Apprentice · win against a medium creature · two spells cast successfully.
* Luna: win against a medium creature · Umbral Lance at Apprentice mastery · three different reactions seen.

Reaching 10 unlocks the form (Mika: **Bloom Form**, *Orbit of First Bloom*; Luna: **Gilded Eclipse Form**,
*Orbit of the Gilded Eclipse*). The first time plays the full transformation; afterwards a mage may choose the
short version before a medium/rare fight (form lasts 3 min, +0.2 spell power, orbit ring visible).

Mika's existing save scores 1 950 XP from what she had already verifiably learned → **Level 9, at the gate**
(she still needs a medium-creature victory).

## Levels 11–100 (proposed, not implemented)
Each orbit is a band of ten levels with its own content and gate; each mage's orbits differ.
| Orbit | Levels | Content that pays | Example gate |
|---|---|---|---|
| 1 First | 1–10 | Sanctuary study, trials, weak/medium creatures | above |
| 2 | 11–20 | other regions (exploration planner), village/forest lore, alchemy recipes | a region's trial set + a rare victory |
| 3 | 21–30 | crystal caverns, cave fire reactions, dual casting | a fusion with a new partner element |
| 4–5 | 31–50 | academy, mentor NPCs, silent casting (Expert) | teach/duel at the academy |
| 6–10 | 51–100 | highlands/summit, advanced forms, chained casting, world events | per-mage capstone quests |
Spell evolution follows mastery, not level: spoken (Untested–Apprentice) → one word (Adept) → silent (Expert+);
dual casting and chaining are planned for orbits 3–5.
