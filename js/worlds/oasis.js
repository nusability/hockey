// Desert Oasis — a lush oasis in a vast desert at golden hour.
// Rolling dunes (one displaced, non-uniform grid), a turquoise pool with rippling
// water beside the far corner of the pitch, instanced palms (swaying in a vertex
// shader), sandstone ruins with an arched gateway, a tent camp with striped canvas,
// cacti, rocks, desert grass, a camel caravan on the dunes, drifting dust and a
// huge low sun. See README.md for the contract.

// ---------------------------------------------------------------- deterministic helpers
function mulberry32(a) {
  return function () {
    a |= 0; a = (a + 0x6d2b79f5) | 0;
    let t = Math.imul(a ^ (a >>> 15), 1 | a);
    t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t;
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  };
}
function hash2(ix, iz) {
  let h = Math.imul(ix, 374761393) + Math.imul(iz, 668265263);
  h = Math.imul(h ^ (h >>> 13), 1274126177);
  h ^= h >>> 16;
  return (h >>> 0) / 4294967296;
}
function vnoise(x, z) {
  const ix = Math.floor(x), iz = Math.floor(z);
  const fx = x - ix, fz = z - iz;
  const sx = fx * fx * (3 - 2 * fx), sz = fz * fz * (3 - 2 * fz);
  const a = hash2(ix, iz), b = hash2(ix + 1, iz), c = hash2(ix, iz + 1), d = hash2(ix + 1, iz + 1);
  return (a + (b - a) * sx + (c - a) * sz + (a - b - c + d) * sx * sz) * 2 - 1;
}
function fbm(x, z, oct) {
  let s = 0, a = 1, f = 1, n = 0;
  for (let i = 0; i < oct; i++) { s += vnoise(x * f + i * 13.7, z * f + i * 7.1) * a; n += a; a *= 0.5; f *= 2.1; }
  return s / n;
}
const clamp01 = (v) => (v < 0 ? 0 : v > 1 ? 1 : v);
const smooth = (t) => t * t * (3 - 2 * t);
function sdRound(x, z, hw, hl, rr) {
  const qx = Math.abs(x) - (hw - rr), qz = Math.abs(z) - (hl - rr);
  return Math.hypot(Math.max(qx, 0), Math.max(qz, 0)) + Math.min(Math.max(qx, qz), 0) - rr;
}

// ---------------------------------------------------------------- landscape
// Two pools: the big one directly behind the far goal (the play camera's scenery
// window) and a second one hugging the far +X corner (seen from the goal camera).
const POOLS = [
  { x: 0, z: 46, R: 10.5, ph: 0.6 },
  { x: 27, z: 32, R: 9.5, ph: 2.4 },
];
function poolR(p, th) {
  return p.R * (1 + 0.16 * Math.sin(2 * th + p.ph) + 0.09 * Math.sin(3 * th + 1.9 + p.ph) + 0.05 * Math.sin(5 * th + 0.4));
}
/** Distance to the nearest pool centre in units of the local shoreline radius (1 = shoreline). */
function poolDist(x, z) {
  let best = 1e9;
  for (const p of POOLS) {
    const dx = x - p.x, dz = z - p.z;
    const d = Math.hypot(dx, dz) / poolR(p, Math.atan2(dz, dx));
    if (d < best) best = d;
  }
  return best;
}
/** Terrain height. Flat apron around the pitch, dunes beyond, shallow basins under the pools. */
function height(x, z) {
  const d = sdRound(x, z, 22, 34, 10);
  const m = smooth(clamp01(d / 18));
  const n1 = fbm(x * 0.013 + 5.3, z * 0.013 + 2.2, 2);
  const ridge = Math.pow(1 - Math.abs(n1), 1.6) * 17;
  const roll = fbm(x * 0.03 + 9, z * 0.03 + 4, 3) * 3.5 + fbm(x * 0.09, z * 0.09, 2) * 0.6;
  let h = ridge + roll + 3;
  // keep the ground low behind the user's goal (the play camera sits there)
  const back = smooth(clamp01((-z - 26) / 30)) * (1 - smooth(clamp01((Math.abs(x) - 22) / 16)));
  const pd = poolDist(x, z);
  const flat = smooth(clamp01((pd - 1.1) / 0.7)); // pools stay on flat ground
  h *= (1 - 0.9 * back) * m * flat;
  // shallow basin under the pools
  h -= 0.45 * smooth(clamp01(1 - (pd - 0.2) / 1.05));
  return -0.05 + h;
}

// ---------------------------------------------------------------- geometry helpers
/** Merge indexed/non-indexed geometries (with optional matrix + vertex colour) into one indexed geometry. */
function mergeGeos(THREE, items, opts = {}) {
  const pos = [], nor = [], uv = [], col = [], idx = [];
  let off = 0;
  const v = new THREE.Vector3();
  for (const it of items) {
    const g = it.geo;
    const p = g.attributes.position, n = g.attributes.normal, u = g.attributes.uv;
    const m = it.matrix || null;
    const nm = m ? new THREE.Matrix3().getNormalMatrix(m) : null;
    for (let i = 0; i < p.count; i++) {
      v.fromBufferAttribute(p, i); if (m) v.applyMatrix4(m);
      pos.push(v.x, v.y, v.z);
      if (opts.projectUV) uv.push((v.x + v.z) * opts.projectUV, v.y * opts.projectUV);
      else if (u) uv.push(u.getX(i), u.getY(i)); else uv.push(0, 0);
      if (n) { v.fromBufferAttribute(n, i); if (nm) v.applyMatrix3(nm).normalize(); nor.push(v.x, v.y, v.z); } else nor.push(0, 1, 0);
      const c = it.color; col.push(c ? c.r : 1, c ? c.g : 1, c ? c.b : 1);
    }
    if (g.index) for (let i = 0; i < g.index.count; i++) idx.push(g.index.getX(i) + off);
    else for (let i = 0; i < p.count; i++) idx.push(i + off);
    off += p.count;
  }
  const out = new THREE.BufferGeometry();
  out.setAttribute('position', new THREE.Float32BufferAttribute(pos, 3));
  out.setAttribute('normal', new THREE.Float32BufferAttribute(nor, 3));
  out.setAttribute('uv', new THREE.Float32BufferAttribute(uv, 2));
  out.setAttribute('color', new THREE.Float32BufferAttribute(col, 3));
  out.setIndex(idx);
  return out;
}

function canvasTex(THREE, w, h, draw, opts = {}) {
  const c = document.createElement('canvas');
  c.width = w; c.height = h;
  draw(c.getContext('2d'), w, h);
  const t = new THREE.CanvasTexture(c);
  t.colorSpace = THREE.SRGBColorSpace;
  if (opts.repeat) { t.wrapS = t.wrapT = THREE.RepeatWrapping; }
  t.anisotropy = 4;
  return t;
}

