#!/usr/bin/env python3
"""The Crown's nine bells (Mentor's Tower, Level 100): original synthesized bronze bells, no samples.

  bell_ring_1 .. bell_ring_9   one bell per Warden's ring, highest (Aelis, the ring of breath) to deepest (the
                               Skyborn Twins); D-minor pentatonic so any of them sounding together stays consonant
  bell_crown_wind              the night wind over the tower top that sets them moving (seamless loop)

Bell timbre: the classic church-bell partial series (hum 0.5, prime 1, minor-third tierce 1.2, quint 1.5,
nominal 2, then 2.5 / 3 / 4.2 / 5.4), each partial with its own decay (the hum rings longest, the high ones
die fast), a short noisy strike and a slow beat from slightly detuned pairs.
Run: python3 tools/audio/synth_bells.py (deterministic)
"""
import sys
import os

sys.path.insert(0, os.path.dirname(__file__))
from synth_milestone_k import SR, t, lp, hp, noise, loopable, slow, save  # noqa: E402
import numpy as np  # noqa: E402

rng = np.random.default_rng(20261017)
FUND = [587.33, 523.25, 440.0, 392.0, 349.23, 293.66, 261.63, 220.0, 196.0]   # ring 1 .. 9
PARTIALS = [(0.5, 0.55, 1.0), (1.0, 1.0, 0.75), (1.2, 0.55, 0.55), (1.5, 0.3, 0.42), (2.0, 0.6, 0.38),
            (2.5, 0.22, 0.25), (3.0, 0.2, 0.2), (4.2, 0.12, 0.13), (5.4, 0.08, 0.09)]   # (ratio, amp, decay scale)


def bell(f0, sec):
    tt = t(sec)
    base_decay = 3.2 * (440.0 / f0) ** 0.5 + 1.2          # big bells ring longer
    y = np.zeros_like(tt)
    for ratio, amp, dk in PARTIALS:
        f = f0 * ratio
        if f > 15000:
            continue
        d = base_decay * dk
        beat = 1.0 + 0.0015 * rng.uniform(-1, 1)          # a detuned twin partial: the slow "wow" of real bronze
        y += amp * np.exp(-tt / d) * (np.sin(2 * np.pi * f * tt + rng.uniform(0, 6.28)) +
                                      0.35 * np.sin(2 * np.pi * f * beat * tt + rng.uniform(0, 6.28)))
    strike_n = int(SR * 0.02)
    strike = rng.standard_normal(strike_n) * np.exp(-np.arange(strike_n) / (SR * 0.004))
    y[:strike_n] += hp(strike, 2000) * 0.4
    y *= np.clip(tt / 0.002, 0, 1)
    fl = int(SR * 0.4)
    y[-fl:] *= np.linspace(1, 0, fl)
    return y


def crown_wind(sec=20.0):
    body = lp(noise(sec + 2, "pink"), 900) * slow(sec + 2, 0.09, 0.45, 0.5)
    whistle = hp(lp(noise(sec + 2, "white"), 2600), 1400) * 0.25 * slow(sec + 2, 0.13, 0.6, 1.5)
    return loopable(body + whistle)


if __name__ == "__main__":
    for i, f in enumerate(FUND):
        save("bell_ring_%d" % (i + 1), bell(f, 7.0 + i * 0.6), 0.85)
    save("bell_crown_wind", crown_wind(), 0.6)
