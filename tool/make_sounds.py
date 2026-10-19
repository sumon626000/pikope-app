#!/usr/bin/env python3
"""Generates the game's original sound effects (no third-party samples).

    python3 tool/make_sounds.py        # rewrites assets/audio/*.wav listed below
"""
import math
import os
import random
import struct
import wave

SR = 44100
OUT = os.path.join(os.path.dirname(__file__), '..', 'assets', 'audio')
random.seed(7)


def silence(seconds):
    return [0.0] * int(SR * seconds)


def add(buf, at, samples):
    start = int(at * SR)
    if len(buf) < start + len(samples):
        buf.extend([0.0] * (start + len(samples) - len(buf)))
    for i, v in enumerate(samples):
        buf[start + i] += v


def ping(freq, decay, seconds, amp=1.0, attack=0.0005, harmonics=((1, 1.0),)):
    """A struck tone: fast attack, exponential decay."""
    out = []
    for i in range(int(SR * seconds)):
        t = i / SR
        env = min(1.0, t / attack) * math.exp(-t / decay)
        out.append(amp * env * sum(a * math.sin(2 * math.pi * freq * h * t) for h, a in harmonics))
    return out


def noise(seconds, decay, amp=1.0, lowpass=1.0, highpass=0.0):
    """Filtered noise burst (one-pole low/high pass, coefficients 0..1)."""
    out, lp, hp_prev, prev = [], 0.0, 0.0, 0.0
    for i in range(int(SR * seconds)):
        t = i / SR
        x = random.uniform(-1, 1)
        lp += lowpass * (x - lp)
        y = lp
        if highpass > 0:
            hp_prev = highpass * (hp_prev + y - prev)
            prev = y
            y = hp_prev
        out.append(amp * y * math.exp(-t / decay))
    return out


def sweep(f0, f1, seconds, decay, amp=1.0):
    out, phase = [], 0.0
    n = int(SR * seconds)
    for i in range(n):
        t = i / SR
        f = f0 + (f1 - f0) * (i / n)
        phase += 2 * math.pi * f / SR
        out.append(amp * math.sin(phase) * min(1.0, t / 0.002) * math.exp(-t / decay))
    return out


def save(name, buf, peak=0.89, fade=0.004):
    n = int(SR * fade)
    for i in range(min(n, len(buf))):
        buf[-1 - i] *= i / n
    top = max(1e-9, max(abs(v) for v in buf))
    with wave.open(os.path.join(OUT, name + '.wav'), 'wb') as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes(b''.join(struct.pack('<h', int(max(-1, min(1, v / top * peak)) * 32767)) for v in buf))
    print(f'{name}.wav  {len(buf) / SR:.2f}s')


# Two hard balls meeting: a full, dry "tock" - most of it between 0.6 and
# 1.3 kHz with a little bite up to 2.3 kHz - that is over in a few hundredths
# of a second.
b = silence(0.11)
add(b, 0, noise(0.004, 0.0012, 0.50, lowpass=0.45, highpass=0.85))
for f, d, a in ((455, 0.012, 0.30), (620, 0.014, 0.55), (810, 0.015, 1.0), (1010, 0.014, 1.0),
                (1240, 0.012, 0.85), (1500, 0.010, 0.70), (1760, 0.009, 0.60), (2020, 0.009, 0.60),
                (2310, 0.008, 0.62), (2620, 0.005, 0.25), (3550, 0.004, 0.18), (4000, 0.004, 0.20)):
    add(b, 0, ping(f, d, 0.10, a, attack=0.0004))
add(b, 0.001, ping(325, 0.018, 0.10, 0.16))
save('ball_hit', b)

# Cue tip on the cue ball: the same family of sound, a touch softer on the
# attack and held slightly longer.
b = silence(0.16)
add(b, 0, noise(0.007, 0.0028, 0.40, lowpass=0.30, highpass=0.90))
for f, d, a in ((450, 0.022, 0.30), (615, 0.024, 0.55), (800, 0.024, 1.0), (995, 0.022, 1.0),
                (1250, 0.019, 0.85), (1490, 0.014, 0.45), (2010, 0.009, 0.30), (2290, 0.008, 0.24)):
    add(b, 0, ping(f, d, 0.15, a, attack=0.0012))
