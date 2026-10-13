#!/usr/bin/env python3
"""Offline analysis of a song in the music library -> timing.json (numpy/scipy only, no network).

  python3 tools/audio/analyze_song.py assets/audio/music/library/<song_id>

Produces (all times in seconds on the ORIGINAL file's timeline):
  bpm, beats, downbeats (bar starts, 4/4 assumed), bar_length
  sections      novelty-based boundaries snapped to bars, each with mean loudness
  endings       bar starts where the music naturally closes a phrase (a section boundary or an 8-bar phrase
                end followed by a drop in loudness): preferred stop points for a performance
  vocal         ESTIMATED vocal activity for a mixed track: an envelope (25 Hz) from harmonic energy in the
                voice band with percussive transients removed, plus on/off segments. This is an amplitude-style
                estimate, NOT phoneme timing and NOT a separated vocal stem.
Everything is measured; nothing is invented. Re-run whenever the audio changes.
"""
import json
import os
import subprocess
import sys

import numpy as np
from scipy.ndimage import median_filter, uniform_filter1d
from scipy.signal import find_peaks, stft

SR = 22050
HOP = 512


def decode(path):
    raw = subprocess.run(["ffmpeg", "-v", "error", "-i", path, "-ac", "1", "-ar", str(SR), "-f", "f32le", "-"],
                         capture_output=True, check=True).stdout
    return np.frombuffer(raw, np.float32).astype(np.float64)


def spectrogram(y):
    f, t, Z = stft(y, fs=SR, nperseg=2048, noverlap=2048 - HOP, boundary=None, padded=False)
    return f, t, np.abs(Z)


def mel_bands(f, S, n=40):
    mel = lambda hz: 2595 * np.log10(1 + hz / 700)
    edges = np.linspace(mel(30), mel(SR / 2 * 0.95), n + 2)
    hz = 700 * (10 ** (edges / 2595) - 1)
    out = np.zeros((n, S.shape[1]))
    for i in range(n):
        lo, c, hi = hz[i], hz[i + 1], hz[i + 2]
        w = np.clip(np.minimum((f - lo) / (c - lo + 1e-9), (hi - f) / (hi - c + 1e-9)), 0, None)
        out[i] = w @ S
    return np.log1p(out * 10)


