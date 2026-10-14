#!/usr/bin/env python3
"""Oriel's CINEMATIC sound (the cinematic pass, 2026-10-14 - the developer: "The sound made it low quality"; "just use
ElevenLabs for effects"). Layered from ElevenLabs Sound Effects v2 / Music v2.5 generations (the developer's own
workspace, flow "Oriel the Phoenix - game sound effects", AB3RHA6aUSXccKmf8aq2; four variations each, the best
picked by measurement: no clipping, level, envelope, stereo width), mixed IN STEREO (the old mixes were mono) and
mastered with a look-ahead peak limiter (no waveshaping distortion). The chosen raw sources are kept in
assets/audio/elevenlabs/phoenix/ (px_*.mp3).

  phoenix_wing_gust       a great wingbeat + the gust it drives through the trees + leaves blown
  phoenix_nova_charge     a roaring inferno swelling, flames sucked inward, ending on the throw (1.9 s)
  phoenix_nova_release    the fireball launched + its roar flying away
  phoenix_nova_impact     a deep explosion boom + a fireball's roar and crackle + debris raining down
  phoenix_scream          her battle scream
  phoenix_fire_burn_loop  crackling fire (seamless loop) - the fires left burning
  phoenix_tf_ignite       the ring of fire catching round her
  phoenix_tf_tornado      the fire tornado, building to its peak at the transformation's hit (2.5 s)
  phoenix_tf_burst        the hit: a magical burst of fire over a deep boom
  phoenix_tf_shimmer      sparkles while the woman is made
  phoenix_tf_wings        wings of fire unfolding
  phoenix_tf_music        11 s orchestral cue (instrumental) whose big hit lands at 3.40 s = the cinematic swap

  python3 tools/audio/phoenix_cine_sfx.py <raw_dir>
"""
import os
import shutil
import subprocess
import sys

import numpy as np
from scipy.io import wavfile
from scipy.ndimage import maximum_filter1d

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
RAW = sys.argv[1] if len(sys.argv) > 1 else os.path.join(ROOT, "assets", "audio", "elevenlabs", "phoenix")
KEEP = os.path.join(ROOT, "assets", "audio", "elevenlabs", "phoenix")
OUT = os.path.join(ROOT, "assets", "audio", "synth")
SR = 44100
PICK = {"wingbeat": 3, "gust": 2, "leaves": 2, "chargeroar": 4, "chargesuck": 3, "launch": 3, "flyby": 1, "boom": 3,
	"fireblast": 4, "debris": 2, "burnloop": 3, "scream": 2, "tornado": 4, "tfburst": 3, "shimmer": 1, "ringignite": 3,
	"wingsunfold": 4, "heartbeat": 3, "tfmusic": 2}


def load(key):
	name = "px_%s_%d.mp3" % (key, PICK[key])
	src = os.path.join(RAW, name)
	if os.path.abspath(RAW) != os.path.abspath(KEEP):
		os.makedirs(KEEP, exist_ok=True)
		shutil.copy(src, os.path.join(KEEP, name))
	raw = subprocess.run(["ffmpeg", "-v", "error", "-i", src, "-ac", "2", "-ar", str(SR), "-f", "s16le", "-"], capture_output=True, check=True).stdout
	return np.frombuffer(raw, dtype=np.int16).astype(np.float32).reshape(-1, 2) / 32768.0


def secs(x):
	return int(round(x * SR))


def db(y, d):
	return y * (10 ** (d / 20.0))


def fade(y, a=0.005, r=0.12):
	y = y.copy()
	na, nr = min(secs(a), len(y)), min(secs(r), len(y))
	if na:
		y[:na] *= np.linspace(0, 1, na)[:, None]
	if nr:
		y[-nr:] *= np.linspace(1, 0, nr)[:, None]
	return y


def env(y, pts):
	t = np.arange(len(y)) / SR
	return y * np.interp(t, [p[0] for p in pts], [p[1] for p in pts])[:, None]


def place(total, layers):
	out = np.zeros((secs(total), 2), np.float32)
	for t0, y in layers:
		i = secs(t0)
		if i < 0:
			y, i = y[-i:], 0
		n = min(len(y), len(out) - i)
		if n > 0:
			out[i:i + n] += y[:n]
	return out


