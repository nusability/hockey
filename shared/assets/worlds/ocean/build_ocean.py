"""
Builds Ocean World (Ozeanwelt): a seagrass pitch on a coral reef, deep beneath the waves
(spec §13, ADR 0006).

Re-authored from the prototype's world (web/js/worlds/ocean.js — read, never run): the same set
pieces in the same places. A teal seagrass pitch with mowing stripes, a faint caustic web and
shells near its edges, inside coral-pink boards with a pearl-white rail strung with pearls, on a
sand rim; a rolling sandy seabed rising away from the reef; blue-violet boulders; coral all round —
staghorn, elkhorn, brain, tube clusters, tall pillar sponges, sea fans — with anemones, starfish,
kelp and sea grass; a shipwreck at the far left, a sunken temple at the far right, stray columns, a
sunken stone head and a treasure chest; schools of fish circling the arena, two manta rays,
glowing jellyfish. The sky: the page gradient, the bright surface far overhead fading to the deep
blue at the horizon. No fog (ADR 0006).

What lives is in the effects (ADR 0007, shared/data/effects.toml): kelp, sea grass, anemones and
sea fans sway in the current; four schools of fish and two manta rays circle the reef; the
jellyfish (glowing, unlit) drift, bob and pulse; bubble streams rise from the reef; motes drift up;
shafts of sunlight shimmer.
Coordinates are the game's (worldkit): X across, Y up, Z along, the far goal at +Z.
Run: tools/build-worlds.sh (Blender 5, headless); `-- --preview` also renders preview.png.
"""
import math
import os
import random
import sys

sys.dont_write_bytecode = True
HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.normpath(os.path.join(HERE, '..', '..', '..', '..', 'tools')))
import worldkit as wk  # noqa: E402
from worldkit import T, R as Rot, S, euler, mix  # noqa: E402

WORLD, SPORT = 'ocean', 'field'
SKY = [(0.0, '#b8f6ff'), (0.06, '#4cc8e6'), (0.15, '#1a8aab'), (0.30, '#0f6f8e'), (0.60, '#0b4f6e'), (1.0, '#052a44')]
LIGHT = dict(hemi_sky='#b8f1fa', hemi_ground='#2a7a8a', hemi=1.3, sun='#f2feff', sun_i=1.8, sun_pos=(14, 60, -10))
SURFACE = dict(base='#2ea393', stripe='#289685', lines='#f0fdfa')
BORDER = dict(color='#ffa4c1', top='#fff8fc', height=1.1, base='#d2b985')
GOAL = dict(post='#ffb020')

rng = random.Random(31)
R = rng.uniform
SLAB_HW, SLAB_HL = wk.HW + wk.SLAB_W, wk.HL + wk.SLAB_W


def sd_slab(x, z):
    return max(abs(x) - SLAB_HW, abs(z) - SLAB_HL)


def seabed_y(x, z):
    d = max(0.0, sd_slab(x, z))
    t = wk.smooth(1.5, 12, d)
    dune = math.sin(x * 0.21 + 1.3) * math.sin(z * 0.17 - 0.4) * 0.9 + math.sin(x * 0.07 - z * 0.09) * 0.6
    return -0.7 + t * (dune + 0.4) + wk.smooth(34, 95, d) * 9


def scatter(n, lo=1.5, hi=45, falloff=16, tall=False, bias=None):
    """Random spots outside the rim, denser near it; `tall` keeps clear of the strip behind the
    user's goal (the play camera's)."""
    out, guard = [], 0
    while len(out) < n and guard < n * 60:
        guard += 1
        x, z = R(-SLAB_HW - hi, SLAB_HW + hi), R(-SLAB_HL - hi, SLAB_HL + hi)
        d = sd_slab(x, z)
        if d < lo or d > hi:
            continue
        if tall and z < -wk.HL - 1 and abs(x) < 19:
            continue
        p = math.exp(-(d - lo) / falloff)
        if z < -wk.HL:
            p *= 0.35
        if bias:
            p *= bias(x, z)
        if rng.random() < p:
            out.append((x, z))
    return out


