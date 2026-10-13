#!/usr/bin/env python3
"""Milestone K: ambience for the Whispering Woods (original audio, no samples, no tonal/bell content).

  amb_waterfall   the falls: a deep body of falling water (low rumble + broadband roar) with slow surges
  amb_stream      the river: bright, busy babble (many small band-limited bursts) over a soft wash
  amb_den         the creature den: a slow cave "breath" (filtered brown noise swelling and receding) and a
                  low, distant rumble — unsettling, not musical

All loops are seamless (crossfaded tail into head). Run:  python3 tools/audio/synth_milestone_k.py  (deterministic)
"""
import os
import subprocess

import numpy as np
from scipy.io import wavfile
from scipy.signal import butter, lfilter, sosfilt

SR = 44100
ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
OUT = os.path.join(ROOT, "assets", "audio", "synth")
rng = np.random.default_rng(20261015)


def t(sec):
    return np.arange(int(SR * sec)) / SR


def _sos(kind, f, order=2):
    return butter(order, f, btype=kind, fs=SR, output="sos")


def lp(x, f, order=2):
    return sosfilt(_sos("low", min(f, SR / 2 - 100), order), x)


def hp(x, f, order=2):
    return sosfilt(_sos("high", f, order), x)


def bp(x, lo, hi, order=2):
    return sosfilt(_sos("band", [lo, min(hi, SR / 2 - 100)], order), x)


def noise(sec, kind="white"):
    w = rng.standard_normal(int(SR * sec))
    if kind == "pink":
        b = [0.049922035, -0.095993537, 0.050612699, -0.004408786]
        a = [1, -2.494956002, 2.017265875, -0.522189400]
        w = lfilter(b, a, w)
    elif kind == "brown":
        w = np.cumsum(w)
        w = w - lp(w, 0.5)
    return w / (np.max(np.abs(w)) + 1e-9)


def loopable(y, xf=2.0):
    k = int(SR * xf)
    head, tail = y[:k].copy(), y[-k:].copy()
    w = np.linspace(0, 1, k)
    y = y[k:].copy()
    y[-k:] = tail * (1 - w) + head * w
    return y


def slow(sec, rate, depth, phase=0.0):
    tt = t(sec)
    return 1.0 - depth + depth * (0.5 + 0.5 * np.sin(2 * np.pi * rate * tt + phase))


def save(name, y, peak=0.8):
    os.makedirs(OUT, exist_ok=True)
    y = np.asarray(y, dtype=np.float64)
    y = y / (np.max(np.abs(y)) or 1.0) * peak
    wav = os.path.join(OUT, name + ".tmp.wav")
    ogg = os.path.join(OUT, name + ".ogg")
    wavfile.write(wav, SR, (y * 32767).astype(np.int16))
    subprocess.run(["ffmpeg", "-y", "-loglevel", "error", "-i", wav, "-c:a", "libvorbis", "-q:a", "5", ogg], check=True)
    os.remove(wav)
    print("wrote", os.path.relpath(ogg, ROOT), f"{len(y) / SR:.2f}s")


def waterfall():
    sec = 30.0
    surge = slow(sec, 0.09, 0.25) * slow(sec, 0.23, 0.12, 1.1)
    body = lp(noise(sec, "brown"), 160) * 0.9
    roar = bp(noise(sec, "pink"), 250, 2600) * 0.75
    hiss = bp(noise(sec, "white"), 3000, 9000) * 0.12
    y = (body + roar * surge + hiss * surge ** 2)
    save("amb_waterfall", loopable(y), 0.55)


def stream():
    sec = 24.0
    n = int(SR * sec)
    y = bp(noise(sec, "pink"), 400, 2400) * 0.35
    # babble: many tiny bursts of band-passed noise at random centre frequencies (water over stones)
    burst = np.zeros(n)
    for _ in range(int(sec * 38)):
        L = int(SR * rng.uniform(0.012, 0.05))
        s = rng.integers(0, n - L)
        f = rng.uniform(700, 3800)
        b = bp(rng.standard_normal(L + 400), f * 0.85, f * 1.15)[400:]
        b *= np.hanning(L) * rng.uniform(0.2, 1.0)
        burst[s:s + L] += b
    y += burst * 0.9
    y *= slow(sec, 0.13, 0.15)
    save("amb_stream", loopable(y), 0.4)


def den():
    sec = 32.0
    tt = t(sec)
    breath = lp(noise(sec, "brown"), 220) * (0.25 + 0.75 * np.clip(np.sin(2 * np.pi * tt / 8.0), 0, 1) ** 2)
    air = bp(noise(sec, "pink"), 150, 600) * 0.3 * slow(sec, 0.125, 0.6)
    rumble = lp(noise(sec, "brown"), 60) * 0.8 * slow(sec, 0.05, 0.5, 2.0)
    y = breath + air + rumble
    save("amb_den", loopable(y), 0.45)


if __name__ == "__main__":
    waterfall()
    stream()
    den()
