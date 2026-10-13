#!/usr/bin/env python3
"""Milestone J: remove the recurring bell / chime timbre from ordinary gameplay (original audio, no samples).

The developer reported a repetitive bell during magic and levelling (docs/FUTURE_POLISH.md #1). Every
ordinary-gameplay layer that used struck-bell partials (or bell-like decaying sine "plinks") is rebuilt here
from NON-TONAL elemental material - air, breath, filtered noise, sub thumps, crackle, water, grit - so a spell
sounds like its element instead of ringing a bell each time. Rare musical moments keep their music (the
transformation cues are untouched; they are composed scores, not notifications).

Rebuilt (same file names, so nothing else changes):
  spell_<el>_activation / _rune / _charge / _release / _impact / _dissipate   for arcane rune self wind water fire mist
  spell_umbral_activation / _charge / _impact / _dissipate                       Luna's Umbral Lance
  impact_light / impact_heavy                                                    combat hits (the "magical ring" removed)
  loot_pickup, trial_complete, rank_up, discovery, level_up, fusion_eclipse, alchemy_glow
Kept: gather loops (drones, no bell), ambience, creature sounds, crystal_shatter (a physical shatter),
transformation music.

Originals are backed up once to .backups/audio_pre_milestone_j/ before anything is overwritten.
Run:  python3 tools/audio/synth_milestone_j.py      (deterministic)
"""
import os
import shutil
import subprocess

import numpy as np
from scipy.io import wavfile
from scipy.signal import butter, sosfilt

SR = 44100
ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
OUT = os.path.join(ROOT, "assets", "audio", "synth")
BACKUP = os.path.join(ROOT, ".backups", "audio_pre_milestone_j")
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
    """Band-passed noise whose centre glides f0 -> f1 (an air movement, not a pitch)."""
    x = noise(sec, kind)
    n = len(x)
    out = np.zeros(n)
    seg = n // steps + 1
    for i in range(steps):
        a, b = i * seg, min(n, (i + 1) * seg + 256)
        fc = f0 * (f1 / f0) ** (i / (steps - 1))
        y = bp(x[max(0, a - 2048):b], fc * (1 - width / 2), fc * (1 + width / 2))
        y = y[(a - max(0, a - 2048)):]
        w = np.ones(b - a)
        out[a:b] += y[: b - a] * w
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


def bubbles(sec, rate, lo=300, hi=900):
    """Low, short water bubbles (kept below ~1 kHz so they never read as chimes)."""
    n = int(SR * sec)
    y = np.zeros(n)
    for _ in range(int(sec * rate)):
        i = rng.integers(0, max(1, n - 6000))
        f = rng.uniform(lo, hi)
        L = int(SR * rng.uniform(0.02, 0.05))
        tt = np.arange(L) / SR
        y[i: i + L] += np.sin(2 * np.pi * f * (1 + tt * 10) * tt) * np.exp(-tt * 90) * rng.uniform(0.3, 1)
    return y


def grit(sec, rate):
    """Stone / glyph grind: dense tiny clicks through a low band."""
    return bp(crackle(sec, rate, 200, 2500), 150, 1800)


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
    os.makedirs(BACKUP, exist_ok=True)
    ogg = os.path.join(OUT, name + ".ogg")
    if os.path.exists(ogg) and not os.path.exists(os.path.join(BACKUP, name + ".ogg")):
        shutil.copy2(ogg, BACKUP)
    y = np.asarray(y, dtype=np.float64)
    y = fade(y / (np.max(np.abs(y)) or 1.0) * peak)
    wav = os.path.join(OUT, name + ".tmp.wav")
    wavfile.write(wav, SR, (y * 32767).astype(np.int16))
    subprocess.run(["ffmpeg", "-y", "-loglevel", "error", "-i", wav, "-c:a", "libvorbis", "-q:a", "5", ogg], check=True)
    os.remove(wav)
    print("wrote", os.path.relpath(ogg, ROOT), f"{len(y) / SR:.2f}s")


# ------------------------------------------------------------------ element colours (bands, not pitches)
EL = {
    # band: where the element's "air" lives; body: low thump frequency; tex: texture generator
    "arcane": {"band": (600, 3200), "body": 70},
    "rune":   {"band": (250, 1800), "body": 55},
    "self":   {"band": (500, 2600), "body": 60},
    "wind":   {"band": (900, 5000), "body": 0},
    "water":  {"band": (300, 2200), "body": 90},
    "fire":   {"band": (200, 1600), "body": 50},
    "mist":   {"band": (1500, 7000), "body": 0},
}