# ---------------------------------------------------------------- the pitch's own paint
def decorate(turf, paint):
    web = mix(mix(SURFACE['base'], SURFACE['stripe'], 0.5), '#e0fff5', 0.06)
    for i in range(40):                                        # a faint caustic web
        x, z, r = R(-12, 12), R(-27, 27), R(1.3, 3.3)
        pts = []
        for a in range(21):
            t = a / 20 * 2 * math.pi
            rr = r * (0.8 + 0.2 * math.sin(t * 3 + i))
            pts.append((x + math.cos(t) * rr, z + math.sin(t) * rr * 0.8))
        turf.strip(pts, 0.1, wk.DECOR_Y, web)
    for _ in range(30):                                        # sand drift and shells near the edges
        side = 1 if rng.random() < 0.5 else -1
        if rng.random() < 0.5:
            x, z = side * (14.4 - R(0, 1.1)), R(-29, 29)
        else:
            x, z = R(-14, 14), side * (29.4 - R(0, 1.1))
        r, rot = R(0.23, 0.47), R(0, 2 * math.pi)
        col = '#fde7d6' if rng.random() < 0.5 else '#fbd3e0'
        pts = [(x, z)]
        for k in range(-4, 5):
            a = rot - math.pi / 2 + k / 4 * 1.15
            pts.append((x + math.cos(a) * r, z + math.sin(a) * r))
        turf.up([(px, wk.DECOR_Y, pz) for px, pz in pts], col)


# ---------------------------------------------------------------- the seabed
SAND = ['#c1a462', '#caad69', '#d6bd7e']


def seabed(m):
    def col(x, y, z, n):
        v = wk.fbm(x * 0.07 + 2.3, z * 0.07 - 4.1, 2) + 0.4 * wk.vnoise(x * 0.35, z * 0.35)
        return SAND[wk.clamp(int((v + 0.8) / 1.6 * 3), 0, 2)]
    N, half = 56, 290.0
    mp = lambda u: half * (0.3 * u + 0.7 * u * u * u)
    xs = [mp(i / N * 2 - 1) for i in range(N + 1)]
    skip = lambda x0, z0, x1, z1: math.hypot((x0 + x1) / 2, (z0 + z1) / 2) > 300 or (max(abs(x0), abs(x1)) < 16 and max(abs(z0), abs(z1)) < 31)
    m.field(xs, xs, seabed_y, col, skip=skip, warp=lambda x, z: wk.push_out(x, z, 0.5, 2.0))


# ---------------------------------------------------------------- reef life
def coral_branches(m, x, z, sc, sy, yaw, col, kids, spread, flat, trunk):
    """The prototype's branching coral: recursive tapered cylinders."""
    base = seabed_y(x, z) - 0.1
    M = T(x, base, z) @ Rot(yaw, 'Y') @ S(sc, sy, sc)
    mm = m.xf(M)

    def grow(p, d, ln, r, lvl):
        end = tuple(p[k] + d[k] * ln for k in range(3))
        tip = lvl >= 2
        mm.frustum(p, end, r, r * 0.15 if tip else r * 0.55, 4, col, phase=0.4 * lvl)
        if tip:
            return
        n = kids if lvl == 0 else 2
        for i in range(n):
            a = i / n * 2 * math.pi + R(-0.6, 0.6)
            dd = wk._norm((math.cos(a) * spread * flat, 1.1, math.sin(a) * spread))
            grow(end, dd, ln * R(0.55, 0.75), r * 0.7, lvl + 1)
    grow((0, 0, 0), (0, 1, 0), trunk, 0.13, 0)


def swaying(fx, y0, h, amp, scale):
    """A piece of the current's sway: weight grows with the square of the height up it (the
    prototype's hh²), scaled to its own amplitude against the effect's."""
    k = 0.4 * amp * scale
    return fx['sway'].piece(lambda pt: (wk.clamp(k * wk.clamp((pt[1] - y0) / h, 0.0, 1.0) ** 2, 0.0, 1.0),
                                        ((pt[0] * 0.7 + pt[2] * 0.9) / (2 * math.pi)) % 1.0))


