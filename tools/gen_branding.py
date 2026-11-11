#!/usr/bin/env python3
"""Erzeugt Noxis-OS-Branding: Logo, Bootanimation (Android-Format), Standard-Wallpaper.
Nur Pillow nötig. Alles prozedural gezeichnet – keine fremden Grafiken oder Schriften."""
import math, os, random, sys, zipfile, io
from PIL import Image, ImageDraw, ImageFilter

OUT = sys.argv[1] if len(sys.argv) > 1 else "out"
os.makedirs(OUT, exist_ok=True)
SS = 4                     # Supersampling für Kantenglättung
WHITE = (240, 243, 250)
ACCENT = (122, 162, 255)   # Noxis-Blau

def stroke_line(d, p, q, w, col):
    d.line([p, q], fill=col, width=w)
    r = w / 2
    for (x, y) in (p, q):
        d.ellipse([x - r, y - r, x + r, y + r], fill=col)

def draw_mark(size, progress=1.0, glow=0.0):
    """Noxis-Zeichen: offener Kreisring + N aus drei Strichen. progress 0..1 zeichnet es auf."""
    S = size * SS
    img = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    c = S / 2
    R = S * 0.40
    w = int(S * 0.045)
    # Ring: Lücke oben rechts (Start bei -50°), läuft im Uhrzeigersinn
    ring_p = min(1.0, progress / 0.6)
    if ring_p > 0:
        start, span = -40, 320 * ring_p
        d.arc([c - R, c - R, c + R, c + R], start=start, end=start + span, fill=WHITE, width=w)
        # runde Enden
        for ang in (start, start + span):
            a = math.radians(ang)
            x, y = c + (R - w / 2) * math.cos(a), c + (R - w / 2) * math.sin(a)
            d.ellipse([x - w / 2, y - w / 2, x + w / 2, y + w / 2], fill=WHITE)
    # N: links hoch, Diagonale runter, rechts hoch – Diagonale in Akzentfarbe
    n_p = max(0.0, (progress - 0.35) / 0.65)
    h, bw = S * 0.30, S * 0.20
    x0, x1, yt, yb = c - bw / 2, c + bw / 2, c - h / 2, c + h / 2
    segs = [((x0, yb), (x0, yt), WHITE), ((x0, yt), (x1, yb), ACCENT), ((x1, yb), (x1, yt), WHITE)]
    for i, (p, q, col) in enumerate(segs):
        t = max(0.0, min(1.0, n_p * 3 - i))
        if t > 0:
            stroke_line(d, p, (p[0] + (q[0] - p[0]) * t, p[1] + (q[1] - p[1]) * t), w, col)
    img = img.resize((size, size), Image.LANCZOS)
    if glow > 0:
        g = img.filter(ImageFilter.GaussianBlur(size * 0.03))
        a = g.split()[3].point(lambda v: int(v * glow))
        tint = Image.new("RGBA", img.size, ACCENT + (0,))
        tint.putalpha(a)
        base = Image.new("RGBA", img.size, (0, 0, 0, 0))
        base.alpha_composite(tint)
        base.alpha_composite(img)
        img = base
    return img

def letter_strokes(ch, x, y, w, h):
    """Geometrische Großbuchstaben als Liniensegmente / Bögen."""
    L = []
    if ch == "N":
        L += [("l", (x, y + h), (x, y)), ("l", (x, y), (x + w, y + h)), ("l", (x + w, y + h), (x + w, y))]
    elif ch == "O":
        L += [("e", (x, y, x + w * 1.15, y + h))]
    elif ch == "X":
        L += [("l", (x, y), (x + w, y + h)), ("l", (x + w, y), (x, y + h))]
    elif ch == "I":
        L += [("l", (x, y), (x, y + h))]
    elif ch == "S":
        r = h / 4
        pts = []
        # oberer Bogen: von rechts oben (30°) gegen den Uhrzeigersinn bis links Mitte-oben
        for k in range(0, 41):
            a = math.radians(-30 - k * (240 / 40))
            pts.append((x + w / 2 + (w / 2) * math.cos(a), y + r + r * math.sin(a)))
        # unterer Bogen: von oben Mitte im Uhrzeigersinn bis links unten (210°)
        for k in range(0, 41):
            a = math.radians(-90 + k * (240 / 40))
            pts.append((x + w / 2 + (w / 2) * math.cos(a), y + 3 * r + r * math.sin(a)))
        L += [("p", pts)]
    return L

