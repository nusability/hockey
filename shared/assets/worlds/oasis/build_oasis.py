"""
Builds the Desert Oasis world (spec §13): green turf between golden dunes and palms.

Field hockey (corner radius 2.0) inside an adobe wall with teal-capped pillars and bunting. Behind
the far goal lies the oasis itself — a turquoise pond with a shore, reeds, lily pads and a little
jetty, ringed by palms — with a striped market stall, Bedouin tents, a sandstone gateway, a camel
caravan on a dune crest, cacti, rocks, rolling dunes out to the horizon and distant buttes.

One scene, two exports: `oasis.glb` (Filament, Android) and `oasis.usdz` (RealityKit, iOS), plus
`palette.png` — the file names both apps load today. Deterministic: the same script always writes
the same world.

Run: tools/build-worlds.sh  (Blender 5, headless). Preview from the play camera:
  Blender --background --factory-startup --python build_oasis.py -- --preview [--wide PATH]

Coordinates: Blender is Z-up; the exporters convert to Y-up, where the game's pitch lies in X-Z
with Z along the pitch (spec §1). Blender's -Y is the game's +Z, so the far end is Blender -Y.

Materials are bound **by name** on each platform (ADR 0005): `turf`, `scenery`, `sky`. All three
sample one palette texture (left half: an 8x8 grid of swatches; right half: the vertical sky
gradient), so colours never live in vertex attributes either engine might drop.
"""
import math
import os
import random
import sys

import bmesh
import bpy
from mathutils import Matrix, Vector

WORLD = 'oasis'
HERE = os.path.dirname(os.path.abspath(__file__))
rng = random.Random(20260913)

HW, HL = 15.0, 30.0          # pitch half-extents (spec §1)
CORNER = 2.0                 # field hockey corner radius
GOAL_Z, GOAL_W, GOAL_D = 26.0, 6.0, 1.6
SKY_R = 320.0

# ---------------------------------------------------------------- palette
SWATCH = {
    'turf_a': '#4c9a3f', 'turf_b': '#448f39', 'line': '#fff7e6', 'wear': '#8fae4a',
    'sand': '#ebc68c', 'sand_light': '#f5dba8', 'sand_dark': '#d9a96b', 'sand_shadow': '#c48d55',
    'wet_sand': '#9c7148', 'wall': '#d28b58', 'wall_top': '#2dd4bf', 'wall_base': '#b8744a',
    'pillar': '#c27a4b', 'post': '#ef4444', 'net': '#fff1d6', 'water_deep': '#0d8a8f',
    'water': '#26b5ae', 'water_light': '#7ee3d4', 'lily': '#4caf50', 'trunk': '#8a5a34',
    'trunk_dark': '#6e4526', 'leaf': '#3aa04a', 'leaf_dark': '#23803c', 'leaf_light': '#72c24e',
    'coconut': '#5a3a1e', 'rock': '#c8865a', 'rock_light': '#e3b487', 'rock_dark': '#9a6642',
    'cactus': '#4f9a52', 'cactus_dark': '#3a7a40', 'reed': '#86b24a', 'tent_a': '#f7ecd4',
    'tent_red': '#e0523f', 'tent_teal': '#1fb5a5', 'tent_blue': '#3b82f6', 'tent_yellow': '#facc15',
    'tent_orange': '#f97316', 'wood': '#6b4526', 'camel': '#c08650', 'camel_dark': '#94623a',
    'blanket': '#d6334a', 'pot': '#c4622d', 'fruit_o': '#f59e0b', 'fruit_g': '#84cc16',
    'ruin': '#e8c08a', 'ruin_dark': '#c99a62', 'shadow': '#5a3a26', 'butte': '#d9905e',
    'butte_dark': '#b86f45',
}
# the sky gradient, bottom (below/at the horizon) to top (zenith): a warm golden hour
SKY = [(0.0, '#fff0cf'), (0.3, '#ffd89e'), (0.62, '#fbb574'), (1.0, '#f3955f')]


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
POND = (-4.0, -60.0, 14.0, 9.0)          # centre and radii of the oasis pond
STALL = (-16.5, -41.0)                   # the market stall
TENTS = ((20.0, -41.0, 0.3), (31.0, -54.0, -0.4))
ROUND_TENT = (-31.0, -58.0)
GATE = (30.0, -98.0)
CARAVAN_Y = -112.0                       # the caravan's crest is searched from here outward
PADS = [(POND[0], POND[1], 22.0), (STALL[0], STALL[1], 7.0), (TENTS[0][0], TENTS[0][1], 7.0), (TENTS[1][0], TENTS[1][1], 7.0),
        (ROUND_TENT[0], ROUND_TENT[1], 6.0), (GATE[0], GATE[1], 7.0)]
