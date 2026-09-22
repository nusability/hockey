"""
Builds Desert Oasis (Wüstenoase): green turf between golden dunes and palms (spec §13, ADR 0006).

Re-authored from the prototype's world (web/js/worlds/oasis.js — read, never run): the same set
pieces in the same places. A green pitch with mowing stripes, sandy wear along its edges and in
the goal mouths and wind-blown streaks on the pool side, inside terracotta boards with a
turquoise rail on a sand rim; rolling dunes (sun-facing slopes warm, the far sides violet —
painted, as the prototype painted them); two turquoise pools — a big one behind the far goal, one
hugging the far +X corner — with wet shores, reeds and glints; palms round the pools, the ruins
and the sides; a sandstone ruin with an arched gateway, broken columns and an old bath flanking the
big pool; a tent camp with striped canvas, awnings, rugs, bunting and a campfire; cacti, rocks,
desert grass; a camel caravan on the dunes; the huge low sun. The sky: the page gradient, violet
over a glowing orange horizon, the sun's glow painted into the sky map. No fog (ADR 0006).

What lives is in the effects (ADR 0007, shared/data/effects.toml): palm crowns, grass, reeds and
bunting sway in one breeze; the pools glitter; the campfire's flame licks and its glow flickers;
dust blows along the dunes.

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
from worldkit import clamp, lerp, mix  # noqa: E402

WORLD, SPORT = 'oasis', 'field'
SKY = [(0.0, '#3b2a6e'), (0.14, '#8a3f6a'), (0.34, '#e0693f'), (0.60, '#f6a35a'), (1.0, '#ffd7a0')]
LIGHT = dict(hemi_sky='#ffd9a8', hemi_ground='#b27a4c', hemi=0.9, sun='#ffc98a', sun_i=2.5, sun_pos=(-40, 30, 14))
SURFACE = dict(base='#4c9a3f', stripe='#448f39', lines='#fff7e6')
BORDER = dict(color='#d28b58', top='#2dd4bf', height=1.1, base='#cfa066')
GOAL = dict(post='#ef4444', net='#fff1d6')

rng = random.Random(20260913)
R = rng.uniform
sm = lambda t: t * t * (3 - 2 * t)
c01 = lambda v: clamp(v, 0.0, 1.0)
SUN_DIR = wk._norm((-300, 26, 105))                          # the painted sun, low over −X


def fbm(x, z, octaves):
    s, a, f, n = 0.0, 1.0, 1.0, 0.0
    for i in range(octaves):
        s += wk.vnoise(x * f + i * 13.7, z * f + i * 7.1) * a
        n += a
        a *= 0.5
        f *= 2.1
    return s / n


# ---------------------------------------------------------------- the landscape (the prototype's)
POOLS = [(0.0, 46.0, 10.5, 0.6), (27.0, 32.0, 9.5, 2.4)]


def pool_r(p, th):
    return p[2] * (1 + 0.16 * math.sin(2 * th + p[3]) + 0.09 * math.sin(3 * th + 1.9 + p[3]) + 0.05 * math.sin(5 * th + 0.4))


def pool_dist(x, z):
    return min(math.hypot(x - p[0], z - p[1]) / pool_r(p, math.atan2(z - p[1], x - p[0])) for p in POOLS)


def height(x, z):
    """Flat apron round the pitch, dunes beyond, a terrace under the camp, basins under the pools."""
    d = wk.sd_round_rect(x, z, 22, 34, 10)
    m = sm(c01(d / 18))
    n1 = fbm(x * 0.013 + 5.3, z * 0.013 + 2.2, 2)
    ridge = (1 - abs(n1)) ** 1.6 * 17
    roll = fbm(x * 0.03 + 9, z * 0.03 + 4, 3) * 3.5 + fbm(x * 0.09, z * 0.09, 2) * 0.6
    h = ridge + roll + 3
    back = sm(c01((-z - 26) / 30)) * (1 - sm(c01((abs(x) - 22) / 16)))
    pd = pool_dist(x, z)
    flat = sm(c01((pd - 1.1) / 0.7))
    camp = sm(c01((math.hypot(x + 33, z - 27) - 12) / 10))
    h *= (1 - 0.9 * back) * m * flat * camp
    h -= 0.45 * sm(c01(1 - (pd - 0.2) / 1.05))
    return -0.05 + h


def in_slab(x, z):
    return abs(x) < 18.5 and abs(z) < 33.5


def sky(az, el):
    """The page gradient, plus the low sun's glow and halo (its sprites, painted into the map)."""
    base = wk.css_sky(SKY)(az, el)
    d = (math.cos(el) * math.sin(az), math.sin(el), math.cos(el) * math.cos(az))
    ang = math.degrees(math.acos(clamp(wk._dot(d, SUN_DIR), -1, 1)))
    glow = 0.9 * math.exp(-(ang / 7.5) ** 2) + 0.35 * math.exp(-(ang / 16) ** 2)
    sun = wk.rgb('#ffcf7a')
    return tuple(min(1.0, base[i] + sun[i] * glow) for i in range(3))


