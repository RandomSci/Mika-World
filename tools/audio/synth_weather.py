#!/usr/bin/env python3
"""Weather (WeatherSystem): original synthesized audio, no samples.

  amb_rain_light   a soft, steady shower on leaves: pink hiss shaped high, a scatter of separate drop ticks
  amb_rain_heavy   a downpour: dense broadband wash, low body, many overlapping drops, slow gusts
  amb_rain_roof    rain heard from under a shelter: muffled wash + hollow ticks on wood/slate (camp tarp, porch)
  thunder_near_1/2 a close strike: a sharp crack that splits into a long rolling rumble
  thunder_far_1    distant thunder: no crack, a slow low roll

Loops are seamless. Run: python3 tools/audio/synth_weather.py (deterministic)
"""
import sys
import os

sys.path.insert(0, os.path.dirname(__file__))
from synth_milestone_k import SR, t, lp, hp, bp, noise, loopable, slow, save  # noqa: E402
import numpy as np  # noqa: E402

rng = np.random.default_rng(20261016)


def drops(sec, rate, lo, hi, decay=0.012, amp=1.0):
    """Individual drop ticks: tiny band-limited clicks at random times."""
    n = int(SR * sec)
    y = np.zeros(n)
    k = int(rate * sec)
    L = int(SR * decay * 6)
    env = np.exp(-np.arange(L) / (SR * decay))
    for _ in range(k):
        s = rng.integers(0, n - L)
        burst = rng.standard_normal(L) * env * rng.uniform(0.3, 1.0) * amp
        y[s:s + L] += burst
    return bp(y, lo, hi)


def rain_light(sec=24.0):
    wash = hp(lp(noise(sec + 2, "pink"), 9000), 900) * 0.5 * slow(sec + 2, 0.05, 0.2)
    ticks = drops(sec + 2, 70, 1800, 7000, 0.008, 0.9)
    leaf = drops(sec + 2, 25, 600, 2500, 0.02, 0.7)
    return loopable(wash + ticks * 0.6 + leaf * 0.5)


def rain_heavy(sec=24.0):
    wash = hp(lp(noise(sec + 2, "white"), 11000), 300) * 0.9 * slow(sec + 2, 0.07, 0.3, 1.0)
    body = lp(noise(sec + 2, "brown"), 400) * 0.6 * slow(sec + 2, 0.04, 0.35, 2.0)
    ticks = drops(sec + 2, 400, 1500, 9000, 0.006, 0.8)
    return loopable(wash + body + ticks * 0.5)


def rain_roof(sec=24.0):
    wash = lp(noise(sec + 2, "pink"), 2500) * 0.7 * slow(sec + 2, 0.05, 0.25)
    hollow = drops(sec + 2, 140, 400, 1600, 0.03, 1.0)
    drip = drops(sec + 2, 8, 900, 2200, 0.05, 1.4)      # the odd heavy drip off an edge
    return loopable(wash + hollow * 0.7 + drip * 0.5)


def thunder(sec=9.0, near=True, seed=0):
    r = np.random.default_rng(seed)
    n = int(SR * sec)
    y = np.zeros(n)
    tt = t(sec)
    if near:
        # the crack: a few ms of broadband noise with a sharp attack, then high crackle
        c = int(SR * 0.35)
        crack = r.standard_normal(c) * np.exp(-np.arange(c) / (SR * 0.06))
        y[:c] += hp(crack, 300) * 1.0
        start = 0.05
    else:
        start = 0.0
    # the roll: brown noise through a slowly sweeping low-pass, several overlapping swells
    roll = noise(sec, "brown")
    env = np.zeros(n)
    for k in range(r.integers(3, 6)):
        c0 = start + r.uniform(0.0, sec * 0.5)
        w = r.uniform(0.8, 2.4)
        env += np.exp(-((tt - c0 - w) ** 2) / (2 * (w * 0.7) ** 2)) * r.uniform(0.5, 1.0)
    env *= np.clip((tt - start) * 4.0, 0, 1)
    env *= np.exp(-tt / (sec * 0.45))
    rolled = lp(roll, 180 if not near else 260) * env
    y += rolled * (0.9 if near else 0.7)
    if near:
        y += lp(bp(r.standard_normal(n), 60, 900), 900) * env * 0.25
    fade = np.ones(n)
    fl = int(SR * 0.6)
    fade[-fl:] = np.linspace(1, 0, fl)
    return y * fade


if __name__ == "__main__":
    save("amb_rain_light", rain_light(), 0.7)
    save("amb_rain_heavy", rain_heavy(), 0.8)
    save("amb_rain_roof", rain_roof(), 0.7)
    save("thunder_near_1", thunder(8.0, True, 11), 0.95)
    save("thunder_near_2", thunder(9.5, True, 23), 0.95)
    save("thunder_far_1", thunder(10.0, False, 37), 0.8)