SUN = Vector((-0.35, 0.55, 1.0)).normalized()             # towards the apps' sun (game (0.35,-1,0.55))


def smooth(t):
    t = max(0.0, min(1.0, t))
    return t * t * (3 - 2 * t)


def build_turf(mat):
    b = Builder()
    turf_bands(b, 12, 'turf_a', 'turf_b')
    # sandy wear in the goal mouths and along the edges
    for sign in (-1, 1):
        for k in range(6):
            b.disc(rng.uniform(-3.5, 3.5), sign * rng.uniform(22.5, 25.2), 0.008, rng.uniform(0.4, 0.8), 10, 'wear', rx=rng.uniform(0.8, 1.5))
    for k in range(10):
        sx = rng.choice((-1, 1))
        b.disc(sx * rng.uniform(13.4, 14.1), rng.uniform(-24, 24), 0.008, rng.uniform(0.5, 1.1), 9, 'wear', rx=rng.uniform(0.35, 0.6))
    z, w = 0.02, 0.1
    for y in (-GOAL_Z, GOAL_Z, 0.0):                      # goal lines and centre line
        cross_line(b, y, w, 'line', z)
    for y in (-15.0, 15.0):                               # the 23 m lines
        cross_line(b, y, 0.08, 'line', z)
    for sign in (-1, 1):                                  # shooting circles, dashed outer circles, spots
        cy = sign * GOAL_Z
        a0, a1 = (math.pi, 2 * math.pi) if sign > 0 else (0.0, math.pi)
        b.arc(0, cy, z, 9.0, w, a0, a1, 28, 'line')
        b.arc(0, cy, z, 13.0, 0.07, a0 + 0.05, a1 - 0.05, 30, 'line', dashed=True)
        b.disc(0, cy - sign * 6.4, z, 0.2, 8, 'line')
    b.disc(0, 0, z, 0.25, 10, 'line')
    return b.to_object('turf', mat)


def ground_h(x, y):
    d = rr_sdf(x, y)
    if d < 6:
        return -0.05
    amp = smooth((d - 6) / 40) * (2.5 + 9 * smooth((d - 40) / 140))
    u, v = x * 0.8 + y * 0.6, -x * 0.6 + y * 0.8                     # wind-aligned dune rows
    w = u * 0.05 + 1.3 * math.sin(v * 0.028) + 0.6 * math.sin(v * 0.07 + 1.3)
    crest = (0.5 + 0.5 * math.sin(w)) ** 1.6
    h = amp * (0.6 * crest + 0.25 * (0.5 + 0.5 * math.sin(x * 0.05 + y * 0.037 + 2)) + 0.15 * (0.5 + 0.5 * math.sin(v * 0.09)))
    for px, py, pr in PADS:                                             # flat pads for the set pieces
        h *= smooth((math.hypot(x - px, y - py) - pr) / 12)
    return h - 0.05


