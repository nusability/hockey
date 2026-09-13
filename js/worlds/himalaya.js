// Himalaya — an ice rink on a high plateau among the peaks.
//
// One polar heightfield (plateau, foothills, an abyss to +X with clouds below the
// rim, a frozen lake basin to −X, ridges of snow-capped peaks all round), plus
// instanced snow-dusted pines, boulders and cairns, merged glacier seracs, a
// monastery on a mesa, prayer-flag strings (vertex-waved in a shader), soft cloud
// wisps and falling snow (GPU-animated Points). Everything is built with plain
// THREE geometry and canvas textures; no assets, no imports.
export default {
  id: 'himalaya',
  sport: 'ice',
  name: { en: 'Himalaya', de: 'Himalaya' },
  tagline: { en: 'Thin air, blue ice and prayer flags among the peaks.', de: 'Dünne Luft, blaues Eis und Gebetsfahnen zwischen den Gipfeln.' },
  sky: 'linear-gradient(180deg, #2a67cc 0%, #5b9fe6 28%, #a9d3f4 52%, #e3f1fb 72%, #f4f9fd 100%)',
  light: {
    hemiSky: 0xd6e9ff, hemiGround: 0x9fb6cc, hemiIntensity: 0.95,
    sun: 0xffe4bf, sunIntensity: 2.0, sunPos: [-35, 46, -26],
    fog: { color: 0xd9eaf8, near: 110, far: 470 },
  },
  surface: { base: '#eef6fd', stripe: '#e3eef9', lines: '#1d4ed8' },
  border: { color: 0xf8fafc, top: 0xdc2626, height: 1.1, glass: true, base: 0x9fb4c8 },
  ball: { color: 0x0f172a },
  goal: { post: 0xef4444, net: 0xffffff },

  buildScenery(group, ctx) {
    const handle = { update() {} };
    try { return build(group, ctx) || handle; }
    catch (e) { console.error('himalaya scenery', e); return handle; }
  },
};

// ------------------------------------------------------------------ helpers
const PI = Math.PI;
const clamp = (v, a, b) => (v < a ? a : v > b ? b : v);
const mix = (a, b, t) => a + (b - a) * t;
const sstep = (a, b, v) => { const t = clamp((v - a) / (b - a), 0, 1); return t * t * (3 - 2 * t); };
const wrapAng = (a) => { a = (a + PI) % (2 * PI); if (a < 0) a += 2 * PI; return a - PI; };
// smooth angular window centred on c: 1 inside ±hw, fading to 0 over `soft`
const win = (phi, c, hw, soft) => 1 - sstep(hw - soft, hw + soft, Math.abs(wrapAng(phi - c)));

function sdRoundRect(x, z, hw, hl, rr) {
  const qx = Math.abs(x) - (hw - rr), qz = Math.abs(z) - (hl - rr);
  return Math.hypot(Math.max(qx, 0), Math.max(qz, 0)) + Math.min(Math.max(qx, qz), 0) - rr;
}

function makeRng(seed) {
  let s = seed >>> 0;
  return () => {
    s = (s + 0x6d2b79f5) >>> 0;
    let t = s;
    t = Math.imul(t ^ (t >>> 15), t | 1);
    t ^= t + Math.imul(t ^ (t >>> 7), t | 61);
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  };
}
function hash2(i, j) {
  let h = (Math.imul(i, 374761393) + Math.imul(j, 668265263)) | 0;
  h = Math.imul(h ^ (h >>> 13), 1274126177);
  h ^= h >>> 16;
  return (h >>> 0) / 4294967296;
}
function vnoise(x, z) {
  const i = Math.floor(x), j = Math.floor(z);
  const fx = x - i, fz = z - j;
  const u = fx * fx * (3 - 2 * fx), v = fz * fz * (3 - 2 * fz);
  const a = hash2(i, j), b = hash2(i + 1, j), c = hash2(i, j + 1), d = hash2(i + 1, j + 1);
  return (a + (b - a) * u + (c - a) * v + (a - b - c + d) * u * v) * 2 - 1;
}
const fbm = (x, z) => vnoise(x, z) * 0.6 + vnoise(x * 2.1 + 7.3, z * 2.1 + 3.1) * 0.28 + vnoise(x * 4.3 + 1.7, z * 4.3 + 9.2) * 0.12;

// ------------------------------------------------------------------ terrain
const PEAKS = [];
function addPeak(x, z, h, R, p = 1.5, sx = 0.8, ax = 0) { PEAKS.push({ x, z, h, R, p, sx, ax, ca: Math.cos(ax), sa: Math.sin(ax) }); }
(function definePeaks() {
  const rng = makeRng(7331);
  // +Z: the backdrop seen from the play camera and the wide view
  addPeak(-18, 118, 60, 46, 1.4, 0.75, 0.4);
  addPeak(28, 138, 80, 56, 1.5, 0.7, -0.5);
  addPeak(74, 150, 56, 44, 1.4, 0.8, 0.9);
  addPeak(-66, 138, 60, 50, 1.5, 0.75, -0.9);
  addPeak(0, 245, 150, 110, 1.35, 0.8, 0.2);
  addPeak(-112, 255, 130, 100, 1.4, 0.75, 0.6);
  addPeak(122, 275, 145, 105, 1.4, 0.7, -0.3);
  addPeak(-38, 380, 165, 120, 1.3, 0.8, 0.0);
  // foothill knuckles at +Z
  addPeak(-40, 90, 22, 20, 1.3, 0.7, 0.3);
  addPeak(46, 92, 18, 18, 1.3, 0.7, -0.6);
  addPeak(14, 100, 16, 16, 1.3, 0.8, 1.0);
  // +X: giants across the abyss (they rise from the valley floor at -70)
  addPeak(232, -44, 195, 92, 1.4, 0.75, 0.3);
  addPeak(272, 62, 215, 100, 1.35, 0.7, -0.4);
  addPeak(332, -124, 205, 110, 1.4, 0.8, 0.9);
  addPeak(205, 150, 175, 90, 1.4, 0.7, 0.5);
  addPeak(300, 200, 190, 100, 1.4, 0.8, -0.8);
  // -X: peaks ringing the frozen lake
  addPeak(-126, -12, 72, 50, 1.5, 0.75, 0.2);
  addPeak(-150, 52, 88, 56, 1.45, 0.7, -0.6);
  addPeak(-140, -62, 62, 46, 1.5, 0.8, 0.8);
  addPeak(-250, 30, 140, 100, 1.4, 0.75, 0.1);
  addPeak(-300, -104, 150, 110, 1.4, 0.8, -0.5);
  addPeak(-262, 152, 125, 92, 1.4, 0.7, 0.7);
  // -Z: only far ridges behind the user's goal
  addPeak(-60, -282, 120, 100, 1.4, 0.8, 0.3);
  addPeak(82, -300, 140, 108, 1.4, 0.75, -0.4);
  addPeak(0, -400, 150, 110, 1.35, 0.8, 0.0);
  addPeak(-205, -252, 130, 100, 1.4, 0.7, 0.5);
  addPeak(202, -252, 120, 90, 1.4, 0.8, -0.6);
  // extra random far peaks for a crowded skyline
  for (let i = 0; i < 26; i++) {
    const phi = rng() * 2 * PI;
    const r = 170 + rng() * 230;
    const x = Math.sin(phi) * r, z = Math.cos(phi) * r;
    if (z < -150 && Math.abs(x) < 120 && r < 230) continue;
    const abyss = win(phi, PI / 2, 0.95, 0.35);
    const h = (50 + rng() * 60) * (0.5 + r / 300) + abyss * 90;
    addPeak(x, z, h, 40 + rng() * 60, 1.3 + rng() * 0.5, 0.6 + rng() * 0.4, rng() * PI);
  }
})();

