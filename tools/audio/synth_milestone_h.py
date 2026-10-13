#!/usr/bin/env python3
"""Original procedural audio for Milestone H (two mages, combat, transformations). No samples, no
third-party audio, no existing melodies: every motif below was written for Mika World. Deterministic.

  spell_umbral_*        Luna's Umbral Lance layers (activation, rune, gather_loop, charge, release, impact, dissipate)
  impact_light/heavy    combat impacts (sub thump + crack + magical ring)
  mage_hit              a mage struck (soft body thud + breath of air)
  monster_bolt/lunge/slam  creature attacks
  loot_pickup, level_up, fusion_eclipse
  transform_<mage>_full / _short   transformation cues; the reveal hit lands exactly on the flash time
                        in data/transformations.json (full 6.05 s, short 1.5 s)

Writes 44.1 kHz WAV, then OGG Vorbis (ffmpeg) into assets/audio/synth/. Re-run to regenerate.
"""
import json
import os
import subprocess
import numpy as np
from scipy.io import wavfile
from scipy.signal import butter, sosfilt

SR = 44100
ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
OUT = os.path.join(ROOT, "assets", "audio", "synth")
rng = np.random.default_rng(20261013)
TR = json.load(open(os.path.join(ROOT, "data", "transformations.json")))


def t(sec):
    return np.arange(int(SR * sec)) / SR


def note(n):  # semitones from A4
    return 440.0 * 2 ** (n / 12.0)


def env(n, a, d, s, r, sustain_level=0.7):
    a, d, r = int(a * SR), int(d * SR), int(r * SR)
    s = max(0, n - a - d - r)
    e = np.concatenate([np.linspace(0, 1, max(a, 1)), np.linspace(1, sustain_level, max(d, 1)),
                        np.full(s, sustain_level), np.linspace(sustain_level, 0, max(r, 1))])
    return np.pad(e, (0, max(0, n - len(e))))[:n]


def lp(x, hz, order=2):
    return sosfilt(butter(order, min(hz, SR * 0.45), "low", fs=SR, output="sos"), x)


def hp(x, hz, order=2):
    return sosfilt(butter(order, hz, "high", fs=SR, output="sos"), x)


def bp(x, lo, hi):
    return sosfilt(butter(2, [lo, hi], "band", fs=SR, output="sos"), x)


def saw(f, tt, partials=12):
    y = np.zeros_like(tt)
    for k in range(1, partials + 1):
        y += np.sin(2 * np.pi * f * k * tt) / k
    return y * 0.6


def bell(f, sec, decay=1.6, bright=1.0):
    tt = t(sec)
    y = np.zeros_like(tt)
    for ratio, amp in [(1, 1.0), (2.76, 0.45 * bright), (5.4, 0.25 * bright), (8.93, 0.12 * bright)]:
        y += amp * np.sin(2 * np.pi * f * ratio * tt) * np.exp(-tt * decay * ratio ** 0.5)
    return y * np.minimum(1, tt * 400)


def pluck(f, sec, decay=3.0):
    tt = t(sec)
    return lp(saw(f, tt, 8) * np.exp(-tt * decay), 2400 + f * 2)


def pad(freqs, sec, cutoff=1800, attack=0.6, release=1.2, detune=0.004):
    tt = t(sec)
    y = np.zeros_like(tt)
    for f in freqs:
        for d in (-detune, 0.0, detune):
            y += saw(f * (1 + d), tt, 8)
    y = lp(y / (3 * len(freqs)), cutoff)
    return y * env(len(tt), attack, 0.3, 0, release, 0.85)


def noise(sec):
    return rng.standard_normal(int(SR * sec))


def reverb(x, mix=0.3, size=1.0):
    y = np.copy(x)
    for delay, g in [(0.0297, 0.62), (0.0371, 0.6), (0.0411, 0.58), (0.0437, 0.56)]:
        d = int(delay * size * SR)
        buf = np.zeros(len(x) + d * 40)
        buf[:len(x)] += x
        for i in range(1, 40):
            buf[i * d:i * d + len(x)] += x * (g ** i)
        y = y + lp(buf[:len(x)], 5000) * (mix / 4)
    return y