def texture(el, sec, amount=1.0):
    if el == "fire":
        return crackle(sec, 40) * amount
    if el == "water":
        return bubbles(sec, 26) * amount
    if el == "rune":
        return grit(sec, 70) * amount
    if el == "arcane":
        # a soft electrical "fizz": noise bursts gated at a fast random rate
        g = (rng.random(int(SR * sec)) < 0.004).astype(float)
        return bp(lp(g, 60) * noise(sec, "white"), 1500, 5000) * 3.0 * amount
    if el == "mist":
        return hp(noise(sec, "pink"), 4000) * 0.5 * amount
    return np.zeros(int(SR * sec))


def spell_layers(el):
    p = EL[el]
    lo, hi = p["band"]
    # activation: the mage draws in the element (a short breath of its air, a low thrum underneath)
    sec = 0.9
    y = sweep_bp(sec, lo, hi * 0.8, 0.9) * swell(int(SR * sec), 0.35, 0.4) * 0.8
    if p["body"]:
        y += sub(sec, p["body"] * 1.2, p["body"], 3.0) * swell(int(SR * sec), 0.3, 0.5) * 0.5
    y += texture(el, sec, 0.35) * swell(int(SR * sec), 0.3, 0.3)
    save(f"spell_{el}_activation", reverb(y, 0.8, 0.25), 0.45)
    # rune formation: the sigil drawing itself - a low formant hum and grit, no high partials
    sec = 2.0
    tt = t(sec)
    hum = lp(noise(sec, "pink"), 400) * (0.6 + 0.4 * np.sin(2 * np.pi * 3.0 * tt)) * 0.6
    y = hum + bp(noise(sec, "pink"), lo, hi) * 0.25 * (0.5 + 0.5 * np.sin(2 * np.pi * 0.7 * tt))
    y += grit(sec, 30) * 0.4 + texture(el, sec, 0.25)
    y *= swell(len(y), 0.5, 0.6)
    save(f"spell_{el}_rune", reverb(y, 1.2, 0.3), 0.4)
    # charge: pressure building (a rising band of air over a growing sub)
    sec = 1.1
    y = sweep_bp(sec, lo * 0.7, hi * 1.2, 0.7) * np.linspace(0.2, 1.0, int(SR * sec)) ** 2
    if p["body"]:
        y += sub(sec, p["body"] * 0.8, p["body"] * 1.4, 0.5) * np.linspace(0.1, 1.0, int(SR * sec)) * 0.6
    y += texture(el, sec, 0.4) * np.linspace(0, 1, int(SR * sec))
    save(f"spell_{el}_charge", reverb(y, 0.6, 0.2), 0.55)
    # gather loop (5 s, seamless): a LOW hum (< 400 Hz) and the element's air - nothing that rings
    sec = 5.0
    tt = t(sec)
    base = {"arcane": 110.0, "rune": 98.0, "self": 98.0, "wind": 0.0, "water": 87.3, "fire": 73.4, "mist": 0.0}[el]
    g = np.zeros_like(tt)
    if base:
        g += (0.55 * np.sin(2 * np.pi * base * tt) + 0.25 * np.sin(2 * np.pi * base * 2 * tt)) * (0.8 + 0.2 * np.sin(2 * np.pi * 0.4 * tt))
        g = lp(g, 380, 4)
    g += bp(noise(sec, "pink"), lo, hi) * (0.3 if el in ("wind", "mist") else 0.16) * (0.75 + 0.25 * np.sin(2 * np.pi * 0.6 * tt))
    g += texture(el, sec, 0.15)
    n_x = int(SR * 1.0)
    head, tail = g[:n_x].copy(), g[-n_x:].copy()
    w = np.linspace(0, 1, n_x)
    g = g[:-n_x]
    g[:n_x] = tail * (1 - w) + head * w
    save(f"spell_{el}_gather_loop", g, 0.4)
    # release: a clean whoosh in the element's band (no tonal tail)
    sec = 0.8
    tt = t(sec)
    y = sweep_bp(sec, hi * 1.1 if el != "fire" else hi, lo * 0.6, 0.8) * np.exp(-((tt - 0.18) ** 2) / 0.015)
    if el == "fire":
        y += lp(noise(sec, "brown"), 300) * np.exp(-tt * 6) * 0.8
    save(f"spell_{el}_release", reverb(y, 0.6, 0.2), 0.7)
    # impact
    save(f"spell_{el}_impact", reverb(impact(el), 1.0, 0.25), 0.8)
    # dissipate: the element's air settling (falling band, soft texture) - no sine plinks
    sec = 1.6
    tt = t(sec)
    y = sweep_bp(sec, hi, lo * 0.5, 0.9) * np.exp(-tt * 2.2) * 0.6 + texture(el, sec, 0.3) * np.exp(-tt * 2.5)
    save(f"spell_{el}_dissipate", reverb(y, 1.0, 0.3), 0.3)


