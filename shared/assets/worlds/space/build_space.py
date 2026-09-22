"""
Builds Deep Space (Tiefer Weltraum): a floating arena adrift among the stars (spec §13, ADR 0006).

Re-authored from the prototype's world (web/js/worlds/space.js — read, never run): the same set
pieces in the same places. A midnight-blue pitch with dark mowing stripes, cyan markings, cyan
haze creeping in from its edges, a hex grid brightening towards them, pink glows in the shooting
circles and orbit rings round the centre; deep-blue boards with a cyan rail on a dark rim; below,
the arena's hull with a keel and a spine, outrigger arms with thruster pods and their flames,
neon edge strips and light studs round the rim, floodlight masts, holographic boards; round it
two dashed halo rings, an asteroid belt, a banded gas giant below the far goal, a ringed ice
planet low beside the −X wall, a cratered moon and a small tan one, a wheel station, two
satellites, a comet. The sky: the prototype's painted sky sphere (its gradient, colour washes,
the milky way, nebula clouds and the planets' halos painted into the palette's sky map) with a
starfield. No fog (ADR 0006).

What glows and stands still — the stars, the planet's ring — is in the unlit `sky` mesh; what lives
is in the effects (ADR 0007, shared/data/effects.toml): twinkling stars, breathing nebula puffs,
pulsing neon (edge strips, pod rings, floodlights), the chase round the light studs, flickering
flames and exhaust and floodlight glows, the bobbing holo boards, the turning halo rings, the comet's
lap and the satellites' orbits.
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
from worldkit import T, R as Rot, S, euler, mix, clamp  # noqa: E402

WORLD, SPORT = 'space', 'field'
LIGHT = dict(hemi_sky='#9fd0ff', hemi_ground='#1a1240', hemi=1.05, sun='#fff1d8', sun_i=1.9, sun_pos=(18, 60, -20))
BORDER = dict(color='#0369a1', top='#67e8f9', height=1.1, base='#121a38')
GOAL = dict(post='#f472b6', net='#bae6fd')
BASE, STRIPE, CYAN = '#151c33', '#121829', '#7df9ff'
HW, HL, CORNER = wk.HW, wk.HL, 2.0

rng = random.Random(4207)
R = rng.uniform
TAU = 2 * math.pi

# the planets, pulled inside the dome (their apparent size kept)
GIANT = (tuple(v * 0.8 for v in (38, -200, 252)), 74 * 0.8)
ICE = (tuple(v * 0.8 for v in (-282, -56, 12)), 40 * 0.8)
MOON_BIG = ((-132, -100, 110), 26)
MOON_SMALL = ((248, -28, -14), 14)


# ---------------------------------------------------------------- the painted sky (skyTexture)
def _dir(az, el):
    return (math.cos(el) * math.sin(az), math.sin(el), math.cos(el) * math.cos(az))


def _ang(a, b):
    return math.acos(clamp(wk._dot(a, b), -1.0, 1.0))


SKY_STOPS = [(0.0, '#02030a'), (0.42, '#060a1f'), (0.62, '#0b0b2c'), (0.85, '#170c3a'), (1.0, '#1f0f3f')]


def _tex_uv(d):
    """World direction -> the prototype's equirect (u, v) on its sky sphere (rotated 0.6 about Y)."""
    c, s = math.cos(-0.6), math.sin(-0.6)
    x, y, z = d[0] * c + d[2] * s, d[1], -d[0] * s + d[2] * c
    th = math.acos(clamp(y, -1, 1))
    ph = math.atan2(z, -x) % TAU
    return ph / TAU, th / math.pi


WASHES = [(0.15, 0.62, 520, (90, 40, 160), 0.22), (0.55, 0.72, 600, (20, 90, 150), 0.2),
          (0.85, 0.58, 460, (150, 50, 110), 0.16), (0.38, 0.3, 420, (40, 60, 140), 0.14)]
