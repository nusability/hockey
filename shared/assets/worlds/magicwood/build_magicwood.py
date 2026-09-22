"""
Builds Magic Wood (Zauberwald): a moonlit clearing where the mushrooms glow (spec §13, ADR 0006).

Re-authored from the prototype's world (web/js/worlds/magicwood.js — read, never run): the same
set pieces in the same places. A moss-green pitch with mowing stripes, clover and tiny flowers
along its edges, inside brown boards with a leaf-green rail on a dark rim; a dark forest floor;
seven giant gnarled hero trees (green, teal, violet canopies, hanging vines) flanking the sides; a
ring of far trees; lantern mushrooms glowing in clusters at the tree feet and along the boards,
each with a warm pool of light on the ground; moss stones and violet crystals; a glowing stream
with a crooked plank bridge on the east side; a ring of standing stones round a floating altar
crystal behind the far goal; hedges hugging the boards, ferns, fireflies, lavender mist. The sky:
the page gradient, night blue over a violet-rose horizon. No fog (ADR 0006).

What glows and stands still (the stream's water) is in the unlit `sky` mesh; what lives is in the
effects (ADR 0007, shared/data/effects.toml): the caps breathing, their warm pools of light and the
two big warm spills, the crystals, the floating turning gem and its halo, glints running down the
stream, fireflies, drifting mist. Coordinates are the game's (worldkit): X across, Y up, Z along,
the far goal at +Z.

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
from worldkit import clamp, lerp, mix, tone  # noqa: E402

WORLD, SPORT = 'magicwood', 'field'
SKY = [(0.0, '#06071a'), (0.30, '#151538'), (0.55, '#241d4e'), (0.80, '#4a2d63'), (1.0, '#7a4470')]
LIGHT = dict(hemi_sky='#9fb2ff', hemi_ground='#2a3820', hemi=1.1, sun='#ffd6a6', sun_i=1.9, sun_pos=(26, 50, -30))
SURFACE = dict(base='#3b8a48', stripe='#357f42', lines='#f3f7ea')
BORDER = dict(color='#6b4527', top='#8fd14f', height=1.1, base='#33291a')
GOAL = dict(post='#f8fafc', net='#e2e8f0')

GROUND = -0.64
CLEAR_X, CLEAR_Z = 15.5, 30.5
rng = random.Random(23)
R = rng.uniform

# the forest floor: the prototype's dark moss texture (#1c2a18 + green blotches) × #b9c9b0
FLOOR = ['#131f11', '#182716', '#1d2f1a', '#24381f']
BARK_D, BARK_L, MOSS = '#35220f', '#6e4a28', '#3f7a33'
CANOPY = {
    'green': ('#17402c', '#3f9a4c', '#8fd66a'),
    'violet': ('#3a1750', '#9a4fb8', '#f0a1e2'),
    'teal': ('#113f3a', '#2f9a7a', '#a2f0c8'),
}
CAPS = ['#ffb347', '#ffb347', '#ff9a3c', '#7dffc2', '#c77dff', '#ff8fb1']


def stream_x(z):
    return 24.5 + 2.4 * math.sin(z * 0.11) + 1.1 * math.sin(z * 0.31 + 1)


def ground_y(x, z):
    """On the rim the pitch stands on (to HW+2.2), 0; beyond it the forest floor."""
    return 0.0 if wk.sd_round_rect(x, z, wk.HW + wk.SLAB_W, wk.HL + wk.SLAB_W, 2.0 + wk.SLAB_W) < 0 else GROUND


def inside_clear(x, z, m=0.0):
    return abs(x) < CLEAR_X + m and abs(z) < CLEAR_Z + m


def canopy_ramp(pal, n=5):
    """The prototype's canopy paint: dark -> mid below 0.55, mid -> light above."""
    out = []
    for i in range(n):
        k = (i + 0.5) / n
        out.append(mix(pal[0], pal[1], k / 0.55) if k < 0.55 else mix(pal[1], pal[2], (k - 0.55) / 0.45))
    return out


