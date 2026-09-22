"""
Builds Magic Wood (Zauberwald): an enchanted forest clearing at dusk (spec §13, ADR 0005).

One scene, two exports: `magicwood.glb` (Filament, Android) and `magicwood.usdz` (RealityKit,
iOS), plus the `palette.png` both sample. Deterministic: the same script always writes the same
world (one seeded RNG, consumed in a fixed order).

Run: tools/build-worlds.sh  (Blender 5, headless)
Preview: WORLD_PREVIEW=1 blender --background --factory-startup --python build_magicwood.py
         also renders preview.png from the play camera.

Coordinates: Blender is Z-up; the exporters convert to Y-up, where the game's pitch lies in X-Z
with Z along the pitch (spec §1). Blender's -Y is the game's +Z, so the far end (what the play
camera looks at) is Blender -Y.

Materials are bound **by name** on each platform (ADR 0005): `turf`, `scenery`, `sky`. All three
sample one palette texture: swatches in the left half, the sky's vertical gradient in the right.

What is in it: a moss-green pitch inside a wooden plank fence; a bowl of forest rising away from
the clearing — giant gnarled trees with green, teal and violet canopies, a ring of stacked-cone
spire trees, lantern mushrooms with glowing ground halos, fireflies, violet crystals, a ring of
standing stones with a floating crystal behind the far goal, and a glowing stream on the east side.
"""
import math
import os
import random

import bmesh
import bpy

HERE = os.path.dirname(os.path.abspath(__file__))
WORLD = 'magicwood'
rng = random.Random(23)

HW, HL = 15.0, 30.0          # pitch half-extents (spec §1)
CORNER = 2.0                 # field hockey corner radius
GOAL_Z, GOAL_W, GOAL_D = 26.0, 6.0, 1.6

# ---------------------------------------------------------------- palette texture
# 32 swatches in a 4x8 grid on the left half; a vertical sky gradient in the right half.
TEX, COLS, ROWS = 256, 4, 8


def rgb(h):
    return (((h >> 16) & 255) / 255.0, ((h >> 8) & 255) / 255.0, (h & 255) / 255.0)


SWATCH = {
    'turf_a': rgb(0x48a052), 'turf_b': rgb(0x40934a), 'line': rgb(0xf3f7ea), 'post': rgb(0xf8fafc),
    'net': rgb(0xe2e8f0), 'moss': rgb(0x2e5c33), 'moss_dark': rgb(0x1f4128), 'moss_light': rgb(0x4c8a3e),
    'wood': rgb(0x6b4527), 'wood_light': rgb(0xa8743f), 'fence_cap': rgb(0x8fd14f), 'bark': rgb(0x4a2f1a),
    'bark_light': rgb(0x7a5230), 'leaf_dark': rgb(0x17402c), 'leaf': rgb(0x3f9a4c), 'leaf_light': rgb(0x9adf6e),
    'violet_dark': rgb(0x3a1750), 'violet': rgb(0x9a4fb8), 'violet_light': rgb(0xf0a1e2), 'teal_dark': rgb(0x113f3a),
    'teal': rgb(0x2f9a7a), 'teal_light': rgb(0xa2f0c8), 'stem': rgb(0xf3e7cc), 'cap_orange': rgb(0xffa040),
    'cap_mint': rgb(0x7dffc2), 'cap_violet': rgb(0xc77dff), 'cap_pink': rgb(0xff8fb1), 'glow': rgb(0xfff2a8),
    'firefly': rgb(0xf4ff7a), 'stone': rgb(0x7f8a86), 'crystal': rgb(0xa8f0ff), 'water': rgb(0x62dcff),
}
NAMES = list(SWATCH)
assert len(NAMES) == COLS * ROWS
# Sky, bottom (horizon) to top: a warm dusk glow under deep violet-blue.
SKY = [(0.0, rgb(0xffb37a)), (0.18, rgb(0xe07a7e)), (0.45, rgb(0x6a3a78)), (0.75, rgb(0x2a2258)), (1.0, rgb(0x0e1030))]


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