def build_ground(b):
    n, size, p = 84, 285.0, 1.7
    cs = [math.copysign(size * abs(u) ** p, u) for u in (-1 + 2 * i / n for i in range(n + 1))]
    H = {(i, j): ground_h(x, y) for i, x in enumerate(cs) for j, y in enumerate(cs)}
    for i in range(n):
        for j in range(n):
            x0, x1, y0, y1 = cs[i], cs[i + 1], cs[j], cs[j + 1]
            if max(abs(x0), abs(x1)) < HW and max(abs(y0), abs(y1)) < HL:
                continue                                  # the turf covers this
            if math.hypot((x0 + x1) / 2, (y0 + y1) / 2) > 300:
                continue
            a, c, d, e = (x0, y0, H[i, j]), (x1, y0, H[i + 1, j]), (x1, y1, H[i + 1, j + 1]), (x0, y1, H[i, j + 1])
            for tri in ((a, c, d), (a, d, e)):
                nrm = (Vector(tri[1]) - Vector(tri[0])).cross(Vector(tri[2]) - Vector(tri[0])).normalized()
                if nrm.z < 0:
                    nrm = -nrm
                lit = nrm.dot(SUN)
                hz = (tri[0][2] + tri[1][2] + tri[2][2]) / 3
                if lit < 0.7:
                    col = 'sand_shadow'
                elif lit < 0.8:
                    col = 'sand_dark'
                elif hz > 7.5 and lit > 0.86:
                    col = 'sand_light'
                else:
                    col = 'sand'
                b.face(list(tri), col)


def adobe_wall(b):
    wall_ring(b, CORNER, 0.15, 0.0, 0.22, 0.34, 'wall_base')
    wall_ring(b, CORNER, 0.15, 0.22, 1.0, 0.3, 'wall')
    wall_ring(b, CORNER, 0.1, 1.0, 1.12, 0.4, 'wall_top')
    tops = []
    for x, y, a in along_ring(rounded_rect(HW + 0.5, HL + 0.5, CORNER + 0.5), 28, 0.5):
        b.box(x, y, 0, 0.7, 0.7, 1.55, 'pillar', rot=a)
        b.box(x, y, 1.55, 0.86, 0.86, 0.14, 'wall_top', rot=a)
        b.cuboid(T(x, y, 1.84) @ R(a + math.pi / 4, 'Z') @ R(0.6155, 'X') @ R(math.pi / 4, 'Y') @ S(0.34, 0.34, 0.34), 'wall_top')
        tops.append((x, y, 1.62))
    colours = ['tent_teal', 'tent_red', 'tent_yellow', 'tent_orange', 'tent_blue', 'fruit_g']
    for k in range(len(tops)):                            # bunting between the pillars
        p0, p1 = tops[k], tops[(k + 1) % len(tops)]
        if p0[1] > 25 and p1[1] > 25:
            continue                                      # behind the camera
        if any(rr_sdf(p0[0] + (p1[0] - p0[0]) * t / 8, p0[1] + (p1[1] - p0[1]) * t / 8) < 0.2 for t in range(9)):
            continue                                      # a chord across a corner would cut inside
        bunting(b, p0, p1, 0.45, colours, k)


def bunting(b, a, c, sag, colours, start=0, size=0.32):
    a, c = Vector(a), Vector(c)
    ln = (c - a).length
    n = max(3, int(ln / 0.8))
    pt = lambda t: a + (c - a) * t - Vector((0, 0, sag * 4 * t * (1 - t)))
    d = (c - a).normalized()
    for k in range(n):
        p0, p1 = pt(k / n), pt((k + 1) / n)
        b.quad(p0, p1, p1 - Vector((0, 0, 0.04)), p0 - Vector((0, 0, 0.04)), 'wood')
        m = pt((k + 0.5) / n)
        b.face([m - d * size, m + d * size, m - Vector((0, 0, size * 1.6))], colours[(k + start) % len(colours)])