def beat_track(onset, fps):
    o = onset - onset.mean()
    ac = np.correlate(o, o, "full")[len(o) - 1:]
    lags = np.arange(len(ac)) / fps
    ok = (lags > 60 / 180) & (lags < 60 / 70)
    # prefer tempos near 120 (log-gaussian prior), as is common for tempo estimators
    bpms = 60 / np.maximum(lags, 1e-9)
    prior = np.exp(-0.5 * (np.log2(bpms / 120) / 0.9) ** 2)
    score = np.where(ok, ac * prior, -np.inf)
    period = int(np.argmax(score))
    bpm = 60 * fps / period
    # dynamic-programming beat placement (Ellis 2007)
    n = len(onset)
    cum = onset.copy()
    back = np.full(n, -1)
    win = np.arange(-2 * period, -period // 2)
    tight = 100.0
    for i in range(n):
        cand = i + win
        cand = cand[cand >= 0]
        if len(cand) == 0:
            continue
        pen = -tight * (np.log((i - cand) / period)) ** 2
        k = int(np.argmax(cum[cand] + pen))
        cum[i] = onset[i] + cum[cand[k]] + pen[k]
        back[i] = cand[k]
    i = int(np.argmax(cum[-period:])) + n - period
    beats = []
    while i >= 0:
        beats.append(i)
        i = back[i]
    return bpm, np.array(beats[::-1]) / fps


def main(song_dir):
    meta_path = os.path.join(song_dir, "metadata.json")
    meta = json.load(open(meta_path)) if os.path.exists(meta_path) else {}
    audio = os.path.join(song_dir, meta.get("file", "original.mp3"))
    y = decode(audio)
    dur = len(y) / SR
    f, t, S = spectrogram(y)
    fps = SR / HOP
    M = mel_bands(f, S)
    flux = np.maximum(np.diff(M, axis=1, prepend=M[:, :1]), 0).sum(0)
    onset = flux / (flux.max() + 1e-9)
    bpm, beats = beat_track(onset, fps)
    # downbeat phase: the beat-in-bar position with the strongest low-band onsets
    low = np.maximum(np.diff(M[:8], axis=1, prepend=M[:8, :1]), 0).sum(0)
    bi = np.clip((beats * fps).astype(int), 0, len(low) - 1)
    phase = int(np.argmax([low[bi[p::4]].mean() for p in range(4)]))
    downbeats = beats[phase::4]
    rms = np.sqrt(uniform_filter1d(y ** 2, size=HOP * 8)[::HOP])
    loud = 20 * np.log10(rms + 1e-6)
    # sections: checkerboard novelty on bar-synchronous features
    bars = downbeats
    feats = []
    for a, b in zip(bars[:-1], bars[1:]):
        ia, ib = int(a * fps), max(int(b * fps), int(a * fps) + 1)
        feats.append(np.concatenate([M[:, ia:ib].mean(1), [loud[ia:ib].mean() / 10]]))
    F = np.array(feats)
    F = (F - F.mean(0)) / (F.std(0) + 1e-9)
    SSM = F @ F.T / F.shape[1]
    k = 4
    kern = np.kron(np.array([[1, -1], [-1, 1]]), np.ones((k, k)))
    nov = np.zeros(len(F))
    for i in range(k, len(F) - k):
        nov[i] = (SSM[i - k:i + k, i - k:i + k] * kern).sum()
    nov = np.maximum(nov, 0)
    peaks, _ = find_peaks(nov, distance=6, height=np.percentile(nov, 70))
    bounds = [0] + sorted(set(int(p) for p in peaks)) + [len(F)]
    sections = []
    for a, b in zip(bounds[:-1], bounds[1:]):
        ta = float(bars[a])
        tb = float(bars[b]) if b < len(bars) else dur
        ia, ib = int(ta * fps), max(int(tb * fps), int(ta * fps) + 1)
        sections.append({"start": round(ta, 3), "end": round(tb, 3), "bars": b - a, "loudness_db": round(float(loud[ia:ib].mean()), 1)})
    # endings: section ends, and 8-bar phrase ends followed by a softer bar
    endings = set(round(s["end"], 3) for s in sections[:-1])
    bar_loud = [float(loud[int(a * fps):max(int(b * fps), int(a * fps) + 1)].mean()) for a, b in zip(bars[:-1], bars[1:])]
    for i in range(8, len(bar_loud) - 1, 8):
        if bar_loud[i] < bar_loud[i - 1] - 1.0:
            endings.add(round(float(bars[i]), 3))
    # vocal estimate: harmonic (median over time) energy in 250-3500 Hz minus percussive (median over freq)
    harm = median_filter(S, size=(1, 17))
    perc = median_filter(S, size=(17, 1))
    mask = harm > perc
    band = (f >= 250) & (f <= 3500)
    hv = (S * mask)[band].sum(0)
    total = S.sum(0) + 1e-9
    ratio = uniform_filter1d(hv / total, 9)
    level = uniform_filter1d(hv, 9)
    env = np.clip((level / (np.percentile(level, 95) + 1e-9)) * np.clip((ratio - np.percentile(ratio, 30)) / (np.percentile(ratio, 90) - np.percentile(ratio, 30) + 1e-9), 0, 1), 0, 1)
    rate = 25
    idx = (np.arange(int(dur * rate)) / rate * fps).astype(int).clip(0, len(env) - 1)
    venv = env[idx]
    on, segs, start = False, [], 0.0
    for i, v in enumerate(uniform_filter1d(venv, 10)):
        ti = i / rate
        if not on and v > 0.32:
            on, start = True, ti
        elif on and v < 0.18:
            on = False
            if ti - start > 0.8:
                segs.append([round(start, 2), round(ti, 2)])
    if on:
        segs.append([round(start, 2), round(dur, 2)])
    timing = {
        "_note": "Measured by tools/audio/analyze_song.py (numpy/scipy, offline). Beats/bars assume 4/4. 'vocal' is an ESTIMATE from a mixed track (voice-band harmonic energy), suitable for amplitude-style mouth movement only - not phonemes, not a separated stem.",
        "duration": round(dur, 3), "bpm": round(float(bpm), 2), "bar_length": round(4 * 60 / float(bpm), 4),
        "beats": [round(float(b), 3) for b in beats], "downbeats": [round(float(b), 3) for b in downbeats],
        "sections": sections, "endings": sorted(endings),
        "vocal": {"method": "estimated_mixed_track", "rate": rate, "envelope": [round(float(v), 2) for v in venv], "segments": segs},
    }
    json.dump(timing, open(os.path.join(song_dir, "timing.json"), "w"))
    print(f"{os.path.basename(song_dir)}: {dur:.1f}s, {bpm:.1f} BPM, {len(beats)} beats, {len(downbeats)} bars, "
          f"{len(sections)} sections, {len(endings)} endings, {len(segs)} vocal segments ({sum(b - a for a, b in segs):.0f}s)")


if __name__ == "__main__":
    for d in sys.argv[1:]:
        main(d)
