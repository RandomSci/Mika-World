#!/usr/bin/env python3
"""V3 Part XIII - sound for the two spell families (original audio, no samples, no bells).

Mika's growing magic gets its own element layer set, `spell_nature_*` (rustling leaves, creaking wood, earth:
the same seven phases every element has, so AudioDirector plays it like the others), and the techniques that
are not projectiles get their own one-shots:
  ward_leaf_up / ward_leaf_absorb              a ring of leaves whirling up; a bolt smothered in leaves
  ward_mirror_up / ward_mirror_absorb /        a pane of glass drawn up; a bolt stopped on glass; a bolt
  ward_mirror_reflect                          thrown back (a rising sweep)
  roots_seam / roots_erupt / roots_wither      the seam racing along the ground; roots cracking up; dry leaves
  rift_open / rift_erupt                       the rift's dark hum and crack; crystal spikes bursting up
Everything is built from filtered noise, sub thumps, crackle and short resonances kept under ~1.2 kHz for the
tonal parts (nothing rings like a bell: docs/FUTURE_POLISH.md #1).
Run:  python3 tools/audio/synth_v3_magic.py      (deterministic)
"""
import os
import subprocess

import numpy as np
from scipy.io import wavfile
from scipy.signal import butter, sosfilt

SR = 44100
ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
OUT = os.path.join(ROOT, "assets", "audio", "synth")
rng = np.random.default_rng(20261014)


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
    n = int(SR * sec)
    w = rng.standard_normal(n)
    if kind == "white":
        return w
    f = np.fft.rfftfreq(n, 1 / SR)
    f[0] = 1
    spec = np.fft.rfft(w) / (np.sqrt(f) if kind == "pink" else f)
    y = np.fft.irfft(spec, n)
    return y / (np.max(np.abs(y)) or 1)


def sweep_bp(sec, f0, f1, width=0.6, kind="pink", steps=48):
    x = noise(sec, kind)
    n = len(x)
    out = np.zeros(n)
    seg = n // steps + 1
    for i in range(steps):
        a, b = i * seg, min(n, (i + 1) * seg + 256)
        fc = f0 * (f1 / f0) ** (i / (steps - 1))
        y = bp(x[max(0, a - 2048):b], fc * (1 - width / 2), fc * (1 + width / 2))
        y = y[(a - max(0, a - 2048)):]
        out[a:b] += y[: b - a]
    return out


def sub(sec, f0, f1, decay):
    tt = t(sec)
    f = np.linspace(f0, f1, len(tt))
    return np.sin(2 * np.pi * np.cumsum(f) / SR) * np.exp(-tt * decay)


def crackle(sec, rate, lo=700, hi=4500):
    n = int(SR * sec)
    y = np.zeros(n)
    for _ in range(int(sec * rate)):
        i = rng.integers(0, max(1, n - 2000))
        L = int(rng.integers(60, 400))
        y[i: i + L] += rng.standard_normal(L) * np.exp(-np.arange(L) / (L / 4)) * rng.uniform(0.3, 1.0)
    return lp(bp(y, lo, hi), 3500)


def rustle(sec, density=90.0, lo=1200, hi=6500):
    """Leaves: many tiny overlapping noise grains, each shaped like a leaf brushing another."""
    n = int(SR * sec)
    y = np.zeros(n)
    for _ in range(int(sec * density)):
        i = rng.integers(0, max(1, n - 1500))
        L = int(rng.integers(150, 1400))
        env = np.sin(np.linspace(0, np.pi, L)) ** 2
        y[i: i + L] += rng.standard_normal(L) * env * rng.uniform(0.2, 1.0)
    return bp(y, lo, hi)


def creak(sec, f0=160.0, f1=90.0, wob=5.0):
    """Wood under strain: a low resonant band whose centre slides and wobbles."""
    n = int(SR * sec)
    tt = t(sec)
    x = noise(sec, "pink")
    out = np.zeros(n)
    steps = 40
    seg = n // steps + 1
    for i in range(steps):
        a, b = i * seg, min(n, (i + 1) * seg + 256)
        k = i / (steps - 1)
        fc = (f0 + (f1 - f0) * k) * (1 + 0.08 * np.sin(2 * np.pi * wob * k * sec))
        y = bp(x[max(0, a - 2048):b], fc * 0.8, fc * 1.25, 3)
        y = y[(a - max(0, a - 2048)):]
        out[a:b] += y[: b - a]
    return out * (0.7 + 0.3 * np.sin(2 * np.pi * 11.0 * tt))


def swell(n, attack, release):
    tt = np.arange(n) / SR
    total = n / SR
    return np.clip(tt / max(attack, 1e-3), 0, 1) * np.clip((total - tt) / max(release, 1e-3), 0, 1)


