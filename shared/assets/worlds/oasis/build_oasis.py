"""
Builds the Oasis placeholder world for the renderer spike (Stori SMASH-2, ADR 0005).

One scene, two exports: `oasis.glb` (Filament, Android) and `oasis.usdz` (RealityKit, iOS), so
both platforms load the same geometry and the same palette texture. Deterministic: the same
script always writes the same world.

Run: tools/build-worlds.sh  (Blender 5, headless)

Coordinates: Blender is Z-up; the exporters convert to Y-up, where the game's pitch lies in X-Z
with Z along the pitch (spec §1). Blender's -Y is the game's +Z.

Materials are bound **by name** on each platform (ADR 0005): `turf`, `scenery`, `sky`. All three
sample one palette texture, so colours never live in vertex attributes either engine might drop.
"""
import math
import os
import random

import bmesh
import bpy

HERE = os.path.dirname(os.path.abspath(__file__))
rng = random.Random(7)

HW, HL = 15.0, 30.0          # pitch half-extents (spec §1)
CORNER = 2.0                 # field hockey corner radius
GOAL_Z, GOAL_W, GOAL_D = 26.0, 6.0, 1.6

# ---------------------------------------------------------------- palette texture
# 16 swatches in a 4x4 grid on the left half; a vertical sky gradient in the right half.
TEX = 256
SWATCH = {
    'turf_a': (0.22, 0.55, 0.24), 'turf_b': (0.20, 0.50, 0.22), 'line': (0.97, 0.97, 0.93),
    'sand': (0.93, 0.78, 0.52), 'sand_dark': (0.84, 0.64, 0.40), 'wall': (0.55, 0.33, 0.18),
    'wall_top': (0.96, 0.63, 0.23), 'trunk': (0.52, 0.36, 0.22), 'leaf': (0.24, 0.62, 0.30),
    'leaf_dark': (0.16, 0.46, 0.24), 'water': (0.16, 0.66, 0.72), 'rock': (0.66, 0.52, 0.42),
    'post': (1.0, 1.0, 1.0), 'net': (0.86, 0.88, 0.90), 'slab': (0.45, 0.30, 0.22), 'flag': (0.94, 0.30, 0.36),
}
NAMES = list(SWATCH)
SKY_TOP, SKY_HORIZON = (0.20, 0.52, 0.86), (1.0, 0.86, 0.62)


def swatch_uv(name):
    i = NAMES.index(name)
    cx, cy = i % 4, i // 4
    return ((cx + 0.5) / 8.0, 1.0 - (cy + 0.5) / 4.0)   # left half: 4 columns of width 1/8


def build_palette():
    img = bpy.data.images.new('palette', TEX, TEX, alpha=False)
    px = [0.0] * (TEX * TEX * 4)
    for y in range(TEX):
        for x in range(TEX):
            if x < TEX // 2:
                cx, cy = x // (TEX // 8), (TEX - 1 - y) // (TEX // 4)
                c = SWATCH[NAMES[cy * 4 + cx]]
            else:
                t = y / (TEX - 1)                          # 0 bottom (horizon) .. 1 top
                c = tuple(SKY_HORIZON[k] + (SKY_TOP[k] - SKY_HORIZON[k]) * t for k in range(3))
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


# ---------------------------------------------------------------- mesh helpers
class Builder:
    """Accumulates triangles with a per-face swatch into one bmesh."""

    def __init__(self):
        self.bm = bmesh.new()
        self.uv = self.bm.loops.layers.uv.new('UVMap')

    def face(self, pts, colour):
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


# ---------------------------------------------------------------- the world
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


def dune_height(x, y):
    d = max(abs(x) - (HW + 6), abs(y) - (HL + 6), 0.0)
    if d <= 0:
        return -0.05
    k = min(1.0, d / 25.0)
    h = 3.5 * math.sin(x * 0.11 + 1.3) * math.cos(y * 0.09) + 2.5 * math.sin(x * 0.05 - y * 0.07) + 4.0
    return max(0.0, h) * k - 0.05


