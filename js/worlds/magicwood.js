// Magic Wood — an enchanted forest clearing at dusk.
//
// Layers (near → far): hedge blobs and ferns hugging the wall, glowing
// lantern-mushrooms with warm ground glow and fireflies, moss stones and
// violet crystals, a glowing stream with a crooked plank bridge on the east
// side, five giant gnarled hero trees (one merged shadow-casting mesh) with
// hanging vines, a ring of standing stones with a floating altar crystal
// behind the far goal, an instanced ring of far trees and drifting mist.
// Everything repeated is an InstancedMesh or merged geometry; update() only
// touches a handful of uniforms/materials and one small object.

const CLEAR_X = 15.5, CLEAR_Z = 30.5; // nothing inside the wall
const streamX = (z) => 24.5 + 2.4 * Math.sin(z * 0.11) + 1.1 * Math.sin(z * 0.31 + 1);

// ------------------------------------------------------------------ helpers
function sdRoundRect(x, z, hw, hl, rr) {
  const qx = Math.abs(x) - (hw - rr), qz = Math.abs(z) - (hl - rr);
  return Math.hypot(Math.max(qx, 0), Math.max(qz, 0)) + Math.min(Math.max(qx, qz), 0) - rr;
}

// Set a per-vertex colour attribute from fn(color, x, y, z, i).
function paint(THREE, g, fn) {
  const p = g.attributes.position, n = p.count, c = new Float32Array(n * 3), col = new THREE.Color();
  for (let i = 0; i < n; i++) {
    fn(col, p.getX(i), p.getY(i), p.getZ(i), i);
    c[i * 3] = col.r; c[i * 3 + 1] = col.g; c[i * 3 + 2] = col.b;
  }
  g.setAttribute('color', new THREE.BufferAttribute(c, 3));
  return g;
}

// Merge geometries (position / normal / color) into one non-indexed geometry.
function merge(THREE, list) {
  const parts = list.map((g) => (g.index ? g.toNonIndexed() : g));
  let total = 0;
  for (const g of parts) total += g.attributes.position.count;
  const pos = new Float32Array(total * 3), nor = new Float32Array(total * 3), col = new Float32Array(total * 3);
  let off = 0;
  for (const g of parts) {
    const n = g.attributes.position.count;
    pos.set(g.attributes.position.array, off * 3);
    if (g.attributes.normal) nor.set(g.attributes.normal.array, off * 3);
    if (g.attributes.color) col.set(g.attributes.color.array, off * 3); else col.fill(1, off * 3, (off + n) * 3);
    off += n;
  }
  const out = new THREE.BufferGeometry();
  out.setAttribute('position', new THREE.BufferAttribute(pos, 3));
  out.setAttribute('normal', new THREE.BufferAttribute(nor, 3));
  out.setAttribute('color', new THREE.BufferAttribute(col, 3));
  for (const g of list) g.dispose();
  for (const g of parts) g.dispose();
  return out;
}

// Jittered icosahedron blob, scaled (sx, sy, sz).
function blob(THREE, r, detail, sx, sy, sz, jitter, rand) {
  const g = new THREE.IcosahedronGeometry(r, detail);
  const p = g.attributes.position;
  for (let i = 0; i < p.count; i++) {
    const k = 1 + rand(-jitter, jitter);
    p.setXYZ(i, p.getX(i) * k * sx, p.getY(i) * k * sy, p.getZ(i) * k * sz);
  }
  g.computeVertexNormals();
  return g;
}

// Gnarled tapered trunk built from rings. Returns { geom, centre(t), radius(t) }.
function trunk(THREE, o) {
  const { h, r0, r1, rings = 12, radial = 10, seed = 0, lean = [0, 0], twist = 1, flare = 0.8, bump = 0.15, wiggle = 0.05 } = o;
  const centre = (t) => [lean[0] * t * t * h + Math.sin(t * 4 + seed) * wiggle * h, t * h, lean[1] * t * t * h + Math.cos(t * 3.3 + seed * 1.7) * wiggle * h];
  const radius = (t) => (r0 + (r1 - r0) * Math.pow(t, 0.7)) * (1 + flare * Math.pow(1 - t, 7));
  const pos = [], idx = [];
  for (let i = 0; i <= rings; i++) {
    const t = i / rings, [cx, y, cz] = centre(t), rr = radius(t);
    for (let j = 0; j <= radial; j++) {
      const a = (j / radial) * Math.PI * 2;
      let b = 1 + bump * Math.sin(a * 5 + t * twist * 5 + seed) + bump * 0.7 * Math.sin(a * 3 - t * 7 + seed * 2);
      if (t < 0.22) b += 0.45 * Math.max(0, Math.cos(a * 4 + seed)) * (1 - t / 0.22); // root buttresses
      pos.push(cx + Math.cos(a) * rr * b, y, cz + Math.sin(a) * rr * b);
    }
  }
  for (let i = 0; i < rings; i++) for (let j = 0; j < radial; j++) {
    const a = i * (radial + 1) + j, b = a + radial + 1;
    idx.push(a, b, a + 1, b, b + 1, a + 1);
  }
  const geom = new THREE.BufferGeometry();
  geom.setAttribute('position', new THREE.Float32BufferAttribute(pos, 3));
  geom.setIndex(idx);
  geom.computeVertexNormals();
  return { geom, centre, radius };
}

function orient(THREE, g, from, dir, scale = 1) {
  const q = new THREE.Quaternion().setFromUnitVectors(new THREE.Vector3(0, 1, 0), dir.clone().normalize());
  g.applyMatrix4(new THREE.Matrix4().compose(from, q, new THREE.Vector3(scale, scale, scale)));
  return g;
}

function canvasTex(THREE, size, draw, repeat = 1) {
  const c = document.createElement('canvas');
  c.width = c.height = size;
  draw(c.getContext('2d'), size);
  const t = new THREE.CanvasTexture(c);
  t.colorSpace = THREE.SRGBColorSpace;
  t.wrapS = t.wrapT = THREE.RepeatWrapping;
  t.repeat.set(repeat, repeat);
  return t;
}