NEBULAE = [((0.2, -0.45, 1), 0.55, [(124, 58, 237), (34, 211, 238), (219, 39, 119)], 0.32),
           ((-1, -0.25, 0.15), 0.5, [(217, 70, 239), (124, 58, 237), (244, 114, 182)], 0.34),
           ((-0.65, -0.6, 0.6), 0.45, [(225, 29, 72), (168, 85, 247), (34, 211, 238)], 0.36),
           ((1, -0.2, 0.2), 0.5, [(249, 115, 22), (236, 72, 153), (139, 92, 246)], 0.28),
           ((0, 0.5, -1), 0.7, [(79, 70, 229), (14, 165, 233), (147, 51, 234)], 0.2),
           ((0, -1, 0), 0.9, [(109, 40, 217), (29, 78, 216), (190, 24, 93)], 0.22)]


def sky(az, el):
    d = _dir(az, el)
    u, v = _tex_uv(d)
    c = list(wk.gradient(SKY_STOPS, v))
    for bu, bv, rad, col, a in WASHES:                          # broad colour washes (source-over)
        du = min(abs(u - bu), 1 - abs(u - bu)) * 2048
        dist = math.hypot(du, (v - bv) * 1024)
        k = a * max(0.0, 1 - dist / rad)
        c = [c[i] * (1 - k) + col[i] / 255 * k for i in range(3)]
    band = 0.5 + 0.21 * math.sin(u * TAU + 0.9)                 # the milky way: a soft band, a dark lane
    g = math.exp(-((v - band) / 0.085) ** 2)
    lane = math.exp(-((v - band - 0.01) / 0.02) ** 2) * 0.5
    k = 0.2 * g * (1 - lane) * (0.75 + 0.25 * wk.vnoise(u * 40, v * 20))
    c = [c[i] + k * w for i, w in enumerate((0.95, 0.92, 1.0))]
    for cd, spread, cols, bright in NEBULAE:                   # the nebula clouds (additive)
        n = wk._norm(cd)
        a = _ang(d, n)
        w = math.exp(-(a / (spread * 0.75)) ** 2) * bright * 0.55
        if w > 0.002:
            t = 0.5 + 0.5 * math.sin(az * 5 + el * 7 + cd[0] * 3)
            mixc = [lerp3(cols[0], cols[1], t)[i] * 0.6 + cols[2][i] * 0.4 * (1 - t) for i in range(3)]
            c = [c[i] + w * mixc[i] / 255 for i in range(3)]
    for (pos, r), col, k in ((GIANT, (255, 176, 122), 0.55), (ICE, (143, 211, 255), 0.5)):
        n = wk._norm(pos)
        a = _ang(d, n)
        rim = math.asin(min(1.0, r / math.sqrt(wk._dot(pos, pos))))
        w = k * math.exp(-((a - rim) / (rim * 0.18)) ** 2) if a > rim * 0.9 else 0.0
        c = [c[i] + w * col[i] / 255 for i in range(3)]
    return tuple(min(1.0, x) for x in c)


def lerp3(a, b, t):
    return [a[i] + (b[i] - a[i]) * t for i in range(3)]


def stars(sky_m):
    """The starfield: tiny unlit triangles just inside the dome, brighter and denser along the band."""
    tints = ['#ffffff', '#ffffff', '#ccdfff', '#ffebc7', '#ffcc99', '#bfd9ff']
    n = 0
    while n < 900:
        y, t = R(-1, 1), R(0, TAU)
        rr = math.sqrt(1 - y * y)
        d = (rr * math.cos(t), y, rr * math.sin(t))
        u, v = _tex_uv(d)
        band = 0.5 + 0.21 * math.sin(u * TAU + 0.9)
        if rng.random() > 0.45 + math.exp(-((v - band) / 0.16) ** 2):
            continue
        big = rng.random()
        size = R(2.2, 3.2) if big > 0.985 else R(1.3, 2.0) if big > 0.9 else R(0.6, 1.1)
        b = rng.choice((0.6, 0.8, 1.0))
        col = wk.scale(rng.choice(tints), b)
        c = tuple(v_ * wk.SKY_R * 0.96 for v_ in d)
        wk.billboard(sky_m, c, size, col, n=3 if size < 2 else 4, towards=(0, 10, 0), phase=R(0, 6))
        n += 1


