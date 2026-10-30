#!/usr/bin/env python3
"""Photoreal-leaning foliage card + bark textures for GreenForest (0.2.57).

The forest trees used to be solid vertex-coloured cones/blobs, which
read as plastic on device.  Real-time games (the Forza reference pass)
build trees from a textured trunk, a dark crown core and alpha-cut
foliage cards; this script paints those cards procedurally with PIL:

  gf_leaf_cluster.png   broadleaf branch spray (leafy/oak crowns)
  gf_birch_cluster.png  small yellow-green birch leaves
  gf_spruce_spray.png   drooping spruce bough with short needles
  gf_pine_spray.png     pine needle tufts on fanning stems
  gf_grass_tuft.png     meadow grass blades (ground geometry cards)
  gf_birch_bark*        white birch bark with lenticels (PBR set)
  gf_pine_bark*         scaly reddish pine/spruce bark plates (PBR set)

Cards are drawn at 1024 and downscaled to 512 for cheap alpha-scissor
materials.  Bark sets go through the shared desert save_set pipeline
(albedo + normal from height + roughness, 1024, seamless wraps).

Run:  python3 scripts/generate_forest_foliage_textures.py
"""

import math
import os
import sys

import numpy as np
from PIL import Image, ImageDraw

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from generate_desert_textures import S, clip01, fractal, save_set  # noqa: E402

SEED = 20261117
OUT_DIR = os.path.join(os.path.dirname(os.path.abspath(__file__)),
                       "..", "src", "assets", "textures", "realworld")
SS = 1024        # supersample canvas
CARD = 512       # shipped card size


def _leaf(draw, cx, cy, ang, length, width, col_dark, col_light, vein):
    """One folded leaf: two half-polygons of different shade + vein."""
    dx, dy = math.cos(ang), math.sin(ang)
    px, py = -dy, dx
    bx, by = cx - dx * length * 0.18, cy - dy * length * 0.18
    tx, ty = cx + dx * length * 0.82, cy + dy * length * 0.82

    def side(t, s):
        w = width * math.sin(math.pi * (0.15 + 0.7 * t))
        return (bx + (tx - bx) * t + px * w * s,
                by + (ty - by) * t + py * w * s)

    left = [(bx, by), side(0.32, 1.0), side(0.68, 1.0), (tx, ty)]
    right = [(bx, by), side(0.68, -1.0), side(0.32, -1.0), (tx, ty)]
    draw.polygon(left, fill=col_light)
    draw.polygon(right, fill=col_dark)
    draw.line([(bx, by), (tx, ty)], fill=vein, width=max(2, int(length * 0.045)))


def _shade(rng, lo, hi):
    t = float(rng.random())
    return tuple(int(lo[i] + (hi[i] - lo[i]) * t) for i in range(3))