def pond(b):
    cx, cy, rx, ry = POND
    seg = 36

    def ring(f, z, wob=0.0):
        return [(cx + rx * f * (1 + wob * math.sin(3 * t + 1)) * math.cos(t), cy + ry * f * (1 + wob * math.sin(3 * t + 1)) * math.sin(t), z)
                for t in (2 * math.pi * i / seg for i in range(seg))]
    b.strip(ring(1.0, 0.04, 0.06), ring(1.22, 0.02, 0.06), 'wet_sand')
    b.strip(ring(0.84, 0.06, 0.06), ring(1.0, 0.06, 0.06), 'water_light')
    b.strip(ring(0.5, 0.06, 0.06), ring(0.84, 0.06, 0.06), 'water')
    b.face(ring(0.5, 0.06, 0.06), 'water_deep')
    for k in range(9):                                    # lily pads
        t = rng.uniform(0, 2 * math.pi)
        f = rng.uniform(0.55, 0.8)
        b.disc(cx + rx * f * math.cos(t), cy + ry * f * math.sin(t), 0.08, rng.uniform(0.5, 0.8), 7, 'lily')
    # a little jetty reaching in from the right-hand shore
    jx, jy = cx - rx * 0.62, cy + ry * 0.5
    for k in range(6):
        b.box(jx - k * 0.95 + 0.5, jy + 3.0, 0.25, 0.8, 2.0, 0.12, 'wood', rot=0.35)
    for sx in (-1, 1):
        for k in range(3):
            b.box(jx - k * 2.3 + 0.8 + sx * 0.3, jy + 3.0 + sx * 0.9, -0.2, 0.18, 0.18, 0.75, 'trunk_dark')
    # reeds in tufts around the shore
    for k in range(34):
        t = 2 * math.pi * k / 34 + rng.uniform(-0.06, 0.06)
        f = rng.uniform(0.98, 1.12)
        x, y = cx + rx * f * math.cos(t), cy + ry * f * math.sin(t)
        if abs(t - 2.6) < 0.35:
            continue                                      # the jetty
        for m in range(4):
            a = rng.uniform(0, 2 * math.pi)
            h = rng.uniform(0.9, 1.7)
            lx, ly = math.cos(a) * 0.2, math.sin(a) * 0.2
            tip = (x + lx * 2.5, y + ly * 2.5, h)
            b.face([(x - ly, y + lx, 0.03), (x + ly, y - lx, 0.03), tip], 'reed' if m % 2 else 'leaf_dark')
    # rocks at the shore
    for k in range(7):
        t = rng.uniform(0, 2 * math.pi)
        s = rng.uniform(0.6, 1.3)
        b.blob(T(cx + rx * 1.2 * math.cos(t), cy + ry * 1.2 * math.sin(t), s * 0.2) @ S(s * 1.3, s, s * 0.7),
               lambda i: 'rock_light' if i % 4 else 'rock', rng.uniform(0, 50))


def palm(b, x, y, height, lean, bend=0.2):
    z = ground_h(x, y) - 0.1
    seg, rings = 6, 7
    dx, dy = math.cos(lean), math.sin(lean)
    centre = lambda t: (x + dx * bend * height * t * t, y + dy * bend * height * t * t, z + height * t)
    loops = []
    for r in range(rings + 1):
        t = r / rings
        c = centre(t)
        rad = 0.4 - 0.17 * t
        loops.append([(c[0] + rad * math.cos(2 * math.pi * s / seg), c[1] + rad * math.sin(2 * math.pi * s / seg), c[2]) for s in range(seg)])
    for r in range(rings):
        b.strip(loops[r], loops[r + 1], 'trunk' if r % 2 else 'trunk_dark')
    top = centre(1.0)
    for k in range(3):                                    # coconuts
        a = 2 * math.pi * k / 3 + lean
        b.cuboid(T(top[0] + 0.3 * math.cos(a), top[1] + 0.3 * math.sin(a), top[2] - 0.25) @ R(0.6, 'X') @ R(0.7, 'Y') @ S(0.34, 0.34, 0.34), 'coconut')
    fronds = 8
    for f in range(fronds):
        a = 2 * math.pi * f / fronds + rng.uniform(-0.18, 0.18)
        length = rng.uniform(3.4, 4.6) * height / 8.5
        fx, fy = math.cos(a), math.sin(a)
        px_, py_ = -fy, fx
        droop = rng.uniform(1.6, 2.4)
        pts = []
        for k in range(6):
            t = k / 5
            w = 0.85 * math.sin(math.pi * min(t * 0.95 + 0.05, 0.97)) * length / 4 + 0.04
            cx_, cy_ = top[0] + fx * length * t, top[1] + fy * length * t
            cz = top[2] + 0.9 * t - droop * t * t
            pts.append(((cx_ - px_ * w, cy_ - py_ * w, cz - 0.15 * t), (cx_ + px_ * w, cy_ + py_ * w, cz - 0.15 * t), (cx_, cy_, cz + 0.14)))
        col = ('leaf', 'leaf_dark', 'leaf_light')[f % 3]
        for k in range(5):
            l0, r0, m0 = pts[k]
            l1, r1, m1 = pts[k + 1]
            b.quad(l0, m0, m1, l1, col)
            b.quad(m0, r0, r1, m1, col)