# ---------------------------------------------------------------- the pitch's paint (decorate)
def paint(x, z, band):
    """Cyan haze from the edges, pink glow in the shooting circles — per cell of the surface
    (where either shows, the two stripe colours, a shade apart, are painted as one)."""
    ds = min(x + HW, HW - x) / 6.0
    de = min(z + HL, HL - z) / 6.0
    cyan = round(min(0.4, 0.26 * max(0.0, 1 - ds) + 0.26 * max(0.0, 1 - de)) / 0.02) * 0.02
    pink = max(round(0.2 * max(0.0, 1 - math.hypot(x, z - gz) / 11) / 0.02) * 0.02 for gz in (-26, 26))
    if cyan == 0 and pink == 0:
        return band
    c = wk.rgb(mix(BASE, STRIPE, 0.5))
    c = [c[i] + (v - c[i]) * pink for i, v in enumerate((244 / 255, 114 / 255, 182 / 255))]
    c = [c[i] + (v - c[i]) * cyan for i, v in enumerate((56 / 255, 189 / 255, 248 / 255))]
    return wk.hexs(c)


def decorate(turf, pnt):
    Rh = 1.25
    dx, dy = Rh * math.sqrt(3), Rh * 1.5
    row, y = 0, -dy
    mid = mix(BASE, STRIPE, 0.5)
    while y < 2 * HL + dy:                                     # the hex grid, brighter to the edges
        off = dx / 2 if row % 2 else 0.0
        x = -dx
        while x < 2 * HW + dx:
            cx, cz = x + off - HW, y - HL
            d = min(cx + HW, HW - cx, cz + HL, HL - cz)
            f = max(0.0, 1 - d / 9)
            a = 0.03 + 0.24 * f * f
            if a >= 0.075:
                pts = [(cx + Rh * math.cos(math.pi / 6 + k * math.pi / 3), cz + Rh * math.sin(math.pi / 6 + k * math.pi / 3)) for k in range(7)]
                if all(abs(px) < HW - 0.05 and abs(pz) < HL - 0.05 and wk.sd_round_rect(px, pz, r=CORNER) < -0.1 for px, pz in pts):
                    turf.strip(pts, 0.07, wk.DECOR_Y, mix(mid, CYAN, round(a / 0.07) * 0.07))
            x += dx
        y += dy
        row += 1
    for r in (4.2, 5.6):                                       # the centre orbit rings
        turf.annulus(0, wk.DECOR_Y, 0, r - 0.045, r + 0.045, 48, mix(mid, '#f0abfc', 0.35))
    turf.annulus(0, wk.DECOR_Y, 0, 7.2 - 0.06, 7.2 + 0.06, 64, mix(mid, CYAN, 0.45), dashed=0.44)


# ---------------------------------------------------------------- the hull, pods, masts, neon
HULL, HULL_D, ARM, POLE = '#1b2542', '#141b33', '#4b5b8c', '#64748b'
NEON = ['#22d3ee', '#e879f9', '#38bdf8']


