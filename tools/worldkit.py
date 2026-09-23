"""
The world kit: everything the five world scripts share (ADR 0005, ADR 0006).

A world script (`shared/assets/worlds/<id>/build_<id>.py`) imports this module, declares its
palette and sky, and fills three meshes; `run()` does the rest — the palette texture, the three
materials, the triangle budget, the pitch contract, both exports and the optional preview.

Coordinates: a world is authored in **game coordinates** — X across the pitch, Y up, Z along it,
the user's goal at −Z (spec §1) — the same frame the prototype's worlds (web/js/worlds) are
described in. The builder converts every vertex to Blender's Z-up frame (x, −z, y); the exporters
convert back to Y-up (glTF Y-up; USD forward −Z, up Y), so a world lands in the apps as authored.

The asset contract both apps load (ADR 0005, ADR 0007, conventions: Rendering):
  - `<id>.glb` + `<id>.usdz` + `palette.png`, with three core meshes, one material each, bound
    by name: `turf` (the pitch surface and its markings), `scenery` (everything lit that stands
    still), `sky` (everything unlit that stands still: the dome, stars, painted glows);
  - plus one mesh `fx_<effect>` per effect shared/data/effects.toml declares for the world — and
    no other: everything that moves, pulses or twinkles (ADR 0007). Each vertex carries its
    motion data inside its palette swatch (`FxMesh`); particles are baked as flat quads;
  - colour comes only from the palette texture: swatches in its left half, the sky's lat-long
    map in its right half; no vertex colours; the V convention is Blender's (glTF flips it);
  - deterministic: seeded RNGs (a seed of its own for each effect), faces added in a fixed order —
    the GLB and the palette rebuild byte-identical; the USDZ rebuilds with identical content (prims
    in name order, zip times pinned), though USD's crate writer lays its tables out differently;
  - ≤ 45k triangles in the core meshes, ≤ 12k in the effects; nothing inside the pitch boundary
    but the surface, its markings and the goals — for an effect, wherever its motion takes it
    (only particles declared `over_pitch` may cross it).

Shading is the apps' own (ADR 0006): Lambert under a hemisphere light and a sun, no shadow maps.
So colour does the work: shade that the prototype got from shadows is painted into swatches.
"""
import math
import os
import random
import sys

import bmesh
import bpy
from mathutils import Matrix, Vector

# ================================================================ the pitch (spec §1)
HW, HL = 15.0, 30.0                      # half-extents of the boundary
GOAL_Z, GOAL_W, GOAL_D, GOAL_H = 26.0, 6.0, 1.6, 1.9
LINE_Z = 9.5                             # the 23 m lines (field) / blue lines (ice)
FACEOFF_R, CREASE_R, D_R = 4.5, 3.2, 9.5
END_SPOTS = [(sx * 7.0, sz * 20.0) for sz in (-1, 1) for sx in (-1, 1)]
NEUTRAL_SPOTS = [(sx * 7.0, sz * 7.0) for sz in (-1, 1) for sx in (-1, 1)]
CORNER = {'field': 2.0, 'ice': 8.5}
WALL_T, SLAB_W = 0.4, 2.2                # the boards' thickness; the rim the pitch stands on
DECOR_Y, LINE_Y = 0.006, 0.012           # paint on the pitch: decoration, then the markings
SKY_R = 320.0
BUDGET = 45000                           # the three core meshes
FX_BUDGET = 12000                        # every effect of a world together (ADR 0007)

TEX, COLS, ROWS = 512, 16, 32            # palette: 16 x 32 swatches (16 px) left, the sky map right


# ================================================================ small maths
def clamp(v, a, b):
    return a if v < a else b if v > b else v


def lerp(a, b, t):
    return a + (b - a) * t


def smooth(a, b, x):
    t = clamp((x - a) / (b - a), 0.0, 1.0)
    return t * t * (3 - 2 * t)


def sd_round_rect(x, z, hw=HW, hl=HL, r=2.0):
    """Signed distance to a rounded rectangle centred on the origin (negative inside)."""
    qx, qz = abs(x) - (hw - r), abs(z) - (hl - r)
    return math.hypot(max(qx, 0.0), max(qz, 0.0)) + min(max(qx, qz), 0.0) - r


def push_out(x, z, off, corner):
    """(x, z) moved onto the rounded rectangle `off` outside the boundary, if it lies inside it
    — terrain that runs under the rim stays out of the pitch."""
    if sd_round_rect(x, z, r=corner) >= off:
        return x, z
    hw, hl, r = HW + off, HL + off, corner + off
    qx, qz = abs(x) - (hw - r), abs(z) - (hl - r)
    if qx > 0 and qz > 0:
        ln = math.hypot(qx, qz)
        px, pz = hw - r + qx / ln * r, hl - r + qz / ln * r
    elif qx > qz:
        px, pz = hw, abs(z)
    else:
        px, pz = abs(x), hl
    return math.copysign(px, x or 1.0), math.copysign(pz, z or 1.0)


def half_width(z, r, hw=HW, hl=HL):
    """Half-width of the rounded boundary at z."""
    d = abs(z) - (hl - r)
    if d <= 0:
        return hw
    return hw - r + math.sqrt(max(r * r - min(d, r) ** 2, 0.0))


def _hash2(i, j):
    h = (i * 374761393 + j * 668265263) & 0xffffffff
    h = ((h ^ (h >> 13)) * 1274126177) & 0xffffffff
    h ^= h >> 16
    return h / 4294967296.0


def vnoise(x, z):
    """Smooth value noise in [-1, 1]."""
    i, j = math.floor(x), math.floor(z)
    fx, fz = x - i, z - j
    u, v = fx * fx * (3 - 2 * fx), fz * fz * (3 - 2 * fz)
    a, b, c, d = _hash2(i, j), _hash2(i + 1, j), _hash2(i, j + 1), _hash2(i + 1, j + 1)
    return (a + (b - a) * u + (c - a) * v + (a - b - c + d) * u * v) * 2 - 1


def fbm(x, z, octaves=3):
    s, a, f, n = 0.0, 1.0, 1.0, 0.0
    for k in range(octaves):
        s += vnoise(x * f + k * 13.7, z * f + k * 7.1) * a
        n += a
        a *= 0.5
        f *= 2.1
    return s / n


def T(x, y, z):
    return Matrix.Translation((x, y, z))


def S(x, y=None, z=None):
    return Matrix.Diagonal((x, x if y is None else y, x if z is None else z, 1.0))


def R(angle, axis):
    """A rotation in game space: axis 'X', 'Y' (up) or 'Z'."""
    return Matrix.Rotation(angle, 4, axis)


def _sub(a, b):
    return (a[0] - b[0], a[1] - b[1], a[2] - b[2])


def _dot(a, b):
    return a[0] * b[0] + a[1] * b[1] + a[2] * b[2]


def _cross(a, b):
    return (a[1] * b[2] - a[2] * b[1], a[2] * b[0] - a[0] * b[2], a[0] * b[1] - a[1] * b[0])


def _norm(a):
    ln = math.sqrt(_dot(a, a)) or 1.0
    return (a[0] / ln, a[1] / ln, a[2] / ln)


def _newell(pts):
    n = [0.0, 0.0, 0.0]
    for i, p in enumerate(pts):
        q = pts[(i + 1) % len(pts)]
        n[0] += (p[1] - q[1]) * (p[2] + q[2])
        n[1] += (p[2] - q[2]) * (p[0] + q[0])
        n[2] += (p[0] - q[0]) * (p[1] + q[1])
    return n


# ================================================================ colour
def rgb(c):
    """'#rrggbb' or 0xrrggbb -> sRGB floats."""
    if isinstance(c, str):
        return tuple(int(c[i:i + 2], 16) / 255.0 for i in (1, 3, 5))
    return (((c >> 16) & 255) / 255.0, ((c >> 8) & 255) / 255.0, (c & 255) / 255.0)


def hexs(c):
    return '#%02x%02x%02x' % tuple(int(round(clamp(v, 0, 1) * 255)) for v in c)


def mix(a, b, t):
    """Blend two colours (sRGB, as a canvas would) -> '#rrggbb'."""
    a, b = rgb(a), rgb(b)
    return hexs(tuple(a[i] + (b[i] - a[i]) * t for i in range(3)))


def scale(c, k):
    return hexs(tuple(v * k for v in rgb(c)))


def mul(a, b):
    """Multiply two colours (a tinted texture, as three.js's `color` × `map`)."""
    a, b = rgb(a), rgb(b)
    return hexs(tuple(a[i] * b[i] for i in range(3)))


def linear(c):
    return tuple(v / 12.92 if v <= 0.04045 else ((v + 0.055) / 1.055) ** 2.4 for v in rgb(c))


def srgb(lin):
    return tuple(12.92 * v if v <= 0.0031308 else 1.055 * v ** (1 / 2.4) - 0.055 for v in lin)


