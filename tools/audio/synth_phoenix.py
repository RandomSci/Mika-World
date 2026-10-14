#!/usr/bin/env python3
"""SUPERSEDED - see tools/audio/phoenix_sfx_elevenlabs.py (real ElevenLabs sound effects, at the developer's request).

Oriel's sounds (V3 Part X): original, synthesised with numpy (no samples), bell-free by construction (no
narrow sustained partials above 600 Hz: every tone glides or sits low, every ring is noise-based).

  python3 tools/audio/synth_phoenix.py        -> assets/audio/synth/phoenix_*.ogg

  phoenix_wing_beat      one stroke: air displaced, a soft whump, feather flutter
  phoenix_wing_fold      feathers settling against the body
  phoenix_land           weight meeting stone, a rustle
  phoenix_takeoff        a gust and two hard strokes
  phoenix_cry            her call: a gliding harmonic voice with breath (not a whistle, not a chime)
  phoenix_ember_loop     embers crackling under a warm rumble (loops)
  phoenix_flare_cast     fire magic released from her chest: rush + crackle + a rising flare
  phoenix_flare_impact   the flare striking: a burst, a low thump, a crackling tail
  phoenix_transform_short 4.2 s gameplay transformation; the swap lands at SHORT_HIT (1.6 s)
  phoenix_transform_long  10.4 s cinematic transformation (visual pass 2): the swap at LONG_HIT (3.4 s), then an
                          airy sparkle as each part of her is made (hair, sandals, skirt, arms, bodice, crown) and
                          a rush of flame for the phantom wings of her final pose
  phoenix_reform          the way back (humanoid -> phoenix, 9 s): unmaking, the rising pillar, wings of fire (hit 4.2 s)
  phoenix_nova_charge     her power attack gathering (1.6 s): an inhaling roar of fire rising in pitch
  phoenix_nova_release    the nova driven forward by her downstroke: a blast of air and fire with her cry
  phoenix_nova_impact     the nova striking: a deep detonation, a burst, a long crackling fall of embers
"""
import os
import subprocess

import numpy as np
from scipy.io import wavfile
from scipy.signal import butter, sosfilt

SR = 44100
ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
OUT = os.path.join(ROOT, "assets", "audio", "synth")
rng = np.random.default_rng(20261015)
SHORT_HIT = 1.6
LONG_HIT = 3.4
REFORM_HIT = 4.2
# seconds after the swap at which each part of her is completed (scripts/phoenix/phoenix_human.gd TL_CINE)
MAKE_BEATS = (1.0, 2.3, 3.4, 4.6, 5.0, 5.6)
WINGS_AT = 5.45


def t(sec):
    return np.arange(int(SR * sec)) / SR


def _sos(kind, f, order=2):
    return butter(order, f, btype=kind, fs=SR, output="sos")


def lp(x, f, order=2):
    return sosfilt(_sos("low", min(f, SR / 2 - 100), order), x)


def hp(x, f, order=2):
    return sosfilt(_sos("high", max(f, 10), order), x)


def bp(x, lo, hi, order=2):
    return sosfilt(_sos("band", [max(lo, 10), min(hi, SR / 2 - 100)], order), x)


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


def env(sec, a=0.01, d=0.1, s=1.0, r=0.2, hold=None):
    n = int(SR * sec)
    e = np.zeros(n)
    ai, di, ri = int(a * SR), int(d * SR), int(r * SR)
    hold = n - ai - di - ri if hold is None else int(hold * SR)
    i = 0
    e[i:i + ai] = np.linspace(0, 1, ai)
    i += ai
    e[i:i + di] = np.linspace(1, s, di)
    i += di
    e[i:i + hold] = s
    i += hold
    e[i:i + ri] = np.linspace(s, 0, ri)
    return e[:n]


def fade(y, a=0.004, b=0.02):
    y = y.copy()
    a, b = int(a * SR), int(b * SR)
    if a:
        y[:a] *= np.linspace(0, 1, a)
    if b:
        y[-b:] *= np.linspace(1, 0, b)
    return y


def mix(sec, *layers):
    n = int(SR * sec)
    out = np.zeros(n)
    for at, y in layers:
        i = int(at * SR)
        m = min(len(y), n - i)
        if m > 0:
            out[i:i + m] += y[:m]
    return out


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


