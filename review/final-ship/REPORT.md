# Mika Live: final ship pass (2026-10-10)

Deployment: `~/Documents/Mika-Live`, branch `mika-world`.
Rollback reference for this pass: tag **`pre-final-ship-pass-2026-10-10`** (= bb4aba7).
Commits of this pass: 9479e68, 5bcf46a, dab477e, f177215, e158d38, 4eb3172, e063ccf (17 files, +391/-39).
DEV (`~/Downloads/VR-Agent-Mika-Dev`) and the original LIVE (`~/Documents/Open-LLM-VTuber`) were only read;
no file in either changed during this pass.

## Launch

    cd ~/Documents/Mika-Live && ./mika-live.sh

It prepares everything, opens OBS on the "Mika World" scene (not streaming) and waits for you to type `GO`.
Mika starts her day (greeting, first goal) when YouTube confirms the broadcast is live (at most 240 s after GO).
Before GO she stands in the OBS preview; that is the speech hold, not a fault.
Rehearsal (never streams, posts nothing): `./mika-live.sh --rehearse`. Stop: Ctrl+C once (about 20 s).

## 1. Three-way audit

| Subsystem | DEV | Original LIVE | Mika-Live (before this pass) | Finding |
|---|---|---|---|---|
| Life planner / goals | yes | no | yes, extended (registry, 5 h pool) | Never started in rehearsal (see 3) |
| Action coordinator, navigation, Rapier, doors | yes | no | identical + ship-now edits | Works: routes, doors, legs confirmed by the Stage |
| Perception | geometry-based landmarks with occlusion, interactables | no | same data in worldState, but the compact MIKA STATE dropped it | Brain did not know what was in view; fixed |
| Memory | goals, vlogger memory, checkpoint | chat memory | + magic, dance, pool files | Viewer-requested activities were not credited; fixed |
| Magic | no | no (Minecraft spells only) | sanctuary, 8 spells, 9 lessons, 6 converted clips | Works (verified) |
| Dance | single routine | no | sessions over 7 routines | Works (verified) |
| Speech routing | one Stage | OBS stage first | lifestyle leader only, first ready page wins | Firefox got nothing; Firefox could become leader; fixed |
| Voice | Kokoro af_heart | Edge | Kokoro `af_bella:0.6,jf_alpha:0.4`, gain 0.7, Edge Ana fallback | Unchanged |
| YouTube OAuth / chat / pre-live | n/a | yes | yes | Works; stale `invalid_grant` shown as current; fixed |
| Minecraft / class | no | yes | launcher delegates to original LIVE | Unchanged |

No DEV module is missing from Mika-Live (only `.before-*`/`.bak-*` backup files exist only in DEV). The migration
regressions were behavioural, not missing files.

## 2. Problems found and fixed