def place(dst, src, at, gain=1.0):
    i = int(at * SR)
    n = min(len(src), len(dst) - i)
    if n > 0:
        dst[i:i + n] += src[:n] * gain


def save(name, y, peak=0.85):
    os.makedirs(OUT, exist_ok=True)
    y = np.asarray(y, dtype=np.float64)
    m = np.max(np.abs(y)) or 1.0
    y = y / m * peak
    fade = min(len(y), int(0.01 * SR))
    y[-fade:] *= np.linspace(1, 0, fade)
    wav = os.path.join(OUT, name + ".wav")
    wavfile.write(wav, SR, (y * 32767).astype(np.int16))
    ogg = os.path.join(OUT, name + ".ogg")
    subprocess.run(["ffmpeg", "-y", "-loglevel", "error", "-i", wav, "-c:a", "libvorbis", "-q:a", "5", ogg], check=True)
    os.remove(wav)
    print("wrote", os.path.relpath(ogg, ROOT), f"{len(y) / SR:.2f}s")


# ------------------------------------------------------------------ Umbral Lance (dark, glassy, gold edge)
def umbral():
    # activation: low glass bloom with a dark undertone
    y = bell(note(-17), 1.4, 2.2, 0.7) * 0.6 + lp(saw(note(-29), t(1.4), 6), 300) * env(int(1.4 * SR), 0.05, 0.4, 0, 0.9, 0.3) * 0.5
    save("spell_umbral_activation", reverb(y, 0.35))
    # rune: minor-second cluster swelling (C, Db, G) with shimmer
    tt = t(1.6)
    y = sum(np.sin(2 * np.pi * note(n) * tt) for n in (-9, -8, -2)) * env(len(tt), 0.5, 0.4, 0, 0.6, 0.6) * 0.4
    y += hp(noise(1.6), 6000) * env(len(tt), 0.6, 0.3, 0, 0.6, 0.2) * 0.08
    save("spell_umbral_rune", reverb(y, 0.4))
    # gather loop: breathing low drone (seamless 3 s)
    tt = t(3.0)
    y = (np.sin(2 * np.pi * note(-33) * tt) + 0.5 * np.sin(2 * np.pi * note(-26) * tt) + 0.25 * np.sin(2 * np.pi * note(-21) * tt))
    y *= 0.75 + 0.25 * np.sin(2 * np.pi * tt / 3.0)
    y += lp(noise(3.0), 600) * 0.15
    save("spell_umbral_gather_loop", y, 0.6)
    # charge: tightening crystal (rising sweep)
    tt = t(0.9)
    f = np.linspace(note(-5), note(7), len(tt))
    y = np.sin(2 * np.pi * np.cumsum(f) / SR) * env(len(tt), 0.4, 0.2, 0, 0.3, 0.8) * 0.5
    y += bell(note(3), 0.9, 3.0) * 0.4
    save("spell_umbral_charge", reverb(y, 0.25))
    # release: fast air tear + glass zing
    tt = t(0.7)
    y = bp(noise(0.7), 900, 5000) * np.exp(-tt * 7) * 0.9
    f = np.linspace(note(15), note(3), len(tt))
    y += np.sin(2 * np.pi * np.cumsum(f) / SR) * np.exp(-tt * 9) * 0.5
    save("spell_umbral_release", y)
    # impact: cracking glass + gold ring
    tt = t(1.2)
    y = hp(noise(1.2), 2500) * np.exp(-tt * 18) * 0.8
    y += bell(note(10), 1.2, 2.5) * 0.5 + bell(note(5), 1.2, 3.0) * 0.4
    y += np.sin(2 * np.pi * 70 * tt) * np.exp(-tt * 10) * 0.7
    save("spell_umbral_impact", reverb(y, 0.3))
    # dissipate: falling dark shimmer
    tt = t(1.4)
    f = np.linspace(note(12), note(-2), len(tt))
    y = np.sin(2 * np.pi * np.cumsum(f) / SR) * np.exp(-tt * 2.5) * 0.25 + hp(noise(1.4), 7000) * np.exp(-tt * 3) * 0.05
    save("spell_umbral_dissipate", reverb(y, 0.45))


