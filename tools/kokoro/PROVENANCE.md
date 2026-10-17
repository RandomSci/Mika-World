# Kokoro voice: provenance and licences

All files were downloaded on 2026-10-09 and verified by SHA-256 (`setup.sh` re-checks them).

| file (`models/kokoro/`) | source | bytes | SHA-256 | licence |
|---|---|---|---|---|
| `kokoro-v1.0.onnx` | github.com/thewh1teagle/kokoro-onnx, release `model-files-v1.0` | 325532387 | `7d5df8ec…3636a6c5` | Apache-2.0 (Kokoro-82M weights, hexgrad) |
| `voices-v1.0.bin` | same release | 28214398 | `bca610b8…1fbf7d` | Apache-2.0 |
| `kokoro-v1.0.int8.onnx` | same release (benchmark only, not used) | 92361271 | `6e742170…f6406cb` | Apache-2.0 |
| `af_heart.pt` | huggingface.co/hexgrad/Kokoro-82M `voices/af_heart.pt` | 523425 | `0ab5709b…a102cb4ff` | Apache-2.0 |
| `af_heart_0_official_sample.wav` | huggingface.co/hexgrad/Kokoro-82M `samples/af_heart_0.wav` | 237644 | `dd7999eb…a2047fc` | Apache-2.0 (reference only) |

## Verification

- **Voice tensor:** the `af_heart` style tensor inside `voices-v1.0.bin` is bit-identical to the official `hexgrad/Kokoro-82M` file `voices/af_heart.pt` (130 560 floats, maximum difference 0.0).
- **Model files:** their sizes match the GitHub release API. The release publishes no digests, so the hashes above were recorded at download.

## Software in the isolated environment (`tools/kokoro/.venv`)

| package | licence |
|---|---|
| kokoro-onnx 0.6.1 | MIT |
| onnxruntime 1.23.2 | MIT |
| soundfile 0.14.0 | BSD-3-Clause |
| numpy 2.2.6 | BSD |
| phonemizer 3.4.0 | GPL-3.0-or-later |
| espeakng-loader 0.2.4, bundling `libespeak-ng` 1.52 | espeak-ng is GPL-3.0-or-later |

The GPL parts are used only inside the separate Kokoro service process. The app talks to that process over local HTTP and does not import or link them.

- Running it locally is free.
- **Redistributing that environment** (for example in an installer or bundle) brings GPL obligations for those components: provide their source and licence. The app's own code is not affected.

**Generated speech:** Kokoro's Apache-2.0 weights put no restriction on using the generated audio, including commercially and on stream.