def lit(albedo, light, n=(0.0, 1.0, 0.0)):
    """What ADR 0006's shading makes of an albedo facing n, under the prototype's light (its
    intensities over π, as three.js r170) — for unlit things that must sit on lit ground."""
    k = 1 / math.pi
    t = 0.5 + 0.5 * n[1]
    sky, gnd, sun = linear(light['hemi_sky']), linear(light['hemi_ground']), linear(light['sun'])
    ld = _norm(light['sun_pos'])
    s = max(0.0, _dot(_norm(n), ld)) * light['sun_i'] * k
    a = linear(albedo)
    return hexs(srgb(tuple(a[i] * ((gnd[i] + (sky[i] - gnd[i]) * t) * light['hemi'] * k + sun[i] * s) for i in range(3))))


def add(base, colour, amount):
    """Additive blending as the prototype's glow sprites did it (in sRGB, onto the lit ground)."""
    a, b = rgb(base), rgb(colour)
    return hexs(tuple(a[i] + b[i] * amount for i in range(3)))


def tone(a, b, t, steps=4):
    """A blend of two colours snapped to `steps` levels, so gradients stay a few swatches."""
    return mix(a, b, round(clamp(t, 0, 1) * (steps - 1)) / (steps - 1))


def gradient(stops, t):
    """CSS-style stops [(t, colour)] -> sRGB floats at t."""
    if t <= stops[0][0]:
        return rgb(stops[0][1])
    for (t0, c0), (t1, c1) in zip(stops, stops[1:]):
        if t <= t1:
            k = (t - t0) / (t1 - t0) if t1 > t0 else 0.0
            a, b = rgb(c0), rgb(c1)
            return tuple(a[i] + (b[i] - a[i]) * k for i in range(3))
    return rgb(stops[-1][1])


