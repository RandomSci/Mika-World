#!/usr/bin/env python3
"""Original procedural sound design for Mika World (no samples, no third-party audio, deterministic).

Spell layers per element (arcane, wind, water, fire, mist, rune, self):
  activation  - a subtle chime
  rune        - crystalline resonance (chord partials swelling)
  gather_loop - a smooth humming bed, seamlessly loopable (pitch is raised in-game as power gathers)
  charge      - a gentle harmonic pulse
  release     - a clear whoosh in the element's colour
  impact      - the element's response (bells / air burst / splash / whoomph / hiss)
  dissipate   - a soft fading shimmer
Ambience loops: forest wind, pond, fire crackle, night insects, library room tone, Heartstone hum,
watchpoint wind. One-shots: bird chirps, fox yip, fish plip, trial complete, rank up, discovery,
portal whoosh, steam hiss, smoke puff, crystal shatter, page rustle (supplementing Kenney's book set).

Everything is written as 16-bit WAV at 44.1 kHz into assets/audio/synth/. Re-run to regenerate.
"""
import os
import numpy as np
from scipy.io import wavfile
from scipy.signal import butter, lfilter, sosfilt

SR = 44100
OUT = os.path.join(os.path.dirname(__file__), "..", "..", "assets", "audio", "synth")
rng = np.random.default_rng(20261011)


def t(sec):
    return np.arange(int(SR * sec)) / SR


def env_adsr(n, a=0.005, d=0.1, s=0.6, r=0.3, total=None):
    total = total or n / SR
    tt = np.arange(n) / SR
    e = np.ones(n)
    e = np.where(tt < a, tt / max(a, 1e-6), e)
    e = np.where((tt >= a) & (tt < a + d), 1 - (1 - s) * (tt - a) / max(d, 1e-6), e)
    e = np.where((tt >= a + d) & (tt < total - r), s, e)
    e = np.where(tt >= total - r, s * np.clip((total - tt) / max(r, 1e-6), 0, 1), e)
    return e


def lp(x, f, order=2):
    sos = butter(order, min(f / (SR / 2), 0.99), "low", output="sos")
    return sosfilt(sos, x)


def hp(x, f, order=2):
    sos = butter(order, min(f / (SR / 2), 0.99), "high", output="sos")
    return sosfilt(sos, x)


def bp(x, lo, hi, order=2):
    sos = butter(order, [lo / (SR / 2), min(hi / (SR / 2), 0.99)], "band", output="sos")
    return sosfilt(sos, x)


def noise(sec, kind="white"):
    n = int(SR * sec)
    w = rng.standard_normal(n)
    if kind == "pink":
        # Voss-ish: filter white noise with -3 dB/oct approximation
        b = [0.049922035, -0.095993537, 0.050612699, -0.004408786]
        a = [1, -2.494956002, 2.017265875, -0.522189400]
        w = lfilter(b, a, w)
    elif kind == "brown":
        w = np.cumsum(w)
        w = w - lp(w, 0.5)
    return w / (np.max(np.abs(w)) + 1e-9)


def reverb(x, tail=1.6, wet=0.35, damp=4000):
    n = int(SR * tail)
    ir = rng.standard_normal(n) * np.exp(-np.arange(n) / SR * (6.9 / tail))
    ir = lp(ir, damp)
    ir[0] = 0
    ir /= np.sqrt(np.sum(ir ** 2)) + 1e-9
    y = np.convolve(x, ir)[: len(x) + n]
    dry = np.concatenate([x, np.zeros(len(y) - len(x))])
    return dry * (1 - wet) + y * wet * 0.6


def bell(f0, sec, partials=((1, 1), (2.76, 0.5), (5.4, 0.25), (8.93, 0.12)), decay=2.5, detune=0.0015):
    tt = t(sec)
    y = np.zeros_like(tt)
    for ratio, amp in partials:
        for d in (-detune, detune):
            y += amp * np.sin(2 * np.pi * f0 * ratio * (1 + d) * tt) * np.exp(-tt * decay * (0.6 + ratio * 0.25))
    y *= np.minimum(1, tt / 0.004)
    return y