def ok_spot(x, y, margin=0.0):
    if rr_sdf(x, y) < 5 + margin:
        return False
    if y > 42 and abs(x) < 34:                            # behind the camera
        return False
    cx, cy, rx, ry = POND
    if math.hypot((x - cx) / (rx + 2), (y - cy) / (ry + 2)) < 1.1:
        return False
    for px, py in (STALL, TENTS[0][:2], TENTS[1][:2], ROUND_TENT, GATE):
        if math.hypot(x - px, y - py) < 6 + margin:
            return False
    return True


def palms(b):
    cx, cy, rx, ry = POND
    n = 0
    for k in range(22):                                   # the oasis ring
        t = 2 * math.pi * k / 22 + rng.uniform(-0.1, 0.1)
        f = rng.uniform(1.3, 1.85)
        x, y = cx + rx * f * math.cos(t), cy + ry * f * math.sin(t)
        if any(math.hypot(x - px, y - py) < 5.5 for px, py in (STALL, TENTS[0][:2])):
            continue
        lean = math.atan2(cy - y, cx - x) + rng.uniform(-0.5, 0.5)     # leaning over the water
        palm(b, x, y, rng.uniform(7.0, 10.5), lean, rng.uniform(0.15, 0.3))
        n += 1
    while n < 58:                                         # scattered groves
        gx, gy = rng.uniform(-95, 95), rng.uniform(-150, 45)
        if not ok_spot(gx, gy, 2) or ground_h(gx, gy) > 6:
            continue
        for m in range(rng.randint(1, 4)):
            x, y = gx + rng.uniform(-4, 4), gy + rng.uniform(-4, 4)
            if not ok_spot(x, y, 1):
                continue
            palm(b, x, y, rng.uniform(6.0, 9.5), rng.uniform(0, 2 * math.pi), rng.uniform(0.12, 0.28))
            n += 1


def market_stall(b):
    x, y = STALL
    face = math.atan2(46 - y, -x) - math.pi / 2           # the front looks toward the camera
    M = T(x, y, ground_h(x, y)) @ R(face, 'Z')
    b.cuboid(M @ T(0, 0.3, 0.5) @ S(5.0, 1.3, 1.0), 'wood', 'tent_a')
    for sx in (-2.4, 2.4):
        for sy in (-1.4, 0.9):
            b.cuboid(M @ T(sx, sy, 1.45) @ S(0.16, 0.16, 2.9), 'wood')
    stripes = 8
    for k in range(stripes):                              # a sloped striped awning
        x0, x1 = -2.8 + 5.6 * k / stripes, -2.8 + 5.6 * (k + 1) / stripes
        col = 'tent_red' if k % 2 else 'tent_a'
        b.quad(M @ Vector((x0, -1.8, 3.1)), M @ Vector((x1, -1.8, 3.1)), M @ Vector((x1, 1.7, 2.45)), M @ Vector((x0, 1.7, 2.45)), col)
        b.face([M @ Vector((x0, 1.7, 2.45)), M @ Vector((x1, 1.7, 2.45)), M @ Vector(((x0 + x1) / 2, 1.75, 2.0))], col)
    for k in range(7):                                    # the goods
        gx = -2.0 + k * 0.66
        kind = k % 3
        if kind == 0:
            b.prism(M @ T(gx, 0.3, 1.0) @ S(1, 1, 0.55), 6, 0.25, 0.18, 'pot', cap='shadow')
        else:
            b.cuboid(M @ T(gx, 0.3, 1.13) @ S(0.5, 0.45, 0.26), 'wood', 'fruit_o' if kind == 1 else 'fruit_g')
    # a stack of pots and a rug beside it
    for k, (px, py, s) in enumerate(((3.4, 0.6, 0.5), (3.9, 0.1, 0.42), (3.6, 0.3, 0.36))):
        b.prism(M @ T(px, py, 0 if k < 2 else 0.85) @ S(1, 1, 0.85), 7, s, s * 0.6, 'pot', cap='shadow')
    b.cuboid(M @ T(-3.9, 1.0, 0.02) @ S(1.8, 2.6, 0.04), 'blanket', 'blanket')