def glide_tone(sec, f_path, harmonics=((1, 1.0), (2, 0.5), (3, 0.3), (4, 0.18), (5, 0.1)), vib=5.5, vib_depth=0.012, breath=0.25):
    """A voiced tone whose pitch follows f_path (list of (time, hz)); harmonics with a soft formant; a little breath."""
    tt = t(sec)
    ts = np.array([p[0] for p in f_path])
    fs = np.array([p[1] for p in f_path])
    f = np.interp(tt, ts, fs) * (1 + vib_depth * np.sin(2 * np.pi * vib * tt + 1.0))
    y = np.zeros_like(tt)
    # three slightly detuned voices (a living throat, not a pure oscillator), each with its own slow drift
    for det, amp in ((1.0, 1.0), (1.014, 0.55), (0.989, 0.45)):
        phase = 2 * np.pi * np.cumsum(f * det * (1 + 0.004 * np.sin(2 * np.pi * 0.31 * tt + det * 7))) / SR
        for h, a in harmonics:
            y += amp * a * np.sin(phase * h) * (0.6 + 0.4 * np.sin(2 * np.pi * 0.7 * tt + h))
    # a soft "throat" formant around 1.2-2.2 kHz, a rasp that follows the voice, and breath noise
    y = y * 0.7 + bp(y, 900, 2600, 1) * 0.5
    rasp = bp(noise(sec, "white"), 700, 4000, 1) * (0.5 + 0.5 * np.sign(y)) * 0.35
    y += rasp * breath + bp(noise(sec, "pink"), 1500, 6000) * breath
    return y


def whoosh(sec, f0=300, f1=2600, kind="pink", shape=(0.35, 0.65)):
    """Air moving: noise with a sweeping low-pass; `shape` = where the loudest point lies (fraction) and its width."""
    tt = t(sec)
    n = len(tt)
    x = noise(sec, kind)
    # time-varying lowpass by crossfading two filtered copies
    a = lp(x, f0, 2)
    b = lp(x, f1, 2)
    k = np.clip((tt / sec - shape[0]) / (shape[1] - shape[0] + 1e-6), 0, 1)
    y = a * (1 - k) + b * k
    e = np.exp(-((tt / sec - shape[0]) ** 2) / (2 * (shape[1] * 0.35) ** 2))
    return y * e


def thump(sec, f0=70, f1=40, decay=9.0, amp=1.0):
    tt = t(sec)
    f = f0 + (f1 - f0) * (1 - np.exp(-tt * 12))
    y = np.sin(2 * np.pi * np.cumsum(f) / SR) * np.exp(-tt * decay)
    return y * amp


def crackle(sec, density=28.0, lo=1500, hi=7000, amp=1.0, decay_ms=(6, 22)):
    n = int(SR * sec)
    y = np.zeros(n)
    count = int(density * sec)
    for _ in range(count):
        i = rng.integers(0, n)
        L = int(rng.uniform(*decay_ms) * SR / 1000)
        burst = rng.standard_normal(L) * np.exp(-np.arange(L) / (L / 3.0)) * rng.uniform(0.3, 1.0)
        m = min(L, n - i)
        y[i:i + m] += burst[:m]
    return bp(y, lo, hi, 1) * amp


def flutter(sec, rate=17.0, amp=1.0):
    tt = t(sec)
    x = bp(noise(sec, "white"), 800, 5000, 1)
    m = 0.5 + 0.5 * np.sign(np.sin(2 * np.pi * rate * tt)) * (0.6 + 0.4 * np.sin(2 * np.pi * 3 * tt))
    return x * m * np.exp(-tt * 3.0) * amp


def rumble(sec, f=48.0, amp=1.0):
    tt = t(sec)
    y = np.sin(2 * np.pi * f * tt + 0.8 * np.sin(2 * np.pi * 0.9 * tt)) + 0.5 * np.sin(2 * np.pi * f * 1.5 * tt + 1.0)
    y += lp(noise(sec, "brown"), 120) * 1.2
    return y * amp