# ---------------------------------------------------------------- the pitch's own paint
def decorate(turf, paint):
    sand = mix(mix(SURFACE['base'], SURFACE['stripe'], 0.5), '#d6ac6a', 0.11)
    for i in range(120):                                       # patches hugging the outline
        side = i % 4
        if side == 0:
            x, z = -wk.HW + R(0, 1.76), R(-wk.HL, wk.HL)
        elif side == 1:
            x, z = wk.HW - R(0, 1.76), R(-wk.HL, wk.HL)
        elif side == 2:
            x, z = R(-wk.HW, wk.HW), -wk.HL + R(0, 2.0)
        else:
            x, z = R(-wk.HW, wk.HW), wk.HL - R(0, 2.0)
        rx, rz = R(0.4, 1.75), R(0.25, 0.75)
        x, z = clamp(x, -wk.HW + rx + 0.2, wk.HW - rx - 0.2), clamp(z, -wk.HL + rx + 0.2, wk.HL - rx - 0.2)
        if wk.sd_round_rect(x, z, r=2.0) < -rx - 0.1:
            paint.dab(x, z, rx, sand, n=7, rz=rz, phase=R(0, 3))
    worn = mix(mix(SURFACE['base'], SURFACE['stripe'], 0.5), '#b89a55', 0.08)
    for zt in (-27.3, 27.3):                                   # trampled goal mouths
        for _ in range(7):
            turf.disc(R(-4, 4), wk.DECOR_Y * 1.5, zt + R(-1.1, 1.1), R(0.9, 3.0), 7, worn, rz=R(0.4, 1.1), phase=R(0, 3))
    streak = mix(SURFACE['base'], '#e2bc7c', 0.16)
    for _ in range(26):                                        # wind-blown sand on the pool side
        x0, z0 = wk.HW - R(0.15, 2.6), R(-28, 28)
        pts = [(x0, z0), (x0 - R(0.6, 2.0), z0 + R(-0.9, 0.9)), (x0 - R(1.2, 4.4), z0 + R(-1.2, 1.2))]
        turf.strip(pts, 0.09, wk.DECOR_Y, streak)


# ---------------------------------------------------------------- dunes
LOW, HIGH = (0.86, 0.60, 0.34), (0.99, 0.85, 0.62)
WARM, COOL = (1.0, 0.76, 0.42), (0.72, 0.46, 0.50)
GREEN, WET, TRAMPLED = (0.52, 0.62, 0.30), (0.55, 0.40, 0.25), (0.84, 0.64, 0.40)
SUN_LIGHT = wk._norm((-40, 30, 14))


