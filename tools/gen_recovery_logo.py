#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
# Noxis OS – Copyright (C) 2026 3rr0r (Real3rr0r303YT) – Made by 3rr0r303YT on TikTok
#
# Noxis logos for the recovery (bootable/recovery/res-*/images/logo_image*.png),
# same layout and sizes as LineageOS' originals: pill outline, mark, "RECOVERY".
# logo_image_switch additionally shows the R (recovery) / F (fastboot) icons,
# fastbootd.png is the same in red with F active and "FASTBOOTD".
#   gen_recovery_logo.py <out-dir>
import math, os, sys
from PIL import Image, ImageDraw, ImageFont

BLUE, WHITE, TEXT = (127, 168, 255), (240, 244, 250), (170, 190, 230)
RED, RTEXT = (215, 25, 33), (255, 120, 120)     # fastbootd: Nothing red
FONT = next((f for f in ("/usr/share/fonts/opentype/inter/Inter-SemiBold.otf",
                         "/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf") if os.path.exists(f)), None)
SIZES = {"mdpi": 256, "hdpi": 384, "xhdpi": 512, "xxhdpi": 768, "xxxhdpi": 1024}

def font(px):
    return ImageFont.truetype(FONT, px) if FONT else ImageFont.load_default()

def draw(switch, W, fb=False):
    K = 4; S = W * K / 768.0          # design units = original xxhdpi pixels
    im = Image.new("RGB", (W * K, int(W * K * 480 / 768)), (0, 0, 0)); d = ImageDraw.Draw(im)
    u = lambda v: v * S
    ACC = RED if fb else BLUE
    d.rounded_rectangle((u(4), u(132), u(764), u(348)), radius=u(108), outline=ACC, width=int(u(6)))
    # mark: open ring + N (diagonal blue)
    cx, cy, R, w = u(384), u(240), u(62), int(u(10))
    d.arc((cx - R - w / 2, cy - R - w / 2, cx + R + w / 2, cy + R + w / 2), start=-48, end=-81 + 360, fill=WHITE, width=w)
    for a in (-48, -81):
        x, y = cx + R * math.cos(math.radians(a)), cy + R * math.sin(math.radians(a))
        d.ellipse((x - w / 2, y - w / 2, x + w / 2, y + w / 2), fill=WHITE)
    nx, ny = u(22), u(28)
    pts = [(cx - nx, cy + ny), (cx - nx, cy - ny), (cx + nx, cy + ny), (cx + nx, cy - ny)]
    d.line([pts[0], pts[1]], fill=WHITE, width=w); d.line([pts[2], pts[3]], fill=WHITE, width=w)
    d.line([pts[1], pts[2]], fill=ACC, width=w)
    for p in pts:
        d.ellipse((p[0] - w / 2, p[1] - w / 2, p[0] + w / 2, p[1] + w / 2), fill=ACC if p in (pts[1], pts[2]) else WHITE)
    # RECOVERY, letter-spaced
    f = font(int(u(40))); x = u(384); word = "FASTBOOTD" if fb else "RECOVERY"; sp = u(14)
    widths = [d.textbbox((0, 0), c, font=f)[2] for c in word]
    total = sum(widths) + sp * (len(word) - 1); x -= total / 2
    for i, (c, cw) in enumerate(zip(word, widths)):
        col = (RED if i == len(word) - 1 else RTEXT) if fb else TEXT
        d.text((x, u(388)), c, font=f, fill=col); x += cw + sp
    if switch and fb:
        fr = font(int(u(36)))
        # R: diamond outline (inactive)
        x0, y0, r = u(112), u(240), u(44)
        d.polygon([(x0, y0 - r), (x0 + r, y0), (x0, y0 + r), (x0 - r, y0)], outline=WHITE, width=int(u(6)))
        bb = d.textbbox((0, 0), "R", font=fr); d.text((x0 - (bb[2] + bb[0]) / 2, y0 - (bb[3] + bb[1]) / 2), "R", font=fr, fill=WHITE)
        # F: filled red triangle (active), dot below
        x1, y1 = u(656), u(244)
        d.polygon([(x1, y1 - u(46)), (x1 + u(46), y1 + u(34)), (x1 - u(46), y1 + u(34))], fill=RED)
        bb = d.textbbox((0, 0), "F", font=fr); d.text((x1 - (bb[2] + bb[0]) / 2, y1 + u(8) - (bb[3] + bb[1]) / 2), "F", font=fr, fill=WHITE)
        d.ellipse((x1 - u(6), u(308), x1 + u(6), u(320)), fill=WHITE)
    elif switch:
        # R: filled diamond (active), dot below
        x0, y0, r = u(112), u(240), u(44)
        d.polygon([(x0, y0 - r), (x0 + r, y0), (x0, y0 + r), (x0 - r, y0)], fill=BLUE)
        fr = font(int(u(36)))
        bb = d.textbbox((0, 0), "R", font=fr); d.text((x0 - (bb[2] + bb[0]) / 2, y0 - (bb[3] + bb[1]) / 2), "R", font=fr, fill=(0, 0, 0))
        d.ellipse((x0 - u(6), u(308), x0 + u(6), u(320)), fill=WHITE)
        # F: triangle outline
        x1, y1 = u(656), u(244)
        d.polygon([(x1, y1 - u(46)), (x1 + u(46), y1 + u(34)), (x1 - u(46), y1 + u(34))], outline=WHITE, width=int(u(6)))
        bb = d.textbbox((0, 0), "F", font=fr); d.text((x1 - (bb[2] + bb[0]) / 2, y1 + u(8) - (bb[3] + bb[1]) / 2), "F", font=fr, fill=WHITE)
    return im.resize((W, int(W * 480 / 768)), Image.LANCZOS)

if __name__ == "__main__":
    out = sys.argv[1] if len(sys.argv) > 1 else "vendor/noxis/branding/recovery"
    for dens, W in SIZES.items():
        os.makedirs(f"{out}/res-{dens}/images", exist_ok=True)
        draw(False, W).save(f"{out}/res-{dens}/images/logo_image.png", optimize=True)
        draw(True, W).save(f"{out}/res-{dens}/images/logo_image_switch.png", optimize=True)
        draw(True, W, fb=True).save(f"{out}/res-{dens}/images/fastbootd.png", optimize=True)
    print("recovery + fastbootd logos →", out)