const ABYSS_C = PI / 2, LAKE_C = -PI / 2;
const MESA = { x: 8, z: 82, y: 9, r: 11 };

function rimRadius(phi) { return 40 + 4.5 * fbm(Math.cos(phi) * 3 + 10, Math.sin(phi) * 3 + 10); }

function terrainH(x, z) {
  const r = Math.hypot(x, z), phi = Math.atan2(x, z);
  const rd = sdRoundRect(x, z, 17.6, 32.6, 11);
  const near = sstep(1, 10, rd);
  let y = -0.5 + near * (0.55 * fbm(x / 11, z / 11) + 0.18 * fbm(x / 3.5, z / 3.5) + 0.3);
  const wPX = win(phi, ABYSS_C, 0.95, 0.35);
  const wMX = win(phi, LAKE_C, 0.8, 0.3);
  const wMZ = win(phi, PI, 0.8, 0.3);
  // gentle foothills everywhere except abyss / behind the user's goal
  y += 7 * sstep(48, 100, r) * (1 - wPX) * (1 - wMZ * 0.7) * (1 + 0.5 * fbm(x / 25, z / 25));
  // frozen lake basin
  const basin = sstep(38, 50, r) * (1 - sstep(84, 100, r)) * wMX;
  y -= 3.6 * basin;
  // peaks (max-blend plus a little mass from overlaps)
  let pmax = 0, psum = 0;
  for (let i = 0; i < PEAKS.length; i++) {
    const p = PEAKS[i];
    let dx = x - p.x, dz = z - p.z;
    if (Math.abs(dx) > p.R * 1.7 || Math.abs(dz) > p.R * 1.7) continue;
    const rx = (dx * p.ca - dz * p.sa) / p.sx, rz = dx * p.sa + dz * p.ca;
    const u = Math.hypot(rx, rz) / p.R;
    if (u >= 1) continue;
    const c = p.h * Math.pow(1 - u, p.p) * (1 + 0.3 * fbm((x + p.x) / 22, (z + p.z) / 22));
    if (c > pmax) pmax = c;
    psum += c;
  }
  const pk = pmax + 0.22 * (psum - pmax);
  y += pk * (1 + 0.14 * fbm(x / 9, z / 9));
  // abyss: plateau rim then a sheer drop to the valley floor
  const rim = rimRadius(phi);
  const drop = sstep(rim, rim + 15, r) * wPX;
  y = mix(y, -70 + 6 * fbm(x / 30, z / 30) + pk, drop);
  // monastery mesa
  const md = Math.hypot(x - MESA.x, z - MESA.z);
  if (md < MESA.r + 8) y = Math.max(y, mix(y, MESA.y, sstep(MESA.r + 8, MESA.r - 1, md)));
  return y;
}