def hull(m, fx):
    ring = lambda off, y: [(x, y, z) for x, z, _, _ in wk._rr_ring(off, CORNER, 6)]
    levels = [(wk.SLAB_W, -0.7, HULL), (wk.SLAB_W + 1.2, -1.6, HULL), (wk.SLAB_W + 1.2, -3.8, HULL_D), (wk.SLAB_W, -4.7, HULL_D)]
    rings = [ring(off, y) for off, y, _ in levels]
    for k in range(len(rings) - 1):
        A, B = rings[k], rings[k + 1]
        for i in range(len(A)):
            j = (i + 1) % len(A)
            m.face([A[i], A[j], B[j], B[i]], levels[k + 1][2], out=(0, (A[i][1] + B[i][1]) / 2, 0))
    m.face(rings[-1], HULL_D, facing=(0, -1, 0))
    m.box(0, -6.2, 0, HW * 1.4, 1.6, HL * 1.9, HULL_D, top=HULL)                     # the keel
    m.frustum((0, -6.6, -HL * 1.15), (0, -6.6, HL * 1.15), 1.6, 1.6, 12, HULL, cap=HULL_D, bottom=HULL_D)
    m.frustum((-HW * 1.3, -6.6, 0), (HW * 1.3, -6.6, 0), 1.2, 1.2, 12, HULL, cap=HULL_D, bottom=HULL_D)
    # neon edge strips: on the rim, at its edge, and round the hull's widest point
    neon = fx['neon']
    neon.ring_band(0.55, 0.85, 0.001, 0.081, CORNER, NEON[0], per=6, inner=True, outer=True)
    neon.ring_band(1.85, 2.2, 0.001, 0.081, CORNER, NEON[1], per=6, inner=True, outer=True)
    neon.ring_band(3.35, 3.65, -2.3, -2.0, CORNER, NEON[2], per=6, inner=True, outer=True)
    studs = wk.rr_points(1.4, CORNER, 72)                      # the 72 light studs: a wave chases round
    for i, (x, z) in enumerate(studs):
        w = 0.5 + 0.5 * math.sin(-i * 0.35)
        col = wk.hexs(_hsl(0.5 + 0.35 * w, 1.0, 0.3 + 0.55 * w))
        with fx['studs'].piece((1.0, (-i * 0.35 / TAU) % 1.0)):
            fx['studs'].octa((x, 0.12, z), 0.2, 0.2, col)


def _hsl(h, s, l):
    import colorsys
    return colorsys.hls_to_rgb(h % 1.0, l, s)


def pods(m, fx):
    spots = [(HW + 9.5, -1.5, -12, 0), (HW + 9.5, -1.5, 12, 0), (-HW - 9.5, -1.5, -12, 0), (-HW - 9.5, -1.5, 12, 0),
             (9, -1.5, HL + 13, 1), (-9, -1.5, HL + 13, 1), (9, -1.5, -HL - 13, 1), (-9, -1.5, -HL - 13, 1)]
    for x, y, z, axis in spots:
        if axis == 0:
            m.box(math.copysign(HW + 5.5, x), y - 0.5, z, 9, 1.0, 2.6, ARM)
        else:
            m.box(x, y - 0.5, math.copysign(HL + 6.5, z), 2.6, 1.0, 12, ARM)
        m.frustum((x, y - 1.5, z), (x, y + 1.5, z), 1.7, 1.5, 14, ARM, cap=HULL, bottom=HULL)
        m.frustum((x, y + 1.5, z), (x, y + 3.2, z), 0.09, 0.09, 5, POLE)
        _torus(fx['neon'], (x, y + 0.2, z), 1.62, 0.13, 20, NEON[0])
        fx['neon'].frustum((x, y + 1.47, z), (x, y + 1.63, z), 1.1, 1.1, 14, NEON[0], cap='#b8fcff')
        fx['neon'].blob((x, y + 3.3, z), 0.3, CYAN, level=0)
        ex = fx['exhaust']                                     # the flame: bright at the nozzle, fading to its tip
        with ex.piece(lambda pt, y=y: (wk.clamp((pt[1] - (y - 6.5)) / 5.0, 0.0, 1.0), 0.0)):
            ex.frustum((x, y - 1.5, z), (x, y - 6.5, z), 1.1, 0.0, 12, '#60c8ff', col_fn=lambda i: '#60c8ff' if i % 2 else '#8fdcff')
        ex.halo((x, y - 1.7, z), 3.25, '#7dd3fc', n=14)       # the exhaust glow disc under the pod


def _torus(m, c, R_, r, n, col, normal=(0, 1, 0)):
    """A torus as a ring of short square rods."""
    ref = (1, 0, 0) if abs(normal[0]) < 0.9 else (0, 0, 1)
    u = wk._norm(wk._cross(normal, ref))
    v = wk._cross(normal, u)
    P = lambda a: tuple(c[k] + R_ * (math.cos(a) * u[k] + math.sin(a) * v[k]) for k in range(3))
    for i in range(n):
        m.bar(P(TAU * i / n), P(TAU * (i + 1) / n), r * 2, col)


