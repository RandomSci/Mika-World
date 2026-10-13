# Milestone I — development record

Branch `milestone-i` (from `milestone-h-two-mages` @ 3b8099f). Checkpoint of the pre-milestone state:
`.backups/2026-10-13_pre-milestone-i/` (HEAD, lectern WIP patch, real save copy). The four lectern
files remain uncommitted and untouched.

## What changed in existing autonomous behaviour (and why)
| Change | Why |
|---|---|
| A tenth-level form is now **permanent** (`progress.appearance`), applied at spawn and after restarts | Milestone H made forms last 3 min — not the intended design |
| The pre-fight short sequence is now an **Orbit Surge** (+0.2 spell power, orbit ring, 60 s) — no outfit change | separates temporary power from permanent appearance |
| Books are offered to the planner only after the mage has **noticed** them (perception) or already started them | removes the omniscience flagged in the first audit (unread book locations) |
| Luna gets every activity kind (reading, alchemy, attunement, gathering, roaming, performing…) | equal capabilities; story leads and the travellers' authored dialogue stay Mika's (lines are written for her) |
| One mage may cause an area change: the **followed** one | only one area can be loaded; prevents a background mage from moving the world |
| Mages steer around each other and creatures; creatures are solid (physics layer 2) | no walking through each other / monsters |
| Picking things up is physical (clip + arm IK; counts only after the hand reaches) | no teleporting items into inventories |
| Seats use Stand-To-Sit / Sit-To-Stand transitions | the old blend into the seated loop |
| Viewer comments are routed to the named mage (or the followed one), wait while she is busy, and her memory of viewers is her own | two mages; identity separation |
| The same-text chat limit now applies within 5 minutes (was: forever) | defect from the first audit ("hi" rejected for the session) |
| Tests ignore keyboard input | windowed tests take focus; stray keystrokes had cast spells mid-test |

No safeguard was removed: repetition/failure penalties, discovery gating, save integrity, knowledge isolation,
progression rules and the LLM budget all still apply. Background simulation never calls the LLM; nearby
mages and off-camera chat replies use authored lines; mage conversations use the LLM only on camera.

## Simulation tiers
* **foreground** — the followed mage: full simulation; may travel between areas.
* **nearby** — same loaded area: full physics, animation, planning; no own LLM calls.
* **background** — her area is not loaded: hidden + frozen; the planner runs `_background_step` at real-time
  pace: rest, repeat practice of reactions she has observed on object kinds she has seen in that area (same
  mastery formula and decaying repeat XP; success chance 0.7–0.95 from mastery), journal from her real log,
  wandering (no XP). Discoveries, fights, items, reading, alchemy, meetings → **deferred** (`mind.deferred`).
  Every background record carries `"sim": "background"`.
* `focus_mage(who)`: same area → camera subject change; other area → waits for the mages in view to be
  between activities, then the masked travel card loads her area and rebuilds her where she was.

## Save format (additive, still version 1; older builds ignore the new keys)
Top level: `mika_location`, `mika_music`, `mika_deferred`, `mika_explored`; per agent: `location`,
`deferred`, `music`, `explored`; `progress.appearance`. Knowledge gains `noticed:*`, `noticed_kind:*`,
`place:*`, `material:*`, `song:*`, `viewer:*`, `rel:*`, `noeffect:*` keys.

## Music
Library: `assets/audio/music/` (`music_catalog.json` + `library/<id>/{original.mp3 (git-ignored),
metadata.json, timing.json}`), discovered automatically; ≥20 songs supported. `tools/audio/analyze_song.py`
measures BPM, beats, bars, sections, musical endings and an **estimated** vocal envelope (mixed track;
amplitude-style lip movement, not phonemes). Controller: `scripts/music/performance_controller.gd`
(casual / special, 60–90 s total hard cap, planned musical endings, tempo-matched dance clips, phrase-synced
camera cuts, bar-downbeat sparkles, interruption handling, per-mage history/familiarity/favourites, no XP,
no API calls). Camera: `CameraDirector` performance mode. Dev: **F8** preview (Shift = special), no memory.

## Performance findings (1600x900, LIVE_OPTIMIZED, this laptop)
* Idle with director: 33.3–33.9 ms/frame (~30 FPS cap).
* Performing, first version: 41.7 ms (beat particles every other beat, re-created nodes). After reusing one
  emitter and firing on bar downbeats: **35.9 ms** (p95 47 ms). With `--music-fx=off`: 34.5 ms.
* Transformations: phases at 26–30 FPS; single ~130–150 ms frames at sequence start and at the form swap
  (hidden by the flash).
* Screenshots during tests cost ~150 ms each (excluded from measurements with `--no-shots`).

## Known limitations
* Lip movement during songs is amplitude-based from an estimated vocal envelope of a mixed track.
* Dance clips are tempo-matched (speed scaled to the song's beat) but not choreographed to the song.
* The Mixamo dances play in place (hips XZ flattened) — some steps would travel in the original clip.
* Background practice outcomes are a bounded statistical model, not physical casts.
* Luna stays in the Sanctuary (no area travel of her own yet); travellers' authored dialogue is Mika's.
* Song rights: generated with Suno — confirm broadcast/commercial rights before any public stream.
* Visual review was done on captured frames from real runs; motion quality still needs a human watch.

## Tests
`tools/run_regression.sh all` (headless) and `tools/run_regression.sh visual` (windowed). See the final report.