// ------------------------------------------------------------------ world
export default {
  id: 'magicwood',
  sport: 'field',
  name: { en: 'Magic Wood', de: 'Zauberwald' },
  tagline: { en: 'A moonlit clearing where the mushrooms glow.', de: 'Eine Waldlichtung im Mondlicht, wo die Pilze leuchten.' },
  sky: 'linear-gradient(180deg, #06071a 0%, #151538 30%, #241d4e 55%, #4a2d63 80%, #7a4470 100%)',
  light: {
    hemiSky: 0x9fb2ff, hemiGround: 0x2a3820, hemiIntensity: 1.1,
    sun: 0xffd6a6, sunIntensity: 1.9, sunPos: [26, 50, -30],
    fog: { color: 0x221d48, near: 58, far: 150 },
  },
  surface: {
    base: '#3b8a48', stripe: '#357f42', lines: '#f3f7ea',
    decorate(ctx, W, H, h) {
      // clover and tiny flowers near the edges only
      const { X, Z, sx, rand } = h;
      const edge = () => {
        const side = Math.random();
        if (side < 0.5) { const x = Math.random() < 0.5 ? rand(-14.4, -12.6) : rand(12.6, 14.4); return [x, rand(-29.4, 29.4)]; }
        const z = Math.random() < 0.5 ? rand(-29.4, -27.4) : rand(27.4, 29.4);
        return [rand(-14.4, 14.4), z];
      };
      for (let i = 0; i < 70; i++) {
        const [x, z] = edge();
        ctx.fillStyle = 'rgba(96,190,104,0.85)';
        for (let k = 0; k < 3; k++) {
          const a = (k / 3) * Math.PI * 2 + rand(0, 1);
          ctx.beginPath(); ctx.arc(X(x) + Math.cos(a) * 3.2, Z(z) + Math.sin(a) * 3.2, 3.2, 0, Math.PI * 2); ctx.fill();
        }
      }
      const petals = ['#ffd9ea', '#fff4bd', '#e6d5ff', '#ffffff', '#ffc4d6'];
      for (let i = 0; i < 130; i++) {
        const [x, z] = edge();
        ctx.fillStyle = petals[Math.floor(Math.random() * petals.length)];
        ctx.beginPath(); ctx.arc(X(x), Z(z), rand(2.2, 4.2), 0, Math.PI * 2); ctx.fill();
        ctx.fillStyle = '#ffb347';
        ctx.beginPath(); ctx.arc(X(x), Z(z), 1.3, 0, Math.PI * 2); ctx.fill();
      }
      void sx;
    },
  },
  border: { color: 0x6b4527, top: 0x8fd14f, height: 1.1, glass: false, base: 0x33291a },
  ball: { color: 0xffffff, emissive: 0x2a2a2a },
  goal: { post: 0xf8fafc, net: 0xe2e8f0 },

  buildScenery(group, ctx) {
    try { return build(group, ctx); }
    catch (e) { console.error('magicwood scenery failed', e); return { update() {} }; }
  },
};

