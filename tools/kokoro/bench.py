"""Kokoro af_heart CPU benchmark: load, warm-up, generation vs audio duration."""

import os
import sys
import time
import json
import soundfile as sf
import onnxruntime as ort
from kokoro_onnx import Kokoro

MODELS = os.path.join(os.path.dirname(__file__), "..", "..", "models", "kokoro")
LINE = "Hey, everyone! I'm Mika! Welcome to my little world. The garden looks beautiful today, doesn't it? I think I'll take a walk by the koi pond!"
SHORT = "Hi! I'm so happy you're here."


def run(model, threads, out=None):
    so = ort.SessionOptions()
    so.intra_op_num_threads = threads
    so.inter_op_num_threads = 1
    t = time.perf_counter()
    sess = ort.InferenceSession(
        os.path.join(MODELS, model), so, providers=["CPUExecutionProvider"]
    )
    k = Kokoro.from_session(sess, os.path.join(MODELS, "voices-v1.0.bin"))
    load = time.perf_counter() - t
    t = time.perf_counter()
    k.create("Hello.", voice="af_heart", speed=1.0, lang="en-us")
    warm = time.perf_counter() - t
    rows = {}
    for name, text in (("short", SHORT), ("line", LINE)):
        best = None
        for _ in range(3):
            t = time.perf_counter()
            audio, sr = k.create(text, voice="af_heart", speed=1.0, lang="en-us")
            g = time.perf_counter() - t
            best = min(best or g, g)
        rows[name] = {
            "gen_s": round(best, 3),
            "audio_s": round(len(audio) / sr, 3),
            "rtf": round(best / (len(audio) / sr), 3),
        }
        if out and name == "line":
            sf.write(out, audio, sr)
    return {
        "model": model,
        "threads": threads,
        "load_s": round(load, 2),
        "warmup_s": round(warm, 3),
        **rows,
    }


if __name__ == "__main__":
    for model, threads, out in json.loads(sys.argv[1]):
        print(json.dumps(run(model, threads, out)), flush=True)