def fence(b):
    """A plank fence on the boundary: a solid 1.1 m wall, a rail, and posts with mossy caps."""
    ring = rounded_rect(HW + 0.15, HL + 0.15, CORNER + 0.15)
    for k in range(len(ring)):
        (ax, ay), (bx, by) = ring[k], ring[(k + 1) % len(ring)]
        nx, ny = by - ay, -(bx - ax)
        ln = math.hypot(nx, ny)
        ox, oy = nx / ln * 0.3, ny / ln * 0.3
        b.quad((ax, ay, 0), (bx, by, 0), (bx, by, 1.1), (ax, ay, 1.1), 'wood')
        b.quad((bx + ox, by + oy, 0), (ax + ox, ay + oy, 0), (ax + ox, ay + oy, 1.1), (bx + ox, by + oy, 1.1), 'wood')
        b.quad((ax, ay, 1.1), (bx, by, 1.1), (bx + ox, by + oy, 1.1), (ax + ox, ay + oy, 1.1), 'wood_light')
    # posts just outside the wall, every ~3 m along the perimeter
    post_ring = rounded_rect(HW + 0.62, HL + 0.62, CORNER + 0.62, per_corner=3)
    per = []
    for k in range(len(post_ring)):
        (ax, ay), (bx, by) = post_ring[k], post_ring[(k + 1) % len(post_ring)]
        seg = math.hypot(bx - ax, by - ay)
        steps = max(1, round(seg / 3.0))
        for s in range(steps):
            t = s / steps
            per.append((ax + (bx - ax) * t, ay + (by - ay) * t))
    for i, (x, y) in enumerate(per):
        h = 1.45 + 0.12 * math.sin(i * 1.7)
        b.box(x, y, 0, 0.34, 0.34, h, 'wood_light', top='fence_cap')
        b.prism((x, y, h), (x, y, h + 0.32), 0.26, 0.0, 4, 'fence_cap', phase=math.pi / 4)


# ---------------------------------------------------------------- the forest
def ground_h(x, y):
    """Flat clearing; beyond it the forest floor rises into a bowl so the far end fills the view."""
    d = sd_round_rect(x, y, HW + 11, HL + 8, 8)
    if d <= 0:
        return -0.05
    k = smoothstep(0, 60, d)
    bumps = 1.4 * math.sin(x * 0.13 + 0.7) * math.cos(y * 0.11) + 1.0 * math.sin(x * 0.07 - y * 0.05 + 2)
    return -0.05 + 16 * k * k + bumps * smoothstep(0, 20, d)


def ground(b):
    n, size = 64, 230.0
    step = size / n
    for i in range(n):
        for j in range(n):
            x0, y0 = -size / 2 + i * step, -size / 2 + j * step
            x1, y1 = x0 + step, y0 + step
            if max(abs(x0), abs(x1)) < HW and max(abs(y0), abs(y1)) < HL:
                continue                                        # the turf covers this
            cx, cy = (x0 + x1) / 2, (y0 + y1) / 2
            nse = math.sin(cx * 0.21 + 1.1) * math.cos(cy * 0.17) + 0.6 * math.sin(cx * 0.05 + cy * 0.09)
            col = 'moss_dark' if nse < -0.35 else 'moss_light' if nse > 1.05 else 'moss'
            h = ground_h
            b.face([(x0, y0, h(x0, y0)), (x1, y0, h(x1, y0)), (x1, y1, h(x1, y1))], col)
            b.face([(x0, y0, h(x0, y0)), (x1, y1, h(x1, y1)), (x0, y1, h(x0, y1))], col)


CANOPY = {
    'green': ('leaf_dark', 'leaf', 'leaf_light'),
    'violet': ('violet_dark', 'violet', 'violet_light'),
    'teal': ('teal_dark', 'teal', 'teal_light'),
}


def push_out(x, y, margin):
    """Moves a point out of the boundary (plus margin) along the nearer axis."""
    if outside(x, y, margin):
        return x, y
    if abs(x) - HW > abs(y) - HL:
        return math.copysign(HW + margin + 0.5, x or 1), y
    return x, math.copysign(HL + margin + 0.5, y or 1)


