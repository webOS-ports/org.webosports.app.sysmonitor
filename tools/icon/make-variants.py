#!/usr/bin/env python3
# (c) 2026 Herman van Hazendonk <github.com@herrie.org>
# SPDX-License-Identifier: GPL-3.0-only
#
# Draws System Monitor's icon designs in the legacy app icon style, standing
# on the platform of the legacy Settings and Update icons, into
# tools/icon/variants/: a gauge (2) and a CPU chip (5). images/icon.svg is
# the chip.
#
#   python3 tools/icon/make-variants.py
#
# No SVG filters anywhere: Qt's renderer, which the launcher uses, has none,
# so every shadow is one gradient.
import math
import os

class Svg:
    def __init__(s): s.defs=[]; s.body=[]; s.n=0
    def id(s,p): s.n+=1; return f"{p}{s.n}"
    def lin(s,stops,x1=0,y1=0,x2=0,y2=1):
        i=s.id("l"); st="".join(f'<stop offset="{o}" stop-color="{c}" stop-opacity="{a}"/>' for o,c,a in stops)
        s.defs.append(f'<linearGradient id="{i}" x1="{x1}" y1="{y1}" x2="{x2}" y2="{y2}">{st}</linearGradient>'); return f"url(#{i})"
    def rad(s,stops,cx,cy,r,fx=None,fy=None,user=True):
        i=s.id("r"); st="".join(f'<stop offset="{o}" stop-color="{c}" stop-opacity="{a}"/>' for o,c,a in stops)
        f=f' fx="{fx}" fy="{fy}"' if fx is not None else ""
        s.defs.append(f'<radialGradient id="{i}" cx="{cx}" cy="{cy}" r="{r}"{f} gradientUnits="userSpaceOnUse">{st}</radialGradient>'); return f"url(#{i})"
    def add(s,x): s.body.append(x)
    def out(s):
        body=s.body[:4]+['<g transform="translate(128 126) scale(1.14) translate(-128 -128)">']+s.body[4:]+['</g>']
        return ('<svg xmlns="http://www.w3.org/2000/svg" width="256" height="256" viewBox="0 0 256 256">\n<defs>'
                        + "".join(s.defs) + "</defs>\n" + "\n".join(body) + "\n</svg>\n")
def plate(s):
    # The legacy app plate: translucent white, brightest at the top, a faint dark rim.
    s.add(f'<circle cx="128" cy="129" r="121" fill="{s.rad([(0.93,"#000",0),(0.975,"#000",0.16),(1,"#000",0)],128,129,121)}"/>')
    s.add(f'<circle cx="128" cy="128" r="117" fill="{s.lin([(0,"#fff",0.5),(0.38,"#fff",0.2),(0.62,"#fff",0.03),(1,"#fff",0.06)])}"/>')
    s.add(f'<circle cx="128" cy="128" r="117" fill="{s.rad([(0.55,"#fff",0),(1,"#fff",0.22)],128,128,117)}"/>')
    s.add('<circle cx="128" cy="128" r="117" fill="none" stroke="#000" stroke-opacity="0.13" stroke-width="1.5"/>')
def ground_shadow(s,cx,cy,rx,ry,a=0.32):
    s.add(f'<ellipse cx="{cx}" cy="{cy}" rx="{rx}" ry="{ry}" fill="{s.rad([(0,"#000",a),(1,"#000",0)],cx,cy,rx)}" transform="translate({cx} {cy}) scale(1 {ry/rx}) translate({-cx} {-cy})"/>'.replace(f'rx="{rx}" ry="{ry}"',f'rx="{rx}" ry="{rx}"'))

def out(s):
    return ('<svg xmlns="http://www.w3.org/2000/svg" width="256" height="256" viewBox="0 0 256 256">\n<defs>'
            + "".join(s.defs) + "</defs>\n" + "\n".join(s.body) + "\n</svg>\n")
def pt(cx, cy, a, r): return cx + r * math.cos(math.radians(a)), cy + r * math.sin(math.radians(a))

