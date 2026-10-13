# Future polish milestone — recorded requests (NOT implemented)

Recorded 2026-10-13 at the end of Milestone I, at the developer's request. Do not implement without approval.

## 1. Remove the repetitive bell / chime during spellcasting and levelling
Where the bells come from (all original synthesis, so they can be changed freely):
* **Every cast**: `spell_<element>_activation` = two soft bell strikes a fifth apart
  (`tools/audio/synth_sfx.py` → `spell_layers()`, "activation: a subtle chime"), played by
  `AudioDirector._on_phase("activation")`; the `rune` layer adds another bell partial
  (`rr += bell(r * 4, …)`), and arcane impacts are bell pairs (`impact()`).
* **Combat impacts (Milestone H)**: `impact_light/heavy` include a two-bell "magical ring"
  (`tools/audio/synth_milestone_h.py` → `combat()`, `ring` term), played by `ImpactFX.play`.
* **Levelling / progress moments**: `trial_complete`, `rank_up` and `discovery` one-shots are bell
  arpeggios (`synth_sfx.py` → `oneshots()`), played on trial completion, rank change, clues and new places
  (`AudioDirector.setup`, lines ~58-61, ~209, ~218). (`level_up.ogg` exists but is not played anywhere.)
Suggested direction: replace activation chimes with non-tonal air/whoosh or element-specific textures,
vary pitch/timbre per cast, rate-limit progress one-shots (one cue per few seconds), and give levelling a
single distinct, non-bell cue. Re-run `synth_sfx.py` / `synth_milestone_h.py` after editing.

## 2. Luna's voice — manual experimentation
Current: Kokoro blend `af_kore:0.6,af_sky:0.4`, speed 0.97, gain 0.75 (`scripts/audio/voice_service.gd`
VOICES["luna"]). Not yet auditioned by a person. Suggested: render a few candidate blends (e.g. other
af_*/bf_* mixes, speed 0.93-1.0) for the same lines with the DEV Kokoro service, listen, pick; keep it
clearly distinct from Mika (`af_bella:0.6,jf_alpha:0.4`).

## 3. Dance choreography and singing lip-sync
Current (honest state): dances are Mixamo clips (Step / Snake / Booty Hip Hop, Belly) played in place and
speed-matched to the song's beat, changed every 8 bars; lip movement is amplitude-based from an ESTIMATED
vocal envelope of the mixed track (`tools/audio/analyze_song.py`). Later pass:
* choreography: per-song routines (clip sequence + phrase/section mapping), entrances/exits, travel steps
  with root motion, mirrored moves, accents on section changes; optional extra licensed/created clips;
* lip-sync: a separated vocal stem (local tool) and/or phoneme timing (vowel shapes aa/ih/ou/ee/oh)
  instead of a single "aa" amplitude; closed mouth on breaths;
* duets later (separate tracks, shared choreography) — see FUTURE_TALENT_FESTIVAL.md.