def reef(m, fx):
    for x, z in scatter(46, lo=1.2, hi=60, falloff=22):         # boulders
        sc = R(0.9, 3.2)
        c = rng.choice(['#7484b3', '#8286b5', '#6a8aa6', '#8c7cac'])
        m.blob((x, seabed_y(x, z) - sc * 0.35, z), sc, [wk.scale(c, 0.85), c], scale=(R(0.8, 1.4), R(0.5, 0.9), R(0.8, 1.4)),
               level=0, jitter=0.15, rng=rng, yaw=R(0, 6.28))
    for x, z in scatter(46, lo=1.4, hi=30, falloff=9, tall=True):  # staghorn
        sc = R(1.5, 3.2)
        coral_branches(m, x, z, sc, sc, R(0, 6.3), rng.choice(['#ff7a59', '#ff9d3b', '#f05a8e', '#ffc94d', '#e8583c']), 3, 0.8, 1, 1)
    for x, z in scatter(28, lo=1.4, hi=28, falloff=10, tall=True):  # elkhorn
        sc = R(1.8, 3.4)
        coral_branches(m, x, z, sc * 1.3, sc * 0.8, R(0, 6.3), rng.choice(['#b56cff', '#8b5cf6', '#d85cc4', '#ff80ab']), 3, 1.4, 1.6, 0.6)
    for x, z in scatter(34, lo=1.2, hi=30, falloff=10):         # brain coral
        sc = R(0.8, 2.3)
        c = rng.choice(['#d6a35c', '#b3d95c', '#c98bd9', '#f0b070', '#7fd1c8'])
        m.blob((x, seabed_y(x, z) + sc * 0.25, z), sc, [wk.scale(c, 0.78), c, wk.scale(c, 0.78), c], scale=(1, 0.66, R(0.8, 1.2)),
               level=1, jitter=0.05, rng=rng, cut=-0.45, band_noise=0.5, yaw=R(0, 6.28))
    for x, z in scatter(38, lo=1.2, hi=30, falloff=10):         # tube coral clusters
        sc, yaw = R(0.9, 1.9), R(0, 6.3)
        c = rng.choice(['#ff5e7a', '#ffa552', '#ffe066', '#ff6fb5'])
        y0 = seabed_y(x, z) - 0.05
        for k in range(5):
            a, r, h = k / 5 * 2 * math.pi + yaw, (0.32 if k else 0.0) * sc, R(0.6, 1.3) * sc
            bx, bz = x + math.cos(a) * r, z + math.sin(a) * r
            m.frustum((bx, y0, bz), (bx + R(-0.25, 0.25) * h, y0 + h, bz + R(-0.25, 0.25) * h), 0.22 * sc, 0.16 * sc, 5, c, cap=wk.scale(c, 0.55))
    for x, z in scatter(30, lo=1.6, hi=36, falloff=13, tall=True):  # pillar corals / sponges
        c = rng.choice(['#9b4dff', '#ff4d7e', '#ff8c42', '#5b6cff'])
        w, h = R(0.8, 1.3), R(2.4, 4.8)
        y0 = seabed_y(x, z) - 0.1
        top = (x + R(-0.15, 0.15) * h, y0 + h, z + R(-0.15, 0.15) * h)
        m.frustum((x, y0, z), top, 0.42 * w, 0.24 * w, 7, c)
        m.blob(top, 0.24 * w, wk.scale(c, 0.7), scale=(1, 0.45, 1), level=0)
    for x, z in scatter(60, lo=1.2, hi=30, falloff=10, tall=True):  # sea fans
        sc, yaw = R(1.8, 3.6), R(0, 6.3)
        c = rng.choice(['#ff4f6d', '#ff8a3d', '#c45cff', '#ffd166', '#ff5cab'])
        y0 = seabed_y(x, z) - 0.1
        ca, sa = math.cos(yaw), math.sin(yaw)
        pts = [(x, y0, z)]
        for k in range(9):
            a = math.radians(-75 + 150 * k / 8)
            rr = sc * (0.46 if k % 2 else 0.4)
            px, py = math.sin(a) * rr, 0.08 * sc + math.cos(a) * rr
            pts.append((x + px * ca, y0 + py, z + px * sa))
        with swaying(fx, y0, 0.55 * sc, 0.06, sc) as fm:
            fm.face(pts, c, facing=(-sa, 0.3, ca))
    for x, z in scatter(48, lo=1.2, hi=28, falloff=9):          # anemones
        sc = R(0.9, 1.9)
        c = rng.choice(['#ff7ab8', '#b388ff', '#7dffc4', '#ffb27a', '#8ad4ff'])
        y0 = seabed_y(x, z) - 0.05
        m.frustum((x, y0, z), (x, y0 + 0.12 * sc, z), 0.2 * sc, 0.2 * sc, 6, wk.scale(c, 0.7), cap=wk.scale(c, 0.6))
        for k in range(6):
            a = k / 6 * 2 * math.pi + R(-0.3, 0.3)
            tip = (x + math.cos(a) * 0.45 * sc, y0 + R(0.55, 0.9) * sc, z + math.sin(a) * 0.45 * sc)
            with swaying(fx, y0, 0.9 * sc, 0.12, sc) as fm:
                fm.frustum((x + math.cos(a) * 0.1 * sc, y0 + 0.1 * sc, z + math.sin(a) * 0.1 * sc), tip, 0.06 * sc, 0.0, 3, c)
    for x, z in scatter(30, lo=1.0, hi=28, falloff=9):          # starfish
        sc, rot = R(0.35, 0.7), R(0, 6.3)
        c = rng.choice(['#ff6a3d', '#ff3d6e', '#a855f7', '#ffb02e'])
        y0 = seabed_y(x, z) + 0.02
        centre = (x, y0 + 0.2 * sc, z)
        ring = [(x + math.cos(rot + i / 10 * 2 * math.pi) * (sc if i % 2 == 0 else 0.42 * sc), y0 + 0.02,
                 z + math.sin(rot + i / 10 * 2 * math.pi) * (sc if i % 2 == 0 else 0.42 * sc)) for i in range(10)]
        for i in range(10):
            m.face([ring[i], ring[(i + 1) % 10], centre], c, facing=(0, 1, 0))
    kelp_bias = lambda x, z: 1.0 if abs(x) > 21 or z > wk.HL + 6 else 0.15
    for x, z in scatter(140, lo=3, hi=40, falloff=14, tall=True, bias=kelp_bias):  # kelp
        w, h, yaw = R(1.3, 2.4), R(4, 8), R(0, 6.3)
        c = rng.choice(['#3fae5a', '#5cc46a', '#2f9c6e', '#7ccf4f', '#9bbf3a'])
        y0 = seabed_y(x, z) - 0.1
        ca, sa = math.cos(yaw), math.sin(yaw)
        prev = None
        sway = R(-0.6, 0.6)
        piece = swaying(fx, y0, h, 0.35, h)
        km = piece.__enter__()
        for k in range(5):
            t = k / 4
            half = w * 0.2 * ((0.5 + 0.5 * math.sin(t * math.pi)) * (1 - t * 0.5) + 0.15) if k < 4 else 0.02
            cx, cz = x + sway * t * t * sa, z - sway * t * t * ca
            pair = ((cx - half * ca, y0 + h * t, cz - half * sa), (cx + half * ca, y0 + h * t, cz + half * sa))
            if prev:
                km.face([prev[0], prev[1], pair[1], pair[0]], c if k % 2 else wk.scale(c, 0.8), facing=(-sa, 0, ca))
            prev = pair
        piece.__exit__()
    for x, z in scatter(360, lo=0.6, hi=22, falloff=6):         # sea grass
        c = rng.choice(['#4fc36a', '#8fd35a', '#35b08a', '#b9d64a'])
        y0 = seabed_y(x, z) - 0.05
        h = R(0.6, 1.5)
        for k in range(2):
            a = R(0, 6.28)
            with swaying(fx, y0, h, 0.2, h) as fm:
                fm.face([(x - math.sin(a) * 0.08, y0, z + math.cos(a) * 0.08), (x + math.sin(a) * 0.08, y0, z - math.cos(a) * 0.08),
                    (x + math.cos(a) * 0.3, y0 + h, z + math.sin(a) * 0.3)], c, facing=(math.cos(a), 0.2, math.sin(a)))