def chord_swell(freqs, sec, attack=0.5, shimmer=6.0):
    tt = t(sec)
    y = np.zeros_like(tt)
    for i, f in enumerate(freqs):
        y += np.sin(2 * np.pi * f * tt + i) * (0.6 + 0.4 * np.sin(2 * np.pi * (shimmer + i * 0.7) * tt)) / len(freqs)
        y += 0.25 * np.sin(2 * np.pi * f * 2.001 * tt) / len(freqs)
    e = np.minimum(1, tt / attack) * np.exp(-np.maximum(0, tt - attack) * 1.6)
    return y * e


def sweep_noise(sec, f_from, f_to, q=1.5, kind="pink"):
    n = int(SR * sec)
    x = noise(sec, kind)
    out = np.zeros(n)
    hop = 512
    for s in range(0, n, hop):
        fr = s / n
        fc = f_from * (f_to / f_from) ** fr
        lo, hi = fc / q, min(fc * q, SR / 2 * 0.95)
        seg = x[max(0, s - 2048): s + hop]
        y = bp(seg, max(lo, 30), hi)
        out[s: s + hop] = y[-min(hop, n - s):]
    return out


def norm(y, peak=0.8):
    m = np.max(np.abs(y)) + 1e-9
    return y / m * peak


def fade(y, fin=0.005, fout=0.05):
    n = len(y)
    a = int(SR * fin)
    b = int(SR * fout)
    if a > 0:
        y[:a] *= np.linspace(0, 1, a)
    if b > 0:
        y[-b:] *= np.linspace(1, 0, b)
    return y


def loopable(y, xf=1.0):
    """Crossfade the tail into the head so the clip loops seamlessly."""
    k = int(SR * xf)
    head, tail = y[:k].copy(), y[-k:].copy()
    w = np.linspace(0, 1, k)
    y = y[k:].copy()
    y[-k:] = tail * (1 - w) + head * w
    return y


def save(name, y, peak=0.8):
    os.makedirs(OUT, exist_ok=True)
    y = norm(np.asarray(y, dtype=np.float64), peak)
    wavfile.write(os.path.join(OUT, name + ".wav"), SR, (y * 32767).astype(np.int16))


# ------------------------------------------------------------------ element palettes
PAL = {
    "arcane": {"root": 440.0, "chord": [440, 554.37, 659.25, 830.61], "bright": 1.0},
    "rune": {"root": 523.25, "chord": [523.25, 659.25, 783.99, 987.77], "bright": 1.1},
    "self": {"root": 392.0, "chord": [392, 493.88, 587.33, 739.99], "bright": 0.9},
    "wind": {"root": 587.33, "chord": [587.33, 739.99, 880, 1174.66], "bright": 0.7},
    "water": {"root": 349.23, "chord": [349.23, 440, 523.25, 698.46], "bright": 0.8},
    "fire": {"root": 293.66, "chord": [293.66, 369.99, 440, 587.33], "bright": 0.6},
    "mist": {"root": 329.63, "chord": [329.63, 415.3, 493.88, 659.25], "bright": 0.7},
}