def impact(el):
    sec = 1.2
    tt = t(sec)
    if el in ("arcane", "rune", "self"):
        y = sub(sec, 120, 45, 9) * 1.0                                         # body thump
        y += bp(noise(sec, "white"), 1200, 7000) * np.exp(-tt * 28) * 0.6       # crack of released energy
        y += sweep_bp(sec, 3000, 400, 0.8) * np.exp(-tt * 5) * 0.5              # air pushed outward
        y += texture(el, sec, 0.6) * np.exp(-tt * 4)
    elif el == "wind":
        y = sweep_bp(sec, 2500, 300, 1.0) * np.exp(-tt * 3) * 1.2
        y += lp(noise(sec, "pink"), 300) * np.exp(-tt * 6) * 0.6
    elif el == "water":
        y = bp(noise(sec, "white"), 400, 3000) * np.exp(-tt * 9) * 0.9
        y += bubbles(sec, 30) * np.exp(-tt * 2) * 0.6
        y += sub(sec, 140, 70, 14) * 0.5
    elif el == "fire":
        y = lp(noise(sec, "brown"), 400) * np.exp(-tt * 4) * 1.0
        y += crackle(sec, 50) * np.exp(-tt * 2.5) * 0.6
        y += sweep_bp(sec, 400, 2200, 0.8) * np.exp(-tt * 5) * 0.4
    else:  # mist
        y = bp(noise(sec, "pink"), 1500, 7000) * (1 - np.exp(-tt * 10)) * np.exp(-tt * 1.8) * 0.8
        y += lp(noise(sec, "pink"), 500) * np.exp(-tt * 3) * 0.3
    return y


def umbral():
    # activation: a dark intake of breath over a low hum (was a glass bell)
    sec = 1.1
    y = sweep_bp(sec, 300, 1400, 0.7) * swell(int(SR * sec), 0.4, 0.4) * 0.7 + sub(sec, 55, 48, 1.5) * swell(int(SR * sec), 0.3, 0.5) * 0.6
    save("spell_umbral_activation", reverb(y, 0.9, 0.3), 0.45)
    # charge: tightening pressure (rising band + glassy grit, no ringing tone)
    sec = 0.9
    y = sweep_bp(sec, 500, 4000, 0.5) * np.linspace(0.2, 1, int(SR * sec)) ** 2 + grit(sec, 60) * np.linspace(0, 0.6, int(SR * sec))
    save("spell_umbral_charge", reverb(y, 0.5, 0.2), 0.55)
    # impact: shadow glass cracking + thump (gold ring removed)
    sec = 1.1
    tt = t(sec)
    y = hp(noise(sec), 2500) * np.exp(-tt * 18) * 0.8 + sub(sec, 110, 40, 9) * 0.9 + grit(sec, 120) * np.exp(-tt * 5) * 0.6
    save("spell_umbral_impact", reverb(y, 0.6, 0.25), 0.8)
    # dissipate: dark air sinking
    sec = 1.3
    tt = t(sec)
    y = sweep_bp(sec, 1800, 200, 0.8) * np.exp(-tt * 2.5) * 0.5
    save("spell_umbral_dissipate", reverb(y, 0.9, 0.3), 0.3)


def combat():
    for name, sec, body, crack in [("impact_light", 0.8, 0.7, 0.5), ("impact_heavy", 1.4, 1.0, 0.8)]:
        tt = t(sec)
        y = sub(sec, 140, 38, 6 if name == "impact_light" else 3.5) * body
        y += bp(noise(sec), 1500, 9000) * np.exp(-tt * 30) * crack
        y += sweep_bp(sec, 2500, 300, 0.9) * np.exp(-tt * 7) * 0.35          # air burst instead of a ring
        y += crackle(sec, 30) * np.exp(-tt * 6) * 0.3
        save(name, reverb(y, 0.4, 0.2), 0.85)


