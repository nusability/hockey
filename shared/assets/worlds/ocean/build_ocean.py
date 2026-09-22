"""
Builds Ocean World (Ozeanwelt): field hockey on a coral-reef plateau beneath the waves
(spec §13, ADR 0005).

One scene, two exports: `ocean.glb` (Filament, Android) and `ocean.usdz` (RealityKit, iOS),
plus the `palette.png` both sample. Deterministic: the same script always writes the same world
(one seeded RNG, consumed in a fixed order).

Run: tools/build-worlds.sh  (Blender 5, headless)
Preview: WORLD_PREVIEW=1 blender --background --factory-startup --python build_ocean.py
         also renders preview.png from the play camera.

Coordinates: Blender is Z-up; the exporters convert to Y-up, where the game's pitch lies in X-Z
with Z along the pitch (spec §1). Blender's -Y is the game's +Z, so the far end (what the play
camera looks at) is Blender -Y.

Materials are bound **by name** on each platform (ADR 0005): `turf`, `scenery`, `sky`. All three
sample one palette texture: swatches in the left half, the sky's vertical gradient in the right —
here it reads as water, deep blue overhead and a pale cyan glow at the horizon.

What is in it: a sea-grass pitch inside a pink reef wall with a pearl rail; a sandy seabed that
rises into a bowl; brain, staghorn, tube, pillar and fan corals, kelp forests, rocks and a rock
arch, shells, starfish and anemones; a sunken ship and a temple ruin framing the far end; schools
of fish, jellyfish and bubble columns in the water above.
"""
import math
import os
import random

import bmesh
import bpy

HERE = os.path.dirname(os.path.abspath(__file__))
WORLD = 'ocean'
rng = random.Random(31)

HW, HL = 15.0, 30.0          # pitch half-extents (spec §1)
CORNER = 2.0                 # field hockey corner radius
GOAL_Z, GOAL_W, GOAL_D = 26.0, 6.0, 1.6

# ---------------------------------------------------------------- palette texture
# 32 swatches in a 4x8 grid on the left half; a vertical sky gradient in the right half.
TEX, COLS, ROWS = 256, 4, 8


def rgb(h):
    return (((h >> 16) & 255) / 255.0, ((h >> 8) & 255) / 255.0, (h & 255) / 255.0)


SWATCH = {
    'turf_a': rgb(0x33ad9b), 'turf_b': rgb(0x2c9f8d), 'line': rgb(0xf0fdfa), 'post': rgb(0xffb020),
    'net': rgb(0xe0fbff), 'sand': rgb(0xf1e2b8), 'sand_dark': rgb(0xd9c28e), 'sand_light': rgb(0xfff3d6),
    'reef': rgb(0xffa4c1), 'pearl': rgb(0xfff8fc), 'rock': rgb(0x7a86b8), 'rock_dark': rgb(0x56608e),
    'coral_orange': rgb(0xff7a59), 'coral_pink': rgb(0xf05a8e), 'coral_yellow': rgb(0xffc94d), 'coral_violet': rgb(0xb56cff),
    'coral_red': rgb(0xe8483c), 'tube': rgb(0x8f4dff), 'tube_tip': rgb(0xffe066), 'kelp': rgb(0x3fae5a),
    'kelp_light': rgb(0xa5c93a), 'grass': rgb(0x4fc36a), 'shell': rgb(0xfde7d6), 'shell_pink': rgb(0xfbc3d6),
    'star': rgb(0xff6a3d), 'anemone': rgb(0xff7ab8), 'wood': rgb(0x5a3a22), 'wood_light': rgb(0x86603a),
    'stone': rgb(0xe3dcc6), 'stone_moss': rgb(0x6f9a63), 'fish_yellow': rgb(0xffd23d), 'fish_blue': rgb(0x3d8bff),
}
NAMES = list(SWATCH)
assert len(NAMES) == COLS * ROWS
# Water, bottom (horizon) to top: a pale cyan glow into deep blue.
SKY = [(0.0, rgb(0x9beef0)), (0.2, rgb(0x4cc8e0)), (0.5, rgb(0x1a88ab)), (0.8, rgb(0x0d527a)), (1.0, rgb(0x052a48))]


def swatch_uv(name):
    i = NAMES.index(name)
    cx, cy = i % COLS, i // COLS
    return ((cx + 0.5) / (2 * COLS), 1.0 - (cy + 0.5) / ROWS)


def sky_colour(t):
    for (t0, c0), (t1, c1) in zip(SKY, SKY[1:]):
        if t <= t1:
            k = (t - t0) / (t1 - t0)
            return tuple(c0[i] + (c1[i] - c0[i]) * k for i in range(3))
    return SKY[-1][1]


