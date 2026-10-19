#!/usr/bin/env python3
"""Generate PikoPe game audio (WAV) — soft menu/gameplay loops + SFX."""
from __future__ import annotations

import math
import random
import struct
import wave
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "assets" / "audio"
SR = 44100


def clamp(x: float) -> float:
    return max(-1.0, min(1.0, x))


def write_wav_mono(path: Path, samples: list[float]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with wave.open(str(path), "w") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(SR)
        frames = bytearray()
        for s in samples:
            v = int(clamp(s) * 32767)
            frames += struct.pack("<h", v)
        w.writeframes(frames)


def write_wav_stereo(path: Path, left: list[float], right: list[float]) -> None:
    n = min(len(left), len(right))
    path.parent.mkdir(parents=True, exist_ok=True)
    with wave.open(str(path), "w") as w:
        w.setnchannels(2)
        w.setsampwidth(2)
        w.setframerate(SR)
        frames = bytearray()
        for i in range(n):
            for s in (left[i], right[i]):
                v = int(clamp(s) * 32767)
                frames += struct.pack("<h", v)
        w.writeframes(frames)


def env_adsr(t: float, a: float, d: float, s: float, r: float, dur: float) -> float:
    if t < 0:
        return 0.0
    if t < a:
        return t / a
    if t < a + d:
        return 1.0 - (1.0 - s) * ((t - a) / d)
    if t < dur - r:
        return s
    if t < dur:
        return s * (1.0 - (t - (dur - r)) / r)
    return 0.0


def sine(freq: float, t: float, phase: float = 0.0) -> float:
    return math.sin(2 * math.pi * freq * t + phase)


def soft_pad(freq: float, t: float, vol: float = 1.0) -> float:
    return vol * (
        0.55 * sine(freq, t)
        + 0.25 * sine(freq * 2.01, t, 0.3)
        + 0.12 * sine(freq * 3.02, t, 0.7)
    )


def noise_sample(rng: random.Random) -> float:
    return rng.uniform(-1, 1)


def lowpass(prev: float, x: float, coeff: float = 0.92) -> float:
    return prev * coeff + x * (1 - coeff)


def gen_bgm_menu(seconds: float = 56.0) -> tuple[list[float], list[float]]:
    """Calm lounge loop — Am / F / C / G soft pads + gentle pulse."""
    n = int(seconds * SR)
    left, right = [0.0] * n, [0.0] * n
    rng = random.Random(42)
    # Chord roots (Hz) per bar @ 72 BPM, 4 bars
    progression = [
        (220.0, 261.63, 329.63),  # Am
        (174.61, 220.0, 261.63),  # F
        (261.63, 329.63, 392.0),  # C
        (196.0, 246.94, 293.66),  # G
    ]
    bar = 2.0
    lp_l = lp_r = 0.0
    for i in range(n):
        t = i / SR
        bar_i = int(t / bar) % 4
        chord = progression[bar_i]
        local = (t % bar) / bar
        swell = 0.5 + 0.5 * math.sin(math.pi * local)
        pad = sum(soft_pad(f, t, 0.14 / len(chord)) for f in chord) * swell
        # Soft sub
        sub_f = chord[0] / 2
        sub = 0.08 * sine(sub_f, t) * swell
        # Quiet shimmer
        shimmer = 0.025 * sine(880 + 40 * math.sin(t * 0.2), t)
        # Gentle closed hat every half beat
        beat = (t * (72 / 60)) % 1.0
        hat = 0.0
        if beat < 0.04 or (0.5 <= beat < 0.54):
            hat = 0.035 * (1 - beat % 0.04 / 0.04) * noise_sample(rng)
        sample = (pad + sub + shimmer + hat) * 0.85
        # Stereo width
        pan = 0.15 * math.sin(t * 0.07)
        lp_l = lowpass(lp_l, sample * (1 - pan))
        lp_r = lowpass(lp_r, sample * (1 + pan))
        left[i] = lp_l
        right[i] = lp_r
    # Fade in/out for seamless loop
    fade = int(0.8 * SR)
    for i in range(fade):
        f = i / fade
        left[i] *= f
        right[i] *= f
        left[-1 - i] *= f
        right[-1 - i] *= f
    return left, right


def gen_bgm_gameplay(seconds: float = 48.0) -> tuple[list[float], list[float]]:
    """Slightly brighter loop for matches — still soft, not distracting."""
    n = int(seconds * SR)
    left, right = [0.0] * n, [0.0] * n
    rng = random.Random(7)
    progression = [
        (246.94, 311.13, 369.99),  # Bm
        (220.0, 277.18, 329.63),
        (293.66, 369.99, 440.0),
        (261.63, 329.63, 392.0),
    ]
    bar = 1.5
    lp_l = lp_r = 0.0
    for i in range(n):
        t = i / SR
        bar_i = int(t / bar) % 4
        chord = progression[bar_i]
        local = (t % bar) / bar
        swell = 0.45 + 0.55 * math.sin(math.pi * local) ** 0.8
        pad = sum(soft_pad(f, t, 0.11 / len(chord)) for f in chord) * swell
        pulse = 0.06 * sine(chord[0] / 2, t) * (0.6 + 0.4 * math.sin(t * 4))
        beat = (t * (88 / 60)) % 1.0
        hat = 0.0
        if beat < 0.035:
            hat = 0.05 * (1 - beat / 0.035) * noise_sample(rng)
        arp = 0.04 * sine(chord[1] * 2, t * 2 + local * 2)
        sample = (pad + pulse + hat + arp) * 0.9
        pan = 0.22 * math.sin(t * 0.11 + 1)
        lp_l = lowpass(lp_l, sample * (1 - pan), 0.88)
        lp_r = lowpass(lp_r, sample * (1 + pan), 0.88)
        left[i] = lp_l
        right[i] = lp_r
    fade = int(0.6 * SR)
    for i in range(fade):
        f = i / fade
        left[i] *= f
        right[i] *= f
        left[-1 - i] *= f
        right[-1 - i] *= f
    return left, right


def tone_burst(freq: float, dur: float, vol: float = 0.5, decay: float = 8.0) -> list[float]:
    n = int(dur * SR)
    out = []
    for i in range(n):
        t = i / SR
        e = math.exp(-decay * t)
        out.append(vol * e * sine(freq, t))
    return out


def noise_burst(dur: float, vol: float = 0.4, decay: float = 12.0) -> list[float]:
    n = int(dur * SR)
    rng = random.Random(99)
    out = []
    lp = 0.0
    for i in range(n):
        t = i / SR
        e = math.exp(-decay * t)
        lp = lowpass(lp, noise_sample(rng), 0.85)
        out.append(vol * e * lp)
    return out


def mix(*tracks: list[float]) -> list[float]:
    n = max(len(t) for t in tracks)
    out = [0.0] * n
    for tr in tracks:
        for i, v in enumerate(tr):
            out[i] += v
    return out


def sfx_tap() -> list[float]:
    return mix(tone_burst(920, 0.05, 0.35, 35), tone_burst(480, 0.04, 0.2, 40))


def sfx_tick() -> list[float]:
    return tone_burst(1200, 0.03, 0.25, 50)


def sfx_success() -> list[float]:
    return mix(
        tone_burst(523.25, 0.12, 0.3, 6),
        tone_burst(659.25, 0.14, 0.28, 5),
        tone_burst(783.99, 0.18, 0.25, 4),
    )


def sfx_win() -> list[float]:
    parts = []
    for f, d in [(523.25, 0.15), (659.25, 0.15), (783.99, 0.2), (1046.5, 0.35)]:
        parts.append(tone_burst(f, d, 0.32, 3.5))
    return mix(*parts)


def sfx_lose() -> list[float]:
    return mix(tone_burst(392, 0.25, 0.35, 4), tone_burst(311, 0.35, 0.3, 3))


def sfx_ball_hit() -> list[float]:
    return mix(noise_burst(0.08, 0.45, 18), tone_burst(180, 0.06, 0.35, 25))


def sfx_cue_hit() -> list[float]:
    return mix(tone_burst(320, 0.04, 0.4, 30), noise_burst(0.03, 0.15, 40))


def sfx_cushion() -> list[float]:
    return mix(noise_burst(0.06, 0.35, 15), tone_burst(140, 0.05, 0.25, 20))


def sfx_pocket() -> list[float]:
    return mix(tone_burst(220, 0.2, 0.4, 5), noise_burst(0.1, 0.25, 10))


def sfx_card() -> list[float]:
    return mix(noise_burst(0.05, 0.3, 25), tone_burst(640, 0.06, 0.2, 20))


def sfx_foul() -> list[float]:
    return mix(tone_burst(180, 0.2, 0.4, 5), tone_burst(150, 0.25, 0.35, 4))


def sfx_extra() -> list[float]:
    return tone_burst(880, 0.15, 0.35, 8)


def sfx_turn() -> list[float]:
    return tone_burst(660, 0.1, 0.28, 10)


def sfx_match_start() -> list[float]:
    return mix(
        tone_burst(440, 0.2, 0.3, 4),
        tone_burst(554.37, 0.2, 0.28, 4),
        tone_burst(659.25, 0.35, 0.32, 3),
    )


def sfx_dice_roll() -> list[float]:
    rng = random.Random(1)
    n = int(0.35 * SR)
    out = []
    lp = 0.0
    for i in range(n):
        t = i / SR
        lp = lowpass(lp, noise_sample(rng), 0.7)
        out.append(0.35 * lp * (0.5 + 0.5 * math.sin(t * 40)))
    return out


def sfx_dice_land() -> list[float]:
    return mix(tone_burst(400, 0.08, 0.35, 12), noise_burst(0.04, 0.2, 25))


def sfx_hop() -> list[float]:
    return tone_burst(520, 0.06, 0.3, 18)


def sfx_token_out() -> list[float]:
    return mix(tone_burst(600, 0.1, 0.32, 8), tone_burst(800, 0.12, 0.25, 7))


def sfx_capture() -> list[float]:
    return mix(sfx_foul(), tone_burst(300, 0.15, 0.25, 6))


def sfx_token_home() -> list[float]:
    return sfx_success()


def sfx_no_move() -> list[float]:
    return tone_burst(220, 0.18, 0.3, 6)


def sfx_chat_pop() -> list[float]:
    return tone_burst(740, 0.07, 0.28, 15)


SFX = {
    "tap": sfx_tap,
    "tick": sfx_tick,
    "success": sfx_success,
    "win": sfx_win,
    "lose": sfx_lose,
    "ball_hit": sfx_ball_hit,
    "cue_hit": sfx_cue_hit,
    "cushion": sfx_cushion,
    "pocket": sfx_pocket,
    "card": sfx_card,
    "foul": sfx_foul,
    "extra": sfx_extra,
    "turn": sfx_turn,
    "match_start": sfx_match_start,
    "dice_roll": sfx_dice_roll,
    "dice_land": sfx_dice_land,
    "hop": sfx_hop,
    "token_out": sfx_token_out,
    "capture": sfx_capture,
    "token_home": sfx_token_home,
    "no_move": sfx_no_move,
    "chat_pop": sfx_chat_pop,
}


def main() -> None:
    OUT.mkdir(parents=True, exist_ok=True)
    print("Writing BGM...")
    l, r = gen_bgm_menu()
    write_wav_stereo(OUT / "bgm_menu.wav", l, r)
    l, r = gen_bgm_gameplay()
    write_wav_stereo(OUT / "bgm_gameplay.wav", l, r)
    print("Writing SFX...")
    for name, fn in SFX.items():
        write_wav_mono(OUT / f"{name}.wav", fn())
        print(f"  {name}.wav")
    print(f"Done — {len(SFX) + 2} files in {OUT}")


if __name__ == "__main__":
    main()
