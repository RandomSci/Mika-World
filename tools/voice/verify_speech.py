#!/usr/bin/env python3
"""Transcribe spoken segments from a recording with the local SenseVoice model (sherpa-onnx), read-only.

usage: verify_speech.py <wav> <start_s> <end_s> [<start_s> <end_s> ...]
Run with an interpreter that has sherpa_onnx (e.g. the production venv, used read-only):
  PYTHONDONTWRITEBYTECODE=1 /home/selwyn/Documents/Mika-Live/.venv/bin/python -I tools/voice/verify_speech.py rec.wav 72.5 78
"""
import sys
import numpy as np
import soundfile as sf
import sherpa_onnx

MODEL = "/home/selwyn/Documents/Open-LLM-VTuber/models/sherpa-onnx-sense-voice-zh-en-ja-ko-yue-2024-07-17"
rec = sherpa_onnx.OfflineRecognizer.from_sense_voice(model=MODEL + "/model.int8.onnx", tokens=MODEL + "/tokens.txt", language="en", use_itn=True, num_threads=2)
x, sr = sf.read(sys.argv[1])
if x.ndim > 1:
    x = x.mean(1)
args = [float(a) for a in sys.argv[2:]]
for i in range(0, len(args), 2):
    seg = x[int(args[i] * sr): int(args[i + 1] * sr)].astype(np.float32)
    s = rec.create_stream()
    s.accept_waveform(sr, seg)
    rec.decode_stream(s)
    print("%.1f-%.1f s: %s" % (args[i], args[i + 1], s.result.text))