def dune_colour(x, y, z, n):
    facing = wk._dot(n, SUN_LIGHT) - SUN_LIGHT[1]
    t = round(c01(y / 15) * 3) / 3
    c = [LOW[i] + (HIGH[i] - LOW[i]) * t for i in range(3)]
    sh = round(c01(-facing * 3.0) * 0.7 * 3) / 3 * 0.7 / 0.7
    lt = round(c01(facing * 3.0) * 0.45 * 3) / 3
    c = [c[i] + (COOL[i] - c[i]) * min(sh, 0.7) for i in range(3)]
    c = [c[i] + (WARM[i] - c[i]) * lt for i in range(3)]
    pd = pool_dist(x, z)
    if pd < 2.4:
        f = round(c01((2.4 - pd) / 1.4) * 0.55 * 3) / 3
        c = [c[i] + (GREEN[i] - c[i]) * f for i in range(3)]
    if pd < 1.35:
        c = list(WET)
    ap = 1 - sm(c01(wk.sd_round_rect(x, z, 22, 34, 10) / 14))
    ap = round(ap * 2) / 2
    c = [c[i] + (TRAMPLED[i] - c[i]) * ap * 0.5 for i in range(3)]
    return wk.hexs(c)


def dunes(m):
    N, half = 64, 300.0
    mp = lambda u: half * (0.28 * u + 0.72 * u * u * u)
    xs = [mp(i / N * 2 - 1) for i in range(N + 1)]
    beyond = lambda x0, z0, x1, z1: math.hypot((x0 + x1) / 2, (z0 + z1) / 2) > 305 or \
        (max(abs(x0), abs(x1)) < 16 and max(abs(z0), abs(z1)) < 31)
    m.field(xs, xs, height, dune_colour, skip=beyond, warp=lambda x, z: wk.push_out(x, z, 0.5, 2.0))


# ---------------------------------------------------------------- pools
def clamp_slab(x, z, lim):
    if abs(x) < lim and abs(z) < lim + 15:
        px, pz = lim - abs(x), lim + 15 - abs(z)
        if px < pz:
            x = math.copysign(lim, x or 1)
        else:
            z = math.copysign(lim + 15, z or 1)
    return x, z


def pools(m, fx):
    c_in, c_out = '#0d8085', '#73e0d1'
    segs = 36
    for p in POOLS:
        ring = lambda f, lim, y: [(*clamp_slab(p[0] + math.cos(2 * math.pi * s / segs) * pool_r(p, 2 * math.pi * s / segs) * f,
                                              p[1] + math.sin(2 * math.pi * s / segs) * pool_r(p, 2 * math.pi * s / segs) * f, lim), y)
                                   for s in range(segs)]
        shore = ring(1.16, 18.4, -0.07)
        m.up([(x, y, z) for x, z, y in shore], '#8c6541')
        for k, f in enumerate((1.0, 0.75, 0.5, 0.25)):
            pts = ring(f, 18.6, 0.08 + 0.004 * k)
            m.up([(x, y, z) for x, z, y in pts], mix(c_out, c_in, (k + 0.5) / 4))
        for _ in range(16):                                    # glints (the prototype's sparkles)
            th = R(0, 2 * math.pi)
            rr = pool_r(p, th) * math.sqrt(R(0.05, 0.85))
            x, z = clamp_slab(p[0] + math.cos(th) * rr, p[1] + math.sin(th) * rr, 19)
            R(0, 3)                                            # (the draw the old glint's yaw took)
            fx['sparkles'].particle((x, 0.16, z), '#fff6d8')
        sp = fx['sparkles']
        for _ in range(38):                                    # and more, on the effect's own seed
            th = sp.rng.uniform(0, 2 * math.pi)
            rr = pool_r(p, th) * math.sqrt(sp.rng.uniform(0.05, 0.9))
            x, z = clamp_slab(p[0] + math.cos(th) * rr, p[1] + math.sin(th) * rr, 19)
            sp.particle((x, 0.16, z), sp.rng.choice(['#fff6d8', '#ffffff', '#fff0b8']))


# ---------------------------------------------------------------- palms
def sway_phase(x, z):
    """The prototype's per-instance phase of the breeze (x·0.31 + z·0.17), as a fraction of a turn."""
    return ((x * 0.31 + z * 0.17) / (2 * math.pi)) % 1.0


