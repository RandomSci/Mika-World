# Mika World V3 — first public test: release checklist

Status as of the Milestone J verification (2026-10-13). Tick only what has been verified on the release machine.

## Release-blocking (must be resolved or consciously accepted before going public)
- [ ] **Voice licence**: Mika's and Luna's confirmed voices are Microsoft Edge neural voices reached through the
      consumer Read Aloud endpoint (`edge-tts`). Confirm that this use is acceptable for a (possibly monetised)
      livestream, or move the same voices to Azure AI Speech (licensed; needs a key — small provider change in
      `tools/voice/edge_service.py`). Until then Kokoro (Apache-2.0) is the safe fallback (`provider: kokoro`).
- [ ] **Song rights**: "ミカの魔法世界！" (Suno-generated) — confirm the plan it was generated under allows
      broadcast / commercial use (kept local, git-ignored).
- [ ] **VRM licences**: the imported VRMs carry `commercialUsage: personalNonProfit` (VRoid default). Re-export
      with the intended licence if the channel is monetised.
- [ ] **Performance on the stream machine**: 10-minute windowed run on AC power with the stream encoder and voice
      running and no unrelated rendering jobs — average >= 28 FPS, no sustained drops (see the Milestone J report).

## Important but non-blocking
- [ ] Laugh / giggle reaction clips are generated candidates — audition and keep or replace.
- [ ] Luna's signature spell has camera beats and power but no dedicated signature visuals yet (Mika's is done).
- [ ] Combat effects compile their shaders on first use (a few 100-150 ms hitches in the first fight of a
      session) — add a warm-up pass at load.
- [ ] Tree canopies still use the decimated broadleaf asset; the leaf material is fixed (depth-correct,
      translucent) but the canopy density is a future art pass.
- [ ] Ultimate Monsters (CC0) could replace / extend creatures once its Google Drive download works again.
- [ ] Dance choreography / phoneme lip-sync (docs/FUTURE_POLISH.md #3).

## Future expansion (not for the first test)
- Regions beyond the Sanctuary at Level 10+, more creature families, Luna-focused / shared stream outputs,
  the Talent Festival (docs/FUTURE_TALENT_FESTIVAL.md), Level 20+ orbits and forms.

## Go / no-go run (do this on the stream machine)
1. `git checkout milestone-j` · `tools/setup_local_assets.sh` (raw Mixamo FBX) · `python3 -m venv .venv-voice &&
   .venv-voice/bin/pip install edge-tts==7.2.8` · `--headless --import`.
2. `tools/run_regression.sh all` → 0 failing suites.
3. Windowed: `--mjtest=encounter --kind=emberwing`, `--kind=hollow_sentinel`, `--mjtest=signature`,
   `--mjtest=awaken --who=mika|luna`, `--mjtest=policy`, `--mjtest=voices`, `--mjtest=aftermath` → PASS.
4. Back up `user://mika_world_save.json`; start `./run.sh live --brain`; watch 15 minutes: Mika stays on camera,
   voices are the confirmed ones, no bell on casts.
5. Rollback if needed: `git checkout milestone-i-final` (the Milestone I build) — saves are forward/backward
   compatible (Milestone J adds no new save fields).
