# Mika world: ship-now report (2026-10-10)

Status: **READY FOR MANUAL LIVE TEST** (see "Before the first public stream").

Deployment: `~/Documents/Mika-Live` (git worktree of the LIVE repo, branch `mika-world`).
The original install `~/Documents/Open-LLM-VTuber` is untouched and still runs Minecraft / class.

## Commands

| What | Command |
|---|---|
| World show | `cd ~/Documents/Mika-Live && ./mika-live.sh` (asks you to type GO) |
| Rehearsal (never streams, publishes nothing) | `./mika-live.sh --rehearse` |
| New title/thumbnail session | `./mika-live.sh --new-session` |
| Skip paid image generation | `./mika-live.sh --no-image` |
| Minecraft / class (original install) | `./mika-live.sh --minecraft` / `--class` |
| Stop | Ctrl+C once: goodbye, broadcast ends, OBS closes (about 20 s) |
| Rollback | `cd ~/Documents/Open-LLM-VTuber && ./go-live.sh` (old system, unchanged) |
| Voice rollback | `room/characters/mika.yaml`: `voice: af_heart`, `gain: 1.0` |
| Brain rollback | `VR_BRAIN_MODEL=gpt-4o-mini ./mika-live.sh` |

Git checkpoints in the LIVE repo: tags `pre-mika-world-migration` (372e30f), `pre-mika-world-migration-wip`;
branch `checkpoint/live-wip-2026-10-09` (3893757); backups in `~/Documents/Mika-Migration-Backups/2026-10-09/`.
Branch `mika-world`: 3893757, 85b622b (DEV import), c58f518 (merge), aa1d30e (production wiring), 583b864 (ship-now), then the shutdown/launcher fixes commit.

## Before the first public stream (manual checks)

1. `.env` `YOUTUBE_CHANNEL_ID` names Math Unlocked (UCOhIp...), not Selwyn Builds. The stream key, chat reader and OAuth
   are all Selwyn Builds (UCKKJh...), and the pre-live check uses that one, so publishing is correct; fix `.env` (or set
   `VR_STREAM_CHANNEL_ID`) to remove the warning.
2. Run `./mika-live.sh --rehearse`, look at the title, comment and thumbnail it prints, Ctrl+C.
3. Run `./mika-live.sh`, check the OBS preview (scene "Mika World"), type GO.
4. In YouTube Studio: confirm the broadcast is on Selwyn Builds, the thumbnail applied, the opening comment posted once.
5. Listen for crackle in the first minutes (cause not found, see Limitations).

## Root causes fixed in this pass

- Bedroom reset loop: outdoor goals had `after=('return_home',)` and candidates were scene-restricted, so every activity
  started and ended in the bedroom. Removed; travel is only added for bedroom-only activities when she is away.
- Server never exited after Ctrl+C (launcher fell back to TERM after 120 s): the goodbye sets `should_exit`, then
  `bye()` sent a second SIGINT through uvicorn's `handle_exit`, which means `force_exit`, which skips the shutdown hooks.
  The YouTube chat browser was therefore closed during uvicorn's mass task cancellation, after Playwright's own reader
  task was cancelled, and `BrowserContext.close()` waited forever. Now a normal exit; hooks run; stop takes ~19 s.
- Launcher lock held by orphaned children (fd 9 inherited): closed for children.
- OBS starting in Safe Mode (websocket off): stale `.sentinel/run_*` files; cleared before launch when OBS is not running.
- World mode wrote `VR_ROOM_CAST` into `os.environ` (leaked into tests); the cast is now passed to `load_room`.

## Feature summary

- Activity registry and pool: 15 registry entries, only Stage-verified ones eligible; 5-hour cycle persisted in
  `data/mika-activity-pool.json`; empty pool means free time, never a loop.
- Magic: sanctuary in the garden, phone on a tripod, 8 spells with fixed Latin incantations (IPA pronunciations),
  9 lessons over levels 1 to 6, outcomes success/partial/fail/mishap, progress in `data/mika-magic.json`.
  The death clip is used only as a short harmless stumble (0 to 0.88 s).
- Dance: multi-routine sessions from 7 routines (macarena, chicken, step, snake_hiphop, booty_hiphop, ymca, belly) with real scores.
- Navigation: 22 real destinations; viewer requests ("go to the koi pond") with negation guard.
- Personality: compact MIKA STATE block replaces the 21k-character world dump.
- Brain: gpt-5.4-mini (reasoning none). Third-party price figures: $0.75 / $4.50 per 1M tokens in/out.
- Voice: Kokoro blend `af_bella:0.6,jf_alpha:0.4`, gain 0.7; same measured WER as af_heart (1.5%), higher pitch (233 vs 203 Hz).
- Pre-live: gpt-4.1-mini metadata (template fallback), gpt-image-2 thumbnail (about $0.04, max 2/day, once per session)
  then cached art then the permanent default; no em dashes anywhere public; opening comment posted once.
- Audio: wind as occasional ~2 s gusts, footsteps 0.16; water ripples and koi containment; meadow plane.
- Coding workstation stays behind `VR_FEATURE_CODING=0`.

## Animation inventory

6 Mixamo FBX converted with Blender to VRM clips in `frontend/vr-agent/assets/animations/local-fbx/`
(`MANIFEST.json`, 26 clips): magic_spell_cast, magic_wide_cast, magic_two_hand, magic_prepare_cast, magic_one_hand,
magic_mishap_fall. Sources in `assets/animations/mixamo-source/` (gitignored); inventory in `review/animation-import/`.

## Tests and evidence

- `tests/test_ship_now.py`, `test_autonomy.py`, `test_dev_voices.py`, `test_clause_chunks.py`, `test_kokoro_tts.py`: 52 passed.
- Full Python suite (`VR_CLASS_MODE=0`, browser-marked tests deselected): 848 passed, 15 failed. None of the 15 is from
  the migration: 9 Minecraft tests fail identically on the pre-migration checkpoint; 4 room tests (rabbit director,
  "asked you" follow-up, tagged-audio fake missing the `latency` argument, hiyori `cheer` action) fail on code and
  registries unchanged since the original LIVE commit; 2 `test_vrm_stage` SwiftShader browser tests are known flaky.
  Earlier full-suite runs showed 84 failures: these came from test-order leaks (`VR_ROOM_CAST` written into
  `os.environ` by world mode, `.env` class mode), now fixed, plus tests encoding the old voice and dance behaviour, now updated.
- Recordings: `review/ship-now/soak-12min-WITH-AUDIO.webm`, `dance-session-3-routines.webm`, `magic-lesson-level1.webm`.
- Production rehearsals (2026-10-10): ready in 12 to 13 s, OBS connected, stage drawn, dry run verified channel and key;
  shutdown 19 s with no processes or OBS sentinels left.

## Performance (12-minute soak)

FPS mean 54.7, 5th percentile 39.8; 219 frames over 50 ms (max 485 ms, at scene transitions). OBS CPU about 1.2%, 1080p30.

## Known limitations

- Crackle root cause not identified (Kokoro output has no clipping or edge clicks; suspects: render stalls or the OBS/PipeWire path).
- Bench sitting and lying under a tree are not implemented (registry entry disabled); chair sitting works.
- Long frames at scene transitions.
- Music beat-aligned only for Macarena.
- Generated thumbnail can draw her hair shorter than the model.
- Many DEV-imported modules use compact one-line style that `ruff check` flags (E701/E702); not reformatted to avoid a large risky diff.
- SwiftShader browser tests (e.g. `test_book_props`) are flaky on this machine.