def cues():
    # loot: a soft pouch "fwip" and a warm low pluck of cloth - no glass notes
    sec = 0.7
    tt = t(sec)
    y = sweep_bp(sec, 1800, 500, 0.8) * np.exp(-((tt - 0.12) ** 2) / 0.006) * 0.8
    y += bp(noise(sec, "pink"), 300, 1500) * np.exp(-((tt - 0.35) ** 2) / 0.004) * 0.6
    y += sub(sec, 180, 140, 12) * 0.25
    save("loot_pickup", reverb(y, 0.4, 0.15), 0.55)
    # progress moments: warm, low, breathy swells (no bells, nothing high and piercing)
    def warm_swell(sec, root, rise, bright):
        tt = t(sec)
        y = np.zeros_like(tt)
        for k, a in ((1, 0.7), (1.5, 0.3), (0.5, 0.35)):        # root, fifth, sub-octave: a soft, low sine pad
            ph = 2 * np.pi * root * k * tt + 0.15 * np.sin(2 * np.pi * 4.8 * tt)
            y += a * np.sin(ph)
        y = lp(y, 420, 4) * swell(len(tt), rise, sec * 0.55)            # nothing tonal above ~0.5 kHz
        y += sweep_bp(sec, 300, 1600, 0.9) * swell(len(tt), rise * 0.8, sec * 0.6) * 0.18 * bright   # air, not a tone
        return y
    save("trial_complete", reverb(warm_swell(1.8, 196.0, 0.25, 0.7), 1.2, 0.3), 0.5)
    save("rank_up", reverb(warm_swell(2.6, 174.6, 0.4, 0.9) + sub(2.6, 60, 55, 1.2) * 0.4, 1.4, 0.3), 0.55)
    save("discovery", reverb(warm_swell(1.4, 220.0, 0.2, 0.5), 1.0, 0.3), 0.45)
    save("level_up", reverb(warm_swell(2.4, 164.8, 0.3, 1.0) + sweep_bp(2.4, 300, 3000, 0.6) * swell(int(SR * 2.4), 1.2, 0.8) * 0.3, 1.4, 0.3), 0.55)
    # fusion: two colours converge into one deep hit (bell cluster removed)
    sec = 3.2
    y = np.zeros(int(SR * sec))
    a = sweep_bp(1.2, 300, 1500, 0.6) * np.linspace(0, 1, int(SR * 1.2)) ** 2
    b = sweep_bp(1.2, 3000, 1500, 0.6) * np.linspace(0, 1, int(SR * 1.2)) ** 2
    y[: len(a)] += (a + b) * 0.5
    h = int(SR * 1.2)
    tail = sub(2.0, 110, 30, 2.5) * 1.0 + bp(noise(2.0), 800, 6000) * np.exp(-t(2.0) * 12) * 0.6 + grit(2.0, 80) * np.exp(-t(2.0) * 3) * 0.5
    y[h: h + len(tail)] += tail
    save("fusion_eclipse", reverb(y, 1.2, 0.3), 0.85)
    # alchemy glow: a warm low swell (the high bell partial removed)
    save("alchemy_glow", reverb(warm_swell(2.0, 220.0, 0.6, 0.4), 1.2, 0.35), 0.4)


# ------------------------------------------------------------------ Level 10 awakening scores (stage-synced)
def note(n):  # semitones from A4
    return 440.0 * 2 ** (n / 12.0)


def pluck(f, sec, decay=3.0):
    tt = t(sec)
    y = np.zeros_like(tt)
    for k, a in ((1, 1.0), (2, 0.45), (3, 0.2), (4, 0.1)):
        y += a * np.sin(2 * np.pi * f * k * tt) * np.exp(-tt * decay * k)
    return y * (1 - np.exp(-tt * 300))


def glass(f, sec, decay=1.4):
    """Soft struck-glass tone for the RARE awakening score only (allowed: a composed musical moment)."""
    tt = t(sec)
    y = sum(a * np.sin(2 * np.pi * f * k * tt) * np.exp(-tt * decay * (1 + 0.6 * i)) for i, (k, a) in enumerate(((1, 1.0), (2.0, 0.35), (3.01, 0.12))))
    return y * (1 - np.exp(-tt * 200))


def pad(freqs, sec, cutoff, attack, release, detune=0.004):
    tt = t(sec)
    y = np.zeros_like(tt)
    for f in freqs:
        for d in (-detune, 0.0, detune):
            ph = 2 * np.pi * f * (1 + d) * tt
            y += (2 / np.pi) * np.arcsin(np.sin(ph)) * 0.6 + np.sin(ph) * 0.4
    y = lp(y / max(1, len(freqs)), cutoff)
    return y * swell(len(tt), attack, release)


def place(dst, src, at, gain=1.0):
    i = int(at * SR)
    n = min(len(src), len(dst) - i)
    if n > 0 and i >= 0:
        dst[i:i + n] += src[:n] * gain


