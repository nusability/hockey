"""
Builds the Himalaya world (spec §13): an ice rink on a high plateau among the peaks.

Ice hockey (spec §1: corner radius 8.5) — an ice sheet with blue and red lines, face-off circles
and creases, white boards with a red rail and a glass panel above them. Around it: a snowy
plateau, clusters of snow-capped pines, a chorten behind the far goal with prayer flags radiating
from its spire, flag strings on poles around the rink, a frozen lake, a monastery on a rock mesa,
boulders and cairns, and a ring of chunky snow-capped peaks.

One scene, two exports: `himalaya.glb` (Filament, Android) and `himalaya.usdz` (RealityKit, iOS),
plus `palette.png`. Deterministic: the same script always writes the same world.

Run: tools/build-worlds.sh  (Blender 5, headless). Preview from the play camera:
  Blender --background --factory-startup --python build_himalaya.py -- --preview [--wide PATH]

Coordinates: Blender is Z-up; the exporters convert to Y-up, where the game's pitch lies in X-Z
with Z along the pitch (spec §1). Blender's -Y is the game's +Z, so the far end is Blender -Y.

Materials are bound **by name** on each platform (ADR 0005): `turf` (the ice sheet and its
markings), `scenery`, `sky`. All three sample one palette texture (left half: an 8x8 grid of
swatches; right half: the vertical sky gradient), so colours never live in vertex attributes.
"""
import math
import os
import random
import sys

import bmesh
import bpy
from mathutils import Matrix, Vector

WORLD = 'himalaya'
HERE = os.path.dirname(os.path.abspath(__file__))
rng = random.Random(8848)

HW, HL = 15.0, 30.0          # pitch half-extents (spec §1)
CORNER = 8.5                 # ice hockey corner radius
GOAL_Z, GOAL_W, GOAL_D = 26.0, 6.0, 1.6
SKY_R = 320.0

# ---------------------------------------------------------------- palette
SWATCH = {
    'ice_a': '#eef6fd', 'ice_b': '#e2eef9', 'red': '#dc2626', 'blue': '#1d4ed8',
    'crease': '#8fcdf2', 'ice_logo': '#c4e2f7', 'board': '#f8fafc', 'kick': '#9fb4c8',
    'rail': '#e23b2e', 'glass': '#cfe8f6', 'glass_frame': '#8ea6bd', 'post': '#ef4444',
    'net': '#ffffff', 'snow': '#f3f7fd', 'snow_shade': '#d8e4f2',
    'rock': '#7d7682', 'rock_light': '#a49dab', 'pine': '#1f4d33',
    'pine_light': '#2e6b45', 'trunk': '#4a3221', 'pole': '#6b4a2e', 'rope': '#3b2f2a',
    'f_blue': '#2f6fd8', 'f_white': '#f5f7fa', 'f_red': '#e23b2e', 'f_green': '#2fa04a',
    'f_yellow': '#f2c31f', 'mon_white': '#f3ede0', 'mon_red': '#9a2c22', 'gold': '#e0ad3a',
    'roof': '#b9822a', 'mon_dark': '#2a221f', 'lake': '#bfe0f5', 'lake_dark': '#8fc4ea',
    'bench': '#2b5c9e',
}
# the sky gradient, bottom (below/at the horizon) to top (zenith)
SKY = [(0.0, '#f4f9fd'), (0.25, '#e3f1fb'), (0.45, '#a9d3f4'), (0.72, '#5b9fe6'), (1.0, '#2a67cc')]


# ================================================================ world kit (shared shape across
# the world scripts; each script stays standalone so tools/build-worlds.sh can run it alone)
TEX, COLS, ROWS = 256, 8, 8
NAMES = list(SWATCH)
assert len(NAMES) <= COLS * ROWS


def hexc(h):
    return tuple(int(h[i:i + 2], 16) / 255.0 for i in (1, 3, 5))


def swatch_uv(name):
    i = NAMES.index(name)
    cx, cy = i % COLS, i // COLS
    return ((cx + 0.5) / (2 * COLS), 1.0 - (cy + 0.5) / ROWS)   # left half


def gradient(stops, t):
    for (t0, c0), (t1, c1) in zip(stops, stops[1:]):
        if t <= t1:
            k = (t - t0) / (t1 - t0) if t1 > t0 else 0.0
            a, b = hexc(c0), hexc(c1)
            return tuple(a[i] + (b[i] - a[i]) * k for i in range(3))
    return hexc(stops[-1][1])