def limit(y, ceiling=0.89, look=0.004, release=0.09):
	"""Look-ahead peak limiter: gain follows the peak envelope down instantly (ahead of the peak) and recovers slowly."""
	peak = maximum_filter1d(np.abs(y).max(axis=1), size=max(secs(look) * 2, 1))
	want = np.minimum(1.0, ceiling / np.maximum(peak, 1e-6))
	g = np.empty_like(want)
	a = np.exp(-1.0 / (release * SR))
	cur = 1.0
	for i in range(len(want)):        # release smoothing (attack is instant: the look-ahead window covers it)
		cur = want[i] if want[i] < cur else want[i] + (cur - want[i]) * a
		g[i] = cur
	return y * g[:, None]


def master(y, loud_db=-14.0, ceiling=0.89):
	"""Bring to a target loudness (RMS of the loud part), then limit the peaks."""
	m = np.abs(y).mean(axis=1)
	loud = np.sqrt(np.mean(np.sort(m)[-max(len(m) // 4, 1):] ** 2)) + 1e-9
	y = y * (10 ** (loud_db / 20.0) / loud)
	return limit(y, ceiling).astype(np.float32)


def save(name, y):
	wav = os.path.join(OUT, "_tmp_" + name + ".wav")
	wavfile.write(wav, SR, (np.clip(y, -1, 1) * 32767).astype(np.int16))
	subprocess.run(["ffmpeg", "-v", "error", "-y", "-i", wav, "-c:a", "libvorbis", "-q:a", "7", os.path.join(OUT, name + ".ogg")], check=True)
	os.remove(wav)
	pk = float(np.abs(y).max())
	print("wrote %-24s %5.2fs  stereo  peak %.2f" % (name, len(y) / SR, pk))


S = {k: load(k) for k in PICK}

save("phoenix_wing_gust", master(fade(place(2.6, [(0.0, S["wingbeat"]), (0.06, db(S["gust"], 2.0)), (0.12, db(S["leaves"], -2.0))]), 0.002, 0.5), -15.0))
roar = env(S["chargeroar"][:secs(1.9)], [(0, 0.25), (0.8, 0.55), (1.6, 1.0), (1.9, 1.0)])
# the inward-rushing flames peak (0.65 s into their take) just before the throw at ~1.85 s
save("phoenix_nova_charge", master(fade(place(1.9, [(0.0, roar), (1.15, db(S["chargesuck"], -2.0)), (0.0, db(S["heartbeat"], -6.0))]), 0.05, 0.03), -10.5))
save("phoenix_nova_release", master(fade(place(2.0, [(0.0, S["launch"]), (0.15, db(S["flyby"], -4.0))]), 0.002, 0.3), -9.5))
save("phoenix_scream", master(fade(S["scream"], 0.002, 0.25), -9.5))
save("phoenix_nova_impact", master(fade(place(4.6, [(0.0, S["boom"]), (0.0, db(S["fireblast"][secs(0.1):], -1.0)), (0.35, db(S["debris"], 8.0))]), 0.001, 0.8), -11.0, 0.93))
save("phoenix_fire_burn_loop", master(S["burnloop"], -20.0))
save("phoenix_tf_ignite", master(fade(S["ringignite"], 0.005, 0.4), -11.0))
tor = S["tornado"][secs(4.75 - 2.3):]
save("phoenix_tf_tornado", master(fade(env(tor, [(0, 0.0), (0.7, 0.55), (2.2, 1.0), (2.5, 1.0)]), 0.01, 0.15), -12.0))
save("phoenix_tf_burst", master(fade(place(3.0, [(0.0, S["tfburst"][secs(0.3):]), (0.0, db(S["boom"], -4.0))]), 0.001, 0.6), -11.0, 0.93))
save("phoenix_tf_shimmer", master(fade(S["shimmer"], 0.05, 0.8), -20.0))
save("phoenix_tf_wings", master(fade(S["wingsunfold"], 0.01, 0.4), -10.5))
save("phoenix_tf_music", master(fade(S["tfmusic"], 0.01, 1.2), -16.0, 0.85))