def hero_tree(b, x, y, h, r0, pal, feet):
    """A giant gnarled tree: a leaning, flared trunk, a few branches ending in canopy blobs."""
    z = ground_h(x, y) - 0.2
    cols = CANOPY[pal]
    lean = rng.uniform(0, 2 * math.pi)
    lx, ly = math.cos(lean) * 0.08 * h, math.sin(lean) * 0.08 * h
    centre = lambda t: (x + lx * t * t + math.sin(t * 4 + x) * 0.03 * h, y + ly * t * t, z + h * t)
    radius = lambda t: r0 * (1 - 0.68 * t ** 0.8)
    segs = 5
    for s in range(segs):
        t0, t1 = s / segs, (s + 1) / segs
        b.prism(centre(t0), centre(t1), radius(t0), radius(t1), 7, 'bark' if s % 2 else 'bark_light',
                cap=False, phase=s * 0.4)
    for k in range(5):                                          # root buttresses
        a = 2 * math.pi * k / 5 + rng.uniform(-0.3, 0.3)
        foot = (x + math.cos(a) * r0 * 2.2, y + math.sin(a) * r0 * 2.2, z)
        b.prism(foot, (x, y, z + r0 * 2.0), 0.35 * r0, 0.25 * r0, 4, 'bark')
    feet.append((x, y, r0 * 2.3))
    blobs = []
    away = math.atan2(y, x)
    for i in range(rng.choice((2, 3, 3))):
        t = rng.uniform(0.5, 0.8)
        a = away + rng.uniform(-1.9, 1.9)
        tilt = rng.uniform(0.5, 0.9)
        ln = h * rng.uniform(0.28, 0.4)
        p0 = centre(t)
        p1 = (p0[0] + math.cos(a) * math.cos(tilt) * ln, p0[1] + math.sin(a) * math.cos(tilt) * ln, p0[2] + math.sin(tilt) * ln)
        b.prism(p0, p1, radius(t) * 0.5, 0.14, 5, 'bark_light', cap=False)
        blobs.append((p1, rng.uniform(0.17, 0.22) * h))
    top = centre(1.0)
    blobs.append(((top[0], top[1], top[2] + 0.8), 0.27 * h))
    for i in range(2):
        a = away + rng.uniform(-2.2, 2.2)
        d = h * rng.uniform(0.12, 0.2)
        blobs.append(((top[0] + math.cos(a) * d, top[1] + math.sin(a) * d, top[2] + rng.uniform(-1.5, 1.0)), h * rng.uniform(0.15, 0.2)))
    for (p, r) in blobs:
        px, py = push_out(p[0], p[1], r + 0.8)
        b.blob((px, py, p[2]), r, cols, scale=(rng.uniform(0.95, 1.15), rng.uniform(0.95, 1.15), rng.uniform(0.62, 0.78)),
               jitter=0.14, level=1, yaw=rng.uniform(0, 6.28))


def spire_tree(b, x, y, h, cols):
    """A stylised fir: a short trunk and three stacked cones."""
    z = ground_h(x, y) - 0.2
    b.prism((x, y, z), (x, y, z + h * 0.3), h * 0.05, h * 0.035, 5, 'bark', cap=False)
    phase = rng.uniform(0, 6.28)
    for k, (t0, t1, rr) in enumerate(((0.2, 0.62, 0.3), (0.42, 0.82, 0.23), (0.62, 1.0, 0.15))):
        b.prism((x, y, z + h * t0), (x, y, z + h * t1), h * rr, 0.0, 7, cols[k % len(cols)], phase=phase + k)
        b.face([(x + h * rr * math.cos(phase + k + 2 * math.pi * i / 7), y + h * rr * math.sin(phase + k + 2 * math.pi * i / 7), z + h * t0)
                for i in range(7)], cols[0], out=(x, y, z + h))


MUSHROOM_CAPS = ('cap_orange', 'cap_orange', 'cap_pink', 'cap_mint', 'cap_violet')


def mushroom(b, x, y, r, h, cap, halo=True):
    z = ground_h(x, y)
    tilt = rng.uniform(-0.12, 0.12)
    top = (x + math.sin(tilt) * h, y, z + h)
    b.prism((x, y, z - 0.1), top, r * 0.28, r * 0.2, 6, 'stem', cap=False)
    prof = [(0.0, 0.62), (0.45, 0.58), (0.82, 0.42), (1.0, 0.16), (0.9, 0.0), (0.2, 0.05)]
    b.lathe((top[0], top[1], top[2] - 0.15 * r), [(pr * r, ph * r) for pr, ph in prof], 8,
            ['glow', cap, cap, cap, 'stem'], phase=rng.uniform(0, 6.28))
    if halo:                                                    # a glowing pool on the ground
        hr = r * 1.5 + 0.3
        n = 8
        ring = [(x + hr * math.cos(2 * math.pi * i / n), y + hr * math.sin(2 * math.pi * i / n)) for i in range(n)]
        pts = [(px, py, ground_h(px, py) + 0.05) for px, py in ring]
        b.face(pts, 'fence_cap' if cap in ('cap_orange', 'cap_pink') else 'teal_light', out=(x, y, z - 5))