def spell_layers(el):
    p = PAL[el]
    r = p["root"]
    # activation: a subtle chime (two soft bell strikes a fifth apart)
    a = bell(r * 2, 1.4, decay=3.5) * 0.7
    a[int(SR * 0.07):] += bell(r * 3, 1.4 - 0.07, decay=3.8)[: len(a) - int(SR * 0.07)] * 0.4
    if el == "wind":
        a += hp(noise(1.4, "pink"), 2500) * np.exp(-t(1.4) * 5) * 0.15
    save(f"spell_{el}_activation", fade(reverb(a, 1.4, 0.4)), 0.5)
    # rune formation: crystalline resonance
    rr = chord_swell(p["chord"], 2.2, attack=0.6, shimmer=7.0 if el != "fire" else 3.0)
    rr += bell(r * 4, 2.2, decay=2.0) * 0.15
    if el == "water":
        rr += np.sin(2 * np.pi * 2.0 * t(2.2)) * 0.0
    save(f"spell_{el}_rune", fade(reverb(rr, 2.0, 0.45), 0.02, 0.4), 0.45)
    # gather loop (4 s, seamless): drone + breathy noise in the element's band
    tt = t(5.0)
    g = 0.5 * np.sin(2 * np.pi * r / 2 * tt) + 0.25 * np.sin(2 * np.pi * r * tt + 0.3) + 0.12 * np.sin(2 * np.pi * r * 1.5 * tt)
    g *= 0.8 + 0.2 * np.sin(2 * np.pi * 0.5 * tt)
    band = {"wind": (800, 4000), "water": (300, 1800), "fire": (150, 1200), "mist": (500, 3000)}.get(el, (1500, 6000))
    g += bp(noise(5.0, "pink"), *band) * (0.25 if el in ("wind", "mist") else 0.12)
    if el == "fire":
        g += crackle(5.0, 18) * 0.15
    if el == "water":
        g += bubbles(5.0, 7) * 0.2
    save(f"spell_{el}_gather_loop", loopable(g, 1.0), 0.4)
    # charge: harmonic pulse
    tt = t(1.2)
    c = np.sin(2 * np.pi * (r / 4) * tt * (1 + 0.3 * np.exp(-tt * 8))) * np.exp(-tt * 4) * 0.8
    c += chord_swell(p["chord"], 1.2, attack=0.08, shimmer=9) * 0.6
    save(f"spell_{el}_charge", fade(reverb(c, 1.2, 0.35)), 0.6)
    # release: whoosh
    w = sweep_noise(0.9, 300 if el != "wind" else 600, 3500 if el != "fire" else 1800, q=1.6)
    w *= np.exp(-((t(0.9) - 0.25) ** 2) / 0.02)
    w += bell(r * 2, 0.9, decay=5) * 0.2 * p["bright"]
    save(f"spell_{el}_release", fade(reverb(w, 0.9, 0.25)), 0.7)
    # impact
    save(f"spell_{el}_impact", fade(reverb(impact(el, r), 1.4, 0.3)), 0.8)
    # dissipate: soft shimmer
    tt = t(2.0)
    d = np.zeros_like(tt)
    for k in range(9):
        f = r * (2 + k * 0.5) * (1 + rng.uniform(-0.01, 0.01))
        st = rng.uniform(0, 0.6)
        seg = (tt >= st)
        d += seg * np.sin(2 * np.pi * f * (tt - st)) * np.exp(-np.maximum(0, tt - st) * 4) * 0.2
    d += hp(noise(2.0, "pink"), 5000) * np.exp(-tt * 2) * 0.05
    save(f"spell_{el}_dissipate", fade(reverb(d, 1.6, 0.5), 0.02, 0.4), 0.35)


def crackle(sec, rate):
    n = int(SR * sec)
    y = np.zeros(n)
    count = int(sec * rate)
    for _ in range(count):
        i = rng.integers(0, n - 2000)
        L = rng.integers(60, 400)
        y[i: i + L] += rng.standard_normal(L) * np.exp(-np.arange(L) / (L / 4)) * rng.uniform(0.3, 1.0)
    return lp(bp(y, 700, 4500), 3500)   # warm, wood-fire crackle rather than a hard digital tick


def bubbles(sec, rate):
    n = int(SR * sec)
    y = np.zeros(n)
    for _ in range(int(sec * rate)):
        i = rng.integers(0, n - 6000)
        f = rng.uniform(500, 1400)
        L = int(SR * rng.uniform(0.03, 0.08))
        tt = np.arange(L) / SR
        y[i: i + L] += np.sin(2 * np.pi * f * (1 + tt * 14) * tt) * np.exp(-tt * 60) * rng.uniform(0.3, 1)
    return y


def impact(el, r):
    tt = t(1.4)
    if el in ("arcane", "rune", "self"):
        y = bell(r * 1.5, 1.4, decay=2.2) * 0.6 + bell(r * 2.25, 1.4, decay=2.6) * 0.4
        y += np.sin(2 * np.pi * 70 * tt) * np.exp(-tt * 10) * 0.8
        y += hp(noise(1.4, "white"), 6000) * np.exp(-tt * 9) * 0.15
    elif el == "wind":
        y = sweep_noise(1.4, 2500, 300, q=1.8) * np.exp(-tt * 3) * 1.2
        y += lp(noise(1.4, "pink"), 300) * np.exp(-tt * 6) * 0.6
    elif el == "water":
        y = bp(noise(1.4, "white"), 400, 3000) * np.exp(-tt * 9) * 0.9
        y += bubbles(1.4, 30) * np.exp(-tt * 2) * 0.6
        y += np.sin(2 * np.pi * 120 * tt) * np.exp(-tt * 14) * 0.5
    elif el == "fire":
        y = lp(noise(1.4, "brown"), 400) * np.exp(-tt * 4) * 1.0
        y += crackle(1.4, 50) * np.exp(-tt * 2.5) * 0.6
        y += sweep_noise(1.4, 400, 2200, q=1.5) * np.exp(-tt * 5) * 0.4
    else:  # mist
        y = bp(noise(1.4, "pink"), 1500, 7000) * (1 - np.exp(-tt * 10)) * np.exp(-tt * 1.8) * 0.8
        y += lp(noise(1.4, "pink"), 500) * np.exp(-tt * 3) * 0.3
    return y