| Problem | Root cause | Fix |
|---|---|---|
| A. Stuck in the bedroom (rehearsal) | `mika-live.sh` always sets `VR_WORLD_HOLD_SPEECH=1`; `lifestyle.run()` waits for `stream_is_live()` before *anything* (greeting, goals, movement). A rehearsal never goes live, so the life loop never started. The 14:47 log has no `started` or `goal_*` event at all. | `hold_speech()` is off when `VR_REHEARSAL=1` (`world_mode.py`). |
| A2. Would stall later in a long stream | The five-hour pool (12 objectives) empties in under an hour; by design she then "stayed free" (standing, talking) until the reset. | When the pool is exhausted she revisits the activities done longest ago, never her last three, cooldowns kept, cycle not reset early (`autonomy.py`). |
| A3. Repeated dance | A viewer-requested dance session was logged as `viewer_dance_session`, so she chose her own dance session 30 s later. | Viewer actions map to her activity ids: repeat penalty, cooldown, pool credit. |
| B. Speech only in OBS | Audio goes only to the lifestyle leader (first ready page). Every page's world state was merged into her reality, so a second page could overwrite where she is. | OBS page reports `window.obsstudio`; the OBS page always leads, otherwise the leader is sticky. Other Stage pages are **monitors**: they get the same audio, captions and lip-sync (`monitor: true`) and mirrored actions, never acknowledge, never send playback events, never change her reality. One LLM generation, one awaited playback. |
| C. `Unknown message type: audio-play-end` | Benign: `message_handler` already consumes it for latency traces; only the router warned. | Not logged as unknown. |
| D. "2:49 AM" at 14:49 Manila | Not a bug in the clock: Mika lives on New York time since DEV commit 29ae351 (02:49 EDT = 14:49 PHT). Speech and display gave a bare time without the city. | Prompt gets `2:49 AM` plus `New York`; the room screen shows `2:49 AM` and `NEW YORK`. Verified: "It's 3:55 AM here in New York." |
| E. Close selfie | Mostly A (the default phone pose was all she ever did). | Also: random framing no longer picks `selfie_close`. |
| F. Footstep "zzt" | | Footsteps off by default, detector does no work (`?footsteps=1` restores). |
| Stale `invalid_grant` | `status()` showed the newest failure even after a later success. | Failures resolved by a later successful run of the same step are history. |
| Spell request only walked | "practise a spell at your sanctuary" matched the place first. | Spell requests run the lesson; "go to / show me your sanctuary" stays a walk. |
| "Can you go dancing?" ignored | Not recognized as a request. | Starts a dance session; compliments still do not. |
| Birds at 3 AM; "snake_hiphop" read aloud | MIKA STATE always listed birds; routine ids not titles. | Sounds follow day/night like world-audio.js; routine titles. |

## 3. Behavioural architecture (what the brain now gets)

MIKA STATE (every spoken line) is built from authoritative Stage reports, not from prompts:
- `perception.inView`: landmarks visible from her eyes (collider-ray occlusion from eye height, facing; not behind her), with distance and direction.
- `perception.nearbyNotInView`: nearby but behind her or blocked. `perception.withinReach`: reachable interactables within 3 m.
- `placesIveEverBeen`: places she actually stood in (from the Stage zone), persisted in `data/mika-places.json`.
- `recentlyDoneNewestFirst`: finished goals with status (completed/failed/interrupted) and minutes ago; plans are marked as plans.
- Magic level and progress, dance results, time (12-hour + city), the open objectives of the cycle.
- Rule: she only sees `inView`; other things she knows from memory or not at all; she need not mention what she sees.

There is no screenshot/vision model; perception is structured geometry, which is the honest description.

## 4. Rehearsal evidence (production launcher, `--rehearse --no-image`, OBS running, 15:23 to 16:00)

Autonomous goals chosen and finished, each step acknowledged by the Stage:
lantern_walk (151 s) → stargaze (291 s) → relax (walked inside through the garden door) → [viewer] go to sanctuary (59 s)
→ [viewer] magic lesson → fresh_air (111 s) → explore (62 s) → room_tour (73 s) → magic_training (passed lesson 2, level 2)
→ window → [viewer] dance session → dance_practice (156 s) → rhythm_challenge (87 s) → atelier.
No bedroom reset between activities; travel only when an activity is in another place.

- Viewer test: "Mika, could you go practise a spell at your magic sanctuary?" → answer "Yeah, heading to my magic sanctuary now." and a real `go_to magic_sanctuary` 0.1 s later; arrived 59 s later.
- Magic: magic_prepare (phone on its tripod) → spoken incantation "Orbis lucis." → Stage-confirmed casts with effects (`orb, orb_burst, orb_flash` partial; `orb_collapse, fizzle` fails) → lesson failed 0/3, reported honestly → later passed by herself 2/2.
  The outcome of each cast is decided by the backend skill model and then performed and confirmed by the Stage (attempting is not completing).
  8 spells / 9 lessons exist; this pass exercised lessons 1 and 2. Six converted clips present; FBX originals untouched in Downloads.
