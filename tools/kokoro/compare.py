"""Objective closeness of generated speech to the official af_heart sample.

Features (no listening claims): median F0 and its spread, a long-term average
log spectrum (timbre / brightness) and the mean of mel-cepstra (vocal-tract
shape), compared by correlation / distance. Control voices show the scale.
"""

import json
import os
import sys
import numpy as np
import soundfile as sf
from kokoro_onnx import Kokoro

M = os.path.join(os.path.dirname(__file__), "..", "..", "models", "kokoro")
LINE = "Hey, everyone! I'm Mika! Welcome to my little world. The garden looks beautiful today, doesn't it? I think I'll take a walk by the koi pond!"


def frames(x, n=1024, h=256):
    k = 1 + (len(x) - n) // h
    return np.stack([x[i * h : i * h + n] for i in range(k)]) * np.hanning(n)


def to_mel(f):
    return 2595 * np.log10(1 + f / 700)


def from_mel(m):
    return 700 * (10 ** (m / 2595) - 1)


def mel_fb(sr, n=1024, bands=40, lo=60, hi=8000):
    pts = from_mel(np.linspace(to_mel(lo), to_mel(hi), bands + 2))
    bins = np.floor((n + 1) * pts / sr).astype(int)
    fb = np.zeros((bands, n // 2 + 1))
    for b in range(bands):
        a, c, d = bins[b], bins[b + 1], bins[b + 2]
        fb[b, a:c] = (np.arange(a, c) - a) / max(1, c - a)
        fb[b, c:d] = (d - np.arange(c, d)) / max(1, d - c)
    return fb


def features(x, sr):
    if x.ndim > 1:
        x = x.mean(1)
    if sr != 24000:
        t = np.arange(0, len(x) / sr, 1 / 24000)
        x = np.interp(t, np.arange(len(x)) / sr, x)
        sr = 24000
    f = frames(x)
    spec = np.abs(np.fft.rfft(f, axis=1)) ** 2
    energy = spec.sum(1)
    voiced = energy > np.percentile(energy, 40)
    mel = np.log(spec[voiced] @ mel_fb(sr).T + 1e-10)
    n = mel.shape[1]
    dct = np.cos(np.pi / n * (np.arange(n) + 0.5)[None, :] * np.arange(13)[:, None])
    cep = (mel @ dct.T)[:, 1:]  # drop c0 (loudness)
    ltas = mel.mean(0)
    ltas -= ltas.mean()
    # F0 by normalized autocorrelation over 70-500 Hz on voiced frames.
    f0 = []
    for fr in f[voiced]:
        ac = np.correlate(fr, fr, "full")[len(fr) - 1 :]
        ac /= ac[0] + 1e-9
        lo, hi = int(sr / 500), int(sr / 70)
        lag = lo + np.argmax(ac[lo:hi])
        if ac[lag] > 0.45:
            f0.append(sr / lag)
    f0 = np.array(f0)
    return {
        "f0_median": float(np.median(f0)),
        "f0_iqr": float(np.subtract(*np.percentile(f0, [75, 25]))),
        "cep": cep.mean(0),
        "ltas": ltas,
    }


def compare(a, b):
    return {
        "cepstral_distance": round(float(np.linalg.norm(a["cep"] - b["cep"])), 2),
        "spectrum_correlation": round(
            float(np.corrcoef(a["ltas"], b["ltas"])[0, 1]), 3
        ),
        "f0_median_hz": round(a["f0_median"], 1),
        "f0_iqr_hz": round(a["f0_iqr"], 1),
    }


if __name__ == "__main__":
    out = sys.argv[1]
    ref_x, ref_sr = sf.read(os.path.join(M, "af_heart_0_official_sample.wav"))
    ref = features(ref_x, ref_sr)
    rows = {
        "official_sample": {
            "f0_median_hz": round(ref["f0_median"], 1),
            "f0_iqr_hz": round(ref["f0_iqr"], 1),
            "seconds": round(len(ref_x) / ref_sr, 2),
            "rate": ref_sr,
        }
    }
    for model, voices in (
        (
            "kokoro-v1.0.onnx",
            ["af_heart", "af_bella", "af_nicole", "af_sarah", "af_sky"],
        ),
        ("kokoro-v1.0.int8.onnx", ["af_heart"]),
    ):
        k = Kokoro(os.path.join(M, model), os.path.join(M, "voices-v1.0.bin"))
        for v in voices:
            audio, sr = k.create(LINE, voice=v, speed=1.0, lang="en-us")
            rows[f"{v} ({'int8' if 'int8' in model else 'fp32'})"] = compare(
                features(audio, sr), ref
            )
    json.dump(rows, open(out, "w"), indent=1)
    print(json.dumps(rows, indent=1))