def palm(m, fx, x, z, h):
    y = height(x, z) - 0.15
    yaw, s = R(0, 2 * math.pi), R(0.85, 1.25)
    bend = (math.cos(yaw), -math.sin(yaw))
    pts = []
    for k in range(6):
        t = k / 5
        pts.append((x + bend[0] * 0.9 * s * t * t, y + h * t, z + bend[1] * 0.9 * s * t * t))
    bands = ['#7d5232', '#5a3a20']
    for k in range(5):
        m.frustum(pts[k], pts[k + 1], 0.36 * s * (1 - 0.44 * k / 5), 0.36 * s * (1 - 0.44 * (k + 1) / 5), 6, bands[k % 2])
    top = pts[-1]
    crown = fx['sway'].piece(lambda pt: (wk.clamp(math.hypot(pt[0] - top[0], pt[2] - top[2]) / 4.0, 0.0, 1.0), sway_phase(x, z)))
    m = crown.__enter__()                                     # the crown sways: its weight grows outward
    cs = R(0.85, 1.15) * (0.75 + h / 20)
    tint = R(0.9, 1.05)
    greens = [wk.scale('#2f6b2a', tint), wk.scale('#4f9a3c', tint), wk.scale('#8cc45a', tint)]
    a0 = R(0, 6.28)
    for count, tilt, ln, droop in ((6, 0.35, 3.3, 1.0), (5, -0.12, 3.6, 1.5), (2, 0.95, 2.2, 0.6)):
        for i in range(count):
            yw = a0 + 2 * math.pi * i / count + R(-0.25, 0.25)
            L, dr = ln * R(0.85, 1.15) * cs, droop * R(0.8, 1.3) * cs
            dx, dz = math.cos(yw), math.sin(yw)
            while L > 0.5 and wk.sd_round_rect(top[0] + dx * (L + 0.4), top[2] + dz * (L + 0.4), r=2.0) < 0.3:
                L *= 0.85                                      # no frond reaches over the pitch
            prev = None
            for k in range(4):
                t = k / 3
                along = L * t
                yy = top[1] + 0.15 * cs + math.sin(tilt) * along * 0.5 + 0.21 * math.sin(math.pi * min(t, 0.5)) * cs - dr * t * t
                w = (0.6 * (1 - 0.82 * t) + 0.06) * cs
                c = (top[0] + dx * along * math.cos(tilt * 0.5), yy, top[2] + dz * along * math.cos(tilt * 0.5))
                pair = ((c[0] - dz * w / 2, c[1], c[2] + dx * w / 2), (c[0] + dz * w / 2, c[1], c[2] - dx * w / 2))
                if prev:
                    m.face([prev[0], prev[1], pair[1], pair[0]], greens[k - 1], facing=(0, 1, 0))
                prev = pair
        a0 += 0.6
    m.blob((top[0], top[1] + 0.05, top[2]), 0.42 * cs, '#6b4a2a', level=0)
    for i in range(2):
        m.blob((top[0] + math.cos(i * 2.4) * 0.35 * cs, top[1] - 0.2 * cs, top[2] + math.sin(i * 2.4) * 0.35 * cs), 0.24 * cs, '#5a3d22', level=0)
    crown.__exit__()


def palms(m, fx):
    spots = []

    def add(x, z, h):
        if not in_slab(x, z) and pool_dist(x, z) > 1.1:
            spots.append((x, z, h))
    for _ in range(16):
        th = R(0, 2 * math.pi)
        rr = pool_r(POOLS[0], th) * R(1.15, 1.7)
        add(POOLS[0][0] + math.cos(th) * rr, POOLS[0][1] + math.sin(th) * rr, R(5, 9.5))
    for _ in range(12):
        th = R(0, 2 * math.pi)
        rr = pool_r(POOLS[1], th) * R(1.18, 1.75)
        add(POOLS[1][0] + math.cos(th) * rr, POOLS[1][1] + math.sin(th) * rr, R(5, 8.5))
    for _ in range(11):
        a, rr = R(0, 2 * math.pi), R(7, 15)
        x, z = -30 + math.cos(a) * rr, 24 + math.sin(a) * rr
        if x < -19.5:
            add(x, z, R(4.8, 8))
    for _ in range(6):
        add(R(-34, -20), R(36, 56), R(6, 10))
    for i in range(8):
        s = 1 if i % 2 else -1
        add(s * R(20, 27), R(-22, 12), R(4.5, 7))
    for i in range(4):
        s = 1 if i % 2 else -1
        add(s * R(23, 34), R(-52, -34), R(5, 8))
    for x, z, h in spots:
        palm(m, fx, x, z, h)