def tent(b, x, y, rot):
    z = ground_h(x, y)
    M = T(x, y, z) @ R(rot, 'Z')
    L, W, H = 7.0, 5.0, 3.0
    stripes = 7
    for k in range(stripes):
        y0, y1 = -L / 2 + L * k / stripes, -L / 2 + L * (k + 1) / stripes
        col = 'tent_teal' if k % 2 else 'tent_a'
        for sx in (-1, 1):
            b.quad(M @ Vector((sx * W / 2, y0, 0.3)), M @ Vector((sx * W / 2, y1, 0.3)), M @ Vector((0, y1, H)), M @ Vector((0, y0, H)), col)
    for sy in (-1, 1):
        b.face([M @ Vector((-W / 2, sy * L / 2, 0.3)), M @ Vector((W / 2, sy * L / 2, 0.3)), M @ Vector((0, sy * L / 2, H))], 'tent_a')
        b.face([M @ Vector((-0.8, sy * (L / 2 + 0.01), 0.3)), M @ Vector((0.8, sy * (L / 2 + 0.01), 0.3)), M @ Vector((0, sy * (L / 2 + 0.01), 1.9))], 'shadow')
    for sx in (-1, 1):                                    # guy poles
        for sy in (-1, 1):
            b.cuboid(M @ T(sx * W / 2, sy * L / 2, 0.15) @ S(0.12, 0.12, 0.4), 'wood')
    b.cuboid(M @ T(0, L / 2, H + 0.4) @ S(0.08, 0.08, 1.0), 'wood')
    b.face([M @ Vector((0, L / 2, H + 0.9)), M @ Vector((0, L / 2 + 0.9, H + 0.7)), M @ Vector((0, L / 2, H + 0.5))], 'tent_red')


def round_tent(b, x, y):
    z = ground_h(x, y)
    b.prism(T(x, y, z) @ S(1, 1, 1.4), 10, 3.2, 3.2, 'tent_yellow', colour_fn=lambda i: 'tent_orange' if i % 2 else 'tent_yellow')
    b.prism(T(x, y, z + 1.4) @ S(1, 1, 2.4), 10, 3.4, 0.0, 'tent_orange', colour_fn=lambda i: 'tent_red' if i % 2 else 'tent_orange')
    b.cuboid(T(x, y, z + 4.1) @ S(0.08, 0.08, 1.0), 'wood')
    b.face([(x, y, z + 4.6), (x + 0.9, y, z + 4.4), (x, y, z + 4.2)], 'tent_teal')
    # a campfire in front
    fx, fy = x + 4.0, y + 3.0
    for k in range(6):
        a = 2 * math.pi * k / 6
        b.blob(T(fx + 0.7 * math.cos(a), fy + 0.7 * math.sin(a), 0.1) @ S(0.3, 0.3, 0.22), lambda i: 'rock_dark', k)
    b.prism(T(fx, fy, 0.0) @ S(1, 1, 1.1), 5, 0.45, 0.0, 'tent_orange')
    b.prism(T(fx, fy, 0.0) @ S(1, 1, 0.7), 5, 0.3, 0.0, 'tent_yellow', phase=0.6)


