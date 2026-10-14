#!/usr/bin/env python3
"""Every combat sound from REAL recorded-quality sources (the developer, 2026-10-14: "the attacks should SCREAM ...
just use ElevenLabs for effects"). Raw ElevenLabs Sound Effects v2 generations (two variations each, generated in
the developer's own ElevenLabs workspace, flow "Mika World - combat sound effects") are read from a source folder;
the better variation of each is chosen by measurement (no clipping, fuller level, the right envelope: impacts
that hit at once, charges that build, releases that start sharp), levelled and written over the game's files of
the same name in assets/audio/synth/ (so no code changes). The chosen raw sources are kept in
assets/audio/elevenlabs/combat/.

Per spell element (fire, wind, nature, water, mist, arcane, umbral, rune, self) the three generated stages
(charge, release, impact) are used directly; the quieter stages are DERIVED from the element's other recording
(never synthesised): activation (a soft cut of the release), rune (the charge stretched by a crossfaded loop),
gather_loop (a seamless 4 s loop of the charge), dissipate (the impact's tail, fading).

  python3 tools/audio/combat_sfx_elevenlabs.py <raw_dir>
"""
import glob
import os
import shutil
import subprocess
import sys

import numpy as np
from scipy.io import wavfile

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
RAW = sys.argv[1] if len(sys.argv) > 1 else os.path.join(ROOT, "assets", "audio", "elevenlabs", "combat")
KEEP = os.path.join(ROOT, "assets", "audio", "elevenlabs", "combat")
OUT = os.path.join(ROOT, "assets", "audio", "synth")
SR = 44100
ELEMENTS = ["fire", "wind", "nature", "water", "mist", "arcane", "umbral", "rune", "self"]
SINGLES = ["impact_heavy", "impact_light", "mage_hit", "monster_bolt", "monster_lunge", "monster_slam", "ward_leaf_up", "ward_leaf_absorb",
           "ward_mirror_up", "ward_mirror_absorb", "ward_mirror_reflect", "rift_open", "rift_erupt", "roots_erupt", "roots_seam", "roots_wither",
           "crystal_shatter", "fusion_eclipse"]


def load(path):
    raw = subprocess.run(["ffmpeg", "-v", "error", "-i", path, "-ac", "1", "-ar", str(SR), "-f", "s16le", "-"], capture_output=True, check=True).stdout
    return np.frombuffer(raw, dtype=np.int16).astype(np.float32) / 32768.0


def secs(x):
    return int(round(x * SR))


def fade(y, a=0.005, r=0.1):
    y = y.copy()
    na, nr = min(secs(a), len(y)), min(secs(r), len(y))
    if na > 0:
        y[:na] *= np.linspace(0, 1, na)
    if nr > 0:
        y[-nr:] *= np.linspace(1, 0, nr)
    return y


def envelope(y, win=0.05):
    w = secs(win)
    return np.array([np.sqrt(np.mean(y[i:i + w] ** 2)) for i in range(0, max(len(y) - w, 1), w)] or [0.0])


def score(y, kind):
    """Higher is better: level and cleanliness, plus the envelope the stage needs."""
    peak = float(np.max(np.abs(y))) or 1e-6
    clip = float(np.mean(np.abs(y) > 0.985))
    env = envelope(y / peak)
    rms = float(np.sqrt(np.mean((y / peak) ** 2)))
    tpk = float(np.argmax(env)) / max(len(env), 1)
    third = np.array_split(env, 3)
    rise = float(np.mean(third[2]) / max(np.mean(third[0]), 1e-4))
    s = rms * 2.0 - clip * 40.0
    if kind in ("impact", "hit", "release"):
        s += 0.6 * (1.0 - tpk)              # hits at once
    elif kind == "charge":
        s += 0.25 * min(rise, 3.0)          # builds
    return s


def master(y, peak=0.9, drive=1.0):
    m = float(np.max(np.abs(y))) or 1.0
    y = y / m
    if drive > 1.0:
        y = np.tanh(drive * y) / np.tanh(drive)
    return (y * peak).astype(np.float32)