def awakening(mage, st):
    L = float(st["length"])
    y = np.zeros(int(L * SR))
    if mage == "mika":
        root, scale, chord = -7, [0, 2, 4, 6, 7, 9, 11], [0, 4, 7, 11, 14, 18]      # D lydian: bright, floating
        motif, colour = [19, 18, 16, 14, 11, 9, 7, 4], 3200
    else:
        root, scale, chord = -9, [0, 1, 3, 5, 7, 8, 10], [0, 3, 7, 10, 14, 19]       # C phrygian: dark, proud
        motif, colour = [19, 17, 15, 12, 10, 8, 7, 3], 2300
    A, B, C, S, R, O, K, P = (float(st[k]) for k in ("awaken", "build", "cover", "swap", "reveal_end", "orbit", "orbit_lock", "pose"))
    # 1 awakening: a low pad breathes in, a few far-apart plucks, air
    place(y, pad([note(root - 24), note(root - 12), note(root - 5)], B + 0.6, 500, 1.2, 0.6), A, 0.5)
    for i, at in enumerate((0.35, 0.95, 1.45)):
        place(y, pluck(note(root + scale[(i * 2) % 7]), 1.2, 3.0), A + at, 0.18)
    place(y, sweep_bp(B, 300, 1200, 0.6) * swell(int(SR * B), B * 0.8, 0.3) * 0.15, A)
    # 2 buildup: a quickening arpeggio + accelerating low pulse + riser
    tpos, i = B, 0
    while tpos < C:
        n = root + scale[i % 7] + 12 * ((i // 7) % 2)
        place(y, pluck(note(n), 0.5, 5.0), tpos, 0.18 + 0.2 * (tpos - B) / (C - B))
        tpos += max(0.08, 0.3 * (1 - (tpos - B) / (C - B)) ** 1.2)
        i += 1
    beat, bt = B, 0.62
    while beat < S - 0.05:
        place(y, sub(0.3, 90, 40, 14), beat, 0.5)
        beat += bt
        bt = max(0.15, bt * 0.84)
    place(y, pad([note(root + c) for c in chord[:4]], S - B, colour * 0.6, (S - B) * 0.7, 0.2), B, 0.35)
    # 3 cocoon: swirling air, the tension held; then the reveal hit and a falling sparkle line that follows
    #   the unravelling from head to feet
    place(y, sweep_bp(S - C, 600, 5000, 0.5) * np.linspace(0.2, 1, int(SR * (S - C))) ** 2 * 0.35, C)
    place(y, sub(2.4, 120, 32, 1.8), S, 1.0)
    place(y, pad([note(root + c) for c in chord], L - S, colour * 1.3, 0.03, 1.6), S, 0.6)
    place(y, hp(noise(1.8), 3500) * np.exp(-t(1.8) * 2.2) * 0.25, S)
    step = (R - S - 0.2) / len(motif)
    for j, n in enumerate(motif):
        place(y, glass(note(root + 12 + n), 1.4), S + 0.15 + j * step, 0.2)
        place(y, pluck(note(root + n), 0.8, 3.5), S + 0.15 + j * step, 0.12)
    # 4 orbit: an eight-step ostinato, one note per segment locking in, rising to the lock pulse
    for k in range(8):
        at = O + 0.06 * k * 6
        if at < K:
            place(y, pluck(note(root + scale[k % 7] + 12), 0.45, 6.0), at, 0.2 + 0.03 * k)
    place(y, sub(1.2, 100, 45, 4), K, 0.7)
    place(y, sweep_bp(0.8, 800, 4000, 0.6) * swell(int(SR * 0.8), 0.6, 0.2) * 0.3, K - 0.6)
    # 5 final reveal: the climax on the pose, the mage's top note, then the settle
    place(y, pad([note(root - 12), note(root + chord[1]), note(root + chord[2]), note(root + 12), note(root + 12 + chord[3])], L - P, colour * 1.5, 0.02, 1.8), P, 0.7)
    place(y, sub(2.0, 110, 35, 2.0), P, 0.9)
    place(y, glass(note(root + 24), 2.2, 1.0), P + 0.05, 0.3)
    place(y, glass(note(root + 19), 2.2, 1.0), P + 0.12, 0.22)
    save("transform_%s_full" % mage, reverb(y, 1.2, 0.3), 0.9)


if __name__ == "__main__":
    import json
    import sys
    if "transform" in sys.argv:
        tr = json.load(open(os.path.join(ROOT, "data", "transformations.json")))
        for m in ("mika", "luna"):
            awakening(m, tr["versions"]["full"]["stages"])
        sys.exit(0)
    for el in EL:
        spell_layers(el)
    umbral()
    combat()
    cues()
