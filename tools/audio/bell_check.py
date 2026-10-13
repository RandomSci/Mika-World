#!/usr/bin/env python3
"""Objective check for the bell / chime timbre (Milestone J). A bell or chime is a NARROW, SUSTAINED tonal
peak in the upper-mid range (600-6000 Hz) that rings on after its onset. For each file: STFT; in every
frame find the most prominent peak in that band (peak magnitude / median magnitude of the band); a
'ringing' frame has a peak >= PROM and the SAME frequency bin stays prominent for >= HOLD seconds.
bell_score = fraction of the file's active frames that are ringing. Usage:
  python3 tools/audio/bell_check.py <file.ogg|dir> [...]
"""
import os
import subprocess
import sys

import numpy as np

SR = 22050
PROM = 18.0
HOLD = 0.25


def load(path):
    raw = subprocess.run(["ffmpeg", "-loglevel", "error", "-i", path, "-ac", "1", "-ar", str(SR), "-f", "f32le", "-"],
                         capture_output=True, check=True).stdout
    return np.frombuffer(raw, dtype=np.float32)


def bell_score(y):
    n, hop = 2048, 256
    if len(y) < n:
        return 0.0
    win = np.hanning(n)
    frames = np.lib.stride_tricks.sliding_window_view(y, n)[::hop] * win
    mag = np.abs(np.fft.rfft(frames, axis=1))
    f = np.fft.rfftfreq(n, 1 / SR)
    band = (f >= 600) & (f <= 6000)
    mb = mag[:, band]
    energy = mag.sum(axis=1)
    active = energy > energy.max() * 0.05
    med = np.median(mb, axis=1) + 1e-9
    pk = mb.argmax(axis=1)
    prom = mb.max(axis=1) / med
    hold = int(HOLD * SR / hop)
    ringing = np.zeros(len(mb), bool)
    run_start = 0
    for i in range(1, len(mb) + 1):
        if i == len(mb) or not (prom[i] >= PROM and prom[i - 1] >= PROM and abs(int(pk[i]) - int(pk[i - 1])) <= 1):
            if i - run_start >= hold and prom[run_start] >= PROM:
                ringing[run_start:i] = True
            run_start = i
    return float((ringing & active).sum() / max(1, active.sum()))


if __name__ == "__main__":
    files = []
    for a in sys.argv[1:]:
        files += [os.path.join(a, x) for x in sorted(os.listdir(a)) if x.endswith(".ogg")] if os.path.isdir(a) else [a]
    for p in files:
        print(f"{bell_score(load(p)):.3f}  {os.path.basename(p)}")
