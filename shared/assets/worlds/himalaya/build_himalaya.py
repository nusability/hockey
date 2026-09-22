"""
Builds Himalaya: thin air, blue ice and prayer flags among the peaks (spec §13, ADR 0006).

Ice hockey (spec §1: corner radius 8.5). Re-authored from the prototype's world
(web/js/worlds/himalaya.js — read, never run): an ice sheet with skating marks, red goal and
centre lines, blue lines, face-off circles and blue creases, white boards with a red rail and a
glass frame above them on a grey-blue rim. Around it one polar heightfield: a snowy plateau, an
abyss to +X whose rim drops to a valley floor with a sea of cloud below it and giants across it, a
frozen lake basin to −X, foothills and ridges of snow-capped peaks all round (pulled inside the
dome, their apparent size kept). On it: snow-dusted pines, boulders, stone cairns, glacier seracs
and ice blocks, a monastery on a mesa, stupas with prayer flags radiating from their spires, and
strings of prayer flags on poles round the rink. The sky: the page gradient, deep blue over a
white horizon. No fog (ADR 0006). What lives is in the effects (ADR 0007, shared/data/effects.toml):
the prayer flags flutter, a wave running along each string; soft cloud wisps drift over the sea of
cloud, round the far peaks and over the lake; snow falls, over the rink too.

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

WORLD, SPORT = 'himalaya', 'ice'
SKY = [(0.0, '#2a67cc'), (0.28, '#5b9fe6'), (0.52, '#a9d3f4'), (0.72, '#e3f1fb'), (1.0, '#f4f9fd')]
LIGHT = dict(hemi_sky='#d6e9ff', hemi_ground='#9fb6cc', hemi=0.95, sun='#ffe4bf', sun_i=2.0, sun_pos=(-35, 46, -26))
SURFACE = dict(base='#eef6fd', stripe='#e3eef9', lines='#1d4ed8')
BORDER = dict(color='#f8fafc', top='#dc2626', height=1.1, glass=True, base='#9fb4c8', frame='#c9e6f7')
GOAL = dict(post='#ef4444', net='#ffffff')

PI = math.pi
rng = random.Random(4242)
R = rng.uniform
sstep = wk.smooth


def wrap(a):
    a = (a + PI) % (2 * PI)
    return a - PI


def win(phi, c, hw, soft):
    """A smooth angular window centred on c: 1 inside ±hw, fading to 0 over `soft`."""
    return 1 - sstep(hw - soft, hw + soft, abs(wrap(phi - c)))


def fbm(x, z):
    v = wk.vnoise
    return v(x, z) * 0.6 + v(x * 2.1 + 7.3, z * 2.1 + 3.1) * 0.28 + v(x * 4.3 + 1.7, z * 4.3 + 9.2) * 0.12


# ---------------------------------------------------------------- the peaks (the prototype's list)
PEAKS = []
REACH = 300.0                                                  # the terrain's edge, inside the dome


def add_peak(x, z, h, rad, p=1.5, sx=0.8, ax=0.0):
    """Beyond 150 m a peak is pulled in towards the pitch and shrunk in proportion, so it keeps
    its apparent size inside the dome (the prototype's ring reached 440 m)."""
    r = math.hypot(x, z)
    if r > 150:
        f = (150 + (r - 150) * 0.5) / r
        x, z, h, rad = x * f, z * f, h * f, rad * f
    PEAKS.append((x, z, h, rad, p, sx, math.cos(ax), math.sin(ax)))


def define_peaks():
    prng = random.Random(7331)
    for args in ((-18, 118, 60, 46, 1.4, 0.75, 0.4), (28, 138, 80, 56, 1.5, 0.7, -0.5), (74, 150, 56, 44, 1.4, 0.8, 0.9),
                 (-66, 138, 60, 50, 1.5, 0.75, -0.9), (0, 245, 150, 110, 1.35, 0.8, 0.2), (-112, 255, 130, 100, 1.4, 0.75, 0.6),
                 (122, 275, 145, 105, 1.4, 0.7, -0.3), (-38, 380, 165, 120, 1.3, 0.8, 0.0),
                 (-40, 90, 22, 20, 1.3, 0.7, 0.3), (46, 92, 18, 18, 1.3, 0.7, -0.6), (14, 100, 16, 16, 1.3, 0.8, 1.0),
                 (232, -44, 195, 92, 1.4, 0.75, 0.3), (272, 62, 215, 100, 1.35, 0.7, -0.4), (332, -124, 205, 110, 1.4, 0.8, 0.9),
                 (205, 150, 175, 90, 1.4, 0.7, 0.5), (300, 200, 190, 100, 1.4, 0.8, -0.8),
                 (-126, -12, 72, 50, 1.5, 0.75, 0.2), (-150, 52, 88, 56, 1.45, 0.7, -0.6), (-140, -62, 62, 46, 1.5, 0.8, 0.8),
                 (-250, 30, 140, 100, 1.4, 0.75, 0.1), (-300, -104, 150, 110, 1.4, 0.8, -0.5), (-262, 152, 125, 92, 1.4, 0.7, 0.7),
                 (-60, -282, 120, 100, 1.4, 0.8, 0.3), (82, -300, 140, 108, 1.4, 0.75, -0.4), (0, -400, 150, 110, 1.35, 0.8, 0.0),
                 (-205, -252, 130, 100, 1.4, 0.7, 0.5), (202, -252, 120, 90, 1.4, 0.8, -0.6)):
        add_peak(*args)
    for _ in range(26):
        phi, r = prng.random() * 2 * PI, 170 + prng.random() * 230
        x, z = math.sin(phi) * r, math.cos(phi) * r
        if z < -150 and abs(x) < 120 and r < 230:
            continue
        abyss = win(phi, PI / 2, 0.95, 0.35)
        h = (50 + prng.random() * 60) * (0.5 + r / 300) + abyss * 90
        add_peak(x, z, h, 40 + prng.random() * 60, 1.3 + prng.random() * 0.5, 0.6 + prng.random() * 0.4, prng.random() * PI)


define_peaks()
ABYSS_C, LAKE_C = PI / 2, -PI / 2
MESA = (8.0, 82.0, 9.0, 11.0)                                  # x, z, top, radius


def rim_radius(phi):
    return 40 + 4.5 * fbm(math.cos(phi) * 3 + 10, math.sin(phi) * 3 + 10)


def terrain_h(x, z):
    r, phi = math.hypot(x, z), math.atan2(x, z)
    rd = wk.sd_round_rect(x, z, 17.6, 32.6, 11)
    near = sstep(1, 10, rd)
    y = -0.5 + near * (0.55 * fbm(x / 11, z / 11) + 0.18 * fbm(x / 3.5, z / 3.5) + 0.3)
    wpx, wmx, wmz = win(phi, ABYSS_C, 0.95, 0.35), win(phi, LAKE_C, 0.8, 0.3), win(phi, PI, 0.8, 0.3)
    y += 7 * sstep(48, 100, r) * (1 - wpx) * (1 - wmz * 0.7) * (1 + 0.5 * fbm(x / 25, z / 25))
    y -= 3.6 * sstep(38, 50, r) * (1 - sstep(84, 100, r)) * wmx
    pmax = psum = 0.0
    for px, pz, h, rad, p, sx, ca, sa in PEAKS:
        dx, dz = x - px, z - pz
        if abs(dx) > rad * 1.7 or abs(dz) > rad * 1.7:
            continue
        rx, rz = (dx * ca - dz * sa) / sx, dx * sa + dz * ca
        u = math.hypot(rx, rz) / rad
        if u >= 1:
            continue
        c = h * (1 - u) ** p * (1 + 0.3 * fbm((x + px) / 22, (z + pz) / 22))
        pmax = max(pmax, c)
        psum += c
    pk = pmax + 0.22 * (psum - pmax)
    y += pk * (1 + 0.14 * fbm(x / 9, z / 9))
    rim = rim_radius(phi)
    drop = sstep(rim, rim + 15, r) * wpx
    y = lerp(y, -70 + 6 * fbm(x / 30, z / 30) + pk, drop)
    mx, mz, my, mr = MESA
    md = math.hypot(x - mx, z - mz)
    if md < mr + 8:
        y = max(y, lerp(y, my, sstep(mr + 8, mr - 1, md)))
    return y


SNOW, SNOW_SHADE = '#f2f6fc', '#d6e3f5'
ROCK_D, ROCK_L = '#5c5761', '#9e918a'
ICE_A, ICE_B = '#94cceb', '#c7e6f7'
HAZE, FLOOR = '#c7dbef', '#404d61'


def terrain_colour(x, y, z, n):
    r, phi = math.hypot(x, z), math.atan2(x, z)
    slope = math.hypot(n[0], n[2]) / max(n[1], 1e-3)
    rock = ROCK_D if fbm(x / 15, z / 15) < 0 else ROCK_L
    snow = SNOW if fbm(x / 6, z / 6) > -0.15 else SNOW_SHADE
    amt = 1 - sstep(1.05, 2.0, slope + 0.6 * fbm(x / 7, z / 7))
    snowline = lerp(-60, 22, sstep(70, 180, r)) + 10 * fbm(x / 40, z / 40)
    amt *= sstep(snowline - 12, snowline + 6, y)
    amt = max(amt, sstep(snowline + 22, snowline + 60, y) * (1 - sstep(2.4, 3.4, slope)))
    basin = sstep(38, 50, r) * (1 - sstep(84, 100, r)) * win(phi, LAKE_C, 0.8, 0.3)
    if basin > 0.4:
        snow = mix(snow, ICE_B, 0.6)
    col = mix(rock, snow, round(amt * 2) / 2)
    wpx, rim = win(phi, ABYSS_C, 0.95, 0.35), rim_radius(phi)
    cliff = wpx * sstep(rim - 3, rim + 2, r) * (1 - sstep(rim + 14, rim + 24, r)) * sstep(0.5, 1.0, slope)
    if cliff > 0.5:
        col = ICE_A if (y * 0.4) % 1 < 0.5 else ICE_B
    if y < -40:
        col = FLOOR
    elif y < -25:
        col = mix(col, FLOOR, 0.5)
    if r < 60 and y < -0.5:
        col = mix(col, SNOW_SHADE, 0.6)                      # the plateau's dips: a blue shade
    hz = 0.35 * sstep(140, 300, r)
    return mix(col, HAZE, round(hz / 0.35 * 2) / 2 * 0.35)


def terrain(m):
    radii, r, dr = [], 6.0, 2.6
    while r < REACH:
        radii.append(r)
        r += dr
        dr *= 1.085
    radii.append(REACH)
    m.polar(radii, 150, terrain_h, terrain_colour, warp=lambda x, z: wk.push_out(x, z, 0.5, wk.CORNER[SPORT]))


# ---------------------------------------------------------------- the frozen lake, the cloud sea
def lake(m):
    pts = []
    for i in range(24):
        phi = LAKE_C - 0.5 + i / 23
        pts.append((math.sin(phi) * (83 + 3 * fbm(phi * 4, 1.5)), math.cos(phi) * (83 + 3 * fbm(phi * 4, 1.5))))
    for i in range(24):
        phi = LAKE_C + 0.5 - i / 23
        pts.append((math.sin(phi) * (50 - 3 * fbm(phi * 4, 5.5)), math.cos(phi) * (50 - 3 * fbm(phi * 4, 5.5))))
    y = -3.25
    m.up([(x, y, z) for x, z in pts], '#bfe0f5')
    for _ in range(14):                                        # cracks and pale streaks
        phi, rr = LAKE_C + R(-0.4, 0.4), R(55, 78)
        x, z = math.sin(phi) * rr, math.cos(phi) * rr
        crack = [(x, z)]
        for _ in range(4):
            x, z = x + R(-4, 4), z + R(-4, 4)
            crack.append((x, z))
        m.strip(crack, 0.35, y + 0.03, '#f4fbff')
    for _ in range(6):
        phi, rr = LAKE_C + R(-0.35, 0.35), R(58, 76)
        m.disc(math.sin(phi) * rr, y + 0.02, math.cos(phi) * rr, R(3, 6), 7, '#8fc4ea', rz=R(2, 4), phase=R(0, 6))


def clouds(m):
    """The abyss's sea of cloud below the rim: flat white puffs. (The prototype's high wisps were
    soft sprites; as solid puffs they read as slabs, so they are left out.)"""
    warm, cool = '#fdfbf6', '#e3edf9'
    for _ in range(46):
        x, y, z = R(46, 170), R(-12, 2), R(-120, 120)
        if math.hypot(x, z) > REACH - 20:
            continue
        w, d = R(14, 30), R(7, 15)
        m.blob((x, y, z), 1.0, [cool, cool, warm], scale=(w, R(2.0, 4.5), d), level=1, jitter=0.12, rng=rng, cut=-0.3, yaw=R(0, 6.28))


# ---------------------------------------------------------------- trees, rocks, cairns, ice
def slope_at(x, z, e=0.8):
    return math.hypot(terrain_h(x + e, z) - terrain_h(x - e, z), terrain_h(x, z + e) - terrain_h(x, z - e)) / (2 * e)


def pine(m, x, y, z, sc, sy):
    m.frustum((x, y, z), (x, y + 1.3 * sy, z), 0.18 * sc, 0.1 * sc, 5, '#4a3221')
    phase = R(0, 6.28)
    for rad, h, y0 in ((1.35, 1.8, 0.7), (1.05, 1.6, 1.8), (0.7, 1.5, 2.85)):
        base, tip = y + y0 * sy, y + (y0 + h) * sy
        m.frustum((x, base, z), (x, tip, z), rad * sc, 0.0, 6, '#1f4d33', phase=phase, col_fn=lambda i: '#1f4d33' if i % 2 else '#2a5e40')
        cb = y + (y0 + h - h * 0.62) * sy + 0.02
        m.frustum((x, cb, z), (x, tip + 0.02, z), rad * 0.62 * sc, 0.0, 6, '#f3f7fd', phase=phase + 0.3)
        phase += 0.5


def pines(m):
    placed = tries = 0
    while placed < 205 and tries < 5000:
        tries += 1
        phi, r = R(-PI, PI), R(30, 115)
        x, z = math.sin(phi) * r, math.cos(phi) * r
        if z < -32 and abs(x) < 22:
            continue
        if win(phi, ABYSS_C, 0.95, 0.35) > 0.15 and r > 30:
            continue
        if wk.sd_round_rect(x, z, wk.HW + 2.5, wk.HL + 2.5, 11) < 5.5:
            continue
        if win(phi, LAKE_C, 0.8, 0.3) > 0.35 and 26 < r < 100:
            continue
        y = terrain_h(x, z)
        if y < -1.5 or y > 26 or slope_at(x, z) > 0.55:
            continue
        if math.hypot(x - MESA[0], z - MESA[1]) < MESA[3] + 1:
            continue
        if r < 42 and rng.random() < 0.3:
            continue
        sc = R(0.75, 1.45) * (1 + 0.3 * sstep(60, 110, r))
        pine(m, x, y - 0.15, z, sc, sc * R(0.9, 1.2))
        placed += 1


def boulders(m):
    placed = tries = 0
    while placed < 80 and tries < 2000:
        tries += 1
        phi, r = R(-PI, PI), R(24, 100)
        x, z = math.sin(phi) * r, math.cos(phi) * r
        if z < -32 and abs(x) < 20:
            continue
        if win(phi, ABYSS_C, 0.95, 0.35) > 0.3 and r > rim_radius(phi) - 4:
            continue
        if wk.sd_round_rect(x, z, wk.HW + 2.5, wk.HL + 2.5, 11) < 4:
            continue
        y = terrain_h(x, z)
        if y < -1.5 or slope_at(x, z, 1.0) > 0.45:
            continue
        sc = R(0.4, 1.6) * (1 + sstep(50, 100, r))
        m.blob((x, y - sc * 0.3, z), sc, ['#5e5862', '#6c6570', '#857d88'], scale=(R(0.8, 1.4), R(0.6, 1.0), 1), level=0,
               jitter=0.18, rng=rng, yaw=R(0, 6.28))
        placed += 1


def cairns(m):
    for x, z in ((-21.5, 12), (21.5, -4), (-20.5, -20), (22, 20), (-19.5, 34.5), (19.8, 35.5), (-24, -34), (24.5, -35),
                 (-26, 44), (27, 46), (-30, 20), (31, -18), (-33, -8), (3, 44.5), (-3, 45), (16, 40), (-16, 41)):
        sc, yaw = R(0.8, 1.35), R(0, PI)
        y = terrain_h(x, z) - 0.05
        for w in (1.0, 0.85, 0.7, 0.55, 0.42, 0.3):
            h = (0.28 + w * 0.2) * sc
            shade = R(0.32, 0.5)
            m.box(x + R(-0.05, 0.05), y, z + R(-0.05, 0.05), w * sc, h, w * sc * R(0.75, 1.0),
                  wk.hexs((shade, shade * 0.95, shade)), yaw=yaw + R(-0.4, 0.4))
            y += h
        m.box(x, y, z, 0.34 * sc, 0.1 * sc, 0.34 * sc, '#f5f8fd')


def ice_blocks(m):
    ice, ice_d = '#a8dcf5', '#7fbfe6'

    def block(x, z, w, h, d, yaw, tilt, c):
        m.box(x, terrain_h(x, z) + h * 0.42 - h / 2, z, w, h, d, c, yaw=yaw, tilt=tilt, roll=tilt * 0.6)
    for _ in range(22):                                        # fins along the abyss rim
        phi = ABYSS_C + R(-0.75, 0.75)
        r = rim_radius(phi) - R(1.5, 6)
        block(math.sin(phi) * r, math.cos(phi) * r, R(2, 5), R(1.5, 5), R(2, 5), R(0, PI), R(-0.25, 0.25), ice if rng.random() < 0.5 else ice_d)
    for _ in range(12):                                        # the ice cliff at the lake's far shore
        phi, r = LAKE_C + R(-0.45, 0.45), R(86, 94)
        block(math.sin(phi) * r, math.cos(phi) * r, R(5, 9), R(6, 13), R(4, 8), phi + R(-0.3, 0.3), R(-0.12, 0.12), ice if rng.random() < 0.5 else ice_d)
    for cx, cz in ((-33, 31), (33, -31), (-34, -14), (34, 12)):
        for _ in range(5):
            block(cx + R(-3, 3), cz + R(-3, 3), R(2, 4), R(3, 7), R(2, 4), R(0, PI), R(-0.2, 0.2), ice if rng.random() < 0.5 else ice_d)
    for x, z, s in ((23.5, -12, 1.4), (25.5, -9, 1.0), (-24, 10, 1.6), (-26.5, 13, 1.1), (-23, 44, 1.5), (22.5, 46, 1.2), (26, 38, 0.9),
                    (-27, -26, 1.3), (28, 24, 1.0), (-25, 27, 1.1), (25.5, 28, 0.9), (-25.5, -28, 1.0), (25, -26, 1.2)):
        block(x, z, 2.2 * s, 1.6 * s, 1.8 * s, R(0, PI), R(-0.2, 0.2), ice if rng.random() < 0.5 else ice_d)


# ---------------------------------------------------------------- monastery, stupas, prayer flags
WHITE, RED, GOLD, DARK, ROOF, WOOD = '#f3ede0', '#9a2c22', '#e0ad3a', '#2a221f', '#b9822a', '#5a3d26'
FLAGS = ['#2f6fd8', '#f5f7fa', '#e23b2e', '#2fa04a', '#f2c31f']


def stupa(m, x, z, sc):
    y = terrain_h(x, z)
    m.box(x, y, z, 4 * sc, 0.7 * sc, 4 * sc, WHITE)
    m.box(x, y + 0.7 * sc, z, 3.1 * sc, 0.5 * sc, 3.1 * sc, WHITE)
    m.box(x, y + 1.2 * sc, z, 2.4 * sc, 0.4 * sc, 2.4 * sc, WHITE)
    m.blob((x, y + 1.9 * sc, z), 1.25 * sc, WHITE, level=1, cut=-0.4)
    m.box(x, y + 2.95 * sc, z, 0.9 * sc, 0.8 * sc, 0.9 * sc, GOLD)
    m.frustum((x, y + 3.7 * sc, z), (x, y + 6.1 * sc, z), 0.62 * sc, 0.0, 8, GOLD)
    m.blob((x, y + 6.2 * sc, z), 0.28 * sc, GOLD, level=0)
    return y + 6.2 * sc


def monastery(m, strings):
    mx, mz, my, _ = MESA
    m.box(mx, my, mz, 11, 6, 7.5, WHITE)
    m.box(mx, my + 6, mz, 11.4, 1.0, 7.9, RED)
    m.box(mx, my + 7, mz, 11.8, 0.25, 8.3, ROOF)
    m.box(mx - 3.2, my + 7, mz + 0.4, 5.2, 3.2, 5.2, WHITE)
    m.box(mx - 3.2, my + 10.15, mz + 0.4, 5.6, 0.7, 5.6, RED)
    m.box(mx - 3.2, my + 10.85, mz + 0.4, 6.0, 0.25, 6.0, ROOF)
    m.frustum((mx - 3.2, my + 11.1, mz + 0.4), (mx - 3.2, my + 12.5, mz + 0.4), 0.5, 0.0, 6, GOLD)
    for i in range(-2, 3):
        for s in (-1, 1):
            m.box(mx + i * 2.2, my + 2.5, mz + s * 3.8, 0.9, 1.4, 0.2, DARK)
    m.box(mx + 3.5, my, mz - 3.8, 1.6, 2.8, 0.25, RED)
    stupa(m, mx + 7, mz - 2, 0.7)
    m.frustum((mx - 3.2, my + 11.5, mz + 0.4), (mx - 3.2, my + 18.5, mz + 0.4), 0.14, 0.1, 5, WOOD)
    top = (mx - 3.2, my + 18.4, mz + 0.4)
    for tx, tz in ((mx - 22, mz - 14), (mx + 20, mz - 10), (mx - 14, mz + 20), (mx + 16, mz + 16)):
        ty = terrain_h(tx, tz)
        m.frustum((tx, ty, tz), (tx, ty + 4, tz), 0.14, 0.1, 5, WOOD)
        strings.append((top, (tx, ty + 4, tz), 1.35))
    for sx, sz, sc in ((-24, 36, 0.8), (25, -37, 0.7), (-30, -6, 0.6), (-9.5, 41, 0.5), (9.5, 41, 0.5)):
        tip = stupa(m, sx, sz, sc)
        for k in range(3):
            a = k * (2 * PI / 3) + R(0, 1)
            tx, tz = sx + math.sin(a) * 7, sz + math.cos(a) * 7
            if wk.sd_round_rect(tx, tz, wk.HW + 2.5, wk.HL + 2.5, 11) < 1.5:
                continue
            ty = terrain_h(tx, tz)
            m.frustum((tx, ty, tz), (tx, ty + 2.2, tz), 0.08, 0.06, 4, WOOD)
            strings.append(((sx, tip - 0.3, sz), (tx, ty + 2.2, tz), 0.6))


def flag_poles(m, strings):
    def pole(x, z, h):
        y = terrain_h(x, z)
        m.frustum((x, y, z), (x, y + h, z), 0.16, 0.11, 6, '#6b4a2e')
        m.blob((x, y + h + 0.1, z), 0.22, GOLD, level=0)
        return (x, y + h, z)
    for sx in (-1, 1):
        tops = [pole(sx * 19.4, z, 5.4) for z in (-25, -8.5, 8.5, 25)]
        strings += [(tops[i], tops[i + 1], 1.15) for i in range(3)]
    ends = [pole(x, 33.8, 4.6) for x in (-14.5, -4.8, 4.8, 14.5)]
    strings += [(ends[i], ends[i + 1], 1.0) for i in range(3)]
    strings.append((ends[0], pole(-19.4, 25, 5.4), 1.0))
    strings.append((ends[3], pole(19.4, 25, 5.4), 1.0))


def flag_strings(m, fx, strings):
    fi = 0
    for a, b, sc in strings:
        ln = math.dist(a, b)
        sag = ln * 0.07
        P = lambda t: (lerp(a[0], b[0], t), lerp(a[1], b[1], t) - sag * 4 * t * (1 - t), lerp(a[2], b[2], t))
        segs = 6
        for i in range(segs):
            m.bar(P(i / segs), P((i + 1) / segs), 0.05, '#3b2f2a')
        hl = math.hypot(b[0] - a[0], b[2] - a[2]) or 1.0
        tx, tz = (b[0] - a[0]) / hl, (b[2] - a[2]) / hl
        fw, fh = 0.85 * sc, 0.65 * sc
        n = max(2, int(ln / (fw * 1.35)))
        for k in range(n):
            t = (k + 0.5) / n
            if t < 0.06 or t > 0.94:
                continue
            c = P(t)
            dy = (b[1] - a[1]) / ln * fw / 2
            col = FLAGS[fi % len(FLAGS)]
            fi += 1
            lean = R(-0.12, 0.12)
            p0 = (c[0] - tx * fw / 2, c[1] - 0.04 - dy, c[2] - tz * fw / 2)
            p1 = (c[0] + tx * fw / 2, c[1] - 0.04 + dy, c[2] + tz * fw / 2)
            # the flag hangs from the string (weight 0) and flutters at its foot (weight 1); the phase
            # runs along the string, so a wave travels down it (the prototype's (x + z)·1.7)
            q = lambda p, v: (p[0] - tz * lean * fh * v, p[1] - fh * v, p[2] + tx * lean * fh * v)
            top = c[1] - 0.04
            with fx['flags'].piece(lambda pt, top=top, fh=fh: (wk.clamp((top - pt[1]) / fh, 0.0, 1.0),
                                                               ((pt[0] + pt[2]) * 1.7 / (2 * PI)) % 1.0)) as fm:
                for v0, v1 in ((0.0, 0.5), (0.5, 1.0)):
                    fm.face([q(p0, v0), q(p1, v0), q(p1, v1), q(p0, v1)], col, facing=(-tz, 0.2, tx))


def wisps(fx):
    """Soft cloud: puffs over the abyss's sea of cloud, wisps round the far peaks and over the
    lake basin (the prototype's cloud quads), drifting together."""
    m = fx['clouds']
    R_ = m.rng.uniform
    warm, cool = '#fdfaf4', '#e6eefa'
    for _ in range(26):
        x, z = R_(48, 160), R_(-110, 110)
        if math.hypot(x, z) > REACH - 25:
            continue
        w = R_(14, 30)
        m.halo((x, R_(0, 5), z), w, m.rng.choice((warm, cool)), p=R_(0, 1), n=14, r2=w * R_(0.45, 0.8), yaw=R_(0, 6.28))
    for _ in range(18):
        phi, r = R_(-PI, PI), R_(200, 280)
        w = R_(35, 60)
        m.halo((math.sin(phi) * r, R_(40, 75), math.cos(phi) * r), w, cool, p=R_(0, 1), n=14, r2=w * R_(0.25, 0.4), yaw=-phi)
    for _ in range(8):
        phi, r = LAKE_C + R_(-0.5, 0.5), R_(95, 125)
        w = R_(15, 25)
        m.halo((math.sin(phi) * r, R_(14, 26), math.cos(phi) * r), w, cool, p=R_(0, 1), n=12, r2=w * R_(0.3, 0.5), yaw=R_(0, 6.28))


def snow(fx):
    """Flakes spawn 36 m up over the whole valley and fall through it (their start is spread by the
    shader's per-flake offset along the fall)."""
    m = fx['snow']
    for _ in range(900):
        m.particle((m.rng.uniform(-60, 60), 36.0, m.rng.uniform(-55, 75)), m.rng.choice(('#ffffff', '#ffffff', '#eef6ff')))


# ---------------------------------------------------------------- the world
def build(turf, scen, sky, fx):
    wk.rink(turf, scen, SPORT, SURFACE, BORDER, GOAL, rng=rng, skirt=-0.9)
    terrain(scen)
    lake(scen)
    pines(scen)
    boulders(scen)
    cairns(scen)
    ice_blocks(scen)
    strings = []
    monastery(scen, strings)
    flag_poles(scen, strings)
    flag_strings(scen, fx, strings)
    clouds(scen)
    wisps(fx)
    snow(fx)


wk.run(WORLD, HERE, wk.Palette(wk.css_sky(SKY)), SPORT, build, LIGHT)