- Dance: viewer "can you go dancing for us?" interrupted her window goal; studio, warm-up, YMCA 1975, Chicken 1400, Belly 3250; her own session: Step 2150, Macarena 1500, Snake 2795. Full-body studio framing (frames).
- Audio: 45 s local OBS recording (`~/Documents/Recordings/2026-10-10_15-55-55.mp4`): music floor -33 dB, her lines -21 to -24 dB at the logged times, peak -8 dB; caption and open mouth visible. Chat to first audio 1.9 to 2.9 s.
- Monitor (second headless Chromium at the same URL): received the line with caption, "Responding" and mouth movement, mirrored actions; OBS kept leadership (no `stage_leader_changed`).
- Footsteps: same walk, 0 steps by default, 4 with `?footsteps=1`.
- Persistence over two restarts: places, magic (practice 3 → 5, lesson 2 passed), dance history, pool cycle 2.
- Stage health in OBS: 29.6 FPS (OBS browser source cap 30), heap ~137 MB flat, 0 errors.
- Broadcast safety: OBS `GetStreamStatus.outputActive = false`, pre-live `dry_run`, not confirmed, no live broadcast, no comment posted; Ctrl+C stops in 20 to 24 s with no server, OBS or launcher left.
- YouTube (read-only): signed-in channel `UCKKJhi5GUjxENIWFErKWy6Q` "Selwyn Builds" = stream channel = `.env`; token valid; OBS key maps to a stream on that channel.

Frames: `review/final-ship/frames/`. 12-minute state probe: `autonomy-probe-12min.log`.

## 5. Opening comment

Fixed text in the creator's voice (200 characters, YouTube's limit; no dashes), applied also to the resumed session:

> Welcome! Mika is my experimental AI. She explores, learns magic, builds skills, remembers and makes her own choices in a persistent 3D world. Still evolving! Subscribe to Selwyn Builds to follow along

Posted once per live broadcast (restart-safe), never in rehearsal or dry run. Pinning: the YouTube Data API has no pin
endpoint, so pin it by hand: in the live chat (Studio or the watch page), hover the message, ⋮ menu, **Pin**.

## 6. Tests

- New `tests/test_final_ship.py` (10 tests): rehearsal not held, OBS leads and monitors never rewrite reality, mirroring, sticky leader, time wording, opening comment, resolved failures, perception, intents, viewer credit.
- Focused suites (ship_now, autonomy, lifestyle, speech routing, calendar, session, intents, dance): all pass.
- Full non-browser suite: 795 passed, 13 failed. The same 13 fail on the checkpoint tag (9 Minecraft, rabbit director, "asked you" follow-up, tagged-audio fake without `latency`, room profile `cheer`), none in code touched here.
- Browser suites: see the end of this file.
- One updated test: `test_exhausted_pool_does_not_loop_an_activity` encoded the old stand-still rule; it now checks the revisit rule.

## 7. Known limitations

- **Night stream**: New York time means a 2 to 4 pm Manila stream is a dark 2 to 4 am world. Deliberate DEV decision, kept. To switch: `MIKA_TIMEZONE=Asia/Manila ./mika-live.sh` (or `room/calendar.json`: timezone and location).
- Walking indoors uses the compact phone hold in front of her face (physical constraint so the phone does not clip doors); indoor legs are short. Activities (magic, dance, quiet time, placed phone) use full-body framing.
- A Firefox monitor runs its own copy of the world from the moment it opens: speech, captions and mouth match OBS; her position can differ (it replays commands, not positions). Use OBS's projector for an exact picture. Its audio plays at full volume; `?monitorAudio=0` mutes it. OBS desktop audio is muted/0 in this profile, so Firefox audio does not reach the stream; if you ever unmute Desktop Audio in OBS, mute the monitor.
- Crackle: not reproduced here; footsteps (the most frequent short sound) are now off. No broad audio refactor.
- Before GO the preview shows her still (speech hold); she starts when YouTube confirms live.
- Coding workstation stays off (`VR_FEATURE_CODING=0`); bench sitting / lying under a tree not implemented.
- A test recording is left in `~/Documents/Recordings/2026-10-10_15-55-55.mp4` (delete if unwanted).

### Browser suites (run on an idle machine after the rehearsal was stopped)

`test_world_audio, test_stage_frontend, test_phone_camera, test_coordination, test_mika_world, test_room_e2e,
test_spatial_world, test_capabilities`: 18 passed, 7 skipped (environment guards), 0 failed.
Earlier in the pass (with the rehearsal running): intents and dance browser tests, 92 passed.
