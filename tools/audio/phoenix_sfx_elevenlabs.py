#!/usr/bin/env python3
"""Oriel's sound effects from REAL recorded-quality sources (visual pass 2, at the developer's request: "just use
ElevenLabs for effects"). The raw ElevenLabs Sound Effects v2 generations (generated in the developer's own
ElevenLabs workspace, flow "Oriel the Phoenix - game sound effects") live in assets/audio/elevenlabs/phoenix/;
this script mixes them into the game's files at the exact beats the code plays them on (same names as before,
so nothing else changes):

  phoenix_nova_charge     a deep fire roar swelling under a reversed fire burst that sucks inward (1.7 s)
  phoenix_nova_release    the fireball blasting forward + the phoenix's scream + a fire burst
  phoenix_nova_impact     a massive fiery explosion, a second explosion's tail, a stone strike transient
  phoenix_flare_cast / phoenix_flare_impact / phoenix_cry / phoenix_wing_beat / phoenix_takeoff / phoenix_land /
  phoenix_wing_fold / phoenix_ember_loop    one source each, trimmed, levelled
  phoenix_transform_long  10.4 s, the swap at 3.4 s: fire rising and sucking inward to the hit, the burst, a
                          ribbon swish as each part of her is made, sparks as each completes, wings of fire
  phoenix_transform_short 4.2 s, hit at 1.6 s
  phoenix_reform          9.0 s, hit at 4.2 s: swishes as she is unmade, the rising fire, the burst, wings of
                          fire, her scream

  python3 tools/audio/phoenix_sfx_elevenlabs.py
"""
import os
import subprocess

import numpy as np
from scipy.io import wavfile

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
SRC = os.path.join(ROOT, "assets", "audio", "elevenlabs", "phoenix")
OUT = os.path.join(ROOT, "assets", "audio", "synth")
SR = 44100
# beats (seconds after the swap) at which each part of her is completed / each ribbon starts
MAKE_DONE = (1.0, 2.3, 3.4, 4.6, 5.0, 5.6)
RIBBON_AT = (0.15, 1.5, 2.35, 3.75, 4.25, 5.0)
WINGS_AT = 5.45
UNMAKE_AT = (0.6, 1.1, 1.4, 1.8, 2.3, 2.7)


def load(name):
    p = os.path.join(SRC, name + ".mp3")
    raw = subprocess.run(["ffmpeg", "-v", "error", "-i", p, "-ac", "1", "-ar", str(SR), "-f", "s16le", "-"], capture_output=True, check=True).stdout
    return np.frombuffer(raw, dtype=np.int16).astype(np.float32) / 32768.0


def secs(x):
    return int(round(x * SR))


def fade(y, a=0.01, r=0.08):
    y = y.copy()
    na, nr = min(secs(a), len(y)), min(secs(r), len(y))
    if na > 0:
        y[:na] *= np.linspace(0, 1, na)
    if nr > 0:
        y[-nr:] *= np.linspace(1, 0, nr)
    return y


def trim(y, length, r=0.12):
    return fade(y[: secs(length)], 0.003, r)


def gain_db(y, db):
    return y * (10 ** (db / 20.0))


def env(y, points):
    """Piecewise-linear gain over time: points = [(t, g), ...]."""
    t = np.arange(len(y)) / SR
    ts = [p[0] for p in points]
    gs = [p[1] for p in points]
    return y * np.interp(t, ts, gs)


def place(total, layers):
    out = np.zeros(secs(total), np.float32)
    for t0, y in layers:
        i = secs(t0)
        if i < 0:
            y = y[-i:]
            i = 0
        n = min(len(y), len(out) - i)
        if n > 0:
            out[i:i + n] += y[:n]
    return out


def loop_to(y, length, xf=0.6):
    """Extend a bed to `length` by crossfading copies of itself."""
    n, x = secs(length), secs(xf)
    out = y.copy()
    while len(out) < n:
        ramp = np.linspace(0, 1, x)
        out = np.concatenate([out[:-x], out[-x:] * (1 - ramp) + y[:x] * ramp, y[x:]])
    return out[:n]


def master(y, peak=0.97, drive=1.0):
    """Normalise to `peak`, with an optional soft-clip drive for loudness (no hard clipping)."""
    m = float(np.max(np.abs(y))) or 1.0
    y = y / m
    if drive > 1.0:
        y = np.tanh(drive * y) / np.tanh(drive)
    return (y * peak).astype(np.float32)


# the nova's three sounds are now made by tools/audio/phoenix_cine_sfx.py (stereo, the cinematic pass): never overwrite them
OWNED_ELSEWHERE = {"phoenix_nova_charge", "phoenix_nova_release", "phoenix_nova_impact"}


def save(name, y):
    if name in OWNED_ELSEWHERE:
        print("skip %s (phoenix_cine_sfx.py makes it)" % name)
        return
    wav = os.path.join(OUT, "_tmp_" + name + ".wav")
    wavfile.write(wav, SR, (np.clip(y, -1, 1) * 32767).astype(np.int16))
    ogg = os.path.join(OUT, name + ".ogg")
    subprocess.run(["ffmpeg", "-v", "error", "-y", "-i", wav, "-c:a", "libvorbis", "-q:a", "6", ogg], check=True)
    os.remove(wav)
    print("wrote %s %.2fs" % (name, len(y) / SR))