def gateway(b):
    x, y = GATE
    z = ground_h(x, y) - 0.3
    face = math.atan2(46 - y, -x) - math.pi / 2
    M = T(x, y, z) @ R(face, 'Z')
    for sx in (-1, 1):
        b.cuboid(M @ T(sx * 2.6, 0, 3.2) @ S(1.6, 1.8, 6.4), 'ruin', 'ruin_dark')
        b.cuboid(M @ T(sx * 2.6, 0, 6.6) @ S(2.0, 2.2, 0.4), 'ruin_dark')
    b.cuboid(M @ T(0, 0, 7.4) @ S(7.4, 2.0, 1.2), 'ruin', 'ruin_dark')
    for k in range(4):                                    # crenellations
        b.cuboid(M @ T(-2.7 + k * 1.8, 0, 8.3) @ S(0.8, 1.6, 0.6), 'ruin')
    for sx, ln in ((-1, 7.0), (1, 4.0)):                  # broken walls either side
        b.cuboid(M @ T(sx * (3.4 + ln / 2), 0.2, 1.4) @ S(ln, 1.0, 2.8), 'ruin', 'ruin_dark')
    for k in range(5):                                    # tumbled blocks
        b.cuboid(M @ T(rng.uniform(-8, 8), rng.uniform(2, 5), 0.35) @ R(rng.uniform(0, 1), 'Z') @ S(1.1, 0.9, 0.7), 'ruin_dark', 'ruin')


def camel(b, x, y, heading, s, rider=False):
    M = T(x, y, ground_h(x, y)) @ R(heading, 'Z') @ S(s, s, s)
    b.cuboid(M @ T(0, 0, 1.6) @ S(2.0, 0.85, 0.8), 'camel')
    b.prism(M @ T(-0.05, 0, 1.9) @ S(1, 1, 0.75), 6, 0.6, 0.0, 'camel', colour_fn=lambda i: 'camel_dark' if i % 3 == 0 else 'camel')
    b.cuboid(M @ T(1.2, 0, 2.05) @ R(-0.5, 'Y') @ S(0.36, 0.34, 1.1), 'camel')
    b.cuboid(M @ T(1.62, 0, 2.55) @ S(0.62, 0.32, 0.32), 'camel')
    for sx in (-0.7, 0.7):
        for sy in (-0.28, 0.28):
            b.cuboid(M @ T(sx, sy, 0.6) @ S(0.2, 0.2, 1.2), 'camel_dark')
    b.cuboid(M @ T(-1.05, 0, 1.55) @ R(0.4, 'Y') @ S(0.08, 0.08, 0.6), 'camel_dark')
    b.cuboid(M @ T(-0.55, 0, 2.02) @ S(0.8, 0.9, 0.08), 'blanket')
    for sy in (-0.46, 0.46):
        b.cuboid(M @ T(-0.55, sy, 1.75) @ S(0.8, 0.04, 0.55), 'blanket')
    if rider:
        b.cuboid(M @ T(-0.55, 0, 2.45) @ S(0.4, 0.45, 0.8), 'tent_blue')
        b.cuboid(M @ T(-0.55, 0, 3.0) @ S(0.34, 0.34, 0.34), 'tent_a')
    else:
        for sy in (-0.5, 0.5):                            # saddle bags
            b.cuboid(M @ T(-0.55, sy, 1.55) @ S(0.5, 0.2, 0.45), 'tent_teal')


def caravan(b):
    """Four camels walking along a dune crest, high enough to show over the palm canopy."""
    for k, (x, s) in enumerate(((13.0, 2.1), (5.0, 2.0), (-3.0, 2.0), (-10.5, 1.5))):
        y = max((CARAVAN_Y - 0.5 * i for i in range(50)), key=lambda yy: ground_h(x, yy))
        camel(b, x, y, math.pi, s, rider=(k == 0))