def reverb(x, tail=1.0, wet=0.3):
    n = int(SR * tail)
    ir = noise(tail, "pink") * np.exp(-np.arange(n) / SR * (5.0 / tail))
    ir = lp(ir, 5000)
    y = np.convolve(x, ir)[: len(x) + n // 2] * 0.05
    dry = np.concatenate([x, np.zeros(len(y) - len(x))])
    return dry * (1 - wet) + y * wet / (np.max(np.abs(y)) or 1) * (np.max(np.abs(dry)) or 1)


def fade(y, fin=0.004, fout=0.06):
    y = y.copy()
    a, b = int(SR * fin), int(SR * fout)
    if a:
        y[:a] *= np.linspace(0, 1, a)
    if b:
        y[-b:] *= np.linspace(1, 0, b)
    return y


def save(name, y, peak=0.8):
    os.makedirs(OUT, exist_ok=True)
    ogg = os.path.join(OUT, name + ".ogg")
    y = np.asarray(y, dtype=np.float64)
    y = fade(y / (np.max(np.abs(y)) or 1.0) * peak)
    wav = os.path.join(OUT, name + ".tmp.wav")
    wavfile.write(wav, SR, (y * 32767).astype(np.int16))
    subprocess.run(["ffmpeg", "-y", "-loglevel", "error", "-i", wav, "-c:a", "libvorbis", "-q:a", "5", ogg], check=True)
    os.remove(wav)
    print("wrote", os.path.relpath(ogg, ROOT), f"{len(y) / SR:.2f}s")


def glass(sec, f=900.0, decay=14.0):
    """A pane of dark glass touched: a short, damped high resonance of NOISE (a tap, not a chime)."""
    tt = t(sec)
    x = bp(noise(sec, "white"), f * 0.85, f * 1.15, 4) * np.exp(-tt * decay)
    return x + lp(noise(sec, "pink"), 250) * np.exp(-tt * 25) * 0.8


# ------------------------------------------------------------------ Mika: the nature element set
def nature_layers():
    lo, hi = 1000, 5200
    # activation: a breath through leaves and a low stir of earth
    sec = 0.9
    y = rustle(sec, 70) * swell(int(SR * sec), 0.3, 0.4) * 0.8 + sub(sec, 80, 60, 3.0) * swell(int(SR * sec), 0.3, 0.5) * 0.4
    y += creak(sec, 150, 110) * swell(int(SR * sec), 0.4, 0.3) * 0.5
    save("spell_nature_activation", reverb(y, 0.8, 0.25), 0.45)
    # rune: the wreath of leaves unfolding - a slow rustle rising, soil grit
    sec = 2.0
    tt = t(sec)
    y = rustle(sec, 60) * (0.4 + 0.6 * np.sin(2 * np.pi * 0.5 * tt) ** 2) * 0.7
    y += bp(crackle(sec, 25, 200, 2200), 150, 1600) * 0.35 + creak(sec, 120, 95, 2.0) * 0.4
    y *= swell(len(y), 0.5, 0.6)
    save("spell_nature_rune", reverb(y, 1.2, 0.3), 0.4)
    # charge: sap rising - a low creak climbing with leaves gathering
    sec = 1.1
    y = creak(sec, 90, 180, 6.0) * np.linspace(0.2, 1.0, int(SR * sec)) ** 2 * 0.9
    y += rustle(sec, 110) * np.linspace(0.0, 1.0, int(SR * sec)) * 0.6
    save("spell_nature_charge", reverb(y, 0.6, 0.2), 0.55)
    # gather loop: a low wooden hum and the constant whisper of leaves (seamless)
    sec = 5.0
    tt = t(sec)
    g = lp(noise(sec, "pink"), 260, 4) * (0.7 + 0.3 * np.sin(2 * np.pi * 0.45 * tt)) * 0.7
    g += rustle(sec, 45, 900, 4200) * (0.6 + 0.4 * np.sin(2 * np.pi * 0.3 * tt)) * 0.5
    g += creak(sec, 120, 120, 1.5) * 0.25
    n_x = int(SR * 1.0)
    head, tail = g[:n_x].copy(), g[-n_x:].copy()
    w = np.linspace(0, 1, n_x)
    g = g[:-n_x]
    g[:n_x] = tail * (1 - w) + head * w
    save("spell_nature_gather_loop", g, 0.4)
    # release: the seam leaving - a quick whoosh through leaves with a soil hiss
    sec = 0.8
    tt = t(sec)
    y = sweep_bp(sec, hi, lo * 0.5, 0.8) * np.exp(-((tt - 0.16) ** 2) / 0.012) + rustle(sec, 120) * np.exp(-tt * 5) * 0.7
    save("spell_nature_release", reverb(y, 0.6, 0.2), 0.7)
    # impact: roots taking hold - an earth thump, cracking wood, leaves settling
    sec = 1.3
    tt = t(sec)
    y = sub(sec, 95, 50, 6.0) * 0.9 + bp(crackle(sec, 50, 150, 2500), 120, 2200) * np.exp(-tt * 3) * 0.8
    y += creak(sec, 170, 80, 4.0) * np.exp(-tt * 2.5) * 0.7 + rustle(sec, 80) * np.exp(-tt * 2) * 0.5
    save("spell_nature_impact", reverb(y, 1.0, 0.25), 0.8)
    # dissipate: leaves drifting down
    sec = 1.6
    tt = t(sec)
    y = rustle(sec, 40, 800, 3600) * np.exp(-tt * 2.0) * 0.7 + lp(noise(sec, "pink"), 300) * np.exp(-tt * 2.5) * 0.3
    save("spell_nature_dissipate", reverb(y, 1.0, 0.3), 0.3)


# ------------------------------------------------------------------ wards, roots, rifts
def oneshots():
    # Leaf Ward: leaves whirl up round her (a rising rustle with air), then a bolt smothered in leaves
    sec = 0.9
    tt = t(sec)
    y = rustle(sec, 140) * swell(len(tt), 0.08, 0.5) + sweep_bp(sec, 900, 3800, 0.8) * np.exp(-((tt - 0.2) ** 2) / 0.03) * 0.6
    save("ward_leaf_up", reverb(y, 0.7, 0.25), 0.6)
    sec = 0.7
    tt = t(sec)
    y = rustle(sec, 220, 1000, 7000) * np.exp(-tt * 6) + lp(noise(sec, "brown"), 220) * np.exp(-tt * 18) * 0.9
    save("ward_leaf_absorb", reverb(y, 0.6, 0.2), 0.7)
    # Gilded Mirror: a pane drawn up (a dark hum with a glass edge), a bolt stopped on glass, a bolt thrown back
    sec = 0.8
    tt = t(sec)
    y = lp(noise(sec, "pink"), 180, 4) * swell(len(tt), 0.05, 0.4) * 0.8 + glass(sec, 1100, 9) * 0.5 + sweep_bp(sec, 400, 1600, 0.5) * swell(len(tt), 0.1, 0.5) * 0.3
    save("ward_mirror_up", reverb(y, 0.9, 0.3), 0.55)
    sec = 0.7
    y = glass(sec, 950, 16) * 1.0 + sub(sec, 110, 60, 12.0) * 0.5 + bp(crackle(sec, 60, 1500, 6000), 1200, 6000) * np.exp(-t(sec) * 9) * 0.5
    save("ward_mirror_absorb", reverb(y, 0.8, 0.25), 0.75)
    sec = 0.8
    tt = t(sec)
    y = glass(sec, 1000, 14) * 0.6 + sweep_bp(sec, 500, 3200, 0.7) * np.exp(-((tt - 0.3) ** 2) / 0.02) * 0.9
    save("ward_mirror_reflect", reverb(y, 0.8, 0.25), 0.75)
    # roots: the seam racing (a low rumble sliding with grit), the eruption, the withering
    sec = 0.6
    tt = t(sec)
    y = lp(noise(sec, "brown"), 160) * swell(len(tt), 0.05, 0.1) * 0.8 + bp(crackle(sec, 80, 200, 1800), 200, 1500) * 0.4 + rustle(sec, 60) * 0.3
    save("roots_seam", reverb(y, 0.5, 0.2), 0.5)
    sec = 1.4
    tt = t(sec)
    y = sub(sec, 110, 45, 5.0) * 1.0 + bp(crackle(sec, 90, 150, 3000), 120, 2600) * np.exp(-tt * 2.5) * 0.9
    y += creak(sec, 220, 70, 5.0) * np.exp(-tt * 2.0) * 0.8 + rustle(sec, 100) * np.exp(-tt * 2.2) * 0.5
    save("roots_erupt", reverb(y, 1.1, 0.3), 0.85)
    sec = 1.2
    tt = t(sec)
    y = rustle(sec, 90, 700, 3200) * np.exp(-tt * 2.2) * 0.8 + creak(sec, 80, 60, 1.0) * np.exp(-tt * 3) * 0.4
    save("roots_wither", reverb(y, 0.9, 0.3), 0.45)
    # rift: a dark hum opening with a crack; the spikes bursting up (crystal grind + sub boom)
    sec = 0.7
    tt = t(sec)
    y = lp(noise(sec, "brown"), 120) * swell(len(tt), 0.03, 0.3) * 0.9 + bp(crackle(sec, 70, 300, 4000), 250, 3500) * np.exp(-tt * 6) * 0.6
    y += sweep_bp(sec, 1800, 300, 0.6) * np.exp(-tt * 5) * 0.4
    save("rift_open", reverb(y, 1.0, 0.3), 0.6)
    sec = 1.3
    tt = t(sec)
    y = sub(sec, 90, 40, 5.0) * 1.0 + glass(sec, 1300, 7) * 0.5 + bp(crackle(sec, 120, 600, 7000), 500, 6500) * np.exp(-tt * 3.5) * 0.7
    y += sweep_bp(sec, 300, 2400, 0.7) * np.exp(-((tt - 0.08) ** 2) / 0.01) * 0.8
    save("rift_erupt", reverb(y, 1.2, 0.3), 0.85)


if __name__ == "__main__":
    nature_layers()
    oneshots()