function build(group, ctx) {
  const { THREE, HW, HL, corner, rand, pick, lerp } = ctx;
  const C = (hex) => new THREE.Color(hex);
  const GROUND = -0.64;
  // ground height: the framework's slab ring (top y=0) reaches HW+2.2 / HL+2.2
  const groundY = (x, z) => (sdRoundRect(x, z, HW + 2.2, HL + 2.2, corner + 2.2) < 0 ? 0 : GROUND);
  const insideClear = (x, z, m = 0) => Math.abs(x) < CLEAR_X + m && Math.abs(z) < CLEAR_Z + m;
  const animated = [];   // { update(dt, time) }
  const dummy = new THREE.Object3D();

  // ------------------------------------------------ ground
  const groundTex = canvasTex(THREE, 512, (g, s) => {
    g.fillStyle = '#1c2a18'; g.fillRect(0, 0, s, s);
    for (let i = 0; i < 900; i++) {
      const r = rand(6, 40);
      g.fillStyle = `rgba(${Math.floor(rand(18, 60))},${Math.floor(rand(48, 96))},${Math.floor(rand(22, 58))},${rand(0.08, 0.28)})`;
      g.beginPath(); g.arc(rand(0, s), rand(0, s), r, 0, Math.PI * 2); g.fill();
    }
    for (let i = 0; i < 700; i++) {
      g.fillStyle = Math.random() < 0.7 ? 'rgba(110,170,90,0.35)' : 'rgba(200,180,255,0.45)';
      g.fillRect(rand(0, s), rand(0, s), rand(1, 2.5), rand(1, 2.5));
    }
  }, 16);
  const ground = new THREE.Mesh(new THREE.CircleGeometry(190, 56), new THREE.MeshLambertMaterial({ map: groundTex, color: 0xb9c9b0 }));
  ground.rotation.x = -Math.PI / 2;
  ground.position.y = GROUND;
  ground.receiveShadow = true;
  group.add(ground);

  // ------------------------------------------------ hero trees (merged, one shadow caster)
  const barkDark = C(0x35220f), barkLight = C(0x6e4a28), moss = C(0x3f7a33);
  const palettes = {
    green: [C(0x17402c), C(0x3f9a4c), C(0x8fd66a)],
    violet: [C(0x3a1750), C(0x9a4fb8), C(0xf0a1e2)],
    teal: [C(0x113f3a), C(0x2f9a7a), C(0xa2f0c8)],
  };
  const paintBark = (g, h) => paint(THREE, g, (c, x, y, z) => {
    const a = Math.atan2(z, x);
    const k = 0.5 + 0.5 * Math.sin(a * 7 + y * 0.9) * Math.cos(a * 3 - y * 0.4);
    c.copy(barkDark).lerp(barkLight, k * 0.85);
    const m = Math.max(0, 1 - y / (h * 0.28)) * (0.5 + 0.5 * Math.sin(a * 4 + 1));
    c.lerp(moss, m * 0.8);
  });
  const paintCanopy = (g, pal, r) => paint(THREE, g, (c, x, y, z) => {
    const t = Math.min(1, Math.max(0, (y / r + 0.7) / 1.5));
    const n = Math.sin(x * 2.1 + z * 1.7) * Math.cos(y * 2.3) * 0.18;
    const k = Math.min(1, Math.max(0, t + n));
    if (k < 0.55) c.copy(pal[0]).lerp(pal[1], k / 0.55); else c.copy(pal[1]).lerp(pal[2], (k - 0.55) / 0.45);
  });

  const heroSpecs = [
    { x: -24.5, z: 9, h: 17, r0: 1.7, seed: 1.3, lean: [-0.1, 0.04], pal: 'green' },
    { x: -22, z: 41, h: 14, r0: 1.4, seed: 4.1, lean: [-0.08, 0.12], pal: 'teal' },
    { x: -27, z: -22, h: 13, r0: 1.3, seed: 2.7, lean: [-0.14, -0.08], pal: 'green' },
    { x: 30, z: -8, h: 15, r0: 1.5, seed: 6.2, lean: [0.1, -0.05], pal: 'violet' },
    { x: 29, z: 40, h: 16, r0: 1.6, seed: 8.8, lean: [0.12, 0.1], pal: 'violet' },
    { x: 32, z: 23, h: 13, r0: 1.25, seed: 3.4, lean: [0.12, 0.02], pal: 'green' },
    { x: -27.5, z: 26, h: 15, r0: 1.5, seed: 5.6, lean: [-0.12, 0.03], pal: 'teal' },
  ];
  const heroParts = [];
  const canopyAnchors = [];   // world-space positions of canopy blobs (fireflies, vines)
  const treeFeet = [];
  for (const s of heroSpecs) {
    const base = new THREE.Vector3(s.x, GROUND, s.z);
    treeFeet.push({ x: s.x, z: s.z, r: s.r0 * 1.9 });
    const T = trunk(THREE, { h: s.h, r0: s.r0, r1: s.r0 * 0.32, rings: 14, radial: 12, seed: s.seed, lean: s.lean, flare: 1.1, bump: 0.16, twist: 1.4 });
    heroParts.push(paintBark(T.geom, s.h).translate(base.x, base.y, base.z));
    const pal = palettes[s.pal];
    const away = Math.atan2(s.z, s.x);
    const blobs = [];
    // branches
    const nb = 3 + Math.floor(rand(0, 2));
    for (let i = 0; i < nb; i++) {
      const t = rand(0.5, 0.86);
      const [cx, cy, cz] = T.centre(t);
      const az = away + rand(-1.9, 1.9);
      const tilt = rand(0.6, 1.0);
      const dir = new THREE.Vector3(Math.cos(az) * Math.cos(tilt), Math.sin(tilt), Math.sin(az) * Math.cos(tilt));
      const len = s.h * rand(0.3, 0.45);
      const B = trunk(THREE, { h: len, r0: T.radius(t) * 0.55, r1: 0.12, rings: 6, radial: 7, seed: s.seed + i, lean: [rand(-0.15, 0.15), 0], flare: 0.2, bump: 0.1, wiggle: 0.03 });
      const from = new THREE.Vector3(cx, cy, cz).add(base);
      heroParts.push(orient(THREE, paintBark(B.geom, len * 3), from, dir));
      const end = from.clone().addScaledVector(dir, len);
      blobs.push({ p: end, r: rand(2.6, 3.6) });
      if (Math.random() < 0.6) {
        // hanging vine from the branch end
        const pts = [];
        const vl = rand(3.5, 6.5);
        const sway = rand(-0.5, 0.5);
        for (let k = 0; k <= 4; k++) { const u = k / 4; pts.push(new THREE.Vector3(end.x + Math.sin(u * 3) * sway, end.y - u * vl, end.z + Math.cos(u * 2.5 + 1) * sway)); }
        const vine = new THREE.TubeGeometry(new THREE.CatmullRomCurve3(pts), 6, 0.07, 4, false);
        heroParts.push(paint(THREE, vine, (c, x, y) => c.copy(pal[0]).lerp(pal[1], 0.5 + 0.5 * Math.sin(y * 3 + x))));
        const leaf = blob(THREE, 0.35, 0, 1, 0.6, 1, 0.2, rand).translate(pts[4].x, pts[4].y, pts[4].z);
        heroParts.push(paint(THREE, leaf, (c) => c.copy(pal[1])));
      }
    }
    // crown
    const [tx, ty, tz] = T.centre(1);
    const top = new THREE.Vector3(tx, ty, tz).add(base);
    blobs.push({ p: top.clone().add(new THREE.Vector3(0, 0.8, 0)), r: s.h * 0.27 });
    for (let i = 0; i < 3; i++) {
      const a = away + rand(-2.2, 2.2), d = s.h * rand(0.12, 0.22);
      blobs.push({ p: top.clone().add(new THREE.Vector3(Math.cos(a) * d, rand(-1.5, 1.2), Math.sin(a) * d)), r: s.h * rand(0.16, 0.22) });
    }
    for (const b of blobs) {
      // keep every canopy blob outside the clear zone
      const margin = b.r + 0.5;
      if (Math.abs(b.p.x) < CLEAR_X + margin && Math.abs(b.p.z) < CLEAR_Z + margin) {
        const sx = Math.sign(b.p.x) || 1, sz = Math.sign(b.p.z) || 1;
        if (Math.abs(b.p.x) - CLEAR_X > Math.abs(b.p.z) - CLEAR_Z) b.p.x = sx * (CLEAR_X + margin); else b.p.z = sz * (CLEAR_Z + margin);
      }
      const g = blob(THREE, b.r, 1, rand(0.9, 1.15), rand(0.62, 0.78), rand(0.9, 1.15), 0.14, rand);
      heroParts.push(paintCanopy(g, pal, b.r).translate(b.p.x, b.p.y, b.p.z));
      canopyAnchors.push(b);
    }
  }
  const heroMesh = new THREE.Mesh(merge(THREE, heroParts), new THREE.MeshLambertMaterial({ vertexColors: true }));
  heroMesh.castShadow = true;
  heroMesh.receiveShadow = true;
  group.add(heroMesh);

  // ------------------------------------------------ far tree ring (instanced)
  {
    const t1 = paintBark(new THREE.CylinderGeometry(0.28, 0.75, 4.2, 6, 1, true).translate(0, 2.1, 0), 4);
    const b1 = paintCanopy(blob(THREE, 3.2, 1, 1, 0.8, 1, 0.12, rand).translate(0, 6.2, 0), palettes.green, 3.2);
    const b2 = paintCanopy(blob(THREE, 2.3, 1, 1, 0.8, 1, 0.12, rand).translate(1.2, 8.4, 0.6), palettes.green, 2.3);
    const geo = merge(THREE, [t1, b1, b2]);
    const N = 70;
    const far = new THREE.InstancedMesh(geo, new THREE.MeshLambertMaterial({ vertexColors: true }), N);
    const col = new THREE.Color();
    let placed = 0, tries = 0;
    while (placed < N && tries++ < 2000) {
      const a = rand(0, Math.PI * 2), r = rand(44, 105);
      const x = Math.cos(a) * r, z = Math.sin(a) * r;
      if (z < -30 && Math.abs(x) < 24) continue;              // behind the user's goal: keep low
      if (Math.abs(x) < 16 && z > 30 && z < 62) continue;       // clearing behind the standing stones
      const s = rand(0.9, 1.9) * (1 + (r - 44) / 120);
      dummy.position.set(x, GROUND, z);
      dummy.rotation.set(0, rand(0, Math.PI * 2), 0);
      dummy.scale.set(s * rand(0.85, 1.15), s * rand(0.9, 1.3), s * rand(0.85, 1.15));
      dummy.updateMatrix();
      far.setMatrixAt(placed, dummy.matrix);
      const k = lerp(1.0, 0.55, (r - 44) / 61);
      col.setRGB(k * 0.8, k * 0.92, k * 1.1);
      if (Math.random() < 0.18) col.setRGB(k * 1.0, k * 0.65, k * 1.05);
      far.setColorAt(placed, col);
      placed++;
    }
    far.count = placed;
    group.add(far);
  }

  // ------------------------------------------------ mushrooms (lanterns)
  const shroomSpots = [];
  const capColors = [C(0xffb347), C(0xffb347), C(0xff9a3c), C(0x7dffc2), C(0xc77dff), C(0xff8fb1)];
  for (const f of treeFeet) {
    const n = 6 + Math.floor(rand(0, 4));
    for (let i = 0; i < n; i++) {
      const a = rand(0, Math.PI * 2), d = f.r + rand(0.4, 4.2);
      const x = f.x + Math.cos(a) * d, z = f.z + Math.sin(a) * d;
      if (insideClear(x, z, 0.8)) continue;
      const big = i === 0;
      shroomSpots.push({ x, z, r: big ? rand(1.2, 1.7) : rand(0.35, 0.8), h: big ? rand(2.2, 3.0) : rand(0.6, 1.5), col: pick(capColors) });
    }
  }
  for (let i = 0; i < 46; i++) {
    let x, z;
    if (Math.random() < 0.65) { x = (Math.random() < 0.5 ? -1 : 1) * rand(16.4, 19.6); z = rand(-29, 29); }
    else { x = rand(-13, 13); z = (Math.random() < 0.5 ? -1 : 1) * rand(31.6, 35.5); }
    shroomSpots.push({ x, z, r: rand(0.35, 0.75), h: rand(0.7, 1.7), col: pick(capColors) });
  }
  {
    const prof = [[0, 1.0], [0.42, 0.95], [0.78, 0.78], [0.98, 0.5], [0.9, 0.36], [0.6, 0.34]].map(([x, y]) => new THREE.Vector2(x, y));
    const capG = paint(THREE, new THREE.LatheGeometry(prof, 9), (c, x, y, z) => {
      const spots = Math.sin(x * 9) * Math.cos(z * 9) > 0.7 ? 1.35 : 1;
      c.setScalar(lerp(0.55, 1.05, Math.min(1, y)) * spots);
    });
    const capMat = new THREE.MeshLambertMaterial({ vertexColors: true, emissive: 0xffffff, emissiveIntensity: 0.6 });
    capMat.onBeforeCompile = (s) => {
      s.fragmentShader = s.fragmentShader.replace('#include <emissivemap_fragment>', '#include <emissivemap_fragment>\n\ttotalEmissiveRadiance *= vColor.rgb * vColor.rgb;');
    };
    const caps = new THREE.InstancedMesh(capG, capMat, shroomSpots.length);
    const stemG = paint(THREE, new THREE.CylinderGeometry(0.2, 0.3, 1, 7, 1, true).translate(0, 0.5, 0), (c, x, y) => c.setScalar(lerp(0.55, 1, y)));
    const stems = new THREE.InstancedMesh(stemG, new THREE.MeshLambertMaterial({ color: 0xe9dcc4, vertexColors: true, emissive: 0x4a3a20, emissiveIntensity: 0.4 }), shroomSpots.length);
    const discG = new THREE.PlaneGeometry(1, 1).rotateX(-Math.PI / 2);
    const discTex = canvasTex(THREE, 128, (g, s) => {
      const gr = g.createRadialGradient(s / 2, s / 2, 0, s / 2, s / 2, s / 2);
      gr.addColorStop(0, 'rgba(255,255,255,0.9)'); gr.addColorStop(0.35, 'rgba(255,255,255,0.35)'); gr.addColorStop(1, 'rgba(255,255,255,0)');
      g.fillStyle = gr; g.fillRect(0, 0, s, s);
    });
    discTex.wrapS = discTex.wrapT = THREE.ClampToEdgeWrapping;
    const discMat = new THREE.MeshBasicMaterial({ map: discTex, transparent: true, blending: THREE.AdditiveBlending, depthWrite: false, opacity: 0.55 });
    const discs = new THREE.InstancedMesh(discG, discMat, shroomSpots.length);
    shroomSpots.forEach((m, i) => {
      const y = groundY(m.x, m.z), tilt = rand(-0.12, 0.12);
      dummy.position.set(m.x, y, m.z); dummy.rotation.set(tilt, rand(0, 6.28), tilt * 0.5); dummy.scale.set(m.r * 0.45, m.h, m.r * 0.45); dummy.updateMatrix();
      stems.setMatrixAt(i, dummy.matrix);
      dummy.position.set(m.x, y + m.h * 0.92, m.z); dummy.scale.set(m.r, m.r * 0.75, m.r); dummy.updateMatrix();
      caps.setMatrixAt(i, dummy.matrix);
      caps.setColorAt(i, m.col);
      dummy.position.set(m.x, y + 0.03, m.z); dummy.rotation.set(0, 0, 0); dummy.scale.setScalar(m.r * 6 + m.h * 1.5); dummy.updateMatrix();
      discs.setMatrixAt(i, dummy.matrix);
      discs.setColorAt(i, m.col);
    });
    caps.castShadow = false;
    group.add(stems, caps, discs);
    animated.push({ update(dt, t) {
      const p = 0.62 + 0.18 * Math.sin(t * 1.4) + 0.08 * Math.sin(t * 3.7);
      capMat.emissiveIntensity = p;
      discMat.opacity = 0.35 + p * 0.45;
    } });
  }

  // ------------------------------------------------ point lights (warm spill from lantern clusters)
  for (const [x, z] of [[-19.5, 6], [19.5, 24]]) {
    const l = new THREE.PointLight(0xffa554, 28, 22, 2);
    l.position.set(x, 1.6, z);
    group.add(l);
  }

  // ------------------------------------------------ stones + crystals
  const stoneSpots = [];
  const cluster = (cx, cz, n, rad, scale) => {
    for (let i = 0; i < n; i++) {
      const a = rand(0, 6.28), d = rand(0, rad);
      const x = cx + Math.cos(a) * d, z = cz + Math.sin(a) * d;
      if (insideClear(x, z, 1.2)) continue;
      stoneSpots.push({ x, z, s: rand(0.5, 1.3) * scale });
    }
  };
  for (const f of treeFeet) cluster(f.x, f.z, 5, f.r + 4, 1.0);
  cluster(0, 46, 10, 11, 0.9);
  cluster(-19, 26, 4, 3, 0.7); cluster(19, -20, 4, 3, 0.7); cluster(-19, -10, 3, 2.5, 0.6);
  for (let i = 0; i < 14; i++) { const z = rand(-44, 62); const x = streamX(z) + (Math.random() < 0.5 ? -1 : 1) * rand(1.8, 3.6); if (!insideClear(x, z, 1)) stoneSpots.push({ x, z, s: rand(0.4, 1.0) }); }
  {
    const g = paint(THREE, blob(THREE, 1, 1, 1, 0.7, 1, 0.22, rand), (c, x, y) => {
      c.copy(C(0x6b7672)).lerp(C(0x8c9591), 0.5 + 0.5 * Math.sin(x * 5 + y * 3));
      if (y > 0.15) c.lerp(C(0x4f8a3a), Math.min(1, (y - 0.15) * 2.2));
    });
    const stones = new THREE.InstancedMesh(g, new THREE.MeshLambertMaterial({ vertexColors: true }), stoneSpots.length);
    stoneSpots.forEach((s, i) => {
      dummy.position.set(s.x, groundY(s.x, s.z) - s.s * 0.15, s.z);
      dummy.rotation.set(rand(-0.2, 0.2), rand(0, 6.28), rand(-0.2, 0.2));
      dummy.scale.set(s.s * rand(0.8, 1.3), s.s * rand(0.7, 1.1), s.s * rand(0.8, 1.3));
      dummy.updateMatrix(); stones.setMatrixAt(i, dummy.matrix);
    });
    stones.receiveShadow = true;
    group.add(stones);

    // violet crystals in a few clusters
    const crystalSpots = [];
    const cc = (cx, cz, n) => { for (let i = 0; i < n; i++) { const x = cx + rand(-1.4, 1.4), z = cz + rand(-1.4, 1.4); if (!insideClear(x, z, 0.8)) crystalSpots.push({ x, z, s: rand(0.5, 1.4) }); } };
    cc(-20, 26, 6); cc(19, -20, 5); cc(-30, -18, 5); cc(26, 46, 5); cc(-19, -10, 4); cc(35, 12, 5);
    const cg = new THREE.OctahedronGeometry(0.5, 0).scale(0.45, 1.3, 0.45).translate(0, 0.5, 0);
    const cmat = new THREE.MeshLambertMaterial({ color: 0xd9c6ff, emissive: 0x8a4dff, emissiveIntensity: 0.9 });
    const crystals = new THREE.InstancedMesh(cg, cmat, crystalSpots.length);
    crystalSpots.forEach((s, i) => {
      dummy.position.set(s.x, groundY(s.x, s.z) - 0.1, s.z);
      dummy.rotation.set(rand(-0.35, 0.35), rand(0, 6.28), rand(-0.35, 0.35));
      dummy.scale.setScalar(s.s); dummy.updateMatrix(); crystals.setMatrixAt(i, dummy.matrix);
    });
    group.add(crystals);
    animated.push({ update(dt, t) { cmat.emissiveIntensity = 0.7 + 0.3 * Math.sin(t * 0.9 + 1); } });
  }

  // ------------------------------------------------ standing stones + altar crystal (behind the far goal)
  {
    const parts = [];
    const n = 9, R = 7.5, cx = 0, cz = 46;
    const grey = C(0x777f7b), greyL = C(0x9aa39e), mossC = C(0x4f8a3a);
    const paintStone = (g, h) => paint(THREE, g, (c, x, y, z) => {
      c.copy(grey).lerp(greyL, 0.5 + 0.5 * Math.sin(x * 4 + y * 2.5 + z * 3));
      c.lerp(mossC, Math.max(0, 1 - y / (h * 0.3)) * 0.6);
    });
    for (let i = 0; i < n; i++) {
      const a = (i / n) * Math.PI * 2 + 0.2, h = rand(3.4, 5.4);
      const S = trunk(THREE, { h, r0: rand(0.8, 1.1), r1: rand(0.45, 0.7), rings: 5, radial: 6, seed: i * 1.7, lean: [rand(-0.05, 0.05), rand(-0.05, 0.05)], flare: 0.15, bump: 0.22, wiggle: 0.01 });
      const g = paintStone(S.geom, h);
      g.rotateY(rand(0, 6.28));
      g.translate(cx + Math.cos(a) * R, GROUND - 0.2, cz + Math.sin(a) * R);
      parts.push(g);
    }
    const altar = paintStone(blob(THREE, 1.9, 1, 1, 0.35, 1, 0.15, rand).translate(cx, GROUND + 0.35, cz), 1.2);
    parts.push(altar);
    const ring = new THREE.Mesh(merge(THREE, parts), new THREE.MeshLambertMaterial({ vertexColors: true }));
    ring.castShadow = true; ring.receiveShadow = true;
    group.add(ring);
    const gem = new THREE.Mesh(new THREE.OctahedronGeometry(0.9, 0).scale(0.6, 1.4, 0.6), new THREE.MeshLambertMaterial({ color: 0xcffaff, emissive: 0x4fd8ff, emissiveIntensity: 1.2 }));
    gem.position.set(cx, GROUND + 2.6, cz);
    group.add(gem);
    const glowTex = canvasTex(THREE, 128, (g, s) => {
      const gr = g.createRadialGradient(s / 2, s / 2, 0, s / 2, s / 2, s / 2);
      gr.addColorStop(0, 'rgba(120,230,255,0.9)'); gr.addColorStop(0.4, 'rgba(120,230,255,0.3)'); gr.addColorStop(1, 'rgba(120,230,255,0)');
      g.fillStyle = gr; g.fillRect(0, 0, s, s);
    });
    glowTex.wrapS = glowTex.wrapT = THREE.ClampToEdgeWrapping;
    const glowMat = new THREE.MeshBasicMaterial({ map: glowTex, transparent: true, blending: THREE.AdditiveBlending, depthWrite: false, opacity: 0.8 });
    const halo = new THREE.Mesh(new THREE.PlaneGeometry(14, 14).rotateX(-Math.PI / 2), glowMat);
    halo.position.set(cx, GROUND + 0.75, cz);
    group.add(halo);
    animated.push({ update(dt, t) {
      gem.rotation.y += dt * 0.7;
      gem.position.y = GROUND + 2.7 + Math.sin(t * 1.3) * 0.35;
      gem.material.emissiveIntensity = 1.0 + 0.4 * Math.sin(t * 2.1);
      glowMat.opacity = 0.6 + 0.25 * Math.sin(t * 1.3);
    } });
  }

  // ------------------------------------------------ stream + crooked bridge (east side)
  {
    const pos = [], uv = [], idx = [];
    const z0 = -50, z1 = 70, step = 2, half = 1.4;
    let row = 0;
    for (let z = z0; z <= z1; z += step, row++) {
      const x = streamX(z), w = half * (1 + 0.25 * Math.sin(z * 0.23));
      pos.push(x - w, GROUND + 0.05, z, x + w, GROUND + 0.05, z);
      uv.push(0, z / 8, 1, z / 8);
      if (row > 0) { const a = (row - 1) * 2; idx.push(a, a + 2, a + 1, a + 1, a + 2, a + 3); }
    }
    const g = new THREE.BufferGeometry();
    g.setAttribute('position', new THREE.Float32BufferAttribute(pos, 3));
    g.setAttribute('uv', new THREE.Float32BufferAttribute(uv, 2));
    g.setIndex(idx); g.computeVertexNormals();
    const waterTex = canvasTex(THREE, 256, (c, s) => {
      c.fillStyle = '#1f6f8a'; c.fillRect(0, 0, s, s);
      const gr = c.createLinearGradient(0, 0, s, 0);
      gr.addColorStop(0, 'rgba(10,40,70,0.9)'); gr.addColorStop(0.5, 'rgba(0,0,0,0)'); gr.addColorStop(1, 'rgba(10,40,70,0.9)');
      c.fillStyle = gr; c.fillRect(0, 0, s, s);
      c.strokeStyle = 'rgba(190,245,255,0.55)'; c.lineWidth = 2;
      for (let i = 0; i < 26; i++) {
        c.beginPath(); const y = rand(0, s), x = rand(0, s);
        c.moveTo(x, y); c.bezierCurveTo(x + 10, y + 30, x - 10, y + 60, x + rand(-15, 15), y + 90); c.stroke();
      }
    }, 1);
    const water = new THREE.Mesh(g, new THREE.MeshBasicMaterial({ map: waterTex, color: 0xa8e8ff }));
    group.add(water);
    animated.push({ update(dt) { waterTex.offset.y -= dt * 0.06; } });

    // bridge
    const parts = [];
    const bz = 14, xa = streamX(bz) - 4.8, xb = streamX(bz) + 4.8, planks = 13;
    const wood = C(0x6a4527), woodL = C(0x9a6b3c);
    const paintWood = (gg) => paint(THREE, gg, (c, x, y, z) => c.copy(wood).lerp(woodL, 0.5 + 0.5 * Math.sin(x * 7 + z * 11 + y * 5)));
    const arcY = (t) => GROUND + 0.35 + Math.sin(t * Math.PI) * 1.1;
    for (let i = 0; i < planks; i++) {
      const t = (i + 0.5) / planks, x = lerp(xa, xb, t);
      const slope = Math.atan2(arcY(t + 0.02) - arcY(t - 0.02), (xb - xa) * 0.04);
      const p = new THREE.BoxGeometry((xb - xa) / planks * 0.92, 0.12, 2.2);
      p.rotateZ(slope + rand(-0.06, 0.06)); p.rotateY(rand(-0.08, 0.08)); p.translate(x, arcY(t), bz + rand(-0.08, 0.08));
      parts.push(paintWood(p));
      if (i % 3 === 0) for (const side of [-1, 1]) {
        const post = new THREE.BoxGeometry(0.14, 1.0, 0.14).translate(0, 0.5, 0);
        post.rotateX(rand(-0.12, 0.12)); post.rotateZ(rand(-0.12, 0.12)); post.translate(x, arcY(t), bz + side * 1.0);
        parts.push(paintWood(post));
      }
    }
    for (const side of [-1, 1]) for (let i = 0; i < 4; i++) {
      const t0 = (i * 3 + 0.5) / planks, t1 = Math.min(1, ((i + 1) * 3 + 0.5) / planks);
      const x0 = lerp(xa, xb, t0), x1 = lerp(xa, xb, t1), y0 = arcY(t0) + 0.95, y1 = arcY(t1) + 0.95;
      const len = Math.hypot(x1 - x0, y1 - y0);
      const rail = new THREE.BoxGeometry(len, 0.1, 0.1);
      rail.rotateZ(Math.atan2(y1 - y0, x1 - x0) + rand(-0.03, 0.03)); rail.translate((x0 + x1) / 2, (y0 + y1) / 2, bz + side * 1.0);
      parts.push(paintWood(rail));
    }
    const bridge = new THREE.Mesh(merge(THREE, parts), new THREE.MeshLambertMaterial({ vertexColors: true }));
    bridge.castShadow = true;
    group.add(bridge);
  }

  // ------------------------------------------------ ferns (instanced)
  {
    const blades = [];
    for (let b = 0; b < 5; b++) {
      const az = (b / 5) * Math.PI * 2 + rand(-0.3, 0.3);
      const dx = Math.cos(az), dz = Math.sin(az);
      const pos = [], idx = [];
      for (let k = 0; k <= 3; k++) {
        const t = k / 3, r = t * 0.95, y = 0.95 * t - 0.55 * t * t, w = 0.17 * (1 - t * 0.75);
        pos.push(dx * r - dz * w, y, dz * r + dx * w, dx * r + dz * w, y, dz * r - dx * w);
        if (k > 0) { const a = (k - 1) * 2; idx.push(a, a + 2, a + 1, a + 1, a + 2, a + 3); }
      }
      const g = new THREE.BufferGeometry();
      g.setAttribute('position', new THREE.Float32BufferAttribute(pos, 3)); g.setIndex(idx); g.computeVertexNormals();
      blades.push(paint(THREE, g, (c, x, y) => c.copy(C(0x1d4d2c)).lerp(C(0x6fe08e), Math.min(1, y * 1.6 + 0.1))));
    }
    const fg = merge(THREE, blades);
    const spots = [];
    for (let i = 0; i < 150; i++) {
      let x, z;
      if (Math.random() < 0.6) { x = (Math.random() < 0.5 ? -1 : 1) * rand(17.3, 21.5); z = rand(-31, 31); }
      else { x = rand(-12, 12); z = (Math.random() < 0.5 ? -1 : 1) * rand(32.5, 37); }
      spots.push({ x, z });
    }
    for (const f of treeFeet) for (let i = 0; i < 6; i++) { const a = rand(0, 6.28), d = f.r + rand(0.3, 3.5); const x = f.x + Math.cos(a) * d, z = f.z + Math.sin(a) * d; if (!insideClear(x, z, 0.5)) spots.push({ x, z }); }
    const ferns = new THREE.InstancedMesh(fg, new THREE.MeshLambertMaterial({ vertexColors: true, side: THREE.DoubleSide }), spots.length);
    spots.forEach((s, i) => {
      dummy.position.set(s.x, groundY(s.x, s.z), s.z); dummy.rotation.set(0, rand(0, 6.28), 0);
      const k = rand(0.9, 1.7); dummy.scale.set(k, k * rand(1.0, 1.4), k); dummy.updateMatrix(); ferns.setMatrixAt(i, dummy.matrix);
    });
    group.add(ferns);
  }

  // ------------------------------------------------ hedge blobs hugging the wall (instanced)
  {
    const g = paint(THREE, blob(THREE, 0.8, 1, 1, 0.75, 1, 0.16, rand), (c, x, y, z) => {
      c.copy(C(0x173d2a)).lerp(C(0x3f8f4c), Math.min(1, Math.max(0, (y + 0.4) / 1.1)));
      if (Math.sin(x * 9) * Math.cos(z * 8 + y * 5) > 0.82) c.copy(C(0xd98cff)); // berries
    });
    const ox = HW + 1.35, oz = HL + 1.35, r = corner + 1.35;
    const pts = [];
    const straight = (x0, z0, x1, z1) => { const n = Math.ceil(Math.hypot(x1 - x0, z1 - z0) / 1.45); for (let i = 0; i < n; i++) { const t = i / n; pts.push([lerp(x0, x1, t), lerp(z0, z1, t)]); } };
    const arc = (cx, cz, a0) => { for (let i = 0; i < 3; i++) { const a = a0 + (i / 3) * Math.PI / 2; pts.push([cx + Math.cos(a) * r, cz + Math.sin(a) * r]); } };
    straight(-ox + r, -oz, ox - r, -oz); arc(ox - r, -oz + r, -Math.PI / 2);
    straight(ox, -oz + r, ox, oz - r); arc(ox - r, oz - r, 0);
    straight(ox - r, oz, -ox + r, oz); arc(-ox + r, oz - r, Math.PI / 2);
    straight(-ox, oz - r, -ox, -oz + r); arc(-ox + r, -oz + r, Math.PI);
    const hedge = new THREE.InstancedMesh(g, new THREE.MeshLambertMaterial({ vertexColors: true }), pts.length);
    const col = new THREE.Color();
    pts.forEach(([x, z], i) => {
      const s = rand(1.0, 1.5);
      dummy.position.set(x + rand(-0.2, 0.2), groundY(x, z) + 0.4 * s, z + rand(-0.2, 0.2));
      dummy.rotation.set(0, rand(0, 6.28), 0); dummy.scale.set(s * rand(0.9, 1.3), s * rand(1.1, 1.5), s * rand(0.9, 1.3));
      dummy.updateMatrix(); hedge.setMatrixAt(i, dummy.matrix);
      col.setScalar(rand(0.75, 1.1)); hedge.setColorAt(i, col);
    });
    hedge.receiveShadow = true;
    group.add(hedge);
  }

  // ------------------------------------------------ fireflies (shader points)
  {
    const N = 260;
    const pos = new Float32Array(N * 3), phase = new Float32Array(N), speed = new Float32Array(N), size = new Float32Array(N), col = new Float32Array(N * 3);
    const warm = C(0xe8ff6a), cool = C(0x7af5ff), pink = C(0xff9be0);
    for (let i = 0; i < N; i++) {
      let x, y, z;
      if (i < N * 0.55) {
        // band around the pitch
        if (Math.random() < 0.6) { x = (Math.random() < 0.5 ? -1 : 1) * rand(16.5, 34); z = rand(-34, 40); }
        else { x = rand(-20, 20); z = rand(32, 58); }
        y = rand(0.4, 7);
      } else {
        const a = pick(canopyAnchors);
        x = a.p.x + rand(-a.r, a.r) * 1.3; y = a.p.y + rand(-a.r * 1.5, a.r * 0.6); z = a.p.z + rand(-a.r, a.r) * 1.3;
        if (insideClear(x, z, 1.2)) { x = Math.sign(x || 1) * (CLEAR_X + 1.5 + rand(0, 3)); }
      }
      pos.set([x, y, z], i * 3);
      phase[i] = rand(0, 100); speed[i] = rand(0.35, 0.8); size[i] = rand(6, 15);
      const c = Math.random() < 0.7 ? warm : Math.random() < 0.6 ? cool : pink;
      col.set([c.r, c.g, c.b], i * 3);
    }
    const g = new THREE.BufferGeometry();
    g.setAttribute('position', new THREE.BufferAttribute(pos, 3));
    g.setAttribute('aPhase', new THREE.BufferAttribute(phase, 1));
    g.setAttribute('aSpeed', new THREE.BufferAttribute(speed, 1));
    g.setAttribute('aSize', new THREE.BufferAttribute(size, 1));
    g.setAttribute('aColor', new THREE.BufferAttribute(col, 3));
    const tex = canvasTex(THREE, 64, (c, s) => {
      const gr = c.createRadialGradient(s / 2, s / 2, 0, s / 2, s / 2, s / 2);
      gr.addColorStop(0, 'rgba(255,255,255,1)'); gr.addColorStop(0.25, 'rgba(255,255,255,0.6)'); gr.addColorStop(1, 'rgba(255,255,255,0)');
      c.fillStyle = gr; c.fillRect(0, 0, s, s);
    });
    const pr = Math.min(window.devicePixelRatio || 1, 2);
    const mat = new THREE.ShaderMaterial({
      uniforms: { uTime: { value: 0 }, uTex: { value: tex }, uScale: { value: 52 * pr } },
      vertexShader: `
        uniform float uTime; uniform float uScale;
        attribute float aPhase; attribute float aSpeed; attribute float aSize; attribute vec3 aColor;
        varying vec3 vCol; varying float vFade;
        void main() {
          float t = uTime * aSpeed + aPhase;
          vec3 p = position + vec3(sin(t) * 0.9 + sin(t * 0.37) * 0.7, sin(t * 0.8 + aPhase) * 0.5, cos(t * 0.9) * 0.9 + cos(t * 0.29) * 0.7);
          vec4 mv = modelViewMatrix * vec4(p, 1.0);
          float pulse = 0.5 + 0.5 * sin(t * 2.3 + aPhase * 3.0);
          pulse = smoothstep(0.15, 1.0, pulse);
          gl_PointSize = aSize * (0.5 + pulse) * uScale / max(1.0, -mv.z);
          vCol = aColor; vFade = pulse * (1.0 - smoothstep(55.0, 130.0, -mv.z));
          gl_Position = projectionMatrix * mv;
        }`,
      fragmentShader: `
        uniform sampler2D uTex; varying vec3 vCol; varying float vFade;
        void main() {
          float a = texture2D(uTex, gl_PointCoord).a * vFade;
          gl_FragColor = vec4(vCol * a, a);
          #include <colorspace_fragment>
        }`,
      transparent: true, depthWrite: false, blending: THREE.AdditiveBlending,
    });
    const pts = new THREE.Points(g, mat);
    pts.frustumCulled = false;
    group.add(pts);
    animated.push({ update(dt, t) { mat.uniforms.uTime.value = t; } });
  }

  // ------------------------------------------------ mist (instanced planes)
  {
    const tex = canvasTex(THREE, 256, (c, s) => {
      c.clearRect(0, 0, s, s);
      for (let i = 0; i < 40; i++) {
        const x = rand(0, s), y = rand(0, s), r = rand(30, 90);
        const gr = c.createRadialGradient(x, y, 0, x, y, r);
        gr.addColorStop(0, 'rgba(255,255,255,0.22)'); gr.addColorStop(1, 'rgba(255,255,255,0)');
        c.fillStyle = gr; c.fillRect(0, 0, s, s);
      }
    });
    const edge = canvasTex(THREE, 128, (c, s) => {
      const gr = c.createRadialGradient(s / 2, s / 2, 0, s / 2, s / 2, s / 2);
      gr.addColorStop(0, 'rgba(255,255,255,1)'); gr.addColorStop(0.45, 'rgba(255,255,255,0.7)'); gr.addColorStop(1, 'rgba(255,255,255,0)');
      c.fillStyle = gr; c.fillRect(0, 0, s, s);
    });
    edge.wrapS = edge.wrapT = THREE.ClampToEdgeWrapping;
    const mat = new THREE.MeshBasicMaterial({ map: tex, alphaMap: edge, color: 0xd6c6ff, transparent: true, opacity: 0.7, depthWrite: false });
    const spots = [[-44, -20], [44, -26], [-46, 24], [46, 20], [0, 62], [-30, 62], [32, 64], [-52, 2], [50, 46]];
    const mist = new THREE.InstancedMesh(new THREE.PlaneGeometry(40, 40).rotateX(-Math.PI / 2), mat, spots.length);
    spots.forEach(([x, z], i) => { dummy.position.set(x, GROUND + 0.9, z); dummy.rotation.set(0, rand(0, 6.28), 0); dummy.scale.setScalar(rand(0.75, 1.1)); dummy.updateMatrix(); mist.setMatrixAt(i, dummy.matrix); });
    group.add(mist);
    animated.push({ update(dt, t) { tex.offset.x += dt * 0.006; tex.offset.y += dt * 0.004; mat.opacity = 0.6 + 0.12 * Math.sin(t * 0.3); } });
  }

  return {
    update(dt, time) {
      for (const a of animated) a.update(dt, time);
    },
  };
}