def shimmer(sec, amp=1.0):
    """The feather veil: many short gliding partials high up, never holding one bin (no chime)."""
    tt = t(sec)
    y = np.zeros_like(tt)
    for k in range(26):
        f0 = rng.uniform(1200, 5200)
        f1 = f0 * (rng.uniform(0.5, 0.78) if rng.random() < 0.5 else rng.uniform(1.28, 1.7))   # always a real glide (no held bin)
        st = rng.uniform(0, sec * 0.8)
        L = rng.uniform(0.18, 0.5)
        seg = (tt >= st) & (tt < st + L)
        tl = tt[seg] - st
        f = f0 + (f1 - f0) * tl / L
        e = np.sin(np.pi * tl / L) ** 2
        y[seg] += np.sin(2 * np.pi * np.cumsum(f) / SR) * e * rng.uniform(0.2, 0.5)
    return y * amp


# ---------------------------------------------------------------------------------------------- the set
def wing_beat():
    sec = 0.7
    return mix(sec, (0.0, whoosh(0.55, 250, 1800, shape=(0.3, 0.6)) * 1.0), (0.12, thump(0.4, 64, 42, 10, 0.7)), (0.05, flutter(0.5, 16, 0.35)))


def wing_fold():
    sec = 0.9
    return mix(sec, (0.0, flutter(0.8, 11, 0.6)), (0.0, bp(noise(0.9, "pink"), 500, 3000, 1) * env(0.9, 0.05, 0.2, 0.5, 0.4) * 0.5), (0.5, crackle(0.4, 40, 1200, 4000, 0.25, (3, 9))))


def land():
    sec = 0.8
    return mix(sec, (0.0, thump(0.5, 80, 45, 8, 1.0)), (0.0, bp(noise(0.12, "white"), 300, 1500, 1) * np.exp(-t(0.12) * 40) * 0.6),
               (0.08, flutter(0.6, 14, 0.5)), (0.02, crackle(0.5, 30, 800, 3000, 0.3, (4, 14))))


def takeoff():
    sec = 1.5
    return mix(sec, (0.0, whoosh(1.1, 200, 3200, shape=(0.25, 0.7)) * 1.1), (0.15, thump(0.5, 70, 44, 9, 0.9)), (0.55, thump(0.5, 66, 42, 9, 0.8)),
               (0.1, flutter(0.6, 15, 0.45)), (0.5, flutter(0.6, 15, 0.45)), (0.0, crackle(1.4, 20, 1500, 6000, 0.25)))


def cry():
    sec = 1.9
    path = [(0.0, 560), (0.2, 1020), (0.45, 1240), (0.75, 860), (1.0, 1120), (1.3, 940), (1.55, 1060), (1.9, 520)]
    v = glide_tone(sec, path, vib=7.0, vib_depth=0.035, breath=0.55)
    e = env(sec, 0.08, 0.3, 0.8, 0.5)
    y = v * e
    y += lp(noise(sec, "pink"), 500) * env(sec, 0.1, 0.4, 0.5, 0.6) * 0.3       # chest resonance (low, wide)
    return y


def ember_loop():
    sec = 3.0
    y = crackle(sec, 26, 1800, 7000, 0.6, (4, 18)) + rumble(sec, 46, 0.35) + bp(noise(sec, "pink"), 200, 900, 1) * 0.12
    # make it loop: crossfade the tail into the head
    n = len(y)
    x = int(0.25 * SR)
    ramp = np.linspace(0, 1, x)
    y[:x] = y[:x] * ramp + y[n - x:] * (1 - ramp)
    return y[: n - x]


def flare_cast():
    sec = 1.2
    tt = t(sec)
    flare = glide_tone(0.9, [(0.0, 180), (0.35, 420), (0.9, 560)], harmonics=((1, 1.0), (2, 0.6), (3, 0.35), (4, 0.2)), vib=4, vib_depth=0.03, breath=0.4)
    flare = lp(flare, 2500, 1) * env(0.9, 0.05, 0.2, 0.7, 0.4)
    return mix(sec, (0.0, whoosh(1.0, 300, 4000, shape=(0.35, 0.7)) * 1.0), (0.1, flare * 0.8), (0.2, crackle(1.0, 60, 1500, 7000, 0.5)), (0.3, thump(0.5, 60, 38, 7, 0.5)))


