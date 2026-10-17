#!/usr/bin/env bash
# Set up Kokoro-82M (af_heart) for Mika: isolated venv + official model files,
# each checked against the SHA-256 recorded when it was first verified.
set -euo pipefail
cd "$(dirname "$0")/../.."
uv venv --python 3.10 tools/kokoro/.venv
uv pip install --python tools/kokoro/.venv/bin/python -r tools/kokoro/requirements.txt
mkdir -p models/kokoro
REL=https://github.com/thewh1teagle/kokoro-onnx/releases/download/model-files-v1.0
HF=https://huggingface.co/hexgrad/Kokoro-82M/resolve/main
fetch() { [ -f "models/kokoro/$1" ] || curl -fL --retry 3 -o "models/kokoro/$1" "$2"; }
fetch kokoro-v1.0.onnx "$REL/kokoro-v1.0.onnx"
fetch voices-v1.0.bin "$REL/voices-v1.0.bin"
fetch af_heart_0_official_sample.wav "$HF/samples/af_heart_0.wav"
fetch af_heart.pt "$HF/voices/af_heart.pt"
( cd models/kokoro && sha256sum -c - <<'SUMS'
7d5df8ecf7d4b1878015a32686053fd0eebe2bc377234608764cc0ef3636a6c5  kokoro-v1.0.onnx
bca610b8308e8d99f32e6fe4197e7ec01679264efed0cac9140fe9c29f1fbf7d  voices-v1.0.bin
dd7999ebbc8369779d5d3f504399ea466c909339f90231143416a7819a2047fc  af_heart_0_official_sample.wav
0ab5709b8ffab19bfd849cd11d98f75b60af7733253ad0d67b12382a102cb4ff  af_heart.pt
SUMS
)
echo "Kokoro ready. Test: tools/kokoro/.venv/bin/python tools/kokoro/bench.py '[[\"kokoro-v1.0.onnx\",4,\"/tmp/af_heart_test.wav\"]]'"