# ---------------------------------------------------------------- the pitch's own paint
def decorate(turf, paint):
    """Clover and tiny flowers near the edges only (the prototype's decorate)."""
    def edge():
        if rng.random() < 0.5:
            x = R(-14.4, -12.6) if rng.random() < 0.5 else R(12.6, 14.4)
            return x, R(-29.4, 29.4)
        z = R(-29.4, -27.4) if rng.random() < 0.5 else R(27.4, 29.4)
        return R(-14.4, 14.4), z
    clover = mix('#60be68', SURFACE['base'], 0.15)
    for _ in range(70):
        x, z = edge()
        for k in range(3):
            a = 2 * math.pi * k / 3 + R(0, 1)
            paint.dab(x + math.cos(a) * 0.094, z + math.sin(a) * 0.094, 0.094, clover, n=5)
    for _ in range(130):
        x, z = edge()
        paint.dab(x, z, R(0.065, 0.12), rng.choice(['#ffd9ea', '#fff4bd', '#e6d5ff', '#ffffff', '#ffc4d6']), n=5, phase=R(0, 6))


# ---------------------------------------------------------------- the forest floor
def floor(m):
    def col(x, y, z, n):
        v = wk.fbm(x * 0.09 + 3.1, z * 0.09 - 1.7, 2) + 0.35 * wk.vnoise(x * 0.4, z * 0.4)
        return FLOOR[clamp(int((v + 0.75) / 1.5 * len(FLOOR)), 0, len(FLOOR) - 1)]
    xs = [-60 + 3 * i for i in range(41)]
    zs = [-84 + 3 * i for i in range(57)]
    inner = lambda x0, z0, x1, z1: max(abs(x0), abs(x1)) < wk.HW + 2.0 and max(abs(z0), abs(z1)) < wk.HL + 2.0
    m.field(xs, zs, lambda x, z: GROUND, col, skip=inner)
    radii = [55, 70, 88, 110, 135, 160, 190]
    m.polar(radii, 40, lambda x, z: GROUND - 0.03, col, skip=lambda x, z, r: abs(x) < 59 and abs(z) < 83)


# ---------------------------------------------------------------- hero trees
def trunk_rings(h, r0, r1, rings, radial, seed, lean, flare, bump, twist=1.0, wiggle=0.05):
    """The prototype's gnarled trunk: rings of bumpy radius with root buttresses at the foot."""
    centre = lambda t: (lean[0] * t * t * h + math.sin(t * 4 + seed) * wiggle * h, t * h, lean[1] * t * t * h + math.cos(t * 3.3 + seed * 1.7) * wiggle * h)
    radius = lambda t: (r0 + (r1 - r0) * t ** 0.7) * (1 + flare * (1 - t) ** 7)
    out = []
    for i in range(rings + 1):
        t = i / rings
        cx, y, cz = centre(t)
        rr = radius(t)
        ring = []
        for j in range(radial):
            a = 2 * math.pi * j / radial
            b = 1 + bump * math.sin(a * 5 + t * twist * 5 + seed) + bump * 0.7 * math.sin(a * 3 - t * 7 + seed * 2)
            if t < 0.22:
                b += 0.45 * max(0.0, math.cos(a * 4 + seed)) * (1 - t / 0.22)
            ring.append((cx + math.cos(a) * rr * b, y, cz + math.sin(a) * rr * b))
        out.append(ring)
    return out, centre, radius


def bark(x, y, z, h, a):
    k = 0.5 + 0.5 * math.sin(a * 7 + y * 0.9) * math.cos(a * 3 - y * 0.4)
    c = tone(BARK_D, BARK_L, k * 0.85, 3)
    mo = max(0.0, 1 - y / (h * 0.28)) * (0.5 + 0.5 * math.sin(a * 4 + 1))
    return tone(c, MOSS, mo * 0.8, 3) if mo > 0.2 else c


def emit_rings(m, rings, xf, h):
    n = len(rings[0])
    for i in range(len(rings) - 1):
        A, B = [xf(p) for p in rings[i]], [xf(p) for p in rings[i + 1]]
        c = xf((sum(p[0] for p in rings[i]) / n, rings[i][0][1], sum(p[2] for p in rings[i]) / n))
        for j in range(n):
            k = (j + 1) % n
            a = 2 * math.pi * (j + 0.5) / n
            y = (rings[i][j][1] + rings[i + 1][j][1]) / 2
            m.face([A[j], A[k], B[k], B[j]], bark(0, y, 0, h, a), out=c)


def orient_xf(base, direction):
    d = wk._norm(direction)
    up = (0.0, 1.0, 0.0)
    ax = wk._cross(up, d)
    s = math.sqrt(wk._dot(ax, ax))
    M = wk.Matrix.Identity(4) if s < 1e-6 else wk.Matrix.Rotation(math.atan2(s, wk._dot(up, d)), 4, wk.Vector(ax).normalized())
    M = wk.T(*base) @ M
    return lambda p: tuple(M @ wk.Vector(p))