# ---------------------------------------------------------------- rocks, cacti, grass
def rocks(m):
    spots = []
    while len(spots) < 64:
        x, z = R(-90, 90), R(-70, 110)
        if in_slab(x, z) or wk.sd_round_rect(x, z, 20, 35, 6) < 0 or pool_dist(x, z) < 1.25:
            continue
        spots.append((x, z, R(0.4, 2.4)))
    for i in range(26):
        p = POOLS[i % 2]
        th = R(0, 6.28)
        rr = pool_r(p, th) * R(1.03, 1.14)
        x, z = p[0] + math.cos(th) * rr, p[1] + math.sin(th) * rr
        if not in_slab(x, z):
            spots.append((x, z, R(0.25, 0.6)))
    for i in range(8):
        a = i / 8 * 6.28
        spots.append((-33 + math.cos(a) * 1.1, 24 + math.sin(a) * 1.1, R(0.3, 0.42)))
    for x, z, s in spots:
        c = rng.choice(['#c8865a', '#d9a072', '#e3b487', '#9a6642', '#b07a55'])
        m.blob((x, height(x, z) - s * 0.25, z), s, [wk.scale(c, 0.85), c], scale=(R(0.8, 1.4), 0.65, R(0.8, 1.4)),
               level=1 if s > 1.2 else 0, jitter=0.15, rng=rng, yaw=R(0, 6.28))


def cactus(m, x, z, sc, sy):
    y = height(x, z) - 0.1
    yaw = R(0, 6.28)
    ribs = lambda i: '#3d7f39' if i % 2 else '#5aa04a'
    ca, sa = math.cos(yaw), math.sin(yaw)
    P = lambda lx, ly: (x + lx * ca * sc, y + ly * sy, z - lx * sa * sc)
    m.frustum(P(0, 0), P(0, 2.6), 0.38 * sc, 0.3 * sc, 6, None, col_fn=ribs)
    m.blob(P(0, 2.6), 0.3 * sc, '#5aa04a', scale=(1, sy / sc, 1), level=0, cut=-0.1)
    for sx, y0, h in ((1, 1.1, 1.1), (-1, 0.75, 1.5)):
        m.frustum(P(sx * 0.2, y0), P(sx * 0.9, y0), 0.17 * sc, 0.17 * sc, 5, '#4a8f40')
        m.frustum(P(sx * 0.82, y0 - 0.05), P(sx * 0.82, y0 + h - 0.05), 0.18 * sc, 0.16 * sc, 5, None, col_fn=ribs)
        m.blob(P(sx * 0.82, y0 + h - 0.05), 0.16 * sc, '#5aa04a', level=0, cut=-0.1)


def cacti(m):
    n = 0
    while n < 24:
        x, z = R(-70, 70), R(-60, 90)
        if in_slab(x, z) or wk.sd_round_rect(x, z, 21, 36, 6) < 0 or pool_dist(x, z) < 1.7 or math.hypot(x + 31, z - 26) < 13:
            continue
        sc = R(0.7, 1.5)
        cactus(m, x, z, sc, sc * R(0.9, 1.4))
        n += 1


def tuft(fx, x, z, s, col, col2):
    y = height(x, z) - 0.05
    with fx['sway'].piece(lambda pt: (wk.clamp((pt[1] - y) / 2.4, 0.0, 1.0), sway_phase(x, z))) as m:
        for k in range(3):
            a = R(0, 6.28)
            lean = R(0.2, 0.6) * s
            tip = (x + math.cos(a) * lean, y + s * R(0.8, 1.1), z + math.sin(a) * lean)
            w = 0.12 * s
            m.face([(x - math.sin(a) * w, y, z + math.cos(a) * w), (x + math.sin(a) * w, y, z - math.cos(a) * w), tip],
                   col if k % 2 else col2, facing=(math.cos(a), 0.3, math.sin(a)))