S = {n: load(n) for n in ["charge_c", "release_a", "impact_a", "impact_c", "flarecast_a", "flareimp_a", "cry_a", "cry_b", "wingbeat_a",
                          "takeoff_a", "land_a", "fold_a", "ember_a", "firebed_a", "tfrise_b", "tfburst_a", "tfburst_b", "sparks_b",
                          "swish_a", "wingsflare_a", "wingsflare_b"]}
rev_burst = fade(S["tfburst_a"][::-1].copy(), 0.3, 0.01)           # a burst reversed: fire sucked inward

# ---- the solar nova
charge_len = 1.7
roar = env(S["firebed_a"][: secs(charge_len)], [(0, 0.12), (0.8, 0.45), (1.5, 1.0), (1.7, 1.0)])
suck = rev_burst[-secs(charge_len):]
deep = env(S["charge_c"][: secs(charge_len)], [(0, 0.0), (0.6, 0.5), (1.7, 0.8)])
save("phoenix_nova_charge", master(fade(place(charge_len, [(0, roar), (0, gain_db(suck, -1.0)), (0, gain_db(deep, -7.0))]), 0.05, 0.02), 0.95, 1.6))
release = place(1.6, [(0, trim(S["release_a"], 1.6)), (0.02, gain_db(trim(S["tfburst_b"], 1.4), -3.0)), (0.06, gain_db(trim(S["cry_b"], 1.2, 0.3), -9.0))])
save("phoenix_nova_release", master(release, 0.97, 1.8))
impact = place(3.2, [(0, S["impact_a"]), (0.05, gain_db(S["impact_c"], -6.0)), (0, gain_db(trim(S["flareimp_a"], 0.8), -5.0))])
save("phoenix_nova_impact", master(fade(impact, 0.002, 0.4), 0.98, 2.0))

# ---- singles
save("phoenix_flare_cast", master(trim(S["flarecast_a"], 1.28), 0.9, 1.3))
save("phoenix_flare_impact", master(trim(S["flareimp_a"], 1.48), 0.92, 1.4))
save("phoenix_cry", master(trim(S["cry_b"], 2.2, 0.25), 0.9))
save("phoenix_wing_beat", master(trim(S["wingbeat_a"], 1.0), 0.8))
save("phoenix_takeoff", master(trim(S["takeoff_a"], 2.0, 0.3), 0.85, 1.2))
save("phoenix_land", master(trim(S["land_a"], 1.36), 0.8))
save("phoenix_wing_fold", master(trim(S["fold_a"], 1.0), 0.7))
ember = S["ember_a"]
save("phoenix_ember_loop", master(ember, 0.55))

# ---- the transformation, Phoenix -> woman (long: 10.4 s, hit 3.4 s)
def transformation(total, hit, ribbons, done, wings_at, bed_db=-6.0):
    bed = env(loop_to(S["firebed_a"], total), [(0, 0.15), (hit, 1.0), (hit + 0.4, 0.55), (total - 1.2, 0.4), (total, 0.0)])
    rise = S["tfrise_b"]
    layers = [(0, gain_db(bed, bed_db)), (hit - len(rise) / SR, env(rise, [(0, 0.3), (len(rise) / SR, 1.0)])),
              (hit - len(rev_burst) / SR, gain_db(rev_burst, -2.0)), (hit, S["tfburst_b"]), (hit + 0.02, gain_db(S["tfburst_a"], -5.0))]
    for k, r in enumerate(ribbons):
        layers.append((hit + r, gain_db(S["swish_a"], -7.0 + 0.5 * k)))
    for d in done:
        layers.append((hit + d - 0.05, gain_db(S["sparks_b"], -2.0)))
    if wings_at is not None:
        layers.append((hit + wings_at, gain_db(S["wingsflare_a"], -2.0)))
    return master(fade(place(total, layers), 0.05, 0.6), 0.95, 1.3)


save("phoenix_transform_long", transformation(10.4, 3.4, RIBBON_AT, MAKE_DONE, WINGS_AT))
save("phoenix_transform_short", transformation(4.2, 1.6, (0.1,), (0.8, 1.0, 1.2, 1.4), 1.0, -7.0))

# ---- the way back (9.0 s, hit 4.2 s)
total, hit = 9.0, 4.2
bed = env(loop_to(S["firebed_a"], total), [(0, 0.1), (hit, 1.0), (hit + 0.5, 0.5), (total - 1.0, 0.35), (total, 0.0)])
rise = S["tfrise_b"]
layers = [(0, gain_db(bed, -6.0)), (hit - len(rise) / SR, env(rise, [(0, 0.3), (len(rise) / SR, 1.0)])),
          (hit - len(rev_burst) / SR, gain_db(rev_burst, -2.0)), (hit, S["tfburst_b"]), (hit + 0.05, gain_db(S["wingsflare_b"], -1.0)),
          (hit + 0.35, gain_db(S["cry_a"], -3.0)), (hit + 0.2, gain_db(S["wingbeat_a"], -4.0))]
for k, u in enumerate(UNMAKE_AT):
    layers.append((u, gain_db(S["swish_a"], -7.0)))
    layers.append((u + 0.3, gain_db(S["sparks_b"], -6.0)))
save("phoenix_reform", master(fade(place(total, layers), 0.05, 0.6), 0.95, 1.3))