def hero_tree(m, glow, s, feet, anchors):
    x, z, h, r0, seed, lean, pal = s
    base = (x, GROUND, z)
    feet.append((x, z, r0 * 1.9))
    rings, centre, radius = trunk_rings(h, r0, r0 * 0.32, 8, 9, seed, lean, 1.1, 0.16, 1.4)
    emit_rings(m, rings, lambda p: (p[0] + base[0], p[1] + base[1], p[2] + base[2]), h)
    cols = canopy_ramp(CANOPY[pal])
    away = math.atan2(z, x)
    blobs = []
    for i in range(3 + int(R(0, 2))):
        t = R(0.5, 0.86)
        cx, cy, cz = centre(t)
        az, tilt = away + R(-1.9, 1.9), R(0.6, 1.0)
        d = (math.cos(az) * math.cos(tilt), math.sin(tilt), math.sin(az) * math.cos(tilt))
        ln = h * R(0.3, 0.45)
        frm = (cx + base[0], cy + base[1], cz + base[2])
        br, _, _ = trunk_rings(ln, radius(t) * 0.55, 0.12, 4, 6, seed + i, (R(-0.15, 0.15), 0), 0.2, 0.1, wiggle=0.03)
        emit_rings(m, br, orient_xf(frm, d), ln * 3)
        end = tuple(frm[k] + d[k] * ln for k in range(3))
        blobs.append((end, R(2.6, 3.6)))
        if rng.random() < 0.6:                                 # a hanging vine with a leaf
            vl, sway = R(3.5, 6.5), R(-0.5, 0.5)
            pts = [(end[0] + math.sin(u * 3) * sway, end[1] - u * vl, end[2] + math.cos(u * 2.5 + 1) * sway) for u in (0, 0.33, 0.66, 1.0)]
            m.tube(pts, 0.1, 3, cols[1], r_end=0.07)
            m.blob(pts[-1], 0.35, cols[2], scale=(1, 0.6, 1), level=0, jitter=0.2, rng=rng)
    tx, ty, tz = centre(1.0)
    top = (tx + base[0], ty + base[1], tz + base[2])
    blobs.append(((top[0], top[1] + 0.8, top[2]), h * 0.27))
    for i in range(3):
        a, dd = away + R(-2.2, 2.2), h * R(0.12, 0.22)
        blobs.append(((top[0] + math.cos(a) * dd, top[1] + R(-1.5, 1.2), top[2] + math.sin(a) * dd), h * R(0.16, 0.22)))
    for (p, r) in blobs:
        px, py, pz = p
        mg = r + 0.5
        if abs(px) < CLEAR_X + mg and abs(pz) < CLEAR_Z + mg:  # keep every canopy blob outside
            if abs(px) - CLEAR_X > abs(pz) - CLEAR_Z:
                px = math.copysign(CLEAR_X + mg, px or 1)
            else:
                pz = math.copysign(CLEAR_Z + mg, pz or 1)
        m.blob((px, py, pz), r, cols, scale=(R(0.9, 1.15), R(0.62, 0.78), R(0.9, 1.15)), level=1, jitter=0.14, rng=rng, band_noise=0.18)
        anchors.append(((px, py, pz), r))