def masts(m, fx):
    for x, z in ((HW + 4.2, -22), (HW + 4.2, 0), (HW + 4.2, 22), (-HW - 4.2, -22), (-HW - 4.2, 0), (-HW - 4.2, 22)):
        s = math.copysign(1, x)
        m.frustum((x, 0, z), (x, 8.5, z), 0.22, 0.14, 7, POLE)
        m.box(x - s * 0.6, 8.35, z, 2.4, 0.5, 0.7, POLE, roll=-s * 0.35)
        fx['neon'].box(x - s * 0.6, 8.05, z, 2.1, 0.12, 0.5, '#9ffcff', roll=-s * 0.35)
        for normal in ((1, 0, 0), (0, 0, 1)):                  # the floodlight's two crossed glows
            fx['exhaust'].halo((x - s * 1.2, 8.4, z), 2.0, '#7dd3fc', n=12, normal=normal)


def holo_boards(fx):
    """The four holographic boards beside the pitch: a navy panel framed in cyan, a pink planet
    with a cyan ring, a bar graph, yellow chevrons (the prototype's canvas, as geometry)."""
    sky_m = fx['holo']
    for bx, bz in ((HW + 6.5, -11), (HW + 6.5, 11), (-HW - 6.5, -11), (-HW - 6.5, 11)):
        s = math.copysign(1, bx)
        facing = (-s, 0, 0)
        P = lambda u, v, d=0.0: (bx - s * d, 4.2 + v, bz - s * u)   # u across the board (7), v up (3.5)
        sky_m.face([P(-3.5, -1.75), P(3.5, -1.75), P(3.5, 1.75), P(-3.5, 1.75)], '#0a1a44', facing=facing)
        for a, b in (((-3.5, -1.75), (3.5, -1.75)), ((3.5, -1.75), (3.5, 1.75)), ((3.5, 1.75), (-3.5, 1.75)), ((-3.5, 1.75), (-3.5, -1.75))):
            (u0, v0), (u1, v1) = a, b
            du, dv = (0.0, 0.08) if v0 == v1 else (0.08, 0.0)
            sky_m.face([P(u0 - du, v0 - dv, 0.02), P(u1 - du, v1 - dv, 0.02), P(u1 + du, v1 + dv, 0.02), P(u0 + du, v0 + dv, 0.02)], CYAN, facing=facing)
        cu, cv = -3.5 + 7 * 110 / 512, 0.0
        sky_m.face([P(cu + 0.74 * math.cos(t), cv + 0.74 * math.sin(t), 0.03) for t in (TAU * k / 12 for k in range(12))], '#f472b6', facing=facing)
        for k in range(20):
            t0, t1 = TAU * k / 20, TAU * (k + 1) / 20
            e = lambda t, r: (cu + r * 1.26 * (math.cos(t) * math.cos(-0.35) - 0.24 * math.sin(t) * math.sin(-0.35)),
                              cv + r * 1.26 * (math.cos(t) * math.sin(-0.35) + 0.24 * math.sin(t) * math.cos(-0.35)))
            a0, a1, b0, b1 = e(t0, 0.94), e(t1, 0.94), e(t0, 1.06), e(t1, 1.06)
            sky_m.face([P(*a0, 0.04), P(*a1, 0.04), P(*b1, 0.04), P(*b0, 0.04)], CYAN, facing=facing)
        for i in range(9):
            h = R(30, 120) / 256 * 3.5
            u0 = -3.5 + 7 * (230 + i * 28) / 512
            v0 = 1.75 - 3.5 * 200 / 256
            sky_m.face([P(u0, v0, 0.03), P(u0 + 0.25, v0, 0.03), P(u0 + 0.25, v0 + h, 0.03), P(u0, v0 + h, 0.03)],
                    '#7df9ff' if i % 2 else '#f0abfc', facing=facing)
        for i in range(4):
            u0 = -3.5 + 7 * (250 + i * 60) / 512
            pts = [(u0, 1.75 - 3.5 * 34 / 256), (u0 + 0.36, 1.75 - 3.5 * 56 / 256), (u0, 1.75 - 3.5 * 78 / 256)]
            for (ua, va), (ub, vb) in zip(pts, pts[1:]):
                sky_m.face([P(ua, va - 0.06, 0.03), P(ub, vb - 0.06, 0.03), P(ub, vb + 0.06, 0.03), P(ua, va + 0.06, 0.03)], '#faf08a', facing=facing)