// ------------------------------------------------------------------ colours
const C = {
  snow: [0.95, 0.965, 0.99], snowShade: [0.84, 0.89, 0.96],
  rockD: [0.36, 0.34, 0.38], rockL: [0.62, 0.57, 0.53],
  iceA: [0.58, 0.8, 0.92], iceB: [0.78, 0.9, 0.97],
  haze: [0.78, 0.86, 0.94], floor: [0.25, 0.3, 0.38],
};
function terrainColor(x, z, y, slope, out) {
  const r = Math.hypot(x, z), phi = Math.atan2(x, z);
  const n1 = fbm(x / 15, z / 15) * 0.5 + 0.5;
  const rock = [mix(C.rockD[0], C.rockL[0], n1), mix(C.rockD[1], C.rockL[1], n1), mix(C.rockD[2], C.rockL[2], n1)];
  const sn = fbm(x / 6, z / 6) * 0.5 + 0.5;
  let snow = [mix(C.snowShade[0], C.snow[0], sn), mix(C.snowShade[1], C.snow[1], sn), mix(C.snowShade[2], C.snow[2], sn)];
  let amt = 1 - sstep(1.05, 2.0, slope + 0.6 * fbm(x / 7, z / 7));
  const snowline = mix(-60, 22, sstep(70, 180, r)) + 10 * fbm(x / 40, z / 40);
  amt *= sstep(snowline - 12, snowline + 6, y);
  // high summits stay white even where steep
  amt = Math.max(amt, sstep(snowline + 22, snowline + 60, y) * (1 - sstep(2.4, 3.4, slope)));
  // frozen lake basin: pale blue ice tint
  const basin = sstep(38, 50, r) * (1 - sstep(84, 100, r)) * win(phi, LAKE_C, 0.8, 0.3);
  // abyss cliff face: banded ice/rock
  const wPX = win(phi, ABYSS_C, 0.95, 0.35);
  const rim = rimRadius(phi);
  const cliff = wPX * sstep(rim - 3, rim + 2, r) * (1 - sstep(rim + 14, rim + 24, r)) * sstep(0.5, 1.0, slope);
  const band = ((y * 0.4) % 1 + 1) % 1 < 0.5 ? C.iceA : C.iceB;
  for (let i = 0; i < 3; i++) snow[i] = mix(snow[i], C.iceB[i], basin * 0.7);
  const col = [mix(rock[0], snow[0], amt), mix(rock[1], snow[1], amt), mix(rock[2], snow[2], amt)];
  for (let i = 0; i < 3; i++) col[i] = mix(col[i], band[i], cliff * 0.85);
  // valley floor deep below the clouds
  const fl = sstep(-30, -60, y);
  for (let i = 0; i < 3; i++) col[i] = mix(col[i], C.floor[i], fl);
  // dips of the plateau get a blue shade
  const dip = clamp(-(y + 0.5) * 1.5, 0, 1) * (1 - sstep(40, 60, r));
  for (let i = 0; i < 3; i++) col[i] = mix(col[i], C.snowShade[i] * 0.95, dip * 0.6);
  // atmospheric haze
  const hz = 0.35 * sstep(140, 430, r);
  for (let i = 0; i < 3; i++) out[i] = mix(col[i], C.haze[i], hz);
  return out;
}

// ------------------------------------------------------------------ geometry merge
function mergeParts(THREE, parts, withUv) {
  const pos = [], nor = [], col = [], uv = [];
  for (const { g, m, c } of parts) {
    const ng = g.index ? g.toNonIndexed() : g;
    if (m) ng.applyMatrix4(m);
    const p = ng.attributes.position.array, n = ng.attributes.normal ? ng.attributes.normal.array : null;
    for (let i = 0; i < p.length; i++) pos.push(p[i]);
    if (n) for (let i = 0; i < n.length; i++) nor.push(n[i]);
    const cnt = p.length / 3;
    const cc = c || [1, 1, 1];
    for (let i = 0; i < cnt; i++) col.push(cc[0], cc[1], cc[2]);
    if (withUv && ng.attributes.uv) { const u = ng.attributes.uv.array; for (let i = 0; i < u.length; i++) uv.push(u[i]); }
    if (ng !== g) ng.dispose();
  }
  const geo = new THREE.BufferGeometry();
  geo.setAttribute('position', new THREE.Float32BufferAttribute(pos, 3));
  if (nor.length === pos.length) geo.setAttribute('normal', new THREE.Float32BufferAttribute(nor, 3));
  geo.setAttribute('color', new THREE.Float32BufferAttribute(col, 3));
  if (withUv && uv.length) geo.setAttribute('uv', new THREE.Float32BufferAttribute(uv, 2));
  return geo;
}
const hex = (h) => [((h >> 16) & 255) / 255, ((h >> 8) & 255) / 255, (h & 255) / 255];

// ------------------------------------------------------------------ textures
function softTexture(THREE, size, draw) {
  const c = document.createElement('canvas');
  c.width = c.height = size;
  draw(c.getContext('2d'), size);
  const t = new THREE.CanvasTexture(c);
  t.colorSpace = THREE.SRGBColorSpace;
  return t;
}