# ================================================================ the palette
class Palette:
    """Swatches (left half, 16 x 32) and the sky's lat-long map (right half).

    A colour is named by its hex string ('#6b4527'); the first use adds the swatch, so the order
    — and the texture — follow the build's (deterministic) order. `sky` is a function
    (azimuth radians, elevation radians) -> sRGB floats, painted per pixel of the right half."""

    def __init__(self, sky):
        self.names = []
        self.sky = sky

    def uv(self, colour):
        c = colour.lower()
        if c not in self.names:
            if len(self.names) >= COLS * ROWS:
                raise RuntimeError(f'palette full ({COLS * ROWS} swatches) adding {c}')
            self.names.append(c)
        i = self.names.index(c)
        cx, cy = i % COLS, i // COLS
        return ((cx + 0.5) / (2 * COLS), 1.0 - (cy + 0.5) / ROWS)

    @staticmethod
    def sky_uv(az, el):
        """UV of a direction in the sky map (az in [0, 2π], el in [-π/2, π/2])."""
        half = TEX // 2
        u = (half + 0.5 + (az / (2 * math.pi)) * (half - 1)) / TEX
        v = (0.5 + ((el + math.pi / 2) / math.pi) * (TEX - 1)) / TEX
        return (u, v)

    def save(self, path):
        img = bpy.data.images.new('palette', TEX, TEX, alpha=False)
        px = [0.0] * (TEX * TEX * 4)
        cw, ch = TEX // 2 // COLS, TEX // ROWS
        cols = [rgb(n) for n in self.names]
        half = TEX // 2
        for y in range(TEX):
            el = clamp((y / (TEX - 1)) * math.pi - math.pi / 2, -math.pi / 2, math.pi / 2)
            for x in range(TEX):
                if x < half:
                    i = ((TEX - 1 - y) // ch) * COLS + x // cw
                    c = cols[i] if i < len(cols) else (0.5, 0.5, 0.5)
                else:
                    az = ((x - half) / (half - 1)) * 2 * math.pi
                    c = self.sky(az, el)
                o = (y * TEX + x) * 4
                px[o:o + 4] = [c[0], c[1], c[2], 1.0]
        img.pixels = px
        img.filepath_raw = path
        img.file_format = 'PNG'
        img.save()
        return img


def css_sky(stops, horizon=0.55, top_el=35.0, below=15.0):
    """The prototype's page gradient as a dome: CSS 0 % at `top_el` degrees above the horizon
    (the top of a goal-camera frame), `horizon` at the horizon, 100 % `below` degrees under it —
    where the page gradient sat behind the prototype's scenery."""
    def f(az, el):
        e = math.degrees(el)
        if e >= 0:
            t = horizon * (1 - min(1.0, e / top_el))
        else:
            t = horizon + (1 - horizon) * min(1.0, -e / below)
        return gradient(stops, t)
    return f


# ================================================================ the mesh builder
class Mesh:
    """Flat faces, each one palette swatch, accumulated into one bmesh (game coordinates)."""

    def __init__(self, pal):
        self.pal = pal
        self.bm = bmesh.new()
        self.uvl = self.bm.loops.layers.uv.new('UVMap')
        self.datafn = None                   # effects: point -> (w, p), encoded in the swatch (FxMesh)

    # ---------------------------------------------------------- faces
    def face(self, pts, col, out=None, facing=None, uvs=None):
        """A polygon. `out`: wind it so its normal points away from that point; `facing`: so its
        normal has a positive component along that vector. Degenerate faces are dropped."""
        n = _newell(pts)
        if _dot(n, n) < 1e-14:
            return None
        if out is not None:
            c = tuple(sum(p[k] for p in pts) / len(pts) for k in range(3))
            if _dot(n, _sub(c, out)) < 0:
                pts, uvs = pts[::-1], (uvs[::-1] if uvs else None)
        elif facing is not None:
            if _dot(n, facing) < 0:
                pts, uvs = pts[::-1], (uvs[::-1] if uvs else None)
        f = self.bm.faces.new([self.bm.verts.new((p[0], -p[2], p[1])) for p in pts])
        u = None if uvs else self.pal.uv(col)
        for k, loop in enumerate(f.loops):
            if uvs:
                loop[self.uvl].uv = uvs[k]
            elif self.datafn:
                loop[self.uvl].uv = encode(u, *self.datafn(pts[k]))
            else:
                loop[self.uvl].uv = u
        return f

    def up(self, pts, col):
        return self.face(pts, col, facing=(0, 1, 0))

    def xf(self, M):
        """This mesh seen through a transform: primitives built on the result land here moved by
        M (a set piece authored in its own frame, then placed, tilted, sunk)."""
        return _Xf(self, M)

    # ---------------------------------------------------------- solids
    def cuboid(self, M, col, top=None, bottom=None, sides=None):
        """The unit cube [-.5, .5]^3 through M (game space). `sides`: colour of the four sides."""
        c = [M @ Vector((x, y, z)) for y in (-0.5, 0.5) for z in (-0.5, 0.5) for x in (-0.5, 0.5)]
        mid = M @ Vector((0, 0, 0))
        c = [tuple(v) for v in c]
        s = sides or col
        self.face([c[4], c[5], c[7], c[6]], top or col, out=mid)
        if bottom:
            self.face([c[0], c[1], c[3], c[2]], bottom, out=mid)
        self.face([c[0], c[1], c[5], c[4]], s, out=mid)
        self.face([c[2], c[3], c[7], c[6]], s, out=mid)
        self.face([c[0], c[2], c[6], c[4]], s, out=mid)
        self.face([c[1], c[3], c[7], c[5]], s, out=mid)

    def box(self, x, y, z, sx, sy, sz, col, top=None, bottom=None, yaw=0.0, tilt=0.0, roll=0.0, sides=None):
        """A box standing on (x, y, z): size sx (across) x sy (up) x sz (along)."""
        M = T(x, y, z) @ R(yaw, 'Y') @ R(tilt, 'X') @ R(roll, 'Z') @ S(sx, sy, sz) @ T(0, 0.5, 0)
        self.cuboid(M, col, top, bottom, sides)

    def frustum(self, p0, p1, r0, r1, n, col, cap=None, bottom=None, phase=0.0, col_fn=None, squash=1.0):
        """An n-sided tube from p0 to p1, radius r0 -> r1 (r1 = 0: a cone). `cap`/`bottom`: colour
        of the end discs (None: open). `col_fn(i)`: colour per side. `squash` flattens it along
        one perpendicular (ovals)."""
        d = _norm(_sub(p1, p0))
        ref = (0, 1, 0) if abs(d[1]) < 0.9 else (1, 0, 0)
        u = _norm(_cross(d, ref))
        v = _cross(d, u)
        ang = [phase + 2 * math.pi * i / n for i in range(n)]

        def ring(p, r):
            return [tuple(p[k] + r * (math.cos(a) * u[k] + math.sin(a) * v[k] * squash) for k in range(3)) for a in ang]
        A = ring(p0, r0)
        for i in range(n):
            j = (i + 1) % n
            c = col_fn(i) if col_fn else col
            if r1 <= 1e-6:
                self.face([A[i], A[j], p1], c, out=p0)
            else:
                B = ring(p1, r1)
                mid = tuple((p0[k] + p1[k]) / 2 for k in range(3))
                if r0 <= 1e-6:
                    self.face([p0, B[j], B[i]], c, out=p1)
                else:
                    self.face([A[i], A[j], B[j], B[i]], c, out=mid)
        if cap and r1 > 1e-6:
            self.face(ring(p1, r1), cap, facing=d)
        if bottom and r0 > 1e-6:
            self.face(ring(p0, r0), bottom, facing=(-d[0], -d[1], -d[2]))

    def bar(self, p0, p1, w, col):
        """A thin square rod (nets, rails, ropes) — four sides, no ends."""
        self.frustum(p0, p1, w * 0.7071, w * 0.7071, 4, col, phase=math.pi / 4)

    def tube(self, pts, r, n, col, r_end=None, col_fn=None):
        """A chain of frusta through a polyline; radius tapers to r_end."""
        r_end = r if r_end is None else r_end
        m = len(pts) - 1
        for k in range(m):
            ra, rb = lerp(r, r_end, k / m), lerp(r, r_end, (k + 1) / m)
            self.frustum(pts[k], pts[k + 1], ra, rb, n, col_fn(k) if col_fn else col)

    def blob(self, c, r, cols, scale=(1, 1, 1), level=1, jitter=0.12, rng=None, yaw=0.0, cut=None, band_noise=0.0):
        """A jittered icosphere. `cols`: one colour, or a list banded bottom -> top by the face's
        local height (the prototype's canopy / rock gradients). `cut` drops faces whose centre
        lies below that local height (a flat-bottomed dome)."""
        verts, faces = _icosphere(level)
        P = []
        for vx, vy, vz in verts:
            k = 1 + (rng.uniform(-jitter, jitter) if rng else 0.0)
            q = (vx * r * scale[0] * k, vy * r * scale[1] * k, vz * r * scale[2] * k)
            if yaw:
                cy, sy = math.cos(yaw), math.sin(yaw)
                q = (q[0] * cy + q[2] * sy, q[1], -q[0] * sy + q[2] * cy)
            P.append((c[0] + q[0], c[1] + q[1], c[2] + q[2]))
        for f in faces:
            hy = sum(verts[i][1] for i in f) / 3
            if cut is not None and hy < cut:
                continue
            if isinstance(cols, str):
                col = cols
            else:
                fc = tuple(sum(P[i][k] for i in f) / 3 for k in range(3))
                t = (hy + 1) / 2 + band_noise * math.sin(fc[0] * 2.1 + fc[2] * 1.7) * math.cos(fc[1] * 2.3)
                col = cols[clamp(int(t * len(cols)), 0, len(cols) - 1)]
            self.face([P[i] for i in f], col, out=c)

    def lathe(self, c, profile, n, cols, phase=0.0, sx=1.0, sz=1.0):
        """Revolve a (radius, height) profile about the vertical through c; colours per band."""
        rings = [[(c[0] + r * sx * math.cos(phase + 2 * math.pi * i / n), c[1] + h,
                   c[2] + r * sz * math.sin(phase + 2 * math.pi * i / n)) for i in range(n)] for r, h in profile]
        centre = (c[0], c[1] + sum(h for _, h in profile) / len(profile), c[2])
        for k in range(len(profile) - 1):
            col = cols[min(k, len(cols) - 1)] if not isinstance(cols, str) else cols
            A, B = rings[k], rings[k + 1]
            for i in range(n):
                j = (i + 1) % n
                if profile[k][0] < 1e-6:
                    self.face([(c[0], c[1] + profile[k][1], c[2]), B[j], B[i]], col, out=centre)
                elif profile[k + 1][0] < 1e-6:
                    self.face([A[i], A[j], (c[0], c[1] + profile[k + 1][1], c[2])], col, out=centre)
                else:
                    self.face([A[i], A[j], B[j], B[i]], col, out=centre)

    def octa(self, c, r, h, col, yaw=0.0, tilt=0.0, roll=0.0, lower=None, top_col=None):
        """A double pyramid (crystals, fireflies, gems): half-width r, half-height h (the lower
        half `lower` long)."""
        lower = h if lower is None else lower
        M = T(*c) @ R(yaw, 'Y') @ R(tilt, 'X') @ R(roll, 'Z')
        eq = [tuple(M @ Vector((r * math.cos(a), 0, r * math.sin(a)))) for a in (0, math.pi / 2, math.pi, 1.5 * math.pi)]
        top, bot = tuple(M @ Vector((0, h, 0))), tuple(M @ Vector((0, -lower, 0)))
        for i in range(4):
            a, b = eq[i], eq[(i + 1) % 4]
            self.face([a, b, top], top_col or col, out=c)
            self.face([b, a, bot], col, out=c)

    def disc(self, x, y, z, r, n, col, rz=None, phase=0.0):
        rz = r if rz is None else rz
        self.up([(x + r * math.cos(phase + 2 * math.pi * i / n), y, z + rz * math.sin(phase + 2 * math.pi * i / n)) for i in range(n)], col)

    def annulus(self, x, y, z, r0, r1, n, col, a0=0.0, a1=2 * math.pi, dashed=None):
        """A flat ring (or arc of one) — painted circles, halos. `dashed`: dash length."""
        steps = n
        if dashed:                           # pieces well under a dash, so the dashes stay even
            steps = max(n, math.ceil(abs(a1 - a0) * (r0 + r1) / 2 / (dashed / 3)))
        for i in range(steps):
            t0, t1 = a0 + (a1 - a0) * i / steps, a0 + (a1 - a0) * (i + 1) / steps
            if dashed and int(((t0 + t1) / 2 - a0) * (r0 + r1) / 2 / dashed) % 2:
                continue
            p = lambda t, rr: (x + rr * math.cos(t), y, z + rr * math.sin(t))
            self.up([p(t0, r0), p(t1, r0), p(t1, r1), p(t0, r1)], col)

    def strip(self, pts, w, y, col, dashed=None, facing=(0, 1, 0)):
        """A flat band of width w along a polyline in the xz plane (painted lines, streams)."""
        if dashed:                           # resample so every piece is a fraction of a dash
            fine = [pts[0]]
            for (ax, az), (bx, bz) in zip(pts, pts[1:]):
                n = max(1, math.ceil(math.hypot(bx - ax, bz - az) / (dashed / 4)))
                fine += [(ax + (bx - ax) * i / n, az + (bz - az) * i / n) for i in range(1, n + 1)]
            pts = fine
        acc = 0.0
        for k in range(len(pts) - 1):
            (ax, az), (bx, bz) = pts[k], pts[k + 1]
            ln = math.hypot(bx - ax, bz - az)
            if ln < 1e-9:
                continue
            if dashed and int((acc + ln / 2) / dashed) % 2:
                acc += ln
                continue
            acc += ln
            nx, nz = -(bz - az) / ln * w / 2, (bx - ax) / ln * w / 2
            yy = y if not callable(y) else None
            ya = yy if yy is not None else y(ax, az)
            yb = yy if yy is not None else y(bx, bz)
            self.face([(ax - nx, ya, az - nz), (bx - nx, yb, bz - nz), (bx + nx, yb, bz + nz), (ax + nx, ya, az + nz)], col, facing=facing)

    def field(self, xs, zs, h, col_fn, skip=None, warp=None):
        """A heightfield on the grid xs x zs; each cell two triangles, coloured by col_fn(x, y, z,
        normal) at the triangle's centre. `skip(x0, z0, x1, z1)` drops a cell; `warp(x, z)` moves
        a vertex (push_out: keep it off the pitch)."""
        P = [[(warp(x, z) if warp else (x, z)) for x in xs] for z in zs]
        H = [[h(*P[j][i]) for i in range(len(xs))] for j in range(len(zs))]
        V = lambda j, i: (P[j][i][0], H[j][i], P[j][i][1])
        for j in range(len(zs) - 1):
            for i in range(len(xs) - 1):
                x0, x1, z0, z1 = xs[i], xs[i + 1], zs[j], zs[j + 1]
                if skip and skip(x0, z0, x1, z1):
                    continue
                a, b, c, d = V(j, i), V(j, i + 1), V(j + 1, i + 1), V(j + 1, i)
                for tri in (((a, b, c) if (i + j) % 2 else (a, b, d)), ((a, c, d) if (i + j) % 2 else (b, c, d))):
                    n = _norm(_newell(list(tri)))
                    if n[1] < 0:
                        n = (-n[0], -n[1], -n[2])
                    cx, cy, cz = (sum(p[k] for p in tri) / 3 for k in range(3))
                    self.face(list(tri), col_fn(cx, cy, cz, n), facing=(0, 1, 0))

    def polar(self, radii, n, h, col_fn, skip=None, offset=0.0, warp=None):
        """A heightfield on polar rings (dense near, sparse far) — same colouring as `field`.
        `warp(x, z)` moves a vertex (push_out: keep it off the pitch)."""
        pts = [[(r * math.sin(2 * math.pi * (a + (k % 2) * 0.5 + offset) / n), r * math.cos(2 * math.pi * (a + (k % 2) * 0.5 + offset) / n))
                for a in range(n)] for k, r in enumerate(radii)]
        if warp:
            pts = [[warp(x, z) for x, z in ring] for ring in pts]
        H = [[h(x, z) for x, z in ring] for ring in pts]
        for k in range(len(radii) - 1):
            for a in range(n):
                b = (a + 1) % n
                A, B = pts[k], pts[k + 1]
                p = lambda kk, aa: (pts[kk][aa][0], H[kk][aa], pts[kk][aa][1])
                if k % 2 == 0:
                    tris = ((p(k, a), p(k + 1, a), p(k, b)), (p(k, b), p(k + 1, a), p(k + 1, b)))
                else:
                    tris = ((p(k, a), p(k + 1, b), p(k, b)), (p(k, a), p(k + 1, a), p(k + 1, b)))
                for tri in tris:
                    cx, cy, cz = (sum(q[i] for q in tri) / 3 for i in range(3))
                    if skip and skip(cx, cz, radii[k]):
                        continue
                    nn = _norm(_newell(list(tri)))
                    if nn[1] < 0:
                        nn = (-nn[0], -nn[1], -nn[2])
                    self.face(list(tri), col_fn(cx, cy, cz, nn), facing=(0, 1, 0))

    def ring_band(self, off0, off1, y0, y1, corner, col, top=None, per=6, inner=True, outer=True, bottom=None):
        """A band on the rounded boundary between offsets off0 < off1 outside it (the boards, the
        rail, the rim): inner and outer walls and a top."""
        A, B = _rr_ring(off0, corner, per), _rr_ring(off1, corner, per)
        for i in range(len(A)):
            j = (i + 1) % len(A)
            (ax, az, anx, anz), (bx, bz, bnx, bnz) = A[i], A[j]
            (cx, cz, cnx, cnz), (dx, dz, dnx, dnz) = B[i], B[j]
            nrm = ((anx + bnx) / 2, 0.0, (anz + bnz) / 2)
            if inner and y1 > y0:
                self.face([(ax, y0, az), (bx, y0, bz), (bx, y1, bz), (ax, y1, az)], col, facing=(-nrm[0], 0, -nrm[2]))
            if outer and y1 > y0:
                self.face([(cx, y0, cz), (dx, y0, dz), (dx, y1, dz), (cx, y1, cz)], col, facing=nrm)
            if top is not False:
                self.face([(ax, y1, az), (bx, y1, bz), (dx, y1, dz), (cx, y1, cz)], top or col, facing=(0, 1, 0))
            if bottom:
                self.face([(ax, y0, az), (bx, y0, bz), (dx, y0, dz), (cx, y0, cz)], bottom, facing=(0, -1, 0))

    # ---------------------------------------------------------- out
    def to_object(self, name, material):
        bmesh.ops.remove_doubles(self.bm, verts=self.bm.verts, dist=1e-5)
        bmesh.ops.triangulate(self.bm, faces=self.bm.faces, quad_method='BEAUTY', ngon_method='BEAUTY')
        mesh = bpy.data.meshes.new(name)
        self.bm.to_mesh(mesh)
        self.bm.free()
        mesh.materials.append(material)
        for p in mesh.polygons:
            p.use_smooth = False
        obj = bpy.data.objects.new(name, mesh)
        bpy.context.scene.collection.objects.link(obj)
        return obj


class _Xf(Mesh):
    def __init__(self, base, M):
        self.base, self.M, self.pal = base, M, base.pal
        self.N = M.to_3x3()

    def face(self, pts, col, out=None, facing=None, uvs=None):
        P = [tuple(self.M @ Vector(p)) for p in pts]
        o = tuple(self.M @ Vector(out)) if out is not None else None
        f = tuple(self.N @ Vector(facing)) if facing is not None else None
        return self.base.face(P, col, out=o, facing=f, uvs=uvs)

    def xf(self, M):
        return _Xf(self.base, self.M @ M)


def euler(x=0.0, y=0.0, z=0.0):
    """three.js's Euler (order XYZ) as a matrix."""
    return R(x, 'X') @ R(y, 'Y') @ R(z, 'Z')


def _rr_ring(off, corner, per):
    """(x, z, nx, nz) around a rounded rectangle `off` outside the boundary; normals outward."""
    hw, hl, r = HW + off, HL + off, max(corner + off, 0.01)
    pts = []
    for (cx, cz, a0) in ((hw - r, hl - r, 0), (-hw + r, hl - r, 90), (-hw + r, -hl + r, 180), (hw - r, -hl + r, 270)):
        for i in range(per + 1):
            a = math.radians(a0 + 90 * i / per)
            pts.append((cx + r * math.cos(a), cz + r * math.sin(a), math.cos(a), math.sin(a)))
    return pts


def rr_points(off, corner, n):
    """n points evenly spaced along the rounded rectangle `off` outside the boundary."""
    ring = _rr_ring(off, corner, 12)
    seg = [(ring[i], ring[(i + 1) % len(ring)]) for i in range(len(ring))]
    total = sum(math.hypot(b[0] - a[0], b[1] - a[1]) for a, b in seg)
    out = []
    for k in range(n):
        s = total * k / n
        for a, b in seg:
            ln = math.hypot(b[0] - a[0], b[1] - a[1])
            if s <= ln and ln > 0:
                t = s / ln
                out.append((a[0] + (b[0] - a[0]) * t, a[1] + (b[1] - a[1]) * t))
                break
            s -= ln
    return out


_PHI = (1 + 5 ** 0.5) / 2
_ICO_V = [(-1, _PHI, 0), (1, _PHI, 0), (-1, -_PHI, 0), (1, -_PHI, 0), (0, -1, _PHI), (0, 1, _PHI),
          (0, -1, -_PHI), (0, 1, -_PHI), (_PHI, 0, -1), (_PHI, 0, 1), (-_PHI, 0, -1), (-_PHI, 0, 1)]
_ICO_F = [(0, 11, 5), (0, 5, 1), (0, 1, 7), (0, 7, 10), (0, 10, 11), (1, 5, 9), (5, 11, 4), (11, 10, 2),
          (10, 7, 6), (7, 1, 8), (3, 9, 4), (3, 4, 2), (3, 2, 6), (3, 6, 8), (3, 8, 9), (4, 9, 5),
          (2, 4, 11), (6, 2, 10), (8, 6, 7), (9, 8, 1)]
_ICO = {}


def _icosphere(level):
    if level not in _ICO:
        verts = [_norm(v) for v in _ICO_V]
        faces = list(_ICO_F)
        for _ in range(level):
            cache, nf = {}, []

            def mid(a, b):
                key = (min(a, b), max(a, b))
                if key not in cache:
                    verts.append(_norm(tuple((verts[a][k] + verts[b][k]) / 2 for k in range(3))))
                    cache[key] = len(verts) - 1
                return cache[key]
            for a, b, c in faces:
                ab, bc, ca = mid(a, b), mid(b, c), mid(c, a)
                nf += [(a, ab, ca), (b, bc, ab), (c, ca, bc), (ab, bc, ca)]
            faces = nf
        _ICO[level] = (verts, faces)
    return _ICO[level]


# ================================================================ the rink (render.js's)
def rink(turf, scen, sport, surface, border, goal, decorate=None, rng=None, skirt=-1.0):
    """The pitch and everything on its boundary, as the prototype builds it: the surface painted
    as its canvas is (field: 12 mowing bands, the outline, centre and 23 m lines, shooting
    circles; ice: skating marks, red and blue lines, face-off circles, creases), the boards with
    their coloured rail (ice: a glass frame above them), the rim the pitch stands on, the goals.

    surface: base, stripe, lines (colours) — and optionally `paint`: (fn(x, z, band colour) ->
    colour, cell size), the surface painted cell by cell (edge haze, glows); border: color, top, height, glass, base; goal:
    post (the frame alone — the apps draw the net, ADR 0008). `decorate(turf, paint)` adds a world's own paint before the markings. `skirt`: how far
    the rim's outer face reaches down (the ground meets it)."""
    corner = CORNER[sport]
    per = 8 if sport == 'field' else 12
    base, stripe = surface['base'], surface.get('stripe', surface['base'])
    # ---- the surface, clipped to the rounded boundary
    arc_z = sorted({s * (HL - corner + corner * math.sin(math.pi / 2 * k / per)) for k in range(per + 1) for s in (-1, 1)})
    bands = 12 if sport == 'field' else 1
    cell = surface.get('paint')              # a world painting its surface cell by cell
    for i in range(bands):
        z0, z1 = -HL + 2 * HL * i / bands, -HL + 2 * HL * (i + 1) / bands
        band = stripe if (sport == 'field' and i % 2 == 0) else base
        if not cell:
            zs = [z0] + [z for z in arc_z if z0 < z < z1] + [z1]
            right = [(half_width(z, corner), 0.0, z) for z in zs]
            left = [(-half_width(z, corner), 0.0, z) for z in reversed(zs)]
            turf.up(right + left, band)
            continue
        nz = max(1, round((z1 - z0) / cell[1]))
        for j in range(nz):
            za, zb = z0 + (z1 - z0) * j / nz, z0 + (z1 - z0) * (j + 1) / nz
            nx = round(2 * HW / cell[1])
            run = None                           # plain cells of one colour merge into a run

            def flush(run):
                if run:
                    c, xa_, xb_ = run
                    turf.up([(xa_, 0.0, za), (xb_, 0.0, za), (xb_, 0.0, zb), (xa_, 0.0, zb)], c)
            for k in range(nx):
                xa, xb = -HW + 2 * HW * k / nx, -HW + 2 * HW * (k + 1) / nx
                c = cell[0]((xa + xb) / 2, (za + zb) / 2, band)
                plain = all(-half_width(z, corner) <= xa and xb <= half_width(z, corner) for z in (za, zb)) and \
                    not any(za < z < zb for z in arc_z)
                if plain:
                    if run and run[0] == c:
                        run = (c, run[1], xb)
                    else:
                        flush(run)
                        run = (c, xa, xb)
                    continue
                flush(run)
                run = None
                cuts = set()
                for xv in (abs(xa), abs(xb)):        # where the corner arc crosses the cell's sides
                    if xv > HW - corner:
                        d = math.sqrt(max(corner * corner - (xv - (HW - corner)) ** 2, 0.0))
                        cuts |= {HL - corner + d, -(HL - corner + d)}
                zs = sorted({za, zb} | {z for z in list(arc_z) + list(cuts) if za < z < zb})
                rows = [(z, max(xa, -half_width(z, corner)), min(xb, half_width(z, corner))) for z in zs]
                rows = [rw for rw in rows if rw[2] > rw[1] - 1e-9]
                if len(rows) < 2:
                    continue
                pts = [(r_, 0.0, z) for z, _, r_ in rows] + [(l_, 0.0, z) for z, l_, _ in reversed(rows)]
                pts = [p for i, p in enumerate(pts) if math.dist(p, pts[i - 1]) > 1e-6]
                if len(pts) >= 3:
                    turf.up(pts, c)
            flush(run)
    paint = Paint(turf, corner)
    if sport == 'ice':
        rng = rng or random.Random(1)
        mark = surface.get('marks', mix('#b4d2eb', base, 0.65))
        for _ in range(70):                                  # skating marks
            x0, z0 = rng.uniform(-HW + 1, HW - 1), rng.uniform(-HL + 1, HL - 1)
            cx, cz = x0 + rng.uniform(-3.5, 3.5), z0 + rng.uniform(-3.5, 3.5)
            x1, z1 = x0 + rng.uniform(-5.8, 5.8), z0 + rng.uniform(-5.8, 5.8)
            pts = []
            for k in range(7):
                t = k / 6
                x = (1 - t) ** 2 * x0 + 2 * (1 - t) * t * cx + t * t * x1
                z = (1 - t) ** 2 * z0 + 2 * (1 - t) * t * cz + t * t * z1
                pts.append((x, z))
            if all(sd_round_rect(x, z, r=corner) < -0.3 for x, z in pts):
                turf.strip(pts, 0.07, DECOR_Y, mark)
    if decorate:
        decorate(turf, paint)
    if sport == 'ice':
        red, blue = surface.get('red', '#ef4444'), surface.get('blue', '#3b82f6')
        crease = surface.get('crease', mix('#60a5fa', base, 0.55))
        for sgn in (-1, 1):                                  # creases, filled then outlined
            gz = sgn * GOAL_Z
            n = 16
            pts = [(CREASE_R * math.cos(math.pi * k / n), 0, gz - sgn * CREASE_R * math.sin(math.pi * k / n)) for k in range(n + 1)]
            turf.up([(x, DECOR_Y, z) for x, _, z in pts], crease)
            paint.arc(0, gz, CREASE_R, 0.176, 0, math.pi, n, red, flip=-sgn)
        paint.hline(-GOAL_Z, 0.176, red)
        paint.hline(GOAL_Z, 0.176, red)
        paint.hline(-LINE_Z, 0.41, blue)
        paint.hline(LINE_Z, 0.41, blue)
        paint.hline(0, 0.35, red)
        paint.circle(0, 0, FACEOFF_R, 0.234, blue)
        paint.dot(0, 0, 0.45, blue)
        for x, z in END_SPOTS:
            paint.circle(x, z, FACEOFF_R, 0.234, red)
            paint.dot(x, z, 0.45, red)
        for x, z in NEUTRAL_SPOTS:
            paint.dot(x, z, 0.45, red)
    else:
        lines, w = surface['lines'], 0.205
        paint.outline(0.6, w, lines)
        for z in (0.0, -LINE_Z, LINE_Z, -GOAL_Z, GOAL_Z):
            paint.hline(z, w, lines)
        paint.dot(0, 0, 0.35, lines)
        for sgn in (-1, 1):
            gz = sgn * GOAL_Z
            half = GOAL_W / 2
            for rr, ww, dash in ((D_R, w, None), (D_R + 3, 0.117, 0.762)):
                paint.line([(-half, gz - sgn * rr), (half, gz - sgn * rr)], ww, lines, dashed=dash)
                for s in (-1, 1):                            # quarter arcs round each post
                    paint.arc(s * half, gz, rr, ww, 0, math.pi / 2, 12, lines, quadrant=(s, -sgn), dashed=dash)
            paint.dot(0, gz - sgn * 6.4, 0.3, lines)
    # ---- the boards, the rail, the glass, the rim
    h = border.get('height', 1.1)
    scen.ring_band(0.0, WALL_T, 0.0, h, corner, border['color'], top=False, per=per)
    scen.ring_band(0.0, WALL_T + 0.02, h, h + 0.12, corner, border['top'], per=per)
    if border.get('glass'):
        # the prototype's glass is an 18 % sheet: here a frame of slim posts and a top rail,
        # so the boards read as glassed without hiding the ice from the high camera
        gh = h + 1.5
        frame = border.get('frame', '#bae6fd')
        scen.ring_band(0.02, 0.36, gh, gh + 0.1, corner, border['top'], per=per)
        for x, z in rr_points(0.19, corner, 64):
            scen.bar((x, h + 0.12, z), (x, gh, z), 0.07, frame)
    scen.ring_band(WALL_T, SLAB_W, skirt, 0.0, corner, border['base'], per=per, inner=False)
    # ---- the goals
    for sgn in (-1, 1):
        goal_frame(scen, sgn, goal['post'])
    return paint


def goal_frame(m, sgn, post):
    """render.js's goal, its rigid half: two posts and a crossbar. The net laced to them is **not**
    in the asset (ADR 0008) — both apps draw and move the whole net themselves (spec §8.8), because a
    goal's ripple answers a moment in the match and nothing baked into a world can. What stayed here
    is what never moves; the net's cords take the world's own colour (teams.toml [[world]] `net`)."""
    gz = sgn * GOAL_Z
    hw, h = GOAL_W / 2, GOAL_H
    for sx in (-1, 1):
        m.frustum((sx * hw, 0, gz), (sx * hw, h, gz), 0.13, 0.13, 10, post, cap=post)
    m.frustum((-hw - 0.13, h, gz), (hw + 0.13, h, gz), 0.12, 0.12, 10, post, cap=post, bottom=post)


class Paint:
    """Painting on the pitch surface (render.js's makeSurfaceTexture): flat bands at LINE_Y."""

    def __init__(self, turf, corner):
        self.m, self.corner = turf, corner

    def hline(self, z, w, col, y=LINE_Y):
        hw = min(half_width(z - w / 2, self.corner), half_width(z + w / 2, self.corner)) - 0.01
        self.m.up([(-hw, y, z - w / 2), (hw, y, z - w / 2), (hw, y, z + w / 2), (-hw, y, z + w / 2)], col)

    def line(self, pts, w, col, dashed=None, y=LINE_Y):
        self.m.strip(pts, w, y, col, dashed=dashed)

    def _clipped(self, pts, w, y, col, dashed):
        """A painted path, dropped where it would leave the pitch (the canvas edge clipped it)."""
        run = []
        for p in pts + [None]:
            if p is not None and sd_round_rect(p[0], p[1], r=self.corner) < -w / 2 - 0.02:
                run.append(p)
                continue
            if len(run) > 1:
                self.m.strip(run, w, y, col, dashed=dashed)
            run = []

    def outline(self, inset, w, col, y=LINE_Y):
        a, b = HW - inset, HL - inset
        h = w / 2
        for z in (-b, b):
            self.m.up([(-a - h, y, z - h), (a + h, y, z - h), (a + h, y, z + h), (-a - h, y, z + h)], col)
        for x in (-a, a):
            self.m.up([(x - h, y, -b + h), (x + h, y, -b + h), (x + h, y, b - h), (x - h, y, b - h)], col)

    def circle(self, x, z, r, w, col, n=40, y=LINE_Y):
        self.m.annulus(x, y, z, r - w / 2, r + w / 2, n, col)

    def arc(self, x, z, r, w, a0, a1, n, col, quadrant=None, flip=None, dashed=None, y=LINE_Y):
        """An arc of a painted circle. `quadrant=(sx, sz)`: the quarter from (x + sx·r, z) round
        to (x, z + sz·r); `flip`: the half on the side sz of z (creases)."""
        pts = []
        for k in range(n + 1):
            t = a0 + (a1 - a0) * k / n
            if quadrant:
                sx, sz = quadrant
                pts.append((x + sx * r * math.cos(t), z + sz * r * math.sin(t)))
            elif flip:
                pts.append((x + r * math.cos(t), z + flip * r * math.sin(t)))
            else:
                pts.append((x + r * math.cos(t), z + r * math.sin(t)))
        self._clipped(pts, w, y, col, dashed)

    def dot(self, x, z, r, col, n=14, y=LINE_Y):
        self.m.disc(x, y, z, r, n, col)

    def dab(self, x, z, r, col, n=6, phase=0.0, rz=None):
        """Decoration below the markings (clover, flowers, wear, shells)."""
        self.m.disc(x, DECOR_Y, z, r, n, col, rz=rz, phase=phase)


# ================================================================ the sky dome
def sky_dome(m, rings=None, seg=32):
    """An inside-out dome of radius SKY_R, built face by face so its index order is fixed; its UVs
    are each vertex's direction in the palette's sky map."""
    els = rings or [-90, -40, -20, -8, 0, 4, 9, 15, 22, 30, 40, 52, 66, 80, 90]
    for k in range(len(els) - 1):
        e0, e1 = math.radians(els[k]), math.radians(els[k + 1])
        for s in range(seg):
            a0, a1 = 2 * math.pi * s / seg, 2 * math.pi * (s + 1) / seg
            am = (a0 + a1) / 2

            def p(a, e):
                return (SKY_R * math.cos(e) * math.sin(a), SKY_R * math.sin(e), SKY_R * math.cos(e) * math.cos(a))
            quad = [(a0, e0), (a1, e0), (a1, e1), (a0, e1)]
            if els[k] == -90:
                quad = [(am, e0), (a1, e1), (a0, e1)]
            elif els[k + 1] == 90:
                quad = [(a0, e0), (a1, e0), (am, e1)]
            pts = [p(a, e) for a, e in quad]
            uvs = [Palette.sky_uv(a, e) for a, e in quad]
            m.face(pts, None, facing=_neg(_centroid(pts)), uvs=uvs)      # seen from inside


def _centroid(pts):
    return tuple(sum(p[k] for p in pts) / len(pts) for k in range(3))


def _neg(v):
    return (-v[0], -v[1], -v[2])


def sky_dir(az_deg, el_deg, r=SKY_R * 0.97):
    """A point on (just inside) the dome, azimuth measured from +Z towards +X."""
    a, e = math.radians(az_deg), math.radians(el_deg)
    return (r * math.cos(e) * math.sin(a), r * math.sin(e), r * math.cos(e) * math.cos(a))


def billboard(m, c, size, col, n=6, towards=(0, 20, 0), phase=0.0):
    """A flat polygon at c facing a point (stars, a sun disc) — part of the unlit sky."""
    d = _norm(_sub(towards, c))
    ref = (0, 1, 0) if abs(d[1]) < 0.9 else (1, 0, 0)
    u = _norm(_cross(d, ref))
    v = _cross(d, u)
    pts = [tuple(c[k] + size * (math.cos(phase + 2 * math.pi * i / n) * u[k] + math.sin(phase + 2 * math.pi * i / n) * v[k]) for k in range(3)) for i in range(n)]
    m.face(pts, col, facing=d)


# ================================================================ effects (ADR 0007)
# What moves is declared in shared/data/effects.toml; a world script fills one FxMesh per declared
# effect. A vertex's motion data — w (a weight, an orbit speed factor, a falloff, a sprite corner)
# and p (a phase, a sprite corner) in [0, 1] — rides inside its palette swatch: the UV sits at
# (0.05 + 0.9·w, 0.05 + 0.9·p) of the swatch's cell instead of its centre. Nearest sampling still
# reads the swatch's colour; the apps' shaders read the data back as fract(u·32), fract((1 − v)·32).
# Position, normal and one UV set are all a vertex needs, and both exporters keep those.
_FX_DECL = None


def effects_declared():
    global _FX_DECL
    if _FX_DECL is None:
        from pathlib import Path
        from datagen import effects as fxdecl
        _FX_DECL = fxdecl.load(Path(__file__).resolve().parent.parent / 'shared' / 'data' / 'effects.toml')
    return _FX_DECL


def effects_of(world):
    return [e for e in effects_declared()['effects'] if e['world'] == world]


def encode(uv, w, p):
    """A swatch's UV carrying (w, p) — see above."""
    w, p = clamp(w, 0.0, 1.0), clamp(p, 0.0, 1.0)
    cw, ch = 1.0 / (2 * COLS), 1.0 / ROWS
    u0 = math.floor(uv[0] / cw) * cw
    v1 = 1.0 - math.floor((1.0 - uv[1]) / ch) * ch
    return (u0 + (0.05 + 0.9 * w) * cw, v1 - (0.05 + 0.9 * p) * ch)


def decode(uv):
    return ((math.modf(uv[0] * 2 * COLS)[0] - 0.05) / 0.9, (math.modf((1.0 - uv[1]) * ROWS)[0] - 0.05) / 0.9)


class FxMesh(Mesh):
    """One declared effect's mesh (`fx_<id>`). Geometry is added as usual, inside `piece(data)`:
    data is (w, p) or a function of the vertex (game coordinates) returning it."""

    def __init__(self, pal, spec, seed):
        super().__init__(pal)
        self.spec = spec
        self.rng = random.Random(seed)       # the effect's own layout seed
        self.datafn = lambda pt: (1.0, 0.0)

    def piece(self, data):
        mesh = self

        class _Piece:
            def __enter__(self):
                self.prev = mesh.datafn
                mesh.datafn = data if callable(data) else (lambda pt: data)
                return mesh

            def __exit__(self, *a):
                mesh.datafn = self.prev
        return _Piece()

    def halo(self, c, r, col, p=0.0, n=12, normal=(0, 1, 0), r2=None, yaw=0.0):
        """A soft disc (glow pool, halo, puff): a fan whose centre carries w = 1 and rim w = 0 —
        the soft shading's falloff. `r2`: the other radius (an ellipse); `yaw` turns it about the normal."""
        d = _norm(normal)
        ref = (0, 1, 0) if abs(d[1]) < 0.9 else (1, 0, 0)
        u = _norm(_cross(ref, d)) if abs(d[1]) < 0.9 else (1.0, 0.0, 0.0)
        v = _cross(d, u)
        r2 = r if r2 is None else r2
        rim = [tuple(c[k] + r * math.cos(yaw + 2 * math.pi * i / n) * u[k] + r2 * math.sin(yaw + 2 * math.pi * i / n) * v[k]
                     for k in range(3)) for i in range(n)]
        centre = tuple(c)
        with self.piece(lambda pt: (1.0 if pt == centre else 0.0, p)):
            for i in range(n):
                self.face([centre, rim[i], rim[(i + 1) % n]], col, facing=d)

    def particle(self, c, col):
        """One sprite, baked as a flat quad of the declared half-size round its spawn point; the
        shader recovers the point from the corner (w, p) and turns the quad to the camera."""
        h = self.spec['size']
        x, y, z = c
        with self.piece(lambda pt: (1.0 if pt[0] > x else 0.0, 1.0 if pt[2] > z else 0.0)):
            self.face([(x - h, y, z - h), (x + h, y, z - h), (x + h, y, z + h), (x - h, y, z + h)], col, facing=(0, 1, 0))


class Fx:
    """The effects a world script fills: fx['caps'] is the FxMesh of the declared effect `caps`."""

    def __init__(self, world, pal):
        self.world, self.pal = world, pal
        self.specs = {e['id']: e for e in effects_of(world)}
        self.meshes = {}

    def __getitem__(self, ident):
        if ident not in self.specs:
            raise RuntimeError(f'{self.world}: effect {ident!r} is not declared in shared/data/effects.toml')
        if ident not in self.meshes:
            seed = sum(ord(ch) * 131 ** k for k, ch in enumerate(f'{self.world}/{ident}')) & 0x7fffffff
            self.meshes[ident] = FxMesh(self.pal, self.specs[ident], seed)
        return self.meshes[ident]


def _orbit(x, y, z, spec, theta):
    px, _, pz = spec['pivot']
    e = spec['ellipse']
    dx, qz = x - px, (z - pz) / e
    c, s = math.cos(theta), math.sin(theta)
    return px + dx * c - qz * s, y, pz + (dx * s + qz * c) * e


def check_effect(obj, spec, sport):
    """The pitch contract for an effect, wherever its motion takes it (ADR 0007): an orbit is
    checked all the way round, a sway at its full reach, particles along their travel."""
    corner = CORNER[sport]
    bad = []
    reach = max(abs(spec['sway'][0]), abs(spec['sway'][2]))
    uvl = obj.data.uv_layers[0].data if obj.data.uv_layers else None
    pts = [(v.co.x, v.co.z, -v.co.y) for v in obj.data.vertices]
    if spec['shading'] == 'particles':
        if spec['over_pitch']:
            return
        h = spec['size']
        centres = {}
        for poly in obj.data.polygons:                    # a sprite's corners recover its spawn point
            for li in poly.loop_indices:
                x, y, z = pts[obj.data.loops[li].vertex_index]
                w, p = decode(uvl[li].uv)
                centres[(round(x - (2 * round(w) - 1) * h, 3), round(y, 3), round(z - (2 * round(p) - 1) * h, 3))] = 1
        t = spec['travel']
        ln = math.sqrt(_dot(t, t))
        path = [(t[0] / ln * spec['wrap'] * f, t[1] / ln * spec['wrap'] * f, t[2] / ln * spec['wrap'] * f)
                for f in (0.0, 0.25, 0.5, 0.75, 1.0)] if ln > 0 else [(0.0, 0.0, 0.0)]
        samples = [(cx + o[0], cy + o[1], cz + o[2]) for cx, cy, cz in centres for o in path]
        reach = 0.0
    elif spec['motion'] == 'orbit':
        samples = [_orbit(x, y, z, spec, 2 * math.pi * k / 32) for x, y, z in pts for k in range(32)]
    else:
        samples = pts
    for x, y, z in samples:
        if y < -0.05 or y > 40:
            continue
        if sd_round_rect(x, z, r=corner) < reach - 0.01:
            in_goal = abs(x) <= GOAL_W / 2 + 0.2 and GOAL_Z - 0.2 <= abs(z) <= GOAL_Z + GOAL_D + 0.1 and y <= GOAL_H + 0.2
            if not in_goal:
                bad.append(f'({x:.2f}, {y:.2f}, {z:.2f})')
    if bad:
        raise RuntimeError(f'{obj.name}: {len(bad)} positions inside the pitch boundary: ' + ', '.join(bad[:6]))


# ================================================================ materials, checks, export
def make_material(name, img):
    m = bpy.data.materials.new(name)
    try:
        m.use_nodes = True
    except Exception:
        pass
    nt = m.node_tree
    bsdf = next(n for n in nt.nodes if n.type == 'BSDF_PRINCIPLED')
    bsdf.inputs['Roughness'].default_value = 1.0
    tex = nt.nodes.new('ShaderNodeTexImage')
    tex.image = img
    tex.interpolation = 'Closest'
    nt.links.new(tex.outputs['Color'], bsdf.inputs['Base Color'])
    return m


def tri_count(obj):
    return sum(len(p.vertices) - 2 for p in obj.data.polygons)


def check_contract(objs, sport):
    """Nothing inside the boundary but the surface, its markings and the goals (spec §1): no
    vertex over the pitch at or above its level, bar the goals'."""
    corner = CORNER[sport]
    bad = []
    for o in objs:
        if o.name == 'turf':
            continue
        for v in o.data.vertices:
            x, z, y = v.co.x, -v.co.y, v.co.z
            if y < -0.05 or y > 40:          # under the pitch (a hull, a keel) or the dome's pole
                continue
            if sd_round_rect(x, z, r=corner) < -0.01:
                in_goal = abs(x) <= GOAL_W / 2 + 0.2 and GOAL_Z - 0.2 <= abs(z) <= GOAL_Z + GOAL_D + 0.1 and y <= GOAL_H + 0.2
                if not in_goal:
                    bad.append(f'{o.name} ({x:.2f}, {y:.2f}, {z:.2f})')
    if bad:
        raise RuntimeError(f'{len(bad)} vertices inside the pitch boundary: ' + ', '.join(bad[:6]))


def run(world, here, pal, sport, build, light, preview_eye=((0, 36, -20), (0, 0, -4))):
    """Builds a world: `build(turf, scenery, sky, fx)` fills the three core meshes (the dome is
    added here) and one FxMesh per effect declared for the world (fx['<id>']); writes palette.png,
    <world>.glb and <world>.usdz next to the script; with `-- --preview` renders preview.png from
    the play camera under ADR 0006's shading, lit by `light` (the prototype's hemisphere and sun:
    hemi_sky, hemi_ground, hemi, sun, sun_i, sun_pos) — effects at rest, soft ones and particles left out."""
    bpy.ops.wm.read_factory_settings(use_empty=True)
    turf, scen, sky = Mesh(pal), Mesh(pal), Mesh(pal)
    fx = Fx(world, pal)
    build(turf, scen, sky, fx)
    sky_dome(sky)
    missing = [i for i in fx.specs if i not in fx.meshes or not fx.meshes[i].bm.faces]
    if missing:
        raise RuntimeError(f'{world}: declared effects without geometry: {missing}')
    img = pal.save(os.path.join(here, 'palette.png'))
    names = ['turf', 'scenery', 'sky'] + [f'fx_{i}' for i in fx.specs]
    mats = {n: make_material(n, img) for n in names}
    objs = [turf.to_object('turf', mats['turf']), scen.to_object('scenery', mats['scenery']), sky.to_object('sky', mats['sky'])]
    fx_objs = [fx.meshes[i].to_object(f'fx_{i}', mats[f'fx_{i}']) for i in fx.specs]
    tris = sum(tri_count(o) for o in objs)
    fx_tris = sum(tri_count(o) for o in fx_objs)
    per = ', '.join(f'{o.name} {tri_count(o)}' for o in objs + fx_objs)
    print(f'{world}: {tris} + {fx_tris} effect triangles in {len(objs) + len(fx_objs)} meshes ({per}), {len(pal.names)} swatches')
    if tris > BUDGET:
        raise RuntimeError(f'{world}: {tris} triangles is over the budget of {BUDGET}')
    if fx_tris > FX_BUDGET:
        raise RuntimeError(f'{world}: {fx_tris} effect triangles is over the budget of {FX_BUDGET}')
    check_contract(objs, sport)
    for o in fx_objs:
        check_effect(o, fx.specs[o.name[3:]], sport)
    bpy.ops.export_scene.gltf(filepath=os.path.join(here, f'{world}.glb'), export_format='GLB',
                              export_apply=True, export_yup=True)
    export_usdz(os.path.join(here, f'{world}.usdz'))
    argv = sys.argv[sys.argv.index('--') + 1:] if '--' in sys.argv else []
    if '--preview' in argv or os.environ.get('WORLD_PREVIEW'):
        unlit = {'sky'} | {f'fx_{i}' for i, e in fx.specs.items() if e['shading'] != 'lit'}
        for o in fx_objs:
            o.hide_render = fx.specs[o.name[3:]]['shading'] in ('soft', 'particles')
        preview(mats, light, os.path.join(here, 'preview.png'), *preview_eye, unlit=unlit)
        if '--shot' in argv:                 # --shot PATH ex ey ez ax ay az fov (game coordinates)
            k = argv.index('--shot')
            v = [float(t) for t in argv[k + 2:k + 9]]
            shoot(argv[k + 1], tuple(v[:3]), tuple(v[3:6]), v[6], 960, 540)


def export_usdz(path):
    """The USD twin (RealityKit): forward −Z, up Y. Blender's exporter writes the meshes and
    materials in whatever order its depsgraph yields them, so the layer is exported loose, its
    prims put in name order, then packaged — a rebuild with no change has identical content."""
    import shutil
    import tempfile
    from pxr import Sdf, UsdUtils
    tmp = tempfile.mkdtemp()
    try:
        name = os.path.splitext(os.path.basename(path))[0]
        loose = os.path.join(tmp, name + '_loose.usdc')
        bpy.ops.wm.usd_export(filepath=loose, export_materials=True, generate_preview_surface=True,
                              export_textures_mode='NEW', relative_paths=True, convert_orientation=True,
                              export_global_forward_selection='NEGATIVE_Z', export_global_up_selection='Y')
        src = Sdf.Layer.FindOrOpen(loose)
        usdc = os.path.join(tmp, name + '.usdc')
        dst = Sdf.Layer.CreateNew(usdc)
        dst.TransferContent(src)
        for parent in ('/root', '/root/_materials'):         # re-add the children in name order
            spec = dst.GetPrimAtPath(parent)
            for child in [c.name for c in spec.nameChildren]:
                del spec.nameChildren[child]
            for child in sorted(c.name for c in src.GetPrimAtPath(parent).nameChildren):
                p = Sdf.Path(parent).AppendChild(child)
                if not Sdf.CopySpec(src, p, dst, p):
                    raise RuntimeError(f'could not copy {p}')
        dst.Save()
        if os.path.exists(path):
            os.remove(path)
        if not UsdUtils.CreateNewUsdzPackage(Sdf.AssetPath(usdc), path):
            raise RuntimeError(f'could not package {path}')
    finally:
        shutil.rmtree(tmp)
    _pin_zip_times(path)


def _pin_zip_times(path):
    """A USDZ is a zip; the exporter stamps each entry with the time of the build. Pinning them
    (1980-01-01, the zip epoch) makes a rebuild with no change byte-identical."""
    import struct
    import zipfile
    data = bytearray(open(path, 'rb').read())
    with zipfile.ZipFile(path) as z:
        offsets = [i.header_offset for i in z.infolist()]
    for o in offsets:                                         # local file headers
        assert data[o:o + 4] == b'PK\x03\x04'
        data[o + 10:o + 14] = b'\x00\x00\x21\x00'
    eocd = data.rfind(b'PK\x05\x06')
    n, = struct.unpack('<H', data[eocd + 10:eocd + 12])
    o, = struct.unpack('<I', data[eocd + 16:eocd + 20])
    for _ in range(n):                                        # the central directory
        assert data[o:o + 4] == b'PK\x01\x02'
        data[o + 12:o + 16] = b'\x00\x00\x21\x00'
        fn, ex, cm = struct.unpack('<HHH', data[o + 28:o + 34])
        o += 46 + fn + ex + cm
    open(path, 'wb').write(bytes(data))


# ================================================================ preview (ADR 0006's shading)
def preview(mats, light, path, eye, at, unlit=('sky',)):
    """Play camera, portrait 540 x 1200; the vertical field of view fitted so the pitch width
    (±16.5) fills the frame, clamped 45–78° (the prototype's fitCamera). Every lit material is
    replaced by ADR 0006's formula — albedo × (hemisphere(n) + sun · max(0, n·l)) — computed as
    emission, the prototype's light values over π as three.js r170 does; the sky is unlit."""
    scene = bpy.context.scene
    scene.render.engine = 'BLENDER_EEVEE'
    try:
        scene.eevee.taa_render_samples = 8
    except AttributeError:
        pass
    scene.view_settings.view_transform = 'Standard'
    scene.render.dither_intensity = 0.0
    scene.render.image_settings.file_format = 'PNG'
    scene.render.image_settings.color_mode = 'RGB'
    scene.render.image_settings.compression = 100
    world = bpy.data.worlds.new('preview')
    scene.world = world
    try:
        world.use_nodes = True
    except Exception:
        pass
    bg = next(n for n in world.node_tree.nodes if n.type == 'BACKGROUND')
    bg.inputs['Strength'].default_value = 0.0
    k = 1 / math.pi
    sky_c = tuple(v * light['hemi'] * k for v in linear(light['hemi_sky']))
    gnd_c = tuple(v * light['hemi'] * k for v in linear(light['hemi_ground']))
    sun_c = tuple(v * light['sun_i'] * k for v in linear(light['sun']))
    sp = light['sun_pos']
    ldir = _norm((sp[0], -sp[2], sp[1]))                 # towards the sun, Blender frame
    for name, mat in mats.items():
        nt = mat.node_tree
        tex = next(n for n in nt.nodes if n.type == 'TEX_IMAGE')
        out = next(n for n in nt.nodes if n.type == 'OUTPUT_MATERIAL')
        em = nt.nodes.new('ShaderNodeEmission')
        nt.links.new(em.outputs['Emission'], out.inputs['Surface'])
        if name in unlit:
            if name == 'sky':
                tex.interpolation = 'Linear'
            nt.links.new(tex.outputs['Color'], em.inputs['Color'])
            continue
        geo = nt.nodes.new('ShaderNodeNewGeometry')
        sep = nt.nodes.new('ShaderNodeSeparateXYZ')
        nt.links.new(geo.outputs['Normal'], sep.inputs['Vector'])
        f = nt.nodes.new('ShaderNodeMath')
        f.operation = 'MULTIPLY_ADD'
        f.inputs[1].default_value, f.inputs[2].default_value = 0.5, 0.5
        nt.links.new(sep.outputs['Z'], f.inputs[0])
        hemi = nt.nodes.new('ShaderNodeMix')
        hemi.data_type = 'RGBA'
        hemi.inputs['A'].default_value = (*gnd_c, 1)
        hemi.inputs['B'].default_value = (*sky_c, 1)
        nt.links.new(f.outputs[0], hemi.inputs['Factor'])
        dot = nt.nodes.new('ShaderNodeVectorMath')
        dot.operation = 'DOT_PRODUCT'
        dot.inputs[1].default_value = ldir
        nt.links.new(geo.outputs['Normal'], dot.inputs[0])
        mx = nt.nodes.new('ShaderNodeMath')
        mx.operation = 'MAXIMUM'
        mx.inputs[1].default_value = 0.0
        nt.links.new(dot.outputs['Value'], mx.inputs[0])
        sun = nt.nodes.new('ShaderNodeVectorMath')
        sun.operation = 'SCALE'
        sun.inputs[0].default_value = sun_c
        nt.links.new(mx.outputs[0], sun.inputs['Scale'])
        add = nt.nodes.new('ShaderNodeVectorMath')
        add.operation = 'ADD'
        nt.links.new(hemi.outputs['Result'], add.inputs[0])
        nt.links.new(sun.outputs['Vector'], add.inputs[1])
        alb = nt.nodes.new('ShaderNodeVectorMath')
        alb.operation = 'MULTIPLY'
        nt.links.new(tex.outputs['Color'], alb.inputs[0])
        nt.links.new(add.outputs['Vector'], alb.inputs[1])
        nt.links.new(alb.outputs['Vector'], em.inputs['Color'])
    ex, ey, ez = eye
    ax, ay, az = at
    near = Vector((0, 0, az - 4)) - Vector((ex, ey, ez))     # the prototype's nearPoint: focus − 8
    d = near.length
    hfov = 2 * math.atan(16.5 / d)
    vfov = 2 * math.atan(math.tan(hfov / 2) / (540 / 1200))
    vfov = clamp(math.degrees(vfov), 45, 78)
    shoot(path, eye, at, vfov, 540, 1200)


def shoot(path, eye, at, fov, w, h):
    scene = bpy.context.scene
    cam = bpy.data.objects.get('cam')
    if cam is None:
        cd = bpy.data.cameras.new('cam')
        cd.sensor_fit = 'VERTICAL'
        cd.clip_start, cd.clip_end = 0.1, 600
        cam = bpy.data.objects.new('cam', cd)
        scene.collection.objects.link(cam)
    scene.camera = cam
    cam.data.angle_y = math.radians(fov)
    scene.render.resolution_x, scene.render.resolution_y = w, h
    scene.render.resolution_percentage = 100
    g = lambda p: Vector((p[0], -p[2], p[1]))
    cam.location = g(eye)
    cam.rotation_euler = (g(at) - g(eye)).to_track_quat('-Z', 'Y').to_euler()
    scene.render.filepath = path
    bpy.ops.render.render(write_still=True)


# ================================================================ re-import check (build-worlds.sh)
def verify(glb, sport):
    """Re-imports a built GLB and checks the contract: the three core meshes and exactly the
    declared effects' `fx_<id>` meshes, each with its one material and UVs and no vertex colours,
    both budgets, nothing inside the boundary — effects wherever their motion takes them."""
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.gltf(filepath=glb)
    world = os.path.basename(glb)[:-4]
    specs = {f'fx_{e["id"]}': e for e in effects_of(world)}
    meshes = sorted((o for o in bpy.context.scene.objects if o.type == 'MESH'), key=lambda o: o.name)
    names = [o.name for o in meshes]
    want = sorted(['scenery', 'sky', 'turf'] + list(specs))
    problems = []
    if names != want:
        problems.append(f'meshes {names}, declared {want}')
    for o in meshes:
        mats = [m.name for m in o.data.materials]
        if mats != [o.name]:
            problems.append(f'{o.name}: materials {mats}')
        if not o.data.uv_layers:
            problems.append(f'{o.name}: no UVs')
        if len(o.data.color_attributes):
            problems.append(f'{o.name}: vertex colours')
    core = [o for o in meshes if o.name not in specs]
    tris = sum(tri_count(o) for o in core)
    fx_tris = sum(tri_count(o) for o in meshes if o.name in specs)
    if tris > BUDGET:
        problems.append(f'{tris} triangles')
    if fx_tris > FX_BUDGET:
        problems.append(f'{fx_tris} effect triangles')
    try:
        check_contract(core, sport)
        for o in meshes:
            if o.name in specs and o.data.uv_layers:
                check_effect(o, specs[o.name], sport)
    except RuntimeError as e:
        problems.append(str(e))
    problems += _verify_usdz(glb[:-4] + '.usdz', want)
    print(f'verify {world}: {tris} + {fx_tris} effect triangles, {len(meshes)} meshes ({len(specs)} effects), usdz twin: '
          + ('ok' if not problems else '; '.join(problems)))
    return not problems


def _verify_usdz(path, want):
    """The USDZ twin: the same meshes, each bound to its material, whose texture resolves
    inside the package."""
    from pxr import Usd, UsdShade
    stage = Usd.Stage.Open(path)
    if not stage:
        return [f'{os.path.basename(path)} does not open']
    problems, seen = [], []
    for prim in stage.Traverse():
        if prim.GetTypeName() == 'Mesh':
            seen.append(prim.GetName())
            mat, _ = UsdShade.MaterialBindingAPI(prim).ComputeBoundMaterial()
            if not mat or mat.GetPrim().GetName() != prim.GetName():
                problems.append(f'usdz {prim.GetName()}: bound to {mat.GetPrim().GetName() if mat else None}')
        if prim.GetTypeName() == 'Shader':
            f = prim.GetAttribute('inputs:file')
            if f and f.Get() is not None and not f.Get().resolvedPath:
                problems.append(f'usdz {prim.GetPath()}: texture does not resolve')
    if sorted(seen) != want:
        problems.append(f'usdz meshes {sorted(seen)}')
    return problems