# ------------------------------------------------------------------ ambience (loops)
def ambience():
    sec = 32.0
    tt = t(sec)
    gust = 0.55 + 0.25 * np.sin(2 * np.pi * 0.07 * tt) + 0.2 * np.sin(2 * np.pi * 0.19 * tt + 1.3)
    wind = lp(noise(sec, "pink"), 900) * gust + bp(noise(sec, "pink"), 1500, 4000) * gust ** 3 * 0.15
    save("amb_forest_wind", loopable(wind, 2.0), 0.35)
    lap = bp(noise(sec, "pink"), 200, 1200) * (0.5 + 0.5 * np.sin(2 * np.pi * 0.35 * tt) ** 2) * 0.5
    lap += bubbles(sec, 2.5) * 0.35
    save("amb_pond", loopable(lap, 2.0), 0.3)
    fire = lp(noise(12.0, "brown"), 250) * 0.5 + crackle(12.0, 22) * 0.7
    save("amb_fire_crackle", loopable(fire, 1.0), 0.45)
    ins = np.zeros_like(tt)
    for k in range(4):
        f = rng.uniform(3800, 5200)
        rate = rng.uniform(2.0, 3.5)
        gate = (np.sin(2 * np.pi * rate * tt + k) > 0.55) * (np.sin(2 * np.pi * 0.11 * tt + k * 2) > -0.3)
        ins += np.sin(2 * np.pi * f * tt) * (0.5 + 0.5 * np.sin(2 * np.pi * 60 * tt)) * lp(gate.astype(float), 40) * 0.25
    ins += lp(noise(sec, "pink"), 500) * 0.05
    save("amb_night_insects", loopable(ins, 2.0), 0.25)
    room = lp(noise(sec, "brown"), 180) * 0.6 + bp(noise(sec, "pink"), 300, 900) * 0.04
    save("amb_library", loopable(room, 2.0), 0.2)
    hum = sum(np.sin(2 * np.pi * f * tt + i) * a for i, (f, a) in enumerate([(55, 0.5), (110.3, 0.35), (165.2, 0.2), (440.5, 0.05), (659.7, 0.03)]))
    hum *= 0.75 + 0.25 * np.sin(2 * np.pi * 0.25 * tt)
    save("amb_heartstone", loopable(hum, 2.0), 0.3)
    high = bp(noise(sec, "pink"), 600, 2500) * gust ** 2 + lp(noise(sec, "pink"), 300) * 0.4
    high += np.sin(2 * np.pi * 880 * tt + 3 * np.sin(2 * np.pi * 0.3 * tt)) * gust ** 4 * 0.03
    save("amb_watchpoint_wind", loopable(high, 2.0), 0.35)