/** Vertex-shader sway. mode: 'radius' (palm crowns), 'height' (grass), 'flag' (bunting). */
function addSway(mat, uTime, instanced, mode) {
  const weight = mode === 'radius' ? 'length(position.xz) * 0.32' : mode === 'height' ? 'clamp(position.y, 0.0, 2.0) * 0.5' : '0.35';
  const phase = instanced ? 'instanceMatrix[3].x * 0.31 + instanceMatrix[3].z * 0.17' : 'position.x * 0.9 + position.z * 0.4';
  mat.onBeforeCompile = (shader) => {
    shader.uniforms.uTime = uTime;
    shader.vertexShader = 'uniform float uTime;\n' + shader.vertexShader.replace('#include <begin_vertex>', `
      #include <begin_vertex>
      {
        float ph = ${phase};
        float w = ${weight};
        float s1 = sin(uTime * 1.1 + ph);
        float s2 = sin(uTime * 2.7 + ph * 1.9 + position.x * 1.3);
        transformed.x += (s1 * 0.10 + s2 * 0.03) * w;
        transformed.z += (cos(uTime * 0.9 + ph * 1.3) * 0.08 + s2 * 0.025) * w;
        transformed.y += s2 * 0.03 * w;
      }`);
  };
  mat.customProgramCacheKey = () => `oasis-sway-${instanced ? 'i' : 'm'}-${mode}`;
}