def forest(b):
    feet = []
    # giant trees: framing the far end, and flanking the sides
    heroes = [
        (-24.0, -8.0, 17, 1.7, 'green'), (27.5, 6.0, 15, 1.5, 'violet'), (-26.0, 20.0, 13, 1.3, 'teal'),
        (29.0, 24.0, 13, 1.3, 'green'), (-25.5, -30.0, 16, 1.6, 'teal'), (28.0, -22.0, 15, 1.5, 'green'),
        (-17.0, -45.0, 17, 1.6, 'violet'), (19.0, -47.0, 18, 1.7, 'teal'), (-4.0, -66.0, 22, 2.0, 'green'),
        (-28.0, -58.0, 19, 1.8, 'green'), (31.0, -64.0, 20, 1.9, 'violet'), (11.0, -78.0, 23, 2.1, 'teal'),
        (-19.0, -82.0, 22, 2.0, 'violet'),
    ]
    for x, y, h, r0, pal in heroes:
        hero_tree(b, x, y, h, r0, pal, feet)
    # a ring of spire trees filling the bowl
    placed, tries = 0, 0
    while placed < 150 and tries < 5000:
        tries += 1
        a, rr = rng.uniform(0, 2 * math.pi), rng.uniform(40, 112)
        x, y = math.cos(a) * rr * 0.8, math.sin(a) * rr
        if not outside(x, y, 14) or behind_camera(x, y) or y > 60:
            continue
        if abs(x) < 9 and -56 < y < -36:
            continue                                            # the standing stones' glade
        if any(math.hypot(x - fx, y - fy) < fr + 3 for fx, fy, fr in feet):
            continue
        d = math.hypot(x, y)
        h = rng.uniform(9, 14) * (1 + (d - 40) / 90)
        roll = rng.random()
        cols = ('teal_dark', 'leaf_dark', 'teal') if roll < 0.45 else ('leaf_dark', 'leaf', 'leaf_dark') if roll < 0.8 else ('violet_dark', 'violet', 'violet_dark')
        spire_tree(b, x, y, h, cols)
        placed += 1
    return feet


def glade(b):
    """Behind the far goal: a ring of standing stones round a floating crystal."""
    cx, cy = 0.0, -46.0
    z = ground_h(cx, cy)
    for i in range(9):
        a = 2 * math.pi * i / 9 + 0.2
        x, y = cx + 7.0 * math.cos(a), cy + 7.0 * math.sin(a)
        h = rng.uniform(3.2, 4.6)
        b.obox((x, y, ground_h(x, y) - 0.2), (1.3, 0.8, h), 'stone', top='moss_light', yaw=a, tilt=rng.uniform(-0.08, 0.08),
               roll=rng.uniform(-0.1, 0.1))
    b.lathe((cx, cy, z - 0.1), [(1.8, 0.0), (1.8, 0.7), (1.3, 1.2), (0.0, 1.2)], 7, ['stone', 'stone', 'moss_light'])
    b.octa((cx, cy, z + 4.2), 0.9, 2.0, 'crystal', yaw=0.4)
    for i in range(6):                                          # little satellite shards
        a = 2 * math.pi * i / 6
        b.octa((cx + 2.3 * math.cos(a), cy + 2.3 * math.sin(a), z + 3.6 + 0.6 * math.sin(i * 2.1)), 0.22, 0.5, 'crystal', yaw=a)
    b.face([(cx + 5.5 * math.cos(2 * math.pi * i / 12), cy + 5.5 * math.sin(2 * math.pi * i / 12), z + 0.04) for i in range(12)],
           'moss_light', out=(cx, cy, z - 5))


def stream(b):
    """A glowing brook down the east side, between the fence and the trees."""
    xs = lambda y: 24.0 + 2.4 * math.sin(y * 0.11) + 1.1 * math.sin(y * 0.31 + 1)
    y, w = -46.0, 1.4
    prev = None
    while y <= 44.0:
        x = xs(y)
        l, r = (x - w, y, ground_h(x - w, y) + 0.06), (x + w, y, ground_h(x + w, y) + 0.06)
        if prev:
            b.quad(prev[0], prev[1], r, l, 'water')
        prev = (l, r)
        y += 2.0
    for i in range(18):                                         # stones along the banks
        yy = rng.uniform(-44, 42)
        xx = xs(yy) + rng.choice((-1, 1)) * rng.uniform(1.7, 2.6)
        b.blob((xx, yy, ground_h(xx, yy)), rng.uniform(0.35, 0.8), ('stone', 'stone', 'moss_light'), scale=(1, 1, 0.65), level=0, jitter=0.2)


