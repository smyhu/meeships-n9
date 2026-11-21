# MeeShips own sounds in the games-common style (functions copied from games-common/make-sounds.py) (square / triangle waves, noise),
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


# shot: short falling "pew"
save('shot.wav', tone(88, 0.14, duty=0.25, vol=0.32, slide_to=64, release=0.02))
# miss: water splash = soft noise burst with a low wobble
save('splash.wav', mix(noise(0.32, 0.30, 9), tone(50, 0.18, 'tri', vol=0.25, slide_to=43)))
# hit: bang = loud noise + low thump
save('hit.wav', mix(noise(0.38, 0.55, 10), tone(40, 0.22, 'tri', vol=0.45, slide_to=28)))
# sunk: bang, then a falling bubbling line
sk = mix(noise(0.30, 0.55, 9), tone(40, 0.2, 'tri', vol=0.45, slide_to=28))
for k in range(7): sk += tone(70 - k * 4, 0.06, duty=0.5, vol=0.28, slide_to=66 - k * 4, release=0.01)
sk += mix(noise(0.25, 0.3, 12), tone(31, 0.25, 'tri', vol=0.35))
save('sunk.wav', sk)
# start of a battle: short call
st = []
for n, d in ((67, 0.1), (67, 0.1), (72, 0.2), (67, 0.1), (72, 0.1), (76, 0.34)):
    st += mix(tone(n, d, duty=0.5, vol=0.3, release=0.03), tone(n - 24, d, 'tri', vol=0.36, release=0.03))
save('start.wav', st)