def halo_rings(fx):
    """The two dashed rings; the outer turns backwards at 0.07 rad/s against the effect's 0.12:
    each ring's speed factor k rides in w = (k + 1) / 2."""
    for R_, y, r, reps, col, spin, k in ((46, -10, 0.32, 28, '#7df9ff', 0.0, 1.0), (53, -14, 0.2, 10, '#f0abfc', 0.7, -0.07 / 0.12)):
        sky_m = fx['orbits']
        sky_m.datafn = lambda pt, k=k: ((k + 1) / 2, 0.0)
        n = 240
        for i in range(n):
            f = (i + 0.5) / n * reps % 1.0 * 256
            if not (f < 150 or 176 <= f < 206):
                continue
            a0, a1 = TAU * i / n + spin, TAU * (i + 1) / n + spin
            sky_m.bar((R_ * math.cos(a0), y, R_ * math.sin(a0)), (R_ * math.cos(a1), y, R_ * math.sin(a1)), r * 2, col)


# ---------------------------------------------------------------- planets, moons, belt, station
def banded_sphere(m, c, r, bands, seg, tilt=0.0, spots=None):
    """A UV sphere whose rings follow `bands` [(height fraction, colour)] from the north pole."""
    M = T(*c) @ Rot(tilt, 'Z') @ S(r)
    mm = m.xf(M)
    th = [0.0]
    for h, _ in bands:
        th.append(th[-1] + h)
    th = [t / th[-1] * math.pi for t in th]
    P = lambda t, a: (math.sin(t) * math.cos(a), math.cos(t), math.sin(t) * math.sin(a))
    for k, (_, col) in enumerate(bands):
        for i in range(seg):
            a0, a1 = TAU * i / seg, TAU * (i + 1) / seg
            cc = spots(k, i, col) if spots else col
            pts = [P(th[k], a0), P(th[k], a1), P(th[k + 1], a1), P(th[k + 1], a0)]
            if k == 0:
                pts = [P(0, 0), P(th[1], a1), P(th[1], a0)]
            elif k == len(bands) - 1:
                pts = [P(th[k], a0), P(th[k], a1), P(math.pi, 0)]
            mm.face(pts, cc, out=(0, 0, 0))