def grass(fx):
    for i in range(150):                                       # reeds and lush grass round the pools
        p = POOLS[i % 2]
        th, f = R(0, 6.28), R(1.06, 2.0)
        rr = pool_r(p, th) * f
        x, z = p[0] + math.cos(th) * rr, p[1] + math.sin(th) * rr
        if in_slab(x, z):
            continue
        near = f < 1.3
        tuft(fx, x, z, R(1.4, 2.4) if near else R(0.8, 1.5), '#4f8a3a' if near else '#8aa04e', '#5f9a40' if near else '#9fb35a')
    n = 0
    while n < 190:                                             # dry tufts everywhere else
        x, z = R(-80, 80), R(-60, 95)
        if in_slab(x, z) or wk.sd_round_rect(x, z, 19, 34, 6) < 0 or pool_dist(x, z) < 1.9:
            continue
        tuft(fx, x, z, R(0.6, 1.4), '#d9c070', '#b8a052')
        n += 1


# ---------------------------------------------------------------- ruins, camp, caravan
BRICK, BRICK_D = '#d18c4e', '#b4743f'


def ruins(m):
    AX, AZ, Ri, Ro, PH, D = -26.0, 25.0, 1.9, 2.7, 2.9, 1.5
    gy = height(AX, AZ)
    for s in (-1, 1):                                          # pillars
        m.box(AX, gy - 0.15, AZ + s * (Ri + (Ro - Ri) / 2), D, PH + 0.3, Ro - Ri + 0.2, BRICK, top=BRICK_D)
    n = 10                                                     # the arch, opening towards the pitch
    for k in range(n):
        a0, a1 = math.pi * k / n, math.pi * (k + 1) / n
        pts = lambda a, r: [(AX + dx, gy + PH + r * math.sin(a), AZ + r * math.cos(a)) for dx in (-D / 2, D / 2)]
        i0, i1, o0, o1 = pts(a0, Ri), pts(a1, Ri), pts(a0, Ro), pts(a1, Ro)
        mid = (AX, gy + PH + (Ri + Ro) / 2 * math.sin((a0 + a1) / 2), AZ + (Ri + Ro) / 2 * math.cos((a0 + a1) / 2))
        c = BRICK if k % 2 else BRICK_D
        m.face([o0[0], o1[0], o1[1], o0[1]], c, out=mid)
        m.face([i0[0], i1[0], i1[1], i0[1]], c, out=mid)
        m.face([i0[0], i1[0], o1[0], o0[0]], c, out=mid)
        m.face([i0[1], i1[1], o1[1], o0[1]], c, out=mid)
    m.box(AX, gy + PH + Ro - 0.05, AZ, D + 0.4, 0.5, 0.9, BRICK_D)
    cols = [(-22.5, 14, 4.2, True), (-22.5, 10, 2.1, False), (-22.5, 18, 3.4, False), (-36, 30, 3.8, True), (-40, 27, 1.6, False),
            (-24, 36, 2.6, False), (-13.5, 37.5, 3.4, True), (13.5, 37.5, 2.2, False), (-16, 47, 4.2, True), (16.5, 46, 3.0, True),
            (-10, 58, 2.0, False), (9, 59, 3.6, True)]
    for x, z, h, cap in cols:
        y = height(x, z)
        m.frustum((x, y - 0.1, z), (x, y + h - 0.1, z), 0.5, 0.42, 8, None, col_fn=lambda i: BRICK if i % 2 else BRICK_D, cap=BRICK_D)
        if cap:
            m.box(x, y + h - 0.12, z, 1.3, 0.35, 1.3, BRICK_D, top=BRICK)
    for x, z, w, h, d, yaw in ((-31, 13, 7, 1.4, 0.8, 0.3), (-35.5, 12, 4, 0.9, 0.8, 0.5), (-23.5, 30, 1.2, 1.0, 1.4, 0.7),
                               (12, 36, 1.4, 0.8, 1.1, 0.4), (-12, 34.5, 3.2, 0.5, 0.6, 0.1)):
        m.box(x, height(x, z) - 0.1, z, w, h, d, BRICK, top=BRICK_D, yaw=yaw)