def leaf_cluster(rng, dark, mid, light, leaf_len, leaf_wid, fill_dark):
    img = Image.new("RGBA", (SS, SS), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    ox, oy = SS * 0.5, SS * 0.97
    branches = []
    for i in range(11):
        ang = -math.pi / 2.0 + (i - 5) * 0.27 + float(rng.uniform(-0.08, 0.08))
        pts = [(ox, oy)]
        x, y = ox, oy
        a = ang
        for _ in range(5):
            a += float(rng.uniform(-0.16, 0.16))
            step = SS * float(rng.uniform(0.10, 0.16))
            x += math.cos(a) * step
            y += math.sin(a) * step
            pts.append((x, y))
        branches.append((pts, a))
        d.line(pts, fill=(64, 46, 28, 255), width=9)
        d.line(pts[2:], fill=(74, 54, 32, 255), width=5)
    # interior shadow leaves first (fill the silhouette cheaply)
    for _ in range(fill_dark):
        a = float(rng.random() * math.tau)
        r = math.sqrt(float(rng.random()))
        x = SS * 0.5 + math.cos(a) * r * SS * 0.40
        y = SS * 0.50 + math.sin(a) * r * SS * 0.38
        _leaf(d, x, y, float(rng.random() * math.tau),
              leaf_len * float(rng.uniform(0.9, 1.25)), leaf_wid,
              _shade(rng, dark, mid), _shade(rng, dark, mid),
              _shade(rng, dark, mid))
    # lit leaves along the branches
    for pts, _a in branches:
        for pi in range(1, len(pts)):
            bx, by = pts[pi]
            for _ in range(16):
                ja = float(rng.random() * math.tau)
                jr = float(rng.uniform(0.0, SS * 0.085))
                x, y = bx + math.cos(ja) * jr, by + math.sin(ja) * jr
                lit = float(rng.random())
                lo = _shade(rng, dark, mid) if lit < 0.55 else _shade(rng, mid, light)
                hi = _shade(rng, mid, light)
                _leaf(d, x, y, float(rng.random() * math.tau),
                      leaf_len * float(rng.uniform(0.75, 1.2)),
                      leaf_wid * float(rng.uniform(0.8, 1.15)), lo, hi,
                      _shade(rng, mid, light))
    return img.resize((CARD, CARD), Image.LANCZOS)


def spruce_spray(rng):
    img = Image.new("RGBA", (SS, SS), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    dark, mid, light = (14, 38, 13), (26, 66, 22), (52, 102, 38)

    def bough(p0, p1, sag, nlen, width):
        pts = []
        for i in range(25):
            t = i / 24.0
            x = p0[0] + (p1[0] - p0[0]) * t
            y = p0[1] + (p1[1] - p0[1]) * t + math.sin(t * math.pi) * sag
            pts.append((x, y))
        for i in range(len(pts) - 1):
            x, y = pts[i]
            t = i / 24.0
            d_ang = math.atan2(pts[i + 1][1] - y, pts[i + 1][0] - x)
            seg = SS * 0.9 / 24.0
            steps = max(2, int(seg / 5.0))
            for s_i in range(steps):
                fx = x + math.cos(d_ang) * seg * (s_i / steps)
                fy = y + math.sin(d_ang) * seg * (s_i / steps)
                scale = (1.0 - t * 0.45)
                for side in (-1.0, 1.0):
                    na = d_ang + side * float(rng.uniform(0.55, 1.05)) \
                        + 0.35  # downward/hanging bias in image space
                    ln = nlen * scale * float(rng.uniform(0.7, 1.15))
                    col = _shade(rng, dark, mid) if side < 0 else _shade(rng, mid, light)
                    d.line([(fx, fy), (fx + math.cos(na) * ln,
                                        fy + math.sin(na) * ln)],
                           fill=col + (255,), width=width)
        d.line(pts, fill=(58, 40, 24, 255), width=max(3, width + 1))
        return pts

    # lower (shadow) boughs first, main lit bough last
    bough((SS * 0.30, SS * 0.46), (SS * 0.88, SS * 0.78), SS * 0.05, SS * 0.075, 5)
    bough((SS * 0.34, SS * 0.40), (SS * 0.95, SS * 0.55), SS * 0.04, SS * 0.07, 5)
    bough((SS * 0.04, SS * 0.30), (SS * 0.97, SS * 0.62), SS * 0.07, SS * 0.085, 6)
    return img.resize((CARD, CARD), Image.LANCZOS)


def pine_spray(rng):
    img = Image.new("RGBA", (SS, SS), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    dark, mid, light = (20, 52, 18), (38, 88, 30), (84, 140, 56)
    base = (SS * 0.10, SS * 0.94)
    tufts = [(0.30, 0.40), (0.52, 0.26), (0.76, 0.38), (0.42, 0.58),
             (0.66, 0.60), (0.88, 0.58), (0.24, 0.66)]
    for (fx, fy) in tufts:
        d.line([base, (SS * fx, SS * fy)], fill=(66, 44, 26, 255), width=6)
    for (fx, fy) in tufts:
        cx, cy = SS * fx, SS * fy
        for _ in range(52):
            a = float(rng.random() * math.tau)
            ln = SS * float(rng.uniform(0.07, 0.13))
            col = _shade(rng, dark, mid) if rng.random() < 0.5 else _shade(rng, mid, light)
            d.line([(cx, cy), (cx + math.cos(a) * ln, cy + math.sin(a) * ln)],
                   fill=col + (255,), width=4)
    for (fx, fy) in ((0.40, 0.52), (0.63, 0.38)):
        cx, cy = SS * fx, SS * fy
        d.ellipse([cx - SS * 0.016, cy - SS * 0.030, cx + SS * 0.016,
                   cy + SS * 0.030], fill=(96, 64, 34, 255))
        d.ellipse([cx - SS * 0.010, cy - SS * 0.022, cx + SS * 0.010,
                   cy + SS * 0.010], fill=(122, 86, 46, 255))
    return img.resize((CARD, CARD), Image.LANCZOS)


def fern_frond(rng):
    img = Image.new("RGBA", (SS, SS), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    dark, mid, light = (16, 48, 16), (30, 84, 26), (66, 132, 48)
    ox, oy = SS * 0.5, SS * 0.99
    for fi in range(7):
        ang = -math.pi / 2.0 + (fi - 3) * 0.34 + float(rng.uniform(-0.05, 0.05))
        length = SS * float(rng.uniform(0.62, 0.88))
        droop = float(rng.uniform(0.25, 0.5))
        pts = []
        for si in range(21):
            tt = si / 20.0
            x = ox + math.cos(ang) * length * tt
            y = oy + math.sin(ang) * length * tt + droop * length * tt * tt
            pts.append((x, y))
        d.line(pts, fill=(52, 66, 30, 255), width=5)
        for si in range(2, 21):
            tt = si / 20.0
            x, y = pts[si]
            tang = math.atan2(pts[si][1] - pts[si - 1][1],
                              pts[si][0] - pts[si - 1][0])
            plen = SS * 0.085 * math.sin(math.pi * (0.12 + 0.8 * tt)) \
                * (1.0 - tt * 0.55)
            for side in (-1.0, 1.0):
                la = tang + side * 0.95
                for li in range(5):
                    lt = (li + 1) / 5.0
                    lx = x + math.cos(la) * plen * lt
                    ly = y + math.sin(la) * plen * lt
                    r = SS * 0.012 * (1.0 - lt * 0.45)
                    col = _shade(rng, dark, mid) if li < 3 else _shade(rng, mid, light)
                    d.ellipse([lx - r, ly - r * 0.55, lx + r, ly + r * 0.55],
                              fill=col + (255,))
                d.line([(x, y), (x + math.cos(la) * plen,
                                 y + math.sin(la) * plen)],
                       fill=(44, 72, 30, 255), width=3)
    return img.resize((CARD, CARD), Image.LANCZOS)


def single_leaf(rng):
    sz = 256
    img = Image.new("RGBA", (sz, sz), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    d.line([(sz * 0.5, sz * 0.98), (sz * 0.5, sz * 0.80)],
           fill=(84, 64, 34, 255), width=7)
    _leaf(d, sz * 0.5, sz * 0.46, -math.pi / 2.0, sz * 0.86, sz * 0.30,
          (44, 96, 30), (86, 148, 54), (140, 190, 96))
    return img


def grass_tuft(rng):
    img = Image.new("RGBA", (SS, SS), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    base = (SS * 0.5, SS * 1.0)
    for _ in range(124):
        spread = float(rng.uniform(-0.62, 0.62))
        h = SS * float(rng.uniform(0.42, 0.82))
        bend = spread * SS * 0.22 + float(rng.uniform(-0.03, 0.03)) * SS
        bx = base[0] + float(rng.uniform(-0.13, 0.13)) * SS
        tip = (bx + math.sin(spread) * h * 0.55 + bend, SS - math.cos(spread) * h)
        midp = (bx + math.sin(spread) * h * 0.26 + bend * 0.35,
                SS - math.cos(spread) * h * 0.52)
        w0 = SS * float(rng.uniform(0.006, 0.011))
        dry = rng.random() < 0.13
        if dry:
            lo = _shade(rng, (108, 96, 44), (142, 128, 62))
            hi = _shade(rng, (150, 138, 72), (186, 172, 96))
        else:
            lo = _shade(rng, (24, 62, 20), (44, 96, 32))
            hi = _shade(rng, (84, 142, 54), (126, 178, 82))
        d.polygon([(bx - w0, SS), (midp[0] - w0 * 0.55, midp[1]), tip,
                   (midp[0] + w0 * 0.55, midp[1]), (bx + w0, SS)], fill=lo + (255,))
        d.polygon([(midp[0] - w0 * 0.5, midp[1]), tip,
                   (midp[0] + w0 * 0.5, midp[1])], fill=hi + (255,))
    return img.resize((CARD, CARD), Image.LANCZOS)


def _wrapped(draw_fn, x, y):
    for ox in (0, -S, S):
        for oy in (0, -S, S):
            draw_fn(x + ox, y + oy)


def birch_bark(rng):
    base = fractal(rng, beta=2.0, fmax=60.0)
    albedo = np.zeros((S, S, 3))
    for c, v in enumerate((0.80, 0.81, 0.78)):
        albedo[..., c] = v + (base - 0.5) * 0.10
    img = Image.fromarray((clip01(albedo) * 255).astype(np.uint8))
    him = Image.new("L", (S, S), 140)
    d = ImageDraw.Draw(img)
    dh = ImageDraw.Draw(him)
    # horizontal lenticel dashes
    for _ in range(950):
        x, y = float(rng.random() * S), float(rng.random() * S)
        ln = float(rng.uniform(12.0, 58.0))
        wd = float(rng.uniform(2.0, 4.5))
        col = _shade(rng, (32, 30, 28), (74, 70, 64))

        def dash(x, y, ln=ln, wd=wd, col=col):
            d.rectangle([x, y, x + ln, y + wd], fill=col)
            dh.rectangle([x, y, x + ln, y + wd], fill=118)
        _wrapped(dash, x, y)
    # black diamond cracks
    for _ in range(70):
        x, y = float(rng.random() * S), float(rng.random() * S)
        ln = float(rng.uniform(30.0, 95.0))
        wd = float(rng.uniform(5.0, 11.0))

        def crack(x, y, ln=ln, wd=wd):
            d.polygon([(x, y - ln * 0.5), (x + wd * 0.5, y), (x, y + ln * 0.5),
                       (x - wd * 0.5, y)], fill=(18, 16, 14))
            dh.polygon([(x, y - ln * 0.5), (x + wd * 0.5, y), (x, y + ln * 0.5),
                        (x - wd * 0.5, y)], fill=70)
        _wrapped(crack, x, y)
    # peeling light strips near the top of some dashes
    for _ in range(180):
        x, y = float(rng.random() * S), float(rng.random() * S)
        ln = float(rng.uniform(18.0, 46.0))

        def peel(x, y, ln=ln):
            d.rectangle([x, y, x + ln, y + 2.5], fill=(236, 234, 226))
            dh.rectangle([x, y, x + ln, y + 2.5], fill=165)
        _wrapped(peel, x, y)
    albedo = np.asarray(img).astype(np.float64) / 255.0
    height = np.asarray(him).astype(np.float64) / 255.0
    rough = np.full((S, S), 0.80)
    return albedo, height, rough


def pine_bark(rng):
    img = Image.new("RGB", (S, S), (38, 24, 15))
    him = Image.new("L", (S, S), 84)
    d = ImageDraw.Draw(img)
    dh = ImageDraw.Draw(him)
    cell = 78.0
    rows = int(S / (cell * 0.72)) + 2
    for ry in range(rows):
        cols = int(S / cell) + 2
        y_base = ry * cell * 0.72
        for rx in range(cols):
            cx = rx * cell + (cell * 0.5 if ry % 2 else 0.0) \
                + float(rng.uniform(-10.0, 10.0))
            cy = y_base + float(rng.uniform(-8.0, 8.0))
            w = cell * float(rng.uniform(0.98, 1.30))
            h = cell * float(rng.uniform(1.35, 1.95))
            pts = []
            for k in range(7):
                a = k / 7.0 * math.tau
                rr = float(rng.uniform(0.78, 1.05))
                pts.append((cx + math.cos(a) * w * 0.5 * rr,
                            cy + math.sin(a) * h * 0.5 * rr))
            col = _shade(rng, (70, 40, 22), (112, 68, 36))
            col_hi = _shade(rng, (118, 76, 42), (148, 98, 56))
            col_lo = _shade(rng, (40, 22, 12), (62, 36, 20))
            for ox in (0, -S, S):
                for oy in (0, -S, S):
                    p2 = [(x + ox, y + oy) for (x, y) in pts]
                    d.polygon(p2, fill=col)
                    dh.polygon(p2, fill=178)
                    inner = [(cx + (x - cx) * 0.62 + ox,
                              cy + (y - cy) * 0.62 - h * 0.10 + oy)
                             for (x, y) in pts]
                    d.polygon(inner, fill=col_hi)
                    dh.polygon(inner, fill=205)
                    lip = [(cx + (x - cx) * 0.8 + ox,
                            cy + (y - cy) * 0.8 + h * 0.16 + oy)
                           for (x, y) in pts if y > cy]
                    if len(lip) >= 3:
                        d.polygon(lip, fill=col_lo)
    # dark fissure strokes + speckle between plates
    for _ in range(520):
        x, y = float(rng.random() * S), float(rng.random() * S)
        ln = float(rng.uniform(8.0, 24.0))
        wd = int(rng.uniform(2, 4))
        jx = float(rng.uniform(-4.0, 4.0))
        col = _shade(rng, (30, 19, 12), (70, 44, 26))

        def stroke(x, y, ln=ln, wd=wd, jx=jx, col=col):
            d.line([(x, y), (x + jx, y + ln)], fill=col, width=wd)
        _wrapped(stroke, x, y)
    albedo = np.asarray(img).astype(np.float64) / 255.0
    grain = fractal(rng, beta=1.5, fmax=500.0)
    albedo = clip01(albedo + (grain[..., None] - 0.5) * 0.10)
    height = np.asarray(him).astype(np.float64) / 255.0
    rough = np.full((S, S), 0.92)
    return albedo, height, rough


def main():
    rng = np.random.default_rng(SEED)
    os.makedirs(OUT_DIR, exist_ok=True)

    def save_card(name, img):
        img.save(os.path.join(OUT_DIR, name))
        print("[foliage] card", name)

    save_card("gf_leaf_cluster.png", leaf_cluster(
        rng, (16, 42, 12), (34, 84, 24), (92, 152, 54),
        SS * 0.041, SS * 0.016, 330))
    save_card("gf_birch_cluster.png", leaf_cluster(
        rng, (34, 74, 22), (66, 124, 40), (140, 190, 88),
        SS * 0.030, SS * 0.013, 350))
    save_card("gf_spruce_spray.png", spruce_spray(rng))
    save_card("gf_pine_spray.png", pine_spray(rng))
    save_card("gf_grass_tuft.png", grass_tuft(rng))
    save_card("gf_fern_frond.png", fern_frond(rng))
    save_card("gf_leaf_single.png", single_leaf(rng))

    a, h, r = birch_bark(rng)
    save_set("gf_birch_bark", a, h, r, 2.0)
    a, h, r = pine_bark(rng)
    save_set("gf_pine_bark", a, h, r, 2.6)
    print("[foliage] done")


if __name__ == "__main__":
    main()