def cacti(b):
    n = 0
    while n < 18:
        x, y = rng.uniform(-110, 110), rng.uniform(-160, 40)
        if not ok_spot(x, y, 4) or rr_sdf(x, y) < 14:
            continue
        z = ground_h(x, y) - 0.2
        h = rng.uniform(3.0, 5.0)
        cf = lambda i: 'cactus_dark' if i % 2 else 'cactus'
        b.prism(T(x, y, z) @ S(1, 1, h), 6, 0.42, 0.36, 'cactus', cap='cactus_dark', colour_fn=cf)
        for sgn in (-1, 1):
            if rng.random() < 0.8:
                a = rng.uniform(0, math.pi) + (0 if sgn > 0 else math.pi)
                ah = h * rng.uniform(0.35, 0.55)
                ox, oy = math.cos(a) * 1.0, math.sin(a) * 1.0
                b.cuboid(T(x + ox / 2, y + oy / 2, z + ah) @ R(a, 'Z') @ S(1.0, 0.5, 0.5), 'cactus')
                b.prism(T(x + ox, y + oy, z + ah - 0.2) @ S(1, 1, h * 0.35), 6, 0.3, 0.26, 'cactus', cap='cactus_dark', colour_fn=cf)
        n += 1


def rocks(b):
    n = 0
    while n < 40:
        x, y = rng.uniform(-120, 120), rng.uniform(-170, 50)
        if not ok_spot(x, y, 1):
            continue
        s = rng.uniform(0.8, 2.8)
        base = rng.choice(('rock', 'rock_light', 'rock'))
        b.blob(T(x, y, ground_h(x, y) + s * 0.15) @ R(rng.uniform(0, 6.3), 'Z') @ S(s * 1.4, s, s * 0.8),
               lambda i, base=base: 'rock_dark' if i % 5 == 0 else base, rng.uniform(0, 50), subdiv=2 if s > 2 else 1)
        n += 1


def buttes(b):
    """Flat-topped sandstone buttes on the horizon."""
    for a_deg, r, h, rad in ((-100, 250, 34, 22), (-72, 262, 26, 16), (-128, 238, 30, 18), (-88, 205, 18, 12),
                             (-40, 230, 24, 20), (-150, 225, 28, 17), (10, 250, 22, 18), (170, 245, 26, 20),
                             (-112, 180, 14, 9), (-58, 190, 16, 11)):
        a = math.radians(a_deg)
        x, y = r * math.cos(a), r * math.sin(a)
        z = ground_h(x, y) - 3
        b.prism(T(x, y, z) @ S(1, 1, h * 0.55), 9, rad * 1.35, rad * 1.05, 'butte', colour_fn=lambda i: 'butte_dark' if i % 3 == 0 else 'butte')
        b.prism(T(x, y, z + h * 0.55) @ S(1, 1, h * 0.08), 9, rad * 1.05, rad * 1.05, 'rock_light')
        b.prism(T(x, y, z + h * 0.63) @ S(1, 1, h * 0.37), 9, rad * 1.05, rad * 0.92, 'butte', cap='rock_light',
                colour_fn=lambda i: 'butte_dark' if i % 3 == 1 else 'butte')


def build_scenery(mat):
    b = Builder()
    build_ground(b)
    adobe_wall(b)
    goals(b, 'post', 'net')
    pond(b)
    palms(b)
    market_stall(b)
    for x, y, rot in TENTS:
        tent(b, x, y, rot)
    round_tent(b, *ROUND_TENT)
    gateway(b)
    caravan(b)
    cacti(b)
    rocks(b)
    buttes(b)
    return b.to_object('scenery', mat)


def main():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    img = build_palette()
    mats = {n: make_material(n, img) for n in ('turf', 'scenery', 'sky')}
    objs = [build_turf(mats['turf']), build_scenery(mats['scenery']), build_sky(mats['sky'])]
    export(objs)
    argv = sys.argv[sys.argv.index('--') + 1:] if '--' in sys.argv else []
    if '--preview' in argv:
        preview('#ffd9a8', argv)


main()