def build_palette():
    img = bpy.data.images.new('palette', TEX, TEX, alpha=False)
    px = [0.0] * (TEX * TEX * 4)
    cw, ch = TEX // 2 // COLS, TEX // ROWS
    cols = [hexc(SWATCH[n]) for n in NAMES]
    for y in range(TEX):
        sky = gradient(SKY, y / (TEX - 1))                   # 0 bottom (horizon) .. 1 top
        for x in range(TEX):
            if x < TEX // 2:
                i = ((TEX - 1 - y) // ch) * COLS + x // cw
                c = cols[i] if i < len(cols) else (0.5, 0.5, 0.5)
            else:
                c = sky
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


def T(x, y, z):
    return Matrix.Translation((x, y, z))


def S(x, y, z):
    return Matrix.Diagonal((x, y, z, 1.0))


def R(angle, axis):
    return Matrix.Rotation(angle, 4, axis)


class Builder:
    """Accumulates flat-shaded faces, each with one palette swatch, into one bmesh."""

    def __init__(self):
        self.bm = bmesh.new()
        self.uv = self.bm.loops.layers.uv.new('UVMap')

    def face(self, pts, colour):
        f = self.bm.faces.new([self.bm.verts.new(p) for p in pts])
        u = swatch_uv(colour)
        for loop in f.loops:
            loop[self.uv].uv = u
        return f

    def quad(self, a, b, c, d, colour):
        self.face([a, b, c, d], colour)

    def cuboid(self, M, colour, top=None, bottom=False):
        """The unit cube [-.5,.5]^3 through M."""
        c = [M @ Vector((x, y, z)) for z in (-0.5, 0.5) for y in (-0.5, 0.5) for x in (-0.5, 0.5)]
        self.face([c[4], c[5], c[7], c[6]], top or colour)
        self.face([c[0], c[1], c[5], c[4]], colour)
        self.face([c[3], c[2], c[6], c[7]], colour)
        self.face([c[1], c[3], c[7], c[5]], colour)
        self.face([c[2], c[0], c[4], c[6]], colour)
        if bottom:
            self.face([c[0], c[2], c[3], c[1]], colour)

    def box(self, cx, cy, z0, sx, sy, sz, colour, top=None, rot=0.0):
        self.cuboid(T(cx, cy, z0 + sz / 2) @ R(rot, 'Z') @ S(sx, sy, sz), colour, top)

    def prism(self, M, seg, r0, r1, colour, cap=None, bottom=False, phase=0.0, colour_fn=None):
        """A frustum (a cone when r1 == 0) of height 1 along local z through M."""
        a = [phase + 2 * math.pi * i / seg for i in range(seg)]
        lo = [M @ Vector((r0 * math.cos(t), r0 * math.sin(t), 0)) for t in a]
        if r1 <= 0:
            apex = M @ Vector((0, 0, 1))
            for i in range(seg):
                self.face([lo[i], lo[(i + 1) % seg], apex], colour_fn(i) if colour_fn else colour)
        else:
            hi = [M @ Vector((r1 * math.cos(t), r1 * math.sin(t), 1)) for t in a]
            for i in range(seg):
                j = (i + 1) % seg
                self.face([lo[i], lo[j], hi[j], hi[i]], colour_fn(i) if colour_fn else colour)
            if cap:
                self.face(hi, cap)
        if bottom:
            self.face(list(reversed(lo)), colour)

    def sphere(self, M, seg, rings, colour_fn):
        """A UV sphere of radius 1 through M; colour_fn(ring, segment)."""
        def p(r, s):
            th = math.pi * r / rings
            ph = 2 * math.pi * s / seg
            return M @ Vector((math.sin(th) * math.cos(ph), math.sin(th) * math.sin(ph), math.cos(th)))
        for r in range(rings):
            for s in range(seg):
                c = colour_fn(r, s)
                if r == 0:
                    self.face([p(0, 0), p(1, s), p(1, s + 1)], c)
                elif r == rings - 1:
                    self.face([p(r, s), p(r + 1, 0), p(r, s + 1)], c)
                else:
                    self.face([p(r, s), p(r + 1, s), p(r + 1, s + 1), p(r, s + 1)], c)

    def blob(self, M, colour_fn, seed, subdiv=1):
        """A lumpy low-poly rock: an icosphere with a smooth deterministic wobble."""
        tmp = bmesh.new()
        bmesh.ops.create_icosphere(tmp, subdivisions=subdiv, radius=1.0)
        vmap = {}
        for v in tmp.verts:
            x, y, z = v.co
            f = 0.8 + 0.16 * math.sin(x * 4.1 + seed) * math.cos(y * 3.3 - seed) + 0.1 * math.sin(z * 5.7 + x * 2.2 + seed * 1.7)
            vmap[v] = M @ (v.co * f)
        for i, f in enumerate(tmp.faces):
            self.face([vmap[v] for v in f.verts], colour_fn(i))
        tmp.free()

    def disc(self, cx, cy, z, r, seg, colour, rx=None):
        rx = rx or r
        pts = [(cx + rx * math.cos(2 * math.pi * i / seg), cy + r * math.sin(2 * math.pi * i / seg), z) for i in range(seg)]
        self.face(pts, colour)

    def arc(self, cx, cy, z, r, w, a0, a1, seg, colour, dashed=False):
        for i in range(seg):
            if dashed and i % 2:
                continue
            t0, t1 = a0 + (a1 - a0) * i / seg, a0 + (a1 - a0) * (i + 1) / seg
            p = lambda t, rr: (cx + rr * math.cos(t), cy + rr * math.sin(t), z)
            self.quad(p(t0, r - w), p(t1, r - w), p(t1, r + w), p(t0, r + w), colour)

    def strip(self, ring_a, ring_b, colour, closed=True):
        """Quads between two point loops of equal length."""
        n = len(ring_a)
        for i in range(n if closed else n - 1):
            j = (i + 1) % n
            self.quad(ring_a[i], ring_a[j], ring_b[j], ring_b[i], colour)

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


def rounded_rect(hw, hl, r, per_corner=6):
    """Counter-clockwise outline of a rounded rectangle centred on the origin."""
    pts = []
    for (cx, cy, a0) in ((hw - r, hl - r, 0), (-hw + r, hl - r, 90), (-hw + r, -hl + r, 180), (hw - r, -hl + r, 270)):
        for i in range(per_corner + 1):
            a = math.radians(a0 + 90 * i / per_corner)
            pts.append((cx + r * math.cos(a), cy + r * math.sin(a)))
    return pts


def along_ring(ring, count, phase=0.0):
    """`count` evenly spaced (x, y, heading) points along a closed outline."""
    edges = [(ring[i], ring[(i + 1) % len(ring)]) for i in range(len(ring))]
    total = sum(math.dist(a, c) for a, c in edges)
    out = []
    for k in range(count):
        s = total * ((k + phase) / count)
        for a, c in edges:
            ln = math.dist(a, c)
            if s <= ln and ln > 0:
                t = s / ln
                out.append((a[0] + (c[0] - a[0]) * t, a[1] + (c[1] - a[1]) * t, math.atan2(c[1] - a[1], c[0] - a[0])))
                break
            s -= ln
    return out


def rr_halfwidth(y, hw=HW, hl=HL, r=CORNER):
    d = abs(y) - (hl - r)
    if d <= 0:
        return hw
    return hw - r + math.sqrt(max(r * r - min(d, r) ** 2, 0.0))


def rr_sdf(x, y, hw=HW, hl=HL, r=CORNER):
    """Signed distance to the rounded-rect boundary (negative inside)."""
    qx, qy = abs(x) - (hw - r), abs(y) - (hl - r)
    return math.hypot(max(qx, 0), max(qy, 0)) + min(max(qx, qy), 0) - r


def turf_bands(b, bands, ca, cb, r=CORNER, per=8):
    """The pitch surface, clipped to the rounded boundary, in alternating bands."""
    arc_ys = sorted({s * (HL - r + r * math.sin(math.pi / 2 * k / per)) for k in range(per + 1) for s in (-1, 1)})
    for i in range(bands):
        y0 = -HL + 2 * HL * i / bands
        y1 = -HL + 2 * HL * (i + 1) / bands
        ys = [y0] + [y for y in arc_ys if y0 < y < y1] + [y1]
        right = [(rr_halfwidth(y, r=r), y, 0.0) for y in ys]
        left = [(-rr_halfwidth(y, r=r), y, 0.0) for y in reversed(ys)]
        b.face(right + left, ca if i % 2 else cb)


def cross_line(b, y, w, colour, z, r=CORNER):
    hw = min(rr_halfwidth(y - w, r=r), rr_halfwidth(y + w, r=r)) - 0.02
    b.quad((-hw, y - w, z), (hw, y - w, z), (hw, y + w, z), (-hw, y + w, z), colour)


def wall_ring(b, r, off, z0, z1, thick, colour, top=None, per=6):
    """A wall band on the rounded boundary: inner face at `off` outside the boundary."""
    ring = rounded_rect(HW + off, HL + off, r + off, per)
    for k in range(len(ring)):
        (ax, ay), (bx, by) = ring[k], ring[(k + 1) % len(ring)]
        nx, ny = by - ay, -(bx - ax)
        ln = math.hypot(nx, ny)
        if ln < 1e-6:
            continue
        ox, oy = nx / ln * thick, ny / ln * thick
        b.quad((ax, ay, z0), (bx, by, z0), (bx, by, z1), (ax, ay, z1), colour)
        b.quad((bx + ox, by + oy, z0), (ax + ox, ay + oy, z0), (ax + ox, ay + oy, z1), (bx + ox, by + oy, z1), colour)
        b.quad((ax, ay, z1), (bx, by, z1), (bx + ox, by + oy, z1), (ax + ox, ay + oy, z1), top or colour)


def goals(b, post, net, height=2.1):
    for sign in (-1, 1):
        gy = sign * GOAL_Z
        back = gy + sign * GOAL_D
        for sx in (-1, 1):
            b.box(sx * GOAL_W / 2, gy, 0, 0.14, 0.14, height, post)
        b.box(0, gy, height - 0.07, GOAL_W, 0.14, 0.14, post)
        b.box(0, back, 0, GOAL_W, 0.05, height, net)
        for sx in (-1, 1):
            b.box(sx * GOAL_W / 2, (gy + back) / 2, 0, 0.05, GOAL_D, height, net)
        b.box(0, (gy + back) / 2, height, GOAL_W, GOAL_D, 0.05, net)


def build_sky(mat):
    """An inside-out dome of radius SKY_R, built face by face (as the rest) so its index order is
    deterministic. The UVs sample the gradient in the palette's right half."""
    seg, rings = 32, 12
    bm = bmesh.new()
    uv = bm.loops.layers.uv.new('UVMap')
    verts = {}

    def vert(r, s):
        key = (r, s % seg) if 0 < r < rings else (r, 0)
        if key not in verts:
            th, ph = math.pi * r / rings, 2 * math.pi * s / seg
            verts[key] = bm.verts.new((SKY_R * math.sin(th) * math.cos(ph), SKY_R * math.sin(th) * math.sin(ph), SKY_R * math.cos(th)))
        return verts[key]

    def v_of(co):
        zn = max(0.0, co.z / SKY_R)
        # the camera mostly sees the first few degrees above the horizon, so the haze is a thin
        # band there (sin 4° ≈ 0.07) and the rest is the zenith colour
        return 0.02 + 0.96 * min(1.0, zn / 0.07) ** 0.5
    for r in range(rings):
        for s in range(seg):
            a, b_, c, d = vert(r, s), vert(r, s + 1), vert(r + 1, s + 1), vert(r + 1, s)
            tris = [(a, c, d)] if r == 0 else [(a, b_, c)] if r == rings - 1 else [(a, b_, c), (a, c, d)]
            for t in tris:
                f = bm.faces.new(t)                            # clockwise from outside: faces inward
                for loop in f.loops:
                    loop[uv].uv = (0.75, v_of(loop.vert.co))
    mesh = bpy.data.meshes.new('sky')
    bm.to_mesh(mesh)
    bm.free()
    mesh.materials.append(mat)
    for p in mesh.polygons:
        p.use_smooth = False
    obj = bpy.data.objects.new('sky', mesh)
    bpy.context.scene.collection.objects.link(obj)
    return obj


def export(objs):
    tris = sum(sum(len(p.vertices) - 2 for p in o.data.polygons) for o in objs)
    per = ', '.join(f'{o.name} {sum(len(p.vertices) - 2 for p in o.data.polygons)}' for o in objs)
    print(f'{WORLD}: {tris} triangles in {len(objs)} meshes ({per})')
    bpy.ops.export_scene.gltf(filepath=os.path.join(HERE, f'{WORLD}.glb'), export_format='GLB',
                              export_apply=True, export_yup=True)
    bpy.ops.wm.usd_export(filepath=os.path.join(HERE, f'{WORLD}.usdz'), export_materials=True,
                          generate_preview_surface=True, export_textures_mode='NEW', relative_paths=True,
                          convert_orientation=True, export_global_forward_selection='NEGATIVE_Z',
                          export_global_up_selection='Y')


def preview(ambient, argv):
    """Renders the play camera (spec: eye (0, 24, -46) → (0, 0, 2), 50° vertical, portrait) with
    the apps' spike light rig: a sun along (0.35, -1, 0.55) and a fill. No fog. Not part of the
    export; run with `-- --preview` (`--wide PATH`: an overview; `--shot PATH eye at`: any view)."""
    scene = bpy.context.scene
    try:
        scene.render.engine = 'BLENDER_EEVEE'
    except TypeError:
        scene.render.engine = 'BLENDER_EEVEE_NEXT'
    scene.render.resolution_x, scene.render.resolution_y = 540, 1200
    scene.render.resolution_percentage = 100
    scene.view_settings.view_transform = 'Standard'
    scene.render.image_settings.file_format = 'PNG'
    scene.render.image_settings.color_mode = 'RGB'
    scene.render.image_settings.compression = 100
    try:
        scene.eevee.taa_render_samples = 16
    except AttributeError:
        pass
    sky = bpy.data.materials['sky']
    nt = sky.node_tree
    tex = next(n for n in nt.nodes if n.type == 'TEX_IMAGE')
    tex.interpolation = 'Linear'
    em = nt.nodes.new('ShaderNodeEmission')
    nt.links.new(tex.outputs['Color'], em.inputs['Color'])
    nt.links.new(em.outputs['Emission'], nt.nodes['Material Output'].inputs['Surface'])
    world = bpy.data.worlds.new('preview')
    world.use_nodes = True
    world.node_tree.nodes['Background'].inputs['Color'].default_value = (*hexc(ambient), 1.0)
    world.node_tree.nodes['Background'].inputs['Strength'].default_value = 1.0
    scene.world = world

    def game(x, y, z):                     # game (Y-up, +Z far) → Blender (Z-up, -Y far)
        return Vector((x, -z, y))
    for name, d, energy in (('sun', (0.35, -1.0, 0.55), 3.2), ('fill', (-0.35, -0.6, -0.55), 0.8)):
        light = bpy.data.lights.new(name, 'SUN')
        light.energy = energy
        light.angle = math.radians(3)
        o = bpy.data.objects.new(name, light)
        o.rotation_euler = game(*d).normalized().to_track_quat('-Z', 'Y').to_euler()
        scene.collection.objects.link(o)
    cam = bpy.data.cameras.new('cam')
    cam.sensor_fit = 'VERTICAL'
    cam.angle_y = math.radians(50)
    cam.clip_start, cam.clip_end = 0.1, 500
    co = bpy.data.objects.new('cam', cam)
    scene.collection.objects.link(co)
    scene.camera = co

    def shoot(eye, at, path, w=540, h=1200, fov=50):
        scene.render.resolution_x, scene.render.resolution_y = w, h
        cam.sensor_fit = 'VERTICAL'
        cam.angle_y = math.radians(fov)
        co.location = game(*eye)
        co.rotation_euler = (game(*at) - game(*eye)).to_track_quat('-Z', 'Y').to_euler()
        scene.render.filepath = path
        bpy.ops.render.render(write_still=True)
    shoot((0, 24, -46), (0, 0, 2), os.path.join(HERE, 'preview.png'))
    if '--wide' in argv:
        shoot((0, 45, -100), (0, 5, 60), argv[argv.index('--wide') + 1], w=1200, h=800, fov=55)
    if '--shot' in argv:                   # --shot PATH ex ey ez ax ay az (game coordinates)
        k = argv.index('--shot')
        v = [float(t) for t in argv[k + 2:k + 8]]
        shoot(tuple(v[:3]), tuple(v[3:]), argv[k + 1], w=1200, h=800, fov=40)


# ================================================================ the world
LAKE = (17.0, -80.0, 14.0, 8.0)          # frozen lake: centre and radii
MESA = (-24.0, -112.0, 13.0, 7.0)        # monastery mesa: centre, radius, height
CHORTEN = (-5.0, -50.0)                  # the chorten behind the far goal
FLAGS = ['f_blue', 'f_white', 'f_red', 'f_green', 'f_yellow']


def smooth(t):
    t = max(0.0, min(1.0, t))
    return t * t * (3 - 2 * t)


def build_turf(mat):
    b = Builder()
    turf_bands(b, 10, 'ice_a', 'ice_b', per=12)
    z0, z1, z2 = 0.012, 0.018, 0.024
    # a snowflake emblem at centre ice
    for k in range(6):
        a = math.pi / 6 + k * math.pi / 3
        ca, sa = math.cos(a), math.sin(a)
        rot = lambda u, v: (u * ca - v * sa, u * sa + v * ca, z0)
        b.quad(rot(0.4, -0.18), rot(3.3, -0.18), rot(3.3, 0.18), rot(0.4, 0.18), 'ice_logo')
        for t, ln in ((1.6, 0.9), (2.5, 0.65)):
            for sgn in (-1, 1):
                ex, ey = t + ln * 0.6, sgn * ln * 0.8
                nx, ny = -ey, ex - t
                nl = math.hypot(nx, ny)
                w = 0.13 / nl
                b.quad(rot(t - nx * w, -ny * w), rot(ex - nx * w, ey - ny * w), rot(ex + nx * w, ey + ny * w), rot(t + nx * w, ny * w), 'ice_logo')
    # creases in front of each goal (radius 3.2, spec §1 keep-out) with a red outline
    for sign in (-1, 1):
        cy = sign * GOAL_Z
        a0, a1 = (math.pi, 2 * math.pi) if sign > 0 else (0.0, math.pi)
        pts = [(0, cy, z1)] + [(3.2 * math.cos(a0 + (a1 - a0) * i / 16), cy + 3.2 * math.sin(a0 + (a1 - a0) * i / 16), z1) for i in range(17)]
        b.face(pts, 'crease')
        b.arc(0, cy, z2, 3.2, 0.06, a0, a1, 16, 'red')
    # lines: goal lines red, blue lines, the red centre line
    for y in (-GOAL_Z, GOAL_Z):
        cross_line(b, y, 0.07, 'red', z2)
    for y in (-9.0, 9.0):
        cross_line(b, y, 0.3, 'blue', z2)
    cross_line(b, 0.0, 0.3, 'red', z2)
    # centre circle and spot (blue), neutral spots (red)
    b.arc(0, 0, z2, 4.5, 0.08, 0, 2 * math.pi, 48, 'blue')
    b.disc(0, 0, z2 + 0.002, 0.32, 12, 'blue')
    for sx in (-7.0, 7.0):
        for sy in (-7.0, 7.0):
            b.disc(sx, sy, z2, 0.3, 10, 'red')
    # end-zone face-off circles with spots and hash marks
    for sx in (-7.0, 7.0):
        for sy in (-20.0, 20.0):
            b.arc(sx, sy, z2, 4.5, 0.07, 0, 2 * math.pi, 40, 'red')
            b.disc(sx, sy, z2, 0.36, 12, 'red')
            for hx in (-1, 1):
                for hy in (-1, 1):
                    x0 = sx + hx * 4.5
                    b.quad((x0, sy + hy * 0.9 - 0.05, z2), (x0 + hx * 0.7, sy + hy * 0.9 - 0.05, z2),
                           (x0 + hx * 0.7, sy + hy * 0.9 + 0.05, z2), (x0, sy + hy * 0.9 + 0.05, z2), 'red')
    return b.to_object('turf', mat)


def ground_h(x, y):
    d = rr_sdf(x, y)
    if d < 7:
        return -0.05
    h = smooth((d - 7) / 34) * (3.2 + 2.2 * math.sin(x * 0.07 + 1.1) * math.cos(y * 0.06 - 0.4) + 1.4 * math.sin(x * 0.13 - y * 0.11 + 2.0))
    r = math.hypot(x, y * 0.9)
    h += smooth((r - 115) / 110) * (26 + 9 * math.sin(math.atan2(y, x) * 5 + 0.7))
    lx, ly, lrx, lry = LAKE
    le = math.hypot((x - lx) / lrx, (y - ly) / lry)
    if le < 2.0:
        h *= smooth((le - 1.15) / 0.85)                   # the lake lies flat on the snow
    return h - 0.05


def build_ground(b):
    n, size, p = 84, 292.0, 1.75
    cs = [math.copysign(size * abs(u) ** p, u) for u in (-1 + 2 * i / n for i in range(n + 1))]
    H = {}
    for i, x in enumerate(cs):
        for j, y in enumerate(cs):
            H[i, j] = ground_h(x, y)
    for i in range(n):
        for j in range(n):
            x0, x1, y0, y1 = cs[i], cs[i + 1], cs[j], cs[j + 1]
            if max(abs(x0), abs(x1)) < HW and max(abs(y0), abs(y1)) < HL:
                continue                                  # the ice covers this
            if math.hypot((x0 + x1) / 2, (y0 + y1) / 2) > 300:
                continue
            a, c, d, e = (x0, y0, H[i, j]), (x1, y0, H[i + 1, j]), (x1, y1, H[i + 1, j + 1]), (x0, y1, H[i, j + 1])
            for tri in ((a, c, d), (a, d, e)):
                n_ = (Vector(tri[1]) - Vector(tri[0])).cross(Vector(tri[2]) - Vector(tri[0])).normalized()
                if abs(n_.z) < 0.6:
                    col = 'rock_light'
                elif abs(n_.z) < 0.8:
                    col = 'snow_shade'
                else:
                    col = 'snow'
                b.face(list(tri), col)


def peak(b, x, y, H, Rb, lean=0.12):
    """A chunky faceted mountain: rock skirt, snow couloirs, a jagged snow line and a white cap."""
    z0 = ground_h(x, y) - 6
    N = 9
    ang = [2 * math.pi * (i + rng.uniform(-0.25, 0.25)) / N for i in range(N)]
    lx, ly = rng.uniform(-lean, lean) * Rb, rng.uniform(-lean, lean) * Rb
    rings = []
    for t, f in ((0.0, 1.0), (0.33, 0.66), (0.6, 0.38), (0.82, 0.16)):
        ring = []
        for a in ang:
            rr = Rb * f * rng.uniform(0.8, 1.15)
            tz = t + (rng.uniform(-0.07, 0.07) if 0 < t < 0.8 else 0)
            ring.append((x + lx * t + rr * math.cos(a), y + ly * t + rr * math.sin(a), z0 + (H + 6) * tz))
        rings.append(ring)
    apex = (x + lx, y + ly, z0 + H + 6)
    for i in range(N):
        j = (i + 1) % N
        b.quad(rings[0][i], rings[0][j], rings[1][j], rings[1][i], 'rock' if i % 3 == 0 else 'snow_shade')
        b.quad(rings[1][i], rings[1][j], rings[2][j], rings[2][i], 'rock_light' if i % 3 == 1 else 'snow')
        b.quad(rings[2][i], rings[2][j], rings[3][j], rings[3][i], 'snow' if i % 4 else 'snow_shade')
        b.face([rings[3][i], rings[3][j], apex], 'snow')


def build_peaks(b):
    """A ring of steep peaks whose footprints stay outside r ≈ 105, so the plateau stays open."""
    def ring(n, a0, a1, r0, r1, h0, h1):
        for _ in range(n):
            a = math.radians(rng.uniform(a0, a1))
            h = rng.uniform(h0, h1)
            rb = h * rng.uniform(0.5, 0.68)
            r = max(rng.uniform(r0, r1), 105 + rb)
            if r + rb > 300:
                r = 300 - rb
            peak(b, r * math.cos(a), r * math.sin(a), h, rb)
    peak(b, -25, -228, 150, 80, 0.05)                     # the giant behind the far end
    peak(b, 62, -222, 115, 66)
    ring(26, -168, -12, 140, 235, 50, 110)                # the far range
    ring(10, -15, 40, 130, 225, 40, 95)                   # the sides
    ring(10, 140, 195, 130, 225, 40, 95)
    ring(9, 40, 140, 170, 240, 40, 75)                    # behind the camera


def boards(b):
    per = 12
    wall_ring(b, CORNER, 0.15, 0.0, 0.24, 0.25, 'kick', per=per)
    wall_ring(b, CORNER, 0.15, 0.24, 1.0, 0.25, 'board', per=per)
    wall_ring(b, CORNER, 0.14, 0.62, 0.74, 0.02, 'blue', per=per)
    wall_ring(b, CORNER, 0.1, 1.0, 1.14, 0.4, 'rail', per=per)
    wall_ring(b, CORNER, 0.3, 1.14, 2.25, 0.05, 'glass', 'glass_frame', per=per)
    for x, y, a in along_ring(rounded_rect(HW + 0.33, HL + 0.33, CORNER + 0.33, per), 44):
        b.box(x, y, 1.14, 0.14, 0.14, 1.2, 'glass_frame', rot=a)
    # team benches along the +X side, outside the glass
    for y0 in (-9.0, 3.0):
        b.box(HW + 2.2, y0 + 3, 0, 1.2, 6.0, 0.5, 'bench', 'bench')
        b.box(HW + 2.7, y0 + 3, 0.5, 0.3, 6.0, 0.8, 'bench')


def pine(b, x, y, h):
    z = ground_h(x, y)
    rot = rng.uniform(0, 1)
    b.prism(T(x, y, z - 0.3) @ S(1, 1, h * 0.25 + 0.3), 5, 0.16 * h / 5, 0.12 * h / 5, 'trunk', phase=rot)
    for k, (z0, hh, r) in enumerate(((0.16, 0.42, 0.34), (0.38, 0.36, 0.27), (0.58, 0.34, 0.19))):
        b.prism(T(x, y, z + h * z0) @ S(1, 1, h * hh), 6, r * h, 0.0, 'pine', phase=rot + k * 0.5,
                colour_fn=lambda i: 'pine_light' if i % 2 else 'pine')
        # a snow skirt on each tier's shoulders
        b.prism(T(x, y, z + h * (z0 + hh * 0.52)) @ S(1, 1, h * hh * 0.48), 6, r * h * 0.5, 0.0, 'snow', phase=rot + k * 0.5)


def pines(b):
    clusters = 0
    count = 0
    while clusters < 72:
        x, y = rng.uniform(-115, 115), rng.uniform(-150, 70)
        d = rr_sdf(x, y)
        if d < 9 or not ok_spot(x, y, 4):
            continue
        clusters += 1
        for _ in range(rng.randint(3, 8)):
            px, py = x + rng.gauss(0, 3.2), y + rng.gauss(0, 3.2)
            if rr_sdf(px, py) < 7 or not ok_spot(px, py, 2):
                continue
            pine(b, px, py, rng.uniform(4.2, 7.5))
            count += 1
    return count


def ok_spot(x, y, margin):
    if y > 40 and abs(x) < 30:                            # behind the camera
        return False
    lx, ly, lrx, lry = LAKE
    if math.hypot((x - lx) / (lrx + margin), (y - ly) / (lry + margin)) < 1.15:
        return False
    if math.hypot(x - MESA[0], y - MESA[1]) < MESA[2] + margin:
        return False
    if math.hypot(x - CHORTEN[0], y - CHORTEN[1]) < 13 + margin:
        return False
    if ground_h(x, y) > 16:
        return False
    return True


def frozen_lake(b):
    lx, ly, lrx, lry = LAKE
    pts = [(lx + lrx * math.cos(2 * math.pi * i / 28), ly + lry * math.sin(2 * math.pi * i / 28), 0.03) for i in range(28)]
    b.face(pts, 'lake')
    inner = [(lx + 0.55 * lrx * math.cos(2 * math.pi * i / 20 + 0.3), ly + 0.5 * lry * math.sin(2 * math.pi * i / 20 + 0.3), 0.05) for i in range(20)]
    b.face(inner, 'lake_dark')
    for k in range(7):                                    # cracks
        a = rng.uniform(0, 2 * math.pi)
        r0, r1 = rng.uniform(0.2, 0.5), rng.uniform(0.7, 0.95)
        p0 = (lx + lrx * r0 * math.cos(a), ly + lry * r0 * math.sin(a))
        p1 = (lx + lrx * r1 * math.cos(a + 0.2), ly + lry * r1 * math.sin(a + 0.2))
        nx, ny = -(p1[1] - p0[1]), p1[0] - p0[0]
        nl = math.hypot(nx, ny)
        nx, ny = nx / nl * 0.08, ny / nl * 0.08
        b.quad((p0[0] - nx, p0[1] - ny, 0.07), (p1[0] - nx, p1[1] - ny, 0.07), (p1[0] + nx, p1[1] + ny, 0.07), (p0[0] + nx, p0[1] + ny, 0.07), 'f_white')


def flag_string(b, a, c, sag, spacing=0.9, start=0):
    """A rope from a to c sagging by `sag`, with prayer flags hanging from it in the five colours."""
    a, c = Vector(a), Vector(c)
    ln = (c - a).length
    n = max(4, int(ln / 1.5))
    pt = lambda t: a + (c - a) * t - Vector((0, 0, sag * 4 * t * (1 - t)))
    for k in range(n):
        p0, p1 = pt(k / n), pt((k + 1) / n)
        b.quad(p0, p1, p1 - Vector((0, 0, 0.07)), p0 - Vector((0, 0, 0.07)), 'rope')
    flags = int(ln / spacing)
    d = (c - a).normalized()
    for k in range(1, flags):
        t = k / flags
        p = pt(t)
        w = d * 0.3
        drop = Vector((0, 0, 0.62))
        tilt = Vector((d.y, -d.x, 0)) * 0.08
        b.quad(p - w, p + w, p + w - drop + tilt, p - w - drop + tilt, FLAGS[(k + start) % 5])


def flag_pole(b, x, y, h):
    z = ground_h(x, y)
    b.prism(T(x, y, z - 0.2) @ S(1, 1, h + 0.2), 6, 0.13, 0.09, 'pole')
    b.cuboid(T(x, y, z + h + 0.15) @ R(0.78, 'Z') @ S(0.34, 0.34, 0.34), 'gold')
    return (x, y, z + h)


def rink_flags(b):
    per = 12
    poles = [flag_pole(b, x, y, 5.0) for x, y, _ in along_ring(rounded_rect(HW + 4.2, HL + 4.2, CORNER + 4.2, per), 16, 0.5)]
    for k in range(len(poles)):
        p0, p1 = poles[k], poles[(k + 1) % len(poles)]
        if p0[1] > 30 and p1[1] > 30:
            continue                                      # behind the camera
        flag_string(b, (p0[0], p0[1], p0[2] - 0.1), (p1[0], p1[1], p1[2] - 0.1), 1.1, start=k)


def chorten(b):
    x, y = CHORTEN
    z = ground_h(x, y)
    for k, (w, hh) in enumerate(((6.0, 0.9), (4.8, 0.8), (3.8, 0.7))):
        zz = z + sum(v[1] for v in ((6.0, 0.9), (4.8, 0.8), (3.8, 0.7))[:k])
        b.box(x, y, zz, w, w, hh, 'mon_white')
    zb = z + 2.4
    b.box(x, y, zb, 3.9, 3.9, 0.25, 'mon_red')
    b.sphere(T(x, y, zb + 0.25) @ S(1.9, 1.9, 1.9), 12, 6, lambda r, s: 'mon_white' if r < 3 else 'mon_white')
    b.box(x, y, zb + 1.9, 1.3, 1.3, 0.8, 'gold')
    b.box(x, y, zb + 2.35, 1.3, 1.3, 0.12, 'mon_red')
    b.prism(T(x, y, zb + 2.7) @ S(1, 1, 3.4), 8, 0.6, 0.0, 'gold')
    for k in range(5):
        b.prism(T(x, y, zb + 2.9 + k * 0.55) @ S(1, 1, 0.14), 8, 0.62 - k * 0.1, 0.62 - k * 0.1, 'roof')
    top = (x, y, zb + 5.6)
    b.sphere(T(*top) @ S(0.28, 0.28, 0.28), 6, 4, lambda r, s: 'gold')
    for k in range(10):                                  # radiating flag strings
        a = 2 * math.pi * (k + 0.5) / 10
        px, py = x + 12 * math.cos(a), y + 12 * math.sin(a)
        if rr_sdf(px, py) < 3:
            continue
        base = flag_pole(b, px, py, 1.6)
        flag_string(b, (x, y, top[2] - 0.2), base, 1.4, spacing=0.8, start=k)


def monastery(b):
    mx, my, mr, mh = MESA
    z0 = ground_h(mx, my) - 2
    b.prism(T(mx, my, z0) @ S(1, 1, mh + 2), 9, mr * 1.25, mr, 'rock', cap='snow',
            colour_fn=lambda i: 'rock_light' if i % 3 == 0 else 'rock')
    zt = z0 + mh + 2
    face = math.atan2(-my + 46, -mx)                     # the facade looks toward the camera
    M = T(mx, my, zt) @ R(face - math.pi / 2, 'Z')
    # lower hall, red frieze, upper storey, gold roofs
    b.cuboid(M @ T(0, 0, 2.2) @ S(11, 7, 4.4), 'mon_white')
    b.cuboid(M @ T(0, 0, 4.7) @ S(11.2, 7.2, 0.8), 'mon_red')
    b.cuboid(M @ T(0, 0.5, 6.4) @ S(6.5, 4.5, 2.6), 'mon_white')
    b.cuboid(M @ T(0, 0.5, 8.0) @ S(6.7, 4.7, 0.6), 'mon_red')
    b.prism(M @ T(0, 0.5, 8.3) @ R(math.pi / 4, 'Z') @ S(1, 1, 2.0), 4, 4.8, 0.0, 'roof')
    b.prism(M @ T(0, 0.5, 10.0) @ S(1, 1, 1.6), 8, 0.35, 0.0, 'gold')
    for k in range(-2, 3):                                # windows on the facade
        b.cuboid(M @ T(k * 2.0, 3.52, 2.9) @ S(0.8, 0.1, 1.1), 'mon_dark')
    b.cuboid(M @ T(0, 3.52, 1.1) @ S(1.6, 0.1, 2.2), 'mon_red')
    for sx in (-1, 1):                                    # two small stupas flanking it
        b.prism(M @ T(sx * 7.5, 1.0, 0) @ S(1, 1, 1.2), 4, 1.4, 1.4, 'mon_white', cap='mon_white', phase=math.pi / 4)
        b.sphere(M @ T(sx * 7.5, 1.0, 1.4) @ S(0.9, 0.9, 0.9), 8, 4, lambda r, s: 'mon_white')
        b.prism(M @ T(sx * 7.5, 1.0, 2.1) @ S(1, 1, 1.4), 6, 0.35, 0.0, 'gold')
    # a mast with flags strung down to the mesa rim
    mast_top = M @ Vector((0, 0.5, 14.0))
    b.prism(M @ T(0, 0.5, 8.5) @ S(1, 1, 5.6), 6, 0.12, 0.08, 'pole')
    for k in range(6):
        a = 2 * math.pi * k / 6 + 0.3
        end = (mx + mr * 0.92 * math.cos(a), my + mr * 0.92 * math.sin(a), zt + 0.2)
        flag_string(b, tuple(mast_top), end, 1.0, spacing=0.9, start=k)


def boulders(b):
    placed = 0
    while placed < 46:
        x, y = rng.uniform(-120, 120), rng.uniform(-140, 60)
        if rr_sdf(x, y) < 6 or not ok_spot(x, y, 1):
            continue
        s = rng.uniform(0.8, 2.6)
        z = ground_h(x, y)
        dark = {rng.randrange(20) for _ in range(4)}
        b.blob(T(x, y, z + s * 0.25) @ R(rng.uniform(0, 6.3), 'Z') @ S(s * 1.2, s, s * 0.75),
               lambda i, dark=dark: 'snow' if i % 5 == 0 else ('rock' if i in dark else 'rock_light'), rng.uniform(0, 50))
        placed += 1
    for _ in range(12):                                   # cairns near the rink
        while True:
            x, y = rng.uniform(-40, 40), rng.uniform(-60, 30)
            if 5 < rr_sdf(x, y) < 18 and ok_spot(x, y, 1):
                break
        z = ground_h(x, y)
        s = 0.7
        for k in range(4):
            b.blob(T(x, y, z + s * 0.4) @ S(s, s * 0.9, s * 0.55), lambda i: 'rock_light' if i % 3 else 'rock', rng.uniform(0, 50), subdiv=0)
            z += s * 0.8
            s *= 0.72


def build_scenery(mat):
    b = Builder()
    build_ground(b)
    boards(b)
    goals(b, 'post', 'net', height=1.8)
    frozen_lake(b)
    build_peaks(b)
    pines(b)
    chorten(b)
    rink_flags(b)
    monastery(b)
    boulders(b)
    return b.to_object('scenery', mat)


def main():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    img = build_palette()
    mats = {n: make_material(n, img) for n in ('turf', 'scenery', 'sky')}
    objs = [build_turf(mats['turf']), build_scenery(mats['scenery']), build_sky(mats['sky'])]
    export(objs)
    argv = sys.argv[sys.argv.index('--') + 1:] if '--' in sys.argv else []
    if '--preview' in argv:
        preview('#9fb6cc', argv)


main()