def build_scenery(mat):
    b = Builder()
    # dunes: a grid around the pitch, flat where the pitch and its apron are
    n, size = 72, 180.0
    step = size / n
    for i in range(n):
        for j in range(n):
            x0, y0 = -size / 2 + i * step, -size / 2 + j * step
            x1, y1 = x0 + step, y0 + step
            if max(abs(x0), abs(x1)) < HW and max(abs(y0), abs(y1)) < HL:
                continue                                        # the turf covers this
            h = lambda x, y: dune_height(x, y)
            col = 'sand' if (i + j) % 7 else 'sand_dark'
            b.face([(x0, y0, h(x0, y0)), (x1, y0, h(x1, y0)), (x1, y1, h(x1, y1))], col)
            b.face([(x0, y0, h(x0, y0)), (x1, y1, h(x1, y1)), (x0, y1, h(x0, y1))], col)
    # boundary wall on the rounded rectangle, 1.1 high, with a coloured top rail
    ring = rounded_rect(HW + 0.15, HL + 0.15, CORNER + 0.15)
    for k in range(len(ring)):
        (ax, ay), (bx, by) = ring[k], ring[(k + 1) % len(ring)]
        nx, ny = by - ay, -(bx - ax)
        ln = math.hypot(nx, ny)
        ox, oy = nx / ln * 0.3, ny / ln * 0.3
        b.quad((ax, ay, 0), (bx, by, 0), (bx, by, 1.1), (ax, ay, 1.1), 'wall')
        b.quad((bx + ox, by + oy, 0), (ax + ox, ay + oy, 0), (ax + ox, ay + oy, 1.1), (bx + ox, by + oy, 1.1), 'wall')
        b.quad((ax, ay, 1.1), (bx, by, 1.1), (bx + ox, by + oy, 1.1), (ax + ox, ay + oy, 1.1), 'wall_top')
    # goals: posts, crossbar, net box
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
    # pond with rocks
    px, py, pr = -34.0, 18.0, 7.0
    for i in range(24):
        a0, a1 = 2 * math.pi * i / 24, 2 * math.pi * (i + 1) / 24
        b.face([(px, py, 0.06), (px + pr * math.cos(a0), py + pr * math.sin(a0), 0.06),
                (px + pr * math.cos(a1), py + pr * math.sin(a1), 0.06)], 'water')
        if i % 3 == 0:
            rx, ry = px + (pr + 0.6) * math.cos(a0), py + (pr + 0.6) * math.sin(a0)
            b.box(rx, ry, 0, 1.2, 1.0, 0.7 + rng.random() * 0.6, 'rock')
    # palms: a bent trunk and seven fronds each
    placed = 0
    while placed < 120:
        x, y = rng.uniform(-80, 80), rng.uniform(-80, 80)
        if abs(x) < HW + 5 and abs(y) < HL + 5:
            continue
        if math.hypot(x - px, y - py) < pr + 2:
            continue
        palm(b, x, y, dune_height(x, y), rng.uniform(6, 10), rng.uniform(0, 2 * math.pi))
        placed += 1
    # corner flags
    for sx in (-1, 1):
        for sy in (-1, 1):
            b.box(sx * (HW - 0.6), sy * (HL - 0.6), 0, 0.08, 0.08, 1.6, 'post')
            b.face([(sx * (HW - 0.6), sy * (HL - 0.6), 1.6), (sx * (HW - 0.6), sy * (HL - 0.6), 1.2),
                    (sx * (HW - 0.6) + 0.6, sy * (HL - 0.6), 1.4)], 'flag')
    return b.to_object('scenery', mat)


def palm(b, x, y, z, height, lean):
    seg, rings = 6, 6
    bend = 0.18 * height
    rings_pts = []
    for r in range(rings + 1):
        t = r / rings
        cx = x + math.cos(lean) * bend * t * t
        cy = y + math.sin(lean) * bend * t * t
        rad = 0.32 - 0.12 * t
        rings_pts.append([(cx + rad * math.cos(2 * math.pi * s / seg), cy + rad * math.sin(2 * math.pi * s / seg), z + height * t) for s in range(seg)])
    for r in range(rings):
        for s in range(seg):
            a, bb = rings_pts[r][s], rings_pts[r][(s + 1) % seg]
            c, d = rings_pts[r + 1][(s + 1) % seg], rings_pts[r + 1][s]
            b.quad(a, bb, c, d, 'trunk')
    top = (x + math.cos(lean) * bend, y + math.sin(lean) * bend, z + height)
    fronds = 7
    for f in range(fronds):
        a = 2 * math.pi * f / fronds + rng.uniform(-0.2, 0.2)
        length = rng.uniform(3.0, 4.2)
        dx, dy = math.cos(a), math.sin(a)
        px_, py_ = -dy, dx
        pts = []
        for k in range(5):
            t = k / 4
            w = 0.7 * math.sin(math.pi * min(t, 0.95)) + 0.05
            cx, cy = top[0] + dx * length * t, top[1] + dy * length * t
            cz = top[2] + 0.6 * t - 1.8 * t * t
            pts.append(((cx - px_ * w, cy - py_ * w, cz), (cx + px_ * w, cy + py_ * w, cz), (cx, cy, cz + 0.12)))
        col = 'leaf' if f % 2 else 'leaf_dark'
        for k in range(4):
            l0, r0, m0 = pts[k]
            l1, r1, m1 = pts[k + 1]
            b.quad(l0, m0, m1, l1, col)
            b.quad(m0, r0, r1, m1, col)


def build_sky(mat):
    bm = bmesh.new()
    uv = bm.loops.layers.uv.new('UVMap')
    bmesh.ops.create_uvsphere(bm, u_segments=32, v_segments=12, radius=320.0)
    bmesh.ops.reverse_faces(bm, faces=bm.faces)                # seen from inside
    for f in bm.faces:
        for loop in f.loops:
            zn = max(0.0, loop.vert.co.z / 320.0)
            # right half: the gradient; the power pulls the blue down toward the horizon, where the
            # camera actually sees the sky
            loop[uv].uv = (0.75, 0.02 + 0.96 * zn ** 0.35)
    mesh = bpy.data.meshes.new('sky')
    bm.to_mesh(mesh)
    bm.free()
    mesh.materials.append(mat)
    obj = bpy.data.objects.new('sky', mesh)
    bpy.context.scene.collection.objects.link(obj)
    return obj


def main():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    img = build_palette()
    mats = {n: make_material(n, img) for n in ('turf', 'scenery', 'sky')}
    objs = [build_turf(mats['turf']), build_scenery(mats['scenery']), build_sky(mats['sky'])]
    tris = sum(sum(len(p.vertices) - 2 for p in o.data.polygons) for o in objs)
    print(f'oasis: {tris} triangles in {len(objs)} meshes')
    bpy.ops.export_scene.gltf(filepath=os.path.join(HERE, 'oasis.glb'), export_format='GLB',
                              export_apply=True, export_yup=True)
    bpy.ops.wm.usd_export(filepath=os.path.join(HERE, 'oasis.usdz'), export_materials=True,
                          generate_preview_surface=True, export_textures_mode='NEW', relative_paths=True,
                          convert_orientation=True, export_global_forward_selection='NEGATIVE_Z',
                          export_global_up_selection='Y')


main()