def pearls(m):
    """Pearls strung along the rail (kept on it: none leans over the pitch)."""
    pts = wk.rr_points(0.3, 2.0, 88)
    for i, (x, z) in enumerate(pts):
        r = 0.28 if i % 4 == 0 else 0.22
        m.blob((x, 1.22 + r * 0.8, z), r, rng.choice(['#fff6fb', '#ffeef5', '#f3f7ff']), level=0)


# ---------------------------------------------------------------- the wreck, the temple, the head, the chest
def shipwreck(m):
    wx, wz = -14.0, 40.5
    mm = m.xf(T(wx, seabed_y(wx, wz) - 1.1, wz) @ euler(0.08, 0.35, 0.28))
    wood, plank, dark, algae = '#5a3a22', '#74502f', '#3b2616', '#4c8f5a'
    outline = [(-7, 0), (-6.6, 1.5), (-5.2, 2.35), (-3, 2.5), (4, 2.3), (6.4, 1.6), (8.5, 0), (6.4, -1.6), (4, -2.3), (-3, -2.5), (-5.2, -2.35), (-6.6, -1.5)]
    top = [(x * 1.08, 2.4, z * 1.1) for x, z in outline]
    mid = [(x, 0.6, z) for x, z in outline]
    bot = [(x * 0.7, -1.4, z * 0.45) for x, z in outline]
    n = len(outline)
    c = (0.5, 0.5, 0.0)
    for A, B, col in ((bot, mid, dark), (mid, top, wood)):
        for i in range(n):
            j = (i + 1) % n
            mm.face([A[i], A[j], B[j], B[i]], col if i % 3 else plank, out=c)
    mm.face(list(reversed(top)), plank, facing=(0, 1, 0))
    for i in range(n):                                         # the gunwale rail
        j = (i + 1) % n
        mm.bar((top[i][0], 2.55, top[i][2]), (top[j][0], 2.55, top[j][2]), 0.25, plank)
    for i in range(6):                                         # ribs where the hull broke open
        mm.box(-6.2 + i * 0.8, 1.4, 2.1 - i * 0.05, 0.22, 2.4, 0.3, dark, roll=-0.4 + i * 0.05, tilt=R(-0.2, 0.2))
    mm.box(-4.2, 2.2, 0, 3.2, 1.6, 3.6, plank)
    mm.box(-4.2, 3.75, 0, 3.6, 0.3, 4.0, dark)
    mm.frustum((1.0, 2.4, 0.3), (2.6, 12.9, 0.3), 0.24, 0.16, 6, dark)
    mm.box(2.2, 9.1, 0.3, 5.5, 0.22, 0.22, dark, yaw=0.3, roll=0.22)
    mm.frustum((-1.6, 3.0, -0.2), (-4.0, 6.3, -0.2), 0.2, 0.14, 6, dark)
    mm.frustum((8.0, 2.2, 0), (11.4, 3.7, 0), 0.16, 0.1, 5, dark)
    for i in range(3):
        mm.frustum((3.5 + i * 1.1, 2.4, -1 + i * 0.7), (3.5 + i * 1.1, 3.3, -1 + i * 0.7), 0.5, 0.5, 8, plank, cap=wood)
    mm.box(6.5, 2.4, 0.9, 1.1, 1.1, 1.1, wood, yaw=0.6)
    for _ in range(7):
        mm.blob((R(-6, 7), R(2.4, 3.2), R(-2, 2)), 0.55, algae, scale=(R(1, 1.8), 0.6, R(1, 1.8)), level=0, jitter=0.15, rng=rng)