def far_trees(m):
    """The instanced far ring: a trunk and two canopy blobs, bluer and darker with distance."""
    placed, tries = 0, 0
    while placed < 64 and tries < 2000:
        tries += 1
        a, r = R(0, 2 * math.pi), R(44, 105)
        x, z = math.cos(a) * r, math.sin(a) * r
        if z < -30 and abs(x) < 24:
            continue                                            # behind the user's goal: keep low
        if abs(x) < 16 and 30 < z < 62:
            continue                                            # the standing stones' clearing
        sc = R(0.9, 1.9) * (1 + (r - 44) / 120)
        sx, sy = sc * R(0.85, 1.15), sc * R(0.9, 1.3)
        yaw = R(0, 2 * math.pi)
        k = lerp(1.0, 0.55, (r - 44) / 61)
        kq = 1.0 if k > 0.78 else 0.7
        pink = rng.random() < 0.18
        tint = (kq, kq * 0.65, kq * 1.05) if pink else (kq * 0.8, kq * 0.92, kq * 1.1)
        tt = lambda c: wk.hexs(tuple(clamp(v * tint[i], 0, 1) for i, v in enumerate(wk.rgb(c))))
        cols = [tt(c) for c in canopy_ramp(CANOPY['green'], 3)]
        m.frustum((x, GROUND, z), (x, GROUND + 4.2 * sy, z), 0.75 * sx, 0.28 * sx, 6, tt(BARK_D))
        m.blob((x, GROUND + 6.2 * sy, z), 3.2 * sx, cols, scale=(1, 0.8 * sy / sx, 1), level=1 if r < 70 else 0, jitter=0.12, rng=rng)
        c2 = (x + math.cos(yaw) * 1.2 * sx, GROUND + 8.4 * sy, z + math.sin(yaw) * 1.2 * sx)
        m.blob(c2, 2.3 * sx, cols, scale=(1, 0.8 * sy / sx, 1), level=0, jitter=0.12, rng=rng)
        placed += 1


# ---------------------------------------------------------------- lantern mushrooms
def light_pool(fx, x, z, radius, colour, idx):
    """The prototype's additive glow disc under a lantern (an effect: it breathes with the caps),
    kept outside the boards."""
    y0 = ground_y(x, z)
    lim = wk.sd_round_rect(x, z, r=2.0) - wk.WALL_T - 0.05
    rr = min(radius, lim)
    if rr >= 0.15:
        fx['pools'].halo((x, y0 + 0.03 + 0.003 * (idx % 7), z), rr, colour, n=10, yaw=idx)


def mushroom(m, fx, x, z, r, h, cap, idx):
    y = ground_y(x, z)
    tilt = R(-0.12, 0.12)
    top = (x + math.sin(tilt) * h * 0.92, y + h * 0.92, z)
    m.frustum((x, y, z), top, 0.135 * r, 0.09 * r, 6, '#d9cbb0', col_fn=lambda i: '#e9dcc4' if i % 3 else '#cdbd9c')
    prof = [(0.0, 1.0), (0.42, 0.95), (0.78, 0.78), (0.98, 0.5), (0.9, 0.36), (0.6, 0.34)]
    hi = wk.mix(cap, '#ffffff', 0.25)
    fx['caps'].lathe(top, [(pr * r, (ph - 0.34) * 0.75 * r) for pr, ph in prof], 7,
                     [hi, hi, cap, cap, wk.scale(cap, 0.62)], phase=R(0, 6.28))
    light_pool(fx, x, z, (r * 6 + h * 1.5) / 2, cap, idx)


def mushrooms(m, fx, feet):
    spots = []
    for tx, tz, tr in feet:
        for i in range(5 + int(R(0, 3))):
            a, d = R(0, 2 * math.pi), tr + R(0.4, 4.2)
            x, z = tx + math.cos(a) * d, tz + math.sin(a) * d
            if inside_clear(x, z, 0.8):
                continue
            big = i == 0
            spots.append((x, z, R(1.2, 1.7) if big else R(0.35, 0.8), R(2.2, 3.0) if big else R(0.6, 1.5), rng.choice(CAPS)))
    for i in range(44):
        if rng.random() < 0.65:
            x, z = (-1 if rng.random() < 0.5 else 1) * R(16.4, 19.6), R(-29, 29)
        else:
            x, z = R(-13, 13), (-1 if rng.random() < 0.5 else 1) * R(31.6, 35.5)
        spots.append((x, z, R(0.35, 0.75), R(0.7, 1.7), rng.choice(CAPS)))
    for i, (x, z, r, h, cap) in enumerate(spots):
        mushroom(m, fx, x, z, r, h, cap, i)
    for i, (x, z) in enumerate(((-19.5, 6.0), (19.5, 24.0))):  # the prototype's two warm point lights
        light_pool(fx, x, z, 9.0, '#ffa554', 7 + i)