def flare_impact():
    sec = 1.0
    return mix(sec, (0.0, bp(noise(0.2, "white"), 150, 6000, 1) * np.exp(-t(0.2) * 26) * 1.0), (0.0, thump(0.6, 75, 40, 7, 1.0)),
               (0.05, crackle(0.9, 90, 1200, 8000, 0.6, (3, 12))), (0.0, whoosh(0.7, 2500, 400, shape=(0.1, 0.55)) * 0.5))


def transformation(total, hit, open_at, veil_at, settle_at):
    """Embers wake (open_at..veil_at), the feather veil gathers (veil_at..hit), the bloom lands at `hit`, the new
    form emerges and the fire settles (hit..settle_at..total)."""
    tt = t(total)
    y = np.zeros_like(tt)
    # embers waking
    emb = crackle(total, 22, 1800, 7000, 0.5, (4, 16)) * np.clip((tt - open_at) / max(veil_at - open_at, 0.1), 0, 1) * (tt < hit + 0.5)
    y += emb
    # a warm rising presence (low, under the chime band): a drone sliding up from 55 to 110 Hz
    dr = glide_tone(total, [(0.0, 55), (hit, 110), (total, 82)], harmonics=((1, 1.0), (2, 0.5), (3, 0.25)), vib=0.6, vib_depth=0.01, breath=0.0)
    y += lp(dr, 300, 1) * env(total, open_at, hit - open_at, 0.9, total - hit) * 0.55
    # the veil: gliding shimmer, growing toward the hit
    sh = shimmer(hit - veil_at + 0.4, 1.0)
    y = mix(total, (0.0, y), (veil_at, sh * np.linspace(0.2, 1.0, len(sh))))
    # rising air
    y += whoosh(total, 200, 5000, shape=(hit / total, 0.5)) * 0.9 * (tt <= hit + 0.4)
    # the bloom: a deep whump, a bright burst of air, a ring of crackle
    y = mix(total, (0.0, y), (hit - 0.02, thump(1.2, 90, 36, 4.5, 1.6)), (hit, bp(noise(0.35, "white"), 300, 8000, 1) * np.exp(-t(0.35) * 14) * 1.2),
            (hit + 0.05, crackle(1.6, 110, 1200, 8000, 0.7, (3, 14))), (hit + 0.1, whoosh(1.4, 3500, 300, shape=(0.05, 0.6)) * 0.8))
    # emergence: a descending warm voice (gliding, never static) and embers settling
    em = glide_tone(settle_at - hit, [(0.0, 440), (0.4, 360), (0.9, 300), (1.6, 250), (settle_at - hit, 170)], harmonics=((1, 1.0), (2, 0.4), (3, 0.2)), vib=5.0, vib_depth=0.03, breath=0.4)
    em = lp(em, 1800, 1) * env(settle_at - hit, 0.15, 0.4, 0.6, max(0.4, settle_at - hit - 0.6))
    y = mix(total, (0.0, y), (hit + 0.25, em * 0.45), (hit + 0.3, crackle(total - hit - 0.3, 14, 1500, 6000, 0.35) * np.linspace(1, 0.1, int((total - hit - 0.3) * SR))))
    y += rumble(total, 44, 0.25) * env(total, open_at, hit - open_at, 0.8, total - hit)
    return y


def sparkle(sec=0.6, amp=1.0):
    """An airy glitter (a part of her made): gliding high partials + a breath of bright noise, no held pitch."""
    return (shimmer(sec, 0.9) + hp(noise(sec, "pink"), 4000) * env(sec, 0.01, 0.05, 0.4, sec - 0.1) * 0.25) * amp


def transformation_long():
    total = 10.4
    y = transformation(total, LONG_HIT, 0.2, 1.6, 9.6)
    parts = [(0.0, y)]
    for k, b in enumerate(MAKE_BEATS):
        parts.append((LONG_HIT + b - 0.05, sparkle(0.7, 0.55 + 0.08 * k)))
    parts.append((LONG_HIT + WINGS_AT, whoosh(1.2, 300, 5200, shape=(0.2, 0.6)) * 0.9))
    parts.append((LONG_HIT + WINGS_AT + 0.05, crackle(1.3, 80, 1200, 7000, 0.6, (3, 12))))
    return mix(total, *parts)