// ---------------------------------------------------------------- world
export default {
  id: 'oasis',
  sport: 'field',
  name: { en: 'Desert Oasis', de: 'Wüstenoase' },
  tagline: { en: 'Green turf between golden dunes and palms.', de: 'Grüner Rasen zwischen goldenen Dünen und Palmen.' },
  sky: 'linear-gradient(180deg, #3b2a6e 0%, #8a3f6a 14%, #e0693f 34%, #f6a35a 60%, #ffd7a0 100%)',
  light: {
    hemiSky: 0xffd9a8, hemiGround: 0xb27a4c, hemiIntensity: 0.9,
    sun: 0xffc98a, sunIntensity: 2.5, sunPos: [-40, 30, 14],
    fog: { color: 0xf2a866, near: 95, far: 320 },
  },
  surface: {
    base: '#4c9a3f', stripe: '#448f39', lines: '#fff7e6',
    // sandy wear around the edges and in the goal mouths
    decorate(ctx, W, H, h) {
      const rng = mulberry32(77);
      const R = (a, b) => a + rng() * (b - a);
      ctx.save();
      ctx.fillStyle = '#d6ac6a';
      for (let i = 0; i < 120; i++) {
        // patches hugging the outline (denser near the corners)
        const side = i % 4;
        let x, y;
        if (side === 0) { x = R(0, 60); y = R(0, H); }
        else if (side === 1) { x = W - R(0, 60); y = R(0, H); }
        else if (side === 2) { x = R(0, W); y = R(0, 70); }
        else { x = R(0, W); y = H - R(0, 70); }
        ctx.globalAlpha = R(0.08, 0.22);
        ctx.beginPath(); ctx.ellipse(x, y, R(14, 60), R(8, 26), R(0, Math.PI), 0, Math.PI * 2); ctx.fill();
      }
      // trampled goal mouths
      ctx.fillStyle = '#b89a55';
      for (const t of [0.045, 0.955]) {
        for (let i = 0; i < 18; i++) {
          ctx.globalAlpha = R(0.05, 0.13);
          ctx.beginPath(); ctx.ellipse(W / 2 + R(-140, 140), H * t + R(-40, 40), R(30, 110), R(14, 40), R(0, Math.PI), 0, Math.PI * 2); ctx.fill();
        }
      }
      // wind-blown sand streaks along the pool side (+X)
      ctx.strokeStyle = '#e2bc7c'; ctx.lineWidth = 3;
      for (let i = 0; i < 26; i++) {
        ctx.globalAlpha = R(0.06, 0.16);
        const x0 = W - R(4, 90), y0 = R(0, H);
        ctx.beginPath(); ctx.moveTo(x0, y0); ctx.quadraticCurveTo(x0 - R(20, 70), y0 + R(-30, 30), x0 - R(40, 150), y0 + R(-40, 40)); ctx.stroke();
      }
      ctx.restore();
    },
  },
  border: { color: 0xd28b58, top: 0x2dd4bf, height: 1.1, glass: false, base: 0xcfa066 },
  ball: { color: 0xffffff },
  goal: { post: 0xef4444, net: 0xfff1d6 },

  buildScenery(group, ctx) {
    const { THREE } = ctx;
    const rng = mulberry32(20260913);
    const R = (a, b) => a + rng() * (b - a);
    const uTime = { value: 0 };
    const updaters = [];
    const dummy = new THREE.Object3D();
    const tmpColor = new THREE.Color();
    const safe = (label, fn) => { try { fn(); } catch (e) { console.error(`oasis scenery: ${label} failed`, e); } };
    const groundY = (x, z) => height(x, z);
    const inSlab = (x, z) => Math.abs(x) < 18.5 && Math.abs(z) < 33.5;

    // ---------------------------------------------------------- dunes
    safe('dunes', () => {
      const N = 100, half = 330;
      const map = (u) => half * (0.28 * u + 0.72 * u * u * u);
      const verts = (N + 1) * (N + 1);
      const pos = new Float32Array(verts * 3), col = new Float32Array(verts * 3);
      const idx = [];
      const low = [0.86, 0.60, 0.34], high = [0.99, 0.85, 0.62], warm = [1.0, 0.76, 0.42], cool = [0.72, 0.46, 0.50];
      const green = [0.52, 0.62, 0.30], wet = [0.55, 0.40, 0.25], trampled = [0.84, 0.64, 0.40];
      let k = 0;
      for (let j = 0; j <= N; j++) {
        for (let i = 0; i <= N; i++) {
          const x = map((i / N) * 2 - 1), z = map((j / N) * 2 - 1);
          const h = height(x, z);
          pos[k * 3] = x; pos[k * 3 + 1] = h; pos[k * 3 + 2] = z;
          k++;
        }
      }
      for (let j = 0; j < N; j++) {
        for (let i = 0; i < N; i++) {
          const a = j * (N + 1) + i, b = a + 1, c = a + N + 1, d = c + 1;
          idx.push(a, c, b, b, c, d);
        }
      }
      const geo = new THREE.BufferGeometry();
      geo.setAttribute('position', new THREE.BufferAttribute(pos, 3));
      geo.setIndex(idx);
      geo.computeVertexNormals();
      const nor = geo.attributes.normal;
      const sunDir = new THREE.Vector3(-40, 30, 14).normalize();
      const nv = new THREE.Vector3();
      for (let v = 0; v < verts; v++) {
        const x = pos[v * 3], h = pos[v * 3 + 1], z = pos[v * 3 + 2];
        nv.fromBufferAttribute(nor, v);
        const facing = nv.dot(sunDir) - sunDir.y; // relative to flat ground
        const t = clamp01(h / 15);
        let r = low[0] + (high[0] - low[0]) * t, g = low[1] + (high[1] - low[1]) * t, b = low[2] + (high[2] - low[2]) * t;
        const sh = clamp01(-facing * 3.0) * 0.7, lt = clamp01(facing * 3.0) * 0.45;
        r += (cool[0] - r) * sh; g += (cool[1] - g) * sh; b += (cool[2] - b) * sh;
        r += (warm[0] - r) * lt; g += (warm[1] - g) * lt; b += (warm[2] - b) * lt;
        const pd = poolDist(x, z);
        if (pd < 2.4) { const f = clamp01((2.4 - pd) / 1.4) * 0.55 * (1 + 0.5 * vnoise(x * 0.4, z * 0.4)); r += (green[0] - r) * f; g += (green[1] - g) * f; b += (green[2] - b) * f; }
        if (pd < 1.35) { const f = clamp01((1.35 - pd) / 0.3); r += (wet[0] - r) * f; g += (wet[1] - g) * f; b += (wet[2] - b) * f; }
        const ap = 1 - smooth(clamp01(sdRound(x, z, 22, 34, 10) / 14));
        r += (trampled[0] - r) * ap * 0.5; g += (trampled[1] - g) * ap * 0.5; b += (trampled[2] - b) * ap * 0.5;
        const sp = vnoise(x * 0.7 + 3, z * 0.7) * 0.025 + fbm(x * 0.045 + 1, z * 0.045 + 8, 2) * 0.06;
        col[v * 3] = r + sp; col[v * 3 + 1] = g + sp; col[v * 3 + 2] = b + sp;
      }
      geo.setAttribute('color', new THREE.BufferAttribute(col, 3));
      const mesh = new THREE.Mesh(geo, new THREE.MeshLambertMaterial({ vertexColors: true }));
      mesh.receiveShadow = true;
      group.add(mesh);
    });

    // ---------------------------------------------------------- pool
    safe('pool', () => {
      const rings = 11, segs = 52;
      const pos = [], col = [], idx = [];
      const cIn = [0.05, 0.50, 0.52], cOut = [0.45, 0.88, 0.82];
      const clampSlab = (x, z, lim) => { // keep off the pitch slab
        if (Math.abs(x) < lim && Math.abs(z) < lim + 15) { const px = lim - Math.abs(x), pz = lim + 15 - Math.abs(z); if (px < pz) x = Math.sign(x || 1) * lim; else z = Math.sign(z || 1) * (lim + 15); }
        return [x, z];
      };
      for (const P of POOLS) {
        const off = pos.length / 3;
        pos.push(P.x, 0.08, P.z); col.push(...cIn);
        for (let r = 1; r <= rings; r++) {
          const f = r / rings;
          for (let s = 0; s < segs; s++) {
            const th = (s / segs) * Math.PI * 2;
            const rr = poolR(P, th) * f;
            const [x, z] = clampSlab(P.x + Math.cos(th) * rr, P.z + Math.sin(th) * rr, 18.6);
            pos.push(x, 0.08, z);
            const t = smooth(f);
            col.push(cIn[0] + (cOut[0] - cIn[0]) * t, cIn[1] + (cOut[1] - cIn[1]) * t, cIn[2] + (cOut[2] - cIn[2]) * t);
          }
        }
        for (let s = 0; s < segs; s++) idx.push(off, off + 1 + ((s + 1) % segs), off + 1 + s);
        for (let r = 1; r < rings; r++) {
          const a0 = off + 1 + (r - 1) * segs, b0 = off + 1 + r * segs;
          for (let s = 0; s < segs; s++) {
            const s1 = (s + 1) % segs;
            idx.push(a0 + s, b0 + s1, b0 + s, a0 + s, a0 + s1, b0 + s1);
          }
        }
      }
      const geo = new THREE.BufferGeometry();
      geo.setAttribute('position', new THREE.Float32BufferAttribute(pos, 3));
      geo.setAttribute('color', new THREE.Float32BufferAttribute(col, 3));
      geo.setIndex(idx);
      geo.computeVertexNormals();
      const water = new THREE.Mesh(geo, new THREE.MeshPhongMaterial({
        vertexColors: true, transparent: true, opacity: 0.86, shininess: 110, specular: 0xfff0c0, depthWrite: false,
      }));
      group.add(water);
      // wet shore
      const shore = geo.clone();
      const sp = shore.attributes.position;
      const perPool = 1 + rings * segs;
      for (let i = 0; i < sp.count; i++) {
        const P = POOLS[Math.floor(i / perPool)];
        const x = sp.getX(i), z = sp.getZ(i);
        const [nx, nz] = clampSlab(P.x + (x - P.x) * 1.16, P.z + (z - P.z) * 1.16, 18.4);
        sp.setXYZ(i, nx, -0.07, nz);
      }
      shore.deleteAttribute('color');
      shore.computeVertexNormals();
      group.add(new THREE.Mesh(shore, new THREE.MeshLambertMaterial({ color: 0x8c6541 })));
      // sparkles
      const nS = 110, spos = new Float32Array(nS * 3), scol = new Float32Array(nS * 3), sphase = [];
      for (let i = 0; i < nS; i++) {
        const P = POOLS[i % POOLS.length];
        const th = R(0, Math.PI * 2), rr = poolR(P, th) * Math.sqrt(R(0.05, 0.9));
        const [x, z] = clampSlab(P.x + Math.cos(th) * rr, P.z + Math.sin(th) * rr, 19);
        spos.set([x, 0.16, z], i * 3); sphase.push(R(0, 6.28), R(2, 5));
      }
      const sg = new THREE.BufferGeometry();
      sg.setAttribute('position', new THREE.BufferAttribute(spos, 3));
      sg.setAttribute('color', new THREE.BufferAttribute(scol, 3));
      const sparkles = new THREE.Points(sg, new THREE.PointsMaterial({ size: 0.28, vertexColors: true, transparent: true, depthWrite: false, blending: THREE.AdditiveBlending, sizeAttenuation: true }));
      group.add(sparkles);
      const base = pos.slice();
      const pa = geo.attributes.position;
      updaters.push((dt, time) => {
        for (let i = 0; i < pa.count; i++) {
          const x = base[i * 3], z = base[i * 3 + 2];
          const y = 0.08 + Math.sin(x * 0.9 + time * 1.4) * 0.035 + Math.sin(z * 1.3 - time * 1.1 + x * 0.3) * 0.03 + Math.sin((x + z) * 0.5 + time * 0.7) * 0.02;
          pa.setY(i, y);
        }
        pa.needsUpdate = true;
        geo.computeVertexNormals();
        for (let i = 0; i < nS; i++) {
          const v = Math.max(0, Math.sin(time * sphase[i * 2 + 1] + sphase[i * 2]));
          const b = v * v * v;
          scol[i * 3] = b; scol[i * 3 + 1] = b * 0.98; scol[i * 3 + 2] = b * 0.85;
        }
        sg.attributes.color.needsUpdate = true;
      });
    });

    // ---------------------------------------------------------- palms
    const palms = [];
    safe('palms', () => {
      const addPalm = (x, z, h) => { if (!inSlab(x, z) && poolDist(x, z) > 1.1) palms.push({ x, z, h }); };
      for (let i = 0; i < 16; i++) { // around the big pool behind the far goal
        const th = R(0, Math.PI * 2), rr = poolR(POOLS[0], th) * R(1.15, 1.7);
        addPalm(POOLS[0].x + Math.cos(th) * rr, POOLS[0].z + Math.sin(th) * rr, R(5, 9.5));
      }
      for (let i = 0; i < 12; i++) { // around the side pool
        const th = R(0, Math.PI * 2), rr = poolR(POOLS[1], th) * R(1.18, 1.75);
        addPalm(POOLS[1].x + Math.cos(th) * rr, POOLS[1].z + Math.sin(th) * rr, R(5, 8.5));
      }
      for (let i = 0; i < 11; i++) { // around the ruins
        const a = R(0, Math.PI * 2), rr = R(7, 15);
        const x = -30 + Math.cos(a) * rr, z = 24 + Math.sin(a) * rr;
        if (x < -19.5) addPalm(x, z, R(4.8, 8));
      }
      for (let i = 0; i < 6; i++) addPalm(R(-34, -20), R(36, 56), R(6, 10)); // far -X corner grove
      for (let i = 0; i < 8; i++) { const s = i % 2 ? 1 : -1; addPalm(s * R(20, 27), R(-22, 12), R(4.5, 7)); } // side strips
      for (let i = 0; i < 4; i++) { const s = i % 2 ? 1 : -1; addPalm(s * R(23, 34), R(-52, -34), R(5, 8)); } // behind the user

      const n = palms.length;
      // trunk: bent cylinder, unit height
      const trunkGeo = new THREE.CylinderGeometry(0.2, 0.36, 1, 7, 8, false);
      trunkGeo.translate(0, 0.5, 0);
      { const p = trunkGeo.attributes.position; for (let i = 0; i < p.count; i++) { const t = p.getY(i); p.setX(i, p.getX(i) + 0.9 * t * t); } trunkGeo.computeVertexNormals(); }
      const barkTex = canvasTex(THREE, 64, 256, (c, w, h) => {
        c.fillStyle = '#7d5232'; c.fillRect(0, 0, w, h);
        for (let y = 0; y < h; y += 14) {
          c.fillStyle = `rgba(${40 + Math.random() * 30 | 0},${20 + Math.random() * 20 | 0},10,0.55)`; c.fillRect(0, y, w, 5);
          c.fillStyle = `rgba(255,200,140,${0.08 + Math.random() * 0.12})`; c.fillRect(0, y + 6, w, 3);
        }
      }, { repeat: true });
      barkTex.repeat.set(1, 7);
      const trunks = new THREE.InstancedMesh(trunkGeo, new THREE.MeshLambertMaterial({ map: barkTex }), n);
      trunks.castShadow = true; trunks.frustumCulled = false;
      // crown: solid serrated fronds, alpha-tested texture; opaque brown patch at the bottom-right for bulb/coconuts
      const frondTex = canvasTex(THREE, 256, 128, (c, w, h) => {
        c.clearRect(0, 0, w, h);
        const grad = c.createLinearGradient(0, 0, w, 0);
        grad.addColorStop(0, '#2f6b2a'); grad.addColorStop(0.5, '#4f9a3c'); grad.addColorStop(1, '#8cc45a');
        c.fillStyle = grad;
        c.beginPath(); c.moveTo(0, 64);
        const hw = (x) => 58 * Math.min(1, x / 18) * (1 - 0.1 * x / w);
        for (let x = 4; x <= w; x += 8) { const j = (x / 8) % 2 ? 1 : 0.5; c.lineTo(x, 64 - hw(x) * j); }
        c.lineTo(w, 64);
        for (let x = w; x >= 4; x -= 8) { const j = (x / 8) % 2 ? 1 : 0.5; c.lineTo(x, 64 + hw(x) * j); }
        c.closePath(); c.fill();
        c.strokeStyle = '#8a7a2a'; c.lineWidth = 4; c.beginPath(); c.moveTo(0, 64); c.lineTo(w, 64); c.stroke();
        c.fillStyle = '#6b4a2a'; c.fillRect(w - 24, h - 24, 24, 24);
      });
      const frondStrip = (len, w0, droop, segs = 5) => {
        const pos = [], nor = [], uv = [], idx = [];
        for (let i = 0; i <= segs; i++) {
          const t = i / segs, x = len * t, y = 0.35 * Math.sin(Math.PI * Math.min(t, 0.5)) * 0.6 - droop * t * t;
          const w = w0 * (1 - 0.82 * t) + 0.06;
          pos.push(x, y, -w / 2, x, y, w / 2); nor.push(0, 1, 0, 0, 1, 0); uv.push(t, 0.02, t, 0.98);
          if (i < segs) { const a = i * 2; idx.push(a, a + 1, a + 2, a + 1, a + 3, a + 2); }
        }
        const g = new THREE.BufferGeometry();
        g.setAttribute('position', new THREE.Float32BufferAttribute(pos, 3));
        g.setAttribute('normal', new THREE.Float32BufferAttribute(nor, 3));
        g.setAttribute('uv', new THREE.Float32BufferAttribute(uv, 2));
        g.setIndex(idx);
        return g;
      };
      const makeCrown = (seed) => {
        const r2 = mulberry32(seed);
        const items = [];
        const m = new THREE.Matrix4(), q = new THREE.Quaternion(), e = new THREE.Euler();
        const layers = [[6, 0.35, 3.3, 1.0], [6, -0.12, 3.6, 1.5], [3, 0.95, 2.2, 0.6]];
        let a0 = 0;
        for (const [count, tilt, len, droop] of layers) {
          for (let i = 0; i < count; i++) {
            const yaw = a0 + (i / count) * Math.PI * 2 + (r2() - 0.5) * 0.5;
            e.set(0, yaw, tilt + (r2() - 0.5) * 0.25, 'YXZ');
            m.compose(new THREE.Vector3(0, 0.15, 0), q.setFromEuler(e), new THREE.Vector3(1, 1, 1));
            items.push({ geo: frondStrip(len * (0.85 + r2() * 0.3), 0.6, droop * (0.8 + r2() * 0.5)), matrix: m.clone() });
          }
          a0 += 0.6;
        }
        const solidUV = (g) => { const u = g.attributes.uv; for (let i = 0; i < u.count; i++) u.setXY(i, 0.955, 0.09); return g; };
        items.push({ geo: solidUV(new THREE.SphereGeometry(0.42, 6, 4)), matrix: new THREE.Matrix4().makeTranslation(0, 0.05, 0) });
        for (let i = 0; i < 2; i++) {
          m.compose(new THREE.Vector3(Math.cos(i * 2.4) * 0.35, -0.2, Math.sin(i * 2.4) * 0.35), q.identity(), new THREE.Vector3(1, 1, 1));
          items.push({ geo: solidUV(new THREE.IcosahedronGeometry(0.24, 0)), matrix: m.clone() });
        }
        return mergeGeos(THREE, items);
      };
      const crownMat = new THREE.MeshLambertMaterial({ map: frondTex, alphaTest: 0.5, side: THREE.DoubleSide });
      addSway(crownMat, uTime, true, 'radius');
      const crownGeos = [makeCrown(11), makeCrown(23)];
      const crownCounts = [Math.ceil(n / 2), Math.floor(n / 2)];
      const crowns = crownGeos.map((g, i) => {
        const mesh = new THREE.InstancedMesh(g, crownMat, crownCounts[i]);
        mesh.castShadow = true; mesh.frustumCulled = false;
        return mesh;
      });
      const ci = [0, 0];
      palms.forEach((p, i) => {
        const yaw = R(0, Math.PI * 2), s = R(0.85, 1.25);
        const y = groundY(p.x, p.z) - 0.15;
        dummy.position.set(p.x, y, p.z); dummy.rotation.set(0, yaw, 0); dummy.scale.set(s, p.h, s);
        dummy.updateMatrix(); trunks.setMatrixAt(i, dummy.matrix);
        const bx = 0.9 * s;
        const cx = p.x + Math.cos(yaw) * bx, cz = p.z - Math.sin(yaw) * bx;
        const which = i % 2, k = ci[which]++;
        const cs = R(0.85, 1.15) * (0.75 + p.h / 20);
        dummy.position.set(cx, y + p.h, cz); dummy.rotation.set(0, R(0, 6.28), 0); dummy.scale.set(cs, cs, cs);
        dummy.updateMatrix(); crowns[which].setMatrixAt(k, dummy.matrix);
        crowns[which].setColorAt(k, tmpColor.setRGB(R(0.85, 1.05), R(0.9, 1.08), R(0.8, 1.0)));
      });
      group.add(trunks, ...crowns);
    });

    // ---------------------------------------------------------- rocks (+ campfire stones)
    safe('rocks', () => {
      const geo = new THREE.IcosahedronGeometry(1, 1);
      const p = geo.attributes.position;
      const r2 = mulberry32(5);
      for (let i = 0; i < p.count; i++) p.setXYZ(i, p.getX(i) * (0.8 + r2() * 0.4), p.getY(i) * 0.65 * (0.85 + r2() * 0.3), p.getZ(i) * (0.8 + r2() * 0.4));
      geo.computeVertexNormals();
      const spots = [];
      for (let i = 0; i < 70; i++) {
        const x = R(-90, 90), z = R(-70, 110);
        if (inSlab(x, z) || sdRound(x, z, 20, 35, 6) < 0 || poolDist(x, z) < 1.25) { i--; continue; }
        spots.push({ x, z, s: R(0.4, 2.4) });
      }
      for (let i = 0; i < 26; i++) { const P = POOLS[i % 2]; const th = R(0, 6.28), rr = poolR(P, th) * R(1.03, 1.14); const x = P.x + Math.cos(th) * rr, z = P.z + Math.sin(th) * rr; if (!inSlab(x, z)) spots.push({ x, z, s: R(0.25, 0.6) }); }
      for (let i = 0; i < 8; i++) { const a = (i / 8) * 6.28; spots.push({ x: -33 + Math.cos(a) * 1.1, z: 24 + Math.sin(a) * 1.1, s: R(0.3, 0.42) }); }
      const rocks = new THREE.InstancedMesh(geo, new THREE.MeshLambertMaterial({ color: 0xffffff }), spots.length);
      rocks.frustumCulled = false;
      const palette = [0xc8865a, 0xd9a072, 0xe3b487, 0x9a6642, 0xb07a55];
      spots.forEach((s, i) => {
        dummy.position.set(s.x, groundY(s.x, s.z) - s.s * 0.25, s.z);
        dummy.rotation.set(R(-0.2, 0.2), R(0, 6.28), R(-0.2, 0.2)); dummy.scale.set(s.s * R(0.8, 1.4), s.s, s.s * R(0.8, 1.4));
        dummy.updateMatrix(); rocks.setMatrixAt(i, dummy.matrix);
        rocks.setColorAt(i, tmpColor.setHex(palette[Math.floor(rng() * palette.length)]).multiplyScalar(R(0.85, 1.1)));
      });
      group.add(rocks);
    });

    // ---------------------------------------------------------- cacti
    safe('cacti', () => {
      const tex = canvasTex(THREE, 64, 64, (c, w, h) => {
        for (let i = 0; i < 8; i++) { c.fillStyle = i % 2 ? '#3d7f39' : '#5aa04a'; c.fillRect(i * 8, 0, 8, h); }
        c.fillStyle = '#f3f0c8'; for (let i = 0; i < 8; i++) for (let y = 4; y < h; y += 10) c.fillRect(i * 8 + 3, y, 2, 2);
      }, { repeat: true });
      tex.repeat.set(3, 1);
      const items = [];
      const m = new THREE.Matrix4();
      const cyl = (rt, rb, h) => new THREE.CylinderGeometry(rt, rb, h, 7, 1, true);
      const cap = (r) => new THREE.SphereGeometry(r, 7, 3, 0, Math.PI * 2, 0, Math.PI / 2);
      items.push({ geo: cyl(0.3, 0.38, 2.6), matrix: m.makeTranslation(0, 1.3, 0).clone() });
      items.push({ geo: cap(0.3), matrix: m.makeTranslation(0, 2.6, 0).clone() });
      for (const [sx, y0, h] of [[1, 1.1, 1.1], [-1, 0.75, 1.5]]) {
        items.push({ geo: cyl(0.17, 0.17, 0.7).rotateZ(Math.PI / 2), matrix: m.makeTranslation(sx * 0.55, y0, 0).clone() });
        items.push({ geo: cyl(0.16, 0.18, h), matrix: m.makeTranslation(sx * 0.82, y0 + h / 2 - 0.05, 0).clone() });
        items.push({ geo: cap(0.16), matrix: m.makeTranslation(sx * 0.82, y0 + h - 0.05, 0).clone() });
      }
      const geo = mergeGeos(THREE, items);
      const spots = [];
      for (let i = 0; i < 26; i++) {
        const x = R(-70, 70), z = R(-60, 90);
        if (inSlab(x, z) || sdRound(x, z, 21, 36, 6) < 0 || poolDist(x, z) < 1.7 || Math.hypot(x + 31, z - 26) < 13) { i--; continue; }
        spots.push({ x, z });
      }
      const cacti = new THREE.InstancedMesh(geo, new THREE.MeshLambertMaterial({ map: tex, color: 0xffffff }), spots.length);
      cacti.frustumCulled = false;
      spots.forEach((s, i) => {
        const sc = R(0.7, 1.5);
        dummy.position.set(s.x, groundY(s.x, s.z) - 0.1, s.z); dummy.rotation.set(0, R(0, 6.28), 0); dummy.scale.set(sc, sc * R(0.9, 1.4), sc);
        dummy.updateMatrix(); cacti.setMatrixAt(i, dummy.matrix);
        cacti.setColorAt(i, tmpColor.setRGB(R(0.8, 1.05), R(0.9, 1.05), R(0.8, 1.0)));
      });
      group.add(cacti);
    });

    // ---------------------------------------------------------- grass & reeds
    safe('grass', () => {
      const tex = canvasTex(THREE, 64, 64, (c, w, h) => {
        c.clearRect(0, 0, w, h);
        for (let i = 0; i < 11; i++) {
          const x0 = 8 + i * 4.5, top = 4 + Math.random() * 14, lean = (Math.random() - 0.5) * 22;
          c.strokeStyle = i % 2 ? '#e8d27a' : '#cdb75e'; c.lineWidth = 2.6;
          c.beginPath(); c.moveTo(x0, h); c.quadraticCurveTo(x0 + lean * 0.4, h * 0.5, x0 + lean, top); c.stroke();
        }
      });
      const plane = new THREE.PlaneGeometry(1, 1); plane.translate(0, 0.5, 0);
      const items = [];
      for (let i = 0; i < 3; i++) items.push({ geo: plane, matrix: new THREE.Matrix4().makeRotationY((i / 3) * Math.PI) });
      const geo = mergeGeos(THREE, items);
      const mat = new THREE.MeshLambertMaterial({ map: tex, alphaTest: 0.4, side: THREE.DoubleSide, color: 0xffffff });
      addSway(mat, uTime, true, 'height');
      const spots = [];
      for (let i = 0; i < 170; i++) { // reeds and lush grass around the pools
        const P = POOLS[i % 2];
        const th = R(0, 6.28), f = R(1.06, 2.0), rr = poolR(P, th) * f;
        const x = P.x + Math.cos(th) * rr, z = P.z + Math.sin(th) * rr;
        if (inSlab(x, z)) continue;
        const near = f < 1.3;
        spots.push({ x, z, s: near ? R(1.4, 2.4) : R(0.8, 1.5), c: near ? [0.35, 0.6, 0.3] : [0.55, 0.7, 0.35] });
      }
      for (let i = 0; i < 230; i++) { // dry tufts everywhere else
        const x = R(-80, 80), z = R(-60, 95);
        if (inSlab(x, z) || sdRound(x, z, 19, 34, 6) < 0 || poolDist(x, z) < 1.9) { i--; continue; }
        spots.push({ x, z, s: R(0.6, 1.4), c: [R(0.75, 0.95), R(0.65, 0.85), R(0.35, 0.55)] });
      }
      const grass = new THREE.InstancedMesh(geo, mat, spots.length);
      grass.frustumCulled = false;
      spots.forEach((s, i) => {
        dummy.position.set(s.x, groundY(s.x, s.z) - 0.05, s.z); dummy.rotation.set(0, R(0, 3.14), 0); dummy.scale.set(s.s * 1.3, s.s, s.s * 1.3);
        dummy.updateMatrix(); grass.setMatrixAt(i, dummy.matrix);
        grass.setColorAt(i, tmpColor.setRGB(...s.c));
      });
      group.add(grass);
    });

    // ---------------------------------------------------------- ruins
    safe('ruins', () => {
      const tex = canvasTex(THREE, 256, 256, (c, w, h) => {
        c.fillStyle = '#a9714a'; c.fillRect(0, 0, w, h);
        const r2 = mulberry32(3);
        for (let row = 0; row < 8; row++) {
          const off = row % 2 ? 32 : 0;
          for (let bx = -1; bx < 5; bx++) {
            const l = 0.82 + r2() * 0.3;
            c.fillStyle = `rgb(${Math.min(255, 222 * l) | 0},${Math.min(255, 170 * l) | 0},${Math.min(255, 118 * l) | 0})`;
            c.fillRect(bx * 64 + off + 2, row * 32 + 2, 60, 28);
          }
        }
      }, { repeat: true });
      const items = [];
      const m = new THREE.Matrix4();
      const box = (w, h, d, x, y, z, ry = 0) => {
        m.compose(new THREE.Vector3(x, y, z), new THREE.Quaternion().setFromEuler(new THREE.Euler(0, ry, 0)), new THREE.Vector3(1, 1, 1));
        items.push({ geo: new THREE.BoxGeometry(w, h, d), matrix: m.clone() });
      };
      // gateway: two pillars + a semicircular arch, opening facing the pitch (along X)
      const AX = -26, AZ = 25, Ri = 1.9, Ro = 2.7, PH = 2.9, D = 1.5;
      const gy = groundY(AX, AZ);
      const shape = new THREE.Shape();
      shape.absarc(0, 0, Ro, 0, Math.PI, false); shape.lineTo(-Ri, 0);
      shape.absarc(0, 0, Ri, Math.PI, 0, true); shape.lineTo(Ro, 0);
      const arch = new THREE.ExtrudeGeometry(shape, { depth: D, bevelEnabled: false, curveSegments: 10 });
      arch.translate(0, 0, -D / 2); arch.rotateY(Math.PI / 2);
      items.push({ geo: arch, matrix: new THREE.Matrix4().makeTranslation(AX, gy + PH, AZ) });
      for (const s of [-1, 1]) box(D, PH + 0.3, Ro - Ri + 0.2, AX, gy + PH / 2, AZ + s * (Ri + (Ro - Ri) / 2));
      box(D + 0.4, 0.5, 0.9, AX, gy + PH + Ro + 0.2, AZ); // keystone block
      // broken columns and a crumbled wall
      const cols = [[-22.5, 14, 4.2, true], [-22.5, 10, 2.1, false], [-22.5, 18, 3.4, false], [-36, 30, 3.8, true], [-40, 27, 1.6, false], [-24, 36, 2.6, false],
        // the old bath: columns flanking the big pool behind the far goal
        [-13.5, 37.5, 3.4, true], [13.5, 37.5, 2.2, false], [-16, 47, 4.2, true], [16.5, 46, 3.0, true], [-10, 58, 2.0, false], [9, 59, 3.6, true]];
      for (const [x, z, h, cap] of cols) {
        const y = groundY(x, z);
        items.push({ geo: new THREE.CylinderGeometry(0.42, 0.5, h, 8), matrix: new THREE.Matrix4().makeTranslation(x, y + h / 2 - 0.1, z) });
        if (cap) box(1.3, 0.35, 1.3, x, y + h + 0.05, z);
      }
      box(7, 1.4, 0.8, -31, groundY(-31, 13) + 0.6, 13, 0.3);
      box(4, 0.9, 0.8, -35.5, groundY(-35.5, 12) + 0.35, 12, 0.5);
      box(1.2, 1.0, 1.4, -23.5, groundY(-23.5, 30) + 0.4, 30, 0.7); // fallen block
      box(1.4, 0.8, 1.1, 12, groundY(12, 36) + 0.3, 36, 0.4); // fallen block by the bath
      box(3.2, 0.5, 0.6, -12, groundY(-12, 34.5) + 0.2, 34.5, 0.1); // broken step
      const geo = mergeGeos(THREE, items, { projectUV: 0.32 });
      const mesh = new THREE.Mesh(geo, new THREE.MeshLambertMaterial({ map: tex, color: 0xf0d2a8 }));
      mesh.castShadow = true; mesh.receiveShadow = true;
      group.add(mesh);
    });

    // ---------------------------------------------------------- tents, awnings, bunting, campfire
    safe('camp', () => {
      const stripes = canvasTex(THREE, 128, 64, (c, w, h) => {
        for (let i = 0; i < 8; i++) { c.fillStyle = i % 2 ? '#c8412f' : '#f7e8c9'; c.fillRect(i * 16, 0, 16, h); }
      }, { repeat: true });
      const items = [];
      const m = new THREE.Matrix4();
      const tents = [[-33, 30, 2.6, 3.4, 0.3, [1, 1, 1]], [-40, 20, 2.3, 3.0, 1.2, [0.78, 0.9, 1.0]], [-35, 38, 2.4, 3.2, 2.2, [1, 0.88, 0.7]]];
      for (const [x, z, r, h, ry, tint] of tents) {
        const y = groundY(x, z) - 0.1;
        const color = new THREE.Color(...tint);
        const cone = new THREE.ConeGeometry(r, h, 9, 1, true);
        m.compose(new THREE.Vector3(x, y + h / 2, z), new THREE.Quaternion().setFromEuler(new THREE.Euler(0, ry, 0)), new THREE.Vector3(1, 1, 1));
        items.push({ geo: cone, matrix: m.clone(), color });
        items.push({ geo: new THREE.CylinderGeometry(0.05, 0.05, h + 0.8, 5), matrix: new THREE.Matrix4().makeTranslation(x, y + h / 2 + 0.4, z), color: new THREE.Color(0.45, 0.3, 0.2) });
        // awning in front (towards the pitch), on two poles
        const ax = x + 2.9, az = z;
        const aw = new THREE.PlaneGeometry(3, 2.2); aw.rotateX(-Math.PI / 2 + 0.25);
        items.push({ geo: aw, matrix: new THREE.Matrix4().makeTranslation(ax, y + 2.2, az), color });
        for (const s of [-1, 1]) items.push({ geo: new THREE.CylinderGeometry(0.04, 0.04, 2.2, 5), matrix: new THREE.Matrix4().makeTranslation(ax + 1.3, y + 1.1, az + s * 1.4), color: new THREE.Color(0.45, 0.3, 0.2) });
      }
      // rugs in front of the tents
      for (const [x, z, ry] of [[-30.5, 33, 0.2], [-37, 23, -0.3]]) {
        const rug = new THREE.PlaneGeometry(2.4, 1.6); rug.rotateX(-Math.PI / 2); rug.rotateY(ry);
        items.push({ geo: rug, matrix: new THREE.Matrix4().makeTranslation(x, groundY(x, z) + 0.02, z), color: new THREE.Color(0.9, 0.6, 0.35) });
      }
      const geo = mergeGeos(THREE, items);
      const mesh = new THREE.Mesh(geo, new THREE.MeshLambertMaterial({ map: stripes, vertexColors: true, side: THREE.DoubleSide }));
      mesh.castShadow = true;
      group.add(mesh);

      // bunting: strings of bright pennants (sway in the shader)
      const flags = [];
      const flagColors = [0x2dd4bf, 0xf43f5e, 0xfacc15, 0xf97316, 0x60a5fa, 0xa3e635];
      const string = (x0, z0, x1, z1, y0, n) => {
        for (let i = 0; i < n; i++) {
          const t = (i + 0.5) / n, sag = 0.45 * Math.sin(Math.PI * t);
          const x = x0 + (x1 - x0) * t, z = z0 + (z1 - z0) * t, y = y0 - sag;
          const dx = (x1 - x0) / n * 0.42, dz = (z1 - z0) / n * 0.42;
          const g = new THREE.BufferGeometry();
          g.setAttribute('position', new THREE.Float32BufferAttribute([x - dx, y, z - dz, x + dx, y, z + dz, x, y - 0.7, z], 3));
          g.setAttribute('normal', new THREE.Float32BufferAttribute([0, 0, 1, 0, 0, 1, 0, 0, 1], 3));
          g.setIndex([0, 1, 2]);
          flags.push({ geo: g, color: new THREE.Color(flagColors[i % flagColors.length]) });
        }
        for (const [x, z] of [[x0, z0], [x1, z1]]) flags.push({ geo: new THREE.CylinderGeometry(0.05, 0.06, y0 + 0.3, 5), matrix: new THREE.Matrix4().makeTranslation(x, groundY(x, z) + (y0 + 0.3) / 2 - 0.2, z), color: new THREE.Color(0.45, 0.3, 0.2) });
      };
      const b0 = groundY(-29, 34) + 3.2;
      string(-29, 33, -38, 35.5, b0, 9);
      string(20, 14, 20, 23, groundY(20, 18) + 3.0, 9);
      string(-21, -6, -21, 4, groundY(-21, -1) + 3.0, 9);
      const fmat = new THREE.MeshLambertMaterial({ vertexColors: true, side: THREE.DoubleSide });
      addSway(fmat, uTime, false, 'flag');
      group.add(new THREE.Mesh(mergeGeos(THREE, flags), fmat));

      // campfire: flame cone + additive glow sprite
      const fx = -33, fz = 24, fy = groundY(fx, fz);
      const flame = new THREE.Mesh(new THREE.ConeGeometry(0.35, 1.0, 6), new THREE.MeshBasicMaterial({ color: 0xffa726 }));
      flame.position.set(fx, fy + 0.45, fz);
      group.add(flame);
      const glowTex = canvasTex(THREE, 64, 64, (c, w, h) => {
        const g = c.createRadialGradient(32, 32, 0, 32, 32, 32);
        g.addColorStop(0, 'rgba(255,190,90,0.9)'); g.addColorStop(0.4, 'rgba(255,120,40,0.35)'); g.addColorStop(1, 'rgba(255,80,20,0)');
        c.fillStyle = g; c.fillRect(0, 0, w, h);
      });
      const glow = new THREE.Sprite(new THREE.SpriteMaterial({ map: glowTex, blending: THREE.AdditiveBlending, depthWrite: false, transparent: true }));
      glow.position.set(fx, fy + 1.0, fz); glow.scale.set(4, 4, 1);
      group.add(glow);
      updaters.push((dt, time) => {
        const f = 0.75 + Math.sin(time * 9) * 0.12 + Math.sin(time * 23.7) * 0.08;
        glow.material.opacity = f; flame.scale.set(1, 0.8 + f * 0.35, 1);
      });
    });

    // ---------------------------------------------------------- camel caravan
    safe('camels', () => {
      const body = [[0, 0.9], [0.2, 1.15], [0.5, 1.3], [0.8, 1.45], [0.95, 1.52], [1.0, 1.9], [1.1, 2.12], [1.22, 1.92], [1.28, 1.52], [1.45, 1.42], [1.7, 1.2], [1.9, 1.05],
        [2.05, 1.15], [2.2, 1.45], [2.3, 1.75], [2.4, 1.92], [2.6, 1.97], [2.78, 1.87], [2.82, 1.7], [2.62, 1.66], [2.47, 1.55], [2.37, 1.3], [2.27, 1.0], [2.17, 0.8],
        [2.17, 0.7], [2.22, 0], [2.06, 0], [1.96, 0.62], [1.62, 0.66], [1.56, 0], [1.4, 0], [1.36, 0.66],
        [0.7, 0.66], [0.66, 0], [0.5, 0], [0.46, 0.62], [0.22, 0.6], [0.16, 0], [0, 0], [-0.06, 0.56], [-0.22, 0.72], [-0.28, 0.88]];
      const shapes = [];
      const baseX = -49, baseZ = 10;
      const sh = new THREE.Shape();
      body.forEach(([x, y], i) => (i ? sh.lineTo(x, y) : sh.moveTo(x, y)));
      sh.closePath();
      const unit = new THREE.ShapeGeometry(sh);
      const items = [];
      for (let i = 0; i < 6; i++) {
        const z = baseZ + i * 4.6 + R(-0.4, 0.4), x = baseX + R(-1.5, 1.5), s = R(1.35, 1.6);
        const m = new THREE.Matrix4().compose(new THREE.Vector3(x, groundY(x, z) - 0.15, z), new THREE.Quaternion().setFromEuler(new THREE.Euler(0, -Math.PI / 2, 0)), new THREE.Vector3(s, s, s));
        items.push({ geo: unit, matrix: m });
      }
      const mesh = new THREE.Mesh(mergeGeos(THREE, items), new THREE.MeshBasicMaterial({ color: 0x3a2418, side: THREE.DoubleSide }));
      group.add(mesh);
    });

    // ---------------------------------------------------------- sun
    safe('sun', () => {
      const tex = canvasTex(THREE, 256, 256, (c, w, h) => {
        const g = c.createRadialGradient(128, 128, 0, 128, 128, 128);
        g.addColorStop(0, 'rgba(255,250,225,1)'); g.addColorStop(0.3, 'rgba(255,238,180,1)'); g.addColorStop(0.36, 'rgba(255,205,110,0.9)');
        g.addColorStop(0.55, 'rgba(255,150,70,0.35)'); g.addColorStop(1, 'rgba(255,110,60,0)');
        c.fillStyle = g; c.fillRect(0, 0, w, h);
      });
      const sun = new THREE.Sprite(new THREE.SpriteMaterial({ map: tex, transparent: true, depthWrite: false, fog: false }));
      sun.position.set(-300, 26, 105); sun.scale.set(130, 130, 1);
      group.add(sun);
      const halo = new THREE.Sprite(new THREE.SpriteMaterial({ map: tex, transparent: true, depthWrite: false, fog: false, opacity: 0.35, blending: THREE.AdditiveBlending }));
      halo.position.set(-300, 14, 105); halo.scale.set(320, 200, 1);
      group.add(halo);
    });

    // ---------------------------------------------------------- dust
    safe('dust', () => {
      const n = 520;
      const pos = new Float32Array(n * 3), vel = [];
      for (let i = 0; i < n; i++) {
        let x, z;
        if (i % 3 === 2) { x = R(-30, 30); z = R(34, 75); } // behind the far goal
        else { x = (i % 2 ? 1 : -1) * R(17, 55); z = R(-45, 75); }
        pos.set([x, groundY(x, z) + R(0.3, 5), z], i * 3);
        vel.push(R(0.6, 1.8), R(0, 6.28));
      }
      const g = new THREE.BufferGeometry();
      g.setAttribute('position', new THREE.BufferAttribute(pos, 3));
      const tex = canvasTex(THREE, 32, 32, (c, w, h) => {
        const gr = c.createRadialGradient(16, 16, 0, 16, 16, 16);
        gr.addColorStop(0, 'rgba(255,225,170,1)'); gr.addColorStop(0.5, 'rgba(255,210,150,0.45)'); gr.addColorStop(1, 'rgba(255,200,140,0)');
        c.fillStyle = gr; c.fillRect(0, 0, w, h);
      });
      const pts = new THREE.Points(g, new THREE.PointsMaterial({ map: tex, size: 1.0, transparent: true, opacity: 0.5, depthWrite: false, sizeAttenuation: true, color: 0xf7c98c }));
      pts.frustumCulled = false;
      group.add(pts);
      updaters.push((dt, time) => {
        const step = Math.min(dt, 0.1);
        for (let i = 0; i < n; i++) {
          let x = pos[i * 3], y = pos[i * 3 + 1], z = pos[i * 3 + 2];
          z += vel[i * 2] * step;
          x += Math.sin(time * 0.7 + vel[i * 2 + 1]) * 0.6 * step;
          y += Math.cos(time * 0.9 + vel[i * 2 + 1] * 1.7) * 0.25 * step;
          if (z > 75) z = i % 3 === 2 ? 34 : -45;
          if (Math.abs(x) < 17 && z < 33) x = Math.sign(x || 1) * 17;
          pos[i * 3] = x; pos[i * 3 + 1] = y; pos[i * 3 + 2] = z;
        }
        g.attributes.position.needsUpdate = true;
      });
    });

    return {
      update(dt, time) {
        uTime.value = time;
        for (const u of updaters) { try { u(dt, time); } catch (e) { /* keep the frame going */ } }
      },
    };
  },
};