# ------------------------------------------------------------------ combat
def combat():
    for name, sec, sub, crack, ring in [("impact_light", 0.9, 0.7, 0.5, 0.35), ("impact_heavy", 1.6, 1.0, 0.8, 0.5)]:
        tt = t(sec)
        f = np.linspace(140, 38, len(tt))
        y = np.sin(2 * np.pi * np.cumsum(f) / SR) * np.exp(-tt * (6 if name == "impact_light" else 3.5)) * sub
        y += bp(noise(sec), 1500, 9000) * np.exp(-tt * 30) * crack
        y += (bell(note(7), sec, 3.5) + bell(note(14), sec, 4.0) * 0.6) * ring
        save(name, reverb(y, 0.22))
    tt = t(0.6)
    y = lp(noise(0.6), 220) * np.exp(-tt * 14) * 1.2 + bp(noise(0.6), 400, 1600) * np.exp(-tt * 9) * 0.3
    save("mage_hit", y, 0.7)
    # gloomwisp bolt: icy chirp
    tt = t(0.6)
    f = np.linspace(note(24), note(31), len(tt))
    y = np.sin(2 * np.pi * np.cumsum(f) / SR) * np.exp(-tt * 6) * 0.5 + hp(noise(0.6), 5000) * np.exp(-tt * 8) * 0.25
    save("monster_bolt", reverb(y, 0.3))
    # thornback lunge: rasping chitter + snap
    tt = t(0.7)
    chit = bp(noise(0.7), 1200, 3200) * (0.5 + 0.5 * np.sign(np.sin(2 * np.pi * 34 * tt))) * np.exp(-tt * 5)
    y = chit * 0.6 + lp(noise(0.7), 300) * np.exp(-tt * 9) * 0.8
    y += bp(noise(0.7), 2000, 8000) * (np.abs(tt - 0.32) < 0.012) * 1.2
    save("monster_lunge", y)
    # sentinel slam: stone boom + rubble
    tt = t(2.0)
    f = np.linspace(90, 28, len(tt))
    y = np.sin(2 * np.pi * np.cumsum(f) / SR) * np.exp(-tt * 2.2) * 1.0 + lp(noise(2.0), 900) * np.exp(-tt * 3) * 0.5
    save("monster_slam", reverb(y, 0.3, 1.4))


def cues():
    # loot: three-note glass rise
    y = np.zeros(int(1.4 * SR))
    for i, n in enumerate((14, 19, 26)):
        place(y, bell(note(n), 1.0, 3.0), i * 0.07, 0.6)
    save("loot_pickup", reverb(y, 0.35))
    # level up: original ascending figure (D lydian colour) + soft pad
    y = np.zeros(int(3.0 * SR))
    for i, n in enumerate((5, 9, 12, 16, 19, 23, 24)):
        place(y, pluck(note(n), 1.6, 2.5), i * 0.09, 0.5)
    place(y, pad([note(5), note(9), note(12), note(16)], 2.6, 2600, 0.2, 1.4), 0.55, 0.5)
    place(y, bell(note(28), 2.0, 1.4), 0.65, 0.4)
    save("level_up", reverb(y, 0.4))
    # fusion: two colours converging into one hit
    y = np.zeros(int(3.5 * SR))
    tt = t(1.2)
    up = np.sin(2 * np.pi * np.cumsum(np.linspace(note(-12), note(0), len(tt))) / SR)
    dn = np.sin(2 * np.pi * np.cumsum(np.linspace(note(12), note(0), len(tt))) / SR)
    place(y, (up + dn) * np.linspace(0, 1, len(tt)) ** 2 * 0.4, 0.0)
    hit_t = 1.2
    tt2 = t(2.3)
    place(y, np.sin(2 * np.pi * np.cumsum(np.linspace(110, 30, len(tt2))) / SR) * np.exp(-tt2 * 2.5), hit_t, 1.0)
    for n in (0, 3, 7, 11, 14):
        place(y, bell(note(n), 2.2, 1.2), hit_t, 0.25)
    place(y, hp(noise(2.0), 4000) * np.exp(-t(2.0) * 2.5) * 0.25, hit_t)
    save("fusion_eclipse", reverb(y, 0.4, 1.3))


