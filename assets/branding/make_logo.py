"""Generates the Rifa Master logo: gold ticket with star on a navy/royal-blue tile."""
import math, sys
from PIL import Image, ImageDraw, ImageFilter, ImageChops

NAVY = (15, 23, 42)        # #0F172A  (AppTheme.primaryDark)
ROYAL = (30, 58, 138)      # #1E3A8A
BLUE = (37, 99, 235)       # #2563EB  (AppTheme.primaryBlue)
GOLD_L = (253, 224, 71)    # #FDE047
GOLD = (245, 158, 11)      # #F59E0B  (AppTheme.accentAmber)
GOLD_D = (180, 83, 9)      # #B45309

def lerp(a, b, t): return tuple(int(a[i] + (b[i] - a[i]) * t) for i in range(3))

def gradient(size, c1, c2, diagonal=True):
    w, h = size
    g = Image.new('RGB', size)
    px = g.load()
    for y in range(h):
        for x in range(w):
            t = ((x / w) * 0.35 + (y / h) * 0.65) if diagonal else y / h
            px[x, y] = lerp(c1, c2, min(1, max(0, t)))
    return g

def rounded_mask(size, radius):
    m = Image.new('L', size, 0)
    ImageDraw.Draw(m).rounded_rectangle([0, 0, size[0] - 1, size[1] - 1], radius=radius, fill=255)
    return m

def star_points(cx, cy, r_out, r_in, n=5, rot=-90):
    pts = []
    for i in range(n * 2):
        r = r_out if i % 2 == 0 else r_in
        a = math.radians(rot + i * 180 / n)
        pts.append((cx + r * math.cos(a), cy + r * math.sin(a)))
    return pts

def ticket_layer(S):
    """Ticket drawn upright on an S x S transparent canvas, then rotated."""
    layer = Image.new('RGBA', (S, S), (0, 0, 0, 0))
    tw, th = int(S * 0.74), int(S * 0.46)
    x0, y0 = (S - tw) // 2, (S - th) // 2
    # ticket body mask with side notches
    body = Image.new('L', (S, S), 0)
    d = ImageDraw.Draw(body)
    d.rounded_rectangle([x0, y0, x0 + tw, y0 + th], radius=int(S * 0.05), fill=255)
    nr = int(th * 0.16)
    cy = y0 + th // 2
    d.ellipse([x0 - nr, cy - nr, x0 + nr, cy + nr], fill=0)
    d.ellipse([x0 + tw - nr, cy - nr, x0 + tw + nr, cy + nr], fill=0)
    # perforation (stub on the left ~30%)
    px = x0 + int(tw * 0.30)
    dash, gap = int(th * 0.075), int(th * 0.055)
    y = y0 + int(th * 0.10)
    while y < y0 + th - int(th * 0.10):
        d.rounded_rectangle([px - int(S * 0.006), y, px + int(S * 0.006), min(y + dash, y0 + th - int(th * 0.1))], radius=int(S * 0.006), fill=0)
        y += dash + gap
    # gold gradient fill
    fill = gradient((S, S), GOLD_L, GOLD)
    layer.paste(fill, (0, 0), body)
    # inner hairline border for depth
    edge = body.filter(ImageFilter.MaxFilter(3))
    inner = ImageChops.subtract(body, body.filter(ImageFilter.MinFilter(max(3, S // 170 * 2 + 1))))
    shade = Image.new('RGBA', (S, S), GOLD_D + (140,))
    layer.paste(shade, (0, 0), inner)
    # star on the main part (navy)
    sd = ImageDraw.Draw(layer)
    scx = x0 + int(tw * 0.30) + int(tw * 0.70 / 2)
    sr = int(th * 0.30)
    sd.polygon(star_points(scx, cy, sr, sr * 0.45), fill=NAVY + (255,))
    # small "N°" dots on stub
    stub_cx = x0 + int(tw * 0.15)
    for k, dy in enumerate((-0.18, 0, 0.18)):
        r = int(th * 0.045)
        sd.ellipse([stub_cx - r, cy + int(th * dy) - r, stub_cx + r, cy + int(th * dy) + r], fill=NAVY + (255,))
    return layer.rotate(-14, resample=Image.BICUBIC, center=(S / 2, S / 2))

def make_icon(size, maskable=False, transparent_bg=False):
    SS = 4  # supersampling
    S = size * SS
    if transparent_bg:
        base = Image.new('RGBA', (S, S), (0, 0, 0, 0))
    else:
        bg = gradient((S, S), BLUE, NAVY).convert('RGBA')
        # soft highlight top-left
        glow = Image.new('L', (S, S), 0)
        ImageDraw.Draw(glow).ellipse([-S * 0.3, -S * 0.45, S * 0.9, S * 0.55], fill=70)
        glow = glow.filter(ImageFilter.GaussianBlur(S * 0.08))
        bg = Image.composite(Image.new('RGBA', (S, S), (255, 255, 255, 255)), bg, glow)
        base = Image.new('RGBA', (S, S), (0, 0, 0, 0))
        mask = Image.new('L', (S, S), 255) if maskable else rounded_mask((S, S), int(S * 0.225))
        base.paste(bg, (0, 0), mask)
    # ticket scaled into safe zone
    scale = 0.70 if maskable else (1.0 if transparent_bg else 0.92)
    T = int(S * scale)
    tl = ticket_layer(T)
    # drop shadow
    if not transparent_bg:
        shadow = Image.new('RGBA', (T, T), (0, 0, 0, 0))
        shadow.putalpha(tl.split()[3].point(lambda a: int(a * 0.45)))
        shadow = shadow.filter(ImageFilter.GaussianBlur(T * 0.02))
        base.alpha_composite(shadow, ((S - T) // 2, (S - T) // 2 + int(S * 0.02)))
    base.alpha_composite(tl, ((S - T) // 2, (S - T) // 2))
    return base.resize((size, size), Image.LANCZOS)

if __name__ == '__main__':
    out = sys.argv[1]
    make_icon(1024).save(f'{out}/icon_1024.png')
    make_icon(1024, maskable=True).save(f'{out}/icon_maskable_1024.png')
    make_icon(1024, transparent_bg=True).save(f'{out}/logo_mark_1024.png')