def draw_wordmark(width, alpha=1.0):
    S = SS
    H = int(width * 0.16) * S
    W = width * S
    img = Image.new("RGBA", (W, H + 20 * S), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    lw = max(2, int(H * 0.085))
    text = "NOXIS"
    widths = {"N": 0.62, "O": 0.62, "X": 0.62, "I": 0.0, "S": 0.58}
    gap = H * 0.42
    total = sum(widths[c] * H for c in text) + gap * (len(text) - 1) + H * 0.09
    x = (W - total) / 2
    y = 10 * S
    col = WHITE + (int(255 * alpha),)
    for ch in text:
        cw = widths[ch] * H
        for s in letter_strokes(ch, x, y, cw, H):
            if s[0] == "l":
                stroke_line(d, s[1], s[2], lw, col)
            elif s[0] == "e":
                d.ellipse(s[1], outline=col, width=lw)
            elif s[0] == "a":
                d.arc(s[1], start=s[2], end=s[3], fill=col, width=lw)
            elif s[0] == "p":
                for p, q in zip(s[1], s[1][1:]):
                    stroke_line(d, p, q, lw, col)
        x += cw * (1.15 if ch == "O" else 1) + gap
    return img.resize((width, (H + 20 * S) // S), Image.LANCZOS)

# ---------------------------------------------------------------- Bootanimation
def bootanimation(path):
    FW, FH, FPS = 720, 900, 30
    mark_sz, wm_w = 420, 440
    def frame(progress, wm_alpha, glow):
        f = Image.new("RGB", (FW, FH), (0, 0, 0))
        m = draw_mark(mark_sz, progress, glow)
        f.paste(m, ((FW - mark_sz) // 2, 150), m)
        if wm_alpha > 0:
            wm = draw_wordmark(wm_w, wm_alpha)
            f.paste(wm, ((FW - wm_w) // 2, 150 + mark_sz + 70), wm)
        return f
    ease = lambda t: 1 - (1 - t) ** 3
    part0, part1 = [], []
    for i in range(45):                                   # 1,5 s: Zeichen zeichnet sich
        t = i / 44
        part0.append(frame(ease(min(1, t / 0.75)), max(0, (t - 0.6) / 0.4), 0))
    for i in range(60):                                   # 2 s Schleife: sanftes Leuchten
        g = 0.5 - 0.5 * math.cos(2 * math.pi * i / 60)
        part1.append(frame(1, 1, 0.9 * g))
    buf = io.BytesIO()
    with zipfile.ZipFile(path, "w", zipfile.ZIP_STORED) as z:
        z.writestr("desc.txt", f"{FW} {FH} {FPS}\nc 1 0 part0 #000000\nc 0 0 part1 #000000\n")
        for name, frames in (("part0", part0), ("part1", part1)):
            for i, im in enumerate(frames):
                b = io.BytesIO()
                im.quantize(colors=96, method=Image.MEDIANCUT, dither=Image.NONE).save(b, "PNG", optimize=True)
                z.writestr(f"{name}/{i:05d}.png", b.getvalue())
    return part0[-1], part1[30]

# ---------------------------------------------------------------- Wallpaper
def wallpaper(path, W=1440, H=3120):
    rnd = random.Random(303)
    img = Image.new("RGB", (W, H))
    px = img.load()
    for y in range(H):
        t = y / H
        r = int(4 + 3 * t); g = int(5 + 5 * t); b = int(9 + 14 * t)
        for x in range(0, W):
            px[x, y] = (r, g, b)
    glow = Image.new("RGB", (W, H), (0, 0, 0))
    gd = ImageDraw.Draw(glow)
    gd.ellipse([-W * 0.4, H * 0.62, W * 0.9, H * 1.3], fill=(14, 26, 70))
    gd.ellipse([W * 0.5, -H * 0.2, W * 1.5, H * 0.3], fill=(10, 16, 42))
    glow = glow.filter(ImageFilter.GaussianBlur(W * 0.22))
    from PIL import ImageChops
    img = ImageChops.add(img, glow)
    # feine konzentrische Linien um das Noxis-Zeichen (sehr dezent)
    lines = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    ld = ImageDraw.Draw(lines)
    cx, cy = W * 0.5, H * 0.58
    for i in range(1, 26):
        R = i * W * 0.055
        ld.ellipse([cx - R, cy - R, cx + R, cy + R], outline=(140, 170, 255, max(4, 30 - i)), width=3)
    img = img.convert("RGBA"); img.alpha_composite(lines)
    # Körnung gegen Banding
    noise = Image.effect_noise((W, H), 10).convert("L").point(lambda v: v // 22)
    img = ImageChops.add(img.convert("RGB"), Image.merge("RGB", (noise, noise, noise)))
    img.save(path, "PNG", optimize=True)
    return img

if __name__ == "__main__":
    logo = draw_mark(1024, 1.0)
    bg = Image.new("RGBA", (1024, 1024), (0, 0, 0, 255)); bg.alpha_composite(logo); bg.convert("RGB").save(f"{OUT}/noxis-logo.png")
    a, b = bootanimation(f"{OUT}/bootanimation.zip")
    a.save(f"{OUT}/preview-boot-end.png"); b.save(f"{OUT}/preview-boot-glow.png")
    wallpaper(f"{OUT}/default_wallpaper.png")
    print("ok")
