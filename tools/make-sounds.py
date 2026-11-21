# Generates the 8-bit sound effects of MeeSnake (square / triangle waves, noise),
# in the spirit of old chip and MIDI game music. Python 3, no extra modules.
# Usage: python3 make-sounds.py outdir
import math, random, struct, sys, wave, os

RATE = 22050
out = sys.argv[1]
random.seed(7)

def note(n):            # MIDI note number -> Hz
    return 440.0 * 2 ** ((n - 69) / 12.0)

def square(f, t, duty=0.5):
    return 1.0 if (t * f) % 1.0 < duty else -1.0

def triangle(f, t):
    p = (t * f) % 1.0
    return 4 * p - 1 if p < 0.5 else 3 - 4 * p

def env(i, n, attack=0.004, release=0.03):
    t = i / RATE; T = n / RATE
    a = min(1.0, t / attack) if attack else 1.0
    r = min(1.0, (T - t) / release) if release else 1.0
    return max(0.0, min(a, r))

def tone(n, dur, wave_fn='sq', duty=0.5, vol=0.5, slide_to=None, release=0.03):
    cnt = int(dur * RATE); s = []
    for i in range(cnt):
        t = i / RATE
        f = note(n) if slide_to is None else note(n + (slide_to - n) * i / cnt)
        v = square(f, t, duty) if wave_fn == 'sq' else triangle(f, t)
        s.append(v * vol * env(i, cnt, release=release))
    return s

def noise(dur, vol=0.5, decay=8.0):
    cnt = int(dur * RATE); s = []; v = 0.0
    for i in range(cnt):
        if i % 3 == 0: v = random.uniform(-1, 1)      # lo-fi noise like old sound chips
        s.append(v * vol * math.exp(-decay * i / RATE))
    return s

def mix(a, b):
    n = max(len(a), len(b))
    return [(a[i] if i < len(a) else 0) + (b[i] if i < len(b) else 0) for i in range(n)]

def rest(dur):
    return [0.0] * int(dur * RATE)

def save(name, s):
    w = wave.open(os.path.join(out, name), 'wb')
    w.setnchannels(1); w.setsampwidth(2); w.setframerate(RATE)
    w.writeframes(b''.join(struct.pack('<h', int(max(-1, min(1, x)) * 32000)) for x in s))
    w.close()

# snake step: tiny "tick" and "tock"
save('move1.wav', tone(45, 0.022, duty=0.25, vol=0.35, release=0.012))
save('move2.wav', tone(40, 0.022, duty=0.25, vol=0.35, release=0.012))
# eating: two quick notes up
save('eat.wav', tone(84, 0.045, duty=0.25, vol=0.45) + tone(91, 0.07, duty=0.25, vol=0.45))
# bonus: fast arpeggio
save('bonus.wav', sum([tone(n, 0.045, duty=0.125, vol=0.45) for n in (84, 88, 91, 96, 100)], []) + tone(103, 0.09, duty=0.125, vol=0.4))
# crash (failure): noise hit + falling tone
save('crash.wav', mix(noise(0.35, 0.55, 9.0), tone(64, 0.42, duty=0.5, vol=0.35, slide_to=36, release=0.08)))
# game over: falling melody
melody = []
for n, d in ((67, 0.16), (64, 0.16), (60, 0.16), (55, 0.16), (54, 0.16), (53, 0.5)):
    melody += mix(tone(n, d, duty=0.5, vol=0.35, release=0.04), tone(n - 12, d, 'tri', vol=0.35, release=0.04))
save('gameover.wav', melody)
# new record: short fanfare
fan = []
for n, d in ((72, 0.1), (72, 0.1), (72, 0.1), (76, 0.22), (72, 0.12), (76, 0.12), (79, 0.5)):
    fan += mix(tone(n, d, duty=0.25, vol=0.33, release=0.03), tone(n - 24, d, 'tri', vol=0.35, release=0.03))
save('record.wav', fan)