# ---------------------------------------------------------------- stones, crystals, standing stones
def stones(m, fx, feet):
    spots = []

    def cluster(cx, cz, n, rad, sc):
        for _ in range(n):
            a, d = R(0, 6.28), R(0, rad)
            x, z = cx + math.cos(a) * d, cz + math.sin(a) * d
            if not inside_clear(x, z, 1.2):
                spots.append((x, z, R(0.5, 1.3) * sc))
    for tx, tz, tr in feet:
        cluster(tx, tz, 4, tr + 4, 1.0)
    cluster(0, 46, 10, 11, 0.9)
    cluster(-19, 26, 4, 3, 0.7)
    cluster(19, -20, 4, 3, 0.7)
    cluster(-19, -10, 3, 2.5, 0.6)
    for _ in range(14):
        z = R(-44, 62)
        x = stream_x(z) + (-1 if rng.random() < 0.5 else 1) * R(1.8, 3.6)
        if not inside_clear(x, z, 1):
            spots.append((x, z, R(0.4, 1.0)))
    grey = [wk.mix('#6b7672', '#8c9591', 0.3), wk.mix('#6b7672', '#8c9591', 0.8), '#4f8a3a']
    for x, z, s in spots:
        m.blob((x, ground_y(x, z) - s * 0.15, z), s, [grey[0], grey[1], grey[1], grey[2]],
               scale=(R(0.8, 1.3), 0.7 * R(0.7, 1.1), R(0.8, 1.3)), level=1 if s > 0.8 else 0, jitter=0.22, rng=rng, yaw=R(0, 6.28))
    # violet crystals in a few clusters (they glow: unlit)
    for cx, cz, n in ((-20, 26, 6), (19, -20, 5), (-30, -18, 5), (26, 46, 5), (-19, -10, 4), (35, 12, 5)):
        for _ in range(n):
            x, z = cx + R(-1.4, 1.4), cz + R(-1.4, 1.4)
            if inside_clear(x, z, 0.8):
                continue
            s = R(0.5, 1.4)
            with fx['crystals'].piece((1.0, 1.0 / (2 * math.pi))):     # the prototype's phase of 1 rad
                fx['crystals'].octa((x, ground_y(x, z) - 0.1 + 0.5 * s, z), 0.225 * s, 0.65 * s, '#b48cff', yaw=R(0, 6.28),
                                    tilt=R(-0.35, 0.35), roll=R(-0.35, 0.35), top_col='#e3d4ff')


def standing_stones(m, fx):
    cx, cz, n, rad = 0.0, 46.0, 9, 7.5
    grey, grey_l, moss = '#777f7b', '#9aa39e', '#4f8a3a'
    for i in range(n):
        a, h = 2 * math.pi * i / n + 0.2, R(3.4, 5.4)
        rings, _, _ = trunk_rings(h, R(0.8, 1.1), R(0.45, 0.7), 4, 6, i * 1.7, (R(-0.05, 0.05), R(-0.05, 0.05)), 0.15, 0.22, wiggle=0.01)
        yaw = R(0, 6.28)
        bx, bz = cx + math.cos(a) * rad, cz + math.sin(a) * rad
        cy, sy = math.cos(yaw), math.sin(yaw)
        xf = lambda p: (bx + p[0] * cy - p[2] * sy, GROUND - 0.2 + p[1], bz + p[0] * sy + p[2] * cy)
        for k in range(len(rings) - 1):
            A, B = [xf(p) for p in rings[k]], [xf(p) for p in rings[k + 1]]
            mid = xf((0, (rings[k][0][1] + rings[k + 1][0][1]) / 2, 0))
            for j in range(len(A)):
                jj = (j + 1) % len(A)
                c = moss if k == 0 and j % 2 else (grey if (j + k) % 3 else grey_l)
                m.face([A[j], A[jj], B[jj], B[j]], c, out=mid)
        top = [xf(p) for p in rings[-1]]
        m.face(top, grey_l, facing=(0, 1, 0))
    m.blob((cx, GROUND + 0.35, cz), 1.9, [grey, grey_l, grey_l], scale=(1, 0.35, 1), level=1, jitter=0.15, rng=rng)
    # the floating altar gem (it bobs and turns about the pivot effects.toml gives it) and its halo
    fx['gem'].octa((cx, GROUND + 2.7, cz), 0.54, 1.26, '#4fd8ff', yaw=0.4, top_col='#cffaff')
    fx['altar'].halo((cx, GROUND + 0.05, cz), 7.0, '#78e6ff', n=16)