def slate(s, *_args, **_kw):
    # The platform of the legacy Settings and Update icons (graphics repo,
    # BG tile), measured at 256 px: a square turned 45 degrees and seen from
    # high above, its top face from (128, 35.5) to (128, 240) and from x 10
    # to 245, 5 px thick, light at the top and dark slate below a gloss line.
    T, R, B, L = (128, 35.5), (245, 129), (128, 240), (10, 129)
    t = 5
    s.add(f'<path d="M{L[0]},{L[1]} L{B[0]},{B[1]} L{B[0]},{B[1] + t} L{L[0]},{L[1] + t} Z" fill="{s.lin([(0, "#3a3a39", 1), (1, "#262625", 1)])}"/>')
    s.add(f'<path d="M{R[0]},{R[1]} L{B[0]},{B[1]} L{B[0]},{B[1] + t} L{R[0]},{R[1] + t} Z" fill="{s.lin([(0, "#343433", 1), (1, "#1f1f1e", 1)])}"/>')
    face = f"M{T[0]},{T[1]} L{R[0]},{R[1]} L{B[0]},{B[1]} L{L[0]},{L[1]} Z"
    gi = s.id("tile")
    s.defs.append(f'<linearGradient id="{gi}" gradientUnits="userSpaceOnUse" x1="0" y1="35.5" x2="0" y2="240">'
                  '<stop offset="0" stop-color="#b3b5b9"/><stop offset="0.45" stop-color="#5b6067"/>'
                  '<stop offset="0.5" stop-color="#454c54"/><stop offset="1" stop-color="#3b424a"/></linearGradient>')
    s.add(f'<path d="{face}" fill="url(#{gi})"/>')
    s.add(f'<path d="{face}" fill="{s.lin([(0, "#fff", 0.08), (0.5, "#fff", 0), (1, "#000", 0.18)], 0, 0, 1, 0)}"/>')
    # the gloss above the line that bows down from the left corner to the right
    s.add(f'<path d="M{L[0]},{L[1]} Q128,146 {R[0]},{R[1]} L{T[0]},{T[1]} Z" fill="{s.lin([(0, "#fff", 0.1), (1, "#fff", 0.03)])}"/>')
    s.add(f'<path d="M{L[0] + 4},{L[1] + 1} Q128,145 {R[0] - 4},{R[1] + 1}" fill="none" stroke="#fff" stroke-opacity="0.22" stroke-width="1"/>')
    s.add(f'<path d="{face}" fill="none" stroke="#9aa0a6" stroke-opacity="0.55" stroke-width="1"/>')

def gauge(s, cx, cy, R, frac=0.68):
    rim = s.rad([(0, "#fbfcfd", 1), (0.6, "#c7ccd2", 1), (1, "#7d848c", 1)], cx - R * 0.2, cy - R * 0.3, R * 1.35)
    s.add(f'<circle cx="{cx}" cy="{cy}" r="{R}" fill="{rim}" stroke="#5d646c" stroke-width="2"/>')
    fr = R * 0.82
    s.add(f'<circle cx="{cx}" cy="{cy}" r="{fr}" fill="{s.lin([(0, "#3a3e44", 1), (1, "#121417", 1)])}"/>')
    # coloured scale: green, amber, red across 240 degrees
    a0, a1 = 150, 390
    for k, (c0, c1) in enumerate((("#5fd04a", "#2f9a3a"), ("#f3c43c", "#d68a12"), ("#f05a3c", "#c22a1a"))):
        b0 = a0 + (a1 - a0) * [0, 0.55, 0.8][k]; b1 = a0 + (a1 - a0) * [0.55, 0.8, 1][k]
        x0, y0 = pt(cx, cy, b0, fr * 0.84); x1, y1 = pt(cx, cy, b1, fr * 0.84)
        s.add(f'<path d="M{x0:.1f},{y0:.1f} A{fr * 0.84},{fr * 0.84} 0 0 1 {x1:.1f},{y1:.1f}" fill="none" stroke="{s.lin([(0, c0, 1), (1, c1, 1)])}" stroke-width="{R * 0.1:.1f}"/>')
    for i in range(13):
        a = a0 + (a1 - a0) * i / 12; long = i % 3 == 0
        xa, ya = pt(cx, cy, a, fr * 0.72); xb, yb = pt(cx, cy, a, fr * (0.6 if long else 0.66))
        s.add(f'<line x1="{xa:.1f}" y1="{ya:.1f}" x2="{xb:.1f}" y2="{yb:.1f}" stroke="#e9ecef" stroke-width="{R * 0.03 if long else R * 0.018:.2f}"/>')
    # needle
    a = a0 + (a1 - a0) * frac
    xt, yt = pt(cx, cy, a, fr * 0.8); xl, yl = pt(cx, cy, a + 90, R * 0.05); xr, yr = pt(cx, cy, a - 90, R * 0.05)
    s.add(f'<path d="M{xl:.1f},{yl:.1f} L{xt:.1f},{yt:.1f} L{xr:.1f},{yr:.1f} Z" fill="#e8442e" stroke="#9e1f12" stroke-width="0.8"/>')
    s.add(f'<circle cx="{cx}" cy="{cy}" r="{R * 0.13}" fill="{s.rad([(0, "#f5f6f8", 1), (1, "#7d848c", 1)], cx - 3, cy - 3, R * 0.16)}" stroke="#4d535a" stroke-width="1"/>')
    # glass highlight
    s.add(f'<path d="M{cx - fr * 0.8},{cy - fr * 0.1} A{fr * 0.82},{fr * 0.82} 0 0 1 {cx + fr * 0.8},{cy - fr * 0.1} Q{cx},{cy - fr * 0.45} {cx - fr * 0.8},{cy - fr * 0.1} Z" fill="{s.lin([(0, "#fff", 0.3), (1, "#fff", 0.02)])}"/>')

