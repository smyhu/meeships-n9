# MeeShips icon variants: raw 8-bit battleships, project background + N9 mask (dev\00-icons style).
# Usage: python3 meeships-icon.py background80.png n9mask80.png outdir
from PIL import Image, ImageDraw, ImageFilter
import sys, os
K = 8; W = 80 * K
LIGHT = (231, 255, 205); GLOW = (120, 170, 100)
base = Image.open(sys.argv[1]).convert('RGBA'); mask = Image.open(sys.argv[2]).convert('L'); out = sys.argv[3]

def sq(d, x, y, s):
    d.rectangle([x * K, y * K, (x + s) * K - 1, (y + s) * K - 1], fill=255)
def frame(d, x, y, s, t):
    for r in ([x, y, x + s, y + t], [x, y + s - t, x + s, y + s], [x, y, x + t, y + s], [x + s - t, y, x + s, y + s]):
        d.rectangle([r[0] * K, r[1] * K, r[2] * K - 1, r[3] * K - 1], fill=255)

def pictogram(v):
    m = Image.new('L', (W, W), 0); d = ImageDraw.Draw(m)
    if v == 'a':      # one big four-square ship
        for k in range(4): sq(d, 10 + k * 15, 33, 13)
    elif v == 'b':    # the whole fleet 4-3-2-1, stacked
        for row, n in enumerate((4, 3, 2, 1)):
            for k in range(n): sq(d, 14 + k * 13, 13 + row * 14, 11)
    elif v == 'c':    # aim brackets on the middle square of a three-square ship
        for k in range(3): sq(d, 10 + k * 21, 33, 15)
        x0, y0, x1, y1, t, L = 27, 29, 50, 52, 2, 7
        for (cx, cy, sx, sy) in ((x0, y0, 1, 1), (x1, y0, -1, 1), (x0, y1, 1, -1), (x1, y1, -1, -1)):
            hx = (cx, cx + sx * L); vy = (cy, cy + sy * L)
            d.rectangle([min(hx) * K, (cy if sy > 0 else cy - t) * K, max(hx) * K - 1, ((cy + t) if sy > 0 else cy) * K - 1], fill=255)
            d.rectangle([(cx if sx > 0 else cx - t) * K, min(vy) * K, ((cx + t) if sx > 0 else cx) * K - 1, max(vy) * K - 1], fill=255)
    elif v == 'd':    # sea grid: ship, misses and a hit (hollow square)
        cell = 14
        for gy in range(4):
            for gx in range(4):
                x = 13 + gx * cell; y = 13 + gy * cell
                if gy == 1 and gx in (0, 1, 2): sq(d, x, y, 12)
                elif (gx, gy) == (3, 1): frame(d, x, y, 12, 3)
                elif (gx, gy) in ((1, 3), (3, 3), (0, 0), (2, 2)): sq(d, x + 4, y + 4, 4)
    return m

def make(v):
    img = base.resize((W, W), Image.BICUBIC)
    m = pictogram(v)
    gl = m.filter(ImageFilter.GaussianBlur(K * 1.6)).point(lambda x: int(x * .55))
    img = Image.composite(Image.new('RGBA', (W, W), GLOW + (255,)), img, gl)
    small = img.resize((80, 80), Image.LANCZOS)
    cell = m.resize((80, 80), Image.NEAREST)
    small = Image.composite(Image.new('RGBA', (80, 80), LIGHT + (255,)), small, cell)
    small.putalpha(mask); return small

icons = {}
for v in 'abcd':
    icons[v] = make(v); icons[v].save(os.path.join(out, 'meeships80-%s.png' % v))
sheet = Image.new('RGBA', (4 * 220 + 20, 330), (0, 0, 0, 255)); d = ImageDraw.Draw(sheet)
for i, v in enumerate('abcd'):
    sheet.alpha_composite(icons[v].resize((200, 200), Image.NEAREST), (20 + i * 220, 20))
    sheet.alpha_composite(icons[v], (80 + i * 220, 230))
    d.text((20 + i * 220, 312), v.upper(), fill=(200, 200, 200))
sheet.save(os.path.join(out, 'meeships-icon-preview.png'))