# ---------------------------------------------------------------- the stream and its bridge
def stream(m, sky, fx):
    edge, mid = '#0c2c45', '#15668a'
    z = -50.0
    rows = []
    while z <= 70.0:
        x, w = stream_x(z), 1.4 * (1 + 0.25 * math.sin(z * 0.23))
        rows.append((x, w, z))
        z += 2.0
    y = GROUND + 0.05
    for (xa, wa, za), (xb, wb, zb) in zip(rows, rows[1:]):
        for f0, f1, c in ((-1, -0.55, edge), (-0.55, 0.55, mid), (0.55, 1, edge)):
            sky.up([(xa + f0 * wa, y, za), (xb + f0 * wb, y, zb), (xb + f1 * wb, y, zb), (xa + f1 * wa, y, za)], c)
    # ripples, glinting in a wave that runs downstream (+Z): the phase falls along the stream
    with fx['stream'].piece(lambda pt: (1.0, (-pt[2] / 4.0) % 1.0)):
        for _ in range(34):
            z0 = R(-48, 66)
            x0 = stream_x(z0) + R(-0.6, 0.6)
            fx['stream'].strip([(x0, z0), (x0 + R(-0.2, 0.2), z0 + 1.2), (x0 + R(-0.3, 0.3), z0 + 2.6)], 0.09, y + 0.01, '#6cc4dc')
    # the crooked plank bridge
    bz = 14.0
    xa, xb, planks = stream_x(bz) - 4.8, stream_x(bz) + 4.8, 13
    wood = lambda: rng.choice(['#6a4527', '#825a32', '#9a6b3c'])
    arc_y = lambda t: GROUND + 0.35 + math.sin(t * math.pi) * 1.1
    for i in range(planks):
        t = (i + 0.5) / planks
        x = lerp(xa, xb, t)
        slope = math.atan2(arc_y(t + 0.02) - arc_y(t - 0.02), (xb - xa) * 0.04)
        m.box(x, arc_y(t) - 0.06, bz + R(-0.08, 0.08), (xb - xa) / planks * 0.92, 0.12, 2.2, wood(), roll=slope + R(-0.06, 0.06), yaw=R(-0.08, 0.08))
        if i % 3 == 0:
            for side in (-1, 1):
                m.box(x, arc_y(t), bz + side * 1.0, 0.14, 1.0, 0.14, '#6a4527', tilt=R(-0.12, 0.12), roll=R(-0.12, 0.12))
    for side in (-1, 1):
        for i in range(4):
            t0, t1 = (i * 3 + 0.5) / planks, min(1.0, ((i + 1) * 3 + 0.5) / planks)
            p0 = (lerp(xa, xb, t0), arc_y(t0) + 0.95, bz + side * 1.0)
            p1 = (lerp(xa, xb, t1), arc_y(t1) + 0.95, bz + side * 1.0)
            m.bar(p0, p1, 0.1, '#825a32')


# ---------------------------------------------------------------- undergrowth
def ferns(m, feet):
    spots = []
    for _ in range(110):
        if rng.random() < 0.6:
            spots.append(((-1 if rng.random() < 0.5 else 1) * R(17.3, 21.5), R(-31, 31)))
        else:
            spots.append((R(-12, 12), (-1 if rng.random() < 0.5 else 1) * R(32.5, 37)))
    for fx, fz, fr in feet:
        for _ in range(5):
            a, d = R(0, 6.28), fr + R(0.3, 3.5)
            x, z = fx + math.cos(a) * d, fz + math.sin(a) * d
            if not inside_clear(x, z, 0.5):
                spots.append((x, z))
    for x, z in spots:
        y0, k, yaw = ground_y(x, z), R(0.9, 1.7), R(0, 6.28)
        ky = k * R(1.0, 1.4)
        for b in range(5):
            az = yaw + 2 * math.pi * b / 5 + R(-0.3, 0.3)
            dx, dz = math.cos(az), math.sin(az)
            prev = None
            for s, t in enumerate((0.0, 0.5, 1.0)):
                r, y, w = t * 0.95 * k, (0.95 * t - 0.55 * t * t) * ky, 0.17 * (1 - t * 0.75) * k
                pair = ((x + dx * r - dz * w, y0 + y, z + dz * r + dx * w), (x + dx * r + dz * w, y0 + y, z + dz * r - dx * w))
                if prev:
                    m.face([prev[0], prev[1], pair[1], pair[0]], '#2a6a3e' if s == 1 else '#5cc47a', facing=(0, 1, 0))
                prev = pair