def temple(m):
    stone, stone_d, moss = '#e3dcc6', '#b9b19a', '#6f9a63'
    rx, rz = 25.5, 40.0
    gy = seabed_y(rx, rz)
    m.box(rx, gy - 0.2, rz, 16, 0.6, 12, stone_d, yaw=0.1)
    m.box(rx, gy + 0.4, rz, 13.5, 0.6, 9.5, stone, yaw=0.1)
    top = gy + 1.0
    grid = [(rx - 5 + i * 3.4, rz + zz) for i in range(4) for zz in (-3.4, 3.4)]
    for i, (x, z) in enumerate(grid):
        full = i not in (2, 5, 7)
        h = 4.6 if full else R(1.2, 2.4)
        tilt = R(-0.03, 0.03) if full else R(-0.1, 0.1)
        m.frustum((x, top, z), (x + tilt * h, top + h, z + tilt * 0.7 * h), 0.52, 0.46, 10, stone, cap=stone_d,
                  col_fn=lambda k: stone if k % 2 else stone_d)
        m.box(x, top - 0.02, z, 1.25, 0.28, 1.25, stone)
        if full:
            m.box(x, top + h - 0.02, z, 1.3, 0.35, 1.3, stone)
    m.box(rx - 3.3, top + 4.9, rz - 3.4, 4.2, 0.7, 1.2, stone)
    m.box(rx + 1, top + 0.1, rz + 0.3, 4.0, 0.7, 1.2, stone_d, yaw=0.5, roll=0.05)
    for i in range(4):
        cx, cz = rx + 8 + i * 1.5, rz + 4.5 + i * 0.3
        ang = 1.3 + i * 0.05
        m.frustum((cx - math.cos(ang) * 0.7, top + 0.5, cz - math.sin(ang) * 0.7), (cx + math.cos(ang) * 0.7, top + 0.5, cz + math.sin(ang) * 0.7),
                  0.5, 0.5, 10, stone, cap=stone_d, bottom=stone_d)
    ped = m.xf(T(rx + 3, gy + 0.3, rz + 9) @ euler(-0.9, 0.4, 0))
    tri = [(-3, 0, 0), (3, 0, 0), (0, 1.6, 0)]
    ped.face(tri, stone, facing=(0, 0, -1))
    ped.face([(x, y, 0.6) for x, y, _ in tri], stone, facing=(0, 0, 1))
    for i in range(3):
        a, b = tri[i], tri[(i + 1) % 3]
        ped.face([a, b, (b[0], b[1], 0.6), (a[0], a[1], 0.6)], stone_d, out=(0, 0.5, 0.3))
    for _ in range(5):
        m.blob((rx + R(-6, 6), top + 0.1, rz + R(-4, 4)), 0.5, moss, scale=(R(1, 2), 0.4, R(1, 2)), level=0, jitter=0.1, rng=rng)
    for x, z, h in ((-25, 8, 4.2), (-28.5, -6, 2.2), (24.5, -14, 3.4), (26, 12, 1.6), (-23, 40, 3.8)):
        y = seabed_y(x, z) - 0.3
        t = R(-0.12, 0.12)
        m.frustum((x, y, z), (x + t * h, y + h, z + t * 0.7 * h), 0.52, 0.46, 10, stone, cap=stone_d, col_fn=lambda k: stone if k % 2 else stone_d)
        m.box(x, y - 0.05, z, 1.3, 0.3, 1.3, stone)
        if h > 3:
            m.box(x + t * h, y + h - 0.02, z + t * 0.7 * h, 1.3, 0.35, 1.3, stone)


