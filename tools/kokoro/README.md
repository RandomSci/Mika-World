# Kokoro-82M voice for Mika (`af_heart`)

Mika speaks with Kokoro-82M, voice `af_heart` (American English, female), run
locally on the CPU through ONNX Runtime. It is free: no account, key or network
once installed. If Kokoro is unavailable, Edge TTS (en-US-AnaNeural) speaks
instead, line by line.

## Setup (once)

```bash
tools/kokoro/setup.sh
```

The script:
1. creates the isolated environment `tools/kokoro/.venv` (Python 3.10, pinned in `requirements.txt`), separate from the app's own `.venv`;
2. downloads the official files into `models/kokoro/`;
3. checks each file's SHA-256.

`models/kokoro/` and the venv are git-ignored (about 450 MB).

## How it runs

- `room/characters/mika.yaml` selects `kokoro_tts` with `voice: af_heart`, `lang: en-us`, `speed: 1.0`, and an `edge_tts` fallback.
- When the server builds Mika's voice (at startup), `src/open_llm_vtuber/tts/kokoro_tts.py` starts `service.py` on `127.0.0.1:12460`. The service loads the model, warms it up, and serves until the server exits.
  - Ready about 3 s after server start.
  - The service exits within about 2 s when the server stops, even after `kill -9`.
- A service that is already running on that port is reused. You can run it by hand:
  `tools/kokoro/.venv/bin/python tools/kokoro/service.py --port 12460`
- One line is synthesized at a time. A reply's sentences are synthesized in order. Long sentences are split at commas, semicolons, colons and dashes into clauses (the first clause at most 60 characters), so each piece is ready before the previous one finishes playing.
- An interrupted reply sends no further requests. At most the clause already in progress completes.
- If the service fails or is killed, that line falls back to Edge immediately and the service restarts in the background. After 3 failures in a row, Kokoro rests for 10 minutes (the room's existing fallback policy).

## Settings (`mika.yaml` → `voice.settings`, or `conf.yaml` → `kokoro_tts`)

| key | default | meaning |
|---|---|---|
| `voice` | `af_heart` | Kokoro voice |
| `lang` | `en-us` | phonemizer language |
| `speed` | `1.0` | natural speed. Leave it at 1.0; there is no pitch setting. |
| `threads` | `4` | ONNX CPU threads. On the i5-13420H, 4 was fastest: 6 threads gave RTF 0.36 and 2 threads 0.46, against 0.30 for 4. |
| `port` | `12460` | local service port |
| `clause_chunk_chars` | `60` | first clause size for long sentences. Set to 0 to disable chunking. |
| `model_path` / `voices_path` / `python_path` | `models/kokoro/...`, `tools/kokoro/.venv/bin/python` | file locations |

To switch Mika back to Edge, set `tts_model: edge_tts` with `settings: {voice: en-US-AnaNeural}` in `mika.yaml`.

## Tools

- `bench.py`: load, warm-up and real-time factor per model and thread count.
- `compare.py`: objective closeness to the official `af_heart` sample, measured as mel-cepstral distance, long-term spectrum correlation and F0, with other Kokoro voices as controls.

## Licences

See `PROVENANCE.md`.
