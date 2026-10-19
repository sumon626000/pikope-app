import math, random, struct, wave, sys, os
SR = 44100
OUT = sys.argv[1]
random.seed(7)

def save(name, samples):
    peak = max(1e-9, max(abs(s) for s in samples))
    k = 0.89 / peak
    with wave.open(os.path.join(OUT, name + '.wav'), 'wb') as w:
        w.setnchannels(1); w.setsampwidth(2); w.setframerate(SR)
        w.writeframes(b''.join(struct.pack('<h', int(max(-1, min(1, s * k)) * 32767)) for s in samples))

def silence(sec): return [0.0] * int(SR * sec)

def mix(dst, src, at):
    i0 = int(at * SR)
    if len(dst) < i0 + len(src): dst.extend([0.0] * (i0 + len(src) - len(dst)))
    for i, v in enumerate(src): dst[i0 + i] += v
    return dst

def lowpass(x, a):
    y, p = [], 0.0
    for v in x:
        p += a * (v - p); y.append(p)
    return y

def highpass(x, a):
    lp = lowpass(x, a); return [v - l for v, l in zip(x, lp)]

def click(dur, f1, f2, decay, noise=0.5, gain=1.0):
    n = int(SR * dur); out = []
    for i in range(n):
        t = i / SR; e = math.exp(-t * decay)
        v = (math.sin(2 * math.pi * f1 * t) * 0.6 + math.sin(2 * math.pi * f2 * t) * 0.4) * (1 - noise)
        v += (random.random() * 2 - 1) * noise * math.exp(-t * decay * 2.5)
        out.append(v * e * gain)
    return out

def tone(f0, f1, dur, decay=6.0, attack=0.004, harmonics=(1.0, 0.3, 0.12), gain=1.0):
    n = int(SR * dur); out = []; ph = 0.0
    for i in range(n):
        t = i / SR; f = f0 + (f1 - f0) * (t / dur)
        ph += 2 * math.pi * f / SR
        env = min(1.0, t / attack) * math.exp(-t * decay)
        out.append(sum(a * math.sin(ph * (h + 1)) for h, a in enumerate(harmonics)) * env * gain)
    return out

# Dice shaken in a cup and thrown: a burst of hard little clacks.
dice = silence(0.62)
t = 0.0
while t < 0.5:
    f = random.uniform(1800, 3400)
    mix(dice, click(0.03, f, f * 1.47, random.uniform(140, 220), noise=0.55, gain=random.uniform(0.35, 1.0) * (1 - t * 0.6)), t)
    t += random.uniform(0.018, 0.055)
save('dice_roll', highpass(dice, 0.02))

# Dice settling on the board: two quick knocks.
land = silence(0.2)
mix(land, click(0.08, 900, 1500, 70, noise=0.35, gain=1.0), 0)
mix(land, click(0.06, 1100, 1800, 90, noise=0.35, gain=0.55), 0.07)
save('dice_land', land)

# One hop of a token: a short wooden "tok".
save('hop', tone(980, 760, 0.09, decay=45, attack=0.002, harmonics=(1.0, 0.45, 0.15)))

# Token leaves the yard: rising pop.
save('token_out', tone(380, 980, 0.2, decay=12, attack=0.003, harmonics=(1.0, 0.35, 0.1)))

# Capture: a whoosh down plus a punchy thud.
cap = silence(0.55)
wh = []
for i in range(int(SR * 0.32)):
    tt = i / SR; wh.append((random.random() * 2 - 1) * math.sin(math.pi * tt / 0.32) ** 2 * 0.7)
mix(cap, lowpass(wh, 0.18), 0)
mix(cap, tone(190, 70, 0.32, decay=11, attack=0.002, harmonics=(1.0, 0.5, 0.2), gain=1.2), 0.2)
mix(cap, click(0.06, 600, 900, 60, noise=0.6, gain=0.8), 0.2)
save('capture', cap)

# Token reaches home: bright arpeggio.
home = silence(0.7)
for k, f in enumerate([1046.5, 1318.5, 1568.0, 2093.0]):
    mix(home, tone(f, f, 0.45, decay=7, harmonics=(1.0, 0.25, 0.08), gain=0.8), k * 0.075)
save('token_home', home)

# No legal move / turn lost: two soft low boops.
nm = silence(0.45)
mix(nm, tone(330, 300, 0.16, decay=14, harmonics=(1.0, 0.2)), 0)
mix(nm, tone(262, 230, 0.22, decay=10, harmonics=(1.0, 0.2)), 0.17)
save('no_move', nm)

# Chat bubble pop.
save('chat_pop', tone(620, 1350, 0.1, decay=28, attack=0.002, harmonics=(1.0, 0.15)))

# Lose: falling three notes.
lose = silence(1.1)
for k, f in enumerate([523.3, 440.0, 349.2]):
    mix(lose, tone(f, f * 0.98, 0.5, decay=4.5, harmonics=(1.0, 0.3, 0.1), gain=0.8), k * 0.22)
save('lose', lose)
print('done')