def stone_head(m):
    sx, sz = -24.0, 24.0
    mm = m.xf(T(sx, seabed_y(sx, sz) - 1.3, sz) @ euler(-0.35, 1.2, 0.18))
    stone, dark, moss = '#7d8798', '#5e6778', '#5f9a68'
    mm.box(0, 0, 0, 2.4, 4.2, 2.0, stone)
    mm.box(0, 2.8, 0.05, 2.6, 0.6, 2.2, dark)
    mm.box(0, 1.4, 1.15, 0.7, 1.4, 0.7, stone, tilt=0.15)
    mm.box(0, 0.93, 1.05, 2.0, 0.35, 0.4, dark)
    for x in (-0.75, 0.75):
        mm.box(x, 2.5, 1.05, 0.5, 0.5, 0.5, dark)
    mm.blob((-0.6, 4.2, -0.2), 0.6, moss, scale=(1.8, 0.5, 1.4), level=0)
    mm.blob((1.1, 3.4, 0.6), 0.6, moss, scale=(0.9, 0.5, 0.8), level=0)


def chest(m):
    cx, cz = -19.5, 36.0
    mm = m.xf(T(cx, seabed_y(cx, cz) - 0.15, cz) @ Rot(0.7, 'Y'))
    wood, band, gold = '#6b4423', '#3f3a36', '#ffc23a'
    mm.box(0, 0, 0, 1.4, 0.8, 1.0, wood)
    for z in (0.44, -0.44):
        mm.box(0, -0.01, z, 1.46, 0.82, 0.16, band)
    mm.cuboid(T(0, 0.95, -0.35) @ Rot(-1.1, 'X') @ S(1.4, 0.12, 1.0), wood)
    mm.blob((0, 0.8, 0.05), 0.5, gold, scale=(1.2, 0.5, 0.9), level=1)


# ---------------------------------------------------------------- fish, mantas, jellyfish
FISH_ELLIPSE = 1.818                                            # effects.toml fish.ellipse (z : x)