def undergrowth(b, feet):
    # hedges hugging the fence outside, with berry tops now and then
    for side in (-1, 1):
        y = -HL - 2.0
        while y < HL - 1:
            x = side * (HW + rng.uniform(1.6, 2.6))
            r = rng.uniform(0.8, 1.3)
            top = 'violet_light' if rng.random() < 0.2 else 'leaf_light'
            b.blob((x, y, 0.0), r, ('leaf_dark', 'leaf', top), scale=(1.0, 1.3, 0.8), level=1, jitter=0.15, cut=-0.4)
            y += rng.uniform(2.2, 3.4)
    x = -HW + 1
    while x < HW - 1:                                           # behind the far goal, low
        y = -(HL + rng.uniform(1.6, 2.6))
        r = rng.uniform(0.8, 1.2)
        b.blob((x, y, 0.0), r, ('leaf_dark', 'leaf', 'leaf_light'), scale=(1.3, 1.0, 0.8), level=1, jitter=0.15, cut=-0.4)
        x += rng.uniform(2.4, 3.2)
    # lantern mushrooms: clusters at the tree feet, a big one each, and a scatter by the fence
    for fx, fy, fr in feet:
        for i in range(rng.randint(4, 7)):
            a, d = rng.uniform(0, 6.28), fr + rng.uniform(0.3, 3.5)
            x, y = fx + math.cos(a) * d, fy + math.sin(a) * d
            if not outside(x, y, 1.6):
                continue
            big = i == 0
            mushroom(b, x, y, rng.uniform(1.2, 1.8) if big else rng.uniform(0.4, 0.8),
                     rng.uniform(2.2, 3.2) if big else rng.uniform(0.6, 1.4), rng.choice(MUSHROOM_CAPS), halo=big)
    for i in range(40):
        if rng.random() < 0.6:
            x, y = rng.choice((-1, 1)) * rng.uniform(17.0, 21.0), rng.uniform(-44, 26)
        else:
            x, y = rng.uniform(-14, 14), -rng.uniform(33.5, 38.0)
        if not outside(x, y, 1.6):
            continue
        mushroom(b, x, y, rng.uniform(0.4, 0.9), rng.uniform(0.7, 1.7), rng.choice(MUSHROOM_CAPS), halo=rng.random() < 0.3)
    # giant lantern mushrooms framing the far corners
    for x, y, r, h, cap in ((-12.0, -37.0, 2.4, 4.6, 'cap_orange'), (13.0, -38.5, 2.1, 3.8, 'cap_violet'),
                            (-21.5, -36.0, 1.8, 3.2, 'cap_mint'), (22.0, -33.0, 1.6, 2.8, 'cap_pink'),
                            (-20.0, -18.0, 1.6, 3.0, 'cap_orange'), (20.5, -4.0, 1.5, 2.6, 'cap_mint')):
        mushroom(b, x, y, r, h, cap)
    # violet crystal clusters
    for cx, cy in ((-9.0, -52.0), (9.5, -54.0), (-22.0, 2.0), (23.0, -12.0), (-6.0, -38.0)):
        z = ground_h(cx, cy)
        for i in range(5):
            a = rng.uniform(0, 6.28)
            p = (cx + math.cos(a) * rng.uniform(0, 1.2), cy + math.sin(a) * rng.uniform(0, 1.2), z)
            h = rng.uniform(0.8, 2.0)
            b.octa((p[0], p[1], p[2] + h * 0.6), 0.3 + h * 0.12, h, 'cap_violet' if i % 2 else 'violet_light',
                   yaw=a, tilt=rng.uniform(-0.4, 0.4))
    # mossy boulders
    for i in range(26):
        a, rr = rng.uniform(0, 6.28), rng.uniform(34, 70)
        x, y = math.cos(a) * rr * 0.7, math.sin(a) * rr
        if not outside(x, y, 3) or behind_camera(x, y):
            continue
        b.blob((x, y, ground_h(x, y)), rng.uniform(0.8, 2.0), ('stone', 'stone', 'moss_light'), scale=(1.2, 1, 0.7), level=0, jitter=0.2)


def fireflies(b):
    placed = 0
    while placed < 140:
        x, y = rng.uniform(-40, 40), rng.uniform(-80, 24)
        if not outside(x, y, 2.5):
            continue
        z = ground_h(x, y) + rng.uniform(1.0, 9.0)
        col = 'firefly' if rng.random() < 0.7 else 'cap_mint' if rng.random() < 0.5 else 'violet_light'
        b.octa((x, y, z), 0.17, 0.24, col, yaw=rng.uniform(0, 6.28))
        placed += 1


def build_scenery(mat):
    b = Builder()
    ground(b)
    fence(b)
    goals(b)
    feet = forest(b)
    glade(b)
    stream(b)
    undergrowth(b, feet)
    fireflies(b)
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
            # horizon, so the warm glow is a thin band there (sin 4° ≈ 0.07) and the rest is dusk.
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
        render_preview(mats, sun_from=(26, 30, 50), sun_colour=(1.0, 0.84, 0.66), ambient=(0.30, 0.28, 0.42))


main()