def hedges(m):
    """Blobs hugging the boards all round, berries here and there; pushed out so none leans
    over the boards into the pitch."""
    greens = ['#173d2a', '#22553a', '#2f6e42', '#3f8f4c']
    dark = [wk.scale(c, 0.82) for c in greens]
    for x, z in wk.rr_points(1.35, 2.0, 112):
        s = R(1.0, 1.5)
        sx, sy, sz = s * R(0.9, 1.3), s * R(1.1, 1.5), s * R(0.9, 1.3)
        reach = 0.8 * max(sx, sz) * 1.16
        off = max(1.35, reach + 0.3)
        # move outward along the ring normal to clear the boards
        d = wk.sd_round_rect(x, z, r=2.0)
        gx = wk.sd_round_rect(x + 0.01, z, r=2.0) - d
        gz = wk.sd_round_rect(x, z + 0.01, r=2.0) - d
        gl = math.hypot(gx, gz) or 1.0
        x, z = x + gx / gl * (off - d) + R(-0.2, 0.2), z + gz / gl * (off - d) + R(-0.2, 0.2)
        cols = greens if rng.random() < 0.6 else dark
        m.blob((x, ground_y(x, z) + 0.4 * s, z), 0.8, cols, scale=(sx, 0.75 * sy, sz), level=1, jitter=0.16, rng=rng, cut=-0.55, yaw=R(0, 6.28))
        if rng.random() < 0.35:
            m.blob((x + R(-0.3, 0.3), ground_y(x, z) + 0.4 * s + 0.75 * 0.8 * sy * 0.8, z + R(-0.3, 0.3)), 0.14, '#d98cff', level=0)


def fireflies(fx, anchors):
    for i in range(200):
        if i < 85:
            if rng.random() < 0.6:
                x, z = (-1 if rng.random() < 0.5 else 1) * R(16.5, 34), R(-34, 40)
            else:
                x, z = R(-20, 20), R(32, 58)
            y = R(0.4, 7)
        else:
            (ax, ay, az), ar = rng.choice(anchors)
            x, y, z = ax + R(-ar, ar) * 1.3, ay + R(-ar * 1.5, ar * 0.6), az + R(-ar, ar) * 1.3
            if inside_clear(x, z, 1.2):
                x = math.copysign(CLEAR_X + 1.5 + R(0, 3), x or 1)
        col = '#e8ff6a' if rng.random() < 0.7 else ('#7af5ff' if rng.random() < 0.6 else '#ff9be0')
        fx['fireflies'].particle((x, max(y, ground_y(x, z) + 0.4), z), col)


def mist(fx):
    """Lavender mist lying on the forest floor round the clearing (drifting: an effect)."""
    m = fx['mist']
    for x, z in ((-44, -20), (44, -26), (-46, 24), (46, 20), (0, 62), (-30, 62), (32, 64), (-52, 2), (50, 46)):
        r = 20 * m.rng.uniform(0.75, 1.1)
        m.halo((x, GROUND + 0.9, z), r, '#d6c6ff', p=m.rng.uniform(0, 1), n=16, r2=r * m.rng.uniform(0.7, 1.0), yaw=m.rng.uniform(0, 6.28))


# ---------------------------------------------------------------- the world
def build(turf, scen, sky, fx):
    wk.rink(turf, scen, SPORT, SURFACE, BORDER, GOAL, decorate=decorate, skirt=GROUND - 0.1)
    floor(scen)
    feet, anchors = [], []
    heroes = [
        (-24.5, 9, 17, 1.7, 1.3, (-0.1, 0.04), 'green'), (-22, 41, 14, 1.4, 4.1, (-0.08, 0.12), 'teal'),
        (-27, -22, 13, 1.3, 2.7, (-0.14, -0.08), 'green'), (30, -8, 15, 1.5, 6.2, (0.1, -0.05), 'violet'),
        (29, 40, 16, 1.6, 8.8, (0.12, 0.1), 'violet'), (32, 23, 13, 1.25, 3.4, (0.12, 0.02), 'green'),
        (-27.5, 26, 15, 1.5, 5.6, (-0.12, 0.03), 'teal'),
    ]
    for s in heroes:
        hero_tree(scen, sky, s, feet, anchors)
    far_trees(scen)
    mushrooms(scen, fx, feet)
    stones(scen, fx, feet)
    standing_stones(scen, fx)
    stream(scen, sky, fx)
    ferns(scen, feet)
    hedges(scen)
    fireflies(fx, anchors)
    mist(fx)


wk.run(WORLD, HERE, wk.Palette(wk.css_sky(SKY)), SPORT, build, LIGHT)