def fish(fx):
    """The four schools on the prototype's ellipses (their z radii; x radii from the one shared
    ellipse the orbit turns them on), each school at its own speed — the prototype's 0.22, −0.16,
    0.3, −0.11 rad/s against the effect's 0.3, baked as w = (k + 1) / 2 — each fish bobbing on its
    own phase."""
    m = fx['fish']
    schools = [(80, 24, 46, 4.5, ['#ffc63d', '#ffb020'], 1, 0.22), (60, 30, 50, 7.5, ['#3d8bff', '#5aa6ff', '#8fd3ff'], -1, -0.16),
               (50, 22, 52, 3.2, ['#ff7a1a', '#ffffff'], 1, 0.3), (30, 36, 62, 12, ['#dfe9f2', '#c0d0e0'], -1, -0.11)]
    for n, rx, rz, y, cols, d, spd in schools:
        rx = rz / FISH_ELLIPSE
        a0 = R(0, 6.28)
        for i in range(n // 2):
            a = a0 + R(-0.6, 0.6)
            dr = R(1, 1.25)
            x, z = math.cos(a) * rx * dr, math.sin(a) * rz * dr
            if wk.sd_round_rect(x, z, r=2.0) < 1.0:
                continue
            yy = y + R(-1.2, 1.2) + math.sin(R(0, 6.3)) * R(0.3, 0.8)
            tx, tz = -math.sin(a) * rx * d, math.cos(a) * rz * d
            heading = math.atan2(tz, tx)
            s = R(0.75, 1.25)
            m.datafn = lambda pt, k=spd / 0.3, ph=m.rng.uniform(0, 1): ((k + 1) / 2, ph)
            mm = m.xf(T(x, yy, z) @ Rot(-heading, 'Y') @ S(s))
            c = rng.choice(cols)
            mm.octa((0, 0, 0), 0.14, 0.275, c, roll=math.pi / 2, lower=0.275, top_col=wk.scale(c, 0.85))
            mm.face([(-0.25, 0, 0), (-0.55, 0.2, 0), (-0.55, -0.2, 0)], c, facing=(0, 0, 1))


def mantas(fx):
    """Two mantas gliding round on circles (a manta is too big to stretch round an ellipse), the
    second backwards at 0.06 rad/s against the effect's 0.075."""
    m = fx['mantas']
    for a, rx, rz, y, sc, d in ((0.4, 50, 50, 9.5, 9, 1), (3.6, 58, 58, 12, 6, -1)):
        m.datafn = lambda pt, k=(1.0 if d > 0 else -0.06 / 0.075), ph=m.rng.uniform(0, 1): ((k + 1) / 2, ph)
        x, z = math.cos(a) * rx, math.sin(a) * rz
        dx, dz = -math.sin(a) * rx * d, math.cos(a) * rz * d
        mm = m.xf(T(x, y, z) @ Rot(math.atan2(-dx, -dz), 'Y') @ Rot(0.22 * d, 'Z') @ S(sc))
        le = lambda u: -0.35 + 0.5 * abs(u) ** 1.4
        te = lambda u: 0.6 - 0.35 * abs(u) ** 0.6
        us = [-1, -0.6, -0.25, 0, 0.25, 0.6, 1]
        for i in range(len(us) - 1):
            u0, u1 = us[i], us[i + 1]
            flap = lambda u: 0.12 * abs(u) ** 1.6
            shade = 0.55 + 0.45 * (1 - abs((u0 + u1) / 2))
            c = wk.hexs((0.3 * shade, 0.42 * shade, 0.6 * shade))
            mm.face([(u0, flap(u0), le(u0)), (u1, flap(u1), le(u1)), (u1, flap(u1), te(u1)), (u0, flap(u0), te(u0))], c, facing=(0, 1, 0))
        mm.face([(-0.03, 0, 0.55), (0.03, 0, 0.55), (0, 0, 1.7)], '#3b4d70', facing=(0, 1, 0))
        for s in (-1, 1):
            mm.face([(s * 0.16, 0, -0.3), (s * 0.08, 0, -0.3), (s * 0.12, 0, -0.55)], '#3b4d70', facing=(0, 1, 0))


def jellyfish(fx):
    sky_m = fx['jellies']
    for x, z in scatter(22, lo=4, hi=40, falloff=18, tall=True):
        sky_m.datafn = lambda pt, ph=sky_m.rng.uniform(0, 1): (1.0, ph)
        y, sc = seabed_y(x, z) + R(3, 10), R(0.6, 1.5)
        c = rng.choice(['#ff9ad5', '#b9a6ff', '#9de8ff', '#ffc4a8'])
        prof = [(0.0, 1.0), (0.55, 0.85), (0.9, 0.45), (1.0, 0.0)]
        sky_m.lathe((x, y, z), [(r * sc, h * sc) for r, h in prof], 8, [mix(c, '#ffffff', 0.35), c, wk.scale(c, 0.85)])
        for i in range(4):
            a = i * math.pi / 2
            p = (x + math.cos(a) * 0.45 * sc, y, z + math.sin(a) * 0.45 * sc)
            sky_m.frustum(p, (p[0] + R(-0.3, 0.3), y - 2.2 * sc, p[2] + R(-0.3, 0.3)), 0.06 * sc, 0.0, 3, wk.scale(c, 0.9))


# ---------------------------------------------------------------- the world
def bubbles(fx):
    """Bubble streams from vents in the reef (and the wreck's, the chest's, the temple's), motes
    drifting up everywhere, shafts of sunlight — each on the effect's own seed."""
    b = fx['bubbles']
    R_ = b.rng.uniform
    sites = [(-14.0, 40.5), (-19.5, 36.0), (25.5, 40.0)]
    while len(sites) < 19:
        x, z = R_(-SLAB_HW - 34, SLAB_HW + 34), R_(-SLAB_HL - 34, SLAB_HL + 34)
        if 2 <= sd_slab(x, z) <= 34 and not (z < -wk.HL - 1 and abs(x) < 19):
            sites.append((x, z))
    for cx, cz in sites:
        for _ in range(12):
            x, z = cx + R_(-0.35, 0.35), cz + R_(-0.35, 0.35)
            b.particle((x, seabed_y(x, z) + R_(0.0, 0.3), z), b.rng.choice(('#e8fbff', '#d4f6ff')))
    m = fx['motes']
    n = 0
    while n < 120:
        x, z = m.rng.uniform(-SLAB_HW - 60, SLAB_HW + 60), m.rng.uniform(-SLAB_HL - 60, SLAB_HL + 60)
        if 1 <= sd_slab(x, z) <= 60:
            m.particle((x, seabed_y(x, z) + m.rng.uniform(0.5, 2.0), z), '#dffaff')
            n += 1
    sh = fx['shafts']
    R_ = sh.rng.uniform
    for _ in range(9):
        x, z = R_(-58, 58), R_(-40, 70)
        if abs(x) < 20 and z < wk.HL + 8:
            continue
        w, h = R_(1.5, 4), R_(34, 60)
        for ry in (0.3, 1.87):
            a = ry + R_(-0.2, 0.2)
            ux, uz = math.cos(a) * w / 2, math.sin(a) * w / 2
            rows = [(0.0, 0.0), (0.55, 1.0), (1.0, 0.35)]           # (height fraction, light): bright below the middle
            for (f0, l0), (f1, l1) in zip(rows, rows[1:]):
                y0, y1 = f0 * h, f1 * h
                with sh.piece(lambda pt, y0=y0, y1=y1, l0=l0, l1=l1: (l0 + (l1 - l0) * wk.clamp((pt[1] - y0) / (y1 - y0), 0.0, 1.0), 0.0)):
                    sh.face([(x - ux, y0, z - uz), (x + ux, y0, z + uz), (x + ux, y1, z + uz), (x - ux, y1, z - uz)], '#9fe8ff',
                            facing=(-math.sin(a), 0, math.cos(a)))


def build(turf, scen, sky_m, fx):
    wk.rink(turf, scen, SPORT, SURFACE, BORDER, GOAL, decorate=decorate, skirt=-1.0)
    seabed(scen)
    reef(scen, fx)
    pearls(scen)
    shipwreck(scen)
    temple(scen)
    stone_head(scen)
    chest(scen)
    fish(fx)
    mantas(fx)
    jellyfish(fx)
    bubbles(fx)


wk.run(WORLD, HERE, wk.Palette(wk.css_sky(SKY)), SPORT, build, LIGHT)