def camp(m, eff):
    stripes = ('#c8412f', '#f7e8c9')
    for x, z, r, h, ry, tint in ((-33, 30, 2.6, 3.4, 0.3, (1, 1, 1)), (-40, 20, 2.3, 3.0, 1.2, (0.78, 0.9, 1.0)), (-35, 38, 2.4, 3.2, 2.2, (1, 0.88, 0.7))):
        y = height(x, z) - 0.1
        tt = lambda c: wk.hexs(tuple(v * tint[i] for i, v in enumerate(wk.rgb(c))))
        m.frustum((x, y, z), (x, y + h, z), r, 0.0, 10, None, phase=ry, col_fn=lambda i: tt(stripes[i % 2]))
        m.frustum((x, y + h - 0.2, z), (x, y + h + 0.4, z), 0.05, 0.05, 4, '#73503a')
        ax, az = x + 2.9, z                                    # the awning, towards the pitch
        corners = [(ax - 1.5, y + 2.2 + 0.27, az - 1.1), (ax + 1.5, y + 2.2 - 0.27, az - 1.1), (ax + 1.5, y + 2.2 - 0.27, az + 1.1), (ax - 1.5, y + 2.2 + 0.27, az + 1.1)]
        for k in range(4):                                     # four stripes across it
            t0, t1 = k / 4, (k + 1) / 4
            L = lambda t, i0, i1: tuple(lerp(corners[i0][j], corners[i1][j], t) for j in range(3))
            m.face([L(t0, 0, 3), L(t1, 0, 3), L(t1, 1, 2), L(t0, 1, 2)], tt(stripes[k % 2]), facing=(0, 1, 0))
        for s in (-1, 1):
            m.frustum((ax + 1.3, y, az + s * 1.4), (ax + 1.3, y + 2.2, az + s * 1.4), 0.05, 0.05, 4, '#73503a')
    for x, z, ry in ((-30.5, 33, 0.2), (-37, 23, -0.3)):
        c = (x, height(x, z) + 0.03, z)
        ca, sa = math.cos(ry), math.sin(ry)
        pts = [(c[0] + dx * ca - dz * sa, c[1], c[2] + dx * sa + dz * ca) for dx, dz in ((-1.2, -0.8), (1.2, -0.8), (1.2, 0.8), (-1.2, 0.8))]
        m.up(pts, '#e6995a')
        m.up([(p[0] * 0.6 + c[0] * 0.4, c[1] + 0.01, p[2] * 0.6 + c[2] * 0.4) for p in pts], '#b8452f')
    colours = ['#2dd4bf', '#f43f5e', '#facc15', '#f97316', '#60a5fa', '#a3e635']

    def string(x0, z0, x1, z1, y0, n):
        for i in range(n):
            t = (i + 0.5) / n
            sag = 0.45 * math.sin(math.pi * t)
            x, z, y = x0 + (x1 - x0) * t, z0 + (z1 - z0) * t, y0 - sag
            dx, dz = (x1 - x0) / n * 0.42, (z1 - z0) / n * 0.42
            with eff['sway'].piece(lambda pt: (0.35 / 1.2, ((pt[0] * 0.9 + pt[2] * 0.4) / (2 * math.pi)) % 1.0)) as flag:
                flag.face([(x - dx, y, z - dz), (x + dx, y, z + dz), (x, y - 0.7, z)], colours[i % len(colours)], facing=(-(z1 - z0), 0.2, x1 - x0))
        for i in range(n * 2):
            t0, t1 = i / (n * 2), (i + 1) / (n * 2)
            P = lambda t: (x0 + (x1 - x0) * t, y0 - 0.45 * math.sin(math.pi * t), z0 + (z1 - z0) * t)
            m.bar(P(t0), P(t1), 0.04, '#5a4030')
        for x, z in ((x0, z0), (x1, z1)):
            g = height(x, z)
            m.frustum((x, g - 0.2, z), (x, y0 + 0.1, z), 0.06, 0.05, 4, '#73503a')
    string(-29, 33, -38, 35.5, height(-29, 34) + 3.2, 9)
    string(20, 14, 20, 23, height(20, 18) + 3.0, 9)
    string(-21, -6, -21, 4, height(-21, -1) + 3.0, 9)
    fx, fz = -33.0, 24.0                                       # the campfire, its lit ground and its glow
    fy = height(fx, fz)
    ground = wk.lit(wk.hexs(TRAMPLED), LIGHT)
    for k, (rr, amt) in enumerate(((2.0, 0.25), (1.2, 0.45))):
        eff.sky.disc(fx, fy + 0.04 + 0.02 * k, fz, rr, 10, wk.add(ground, '#ff8a3a', amt))
    with eff['flame'].piece(lambda pt: (wk.clamp((pt[1] - fy) / 1.0, 0.0, 1.0), 0.0)) as flame:
        flame.frustum((fx, fy, fz), (fx, fy + 1.0, fz), 0.35, 0.0, 6, '#ffa726', col_fn=lambda i: '#ffa726' if i % 2 else '#ffd166')
    eff['fireglow'].particle((fx, fy + 1.0, fz), '#ffb35a')


