#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
# Noxis OS – Made by 3rr0r303YT on TikTok
#
# Writes the Lottie animation of the SetupWizard welcome screen
# (org.lineageos.setupwizard raw/lottie_welcome) with the Noxis mark:
# open ring + N with a blue diagonal, slowly "breathing" like the original.
# Usage: gen_setup_lottie.py <out.json> [preview.png]
import json
import math
import sys

W, H, FR, OP = 512, 260, 60, 150          # same canvas/timing as LineageOS
CX, CY = 256.0, 130.0
R, SW = 88.0, 14.0                        # ring radius, stroke width
NX, NY = 31.0, 40.0                       # half width/height of the N
GAP = (-81.0, -48.0)                      # ring opening (degrees, y down)
RING = (0x7F / 255, 0xA8 / 255, 0xFF / 255, 1)   # Noxis blue – readable on dark and light
DIAG = (0x3D / 255, 0x6B / 255, 0xE0 / 255, 1)   # deeper blue for the diagonal


def arc(a0, a1):
    """Bezier path of a circle arc from a0 to a1 (degrees, increasing)."""
    n = max(1, math.ceil((a1 - a0) / 90.0))
    step = (a1 - a0) / n
    k = 4.0 / 3.0 * math.tan(math.radians(step) / 4.0) * R
    pts = [math.radians(a0 + i * step) for i in range(n + 1)]
    v, i_, o = [], [], []
    for j, a in enumerate(pts):
        v.append([CX + R * math.cos(a), CY + R * math.sin(a)])
        d = [-math.sin(a), math.cos(a)]
        i_.append([0.0, 0.0] if j == 0 else [-k * d[0], -k * d[1]])
        o.append([0.0, 0.0] if j == n else [k * d[0], k * d[1]])
    return {"i": i_, "o": o, "v": v, "c": False}


def line(p, q):
    return {"i": [[0, 0], [0, 0]], "o": [[0, 0], [0, 0]], "v": [p, q], "c": False}


def group(name, paths, color):
    it = [{"ty": "sh", "nm": f"{name}{n}", "ks": {"a": 0, "k": p}} for n, p in enumerate(paths)]
    it.append({"ty": "st", "nm": "stroke", "c": {"a": 0, "k": list(color)}, "o": {"a": 0, "k": 100},
               "w": {"a": 0, "k": SW}, "lc": 2, "lj": 2, "ml": 4})
    it.append({"ty": "tr", "p": {"a": 0, "k": [0, 0]}, "a": {"a": 0, "k": [0, 0]},
               "s": {"a": 0, "k": [100, 100]}, "r": {"a": 0, "k": 0}, "o": {"a": 0, "k": 100}})
    return {"ty": "gr", "nm": name, "it": it}


def ease(t, s):
    return {"t": t, "s": s, "o": {"x": [0.33] * len(s), "y": [0] * len(s)},
            "i": {"x": [0.67] * len(s), "y": [1] * len(s)}}


p_bl, p_tl = [CX - NX, CY + NY], [CX - NX, CY - NY]
p_br, p_tr = [CX + NX, CY + NY], [CX + NX, CY - NY]
shapes = [
    group("ring", [arc(GAP[1], GAP[0] + 360.0)], RING),
    group("legs", [line(p_bl, p_tl), line(p_br, p_tr)], RING),
    group("diagonal", [line(p_tl, p_br)], DIAG),
]
anim = {
    "v": "5.7.0", "fr": FR, "ip": 0, "op": OP, "w": W, "h": H, "nm": "noxis_welcome", "ddd": 0, "assets": [],
    "layers": [{
        "ddd": 0, "ind": 1, "ty": 4, "nm": "noxis", "sr": 1, "ip": 0, "op": OP, "st": 0, "bm": 0,
        "ks": {
            "o": {"a": 1, "k": [ease(0, [100]), ease(75, [90]), {"t": OP, "s": [100]}]},
            "r": {"a": 0, "k": 0},
            "p": {"a": 0, "k": [CX, CY, 0]},
            "a": {"a": 0, "k": [CX, CY, 0]},
            "s": {"a": 1, "k": [ease(0, [100, 100, 100]), ease(75, [104, 104, 100]),
                                {"t": OP, "s": [100, 100, 100]}]},
        },
        "shapes": shapes,
    }],
}

with open(sys.argv[1], "w") as f:
    json.dump(anim, f, separators=(",", ":"))

if len(sys.argv) > 2:                     # preview of frame 0 to check the geometry
    from PIL import Image, ImageDraw
    K = 4
    im = Image.new("RGB", (W * K, H * K), (18, 18, 18))
    d = ImageDraw.Draw(im)
    rgb = lambda c: tuple(int(x * 255) for x in c[:3])
    for g in shapes:
        col = rgb(g["it"][-2]["c"]["k"])
        for s in g["it"][:-2]:
            p = s["ks"]["k"]
            pts = []
            for j in range(len(p["v"]) - 1):
                a, b = p["v"][j], p["v"][j + 1]
                c1 = [a[0] + p["o"][j][0], a[1] + p["o"][j][1]]
                c2 = [b[0] + p["i"][j + 1][0], b[1] + p["i"][j + 1][1]]
                for t in [x / 40 for x in range(41)]:
                    m = 1 - t
                    pts.append(((m**3 * a[0] + 3 * m * m * t * c1[0] + 3 * m * t * t * c2[0] + t**3 * b[0]) * K,
                                (m**3 * a[1] + 3 * m * m * t * c1[1] + 3 * m * t * t * c2[1] + t**3 * b[1]) * K))
            d.line(pts, fill=col, width=int(SW * K), joint="curve")
            for q in (pts[0], pts[-1]):
                d.ellipse((q[0] - SW * K / 2, q[1] - SW * K / 2, q[0] + SW * K / 2, q[1] + SW * K / 2), fill=col)
    im.resize((W, H), Image.LANCZOS).save(sys.argv[2])