def reform():
    """Humanoid -> phoenix (9 s): her parts unmade into ribbons of fire, the rising pillar, the burst at the hit with
    her cry, wings of flame."""
    total = 9.0
    y = transformation(total, REFORM_HIT, 0.1, 1.2, 8.2)
    cr = cry() * 0.6
    parts = [(0.0, y), (REFORM_HIT + 0.35, cr), (REFORM_HIT + 0.2, takeoff() * 0.5)]
    for k, b in enumerate((1.2, 1.8, 2.1, 2.6, 3.0, 3.4)):
        parts.append((b - 0.05, sparkle(0.6, 0.4 + 0.05 * k)))
    return mix(total, *parts)


def nova_charge():
    sec = 1.7
    tt = t(sec)
    roar = glide_tone(sec, [(0.0, 70), (0.9, 120), (1.7, 190)], harmonics=((1, 1.0), (2, 0.7), (3, 0.45), (4, 0.25)), vib=3.0, vib_depth=0.04, breath=0.6)
    roar = lp(roar, 1400, 1) * env(sec, 0.3, 0.6, 0.9, 0.5)
    inhale = whoosh(sec, 5000, 400, shape=(0.85, 0.4)) * 0.8           # air drawn in toward her
    return mix(sec, (0.0, roar * 0.9), (0.0, inhale), (0.2, crackle(1.5, 40, 1500, 7000, 0.6, (4, 14)) * np.linspace(0.2, 1.2, int(1.5 * SR))),
               (0.0, rumble(sec, 40, 0.5) * np.linspace(0.3, 1.0, int(sec * SR))))


def nova_release():
    sec = 1.4
    blast = bp(noise(0.5, "white"), 200, 7000, 1) * np.exp(-t(0.5) * 9) * 1.2
    return mix(sec, (0.0, whoosh(1.0, 300, 6000, shape=(0.12, 0.6)) * 1.3), (0.0, thump(0.9, 70, 34, 5, 1.4)), (0.02, blast),
               (0.05, cry()[: int(0.9 * SR)] * env(0.9, 0.02, 0.2, 0.7, 0.6) * 0.6), (0.1, crackle(1.2, 100, 1500, 8000, 0.7, (3, 12))))


def nova_impact():
    sec = 2.4
    det = bp(noise(0.6, "white"), 60, 9000, 1) * np.exp(-t(0.6) * 7) * 1.4
    return mix(sec, (0.0, thump(1.6, 95, 30, 3.0, 2.0)), (0.0, det), (0.03, whoosh(1.4, 4000, 200, shape=(0.05, 0.7)) * 0.9),
               (0.08, crackle(2.2, 140, 1000, 8000, 0.8, (3, 16)) * np.linspace(1.2, 0.05, int(2.2 * SR))), (0.0, rumble(sec, 34, 1.0) * env(sec, 0.01, 0.3, 0.6, 1.8)))


if __name__ == "__main__":
    import sys
    if "--synth" not in sys.argv:
        # superseded (2026-10-14, the developer: "just use ElevenLabs for effects"): Oriel's sounds are now mixed from
        # real ElevenLabs sound effects by tools/audio/phoenix_sfx_elevenlabs.py; this synthesis is kept only for
        # reference and never overwrites them unless asked with --synth.
        print("synth_phoenix: superseded by tools/audio/phoenix_sfx_elevenlabs.py (pass --synth to regenerate the old set)")
        sys.exit(0)
    save("phoenix_wing_beat", wing_beat(), 0.7)
    save("phoenix_wing_fold", wing_fold(), 0.55)
    save("phoenix_land", land(), 0.75)
    save("phoenix_takeoff", takeoff(), 0.8)
    save("phoenix_cry", cry(), 0.8)
    save("phoenix_ember_loop", ember_loop(), 0.55)
    save("phoenix_flare_cast", flare_cast(), 0.8)
    save("phoenix_flare_impact", flare_impact(), 0.85)
    save("phoenix_transform_short", transformation(4.2, SHORT_HIT, 0.05, 0.6, 3.8), 0.85)
    save("phoenix_transform_long", transformation_long(), 0.85)
    save("phoenix_reform", reform(), 0.85)
    save("phoenix_nova_charge", nova_charge(), 0.8)
    save("phoenix_nova_release", nova_release(), 0.9)
    save("phoenix_nova_impact", nova_impact(), 0.95)