# ------------------------------------------------------------------ transformations
def transform(mage, version):
    v = TR["versions"][version]
    L, H = float(v["length"]), float(v["swap"])
    y = np.zeros(int(L * SR))
    if mage == "mika":
        root = -7          # D
        scale = [0, 2, 4, 6, 7, 9, 11]                # lydian: bright, floating
        chord = [0, 4, 7, 11, 14, 18]                 # maj9 #11
        motif = [7, 9, 11, 14, 16, 14, 11, 9, 7, 11, 14, 19]
        bright, colour = 1.0, 3200
    else:
        root = -9          # C
        scale = [0, 1, 3, 5, 7, 8, 10]                # phrygian: dark, proud
        chord = [0, 3, 7, 10, 14, 19]                 # m9 (add 11) with a gold top
        motif = [7, 8, 10, 12, 15, 13, 12, 10, 8, 7, 12, 19]
        bright, colour = 0.7, 2200
    # buildup: pad opening + quickening arpeggio + riser + low pulse
    tt = t(H)
    k = tt / H
    p = pad([note(root - 12), note(root - 5), note(root)], H, 400, 0.4 * H, 0.1)
    p = sosfilt(butter(2, 400, "low", fs=SR, output="sos"), p) * (0.3 + 0.7 * k) + lp(p, colour) * k
    place(y, p, 0.0, 0.5)
    tpos, i = 0.25, 0
    while tpos < H - 0.05:
        n = root + scale[i % len(scale)] + 12 * (i // len(scale) % 3)
        place(y, pluck(note(n), 0.6, 5.0), tpos, 0.22 + 0.25 * tpos / H)
        tpos += max(0.06, 0.32 * (1 - tpos / H) ** 1.3)
        i += 1
    riser = hp(noise(H), 2500) * (k ** 3) * 0.35
    place(y, riser, 0.0)
    beat, bt = 0.0, 0.8
    while beat < H - 0.1:
        tb = t(0.3)
        place(y, np.sin(2 * np.pi * np.cumsum(np.linspace(90, 40, len(tb))) / SR) * np.exp(-tb * 14), beat, 0.55)
        beat += bt
        bt = max(0.18, bt * 0.85)
    # reveal hit: boom + full chord + bells + air
    tail = L - H
    th = t(min(2.6, tail))
    place(y, np.sin(2 * np.pi * np.cumsum(np.linspace(120, 32, len(th))) / SR) * np.exp(-th * 1.8), H, 1.0)
    place(y, pad([note(root + c) for c in chord], tail, colour * 1.4, 0.02, min(2.5, tail * 0.5)), H, 0.7)
    for j, c in enumerate(chord):
        place(y, bell(note(root + 12 + c), min(3.0, tail), 1.0, bright), H + 0.02 * j, 0.22)
    place(y, hp(noise(min(2.5, tail)), 3500) * np.exp(-t(min(2.5, tail)) * 1.8) * 0.3, H)
    # after the reveal: the mage's own motif over the held chord, then a settling cadence
    step = 0.32 if version == "full" else 0.2
    notes = motif if version == "full" else motif[:6]
    for j, n in enumerate(notes):
        at = H + 0.55 + j * step
        if at < L - 0.6:
            place(y, bell(note(root + 12 + n), 1.6, 1.8, bright), at, 0.3)
            place(y, pluck(note(root + n), 0.9, 3.0), at, 0.18)
    if version == "full":
        end = L - 3.0
        place(y, pad([note(root - 12), note(root + chord[1]), note(root + chord[2]), note(root + 12)], 3.0, colour, 0.3, 2.0), end, 0.55)
        place(y, bell(note(root + 24), 2.8, 1.0, bright), end + 0.2, 0.35)
    save("transform_%s_%s" % (mage, version), reverb(y, 0.35, 1.2), 0.9)


if __name__ == "__main__":
    umbral()
    combat()
    cues()
    for m in ("mika", "luna"):
        for v in ("full", "short"):
            transform(m, v)