def planets(m, sky_m):
    gp = ['#f3dcae', '#e6b98a', '#c9776a', '#f6e7c9', '#a45c6b', '#e2a27c', '#6f4c8f', '#f1d4b2', '#d98a6a', '#8b5a97']
    bands, total, i = [], 0.0, 0
    while total < 512:
        h = R(14, 58)
        bands.append((h, gp[i % len(gp)]))
        total += h
        i += 1
    storm = lambda k, i_, col: ('#f5e0d0' if (k, i_) in ((len(bands) * 6 // 10, 17), (len(bands) * 6 // 10, 18)) else col)
    banded_sphere(m, GIANT[0], GIANT[1], bands, 32, tilt=0.28, spots=storm)
    ip = ['#a9cdf7', '#e6f2ff', '#7fb0e6', '#bfdcff', '#d9ecff', '#8fbdf0']
    bands, total, i = [], 0.0, 0
    while total < 256:
        h = R(8, 40)
        bands.append((h, ip[i % len(ip)]))
        total += h
        i += 1
    banded_sphere(m, ICE[0], ICE[1], bands, 24)
    pos, r = ICE
    normal = wk._norm((0.55, 0.8, 0.25))
    ref = (1, 0, 0)
    u = wk._norm(wk._cross(normal, ref))
    v = wk._cross(normal, u)
    bg = '#140c33'
    steps = 14
    for k in range(steps):                                     # the rings: bands, unlit
        r0, r1 = r * (1.35 + 1.1 * k / steps), r * (1.35 + 1.1 * (k + 1) / steps)
        t = (k + 0.5) / steps
        gap = math.sin(t * 40) * 0.5 + math.sin(t * 7.3) * 0.5
        a = max(0.0, 0.15 + 0.55 * (0.5 + 0.5 * gap)) * ((1 - t) / 0.07 if t > 0.93 else 1)
        col = (215, 200, 255) if t < 0.35 else (250, 235, 205) if t < 0.7 else (180, 215, 255)
        cc = mix(bg, wk.hexs(tuple(x / 255 for x in col)), a)
        n = 48
        for i in range(n):
            a0, a1 = TAU * i / n, TAU * (i + 1) / n
            p = lambda aa, rr: tuple(pos[j] + rr * (math.cos(aa) * u[j] + math.sin(aa) * v[j]) for j in range(3))
            sky_m.face([p(a0, r0), p(a1, r0), p(a1, r1), p(a0, r1)], cc, facing=normal)
    moon = lambda k, i_, col: '#6f6e80' if wk._hash2(k * 7 + 3, i_ * 13 + 1) < 0.18 else ('#b4b2be' if wk._hash2(k, i_) < 0.25 else col)
    mb = [(1, '#9b9ca8')] * 12
    banded_sphere(m, MOON_BIG[0], MOON_BIG[1], mb, 18, tilt=0.4, spots=moon)
    ms = [(1, '#c9bba6')] * 9
    banded_sphere(m, MOON_SMALL[0], MOON_SMALL[1], ms, 14, spots=lambda k, i_, col: '#8f8577' if wk._hash2(k + 9, i_ + 4) < 0.2 else col)


def belt(m):
    M = euler(0.5, 0, 0.35)
    for k in range(150):
        a = R(0, TAU)
        r = 132 + R(-18, 26) + (R(20, 40) if rng.random() > 0.85 else 0.0)
        p = tuple(M @ wk.Vector((math.cos(a) * r, R(-9, 9), math.sin(a) * r)))
        s = R(1.2, 4.0) * (1.6 if rng.random() > 0.92 else 1.0)
        m.blob(p, s, ['#6f655f', '#8b7f78', '#9a8f88'], scale=(R(0.7, 1.3), R(0.7, 1.3), R(0.7, 1.3)), level=0, jitter=0.2, rng=rng, yaw=R(0, TAU))


def station(m):
    mm = m.xf(T(214, -18, 24) @ euler(0.25, -0.7, 0.15))
    col, dark = '#c7ccd6', '#8e96a8'
    n = 24
    for i in range(n):                                          # the wheel (in the XY plane)
        a0, a1 = TAU * i / n, TAU * (i + 1) / n
        mm.frustum((12 * math.cos(a0), 12 * math.sin(a0), 0), (12 * math.cos(a1), 12 * math.sin(a1), 0), 1.5, 1.5, 6, col)
    mm.frustum((0, 0, -3), (0, 0, 3), 3, 3, 14, col, cap=dark, bottom=dark)
    for i in range(6):
        a = TAU * i / 6
        mm.bar((0, 0, 0), (12 * math.cos(a), 12 * math.sin(a), 0), 0.7, dark)
    mm.frustum((0, 0, -22), (0, 0, 22), 1, 1, 8, dark, cap=col, bottom=col)
    for s in (-1, 1):
        mm.box(0, -0.125, s * 17, 16, 0.25, 6, '#2b4f9e', top='#3b6fd8')
        mm.box(0, -1.2, s * 21, 2.4, 2.4, 3, col)


def satellites(fx):
    for x, z, ry in ((60, 0, 0.3), (-40, 52, 1.9)):
        mm = fx['satellites'].xf(T(x, -5.5, z) @ Rot(ry, 'Y'))
        mm.box(0, -0.7, 0, 1.4, 1.4, 2.0, '#d9dee8')
        for s in (-1, 1):
            mm.box(s * 2.6, -0.04, 0, 3.6, 0.08, 1.4, '#2b4f9e', top='#3b6fd8')
        mm.frustum((0, 0.75, 0), (0, 1.25, 0), 0.0, 0.8, 12, '#d9dee8')


def comet(fx):
    """The comet laps the low sky at 0.045 rad/s: its speed factor against the orbits' 0.12."""
    sky_m = fx['orbits']
    sky_m.datafn = lambda pt: ((0.045 / 0.12 + 1) / 2, 0.0)
    a = 2.2
    c = (math.cos(a) * 300, -30 + 40 * math.sin(a * 2), math.sin(a) * 300)
    d = wk._norm((-math.sin(a), 0.15, math.cos(a)))
    wk.billboard(sky_m, c, 2.6, '#ffffff', n=10, towards=(0, 0, 0))
    up = wk._norm(wk._cross(d, wk._norm(c)))
    for k, (l0, l1, w0, w1, col) in enumerate(((0, 14, 2.4, 1.9, '#b4e6ff'), (14, 30, 1.9, 1.2, '#5f8fc4'), (30, 46, 1.2, 0.3, '#2c3f78'))):
        p = lambda l, w: tuple(c[j] - d[j] * l + up[j] * w for j in range(3))
        sky_m.face([p(l0, -w0), p(l1, -w1), p(l1, w1), p(l0, w0)], col, facing=wk._neg(c))


# ---------------------------------------------------------------- the world
def twinkling_stars(fx):
    """Stars that twinkle (effect particles), spread like the static field, denser along the band."""
    m = fx['stars']
    R_ = m.rng.uniform
    tints = ['#ffffff', '#ffffff', '#ccdfff', '#ffebc7', '#ffcc99', '#bfd9ff']
    n = 0
    while n < 220:
        y, t = R_(-0.35, 1), R_(0, TAU)
        rr = math.sqrt(1 - y * y)
        d = (rr * math.cos(t), y, rr * math.sin(t))
        u, v = _tex_uv(d)
        band = 0.5 + 0.21 * math.sin(u * TAU + 0.9)
        if m.rng.random() > 0.45 + math.exp(-((v - band) / 0.16) ** 2):
            continue
        m.particle(tuple(c * wk.SKY_R * 0.93 for c in d), wk.scale(m.rng.choice(tints), m.rng.choice((0.8, 1.0))))
        n += 1


def nebula(fx):
    """The prototype's additive nebula puffs over the painted clouds (they breathe, each on its own beat)."""
    m = fx['nebula']
    R_ = m.rng.uniform
    for cd, spread, cols, bright in NEBULAE:
        d = wk._norm(cd)
        for _ in range(12):
            p = wk._norm((d[0] + R_(-spread, spread), d[1] + R_(-spread, spread) * 0.6, d[2] + R_(-spread, spread)))
            r = R_(55, 110)
            col = m.rng.choice(cols)
            k = R_(bright * 0.6, bright) * 2.2
            m.halo(tuple(c * wk.SKY_R * 0.88 for c in p), r, wk.hexs(tuple(min(1.0, v / 255 * k) for v in col)),
                   p=R_(0, 1), n=10, normal=wk._neg(p), r2=r * R_(0.6, 1.0), yaw=R_(0, TAU))


def build(turf, scen, sky_m, fx):
    surface = dict(base=BASE, stripe=STRIPE, lines=CYAN, paint=(paint, 0.5))
    wk.rink(turf, scen, SPORT, surface, BORDER, GOAL, decorate=decorate, skirt=-0.7)
    hull(scen, fx)
    pods(scen, fx)
    masts(scen, fx)
    holo_boards(fx)
    halo_rings(fx)
    planets(scen, sky_m)
    belt(scen)
    station(scen)
    satellites(fx)
    stars(sky_m)
    comet(fx)
    twinkling_stars(fx)
    nebula(fx)


wk.run(WORLD, HERE, wk.Palette(sky), SPORT, build, LIGHT)