# ------------------------------------------------------------------ one-shots
def oneshots():
    for k in range(6):
        sec = rng.uniform(0.35, 0.9)
        tt = t(sec)
        f0 = rng.uniform(2600, 4200)
        notes = rng.integers(2, 5)
        y = np.zeros_like(tt)
        for i in range(notes):
            st = i * sec / notes
            L = sec / notes * 0.8
            m = (tt >= st) & (tt < st + L)
            tl = tt - st
            sweep = f0 * (1 + rng.uniform(-0.25, 0.35) * tl / L)
            y += m * np.sin(2 * np.pi * sweep * tl + 4 * np.sin(2 * np.pi * rng.uniform(25, 60) * tl)) * np.sin(np.pi * np.clip(tl / L, 0, 1))
        save(f"bird_chirp_{k}", fade(reverb(y, 0.6, 0.25)), 0.4)
    tt = t(0.5)
    fox = (np.sin(2 * np.pi * (700 + 500 * np.exp(-tt * 9)) * tt) + 0.4 * np.sin(2 * np.pi * (1400 + 900 * np.exp(-tt * 9)) * tt)) * np.exp(-tt * 9)
    fox += bp(noise(0.5, "white"), 1000, 3000) * np.exp(-tt * 20) * 0.2
    save("fox_yip", fade(reverb(fox, 0.5, 0.2)), 0.5)
    tt = t(0.3)
    plip = np.sin(2 * np.pi * (900 + 1500 * tt) * tt) * np.exp(-tt * 25) + bp(noise(0.3, "white"), 800, 3000) * np.exp(-tt * 40) * 0.3
    save("fish_plip", fade(plip), 0.4)
    for name, notes, sec in [("trial_complete", [659.25, 830.61, 987.77], 2.2), ("rank_up", [523.25, 659.25, 783.99, 1046.5, 1318.5], 3.5),
                             ("discovery", [880, 1318.5], 1.8)]:
        y = np.zeros(int(SR * sec))
        for i, f in enumerate(notes):
            st = int(SR * i * 0.13)
            b = bell(f, sec - i * 0.13, decay=2.2) * (0.9 - i * 0.08)
            y[st: st + len(b)] += b[: len(y) - st]
        if name == "rank_up":
            y += chord_swell([523.25, 659.25, 783.99], sec, attack=0.8) * 0.4
        save(name, fade(reverb(y, 2.0, 0.45), 0.003, 0.4), 0.6)
    tt = t(2.6)
    portal = sweep_noise(2.6, 200, 4000, q=1.4) * np.sin(np.pi * tt / 2.6) + chord_swell([392, 587.33, 783.99], 2.6, attack=1.2, shimmer=11) * 0.5
    save("portal_whoosh", fade(reverb(portal, 1.6, 0.4), 0.02, 0.5), 0.7)
    tt = t(1.6)
    steam = lp(hp(noise(1.6, "pink"), 1800), 7000) * (1 - np.exp(-tt * 20)) * np.exp(-tt * 1.8)
    save("steam_hiss", fade(steam), 0.5)
    tt = t(1.2)
    puff = lp(noise(1.2, "pink"), 700) * np.exp(-tt * 4) * (1 - np.exp(-tt * 30))
    save("smoke_puff", fade(puff), 0.5)
    tt = t(1.5)
    sh = np.zeros_like(tt)
    for k in range(18):
        st = rng.uniform(0, 0.25)
        f = rng.uniform(2500, 7000)
        sh += (tt >= st) * np.sin(2 * np.pi * f * (tt - st)) * np.exp(-np.maximum(0, tt - st) * rng.uniform(8, 20)) * rng.uniform(0.2, 0.6)
    sh += hp(noise(1.5, "white"), 3000) * np.exp(-tt * 12) * 0.6
    save("crystal_shatter", fade(reverb(sh, 1.0, 0.35)), 0.6)
    tt = t(1.4)
    sit = bp(noise(1.4, "pink"), 400, 3000) * np.exp(-((tt - 0.5) ** 2) / 0.05) * 0.6
    save("cloth_settle", fade(sit), 0.35)
    tt = t(1.0)
    bub = bubbles(1.0, 25) + lp(noise(1.0, "pink"), 600) * 0.2
    save("alchemy_bubble", fade(bub), 0.4)
    tt = t(1.3)
    pour = bp(noise(1.3, "pink"), 500, 2500) * (0.6 + 0.4 * np.sin(2 * np.pi * 7 * tt)) * np.minimum(1, tt / 0.1) * np.minimum(1, (1.3 - tt) / 0.2)
    pour += bubbles(1.3, 14) * 0.3
    save("pour_liquid", fade(pour), 0.4)
    tt = t(2.2)
    glow = chord_swell([440, 659.25, 880, 1108.73], 2.2, attack=0.7, shimmer=8) + bell(1760, 2.2, decay=2.5) * 0.2
    save("alchemy_glow", fade(reverb(glow, 1.6, 0.45), 0.02, 0.4), 0.45)


if __name__ == "__main__":
    for el in PAL:
        spell_layers(el)
    ambience()
    oneshots()
    files = sorted(os.listdir(OUT))
    print(len(files), "files ->", os.path.abspath(OUT))
