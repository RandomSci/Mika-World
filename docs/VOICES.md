# Character voices: one voice per character (2026-10-15)

The developer approved the change: "change their voice already". The auditions are in `docs/VOICE_AUDITIONS.md`.

| character | voice identity | model / voice | processing |
|---|---|---|---|
| **Mika** | `mika-leda-p115-v1` | Gemini `gemini-3.8-flash-tts`, prebuilt **Leda** | +15 % pitch, formant-preserving (rubberband), −18 LUFS, ×0.9 |
| **Luna** | `luna-achernar-p115-v1` | Gemini `gemini-3.8-flash-tts`, prebuilt **Achernar** | same chain |
| Oriel (Phoenix) | unchanged | Gemini `gemini-2.5-flash-preview-tts`, **Kore** | unchanged, plus the VoicePhoenix bus |
| travellers / NPCs | unchanged | Kokoro / Edge | — |

The delivery is the audition's `3b_directed_pitch15` variant: her persona plus a delivery style, then +15 %.

## Why the voice used to change
Before this change Mika and Luna could come out of **four different voices**:
* Edge for normal lines;
* their Kokoro blend whenever the Edge service was slow or failed;
* Kokoro (IPA) for every Latin incantation;
* Edge again for laughs and gasps.

Kokoro was also the default for any unknown speaker, with *Mika's* blend.

## The rule now
Every sound Mika or Luna makes goes through her **voice identity** (`data/voices.json` → `speakers.<who>`, provider
`gemini_identity`). That covers speech, laughs, giggles, gasps, cries of impact, effort and breathing, and Latin
incantations. Each identity fixes:
* the model, the prebuilt voice, and a **persona** sentence (who she is and how she sounds);
* a **fixed set of moods**: neutral, happy, excited, surprised, concerned, sad, frustrated, determined, scared, hurt,
  tender, teasing, whisper, casting, latin, plus the reaction kinds. A line's delivery is
  `persona; mood`. The mood comes from the caller (`opts.mood`), or `latin` for an incantation, or her current
  facial expression (`emotion_moods`), or `neutral`. Free-text direction is never sent, because it makes the voice
  drift.
* the **processing chain** (`post`), applied to every clip.

Where a line comes from, in order:
1. **shipped**: `assets/voice/<who>/<key>.wav`. Fixed lines are pre-rendered by `tools/voice/voice_identity.py ship`
   (manifest in `assets/voice/<who>/manifest.json`): reaction clips, every incantation in
   `data/pronunciations.json`, the aftermath lines in `data/impacts.json`, and the Phoenix bystander lines.
2. **session cache**: `user://voice_cache/<identity>/<key>.wav`. Every new line is rendered once and kept.
3. **one synthesis in her voice**: asynchronous, with a timeout and one retry on a transient error. A 429 pauses
   that model for ten minutes. The audio is validated (length, loudness). The same voice on
   `gemini-2.5-flash-preview-tts` is tried only if the main model is unavailable (400/404).
4. **otherwise a subtitle only.** There is no cross-voice fallback. Kokoro and Edge are never used for Mika or Luna.
   The result says `audio: false` and why.

`key = sha1("<identity>|<persona>; <mood text>|<text>")`, computed identically by the game and the tool.

**Changing an identity** (another voice, pitch, persona or mood text) means bumping `identity` (for example `-v2`)
and running `python3 tools/voice/voice_identity.py ship` again. Old clips are then never mixed with new ones.

## Test
`--mjtest=voices` checks:
* both identities exist, and nobody needs Edge;
* each mage speaks in her own voice, with the right voice and identity;
* a fixed line plays from the shipped set;
* Latin is spoken in her voice with the `latin` mood;
* a gasp plays;
* laugh tokens are handled;
* offline gives a subtitle and never another voice;
* no line of theirs was spoken by Kokoro or Edge.

## Daily quota (measured 2026-10-15)
The project key is on Gemini's **Tier 1**. `gemini-3.8-flash-tts` allows **100 requests per day**; the 429 answer
says so. `gemini-2.5-flash-preview-tts` serves the same prebuilt voices with its own daily quota. When the first
model is out of quota or unavailable, the identity switches to the second model, with the same voice, persona, mood
and processing chain. Raising the tier would be a new paid service, so it was not done.

What this means:
* Fixed lines are shipped once and then cost nothing.
* Every new line is cached forever.
* Live (LLM) lines draw on a budget of about **200 new lines a day**. After that, new lines are subtitled until the
  quota resets (about midnight Pacific).

A 24/7 stream will exceed this on busy days. The structural option is a **local voice model** made from her
identity clips: unlimited, offline, and the same timbre. It is not in production; see the open question in the
session report.

## Known limits
* A brand-new (LLM) line needs one cloud call, about 1–4 s, before it plays the first time. Prefetch hides this
  where the text is known in advance.
* Without network and without a key, unshipped lines are silent (subtitled). This is by design: a different
  voice is worse than none.
* The previous settings (Edge Ava/Nanami and the Kokoro blends) are kept under `previous` in `voices.json` for
  rollback. They are not used.