def loop_to(y, length, xf=0.5):
    n, x = secs(length), min(secs(xf), len(y) // 3)
    out = y.copy()
    while len(out) < n:
        ramp = np.linspace(0, 1, x)
        out = np.concatenate([out[:-x], out[-x:] * (1 - ramp) + y[:x] * ramp, y[x:]])
    return out[:n]


def seamless_loop(y, length, xf=0.6):
    """A loop whose end crossfades into its start (for gather_loop)."""
    body = loop_to(y, length + xf, xf)
    x = secs(xf)
    ramp = np.linspace(0, 1, x)
    out = body[: secs(length)].copy()
    out[:x] = out[:x] * ramp + body[-x:] * (1 - ramp)
    return out


def save(name, y):
    wav = os.path.join(OUT, "_tmp_" + name + ".wav")
    wavfile.write(wav, SR, (np.clip(y, -1, 1) * 32767).astype(np.int16))
    subprocess.run(["ffmpeg", "-v", "error", "-y", "-i", wav, "-c:a", "libvorbis", "-q:a", "6", os.path.join(OUT, name + ".ogg")], check=True)
    os.remove(wav)
    print("wrote %-28s %.2fs" % (name, len(y) / SR))


def variants(name):
    return sorted(glob.glob(os.path.join(RAW, name + "_[0-9].mp3")))


def pick(name, kind):
    vs = variants(name)
    if not vs:
        return None, None, []
    loaded = [(p, load(p)) for p in vs]
    loaded.sort(key=lambda pv: score(pv[1], kind), reverse=True)
    best = loaded[0]
    os.makedirs(KEEP, exist_ok=True)
    if os.path.abspath(os.path.dirname(best[0])) != os.path.abspath(KEEP):
        shutil.copy(best[0], os.path.join(KEEP, os.path.basename(best[0])))
    return best[0], best[1], [pv[1] for pv in loaded[1:]]


KIND = {"impact_heavy": "hit", "impact_light": "hit", "mage_hit": "hit", "monster_bolt": "release", "monster_lunge": "release", "monster_slam": "impact",
        "ward_leaf_absorb": "hit", "ward_mirror_absorb": "hit", "ward_mirror_reflect": "release", "rift_erupt": "impact", "roots_erupt": "impact",
        "roots_seam": "hit", "crystal_shatter": "impact", "fusion_eclipse": "impact"}
LEVEL = {"impact_heavy": (0.95, 1.6), "impact_light": (0.85, 1.3), "mage_hit": (0.85, 1.2), "monster_slam": (0.97, 1.8), "fusion_eclipse": (0.97, 1.5),
         "crystal_shatter": (0.9, 1.2), "rift_erupt": (0.95, 1.5), "roots_erupt": (0.95, 1.4)}

for el in ELEMENTS:
    got = {}
    spare = {}
    for stage, kind, (pk, drv) in (("charge", "charge", (0.9, 1.3)), ("release", "release", (0.95, 1.5)), ("impact", "impact", (0.97, 1.7))):
        name = "spell_%s_%s" % (el, stage)
        p, y, others = pick(name, kind)
        if y is None:
            print("missing", name)
            continue
        got[stage] = y
        spare[stage] = others[0] if others else y
        save(name, master(fade(y, 0.003, 0.12), pk, drv))
    if len(got) < 3:
        continue
    # the quieter stages, derived from the element's other recordings (never synthesised)
    save("spell_%s_activation" % el, master(fade(spare["release"][: secs(1.3)], 0.06, 0.4), 0.7))
    save("spell_%s_rune" % el, master(fade(loop_to(spare["charge"], 2.6, 0.5), 0.3, 0.6), 0.65))
    save("spell_%s_gather_loop" % el, master(seamless_loop(spare["charge"], 4.0, 0.6), 0.6))
    tail = spare["impact"][secs(0.35):]
    save("spell_%s_dissipate" % el, master(fade(loop_to(tail, 2.1, 0.4), 0.15, 1.0), 0.6))

for name in SINGLES:
    p, y, _ = pick(name, KIND.get(name, "other"))
    if y is None:
        print("missing", name)
        continue
    pk, drv = LEVEL.get(name, (0.88, 1.2))
    save(name, master(fade(y, 0.003, 0.12), pk, drv))
