# Mika and Luna — voice auditions (2026-10-15)

**APPROVED 2026-10-15** ("change their voice already"): Mika = Leda +15 %, Luna = Achernar +15 % are now the
production voices; see `docs/VOICES.md`. The text below is the original audition record. Oriel keeps Gemini **Kore** and her fallback, unchanged. These files are for the developer to listen
to and choose from. A voice changes only after the developer approves one.

## How they were made
* `tools/voice/gemini_audition.py` uses the Gemini API **Interactions** endpoint with model **`gemini-3.8-flash-tts`**
  (the current TTS model in https://ai.google.dev/gemini-api/docs/speech-generation). The key is the project's
  `GEMINI_API_KEY`, read from `.env` and never printed.
* Delivery is steered with the documented **`speech_metadata.style`** annotation. This model has no pitch or rate
  parameter, and the text is spoken verbatim. Each style string is a short persona plus the line's emotion: no long
  "director's notes", which the docs warn cause voice drift.
* Pitch processing uses ffmpeg's **rubberband** filter with **`formant=preserved`** and `pitchq=quality`. The pitch
  rises without speeding the clip up (durations are identical) and without the chipmunk timbre of a resample.
* All results are cached by hash in `~/.cache/mika_voice_auditions`: re-running costs nothing. 50 TTS calls were made
  in total.

## Files: `assets/voice/auditions/<mika|luna>/<line>_<variant>.wav` (24 kHz mono)
Lines: `casual`, `excitement`, `surprise`, `concern`, `magic` (casting). Variants, in listening order:

| variant | what it is |
|---|---|
| `1_original` | the selected voice, no direction |
| `2_pitch15` | (1) + 15 % pitch (2.42 semitones), formant-preserving |
| `3_directed` | re-synthesised with a per-line delivery style (emotion, prosody, pacing) |
| `3b_directed_pitch15` | (3) + 15 % pitch |
| `4_best` | (3) + a gentler +8 % lift, light presence EQ (+2.5 dB at 3.2 kHz, −2 dB at 250 Hz), soft compression, loudness −18 LUFS |
| `5_alt_<Voice>` | other youthful prebuilt voices with the same direction |

Personas used:
* **Mika** (Leda; alternatives Zephyr, Autonoe, Laomedeia): "a young girl of about sixteen, a cheerful apprentice
  mage: bright, gentle, playful and warm, natural youthful voice".
* **Luna** (Achernar; alternatives Vindemiatrix, Aoede, Despina): "... a quiet, clever moon mage: soft, calm, curious
  and a little mysterious, sometimes teasing".

## Measurements
Average median F0 over the five lines; per-file values are in `assets/voice/auditions/measurements.json`.

| | original | +15 % | directed | directed +15 % | best | alternatives |
|---|---|---|---|---|---|---|
| Mika (Leda) | 255 Hz | 287 | 300 | 353 | 329 | Autonoe 323 · Zephyr 303 · Laomedeia 291 |
| Luna (Achernar) | 238 Hz | 281 | 219 | 251 | 248 | Despina 232 · Vindemiatrix 199 · Aoede 196 |

Observations:
* **Direction alone raised Mika's pitch** (255 → 300 Hz) more than the +15 % shift did, and with natural intonation
  rather than processing. That is why `4_best` uses a smaller +8 % lift on top.
* **Luna's "calm, mysterious" direction lowers her pitch** (238 → 219 Hz). Her youthful-but-calm target sits around
  `4_best` (≈ 248 Hz) or `3b` (≈ 251 Hz).
* The full +15 % on top of direction (`3b`, Mika 353 Hz) is the variant most at risk of sounding artificially
  high. Listen to it last.

Measurements cannot judge naturalness. **The final choice needs the developer's ears**: I have not heard these
files. Once a variant is chosen, production would switch `speakers.mika`/`luna` to
`{"provider": "gemini", "model": "gemini-3.8-flash-tts", "voice": ..., "styles": ...}` with the post-processing
applied after synthesis. The asynchronous synthesis, the per-line cache, Kokoro fallback, timeouts and the
quota pause are unchanged.
