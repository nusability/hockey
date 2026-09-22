"""
Builds the Deep Space world (spec §13): a floating arena adrift among the stars.

The pitch sits on a hovering deck with a tapered hull, thruster pods and floodlight masts; around
it drift two dashed halo rings, an asteroid belt, a banded gas giant and a ringed ice planet behind
the far goal, a cratered moon, a wheel station and a starfield. Field hockey (corner radius 2.0).

One scene, two exports: `space.glb` (Filament, Android) and `space.usdz` (RealityKit, iOS), plus
`palette.png`. Deterministic: the same script always writes the same world.

Run: tools/build-worlds.sh  (Blender 5, headless). Preview from the play camera:
  Blender --background --factory-startup --python build_space.py -- --preview [--wide PATH]

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

WORLD = 'space'
HERE = os.path.dirname(os.path.abspath(__file__))
rng = random.Random(4207)

HW, HL = 15.0, 30.0          # pitch half-extents (spec §1)
CORNER = 2.0                 # field hockey corner radius
GOAL_Z, GOAL_W, GOAL_D = 26.0, 6.0, 1.6
SKY_R = 320.0

# ---------------------------------------------------------------- palette
SWATCH = {
    'turf_a': '#26335e', 'turf_b': '#1f2a50', 'line': '#7df9ff', 'line_pink': '#f0abfc',
    'deck': '#222d52', 'deck_light': '#3a4a80', 'hull': '#46568e', 'hull_dark': '#161d38',
    'neon_c': '#67e8f9', 'neon_p': '#e879f9', 'wall': '#0369a1', 'wall_top': '#67e8f9',
    'post': '#f472b6', 'net': '#bae6fd', 'flame': '#60c8ff', 'lamp': '#fff6c8',
    'giant_a': '#f3dcae', 'giant_b': '#e6b98a', 'giant_c': '#d98a6a', 'giant_d': '#a45c6b',
    'giant_e': '#8b5a97', 'giant_f': '#f6e7c9', 'ice_a': '#cfe6ff', 'ice_b': '#7fb0e6',
    'ring_a': '#e6f2ff', 'ring_b': '#a9cdf7', 'moon': '#b4b3c2', 'moon_dark': '#7b7a8c',
    'rock': '#8b7f78', 'rock_dark': '#5e5250', 'rock_warm': '#a8876f', 'station': '#d4d9e3',
    'panel': '#2563eb', 'star': '#ffffff', 'star_warm': '#ffe3a8', 'star_blue': '#b9dcff',
    'hazard': '#fde047', 'core': '#a5f3fc',
}
# the sky gradient, bottom (below/at the horizon) to top (zenith)
SKY = [(0.0, '#2d1458'), (0.25, '#22114a'), (0.55, '#0d0c2e'), (1.0, '#03040d')]


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
def build_turf(mat):
    b = Builder()
    turf_bands(b, 12, 'turf_a', 'turf_b')
    z, w = 0.02, 0.12
    for y in (-GOAL_Z, GOAL_Z, 0.0):                      # goal lines and centre line
        cross_line(b, y, w, 'line', z)
    for y in (-15.0, 15.0):                               # the 23 m lines
        cross_line(b, y, 0.08, 'line', z)
    for sign in (-1, 1):                                  # shooting circles, penalty spots
        cy = sign * GOAL_Z
        b.arc(0, cy, z, 9.0, w, math.pi if sign > 0 else 0, 2 * math.pi if sign > 0 else math.pi, 28, 'line')
        b.arc(0, cy, z, 11.0, 0.08, math.pi if sign > 0 else 0, 2 * math.pi if sign > 0 else math.pi, 28, 'line_pink', dashed=True)
        b.disc(0, cy - sign * 6.4, z, 0.22, 8, 'line')
    b.disc(0, 0, z, 0.25, 10, 'line')
    b.arc(0, 0, z, 4.2, 0.07, 0, 2 * math.pi, 40, 'line_pink')    # centre orbit rings
    b.arc(0, 0, z, 5.6, 0.07, 0, 2 * math.pi, 48, 'line_pink')
    b.arc(0, 0, z, 7.2, 0.1, 0, 2 * math.pi, 48, 'line', dashed=True)
    return b.to_object('turf', mat)


def offset_ring(o, z, per=6, r=CORNER):
    return [(x, y, z) for x, y in rounded_rect(HW + o, HL + o, r + o, per)]


def build_platform(b):
    """The floating deck: flat plating out to 4.5 beyond the boundary, a rim, a tapered hull."""
    per = 6
    ring0 = offset_ring(0.0, -0.02, per)
    ring1 = offset_ring(4.5, -0.02, per)
    # deck plates between neon inlays (the inlays are coplanar strips a hair above)
    b.strip(ring0, ring1, 'deck')
    for o0, o1, col in ((0.75, 0.95, 'neon_c'), (2.0, 2.3, 'neon_p'), (3.9, 4.05, 'neon_c')):
        b.strip(offset_ring(o0, 0.01, per), offset_ring(o1, 0.01, per), col)
    # rim, neon band, hull tapering to a keel far below
    rim_lo = offset_ring(4.5, -1.3, per)
    b.strip(ring1, offset_ring(4.5, -0.5, per), 'deck_light')
    b.strip(offset_ring(4.5, -0.5, per), offset_ring(4.5, -0.8, per), 'neon_c')
    b.strip(offset_ring(4.5, -0.8, per), rim_lo, 'deck_light')
    mid = offset_ring(2.0, -4.5, per)
    b.strip(rim_lo, mid, 'hull')
    keel = offset_ring(-6.0, -10.0, per)
    b.strip(mid, keel, 'hull_dark')
    b.face([p for p in reversed(keel)], 'hull_dark')
    # a glowing core hanging under the keel
    b.prism(T(0, 0, -16) @ S(1, 1, 6), 12, 2.2, 5.5, 'core')
    b.prism(T(0, 0, -19) @ S(1, 1, 3), 12, 0.0001, 2.2, 'neon_c')
    # boundary wall with a glowing top rail
    wall_ring(b, CORNER, 0.15, 0.0, 1.1, 0.3, 'wall', 'wall_top')
    # glow studs on the wall top
    for x, y, a in along_ring(rounded_rect(HW + 0.3, HL + 0.3, CORNER + 0.3, per), 64):
        b.box(x, y, 1.1, 0.22, 0.22, 0.14, 'lamp', rot=a)


def thruster_pod(b, x, y, face):
    """A pod on an arm, jutting out from the rim; `face` is the outward direction (radians)."""
    dx, dy = math.cos(face), math.sin(face)
    ax, ay = x - dx * 3.0, y - dy * 3.0
    b.cuboid(T((x + ax) / 2, (y + ay) / 2, -1.2) @ R(face, 'Z') @ S(3.2, 0.9, 0.7), 'deck_light', 'hull')
    b.prism(T(x, y, -3.6) @ S(1, 1, 3.6), 8, 1.3, 1.5, 'hull', cap='deck_light')
    b.prism(T(x, y, -1.4) @ S(1, 1, 0.35), 8, 1.56, 1.56, 'neon_p')
    b.prism(T(x, y, 0.0) @ S(1, 1, 0.6), 8, 1.5, 0.6, 'deck_light', cap='neon_c')
    b.prism(T(x, y, -3.6) @ R(math.pi, 'X') @ S(1, 1, 2.8), 8, 1.1, 0.0, 'flame')
    b.prism(T(x, y, -3.6) @ R(math.pi, 'X') @ S(1, 1, 1.4), 8, 1.35, 0.9, 'core')


def mast(b, x, y):
    """A floodlight mast on the deck corner: a lattice-ish pole and a lamp head facing the pitch."""
    b.prism(T(x, y, 0) @ S(1, 1, 14), 6, 0.45, 0.25, 'deck_light')
    for z in (3.5, 7.0, 10.5):
        b.prism(T(x, y, z) @ S(1, 1, 0.3), 6, 0.55, 0.5, 'neon_c')
    face = math.atan2(-y, -x)
    b.cuboid(T(x, y, 14.6) @ R(face, 'Z') @ R(-0.5, 'Y') @ S(1.0, 3.2, 1.8), 'hull', 'deck_light')
    b.cuboid(T(x + math.cos(face) * 0.55, y + math.sin(face) * 0.55, 14.3) @ R(face, 'Z') @ R(-0.5, 'Y') @ S(0.2, 2.8, 1.5), 'lamp')


def halo_ring(b, radius, z, tilt_x, tilt_y, seg, colour, width, gap):
    M = T(0, 0, z) @ R(tilt_x, 'X') @ R(tilt_y, 'Y')
    for i in range(seg):
        if i % gap == gap - 1:
            continue
        a = 2 * math.pi * (i + 0.5) / seg
        length = 2 * math.pi * radius / seg * 0.82
        b.cuboid(M @ T(radius * math.cos(a), radius * math.sin(a), 0) @ R(a + math.pi / 2, 'Z') @ S(length, width, width), colour)


def gas_giant(b, c, radius):
    bands = ['giant_f', 'giant_a', 'giant_b', 'giant_c', 'giant_a', 'giant_d', 'giant_b', 'giant_e',
             'giant_c', 'giant_a', 'giant_f', 'giant_b', 'giant_d', 'giant_a', 'giant_e', 'giant_b',
             'giant_c', 'giant_a']
    M = T(*c) @ R(0.28, 'Y') @ R(0.2, 'X') @ S(radius, radius, radius * 0.94)
    # a storm spot: two faces on one band use the dark swatch
    b.sphere(M, 36, 18, lambda r, s: 'giant_d' if (r == 11 and s in (5, 6)) else bands[r])


def ringed_planet(b, c, radius):
    M = T(*c) @ R(-0.35, 'Y') @ S(radius, radius, radius)
    b.sphere(M, 24, 12, lambda r, s: 'ice_b' if r in (3, 7, 8) else ('ring_a' if r in (1, 10) else 'ice_a'))
    Mr = T(*c) @ R(0.32, 'X') @ R(-0.3, 'Y')
    for r0, r1, col in ((1.35, 1.7, 'ring_b'), (1.76, 2.15, 'ring_a')):
        a_pts = [Mr @ Vector((radius * r0 * math.cos(2 * math.pi * i / 48), radius * r0 * math.sin(2 * math.pi * i / 48), 0)) for i in range(48)]
        b_pts = [Mr @ Vector((radius * r1 * math.cos(2 * math.pi * i / 48), radius * r1 * math.sin(2 * math.pi * i / 48), 0)) for i in range(48)]
        b.strip(a_pts, b_pts, col)


def moon(b, c, radius):
    M = T(*c) @ R(0.4, 'X') @ S(radius, radius, radius)
    crater = {(rng.randrange(2, 12), rng.randrange(0, 20)) for _ in range(26)}
    b.sphere(M, 20, 14, lambda r, s: 'moon_dark' if (r, s) in crater else 'moon')


def station(b, c, radius, tilt):
    M = T(*c) @ R(tilt, 'X') @ R(0.5, 'Y')
    seg, side, minor = 28, 6, radius * 0.1
    for i in range(seg):                                  # the wheel: a coarse torus
        for j in range(side):
            def p(ii, jj):
                a, t = 2 * math.pi * ii / seg, 2 * math.pi * jj / side
                rr = radius + minor * math.cos(t)
                return M @ Vector((rr * math.cos(a), rr * math.sin(a), minor * math.sin(t)))
            col = 'neon_c' if (j == 0 and i % 4 == 0) else 'station'
            b.quad(p(i, j), p(i + 1, j), p(i + 1, j + 1), p(i, j + 1), col)
    for k in range(4):                                    # spokes
        a = math.pi / 2 * k + math.pi / 4
        b.cuboid(M @ T(radius / 2 * math.cos(a), radius / 2 * math.sin(a), 0) @ R(a, 'Z') @ S(radius, minor * 0.6, minor * 0.6), 'station')
    b.prism(M @ T(0, 0, -radius * 0.35) @ S(1, 1, radius * 0.7), 8, radius * 0.18, radius * 0.18, 'station', cap='deck_light', bottom=True)
    for sgn in (-1, 1):                                   # solar wings on the hub axis
        b.cuboid(M @ T(0, 0, sgn * radius * 0.6) @ S(radius * 1.4, radius * 0.35, 0.2), 'panel')
        b.cuboid(M @ T(0, 0, sgn * radius * 0.48) @ S(0.3, 0.3, radius * 0.25), 'station')


def satellite(b, c, yaw):
    M = T(*c) @ R(yaw, 'Z') @ R(0.4, 'X')
    b.cuboid(M @ S(1.4, 1.4, 1.8), 'station', 'hazard')
    for sgn in (-1, 1):
        b.cuboid(M @ T(sgn * 2.6, 0, 0) @ S(3.2, 1.2, 0.08), 'panel')
    b.prism(M @ T(0, 0, 0.9) @ S(1, 1, 0.8), 8, 0.0001, 0.9, 'station')


def asteroids(b):
    placed = 0
    while placed < 95:
        a = rng.uniform(0, 2 * math.pi)
        rad = rng.uniform(58, 150)
        x, y = rad * math.cos(a), rad * math.sin(a) * 1.15
        z = rng.uniform(-26, 6) + 6 * math.sin(a * 2)
        if y > 40 and abs(x) < 40:                        # behind the camera: nobody sees these
            continue
        size = rng.uniform(1.2, 4.2) * (1.6 if rng.random() < 0.12 else 1.0)
        seed = rng.uniform(0, 100)
        rot = R(rng.uniform(0, 6.3), 'Z') @ R(rng.uniform(0, 6.3), 'X')
        tone = rng.random()
        dark = {rng.randrange(20) for _ in range(4)}
        base = 'rock_warm' if tone < 0.3 else 'rock'
        b.blob(T(x, y, z) @ rot @ S(size, size * rng.uniform(0.7, 1.0), size * rng.uniform(0.6, 0.9)),
               lambda i, dark=dark, base=base: 'rock_dark' if i in dark else base, seed)
        placed += 1


def starfield(b):
    cols = ['star'] * 5 + ['star_warm'] * 2 + ['star_blue'] * 2
    n = 0
    while n < 3200:
        # half the stars in the band the play camera sees: a little below the horizon, ahead
        z = rng.uniform(-1, 1) if n % 2 else rng.uniform(-0.45, 0.12)
        t = rng.uniform(0, 2 * math.pi)
        rr = math.sqrt(1 - z * z)
        d = Vector((rr * math.cos(t), rr * math.sin(t), z))
        if d.y > 0.55 and d.z < 0.2:                      # behind the camera, low
            continue
        if n % 2 == 0 and (d.y > -0.6 or rng.random() < 0.55):   # the ahead band: far end, sparser
            continue
        c = d * rng.uniform(300, 312)
        u = d.cross(Vector((0, 0, 1)))
        if u.length < 1e-3:
            u = Vector((1, 0, 0))
        u.normalize()
        v = d.cross(u).normalized()
        big = rng.random()
        s = rng.uniform(1.6, 2.4) if big > 0.97 else rng.uniform(0.8, 1.3) if big > 0.8 else rng.uniform(0.4, 0.75)
        col = rng.choice(cols)
        b.face([c + u * s, c + v * s, c - u * s, c - v * s], col)
        if big > 0.97:                                    # a twinkle cross on the brightest
            b.face([c + (u + v) * s * 0.5, c + (v - u) * s * 0.5, c - (u + v) * s * 0.5, c + (u - v) * s * 0.5], col)
        n += 1


def build_scenery(mat):
    b = Builder()
    build_platform(b)
    goals(b, 'post', 'net')
    for x, y, face in ((HW + 7.0, -14, 0), (HW + 7.0, 14, 0), (-HW - 7.0, -14, math.pi), (-HW - 7.0, 14, math.pi),
                       (8, -HL - 7.0, -math.pi / 2), (-8, -HL - 7.0, -math.pi / 2), (8, HL + 7.0, math.pi / 2), (-8, HL + 7.0, math.pi / 2)):
        thruster_pod(b, x, y, face)
    for sx in (-1, 1):
        for sy in (-1, 1):
            mast(b, sx * (HW + 2.9), sy * (HL + 2.9))
    halo_ring(b, 46, -3.0, 0.1, 0.06, 72, 'neon_c', 0.55, 3)
    halo_ring(b, 54, -5.5, -0.08, -0.1, 84, 'neon_p', 0.4, 4)
    gas_giant(b, (-78, -212, -14), 58)
    ringed_planet(b, (74, -236, -4), 15)
    moon(b, (165, -95, -12), 22)
    moon(b, (-120, -150, 30), 9)
    station(b, (-150, -60, 8), 16, 1.0)
    satellite(b, (38, -78, 6), 0.6)
    satellite(b, (-72, 20, 14), 2.0)
    asteroids(b)
    starfield(b)
    return b.to_object('scenery', mat)


def main():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    img = build_palette()
    mats = {n: make_material(n, img) for n in ('turf', 'scenery', 'sky')}
    objs = [build_turf(mats['turf']), build_scenery(mats['scenery']), build_sky(mats['sky'])]
    export(objs)
    argv = sys.argv[sys.argv.index('--') + 1:] if '--' in sys.argv else []
    if '--preview' in argv:
        preview('#39407a', argv)


main()