add(b, 0.001, ping(320, 0.024, 0.15, 0.20))
save('cue_hit', b)

# A ball drops into a pocket: a low knock as it goes in (around 300 Hz with
# body up to 1 kHz), a short rattle against the pocket, then - a quarter of a
# second later - a soft clack as it comes to rest below the table.
b = silence(0.48)
add(b, 0, noise(0.005, 0.0015, 0.35, lowpass=0.35, highpass=0.80))
for f, d, a in ((150, 0.030, 0.30), (225, 0.026, 0.35), (320, 0.028, 1.0), (455, 0.022, 0.50),
                (610, 0.020, 0.55), (800, 0.018, 0.60), (1000, 0.016, 0.55), (1750, 0.008, 0.12)):
    add(b, 0, ping(f, d, 0.20, a, attack=0.0008))
for at, amp in ((0.040, 0.42), (0.072, 0.26)):
    add(b, at, noise(0.003, 0.0012, 0.25 * amp, lowpass=0.6, highpass=0.8))
    for f, d, a in ((150, 0.030, 0.9), (320, 0.020, 0.7), (1000, 0.016, 1.0), (3550, 0.007, 0.36),
                    (4000, 0.006, 0.40), (2000, 0.010, 0.18)):
        add(b, at, ping(f, d, 0.14, amp * a, attack=0.0008))
add(b, 0.262, noise(0.004, 0.0015, 0.05, lowpass=0.6, highpass=0.8))
for f, d, a in ((150, 0.045, 1.0), (1000, 0.022, 0.55), (1760, 0.020, 0.70), (2010, 0.018, 0.55),
                (3520, 0.012, 0.55), (320, 0.030, 0.55)):
    add(b, 0.262, ping(f, d, 0.20, 0.17 * a, attack=0.0015))
save('pocket', b)

# The turn passes: two soft, rising marimba-like notes.
b = silence(0.6)
tone = ((1, 1.0), (2, 0.28), (4, 0.10))
add(b, 0.00, ping(659.25, 0.11, 0.35, 0.8, attack=0.004, harmonics=tone))
add(b, 0.13, ping(987.77, 0.16, 0.45, 1.0, attack=0.004, harmonics=tone))
save('turn', b, peak=0.75)

# Button touch: a small soft pop.
b = silence(0.09)
add(b, 0, sweep(980, 520, 0.08, 0.022, 1.0))
add(b, 0, noise(0.003, 0.001, 0.25, lowpass=0.6, highpass=0.7))
add(b, 0.004, ping(1960, 0.012, 0.06, 0.18))
save('tap', b, peak=0.7)

# A match begins: the rack is set (a few clacks), then a bright rising chord.
b = silence(1.5)
for at, amp in ((0.00, 0.5), (0.07, 0.65), (0.13, 0.8), (0.21, 1.0)):
    add(b, at, noise(0.004, 0.0012, 0.5 * amp, lowpass=0.9, highpass=0.85))
    for f, d, a in ((2150, 0.010, 1.0), (3380, 0.008, 0.7), (1180, 0.014, 0.45)):
        add(b, at, ping(f * (1 + 0.04 * random.uniform(-1, 1)), d, 0.08, 0.5 * amp * a))
add(b, 0.18, [v * (i / (SR * 0.22)) for i, v in enumerate(noise(0.22, 5.0, 0.22, lowpass=0.12, highpass=0.9))])
bell = ((1, 1.0), (2, 0.35), (3, 0.12), (4.2, 0.06))
for k, f in enumerate((523.25, 659.25, 783.99, 1046.5)):
    add(b, 0.40 + 0.075 * k, ping(f, 0.30, 0.95, 0.55 + 0.1 * k, attack=0.003, harmonics=bell))
save('match_start', b, peak=0.8)