def dust(fx):
    """Dust blowing along the dunes (+Z), beside the pitch and behind the far goal."""
    m = fx['dust']
    R_ = m.rng.uniform
    for i in range(300):
        if i % 3 == 2:
            x, z = R_(-30, 30), R_(34, 50)
        else:
            x, z = (1 if i % 2 else -1) * R_(17, 55), R_(-45, 15)
        m.particle((x, height(x, z) + R_(0.3, 5), z), m.rng.choice(['#f7c98c', '#f1d2a0', '#e8b87a']))


CAMEL = [(0, 0.9), (0.2, 1.15), (0.5, 1.3), (0.8, 1.45), (0.95, 1.52), (1.0, 1.9), (1.1, 2.12), (1.22, 1.92), (1.28, 1.52), (1.45, 1.42),
         (1.7, 1.2), (1.9, 1.05), (2.05, 1.15), (2.2, 1.45), (2.3, 1.75), (2.4, 1.92), (2.6, 1.97), (2.78, 1.87), (2.82, 1.7), (2.62, 1.66),
         (2.47, 1.55), (2.37, 1.3), (2.27, 1.0), (2.17, 0.8), (2.17, 0.7), (2.22, 0), (2.06, 0), (1.96, 0.62), (1.62, 0.66), (1.56, 0),
         (1.4, 0), (1.36, 0.66), (0.7, 0.66), (0.66, 0), (0.5, 0), (0.46, 0.62), (0.22, 0.6), (0.16, 0), (0, 0), (-0.06, 0.56),
         (-0.22, 0.72), (-0.28, 0.88)]


def caravan(sky_m):
    """Six camel silhouettes walking the dune crest west of the pitch (unlit, as the prototype's)."""
    for i in range(6):
        z, x, s = 10 + i * 4.6 + R(-0.4, 0.4), -49 + R(-1.5, 1.5), R(1.35, 1.6)
        y = height(x, z) - 0.15
        sky_m.face([(x, y + py * s, z + px * s) for px, py in CAMEL], '#3a2418', facing=(1, 0, 0))


def sun(sky_m):
    c = tuple(v * wk.SKY_R * 0.95 for v in SUN_DIR)
    wk.billboard(sky_m, c, 19.0, '#fff4d2', n=20, towards=(0, 0, 0))


# ---------------------------------------------------------------- the world
def build(turf, scen, sky_m, fx):
    fx.sky = sky_m
    wk.rink(turf, scen, SPORT, SURFACE, BORDER, GOAL, decorate=decorate, skirt=-0.6)
    dunes(scen)
    pools(scen, fx)
    palms(scen, fx)
    rocks(scen)
    cacti(scen)
    grass(fx)
    ruins(scen)
    camp(scen, fx)
    caravan(sky_m)
    sun(sky_m)
    dust(fx)


wk.run(WORLD, HERE, wk.Palette(sky), SPORT, build, LIGHT)