// ------------------------------------------------------------------ build
function build(group, ctx) {
  const { THREE, HW, HL } = ctx;
  const rng = makeRng(4242);
  const R = (a, b) => a + rng() * (b - a);
  const uTime = { value: 0 };
  let tris = 0;

  // ---- terrain: polar heightfield, one mesh
  {
    const NA = 192;
    const radii = [0.6];
    let dr = 2.5;
    while (radii[radii.length - 1] < 440) { radii.push(radii[radii.length - 1] + dr); dr *= 1.06; }
    const NR = radii.length;
    const pos = new Float32Array(NR * NA * 3), col = new Float32Array(NR * NA * 3);
    const tmp = [0, 0, 0];
    for (let k = 0; k < NR; k++) {
      const r = radii[k];
      const e = 0.6 + r * 0.012;
      for (let a = 0; a < NA; a++) {
        const phi = (a / NA) * 2 * PI + (k % 2) * (PI / NA);
        const x = Math.sin(phi) * r, z = Math.cos(phi) * r;
        const y = terrainH(x, z);
        const sx = (terrainH(x + e, z) - terrainH(x - e, z)) / (2 * e);
        const sz = (terrainH(x, z + e) - terrainH(x, z - e)) / (2 * e);
        const i = (k * NA + a) * 3;
        pos[i] = x; pos[i + 1] = y; pos[i + 2] = z;
        terrainColor(x, z, y, Math.hypot(sx, sz), tmp);
        col[i] = tmp[0]; col[i + 1] = tmp[1]; col[i + 2] = tmp[2];
      }
    }
    const idx = [];
    for (let k = 0; k < NR - 1; k++) {
      for (let a = 0; a < NA; a++) {
        const a1 = (a + 1) % NA;
        const i0 = k * NA + a, i1 = k * NA + a1, i2 = (k + 1) * NA + a, i3 = (k + 1) * NA + a1;
        if (k % 2 === 0) { idx.push(i0, i2, i1, i1, i2, i3); } else { idx.push(i0, i3, i1, i0, i2, i3); }
      }
    }
    const geo = new THREE.BufferGeometry();
    geo.setAttribute('position', new THREE.BufferAttribute(pos, 3));
    geo.setAttribute('color', new THREE.BufferAttribute(col, 3));
    geo.setIndex(idx);
    geo.computeVertexNormals();
    const mesh = new THREE.Mesh(geo, new THREE.MeshLambertMaterial({ vertexColors: true, flatShading: true }));
    mesh.receiveShadow = true;
    group.add(mesh);
    tris += idx.length / 3;
  }

  // ---- frozen lake in the -X basin
  {
    const shape = new THREE.Shape();
    const n = 40;
    for (let i = 0; i <= n; i++) {
      const t = i / n;
      // loop: outer arc then inner arc
      let phi, r;
      if (t < 0.5) { const u = t * 2; phi = LAKE_C - 0.5 + u * 1.0; r = 83 + 3 * fbm(phi * 4, 1.5); }
      else { const u = (t - 0.5) * 2; phi = LAKE_C + 0.5 - u * 1.0; r = 50 - 3 * fbm(phi * 4, 5.5); }
      const x = Math.sin(phi) * r, z = Math.cos(phi) * r;
      if (i === 0) shape.moveTo(x, -z); else shape.lineTo(x, -z);
    }
    const geo = new THREE.ShapeGeometry(shape, 1);
    geo.rotateX(-PI / 2);
    const tex = softTexture(THREE, 256, (g, s) => {
      const grd = g.createLinearGradient(0, 0, s, s);
      grd.addColorStop(0, '#9fd2f2'); grd.addColorStop(0.5, '#c4e4f7'); grd.addColorStop(1, '#8fc4ea');
      g.fillStyle = grd; g.fillRect(0, 0, s, s);
      g.strokeStyle = 'rgba(255,255,255,0.55)'; g.lineWidth = 1.5;
      for (let i = 0; i < 14; i++) {
        g.beginPath(); let x = Math.random() * s, y = Math.random() * s; g.moveTo(x, y);
        for (let j = 0; j < 4; j++) { x += (Math.random() - 0.5) * 90; y += (Math.random() - 0.5) * 90; g.lineTo(x, y); }
        g.stroke();
      }
    });
    tex.wrapS = tex.wrapT = THREE.RepeatWrapping;
    const lake = new THREE.Mesh(geo, new THREE.MeshPhongMaterial({ color: 0xbfe0f5, map: tex, specular: 0xffffff, shininess: 120, emissive: 0x1c3d5c, emissiveIntensity: 0.25 }));
    lake.position.y = -3.25;
    group.add(lake);
    tris += geo.attributes.position.count;
  }

  // ---- pine trees (instanced, snow-dusted)
  {
    const parts = [];
    const trunk = new THREE.CylinderGeometry(0.1, 0.18, 1.3, 6, 1, true);
    parts.push({ g: trunk, m: new THREE.Matrix4().makeTranslation(0, 0.65, 0), c: hex(0x4a3221) });
    const layers = [[1.35, 1.8, 0.7], [1.05, 1.6, 1.8], [0.7, 1.5, 2.85]];
    for (const [rad, h, y0] of layers) {
      const green = new THREE.ConeGeometry(rad, h, 7, 1, true);
      parts.push({ g: green, m: new THREE.Matrix4().makeTranslation(0, y0 + h / 2, 0), c: hex(0x1f4d33) });
      const cap = new THREE.ConeGeometry(rad * 0.62, h * 0.62, 7, 1, true);
      parts.push({ g: cap, m: new THREE.Matrix4().makeTranslation(0.0, y0 + h - h * 0.31 + 0.02, 0), c: hex(0xf3f7fd) });
    }
    const geo = mergeParts(THREE, parts, false);
    const N = 230;
    const mesh = new THREE.InstancedMesh(geo, new THREE.MeshLambertMaterial({ vertexColors: true, flatShading: true }), N);
    const m = new THREE.Matrix4(), q = new THREE.Quaternion(), s = new THREE.Vector3(), p = new THREE.Vector3();
    let placed = 0, tries = 0;
    while (placed < N && tries++ < 4000) {
      const phi = R(-PI, PI), r = R(30, 115);
      const x = Math.sin(phi) * r, z = Math.cos(phi) * r;
      if (z < -32 && Math.abs(x) < 22) continue;                       // keep the view behind the user's goal clear
      if (win(phi, ABYSS_C, 0.95, 0.35) > 0.15 && r > 30) continue;     // no trees in the abyss
      if (sdRoundRect(x, z, HW + 2.5, HL + 2.5, 11) < 5.5) continue;
      if (win(phi, LAKE_C, 0.8, 0.3) > 0.35 && r > 26 && r < 100) continue;   // open snowfield down to the lake
      const y = terrainH(x, z);
      if (y < -1.5 || y > 26) continue;
      const e = 0.8;
      const slope = Math.hypot(terrainH(x + e, z) - terrainH(x - e, z), terrainH(x, z + e) - terrainH(x, z - e)) / (2 * e);
      if (slope > 0.55) continue;
      if (Math.hypot(x - MESA.x, z - MESA.z) < MESA.r + 1) continue;
      // cluster density: denser at the +Z foothills, sparser near the boards
      if (r < 42 && rng() < 0.3) continue;
      const sc = R(0.75, 1.45) * (1 + 0.3 * sstep(60, 110, r));
      q.setFromAxisAngle(new THREE.Vector3(0, 1, 0), R(0, 2 * PI));
      s.set(sc, sc * R(0.9, 1.2), sc);
      p.set(x, y - 0.15, z);
      m.compose(p, q, s);
      mesh.setMatrixAt(placed++, m);
    }
    mesh.count = placed;
    mesh.castShadow = true;
    mesh.receiveShadow = true;
    group.add(mesh);
    tris += (geo.attributes.position.count / 3) * placed;
  }

  // ---- boulders (instanced dodecahedra)
  {
    const geo = new THREE.DodecahedronGeometry(1, 0);
    const N = 90;
    const mesh = new THREE.InstancedMesh(geo, new THREE.MeshLambertMaterial({ color: 0x6c6570, flatShading: true }), N);
    const m = new THREE.Matrix4(), q = new THREE.Quaternion(), s = new THREE.Vector3(), p = new THREE.Vector3(), eu = new THREE.Euler();
    let placed = 0, tries = 0;
    while (placed < N && tries++ < 2000) {
      const phi = R(-PI, PI), r = R(24, 100);
      const x = Math.sin(phi) * r, z = Math.cos(phi) * r;
      if (z < -32 && Math.abs(x) < 20) continue;
      if (win(phi, ABYSS_C, 0.95, 0.35) > 0.3 && r > rimRadius(phi) - 4) continue;
      if (sdRoundRect(x, z, HW + 2.5, HL + 2.5, 11) < 4) continue;
      const y = terrainH(x, z);
      if (y < -1.5) continue;
      const e = 1.0;
      if (Math.hypot(terrainH(x + e, z) - terrainH(x - e, z), terrainH(x, z + e) - terrainH(x, z - e)) / (2 * e) > 0.45) continue;
      const sc = R(0.4, 1.6) * (1 + sstep(50, 100, r));
      eu.set(R(0, PI), R(0, PI), R(0, PI));
      q.setFromEuler(eu);
      s.set(sc * R(0.8, 1.4), sc * R(0.6, 1.0), sc);
      p.set(x, y - sc * 0.45, z);
      m.compose(p, q, s);
      mesh.setMatrixAt(placed++, m);
    }
    mesh.count = placed;
    mesh.receiveShadow = true;
    group.add(mesh);
    tris += 36 * placed;
  }

  // ---- stone cairns (instanced stacks) near the rink
  {
    const parts = [];
    let y = 0;
    const sizes = [1.0, 0.85, 0.7, 0.55, 0.42, 0.3];
    for (let i = 0; i < sizes.length; i++) {
      const w = sizes[i], h = 0.28 + w * 0.2;
      const g = new THREE.BoxGeometry(w, h, w * R(0.75, 1.0));
      const m = new THREE.Matrix4().makeRotationY(R(-0.4, 0.4)).setPosition(R(-0.05, 0.05), y + h / 2, R(-0.05, 0.05));
      const shade = R(0.32, 0.5);
      parts.push({ g, m, c: [shade, shade * 0.95, shade * 1.0] });
      y += h;
    }
    parts.push({ g: new THREE.BoxGeometry(0.34, 0.1, 0.34), m: new THREE.Matrix4().makeTranslation(0, y + 0.04, 0), c: hex(0xf5f8fd) });
    const geo = mergeParts(THREE, parts, false);
    const spots = [
      [-21.5, 12], [21.5, -4], [-20.5, -20], [22, 20], [-19.5, 34.5], [19.8, 35.5], [-24, -34], [24.5, -35],
      [-26, 44], [27, 46], [-30, 20], [31, -18], [-33, -8], [3, 44.5], [-3, 45], [16, 40], [-16, 41],
    ];
    const mesh = new THREE.InstancedMesh(geo, new THREE.MeshLambertMaterial({ vertexColors: true, flatShading: true }), spots.length);
    const m = new THREE.Matrix4(), q = new THREE.Quaternion(), s = new THREE.Vector3(), p = new THREE.Vector3();
    spots.forEach(([x, z], i) => {
      const sc = R(0.8, 1.35);
      q.setFromAxisAngle(new THREE.Vector3(0, 1, 0), R(0, PI));
      s.set(sc, sc, sc); p.set(x, terrainH(x, z) - 0.05, z);
      m.compose(p, q, s); mesh.setMatrixAt(i, m);
    });
    mesh.receiveShadow = true;
    group.add(mesh);
    tris += (geo.attributes.position.count / 3) * spots.length;
  }

  // ---- glacier seracs and ice cliffs (merged boxes)
  {
    const parts = [];
    const ice = hex(0xa8dcf5), iceD = hex(0x7fbfe6);
    const block = (x, z, w, h, d, rot, tilt, c) => {
      const y = terrainH(x, z);
      const m = new THREE.Matrix4().makeRotationFromEuler(new THREE.Euler(tilt, rot, tilt * 0.6)).setPosition(x, y + h * 0.42, z);
      parts.push({ g: new THREE.BoxGeometry(w, h, d), m, c });
    };
    // ice fins along the abyss rim
    for (let i = 0; i < 22; i++) {
      const phi = ABYSS_C + R(-0.75, 0.75);
      const r = rimRadius(phi) - R(1.5, 6);
      block(Math.sin(phi) * r, Math.cos(phi) * r, R(2, 5), R(1.5, 5), R(2, 5), R(0, PI), R(-0.25, 0.25), rng() < 0.5 ? ice : iceD);
    }
    // ice cliff at the lake's far shore
    for (let i = 0; i < 12; i++) {
      const phi = LAKE_C + R(-0.45, 0.45);
      const r = R(86, 94);
      block(Math.sin(phi) * r, Math.cos(phi) * r, R(5, 9), R(6, 13), R(4, 8), phi + R(-0.3, 0.3), R(-0.12, 0.12), rng() < 0.5 ? ice : iceD);
    }
    // small blue ice blocks near the boards (never behind the user's goal)
    for (const [cx, cz] of [[-33, 31], [33, -31], [-34, -14], [34, 12]]) {
      for (let i = 0; i < 5; i++) block(cx + R(-3, 3), cz + R(-3, 3), R(2, 4), R(3, 7), R(2, 4), R(0, PI), R(-0.2, 0.2), rng() < 0.5 ? ice : iceD);
    }
    const near = [[23.5, -12, 1.4], [25.5, -9, 1.0], [-24, 10, 1.6], [-26.5, 13, 1.1], [-23, 44, 1.5], [22.5, 46, 1.2], [26, 38, 0.9], [-27, -26, 1.3], [28, 24, 1.0], [-25, 27, 1.1], [25.5, 28, 0.9], [-25.5, -28, 1.0], [25, -26, 1.2]];
    for (const [x, z, sc] of near) block(x, z, 2.2 * sc, 1.6 * sc, 1.8 * sc, R(0, PI), R(-0.2, 0.2), rng() < 0.5 ? ice : iceD);
    const geo = mergeParts(THREE, parts, false);
    const mesh = new THREE.Mesh(geo, new THREE.MeshPhongMaterial({ vertexColors: true, flatShading: true, specular: 0xcfeeff, shininess: 60, emissive: 0x123a52, emissiveIntensity: 0.35 }));
    mesh.castShadow = true;
    mesh.receiveShadow = true;
    group.add(mesh);
    tris += geo.attributes.position.count / 3;
  }

  // ---- monastery on the mesa + stupas near the rink (one merged mesh)
  const flagStrings = []; // [ax, ay, az, bx, by, bz, scale]
  {
    const parts = [];
    const box = (x, y, z, w, h, d, c, rot = 0) => parts.push({ g: new THREE.BoxGeometry(w, h, d), m: new THREE.Matrix4().makeRotationY(rot).setPosition(x, y, z), c });
    const white = hex(0xf3ede0), red = hex(0x9a2c22), gold = hex(0xe0ad3a), dark = hex(0x2a221f), roof = hex(0xb9822a);
    const stupa = (x, z, sc) => {
      const y = terrainH(x, z);
      box(x, y + 0.35 * sc, z, 4 * sc, 0.7 * sc, 4 * sc, white);
      box(x, y + 0.95 * sc, z, 3.1 * sc, 0.5 * sc, 3.1 * sc, white);
      box(x, y + 1.4 * sc, z, 2.4 * sc, 0.4 * sc, 2.4 * sc, white);
      parts.push({ g: new THREE.SphereGeometry(1.25 * sc, 10, 7), m: new THREE.Matrix4().makeTranslation(x, y + 1.9 * sc, z), c: white });
      box(x, y + 3.35 * sc, z, 0.9 * sc, 0.8 * sc, 0.9 * sc, gold);
      parts.push({ g: new THREE.ConeGeometry(0.62 * sc, 2.4 * sc, 8, 1, true), m: new THREE.Matrix4().makeTranslation(x, y + 4.9 * sc, z), c: gold });
      parts.push({ g: new THREE.SphereGeometry(0.28 * sc, 6, 5), m: new THREE.Matrix4().makeTranslation(x, y + 6.2 * sc, z), c: gold });
      return y + 6.2 * sc;
    };
    // monastery
    const mx = MESA.x, mz = MESA.z, my = MESA.y;
    box(mx, my + 3, mz, 11, 6, 7.5, white);
    box(mx, my + 6.5, mz, 11.4, 1.0, 7.9, red);
    box(mx, my + 7.1, mz, 11.8, 0.25, 8.3, roof);
    box(mx - 3.2, my + 8.6, mz + 0.4, 5.2, 3.2, 5.2, white);      // upper storey
    box(mx - 3.2, my + 10.5, mz + 0.4, 5.6, 0.7, 5.6, red);
    box(mx - 3.2, my + 11.0, mz + 0.4, 6.0, 0.25, 6.0, roof);
    parts.push({ g: new THREE.ConeGeometry(0.5, 1.4, 6, 1, true), m: new THREE.Matrix4().makeTranslation(mx - 3.2, my + 11.8, mz + 0.4), c: gold });
    for (let i = -2; i <= 2; i++) { box(mx + i * 2.2, my + 3.2, mz - 3.8, 0.9, 1.4, 0.2, dark); box(mx + i * 2.2, my + 3.2, mz + 3.8, 0.9, 1.4, 0.2, dark); }
    box(mx + 3.5, my + 1.4, mz - 3.8, 1.6, 2.8, 0.25, red);          // door
    stupa(mx + 7, mz - 2, 0.7);
    // flag mast on the monastery roof
    parts.push({ g: new THREE.CylinderGeometry(0.1, 0.14, 7, 6), m: new THREE.Matrix4().makeTranslation(mx - 3.2, my + 15, mz + 0.4), c: hex(0x5a3d26) });
    const mastTop = [mx - 3.2, my + 18.4, mz + 0.4];
    for (const [tx, tz] of [[mx - 22, mz - 14], [mx + 20, mz - 10], [mx - 14, mz + 20], [mx + 16, mz + 16]]) {
      const ty = terrainH(tx, tz);
      parts.push({ g: new THREE.CylinderGeometry(0.1, 0.14, 4, 6), m: new THREE.Matrix4().makeTranslation(tx, ty + 2, tz), c: hex(0x5a3d26) });
      flagStrings.push([mastTop[0], mastTop[1], mastTop[2], tx, ty + 4, tz, 1.35]);
    }
    // stupas near the rink (the -Z one sits well outside |X|<18)
    for (const [sx, sz, sc] of [[-24, 36, 0.8], [25, -37, 0.7], [-30, -6, 0.6], [-9.5, 41, 0.5], [9.5, 41, 0.5]]) {
      const top = stupa(sx, sz, sc);
      // four short strings radiating from the spire
      for (let k = 0; k < 3; k++) {
        const a = k * (2 * PI / 3) + R(0, 1);
        const tx = sx + Math.sin(a) * 7, tz = sz + Math.cos(a) * 7;
        if (sdRoundRect(tx, tz, HW + 2.5, HL + 2.5, 11) < 1.5) continue;
        const ty = terrainH(tx, tz);
        parts.push({ g: new THREE.CylinderGeometry(0.06, 0.08, 2.2, 5), m: new THREE.Matrix4().makeTranslation(tx, ty + 1.1, tz), c: hex(0x5a3d26) });
        flagStrings.push([sx, top - 0.3, sz, tx, ty + 2.2, tz, 0.6]);
      }
    }
    const geo = mergeParts(THREE, parts, false);
    const mesh = new THREE.Mesh(geo, new THREE.MeshLambertMaterial({ vertexColors: true, flatShading: true }));
    mesh.castShadow = true;
    mesh.receiveShadow = true;
    group.add(mesh);
    tris += geo.attributes.position.count / 3;
  }

  // ---- prayer-flag poles around the rink + flag strings
  {
    const poleParts = [];
    const pole = (x, z, h) => {
      const y = terrainH(x, z);
      poleParts.push({ g: new THREE.CylinderGeometry(0.11, 0.16, h, 6), m: new THREE.Matrix4().makeTranslation(x, y + h / 2, z), c: hex(0x6b4a2e) });
      poleParts.push({ g: new THREE.SphereGeometry(0.22, 6, 5), m: new THREE.Matrix4().makeTranslation(x, y + h + 0.1, z), c: hex(0xe0ad3a) });
      return [x, y + h, z];
    };
    for (const sx of [-1, 1]) {
      const tops = [-25, -8.5, 8.5, 25].map((z) => pole(sx * 19.4, z, 5.4));
      for (let i = 0; i < tops.length - 1; i++) flagStrings.push([...tops[i], ...tops[i + 1], 1.15]);
    }
    const endTops = [-14.5, -4.8, 4.8, 14.5].map((x) => pole(x, 33.8, 4.6));
    for (let i = 0; i < endTops.length - 1; i++) flagStrings.push([...endTops[i], ...endTops[i + 1], 1.0]);
    // corner strings from the far-end poles to the side poles
    flagStrings.push([...endTops[0], ...pole(-19.4, 25, 5.4), 1.0]);
    flagStrings.push([...endTops[3], ...pole(19.4, 25, 5.4), 1.0]);
    const poleGeo = mergeParts(THREE, poleParts, false);
    const poles = new THREE.Mesh(poleGeo, new THREE.MeshLambertMaterial({ vertexColors: true, flatShading: true }));
    poles.receiveShadow = true;
    group.add(poles);
    tris += poleGeo.attributes.position.count / 3;

    // ropes (one LineSegments) + flags (one merged, shader-waved mesh)
    const rope = [];
    const fpos = [], fcol = [], fflag = [], fnor = [];
    const palette = [0x2f6fd8, 0xf5f7fa, 0xe23b2e, 0x2fa04a, 0xf2c31f].map(hex);
    let fi = 0;
    for (const [ax, ay, az, bx, by, bz, sc] of flagStrings) {
      const len = Math.hypot(bx - ax, by - ay, bz - az);
      const sag = len * 0.07;
      const P = (t) => [mix(ax, bx, t), mix(ay, by, t) - sag * 4 * t * (1 - t), mix(az, bz, t)];
      const segs = 10;
      for (let i = 0; i < segs; i++) { rope.push(...P(i / segs), ...P((i + 1) / segs)); }
      const tx = (bx - ax) / len, tz = (bz - az) / len;
      const hl = Math.hypot(tx, tz) || 1;
      const nx = -tz / hl, nz = tx / hl;         // horizontal perpendicular
      const fw = 0.85 * sc, fh = 0.65 * sc;
      const n = Math.max(2, Math.floor(len / (fw * 1.35)));
      for (let k = 0; k < n; k++) {
        const t = (k + 0.5) / n;
        if (t < 0.06 || t > 0.94) continue;
        const c = P(t);
        const color = palette[fi++ % palette.length];
        const phase = R(0, 2 * PI);
        // 3x2 grid of quads hanging below the rope point
        const cols = 3, rows = 2;
        const grid = [];
        for (let r = 0; r <= rows; r++) {
          for (let q = 0; q <= cols; q++) {
            const u = q / cols, v = r / rows;
            const dx = (u - 0.5) * fw, dy = -v * fh - 0.04;
            grid.push([c[0] + (tx / hl) * dx, c[1] + dy + (mix(ay, by, t + dx / len) - mix(ay, by, t)), c[2] + (tz / hl) * dx, v]);
          }
        }
        const push = (g) => { fpos.push(g[0], g[1], g[2]); fcol.push(color[0], color[1], color[2]); fflag.push(nx, nz, phase, g[3]); fnor.push(nx, 0, nz); };
        for (let r = 0; r < rows; r++) {
          for (let q = 0; q < cols; q++) {
            const i0 = r * (cols + 1) + q, i1 = i0 + 1, i2 = i0 + cols + 1, i3 = i2 + 1;
            push(grid[i0]); push(grid[i2]); push(grid[i1]);
            push(grid[i1]); push(grid[i2]); push(grid[i3]);
          }
        }
      }
    }
    const ropeGeo = new THREE.BufferGeometry();
    ropeGeo.setAttribute('position', new THREE.Float32BufferAttribute(rope, 3));
    group.add(new THREE.LineSegments(ropeGeo, new THREE.LineBasicMaterial({ color: 0x3b2f2a })));
    const flagGeo = new THREE.BufferGeometry();
    flagGeo.setAttribute('position', new THREE.Float32BufferAttribute(fpos, 3));
    flagGeo.setAttribute('normal', new THREE.Float32BufferAttribute(fnor, 3));
    flagGeo.setAttribute('color', new THREE.Float32BufferAttribute(fcol, 3));
    flagGeo.setAttribute('aFlag', new THREE.Float32BufferAttribute(fflag, 4));
    const flagMat = new THREE.MeshLambertMaterial({ vertexColors: true, side: THREE.DoubleSide });
    flagMat.onBeforeCompile = (shader) => {
      shader.uniforms.uTime = uTime;
      shader.vertexShader = shader.vertexShader
        .replace('#include <common>', '#include <common>\nuniform float uTime;\nattribute vec4 aFlag;')
        .replace('#include <begin_vertex>',
          'vec3 transformed = vec3(position);\n' +
          'float fw = sin(uTime * 3.6 + aFlag.z + (position.x + position.z) * 1.7) + 0.4 * sin(uTime * 7.1 + aFlag.z * 1.7 + position.y * 3.0);\n' +
          'transformed += vec3(aFlag.x, 0.0, aFlag.y) * fw * 0.16 * aFlag.w;\n' +
          'transformed.y += sin(uTime * 5.3 + aFlag.z * 1.3) * 0.04 * aFlag.w;');
    };
    const flags = new THREE.Mesh(flagGeo, flagMat);
    group.add(flags);
    tris += fpos.length / 9;
  }

  // ---- cloud wisps: below the abyss rim and around the far peaks (merged quads)
  const cloudMesh = (() => {
    const tex = softTexture(THREE, 256, (g, s) => {
      g.clearRect(0, 0, s, s);
      const blob = (x, y, r, a) => { const grd = g.createRadialGradient(x, y, 0, x, y, r); grd.addColorStop(0, `rgba(255,255,255,${a})`); grd.addColorStop(0.55, `rgba(255,255,255,${a * 0.45})`); grd.addColorStop(1, 'rgba(255,255,255,0)'); g.fillStyle = grd; g.fillRect(x - r, y - r, r * 2, r * 2); };
      blob(128, 140, 110, 0.95); blob(80, 150, 70, 0.9); blob(180, 150, 75, 0.9); blob(120, 110, 60, 0.85); blob(60, 170, 50, 0.7); blob(200, 175, 45, 0.7);
    });
    const parts = [];
    const quad = (x, y, z, w, h, rotY, rotX, c) => {
      const m = new THREE.Matrix4().makeRotationFromEuler(new THREE.Euler(rotX, rotY, 0)).setPosition(x, y, z);
      m.multiply(new THREE.Matrix4().makeScale(w, h, 1));
      parts.push({ g: new THREE.PlaneGeometry(1, 1), m, c });
    };
    const warm = [1, 0.98, 0.95], cool = [0.9, 0.95, 1];
    // abyss sea of cloud: horizontal puffs plus a vertical face towards the rink
    const abyss = [];
    for (let i = 0; i < 60; i++) abyss.push([R(44, 170), R(-12, 4), R(-120, 120), R(28, 60), R(14, 30)]);
    abyss.sort((a, b) => b[0] - a[0]);
    for (const [x, y, z, w, d] of abyss) {
      quad(x, y, z, w, d, 0, -PI / 2, rng() < 0.5 ? warm : cool);
      if (x < 100) quad(x - 2, y + 3, z, w * 0.9, d * 0.7, -PI / 2, 0, cool);
    }
    // high wisps around the far peaks
    for (let i = 0; i < 18; i++) {
      const phi = R(-PI, PI), r = R(200, 330);
      quad(Math.sin(phi) * r, R(40, 75), Math.cos(phi) * r, R(70, 120), R(20, 36), 0, -PI / 2, cool);
      quad(Math.sin(phi) * r, R(40, 75), Math.cos(phi) * r, R(70, 120), R(12, 22), -phi, 0, cool);
    }
    // a few wisps clinging to the lake basin and the +Z foothills
    for (let i = 0; i < 8; i++) {
      const phi = LAKE_C + R(-0.5, 0.5), r = R(95, 125);
      quad(Math.sin(phi) * r, R(14, 26), Math.cos(phi) * r, R(30, 50), R(10, 16), 0, -PI / 2, cool);
    }
    const geo = mergeParts(THREE, parts, true);
    const mesh = new THREE.Mesh(geo, new THREE.MeshBasicMaterial({ map: tex, transparent: true, depthWrite: false, side: THREE.DoubleSide, vertexColors: true, opacity: 0.95 }));
    mesh.renderOrder = 2;
    group.add(mesh);
    tris += geo.attributes.position.count / 3;
    return mesh;
  })();

  // ---- falling snow (GPU animated points)
  {
    const N = 2200;
    const pos = new Float32Array(N * 3), seed = new Float32Array(N * 3);
    for (let i = 0; i < N; i++) {
      pos[i * 3] = R(-60, 60); pos[i * 3 + 1] = R(0, 36); pos[i * 3 + 2] = R(-55, 75);
      seed[i * 3] = R(0, 100); seed[i * 3 + 1] = R(1.2, 2.6); seed[i * 3 + 2] = R(0.18, 0.4);
    }
    const geo = new THREE.BufferGeometry();
    geo.setAttribute('position', new THREE.BufferAttribute(pos, 3));
    geo.setAttribute('aSeed', new THREE.BufferAttribute(seed, 3));
    geo.boundingSphere = new THREE.Sphere(new THREE.Vector3(0, 18, 10), 120);
    const tex = softTexture(THREE, 32, (g, s) => {
      const grd = g.createRadialGradient(s / 2, s / 2, 0, s / 2, s / 2, s / 2);
      grd.addColorStop(0, 'rgba(255,255,255,1)'); grd.addColorStop(0.4, 'rgba(255,255,255,0.8)'); grd.addColorStop(1, 'rgba(255,255,255,0)');
      g.fillStyle = grd; g.fillRect(0, 0, s, s);
    });
    const dpr = Math.min(window.devicePixelRatio || 1, 2);
    const scale = ((window.innerHeight || 800) * dpr) / 2;
    const mat = new THREE.ShaderMaterial({
      uniforms: { uTime: uTime, uScale: { value: scale }, map: { value: tex } },
      vertexShader: `
        uniform float uTime; uniform float uScale;
        attribute vec3 aSeed;
        varying float vA;
        void main() {
          vec3 p = position;
          p.y = mod(p.y - uTime * aSeed.y, 36.0);
          p.x += sin(uTime * 0.7 + aSeed.x) * 1.4 + sin(uTime * 2.1 + aSeed.x * 1.7) * 0.35;
          p.z += cos(uTime * 0.6 + aSeed.x * 1.3) * 1.2;
          vec4 mv = modelViewMatrix * vec4(p, 1.0);
          gl_PointSize = clamp(aSeed.z * uScale / -mv.z, 1.0, 40.0);
          gl_Position = projectionMatrix * mv;
          vA = smoothstep(0.0, 2.5, p.y) * (0.55 + 0.45 * sin(uTime * 3.0 + aSeed.x * 3.0));
        }`,
      fragmentShader: `
        uniform sampler2D map; varying float vA;
        void main() { vec4 t = texture2D(map, gl_PointCoord); gl_FragColor = vec4(t.rgb, t.a * vA * 0.9); }`,
      transparent: true, depthWrite: false,
    });
    const snow = new THREE.Points(geo, mat);
    snow.frustumCulled = false;
    snow.renderOrder = 3;
    group.add(snow);
  }

  return {
    update(dt, time) {
      uTime.value = time;
      cloudMesh.position.x = Math.sin(time * 0.05) * 2.5;
      cloudMesh.position.z = Math.cos(time * 0.037) * 2.0;
    },
  };
}