def build_palette():
    img = bpy.data.images.new('palette', TEX, TEX, alpha=False)
    px = [0.0] * (TEX * TEX * 4)
    sw, sh = TEX // 2 // COLS, TEX // ROWS
    for y in range(TEX):
        for x in range(TEX):
            if x < TEX // 2:
                c = SWATCH[NAMES[((TEX - 1 - y) // sh) * COLS + x // sw]]
            else:
                c = sky_colour(y / (TEX - 1))              # 0 bottom (horizon) .. 1 top
            o = (y * TEX + x) * 4
            px[o:o + 4] = [c[0], c[1], c[2], 1.0]
    img.pixels = px
    img.filepath_raw = os.path.join(HERE, 'palette.png')
    img.file_format = 'PNG'
    img.save()
    return img


def make_material(name, img):
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    nt = m.node_tree
    bsdf = nt.nodes['Principled BSDF']
    bsdf.inputs['Roughness'].default_value = 1.0
    tex = nt.nodes.new('ShaderNodeTexImage')
    tex.image = img
    tex.interpolation = 'Closest'
    nt.links.new(tex.outputs['Color'], bsdf.inputs['Base Color'])
    return m


# ---------------------------------------------------------------- geometry helpers
def sub(a, b):
    return (a[0] - b[0], a[1] - b[1], a[2] - b[2])


def cross(a, b):
    return (a[1] * b[2] - a[2] * b[1], a[2] * b[0] - a[0] * b[2], a[0] * b[1] - a[1] * b[0])


def dot(a, b):
    return a[0] * b[0] + a[1] * b[1] + a[2] * b[2]


def norm(a):
    ln = math.sqrt(dot(a, a)) or 1.0
    return (a[0] / ln, a[1] / ln, a[2] / ln)


def newell(pts):
    n = [0.0, 0.0, 0.0]
    for i, p in enumerate(pts):
        q = pts[(i + 1) % len(pts)]
        n[0] += (p[1] - q[1]) * (p[2] + q[2])
        n[1] += (p[2] - q[2]) * (p[0] + q[0])
        n[2] += (p[0] - q[0]) * (p[1] + q[1])
    return n


def rot(p, yaw=0.0, tilt=0.0, roll=0.0):
    """Rotate a local point: roll about Y, tilt about X, then yaw about Z."""
    x, y, z = p
    if roll:
        c, s = math.cos(roll), math.sin(roll)
        x, z = x * c + z * s, -x * s + z * c
    if tilt:
        c, s = math.cos(tilt), math.sin(tilt)
        y, z = y * c - z * s, y * s + z * c
    if yaw:
        c, s = math.cos(yaw), math.sin(yaw)
        x, y = x * c - y * s, x * s + y * c
    return (x, y, z)


PHI = (1 + 5 ** 0.5) / 2
ICO_V = [(-1, PHI, 0), (1, PHI, 0), (-1, -PHI, 0), (1, -PHI, 0), (0, -1, PHI), (0, 1, PHI),
         (0, -1, -PHI), (0, 1, -PHI), (PHI, 0, -1), (PHI, 0, 1), (-PHI, 0, -1), (-PHI, 0, 1)]
ICO_F = [(0, 11, 5), (0, 5, 1), (0, 1, 7), (0, 7, 10), (0, 10, 11), (1, 5, 9), (5, 11, 4), (11, 10, 2),
         (10, 7, 6), (7, 1, 8), (3, 9, 4), (3, 4, 2), (3, 2, 6), (3, 6, 8), (3, 8, 9), (4, 9, 5),
         (2, 4, 11), (6, 2, 10), (8, 6, 7), (9, 8, 1)]
_ICO = {}


def icosphere(level):
    if level not in _ICO:
        verts = [norm(v) for v in ICO_V]
        faces = list(ICO_F)
        for _ in range(level):
            cache, nf = {}, []

            def mid(a, b):
                key = (min(a, b), max(a, b))
                if key not in cache:
                    verts.append(norm(tuple((verts[a][k] + verts[b][k]) / 2 for k in range(3))))
                    cache[key] = len(verts) - 1
                return cache[key]
            for a, b, c in faces:
                ab, bc, ca = mid(a, b), mid(b, c), mid(c, a)
                nf += [(a, ab, ca), (b, bc, ab), (c, ca, bc), (ab, bc, ca)]
            faces = nf
        _ICO[level] = (verts, faces)
    return _ICO[level]


class Builder:
    """Accumulates flat-shaded faces, each coloured by one palette swatch, into one bmesh."""

    def __init__(self):
        self.bm = bmesh.new()
        self.uv = self.bm.loops.layers.uv.new('UVMap')

    def face(self, pts, colour, out=None):
        """A polygon; with `out`, it is wound so its normal points away from that point."""
        if out is not None:
            c = tuple(sum(p[k] for p in pts) / len(pts) for k in range(3))
            if dot(newell(pts), sub(c, out)) < 0:
                pts = pts[::-1]
        verts = [self.bm.verts.new(p) for p in pts]
        f = self.bm.faces.new(verts)
        u = swatch_uv(colour)
        for loop in f.loops:
            loop[self.uv].uv = u
        return f

    def quad(self, a, b, c, d, colour):
        self.face([a, b, c, d], colour)

    def box(self, cx, cy, z0, sx, sy, sz, colour, top=None):
        x0, x1, y0, y1, z1 = cx - sx / 2, cx + sx / 2, cy - sy / 2, cy + sy / 2, z0 + sz
        self.quad((x0, y0, z1), (x1, y0, z1), (x1, y1, z1), (x0, y1, z1), top or colour)
        self.quad((x0, y0, z0), (x1, y0, z0), (x1, y0, z1), (x0, y0, z1), colour)
        self.quad((x1, y1, z0), (x0, y1, z0), (x0, y1, z1), (x1, y1, z1), colour)
        self.quad((x1, y0, z0), (x1, y1, z0), (x1, y1, z1), (x1, y0, z1), colour)
        self.quad((x0, y1, z0), (x0, y0, z0), (x0, y0, z1), (x0, y1, z1), colour)

    def obox(self, c, size, colour, top=None, yaw=0.0, tilt=0.0, roll=0.0):
        """An oriented box standing on `c` (its base centre), rotated about its base."""
        sx, sy, sz = size[0] / 2, size[1] / 2, size[2]
        P = [tuple(c[k] + v[k] for k in range(3)) for v in
             (rot((x, y, z), yaw, tilt, roll) for z in (0, sz) for y in (-sy, sy) for x in (-sx, sx))]
        mid = tuple(c[k] + rot((0, 0, sz / 2), yaw, tilt, roll)[k] for k in range(3))
        for idx, col in (((4, 5, 7, 6), top or colour), ((0, 1, 5, 4), colour), ((1, 3, 7, 5), colour),
                         ((3, 2, 6, 7), colour), ((2, 0, 4, 6), colour)):
            self.face([P[i] for i in idx], col, out=mid)

    def prism(self, p0, p1, r0, r1, n, colour, cap=None, phase=0.0):
        """A tapered n-sided tube from p0 to p1; r1 == 0 makes a cone. Capped at the top."""
        d = norm(sub(p1, p0))
        u = norm(cross(d, (0, 0, 1) if abs(d[2]) < 0.9 else (1, 0, 0)))
        v = cross(d, u)
        ring = lambda p, r: [tuple(p[k] + r * (math.cos(a) * u[k] + math.sin(a) * v[k]) for k in range(3))
                             for a in (phase + 2 * math.pi * i / n for i in range(n))]
        A = ring(p0, r0)
        if r1 <= 1e-6:
            for i in range(n):
                self.face([A[i], A[(i + 1) % n], p1], colour, out=p0)
            return
        B = ring(p1, r1)
        for i in range(n):
            j = (i + 1) % n
            self.face([A[i], A[j], B[j], B[i]], colour)
        if cap is not False:
            self.face(B, cap or colour, out=p0)

    def blob(self, c, r, colours, scale=(1, 1, 1), jitter=0.12, level=1, yaw=0.0, cut=None):
        """A jittered icosphere. `colours` (dark, mid, light) band it by height, toy-like.
        `cut` drops faces whose centre lies below that local height (a flat-bottomed dome)."""
        verts, faces = icosphere(level)
        P = []
        for v in verts:
            k = 1 + rng.uniform(-jitter, jitter)
            q = rot((v[0] * r * scale[0] * k, v[1] * r * scale[1] * k, v[2] * r * scale[2] * k), yaw)
            P.append((c[0] + q[0], c[1] + q[1], c[2] + q[2]))
        for f in faces:
            zc = sum(verts[i][2] for i in f) / 3
            if cut is not None and zc < cut:
                continue
            if isinstance(colours, str):
                col = colours
            else:
                col = colours[0] if zc < -0.3 else colours[1] if zc < 0.4 else colours[2]
            self.face([P[i] for i in f], col, out=c)

    def octa(self, c, r, h, colour, yaw=0.0, tilt=0.0):
        """A double pyramid (crystals, fireflies)."""
        eq = [rot((r * math.cos(a), r * math.sin(a), 0), yaw, tilt) for a in (0, math.pi / 2, math.pi, 1.5 * math.pi)]
        top, bot = rot((0, 0, h), yaw, tilt), rot((0, 0, -h), yaw, tilt)
        at = lambda p: (c[0] + p[0], c[1] + p[1], c[2] + p[2])
        for i in range(4):
            a, b = at(eq[i]), at(eq[(i + 1) % 4])
            self.face([a, b, at(top)], colour, out=c)
            self.face([b, a, at(bot)], colour, out=c)

    def lathe(self, c, profile, n, colours, phase=0.0):
        """Revolves a (radius, height) profile about the vertical through c; colours per band."""
        rings = [[(c[0] + r * math.cos(phase + 2 * math.pi * i / n), c[1] + r * math.sin(phase + 2 * math.pi * i / n), c[2] + h)
                  for i in range(n)] for r, h in profile]
        centre = (c[0], c[1], c[2] + sum(h for _, h in profile) / len(profile))
        for k in range(len(profile) - 1):
            col = colours[min(k, len(colours) - 1)]
            A, B = rings[k], rings[k + 1]
            for i in range(n):
                j = (i + 1) % n
                if profile[k][0] < 1e-6:
                    self.face([A[i], B[j], B[i]], col, out=centre)
                elif profile[k + 1][0] < 1e-6:
                    self.face([A[i], A[j], B[i]], col, out=centre)
                else:
                    self.face([A[i], A[j], B[j], B[i]], col, out=centre)

    def to_object(self, name, material):
        mesh = bpy.data.meshes.new(name)
        bmesh.ops.remove_doubles(self.bm, verts=self.bm.verts, dist=1e-5)
        self.bm.to_mesh(mesh)
        self.bm.free()
        mesh.materials.append(material)
        for p in mesh.polygons:
            p.use_smooth = False
        obj = bpy.data.objects.new(name, mesh)
        bpy.context.scene.collection.objects.link(obj)
        return obj


def rounded_rect(hw, hl, r, per_corner=6):
    pts = []
    for (cx, cy, a0) in ((hw - r, hl - r, 0), (-hw + r, hl - r, 90), (-hw + r, -hl + r, 180), (hw - r, -hl + r, 270)):
        for i in range(per_corner + 1):
            a = math.radians(a0 + 90 * i / per_corner)
            pts.append((cx + r * math.cos(a), cy + r * math.sin(a)))
    return pts


def sd_round_rect(x, y, hw, hl, r):
    qx, qy = abs(x) - (hw - r), abs(y) - (hl - r)
    return math.hypot(max(qx, 0.0), max(qy, 0.0)) + min(max(qx, qy), 0.0) - r


def outside(x, y, margin):
    """True when (x, y) lies at least `margin` outside the pitch boundary."""
    return sd_round_rect(x, y, HW, HL, CORNER) > margin


def behind_camera(x, y):
    """The strip between the play camera and the near goal: only low things may stand there."""
    return y > HL and abs(x) < 28


def smoothstep(a, b, x):
    t = min(1.0, max(0.0, (x - a) / (b - a)))
    return t * t * (3 - 2 * t)


# ---------------------------------------------------------------- pitch, boundary, goals
def build_turf(mat):
    b = Builder()
    bands = 12
    for i in range(bands):
        y0 = -HL + 2 * HL * i / bands
        y1 = -HL + 2 * HL * (i + 1) / bands
        b.quad((-HW, y0, 0), (HW, y0, 0), (HW, y1, 0), (-HW, y1, 0), 'turf_a' if i % 2 else 'turf_b')
    e, w = 0.01, 0.12
    for y in (-GOAL_Z, GOAL_Z, 0.0):                          # goal lines and centre line
        b.quad((-HW + 0.5, y - w, e), (HW - 0.5, y - w, e), (HW - 0.5, y + w, e), (-HW + 0.5, y + w, e), 'line')
    for sign in (-1, 1):                                       # shooting circles
        cy = sign * GOAL_Z
        for i in range(24):
            a0, a1 = math.pi * i / 24, math.pi * (i + 1) / 24
            r0, r1 = 9.0 - w, 9.0 + w
            p = lambda a, r: (r * math.cos(a), cy - sign * r * math.sin(a), e)
            b.quad(p(a0, r0), p(a1, r0), p(a1, r1), p(a0, r1), 'line')
    return b.to_object('turf', mat)


def goals(b):
    for sign in (-1, 1):
        gy = sign * GOAL_Z
        back = gy + sign * GOAL_D
        for sx in (-1, 1):
            b.box(sx * GOAL_W / 2, gy, 0, 0.14, 0.14, 2.1, 'post')
        b.box(0, gy, 2.03, GOAL_W, 0.14, 0.14, 'post')
        b.box(0, back, 0, GOAL_W, 0.05, 2.1, 'net')
        for sx in (-1, 1):
            b.box(sx * GOAL_W / 2, (gy + back) / 2, 0, 0.05, GOAL_D, 2.1, 'net')
        b.box(0, (gy + back) / 2, 2.1, GOAL_W, GOAL_D, 0.05, 'net')



def reef_wall(b):
    """The boundary as a reef wall: a 1.1 m pink wall with a pearl rail, lumpy rock behind it."""
    ring = rounded_rect(HW + 0.15, HL + 0.15, CORNER + 0.15)
    for k in range(len(ring)):
        (ax, ay), (bx, by) = ring[k], ring[(k + 1) % len(ring)]
        nx, ny = by - ay, -(bx - ax)
        ln = math.hypot(nx, ny)
        ox, oy = nx / ln * 0.3, ny / ln * 0.3
        b.quad((ax, ay, 0), (bx, by, 0), (bx, by, 1.1), (ax, ay, 1.1), 'reef')
        b.quad((bx + ox, by + oy, 0), (ax + ox, ay + oy, 0), (ax + ox, ay + oy, 1.1), (bx + ox, by + oy, 1.1), 'reef')
        b.quad((ax, ay, 1.1), (bx, by, 1.1), (bx + ox, by + oy, 1.1), (ax + ox, ay + oy, 1.1), 'pearl')
    # pearls on the rail and reef lumps behind the wall, every ~2.4 m along the perimeter
    lump_ring = rounded_rect(HW + 1.25, HL + 1.25, CORNER + 1.25, per_corner=3)
    pearl_ring = rounded_rect(HW + 0.3, HL + 0.3, CORNER + 0.3, per_corner=3)
    for which, pr in ((0, lump_ring), (1, pearl_ring)):
        k = 0
        for s in range(len(pr)):
            (ax, ay), (bx, by) = pr[s], pr[(s + 1) % len(pr)]
            steps = max(1, round(math.hypot(bx - ax, by - ay) / 2.4))
            for i in range(steps):
                t = i / steps
                x, y = ax + (bx - ax) * t, ay + (by - ay) * t
                if which == 0:
                    col = ('rock_dark', 'rock', 'reef') if k % 3 else ('rock_dark', 'coral_violet', 'anemone')
                    b.blob((x, y, 0.0), rng.uniform(0.8, 1.0), col, scale=(1, 1, rng.uniform(1.1, 1.6)), level=0, jitter=0.15)
                else:
                    b.blob((x, y, 1.18), 0.2, 'pearl', level=0, jitter=0.0)
                k += 1


# ---------------------------------------------------------------- the reef
def ground_h(x, y):
    """Flat around the pitch; beyond it the seabed rises into a bowl so the far end fills the view."""
    d = sd_round_rect(x, y, HW + 9, HL + 7, 8)
    if d <= 0:
        return -0.05
    k = smoothstep(0, 60, d)
    dunes = 1.2 * math.sin(x * 0.15 + 0.4) * math.cos(y * 0.12) + 0.9 * math.sin(x * 0.06 + y * 0.08 + 1)
    return -0.05 + 14 * k * k + dunes * smoothstep(0, 18, d)


def seabed(b):
    n, size = 64, 230.0
    step = size / n
    for i in range(n):
        for j in range(n):
            x0, y0 = -size / 2 + i * step, -size / 2 + j * step
            x1, y1 = x0 + step, y0 + step
            if max(abs(x0), abs(x1)) < HW and max(abs(y0), abs(y1)) < HL:
                continue                                        # the turf covers this
            cx, cy = (x0 + x1) / 2, (y0 + y1) / 2
            ripple = math.sin(cx * 0.35 + cy * 0.12) + 0.7 * math.sin(cy * 0.27 - cx * 0.05 + 2)
            col = 'sand_dark' if ripple < -0.9 else 'sand_light' if ripple > 1.2 else 'sand'
            h = ground_h
            b.face([(x0, y0, h(x0, y0)), (x1, y0, h(x1, y0)), (x1, y1, h(x1, y1))], col)
            b.face([(x0, y0, h(x0, y0)), (x1, y1, h(x1, y1)), (x0, y1, h(x0, y1))], col)


LIGHTER = {'coral_orange': 'coral_yellow', 'coral_pink': 'anemone', 'coral_violet': 'shell_pink',
           'coral_red': 'coral_orange', 'coral_yellow': 'sand_light', 'tube': 'coral_violet'}
CORALS = ('coral_orange', 'coral_pink', 'coral_violet', 'coral_red', 'coral_yellow')


def brain_coral(b, x, y, r, col):
    b.blob((x, y, ground_h(x, y) - 0.1), r, ('rock_dark', col, LIGHTER[col]), scale=(1, 1, 0.75), level=1, jitter=0.1, cut=-0.3,
           yaw=rng.uniform(0, 6.28))


def staghorn(b, x, y, s, col):
    """A branching coral: each branch splits into two or three, twice."""
    def branch(p, az, el, ln, r, depth):
        q = (p[0] + math.cos(az) * math.cos(el) * ln, p[1] + math.sin(az) * math.cos(el) * ln, p[2] + math.sin(el) * ln)
        b.prism(p, q, r, r * 0.7, 5, col, cap=LIGHTER[col])
        if depth:
            for k in range(rng.choice((2, 3))):
                branch(q, az + rng.uniform(-1.2, 1.2), min(1.45, el + rng.uniform(-0.3, 0.35)), ln * 0.72, r * 0.7, depth - 1)
    z = ground_h(x, y) - 0.1
    for k in range(3):
        branch((x, y, z), rng.uniform(0, 6.28), rng.uniform(0.9, 1.35), 1.3 * s, 0.22 * s, 2)


def tube_coral(b, x, y, s, col):
    z = ground_h(x, y) - 0.1
    for k in range(rng.randint(5, 8)):
        a, d = rng.uniform(0, 6.28), rng.uniform(0, 0.9 * s)
        px, py = x + math.cos(a) * d, y + math.sin(a) * d
        h = rng.uniform(0.9, 2.6) * s
        lean = rng.uniform(-0.15, 0.15)
        b.prism((px, py, z), (px + lean * h, py, z + h), 0.26 * s, 0.34 * s, 6, col, cap='tube_tip')


def pillar_coral(b, x, y, s):
    z = ground_h(x, y) - 0.1
    for k in range(rng.randint(3, 5)):
        a, d = rng.uniform(0, 6.28), rng.uniform(0, 1.0 * s)
        px, py = x + math.cos(a) * d, y + math.sin(a) * d
        h = rng.uniform(2.5, 6.0) * s
        r = rng.uniform(0.35, 0.55) * s
        col = 'coral_yellow' if k % 2 else 'coral_orange'
        b.prism((px, py, z), (px, py, z + h), r, r * 0.85, 7, col, cap=False)
        b.prism((px, py, z + h), (px, py, z + h + r * 0.9), r * 0.85, 0.0, 7, col)


def fan_coral(b, x, y, r, col, yaw):
    """A flat, upright sea fan on a short stalk; drawn from both sides."""
    z = ground_h(x, y) - 0.05
    b.prism((x, y, z), (x, y, z + r * 0.35), 0.12, 0.1, 4, 'coral_red', cap=False)
    c = (x, y, z + r * 0.35)
    n = 9
    pts = [c]
    for i in range(n + 1):
        a = math.pi * (0.08 + 0.84 * i / n)
        rr = r * (0.85 + 0.15 * math.sin(i * 2.3))
        pts.append(tuple(c[k] + rot((math.cos(a) * rr, 0, math.sin(a) * rr), yaw)[k] for k in range(3)))
    for i in range(1, n + 1):
        b.face([pts[0], pts[i], pts[i + 1]], col if i % 2 else LIGHTER.get(col, col))


def kelp(b, x, y, h):
    """A tall wavy kelp ribbon with leaves; drawn from both sides."""
    z = ground_h(x, y) - 0.1
    segs = 7
    yaw = rng.uniform(0, 6.28)
    ph = rng.uniform(0, 6.28)
    col, leaf = rng.choice((('kelp', 'kelp_light'), ('grass', 'kelp_light'), ('kelp', 'grass'), ('stone_moss', 'kelp')))
    prev = None
    for s in range(segs + 1):
        t = s / segs
        cx = x + math.sin(t * 3.2 + ph) * 0.6 * t * h * 0.12
        cy = y + math.cos(t * 2.4 + ph) * 0.4 * t * h * 0.12
        w = 0.45 * (1 - 0.6 * t) + 0.1
        a = yaw + t * 1.6
        l = (cx - math.cos(a) * w, cy - math.sin(a) * w, z + h * t)
        r = (cx + math.cos(a) * w, cy + math.sin(a) * w, z + h * t)
        if prev:
            b.quad(prev[0], prev[1], r, l, col)
        if 0 < s < segs and s % 2 == 0:                         # a leaf off one side
            side = 1 if s % 4 else -1
            tip = (cx + side * math.cos(a) * 1.4, cy + side * math.sin(a) * 1.4, z + h * t + 0.9)
            b.face([l if side < 0 else r, tip, (cx, cy, z + h * t + 0.5)], leaf)
        prev = (l, r)


def rock(b, x, y, r, sz=0.8):
    b.blob((x, y, ground_h(x, y) - 0.2), r, ('rock_dark', 'rock', 'rock'), scale=(1.1, 1, sz), level=0, jitter=0.22,
           yaw=rng.uniform(0, 6.28))


def shell(b, x, y, r, yaw):
    """A scallop: a domed fan of ribs, alternating cream and pink."""
    z = ground_h(x, y) + 0.02
    hinge = (x, y, z)
    n = 7
    rim = []
    for i in range(n + 1):
        a = math.pi * (0.1 + 0.8 * i / n)
        rim.append(tuple(hinge[k] + rot((math.cos(a) * r, math.sin(a) * r, 0.0), yaw)[k] for k in range(3)))
    top = tuple(hinge[k] + rot((0, r * 0.45, r * 0.35), yaw)[k] for k in range(3))
    for i in range(n):
        b.face([hinge, rim[i], top], 'shell' if i % 2 else 'shell_pink', out=(x, y, z - 5))
        b.face([rim[i], rim[i + 1], top], 'shell' if i % 2 else 'shell_pink', out=(x, y, z - 5))


def starfish(b, x, y, r, yaw, col):
    z = ground_h(x, y) + 0.03
    c = (x, y, z + r * 0.18)
    pts = []
    for i in range(10):
        rr = r if i % 2 == 0 else r * 0.42
        a = yaw + math.pi * i / 5
        pts.append((x + math.cos(a) * rr, y + math.sin(a) * rr, z))
    for i in range(10):
        b.face([pts[i], pts[(i + 1) % 10], c], col, out=(x, y, z - 5))


def anemone(b, x, y, r, col):
    z = ground_h(x, y) - 0.05
    b.prism((x, y, z), (x, y, z + r * 0.6), r * 0.45, r * 0.55, 6, 'coral_violet', cap='coral_violet')
    for i in range(9):
        a = 2 * math.pi * i / 9
        p0 = (x + math.cos(a) * r * 0.35, y + math.sin(a) * r * 0.35, z + r * 0.6)
        p1 = (x + math.cos(a) * r * 1.0, y + math.sin(a) * r * 1.0, z + r * 1.4)
        b.prism(p0, p1, 0.1 * r, 0.0, 3, col)


def spot(xmin, xmax, ymin, ymax, margin, tall=False):
    """A random point in a box, outside the boundary (and not in front of the camera if tall)."""
    for _ in range(200):
        x, y = rng.uniform(xmin, xmax), rng.uniform(ymin, ymax)
        if outside(x, y, margin) and not (tall and behind_camera(x, y)):
            return x, y
    return None


def reef(b):
    # coral clusters: dense in the band just outside the wall, then thinning into the bowl
    for i in range(120):
        p = spot(-46, 46, -70, 34, 2.8) if i % 3 == 0 else spot(-34, 34, -80, -32, 2.6)
        if not p:
            continue
        x, y = p
        kind = (0, 1, 2, 4, 0, 1, 4, 2, 3, 0)[i % 10]
        col = CORALS[rng.randrange(len(CORALS))]
        if behind_camera(x, y) and kind in (1, 3):
            kind = 0
        s = 1 + max(0.0, sd_round_rect(x, y, HW, HL, CORNER) - 3) / 25
        if kind == 0:
            brain_coral(b, x, y, rng.uniform(0.8, 1.6) * s, col)
        elif kind == 1:
            staghorn(b, x, y, rng.uniform(0.8, 1.3) * s, col)
        elif kind == 2:
            tube_coral(b, x, y, rng.uniform(0.8, 1.2) * s, 'tube' if rng.random() < 0.6 else col)
        elif kind == 3:
            pillar_coral(b, x, y, rng.uniform(0.8, 1.1) * min(s, 1.3))
        else:
            fan_coral(b, x, y, rng.uniform(1.4, 2.4) * s, col, rng.uniform(0, 6.28))
    # hero corals framing the far goal
    for x, y, kind, s, col in ((-11.0, -36.0, 1, 1.9, 'coral_orange'), (11.5, -37.0, 4, 3.6, 'coral_pink'),
                               (-19.0, -34.0, 3, 1.4, None), (20.0, -35.0, 1, 1.7, 'coral_violet'),
                               (-5.0, -40.0, 0, 2.2, 'coral_pink'), (5.5, -41.0, 2, 1.5, 'tube'),
                               (-26.0, -44.0, 4, 4.0, 'coral_violet'), (26.0, -48.0, 3, 1.8, None)):
        if kind == 0:
            brain_coral(b, x, y, s, col)
        elif kind == 1:
            staghorn(b, x, y, s, col)
        elif kind == 2:
            tube_coral(b, x, y, s, col)
        elif kind == 3:
            pillar_coral(b, x, y, s)
        else:
            fan_coral(b, x, y, s, col, rng.uniform(-0.4, 0.4))
    # kelp forests in the bowl: taller with distance so the far end has a skyline
    placed = 0
    while placed < 110:
        a, rr = rng.uniform(0, 2 * math.pi), rng.uniform(46, 110)
        x, y = math.cos(a) * rr * 0.8, math.sin(a) * rr
        if not outside(x, y, 10) or behind_camera(x, y) or y > 60:
            continue
        if -34 < x < -8 and -66 < y < -50 or 8 < x < 28 and -62 < y < -46:
            continue                                            # the wreck and the ruin
        clump = rng.randint(2, 4)
        base = rng.uniform(8, 13) * (1 + (math.hypot(x, y) - 36) / 80)
        for k in range(clump):
            kelp(b, x + rng.uniform(-1.5, 1.5), y + rng.uniform(-1.5, 1.5), base * rng.uniform(0.7, 1.1))
        placed += 1
    # short kelp and sea grass by the wall
    for i in range(40):
        p = spot(-24, 24, -40, 30, 2.4)
        if p:
            kelp(b, p[0], p[1], rng.uniform(2.5, 5.0))
    # rocks, and a rock arch beyond the ruin
    for i in range(40):
        p = spot(-60, 60, -95, 40, 3, tall=True)
        if p:
            rock(b, p[0], p[1], rng.uniform(0.8, 2.6) * (1 + abs(p[1]) / 80))
    ax, ay = -2.0, -74.0
    z = ground_h(ax, ay)
    for sx in (-1, 1):
        for k in range(4):
            b.blob((ax + sx * 7 + rng.uniform(-0.5, 0.5), ay, z + k * 2.6), 2.2 - k * 0.15, ('rock_dark', 'rock', 'rock'), level=1, jitter=0.15)
    for k in range(5):
        b.blob((ax - 6 + 3 * k, ay, z + 11.0 + math.sin(k / 4 * math.pi) * 1.4), 2.2, ('rock_dark', 'rock', 'coral_violet'), level=1, jitter=0.15)
    # small life on the sand close in: shells, starfish, anemones
    for i in range(46):
        p = spot(-26, 26, -44, 28, 1.6)
        if not p:
            continue
        x, y = p
        k = i % 3
        if k == 0:
            shell(b, x, y, rng.uniform(0.4, 0.8), rng.uniform(0, 6.28))
        elif k == 1:
            starfish(b, x, y, rng.uniform(0.45, 0.8), rng.uniform(0, 6.28), 'star' if rng.random() < 0.6 else 'coral_violet')
        else:
            anemone(b, x, y, rng.uniform(0.5, 0.9), 'anemone' if rng.random() < 0.6 else 'coral_yellow')


def shipwreck(b):
    """A sunken galleon lying on its side, left of the far end."""
    cx, cy = -21.0, -58.0
    z = ground_h(cx, cy) - 0.6
    yaw = 0.5
    L, W = 16.0, 5.0
    at = lambda p: (cx + p[0], cy + p[1], z + p[2])
    # hull: ribs of planks as a hull cross-section lathed along the length
    prof = [(-W / 2, 3.2), (-W / 2 - 0.3, 1.6), (-W / 2 + 0.6, 0.2), (W / 2 - 0.6, 0.2), (W / 2 + 0.3, 1.6), (W / 2, 3.2)]
    stations = [(-L / 2, 0.35), (-L / 4, 0.9), (0, 1.0), (L / 4, 0.95), (L / 2, 0.55)]
    secs = []
    for sx, k in stations:
        secs.append([at(rot((sx, px * k, pz * (0.8 + 0.2 * k)), yaw, 0, 0)) for px, pz in prof])
    for i in range(len(secs) - 1):
        A, B = secs[i], secs[i + 1]
        for j in range(len(prof) - 1):
            b.quad(A[j], A[j + 1], B[j + 1], B[j], 'wood' if (i + j) % 2 else 'wood_light')
    for S in (secs[0], secs[-1]):                               # bow and stern walls
        b.face(S, 'wood')
    b.face([at(rot((-L / 2 + 1, 0, 3.4), yaw)), at(rot((-L / 2 - 2.5, 0, 4.0), yaw)), at(rot((-L / 2 + 1, 0, 2.0), yaw))], 'wood_light')
    # a broken mast, leaning, with a torn sail and a crow's nest
    base = at(rot((1.0, 0, 1.0), yaw))
    top = at(rot((3.5, 3.0, 12.0), yaw))
    b.prism(base, top, 0.35, 0.25, 6, 'wood_light', cap='wood')
    mid = tuple(base[k] + (top[k] - base[k]) * 0.7 for k in range(3))
    yard = at(rot((2.8, 2.2, 9.0), yaw))
    b.prism(tuple(yard[k] + rot((0, -3.0, 0), yaw)[k] for k in range(3)), tuple(yard[k] + rot((0, 3.0, 0), yaw)[k] for k in range(3)),
            0.15, 0.15, 4, 'wood')
    s0 = tuple(yard[k] + rot((0, -2.6, 0), yaw)[k] for k in range(3))
    s1 = tuple(yard[k] + rot((0, 2.6, 0), yaw)[k] for k in range(3))
    b.face([s0, s1, tuple(s1[k] + rot((0.6, 0, -4.5), yaw)[k] for k in range(3)),
            tuple(s0[k] + rot((1.4, 0.6, -3.0), yaw)[k] for k in range(3))], 'sand_light')
    b.prism(mid, tuple(mid[k] + (0, 0, 0.8)[k] for k in range(3)), 0.9, 1.0, 6, 'wood', cap='wood_light')
    # algae and coral taking it over
    for i in range(5):
        p = at(rot((rng.uniform(-L / 2.5, L / 2.5), rng.choice((-1, 1)) * W * 0.55, rng.uniform(0.5, 2.5)), yaw))
        b.blob(p, rng.uniform(0.5, 0.9), ('stone_moss', 'kelp', 'kelp_light'), level=0, jitter=0.2)
    # a treasure chest spilling in front of it
    tx, ty = cx + 7.0, cy + 7.0
    tz = ground_h(tx, ty)
    b.obox((tx, ty, tz), (1.6, 1.0, 0.9), 'wood', top='coral_yellow', yaw=0.3)
    b.obox((tx - 0.1, ty - 0.5, tz + 0.9), (1.6, 0.25, 0.9), 'wood_light', top='coral_yellow', yaw=0.3, tilt=-0.5)
    for i in range(7):
        b.blob((tx + rng.uniform(-1.4, 1.4), ty + rng.uniform(0.6, 1.6), tz), rng.uniform(0.15, 0.3), 'fish_yellow', level=0, jitter=0.0)


def ruin(b):
    """A sunken temple: a stepped plinth, columns (some broken) and a fallen pediment."""
    cx, cy = 18.0, -54.0
    z = ground_h(cx, cy) - 0.2
    b.obox((cx, cy, z), (12.0, 8.0, 0.8), 'stone', top='stone', yaw=-0.2)
    b.obox((cx, cy, z + 0.8), (10.5, 6.5, 0.6), 'stone', top='stone_moss', yaw=-0.2)
    top_z = z + 1.4
    for i, (lx, ly) in enumerate(((-4.2, -2.4), (-1.4, -2.4), (1.4, -2.4), (4.2, -2.4), (-4.2, 2.4), (4.2, 2.4))):
        px, py, _ = rot((lx, ly, 0), -0.2)
        h = (6.5, 3.2, 6.5, 6.5, 4.4, 6.5)[i]
        b.prism((cx + px, cy + py, top_z), (cx + px, cy + py, top_z + h), 0.55, 0.5, 8, 'stone', cap='stone_moss' if h < 6 else 'stone')
        if h >= 6:
            b.obox((cx + px, cy + py, top_z + h), (1.4, 1.4, 0.4), 'stone', top='stone_moss', yaw=-0.2)
    # architrave on the front columns, pediment fallen and leaning on the plinth
    b.obox((cx + rot((1.4, -2.4, 0), -0.2)[0], cy + rot((1.4, -2.4, 0), -0.2)[1], top_z + 6.9), (6.6, 1.2, 0.7), 'stone', yaw=-0.2)
    p0 = rot((-5.5, 4.8, 0), -0.2)
    a, c2, apex = (cx + p0[0], cy + p0[1], z), (cx + p0[0] + 6.5, cy + p0[1] + 1.2, z + 0.4), (cx + p0[0] + 3.0, cy + p0[1] + 1.8, z + 2.6)
    b.face([a, c2, apex], 'stone')
    for i in range(4):                                          # stray drums
        x, y = cx + rng.uniform(-8, 8), cy + rng.uniform(4.5, 8)
        b.obox((x, y, ground_h(x, y) - 0.1), (1.0, 2.2, 1.0), 'stone', top='stone_moss', yaw=rng.uniform(0, 3), tilt=1.4)


def water_life(b):
    # fish: schools in arcs above the reef at the far end and the sides
    def fish(p, heading, s, col):
        f = lambda q: tuple(p[k] + rot((q[0] * s, q[1] * s, q[2] * s), heading)[k] for k in range(3))
        nose, tail, top, bot = f((0.9, 0, 0)), f((-0.6, 0, 0)), f((0, 0, 0.4)), f((0, 0, -0.35))
        l, r = f((0, -0.18, 0)), f((0, 0.18, 0))
        for side in (l, r):
            b.face([nose, top, side], col)
            b.face([nose, side, bot], col)
            b.face([tail, side, top], col)
            b.face([tail, bot, side], col)
        b.face([tail, f((-1.1, 0, 0.35)), f((-1.1, 0, -0.35))], col)
    for cx, cy, cz, rr, n, col, s in ((0, -50, 9, 14, 26, 'fish_yellow', 0.55), (-8, -44, 5, 9, 16, 'fish_blue', 0.5),
                                      (14, -64, 13, 12, 18, 'coral_orange', 0.6), (-24, -20, 6, 6, 10, 'fish_yellow', 0.5),
                                      (24, -10, 7, 7, 10, 'fish_blue', 0.5)):
        a0 = rng.uniform(0, 6.28)
        for i in range(n):
            a = a0 + 1.4 * i / n + rng.uniform(-0.05, 0.05)
            rrr = rr + rng.uniform(-1.8, 1.8)
            p = (cx + math.cos(a) * rrr, cy + math.sin(a) * rrr * 0.6, cz + rng.uniform(-1.2, 1.2))
            if not outside(p[0], p[1], 1.5):
                continue
            fish(p, a + math.pi / 2, s * rng.uniform(0.85, 1.15), col)
    # jellyfish drifting high over the far end
    for i in range(9):
        p = spot(-30, 30, -80, -36, 4)
        if not p:
            continue
        x, y = p
        z = ground_h(x, y) + rng.uniform(7, 13)
        r = rng.uniform(0.7, 1.3)
        col = ('anemone', 'shell_pink', 'coral_violet')[i % 3]
        b.lathe((x, y, z), [(0.0, r * 0.9), (r * 0.6, r * 0.8), (r, r * 0.3), (r * 0.9, 0.0), (0.0, 0.1 * r)], 8, [col, col, col, 'pearl'])
        for k in range(4):
            a = 2 * math.pi * k / 4
            p0 = (x + math.cos(a) * r * 0.5, y + math.sin(a) * r * 0.5, z)
            b.prism(p0, (p0[0] + rng.uniform(-0.3, 0.3), p0[1] + rng.uniform(-0.3, 0.3), z - r * 2.6), 0.06, 0.0, 3, 'shell_pink')
    # bubble columns
    for i in range(10):
        p = spot(-28, 28, -70, 20, 2.5)
        if not p:
            continue
        x, y = p
        z = ground_h(x, y)
        for k in range(9):
            b.octa((x + math.sin(k * 1.3) * 0.3, y + math.cos(k * 1.7) * 0.3, z + 0.8 + k * 1.1 + rng.uniform(-0.2, 0.2)),
                   0.12 + 0.02 * k, 0.12 + 0.02 * k, 'pearl')


def build_scenery(mat):
    b = Builder()
    seabed(b)
    reef_wall(b)
    goals(b)
    shipwreck(b)
    ruin(b)
    reef(b)
    water_life(b)
    return b.to_object('scenery', mat)


def build_sky(mat):
    bm = bmesh.new()
    uv = bm.loops.layers.uv.new('UVMap')
    bmesh.ops.create_uvsphere(bm, u_segments=32, v_segments=12, radius=320.0)
    bmesh.ops.reverse_faces(bm, faces=bm.faces)                # seen from inside
    for f in bm.faces:
        for loop in f.loops:
            zn = max(0.0, loop.vert.co.z / 320.0)
            # right half: the gradient. The camera only ever sees the first few degrees above the
            # horizon, so the pale glow is a thin band there (sin 4° ≈ 0.07) and the rest is deep water.
            loop[uv].uv = (0.75, 0.02 + 0.96 * min(1.0, zn / 0.07) ** 0.5)
    mesh = bpy.data.meshes.new('sky')
    bm.to_mesh(mesh)
    bm.free()
    mesh.materials.append(mat)
    obj = bpy.data.objects.new('sky', mesh)
    bpy.context.scene.collection.objects.link(obj)
    return obj


# ---------------------------------------------------------------- preview (WORLD_PREVIEW=1)
def render_preview(mats, sun_from, sun_colour, ambient):
    """Renders the play camera's view (portrait phone, 50° vertical FOV) to preview.png."""
    from mathutils import Vector
    scene = bpy.context.scene
    bpy.data.objects['sky'].visible_shadow = False             # the dome would shade the sun out
    sky = mats['sky'].node_tree                                # the sky is unlit, like on device
    em = sky.nodes.new('ShaderNodeEmission')
    sky.links.new(sky.nodes['Image Texture'].outputs['Color'], em.inputs['Color'])
    sky.links.new(em.outputs['Emission'], sky.nodes['Material Output'].inputs['Surface'])
    cam_data = bpy.data.cameras.new('cam')
    cam_data.sensor_fit = 'VERTICAL'
    cam_data.angle = math.radians(50)
    cam_data.clip_end = 1000
    cam = bpy.data.objects.new('cam', cam_data)
    scene.collection.objects.link(cam)
    cam.location = (0, 46, 24)                                 # game (0, 24, -46)
    cam.rotation_euler = (Vector((0, -2, 0)) - cam.location).to_track_quat('-Z', 'Y').to_euler()
    scene.camera = cam
    sun_data = bpy.data.lights.new('sun', 'SUN')
    sun_data.energy = 3.0
    sun_data.color = sun_colour
    sun = bpy.data.objects.new('sun', sun_data)
    scene.collection.objects.link(sun)
    sun.rotation_euler = (-Vector(sun_from)).to_track_quat('-Z', 'Y').to_euler()
    world = bpy.data.worlds.new('world')
    world.use_nodes = True
    world.node_tree.nodes['Background'].inputs['Color'].default_value = (*ambient, 1)
    world.node_tree.nodes['Background'].inputs['Strength'].default_value = 1.0
    scene.world = world
    scene.render.engine = 'BLENDER_EEVEE'
    scene.render.resolution_x, scene.render.resolution_y = 540, 1200
    scene.render.resolution_percentage = 100
    scene.view_settings.view_transform = 'Standard'
    scene.render.image_settings.file_format = 'PNG'
    scene.render.image_settings.compression = 100
    scene.render.filepath = os.path.join(HERE, 'preview.png')
    bpy.ops.render.render(write_still=True)

def main():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    img = build_palette()
    mats = {n: make_material(n, img) for n in ('turf', 'scenery', 'sky')}
    objs = [build_turf(mats['turf']), build_scenery(mats['scenery']), build_sky(mats['sky'])]
    tris = sum(sum(len(p.vertices) - 2 for p in o.data.polygons) for o in objs)
    print(f'{WORLD}: {tris} triangles in {len(objs)} meshes')
    bpy.ops.export_scene.gltf(filepath=os.path.join(HERE, f'{WORLD}.glb'), export_format='GLB',
                              export_apply=True, export_yup=True)
    bpy.ops.wm.usd_export(filepath=os.path.join(HERE, f'{WORLD}.usdz'), export_materials=True,
                          generate_preview_surface=True, export_textures_mode='NEW', relative_paths=True,
                          convert_orientation=True, export_global_forward_selection='NEGATIVE_Z',
                          export_global_up_selection='Y')
    if os.environ.get('WORLD_PREVIEW'):
        render_preview(mats, sun_from=(14, 10, 60), sun_colour=(0.9, 1.0, 1.0), ambient=(0.32, 0.46, 0.56))


main()