def v2_gauge_slate():
    s = Svg(); slate(s)
    s.add(f'<ellipse cx="128" cy="176" rx="74" ry="30" fill="{s.rad([(0, "#000", 0.5), (1, "#000", 0)], 128, 176, 74)}" transform="translate(128 176) scale(1 0.4) translate(-128 -176)"/>'.replace('ry="30"','ry="74"'))
    gauge(s, 128, 112, 86)
    return out(s)

def v5_chip_slate():
    s = Svg(); slate(s)
    s.add(f'<ellipse cx="128" cy="180" rx="80" ry="80" fill="{s.rad([(0, "#000", 0.5), (1, "#000", 0)], 128, 180, 80)}" transform="translate(128 180) scale(1 0.4) translate(-128 -180)"/>')
    cx, cy = 128, 112
    # gold pins on four sides
    for i in range(7):
        o = -54 + i * 18
        for (x, y, w, h) in ((cx + o - 4, cy - 82, 8, 18), (cx + o - 4, cy + 64, 8, 18), (cx - 82, cy + o - 4, 18, 8), (cx + 64, cy + o - 4, 18, 8)):
            s.add(f'<rect x="{x}" y="{y}" width="{w}" height="{h}" rx="2" fill="{s.lin([(0, "#fbe7a6", 1), (1, "#b78630", 1)], 0, 0, 1, 1)}" stroke="#7a5414" stroke-width="0.8"/>')
    s.add(f'<rect x="{cx - 68}" y="{cy - 68}" width="136" height="136" rx="10" fill="{s.lin([(0, "#4a4f56", 1), (1, "#16181b", 1)], 0, 0, 1, 1)}" stroke="#0b0c0e" stroke-width="2"/>')
    s.add(f'<rect x="{cx - 48}" y="{cy - 48}" width="96" height="96" rx="6" fill="{s.lin([(0, "#e6e9ec", 1), (0.5, "#b4bac1", 1), (1, "#7d848c", 1)], 0, 0, 1, 1)}" stroke="#4d535a" stroke-width="1.5"/>')
    trace = f"M{cx - 40},{cy + 6} L{cx - 18},{cy + 6} L{cx - 10},{cy - 14} L{cx},{cy + 24} L{cx + 10},{cy - 4} L{cx + 16},{cy + 6} L{cx + 40},{cy + 6}"
    s.add(f'<path d="{trace}" fill="none" stroke="#2f9a3a" stroke-width="5" stroke-linejoin="round" stroke-linecap="round"/>')
    s.add(f'<rect x="{cx - 68}" y="{cy - 68}" width="136" height="60" rx="10" fill="{s.lin([(0, "#fff", 0.18), (1, "#fff", 0)])}"/>')
    return out(s)


VARIANTS = [
    ("2-gauge-slate", "a chrome gauge with a green, amber and red scale", v2_gauge_slate),
    ("5-chip-slate", "a CPU chip with gold pins and a pulse line", v5_chip_slate),
]

if __name__ == "__main__":
    out_dir = os.path.join(os.path.dirname(os.path.abspath(__file__)), "variants")
    os.makedirs(out_dir, exist_ok=True)
    for n, what, f in VARIANTS:
        with open(os.path.join(out_dir, n + ".svg"), "w") as fh:
            fh.write("<!-- System Monitor icon design " + n + ": " + what + ", on the legacy\n"
                     "     Settings icons' platform.\n"
                     "     Copyright 2026 Herman van Hazendonk <github.com@herrie.org>\n"
                     "     SPDX-License-Identifier: GPL-3.0-only\n"
                     "     Drawn by tools/icon/make-variants.py. -->\n" + f())
