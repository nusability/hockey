// Ocean World — field hockey on a coral-reef plateau beneath the waves.
//
// Everything around the pitch is built here from primitives and canvas
// textures: a rolling sandy seabed with animated caustics, instanced coral
// clusters (staghorn, elkhorn, brain, tube, pillar, fan), swaying kelp and sea
// grass, anemones, starfish, schools of fish circling the arena, two manta rays
// gliding round the reef, jellyfish, bubble streams, light shafts, a sunken
// temple ruin, a shipwreck, a stone head and a treasure chest.
// Adds about 25 draw calls and ~53k triangles; update() only moves the
// fish/manta/jelly instance matrices, a bubble buffer and one time uniform.

const T = { value: 0 }; // shared time uniform for all animated shaders

// ---------------------------------------------------------------- helpers
const smooth = (a, b, x) => { const t = Math.min(1, Math.max(0, (x - a) / (b - a))); return t * t * (3 - 2 * t); };

/** Merge parts [{ geo, color, matrix? }] into one non-indexed geometry with vertex colours. */
function mergeParts(THREE, parts) {
  const pos = [], nor = [], uv = [], col = [];
  const c = new THREE.Color();
  for (const p of parts) {
    let g = p.geo.index ? p.geo.toNonIndexed() : p.geo.clone();
    if (p.matrix) g.applyMatrix4(p.matrix);
    const P = g.attributes.position.array;
    const N = g.attributes.normal ? g.attributes.normal.array : null;
    const U = g.attributes.uv ? g.attributes.uv.array : null;
    c.set(p.color);
    const n = P.length / 3;
    for (let i = 0; i < P.length; i++) pos.push(P[i]);
    for (let i = 0; i < n; i++) {
      if (N) nor.push(N[i * 3], N[i * 3 + 1], N[i * 3 + 2]); else nor.push(0, 1, 0);
      uv.push(U ? U[i * 2] : 0, U ? U[i * 2 + 1] : 0);
      col.push(c.r, c.g, c.b);
    }
    g.dispose();
  }
  const geo = new THREE.BufferGeometry();
  geo.setAttribute('position', new THREE.Float32BufferAttribute(pos, 3));
  geo.setAttribute('normal', new THREE.Float32BufferAttribute(nor, 3));
  geo.setAttribute('uv', new THREE.Float32BufferAttribute(uv, 2));
  geo.setAttribute('color', new THREE.Float32BufferAttribute(col, 3));
  return geo;
}

function mat4(THREE, x, y, z, rx = 0, ry = 0, rz = 0, sx = 1, sy = sx, sz = sx) {
  return new THREE.Matrix4().compose(
    new THREE.Vector3(x, y, z),
    new THREE.Quaternion().setFromEuler(new THREE.Euler(rx, ry, rz)),
    new THREE.Vector3(sx, sy, sz),
  );
}

/** Inject a time uniform + vertex/fragment code into a built-in material. */
function animate(mat, key, { vertex = '', vertexHead = '', fragment = '', fragmentHead = '' } = {}) {
  mat.onBeforeCompile = (shader) => {
    shader.uniforms.uTime = T;
    shader.vertexShader = 'uniform float uTime;\n' + vertexHead + shader.vertexShader
      .replace('#include <begin_vertex>', '#include <begin_vertex>\n' + vertex);
    shader.fragmentShader = 'uniform float uTime;\n' + fragmentHead + shader.fragmentShader
      .replace('#include <map_fragment>', '#include <map_fragment>\n' + fragment);
  };
  mat.customProgramCacheKey = () => 'ocean_' + key;
  return mat;
}

const SWAY = (amp) => `
  float ph = instanceMatrix[3][0] * 0.7 + instanceMatrix[3][2] * 0.9;
  float hh = clamp(position.y, 0.0, 1.0);
  float sw = sin(uTime * 1.1 + ph) * 0.6 + sin(uTime * 2.3 + ph * 1.7) * 0.2;
  transformed.x += sw * hh * hh * ${amp.toFixed(2)};
  transformed.z += cos(uTime * 0.8 + ph * 1.3) * hh * hh * ${(amp * 0.5).toFixed(2)};
`;

// ---------------------------------------------------------------- textures
function canvas(w, h, draw) {
  const c = document.createElement('canvas');
  c.width = w; c.height = h;
  draw(c.getContext('2d'), w, h);
  return c;
}

function texSand(THREE) {
  const c = canvas(256, 256, (g, w, h) => {
    g.fillStyle = '#d6c391'; g.fillRect(0, 0, w, h);
    for (let i = 0; i < 2600; i++) {
      const v = Math.random();
      g.fillStyle = v < 0.5 ? 'rgba(120,95,55,0.18)' : v < 0.85 ? 'rgba(255,245,215,0.22)' : 'rgba(90,110,120,0.16)';
      g.fillRect(Math.random() * w, Math.random() * h, 1.5 + Math.random() * 2, 1.5 + Math.random() * 2);
    }
    g.strokeStyle = 'rgba(160,130,80,0.16)'; g.lineWidth = 3;
    for (let i = 0; i < 14; i++) {
      g.beginPath();
      const y = Math.random() * h;
      g.moveTo(0, y);
      for (let x = 0; x <= w; x += 16) g.lineTo(x, y + Math.sin(x * 0.06 + i) * 6);
      g.stroke();
    }
  });
  const t = new THREE.CanvasTexture(c);
  t.wrapS = t.wrapT = THREE.RepeatWrapping;
  t.repeat.set(48, 54);
  t.colorSpace = THREE.SRGBColorSpace;
  t.anisotropy = 4;
  return t;
}

function texKelp(THREE) {
  const c = canvas(64, 256, (g, w, h) => {
    g.clearRect(0, 0, w, h);
    g.fillStyle = '#ffffff';
    g.beginPath();
    g.moveTo(w / 2 - 6, h);
    for (let i = 0; i <= 12; i++) {
      const t = i / 12, y = h - t * h;
      const half = (0.5 + 0.5 * Math.sin(t * Math.PI)) * 26 * (1 - t * 0.5) + 4 + Math.sin(t * 19) * 4;
      g.lineTo(w / 2 - half, y);
    }
    for (let i = 12; i >= 0; i--) {
      const t = i / 12, y = h - t * h;
      const half = (0.5 + 0.5 * Math.sin(t * Math.PI)) * 26 * (1 - t * 0.5) + 4 + Math.sin(t * 19 + 2) * 4;
      g.lineTo(w / 2 + half, y);
    }
    g.closePath(); g.fill();
    g.strokeStyle = 'rgba(0,0,0,0.35)'; g.lineWidth = 4;
    g.beginPath(); g.moveTo(w / 2, h); g.lineTo(w / 2, 8); g.stroke();
  });
  const t = new THREE.CanvasTexture(c);
  t.colorSpace = THREE.SRGBColorSpace;
  return t;
}

function texGrass(THREE) {
  const c = canvas(64, 128, (g, w, h) => {
    g.clearRect(0, 0, w, h);
    g.fillStyle = '#ffffff';
    for (const [x0, x1, top] of [[8, 22, 30], [22, 40, 6], [40, 56, 24]]) {
      g.beginPath(); g.moveTo(x0, h); g.quadraticCurveTo((x0 + x1) / 2 + 6, h * 0.5, (x0 + x1) / 2, top); g.lineTo(x1, h); g.closePath(); g.fill();
    }
  });
  const t = new THREE.CanvasTexture(c);
  t.colorSpace = THREE.SRGBColorSpace;
  return t;
}

function texFan(THREE) {
  const c = canvas(256, 256, (g, w, h) => {
    g.clearRect(0, 0, w, h);
    g.strokeStyle = '#ffffff'; g.lineCap = 'round';
    const cx = w / 2, cy = h - 6;
    g.lineWidth = 14; g.beginPath(); g.moveTo(cx, h); g.lineTo(cx, cy - 40); g.stroke();
    for (let a = -75; a <= 75; a += 9) {
      const r = a % 18 === 0 ? 118 : 100;
      g.lineWidth = 7 - Math.abs(a) * 0.02;
      g.beginPath(); g.moveTo(cx, cy - 20);
      const ang = (a * Math.PI) / 180;
      g.quadraticCurveTo(cx + Math.sin(ang) * r * 0.5, cy - 20 - Math.cos(ang) * r * 0.55 - 20, cx + Math.sin(ang) * r, cy - 20 - Math.cos(ang) * r);
      g.stroke();
    }
    g.lineWidth = 5;
    for (let r = 34; r <= 118; r += 18) {
      g.beginPath();
      for (let a = -75; a <= 75; a += 5) {
        const ang = (a * Math.PI) / 180, rr = r + Math.sin(a * 0.4 + r) * 4;
        const x = cx + Math.sin(ang) * rr, y = cy - 20 - Math.cos(ang) * rr;
        if (a === -75) g.moveTo(x, y); else g.lineTo(x, y);
      }
      g.stroke();
    }
  });
  const t = new THREE.CanvasTexture(c);
  t.colorSpace = THREE.SRGBColorSpace;
  return t;
}

function texAnemone(THREE) {
  const c = canvas(256, 256, (g, w, h) => {
    g.clearRect(0, 0, w, h);
    g.strokeStyle = '#ffffff'; g.fillStyle = '#ffffff'; g.lineCap = 'round';
    const cx = w / 2;
    g.beginPath(); g.ellipse(cx, h - 14, 46, 16, 0, 0, Math.PI * 2); g.fill();
    for (let i = 0; i < 22; i++) {
      const t = i / 21, x0 = cx - 40 + t * 80;
      const x1 = cx + (t - 0.5) * 210 + (Math.random() - 0.5) * 20;
      const y1 = 40 + Math.random() * 60 + Math.abs(t - 0.5) * 120;
      g.lineWidth = 9;
      g.beginPath(); g.moveTo(x0, h - 18); g.quadraticCurveTo(x0 + (x1 - x0) * 0.3, h - 90, x1, y1); g.stroke();
      g.beginPath(); g.arc(x1, y1, 9, 0, Math.PI * 2); g.fill();
    }
  });
  const t = new THREE.CanvasTexture(c);
  t.colorSpace = THREE.SRGBColorSpace;
  return t;
}

function texBrain(THREE) {
  const c = canvas(256, 128, (g, w, h) => {
    g.fillStyle = '#ffffff'; g.fillRect(0, 0, w, h);
    g.strokeStyle = 'rgba(70,40,60,0.55)'; g.lineWidth = 5; g.lineCap = 'round';
    for (let i = 0; i < 60; i++) {
      const x = Math.random() * w, y = Math.random() * h;
      g.beginPath(); g.moveTo(x, y);
      let px = x, py = y, a = Math.random() * Math.PI * 2;
      for (let s = 0; s < 6; s++) { a += (Math.random() - 0.5) * 1.6; px += Math.cos(a) * 12; py += Math.sin(a) * 12; g.lineTo(px, py); }
      g.stroke();
    }
  });
  const t = new THREE.CanvasTexture(c);
  t.wrapS = t.wrapT = THREE.RepeatWrapping;
  t.colorSpace = THREE.SRGBColorSpace;
  return t;
}

function texBubble(THREE) {
  const c = canvas(64, 64, (g, w, h) => {
    g.clearRect(0, 0, w, h);
    const r = g.createRadialGradient(28, 26, 2, 32, 32, 30);
    r.addColorStop(0, 'rgba(255,255,255,0.9)');
    r.addColorStop(0.35, 'rgba(210,245,255,0.25)');
    r.addColorStop(0.8, 'rgba(200,240,255,0.35)');
    r.addColorStop(0.92, 'rgba(255,255,255,0.9)');
    r.addColorStop(1, 'rgba(255,255,255,0)');
    g.fillStyle = r; g.beginPath(); g.arc(32, 32, 30, 0, Math.PI * 2); g.fill();
  });
  const t = new THREE.CanvasTexture(c);
  t.colorSpace = THREE.SRGBColorSpace;
  return t;
}

// ---------------------------------------------------------------- geometry builders
/** Branching coral: recursive tapered cylinders merged into one geometry. */
function coralBranches(THREE, rand, { radial = 4, depth = 2, kids = 3, spread = 0.9, flat = 1, trunk = 1 }) {
  const parts = [];
  const up = new THREE.Vector3(0, 1, 0);
  const grow = (from, dir, len, r, lvl) => {
    const q = new THREE.Quaternion().setFromUnitVectors(up, dir.clone().normalize());
    const mid = from.clone().addScaledVector(dir, len / 2);
    const m = new THREE.Matrix4().compose(mid, q, new THREE.Vector3(1, 1, 1));
    const tip = lvl >= depth;
    parts.push({ geo: new THREE.CylinderGeometry(tip ? r * 0.15 : r * 0.55, r, len, radial, 1, tip), color: 0xffffff, matrix: m });
    if (tip) return;
    const end = from.clone().addScaledVector(dir, len);
    const n = lvl === 0 ? kids : 2;
    for (let i = 0; i < n; i++) {
      const a = (i / n) * Math.PI * 2 + rand(-0.6, 0.6);
      const d = new THREE.Vector3(Math.cos(a) * spread * flat, 1.1, Math.sin(a) * spread).normalize();
      grow(end, d, len * rand(0.55, 0.75), r * 0.7, lvl + 1);
    }
  };
  grow(new THREE.Vector3(0, 0, 0), up.clone(), trunk, 0.13, 0);
  return mergeParts(THREE, parts);
}

function fishGeometry(THREE) {
  const body = new THREE.SphereGeometry(0.5, 6, 4);
  body.scale(1, 0.55, 0.28);
  const tail = new THREE.BufferGeometry();
  tail.setAttribute('position', new THREE.Float32BufferAttribute([
    -0.42, 0, 0, -0.85, 0.32, 0, -0.85, -0.32, 0,
    -0.42, 0, 0, -0.85, -0.32, 0, -0.85, 0.32, 0,
    0.05, 0.25, 0, -0.3, 0.25, 0, -0.15, 0.5, 0,
    0.05, 0.25, 0, -0.15, 0.5, 0, -0.3, 0.25, 0,
  ], 3));
  tail.setAttribute('normal', new THREE.Float32BufferAttribute(new Array(12).fill(0).flatMap(() => [0, 0, 1]), 3));
  return mergeParts(THREE, [{ geo: body, color: 0xffffff }, { geo: tail, color: 0xffffff }]);
}

function mantaGeometry(THREE) {
  const nx = 20, nz = 6;
  const pos = [], idx = [], col = [];
  const le = (u) => -0.35 + 0.5 * Math.pow(Math.abs(u), 1.4);
  const te = (u) => 0.6 - 0.35 * Math.pow(Math.abs(u), 0.6);
  for (let i = 0; i <= nx; i++) {
    const u = (i / nx) * 2 - 1;
    for (let j = 0; j <= nz; j++) {
      const v = j / nz;
      pos.push(u, 0, le(u) + (te(u) - le(u)) * v);
      const shade = 0.55 + 0.45 * (1 - Math.abs(u));
      col.push(0.3 * shade, 0.42 * shade, 0.6 * shade);
    }
  }
  for (let i = 0; i < nx; i++) for (let j = 0; j < nz; j++) {
    const a = i * (nz + 1) + j, b = a + nz + 1;
    idx.push(a, b, a + 1, b, b + 1, a + 1);
  }
  const g = new THREE.BufferGeometry();
  g.setAttribute('position', new THREE.Float32BufferAttribute(pos, 3));
  g.setAttribute('color', new THREE.Float32BufferAttribute(col, 3));
  g.setIndex(idx);
  g.computeVertexNormals();
  // tail and cephalic lobes
  const extra = new THREE.BufferGeometry();
  extra.setAttribute('position', new THREE.Float32BufferAttribute([
    -0.03, 0, 0.55, 0.03, 0, 0.55, 0, 0, 1.7,
    -0.16, 0, -0.3, -0.08, 0, -0.3, -0.12, 0, -0.55,
    0.16, 0, -0.3, 0.08, 0, -0.3, 0.12, 0, -0.55,
  ], 3));
  extra.setAttribute('normal', new THREE.Float32BufferAttribute(new Array(9).fill(0).flatMap(() => [0, 1, 0]), 3));
  const merged = mergeParts(THREE, [{ geo: g, color: 0xffffff }, { geo: extra, color: 0x3b4d70 }]);
  const c = merged.attributes.color.array, src = g.toNonIndexed().attributes.color.array;
  for (let i = 0; i < src.length; i++) c[i] = src[i]; // keep the body's own shading
  return merged;
}

function starGeometry(THREE) {
  const s = new THREE.Shape();
  for (let i = 0; i < 10; i++) {
    const r = i % 2 ? 0.42 : 1, a = (i / 10) * Math.PI * 2;
    if (i) s.lineTo(Math.cos(a) * r, Math.sin(a) * r); else s.moveTo(Math.cos(a) * r, Math.sin(a) * r);
  }
  s.closePath();
  const g = new THREE.ExtrudeGeometry(s, { depth: 0.16, bevelEnabled: true, bevelThickness: 0.12, bevelSize: 0.1, bevelSegments: 1, curveSegments: 2 });
  g.rotateX(-Math.PI / 2);
  return g;
}

// ---------------------------------------------------------------- the world
export default {
  id: 'ocean',
  sport: 'field',
  name: { en: 'Ocean World', de: 'Ozeanwelt' },
  tagline: { en: 'Seagrass pitch on a coral reef, deep beneath the waves.', de: 'Ein Seegras-Feld auf dem Korallenriff, tief unter den Wellen.' },
  sky: 'linear-gradient(180deg, #b8f6ff 0%, #4cc8e6 6%, #1a8aab 15%, #0f6f8e 30%, #0b4f6e 60%, #052a44 100%)',
  light: {
    hemiSky: 0xb8f1fa, hemiGround: 0x2a7a8a, hemiIntensity: 1.3,
    sun: 0xf2feff, sunIntensity: 1.8, sunPos: [14, 60, -10],
    fog: { color: 0x0f6f8e, near: 48, far: 165 },
  },
  surface: {
    base: '#2ea393', stripe: '#289685', lines: '#f0fdfa',
    decorate(g, W, H, h) {
      // faint caustic web: overlapping soft rings
      g.save();
      g.lineCap = 'round';
      for (let i = 0; i < 150; i++) {
        const x = Math.random() * W, y = Math.random() * H, r = 45 + Math.random() * 70;
        g.beginPath();
        for (let a = 0; a <= 16; a++) {
          const t = (a / 16) * Math.PI * 2, rr = r * (0.8 + 0.2 * Math.sin(t * 3 + i));
          const px = x + Math.cos(t) * rr, py = y + Math.sin(t) * rr * 0.8;
          if (a) g.lineTo(px, py); else g.moveTo(px, py);
        }
        g.strokeStyle = 'rgba(210,255,245,0.045)'; g.lineWidth = 12; g.stroke();
        g.strokeStyle = 'rgba(240,255,250,0.06)'; g.lineWidth = 4; g.stroke();
      }
      // sand drift + shells near the edges
      for (let i = 0; i < 30; i++) {
        const side = Math.random() < 0.5 ? -1 : 1;
        const along = Math.random() < 0.5;
        const x = along ? h.X(side * (14.4 - Math.random() * 1.1)) : Math.random() * W;
        const y = along ? Math.random() * H : h.Z(side * (29.4 - Math.random() * 1.1));
        const r = 8 + Math.random() * 8, rot = Math.random() * Math.PI * 2;
        g.save(); g.translate(x, y); g.rotate(rot);
        g.fillStyle = Math.random() < 0.5 ? '#fde7d6' : '#fbd3e0';
        g.beginPath(); g.moveTo(0, r * 0.6);
        for (let k = -4; k <= 4; k++) { const a = -Math.PI / 2 + (k / 4) * 1.15; g.lineTo(Math.cos(a) * r, r * 0.6 + Math.sin(a) * r); if (k < 4) g.lineTo(Math.cos(a + 0.14) * r * 0.85, r * 0.6 + Math.sin(a + 0.14) * r * 0.85); }
        g.closePath(); g.fill();
        g.strokeStyle = 'rgba(120,60,60,0.25)'; g.lineWidth = 1.5;
        for (let k = -3; k <= 3; k++) { g.beginPath(); g.moveTo(0, r * 0.6); const a = -Math.PI / 2 + (k / 4) * 1.15; g.lineTo(Math.cos(a) * r, r * 0.6 + Math.sin(a) * r); g.stroke(); }
        g.restore();
      }
      g.restore();
    },
  },
  border: { color: 0xffa4c1, top: 0xfff8fc, height: 1.1, glass: false, base: 0xd2b985 },
  ball: { color: 0xfff7ed },
  goal: { post: 0xffb020, net: 0xe0fbff },

  buildScenery(group, ctx) {
    const { THREE, HW, HL, rand, pick } = ctx;
    const slabHW = HW + 2.2, slabHL = HL + 2.2;
    const sdSlab = (x, z) => Math.max(Math.abs(x) - slabHW, Math.abs(z) - slabHL);
    const seabedY = (x, z) => {
      const d = Math.max(0, sdSlab(x, z));
      const t = smooth(1.5, 12, d);
      const dune = Math.sin(x * 0.21 + 1.3) * Math.sin(z * 0.17 - 0.4) * 0.9 + Math.sin(x * 0.07 - z * 0.09) * 0.6;
      return -0.7 + t * (dune + 0.4) + smooth(34, 95, d) * 9;
    };
    /** Random spots outside the platform; tall = keep clear of the zone behind the user's goal. */
    const scatter = (n, { min = 1.5, max = 45, falloff = 16, tall = false, bias = null } = {}) => {
      const out = [];
      let guard = 0;
      while (out.length < n && guard++ < n * 60) {
        const x = rand(-slabHW - max, slabHW + max), z = rand(-slabHL - max, slabHL + max);
        const d = sdSlab(x, z);
        if (d < min || d > max) continue;
        if (tall && z < -HL - 1 && Math.abs(x) < 19) continue;
        let p = Math.exp(-(d - min) / falloff);
        if (z < -HL) p *= 0.35;           // behind the camera: sparse
        if (bias) p *= bias(x, z);
        if (Math.random() < p) out.push({ x, z, d });
      }
      return out;
    };
    const dummy = new THREE.Object3D();
    const color = new THREE.Color();
    const instanced = (geo, mat, spots, fn, { shadow = false } = {}) => {
      const m = new THREE.InstancedMesh(geo, mat, spots.length);
      spots.forEach((s, i) => {
        dummy.position.set(0, 0, 0); dummy.rotation.set(0, 0, 0); dummy.scale.set(1, 1, 1);
        const c = fn(s, i, dummy);
        dummy.updateMatrix();
        m.setMatrixAt(i, dummy.matrix);
        m.setColorAt(i, color.set(c ?? 0xffffff));
      });
      m.instanceMatrix.needsUpdate = true;
      if (m.instanceColor) m.instanceColor.needsUpdate = true;
      m.frustumCulled = false;
      m.castShadow = shadow;
      group.add(m);
      return m;
    };
    const jitter = (hex, amt) => { color.set(hex); color.offsetHSL(rand(-amt, amt) * 0.15, rand(-amt, amt), rand(-amt, amt) * 0.6); return color.getHex(); };

    // ------------------------------------------------ seabed
    {
      const g = new THREE.PlaneGeometry(320, 360, 44, 50);
      g.rotateX(-Math.PI / 2);
      const P = g.attributes.position;
      for (let i = 0; i < P.count; i++) P.setY(i, seabedY(P.getX(i), P.getZ(i)));
      g.computeVertexNormals();
      const mat = new THREE.MeshLambertMaterial({ map: texSand(THREE), color: 0xf1e2b8 });
      animate(mat, 'seabed', {
        vertexHead: 'varying vec2 vSbPos;\n',
        vertex: 'vSbPos = (modelMatrix * vec4(transformed, 1.0)).xz;\n',
        fragmentHead: 'varying vec2 vSbPos;\n',
        fragment: `
          vec2 p = vSbPos * 0.42;
          float t = uTime * 0.55;
          float ca = sin(p.x * 1.3 + t + sin(p.y * 1.7 - t * 0.7) * 1.4);
          float cb = sin(p.y * 1.5 - t * 0.9 + sin(p.x * 1.1 + t * 0.6) * 1.4);
          float cc = pow(clamp(1.0 - abs(ca + cb) * 0.7, 0.0, 1.0), 4.0);
          diffuseColor.rgb += vec3(0.45, 0.8, 0.85) * cc * 0.5;
        `,
      });
      const mesh = new THREE.Mesh(g, mat);
      mesh.receiveShadow = true;
      group.add(mesh);
    }

    // ------------------------------------------------ rocks / boulders
    const rockSpots = scatter(48, { min: 1.2, max: 60, falloff: 22 });
    instanced(new THREE.DodecahedronGeometry(1, 0), new THREE.MeshLambertMaterial({ color: 0xffffff }), rockSpots, (s, i, o) => {
      const sc = rand(0.9, 3.2);
      o.position.set(s.x, seabedY(s.x, s.z) - sc * 0.35, s.z);
      o.rotation.set(rand(0, 3), rand(0, 3), rand(0, 3));
      o.scale.set(sc * rand(0.8, 1.4), sc * rand(0.5, 0.9), sc * rand(0.8, 1.4));
      return jitter(pick([0x7484b3, 0x8286b5, 0x6a8aa6, 0x8c7cac]), 0.08);
    }, { shadow: true });

    // ------------------------------------------------ corals
    const coralMat = (map) => new THREE.MeshLambertMaterial({ color: 0xffffff, map: map || null });
    const stag = coralBranches(THREE, rand, { radial: 4, depth: 2, kids: 4, spread: 0.8, trunk: 1 });
    instanced(stag, coralMat(), scatter(50, { min: 1.4, max: 30, falloff: 9, tall: true }), (s, i, o) => {
      const sc = rand(1.5, 3.2);
      o.position.set(s.x, seabedY(s.x, s.z) - 0.1, s.z);
      o.rotation.y = rand(0, 6.3);
      o.scale.set(sc * rand(0.8, 1.2), sc, sc * rand(0.8, 1.2));
      return jitter(pick([0xff7a59, 0xff9d3b, 0xf05a8e, 0xffc94d, 0xe8583c]), 0.1);
    });
    const elk = coralBranches(THREE, rand, { radial: 4, depth: 2, kids: 3, spread: 1.4, flat: 1.6, trunk: 0.6 });
    instanced(elk, coralMat(), scatter(30, { min: 1.4, max: 28, falloff: 10, tall: true }), (s, i, o) => {
      const sc = rand(1.8, 3.4);
      o.position.set(s.x, seabedY(s.x, s.z) - 0.1, s.z);
      o.rotation.y = rand(0, 6.3);
      o.scale.set(sc * 1.3, sc * 0.8, sc * 1.3);
      return jitter(pick([0xb56cff, 0x8b5cf6, 0xd85cc4, 0xff80ab]), 0.1);
    });
    const brainGeo = new THREE.SphereGeometry(1, 10, 6);
    brainGeo.scale(1, 0.66, 1);
    instanced(brainGeo, coralMat(texBrain(THREE)), scatter(36, { min: 1.2, max: 30, falloff: 10 }), (s, i, o) => {
      const sc = rand(0.8, 2.3);
      o.position.set(s.x, seabedY(s.x, s.z) + sc * 0.25, s.z);
      o.rotation.y = rand(0, 6.3);
      o.scale.set(sc, sc, sc * rand(0.8, 1.2));
      return jitter(pick([0xd6a35c, 0xb3d95c, 0xc98bd9, 0xf0b070, 0x7fd1c8]), 0.1);
    });
    // tube coral clusters
    {
      const parts = [];
      for (let k = 0; k < 5; k++) {
        const a = (k / 5) * Math.PI * 2, r = k ? 0.32 : 0, h = rand(0.6, 1.3);
        parts.push({ geo: new THREE.CylinderGeometry(0.16, 0.22, h, 6, 1, false), color: 0xffffff, matrix: mat4(THREE, Math.cos(a) * r, h / 2, Math.sin(a) * r, rand(-0.25, 0.25), 0, rand(-0.25, 0.25)) });
      }
      instanced(mergeParts(THREE, parts), coralMat(), scatter(40, { min: 1.2, max: 30, falloff: 10 }), (s, i, o) => {
        const sc = rand(0.9, 1.9);
        o.position.set(s.x, seabedY(s.x, s.z) - 0.05, s.z);
        o.rotation.y = rand(0, 6.3);
        o.scale.setScalar(sc);
        return jitter(pick([0xff5e7a, 0xffa552, 0xffe066, 0xff6fb5]), 0.08);
      });
    }
    // tall pillar corals / sponges (vertical accents for the goal camera)
    const pillarGeo = mergeParts(THREE, [
      { geo: new THREE.CylinderGeometry(0.24, 0.42, 1, 7, 1, true), color: 0xffffff, matrix: mat4(THREE, 0, 0.5, 0) },
      { geo: new THREE.SphereGeometry(0.24, 7, 4), color: 0xffffff, matrix: mat4(THREE, 0, 1, 0, 0, 0, 0, 1, 0.45, 1) },
    ]);
    instanced(pillarGeo, coralMat(),
      scatter(32, { min: 1.6, max: 36, falloff: 13, tall: true }), (s, i, o) => {
        o.position.set(s.x, seabedY(s.x, s.z) - 0.1, s.z);
        o.rotation.set(rand(-0.15, 0.15), rand(0, 6.3), rand(-0.15, 0.15));
        o.scale.set(rand(0.8, 1.3), rand(2.4, 4.8), rand(0.8, 1.3));
        return jitter(pick([0x9b4dff, 0xff4d7e, 0xff8c42, 0x5b6cff]), 0.08);
      });
    // fan corals (alpha planes)
    {
      const fanGeo = new THREE.PlaneGeometry(1, 1).translate(0, 0.5, 0);
      const mat = new THREE.MeshLambertMaterial({ color: 0xffffff, map: texFan(THREE), alphaTest: 0.5, side: THREE.DoubleSide });
      animate(mat, 'fan', { vertex: SWAY(0.06) });
      instanced(fanGeo, mat, scatter(66, { min: 1.2, max: 30, falloff: 10, tall: true }), (s, i, o) => {
        const sc = rand(1.8, 3.6);
        o.position.set(s.x, seabedY(s.x, s.z) - 0.1, s.z);
        o.rotation.y = rand(0, 6.3);
        o.scale.set(sc, sc, sc);
        return jitter(pick([0xff4f6d, 0xff8a3d, 0xc45cff, 0xffd166, 0xff5cab]), 0.1);
      });
    }
    // anemones (three crossed alpha planes, swaying)
    {
      const p1 = new THREE.PlaneGeometry(1, 1).translate(0, 0.5, 0);
      const parts = [0, 1, 2].map((k) => ({ geo: p1, color: 0xffffff, matrix: mat4(THREE, 0, 0, 0, 0, (k * Math.PI) / 3, 0) }));
      const mat = new THREE.MeshLambertMaterial({ color: 0xffffff, map: texAnemone(THREE), alphaTest: 0.5, side: THREE.DoubleSide, vertexColors: false });
      animate(mat, 'anemone', { vertex: SWAY(0.12) });
      instanced(mergeParts(THREE, parts), mat, scatter(52, { min: 1.2, max: 28, falloff: 9 }), (s, i, o) => {
        const sc = rand(0.9, 1.9);
        o.position.set(s.x, seabedY(s.x, s.z) - 0.05, s.z);
        o.rotation.y = rand(0, 6.3);
        o.scale.set(sc, sc * rand(0.8, 1.3), sc);
        return jitter(pick([0xff7ab8, 0xb388ff, 0x7dffc4, 0xffb27a, 0x8ad4ff]), 0.08);
      });
    }
    // starfish
    instanced(starGeometry(THREE), new THREE.MeshLambertMaterial({ color: 0xffffff }), scatter(30, { min: 1.0, max: 28, falloff: 9 }), (s, i, o) => {
      const sc = rand(0.35, 0.7);
      o.position.set(s.x, seabedY(s.x, s.z) + 0.02, s.z);
      o.rotation.set(rand(-0.15, 0.15), rand(0, 6.3), rand(-0.15, 0.15));
      o.scale.setScalar(sc);
      return jitter(pick([0xff6a3d, 0xff3d6e, 0xa855f7, 0xffb02e]), 0.06);
    });

    // ------------------------------------------------ kelp and sea grass
    {
      const kelpGeo = new THREE.PlaneGeometry(1, 1, 1, 8).translate(0, 0.5, 0);
      const kelpMat = new THREE.MeshLambertMaterial({ color: 0xffffff, map: texKelp(THREE), alphaTest: 0.5, side: THREE.DoubleSide });
      animate(kelpMat, 'kelp', { vertex: SWAY(0.35) });
      const kelpSpots = scatter(150, { min: 3, max: 40, falloff: 14, tall: true, bias: (x, z) => (Math.abs(x) > 21 || z > HL + 6 ? 1 : 0.15) });
      instanced(kelpGeo, kelpMat, kelpSpots, (s, i, o) => {
        o.position.set(s.x, seabedY(s.x, s.z) - 0.1, s.z);
        o.rotation.y = rand(0, 6.3);
        o.scale.set(rand(1.3, 2.4), rand(4, 8), 1);
        return jitter(pick([0x3fae5a, 0x5cc46a, 0x2f9c6e, 0x7ccf4f, 0x9bbf3a]), 0.08);
      });
      const grassGeo = new THREE.PlaneGeometry(1, 1, 1, 3).translate(0, 0.5, 0);
      const grassMat = new THREE.MeshLambertMaterial({ color: 0xffffff, map: texGrass(THREE), alphaTest: 0.5, side: THREE.DoubleSide });
      animate(grassMat, 'grass', { vertex: SWAY(0.2) });
      instanced(grassGeo, grassMat, scatter(420, { min: 0.6, max: 22, falloff: 6 }), (s, i, o) => {
        o.position.set(s.x, seabedY(s.x, s.z) - 0.05, s.z);
        o.rotation.y = rand(0, 6.3);
        o.scale.set(rand(0.9, 1.8), rand(0.6, 1.5), 1);
        return jitter(pick([0x4fc36a, 0x8fd35a, 0x35b08a, 0xb9d64a]), 0.08);
      });
    }

    // ------------------------------------------------ pearls on the wall rail
    {
      const r = ctx.corner + 0.2, hw = HW + 0.2, hl = HL + 0.2, y = 1.1 + 0.14;
      const pts = [];
      const walk = (n, f) => { for (let i = 0; i < n; i++) pts.push(f(i / n)); };
      const nS = 22, nE = 11, nC = 3;
      walk(nS, (t) => [-hw + r + (2 * (hw - r)) * t, -hl]);
      walk(nC, (t) => { const a = -Math.PI / 2 + (Math.PI / 2) * t; return [hw - r + Math.cos(a) * r, -hl + r + Math.sin(a) * r]; });
      walk(nE, (t) => [hw, -hl + r + (2 * (hl - r)) * t]);
      walk(nC, (t) => { const a = (Math.PI / 2) * t; return [hw - r + Math.cos(a) * r, hl - r + Math.sin(a) * r]; });
      walk(nS, (t) => [hw - r - (2 * (hw - r)) * t, hl]);
      walk(nC, (t) => { const a = Math.PI / 2 + (Math.PI / 2) * t; return [-hw + r + Math.cos(a) * r, hl - r + Math.sin(a) * r]; });
      walk(nE, (t) => [-hw, hl - r - (2 * (hl - r)) * t]);
      walk(nC, (t) => { const a = Math.PI + (Math.PI / 2) * t; return [-hw + r + Math.cos(a) * r, -hl + r + Math.sin(a) * r]; });
      // sparser along the long sides: drop every other side pearl
      const spots = pts.map(([x, z]) => ({ x, z }));
      instanced(new THREE.SphereGeometry(0.24, 6, 4), new THREE.MeshLambertMaterial({ color: 0xffffff, emissive: 0x554455 }), spots, (s, i, o) => {
        o.position.set(s.x, y, s.z);
        o.scale.setScalar(i % 4 === 0 ? 1.35 : 1);
        return pick([0xfff6fb, 0xffeef5, 0xf3f7ff]);
      });
    }

    // ------------------------------------------------ light shafts
    let shaftMat = null;
    {
      const parts = [];
      const plane = new THREE.PlaneGeometry(1, 1, 1, 1);
      const shaftCol = (g) => { // fade to black (adds nothing) at top and bottom
        const P = g.attributes.position, c = [];
        for (let i = 0; i < P.count; i++) { const v = P.getY(i) > 0 ? 0.75 : 0.0; c.push(v, v, v); }
        g.setAttribute('color', new THREE.Float32BufferAttribute(c, 3));
        return g;
      };
      for (let i = 0; i < 9; i++) {
        const x = rand(-58, 58), z = rand(-40, 70);
        if (Math.abs(x) < 20 && z < HL + 8) continue;
        const w = rand(1.5, 4), hgt = rand(34, 60);
        for (const ry of [0.3, 1.87]) {
          const g = shaftCol(plane.clone());
          parts.push({ geo: g, color: 0xffffff, matrix: mat4(THREE, x, hgt / 2, z, 0.12, ry + rand(-0.2, 0.2), 0.08, w, hgt, 1) });
        }
      }
      const geo = mergeParts(THREE, parts);
      const mat = new THREE.MeshBasicMaterial({ color: 0x9fe8ff, vertexColors: true, transparent: true, opacity: 0.05, blending: THREE.AdditiveBlending, depthWrite: false, side: THREE.DoubleSide, fog: false });
      const mesh = new THREE.Mesh(geo, mat);
      mesh.frustumCulled = false;
      group.add(mesh);
      shaftMat = mat;
    }

    // ------------------------------------------------ shipwreck (far end, left)
    {
      const parts = [];
      const wood = 0x5a3a22, plank = 0x74502f, dark = 0x3b2616, algae = 0x4c8f5a;
      // hull: boat outline extruded, tapered by bevel
      const hs = new THREE.Shape();
      hs.moveTo(-7, 0); hs.quadraticCurveTo(-6.5, 2.4, -3, 2.5); hs.lineTo(4, 2.3); hs.quadraticCurveTo(7.5, 1.8, 8.5, 0);
      hs.quadraticCurveTo(7.5, -1.8, 4, -2.3); hs.lineTo(-3, -2.5); hs.quadraticCurveTo(-6.5, -2.4, -7, 0);
      const hull = new THREE.ExtrudeGeometry(hs, { depth: 2.6, bevelEnabled: true, bevelThickness: 0.9, bevelSize: 0.7, bevelSegments: 2, curveSegments: 6 });
      hull.rotateX(-Math.PI / 2);
      parts.push({ geo: hull, color: wood, matrix: mat4(THREE, 0, -0.5, 0) });
      // gunwale rail and deck line
      const rail = new THREE.ExtrudeGeometry(hs, { depth: 0.25, bevelEnabled: false, curveSegments: 6 });
      rail.rotateX(-Math.PI / 2);
      parts.push({ geo: rail, color: plank, matrix: mat4(THREE, 0, 2.15, 0, 0, 0, 0, 1.04, 1, 1.04) });
      // ribs where the hull broke open (stern-left)
      for (let i = 0; i < 6; i++) parts.push({ geo: new THREE.BoxGeometry(0.22, 2.4, 0.3), color: dark, matrix: mat4(THREE, -6.2 + i * 0.8, 2.6, 2.1 - i * 0.05, rand(-0.2, 0.2), 0, -0.4 + i * 0.05) });
      // stern cabin
      parts.push({ geo: new THREE.BoxGeometry(3.2, 1.6, 3.6), color: plank, matrix: mat4(THREE, -4.2, 3.0, 0) });
      parts.push({ geo: new THREE.BoxGeometry(3.6, 0.3, 4.0), color: dark, matrix: mat4(THREE, -4.2, 3.9, 0) });
      // masts (one broken and tilted) with yards
      parts.push({ geo: new THREE.CylinderGeometry(0.16, 0.24, 11, 6), color: dark, matrix: mat4(THREE, 1.5, 7.4, 0.3, 0.06, 0, 0.22) });
      parts.push({ geo: new THREE.BoxGeometry(5.5, 0.22, 0.22), color: dark, matrix: mat4(THREE, 1.2, 9.2, 0.3, 0, 0.3, 0.22) });
      parts.push({ geo: new THREE.CylinderGeometry(0.14, 0.2, 5, 6), color: dark, matrix: mat4(THREE, -2.6, 5.2, -0.2, 0.5, 0, -0.9) });
      // bowsprit
      parts.push({ geo: new THREE.CylinderGeometry(0.1, 0.16, 4.5, 5), color: dark, matrix: mat4(THREE, 9.6, 2.9, 0, 0, 0, -1.2) });
      // barrels and crates on deck
      for (let i = 0; i < 3; i++) parts.push({ geo: new THREE.CylinderGeometry(0.5, 0.5, 1, 8), color: plank, matrix: mat4(THREE, 3.5 + i * 1.1, 2.8, -1 + i * 0.7, i ? 1.5 : 0, 0, 0) });
      parts.push({ geo: new THREE.BoxGeometry(1.1, 1.1, 1.1), color: wood, matrix: mat4(THREE, 6.5, 2.85, 0.9, 0, 0.6, 0) });
      // algae clumps
      for (let i = 0; i < 7; i++) parts.push({ geo: new THREE.SphereGeometry(0.55, 6, 4), color: algae, matrix: mat4(THREE, rand(-6, 7), rand(2.2, 3.4), rand(-2, 2), 0, 0, 0, rand(1, 1.8), 0.6, rand(1, 1.8)) });
      const geo = mergeParts(THREE, parts);
      const mesh = new THREE.Mesh(geo, new THREE.MeshLambertMaterial({ vertexColors: true }));
      const wx = -14, wz = 40.5;
      mesh.position.set(wx, seabedY(wx, wz) - 1.1, wz);
      mesh.rotation.set(0.08, 0.35, 0.28);
      mesh.castShadow = true; mesh.receiveShadow = true;
      group.add(mesh);
    }

    // ------------------------------------------------ sunken temple ruin (far end, right) + stray columns
    {
      const stone = 0xe3dcc6, stoneDark = 0xb9b19a, moss = 0x6f9a63;
      const cols = [];
      const extras = [];
      const rx = 25.5, rz = 40;
      const gy = seabedY(rx, rz);
      extras.push({ geo: new THREE.BoxGeometry(16, 0.6, 12), color: stoneDark, matrix: mat4(THREE, rx, gy + 0.1, rz, 0, 0.1, 0.02) });
      extras.push({ geo: new THREE.BoxGeometry(13.5, 0.6, 9.5), color: stone, matrix: mat4(THREE, rx, gy + 0.7, rz, 0, 0.1, 0.02) });
      const top = gy + 1.0;
      const grid = [];
      for (let i = 0; i < 4; i++) for (const zz of [-3.4, 3.4]) grid.push([rx - 5 + i * 3.4, rz + zz]);
      grid.forEach(([x, z], i) => {
        const full = i !== 2 && i !== 5 && i !== 7;
        const h = full ? 4.6 : rand(1.2, 2.4);
        cols.push({ x, y: top, z, h, tilt: full ? rand(-0.03, 0.03) : rand(-0.1, 0.1) });
        extras.push({ geo: new THREE.BoxGeometry(1.25, 0.28, 1.25), color: stone, matrix: mat4(THREE, x, top + 0.12, z) });
        if (full) extras.push({ geo: new THREE.BoxGeometry(1.3, 0.35, 1.3), color: stone, matrix: mat4(THREE, x, top + h + 0.15, z) });
      });
      // architrave across the first two full front columns and a fallen one
      extras.push({ geo: new THREE.BoxGeometry(4.2, 0.7, 1.2), color: stone, matrix: mat4(THREE, rx - 3.3, top + 4.6 + 0.6, rz - 3.4) });
      extras.push({ geo: new THREE.BoxGeometry(4.0, 0.7, 1.2), color: stoneDark, matrix: mat4(THREE, rx + 1, top + 0.45, rz + 0.3, 0, 0.5, 0.05) });
      // fallen column drums
      for (let i = 0; i < 4; i++) extras.push({ geo: new THREE.CylinderGeometry(0.5, 0.5, 1.4, 10), color: stone, matrix: mat4(THREE, rx + 8 + i * 1.5, top + 0.5, rz + 4.5 + i * 0.3, Math.PI / 2, 0, 1.3 + i * 0.05) });
      // pediment fragment
      const tri = new THREE.Shape(); tri.moveTo(-3, 0); tri.lineTo(3, 0); tri.lineTo(0, 1.6); tri.closePath();
      const ped = new THREE.ExtrudeGeometry(tri, { depth: 0.6, bevelEnabled: false });
      extras.push({ geo: ped, color: stone, matrix: mat4(THREE, rx + 3, gy + 0.3, rz + 9, -0.9, 0.4, 0) });
      for (let i = 0; i < 5; i++) extras.push({ geo: new THREE.SphereGeometry(0.5, 6, 4), color: moss, matrix: mat4(THREE, rx + rand(-6, 6), top + 0.1, rz + rand(-4, 4), 0, 0, 0, rand(1, 2), 0.4, rand(1, 2)) });
      // stray columns along the sides
      for (const [x, z, h] of [[-25, 8, 4.2], [-28.5, -6, 2.2], [24.5, -14, 3.4], [26, 12, 1.6], [-23, 40, 3.8]]) {
        const y = seabedY(x, z) - 0.3;
        cols.push({ x, y, z, h, tilt: rand(-0.12, 0.12) });
        extras.push({ geo: new THREE.BoxGeometry(1.3, 0.3, 1.3), color: stone, matrix: mat4(THREE, x, y + 0.1, z) });
        if (h > 3) extras.push({ geo: new THREE.BoxGeometry(1.3, 0.35, 1.3), color: stone, matrix: mat4(THREE, x, y + h + 0.15, z, 0, 0, 0) });
      }
      const colGeo = new THREE.CylinderGeometry(0.46, 0.52, 1, 12, 1, false).translate(0, 0.5, 0);
      instanced(colGeo, new THREE.MeshLambertMaterial({ color: 0xffffff }), cols, (s, i, o) => {
        o.position.set(s.x, s.y, s.z);
        o.rotation.set(s.tilt, 0, s.tilt * 0.7);
        o.scale.set(1, s.h, 1);
        return jitter(stone, 0.04);
      }, { shadow: true });
      const mesh = new THREE.Mesh(mergeParts(THREE, extras), new THREE.MeshLambertMaterial({ vertexColors: true }));
      mesh.receiveShadow = true;
      group.add(mesh);
    }

    // ------------------------------------------------ sunken stone head (left side)
    {
      const stone = 0x7d8798, dark = 0x5e6778, moss = 0x5f9a68;
      const parts = [
        { geo: new THREE.BoxGeometry(2.4, 4.2, 2.0), color: stone, matrix: mat4(THREE, 0, 2.1, 0) },
        { geo: new THREE.BoxGeometry(2.6, 0.6, 2.2), color: dark, matrix: mat4(THREE, 0, 3.1, 0.05) },            // brow
        { geo: new THREE.BoxGeometry(0.7, 1.4, 0.7), color: stone, matrix: mat4(THREE, 0, 2.1, 1.15, 0.15, 0, 0) },  // nose
        { geo: new THREE.BoxGeometry(2.0, 0.35, 0.4), color: dark, matrix: mat4(THREE, 0, 1.1, 1.05) },             // mouth
        { geo: new THREE.BoxGeometry(0.5, 0.5, 0.5), color: dark, matrix: mat4(THREE, -0.75, 2.75, 1.05) },
        { geo: new THREE.BoxGeometry(0.5, 0.5, 0.5), color: dark, matrix: mat4(THREE, 0.75, 2.75, 1.05) },
        { geo: new THREE.SphereGeometry(0.6, 6, 4), color: moss, matrix: mat4(THREE, -0.6, 4.2, -0.2, 0, 0, 0, 1.8, 0.5, 1.4) },
        { geo: new THREE.SphereGeometry(0.6, 6, 4), color: moss, matrix: mat4(THREE, 1.1, 3.4, 0.6, 0, 0, 0, 0.9, 0.5, 0.8) },
      ];
      const mesh = new THREE.Mesh(mergeParts(THREE, parts), new THREE.MeshLambertMaterial({ vertexColors: true }));
      const sx = -24, sz = 24;
      mesh.position.set(sx, seabedY(sx, sz) - 1.3, sz);
      mesh.rotation.set(-0.35, 1.2, 0.18);
      mesh.castShadow = true; mesh.receiveShadow = true;
      group.add(mesh);
    }

    // ------------------------------------------------ treasure chest
    {
      const wood = 0x6b4423, band = 0x3f3a36, gold = 0xffc23a;
      const parts = [
        { geo: new THREE.BoxGeometry(1.4, 0.8, 1.0), color: wood, matrix: mat4(THREE, 0, 0.4, 0) },
        { geo: new THREE.BoxGeometry(1.46, 0.82, 0.16), color: band, matrix: mat4(THREE, 0, 0.4, 0.44) },
        { geo: new THREE.BoxGeometry(1.46, 0.82, 0.16), color: band, matrix: mat4(THREE, 0, 0.4, -0.44) },
        { geo: new THREE.CylinderGeometry(0.5, 0.5, 1.4, 8, 1, false, 0, Math.PI), color: wood, matrix: mat4(THREE, 0, 0.8, -0.5, -1.9, 0, Math.PI / 2) },
        { geo: new THREE.SphereGeometry(0.5, 7, 5), color: gold, matrix: mat4(THREE, 0, 0.75, 0.05, 0, 0, 0, 1.2, 0.5, 0.9) },
      ];
      const mesh = new THREE.Mesh(mergeParts(THREE, parts), new THREE.MeshLambertMaterial({ vertexColors: true, emissive: 0x3a2a00 }));
      const cx = -19.5, cz = 36;
      mesh.position.set(cx, seabedY(cx, cz) - 0.15, cz);
      mesh.rotation.y = 0.7;
      group.add(mesh);
    }

    // ------------------------------------------------ fish schools
    const fish = [];
    {
      const geo = fishGeometry(THREE);
      const mat = new THREE.MeshLambertMaterial({ color: 0xffffff, side: THREE.DoubleSide });
      animate(mat, 'fish', { vertex: `
        float ph = instanceMatrix[3][0] * 1.3 + instanceMatrix[3][2] * 0.7;
        float tail = max(0.0, -position.x - 0.1);
        transformed.z += sin(uTime * 9.0 + ph) * tail * 0.7;
      ` });
      const schools = [
        // orbits are ellipses that stay outside the wall even at the corners (checked at x = 16.5 -> |z| > 31.5)
        { n: 80, rx: 24, rz: 46, y: 4.5, spd: 0.22, cols: [0xffc63d, 0xffb020], dir: 1 },
        { n: 60, rx: 30, rz: 50, y: 7.5, spd: -0.16, cols: [0x3d8bff, 0x5aa6ff, 0x8fd3ff], dir: -1 },
        { n: 50, rx: 22, rz: 52, y: 3.2, spd: 0.3, cols: [0xff7a1a, 0xffffff], dir: 1 },
        { n: 30, rx: 36, rz: 62, y: 12, spd: -0.11, cols: [0xdfe9f2, 0xc0d0e0], dir: -1 },
      ];
      const spots = [];
      for (const s of schools) {
        const base = rand(0, Math.PI * 2);
        for (let i = 0; i < s.n; i++) spots.push({
          school: s, off: rand(-0.6, 0.6), dr: rand(1, 1.25), dy: rand(-1.2, 1.2), amp: rand(0.3, 0.8), ph: rand(0, 6.3),
          size: rand(0.75, 1.25), col: pick(s.cols), base, wob: rand(0.6, 1.4),
        });
      }
      schools.forEach((s) => { s.a = rand(0, 6.3); });
      const mesh = instanced(geo, mat, spots, (s, i, o) => { o.position.set(s.school.rx, s.school.y, 0); o.scale.setScalar(s.size); return s.col; });
      fish.push({ mesh, spots, schools });
    }

    // ------------------------------------------------ manta rays
    const mantas = { spots: [{ a: 0.4, rx: 34, rz: 56, y: 9.5, spd: 0.075, sc: 9, ph: 0 }, { a: 3.6, rx: 44, rz: 66, y: 12, spd: -0.06, sc: 6, ph: 2 }] };
    {
      const mat = new THREE.MeshLambertMaterial({ vertexColors: true, side: THREE.DoubleSide });
      animate(mat, 'manta', { vertex: `
        float flap = sin(uTime * 1.5 + instanceMatrix[3][0] * 0.05 + instanceMatrix[3][2] * 0.03);
        transformed.y += flap * pow(abs(position.x), 1.6) * 0.45;
      ` });
      mantas.mesh = instanced(mantaGeometry(THREE), mat, mantas.spots, (s, i, o) => { o.position.set(s.rx, s.y, 0); o.scale.setScalar(s.sc); return 0xffffff; });
    }

    // ------------------------------------------------ jellyfish
    const jellies = { spots: scatter(22, { min: 4, max: 40, falloff: 18, tall: true }).map((s) => ({ ...s, y: rand(3, 10), ph: rand(0, 6.3), sc: rand(0.6, 1.5), col: pick([0xff9ad5, 0xb9a6ff, 0x9de8ff, 0xffc4a8]) })) };
    {
      const bell = new THREE.SphereGeometry(1, 9, 5, 0, Math.PI * 2, 0, Math.PI * 0.55);
      const parts = [{ geo: bell, color: 0xffffff }];
      for (let i = 0; i < 4; i++) parts.push({ geo: new THREE.CylinderGeometry(0.05, 0.02, 2.2, 3, 1, true), color: 0xffffff, matrix: mat4(THREE, Math.cos(i * 1.57) * 0.45, -1.1, Math.sin(i * 1.57) * 0.45, rand(-0.2, 0.2), 0, rand(-0.2, 0.2)) });
      const mat = new THREE.MeshLambertMaterial({ color: 0xffffff, emissive: 0x552255, transparent: true, opacity: 0.72, depthWrite: false, side: THREE.DoubleSide });
      jellies.mesh = instanced(mergeParts(THREE, parts), mat, jellies.spots, (s, i, o) => { o.position.set(s.x, seabedY(s.x, s.z) + s.y, s.z); o.scale.setScalar(s.sc); return s.col; });
    }

    // ------------------------------------------------ bubbles and motes
    const bubbles = {};
    {
      const sites = scatter(16, { min: 2, max: 34, falloff: 14, tall: true });
      sites.push({ x: -14, z: 40.5 }, { x: -19.5, z: 36 }, { x: 25.5, z: 40 });
      const pts = [];
      for (const s of sites) for (let i = 0; i < 12; i++) pts.push({ cx: s.x, cz: s.z, y0: seabedY(s.x, s.z), y: rand(0, 14), top: rand(10, 16), spd: rand(1.2, 2.6), ph: rand(0, 6.3), r: rand(0.15, 0.5), mote: false });
      const moteSpots = scatter(120, { min: 1, max: 60, falloff: 40 });
      for (const s of moteSpots) pts.push({ cx: s.x, cz: s.z, y0: seabedY(s.x, s.z), y: rand(0.5, 12), top: 14, spd: rand(0.15, 0.4), ph: rand(0, 6.3), r: 0.35, mote: true });
      const pos = new Float32Array(pts.length * 3);
      const geo = new THREE.BufferGeometry();
      geo.setAttribute('position', new THREE.BufferAttribute(pos, 3));
      const mat = new THREE.PointsMaterial({ map: texBubble(THREE), size: 0.55, sizeAttenuation: true, transparent: true, opacity: 0.75, depthWrite: false, color: 0xe8fbff });
      const mesh = new THREE.Points(geo, mat);
      mesh.frustumCulled = false;
      group.add(mesh);
      Object.assign(bubbles, { pts, pos, geo, mesh });
    }

    // ------------------------------------------------ animation
    return {
      update(dt, time) {
        dt = Math.min(dt, 0.1);
        T.value = time;
        if (shaftMat) shaftMat.opacity = 0.05 + Math.sin(time * 0.7) * 0.015 + Math.sin(time * 1.9) * 0.008;
        // fish
        for (const f of fish) {
          for (const s of f.schools) s.a += s.spd * dt;
          f.spots.forEach((s, i) => {
            const sc = s.school;
            const a = sc.a + s.off + Math.sin(time * 0.7 * s.wob + s.ph) * 0.05;
            const rx = sc.rx * s.dr, rz = sc.rz * s.dr;
            const x = Math.cos(a) * rx, z = Math.sin(a) * rz;
            const y = sc.y + s.dy + Math.sin(time * 0.9 + s.ph) * s.amp;
            const dx = -Math.sin(a) * rx * sc.dir, dz = Math.cos(a) * rz * sc.dir;
            dummy.position.set(x, y, z);
            dummy.rotation.set(0, Math.atan2(-dz, dx), Math.sin(time * 1.3 + s.ph) * 0.15);
            dummy.scale.setScalar(s.size);
            dummy.updateMatrix();
            f.mesh.setMatrixAt(i, dummy.matrix);
          });
          f.mesh.instanceMatrix.needsUpdate = true;
        }
        // mantas
        mantas.spots.forEach((s, i) => {
          s.a += s.spd * dt;
          const x = Math.cos(s.a) * s.rx, z = Math.sin(s.a) * s.rz;
          const dir = Math.sign(s.spd);
          const dx = -Math.sin(s.a) * s.rx * dir, dz = Math.cos(s.a) * s.rz * dir;
          dummy.position.set(x, s.y + Math.sin(time * 0.35 + s.ph) * 1.5, z);
          dummy.rotation.set(Math.sin(time * 0.35 + s.ph) * 0.08, Math.atan2(-dx, -dz), 0.22 * dir);
          dummy.scale.setScalar(s.sc);
          dummy.updateMatrix();
          mantas.mesh.setMatrixAt(i, dummy.matrix);
        });
        mantas.mesh.instanceMatrix.needsUpdate = true;
        // jellyfish: slow bob and pulse
        jellies.spots.forEach((s, i) => {
          const p = 1 + Math.sin(time * 1.6 + s.ph) * 0.12;
          dummy.position.set(s.x + Math.sin(time * 0.25 + s.ph) * 1.5, seabedY(s.x, s.z) + s.y + Math.sin(time * 0.5 + s.ph) * 1.2, s.z + Math.cos(time * 0.2 + s.ph) * 1.5);
          dummy.rotation.set(Math.sin(time * 0.4 + s.ph) * 0.2, 0, Math.cos(time * 0.3 + s.ph) * 0.2);
          dummy.scale.set(s.sc * p, s.sc * (2 - p), s.sc * p);
          dummy.updateMatrix();
          jellies.mesh.setMatrixAt(i, dummy.matrix);
        });
        jellies.mesh.instanceMatrix.needsUpdate = true;
        // bubbles: rise and wobble, motes drift
        const P = bubbles.pos;
        bubbles.pts.forEach((b, i) => {
          b.y += b.spd * dt;
          if (b.y > b.top) b.y = 0;
          const w = b.mote ? 0.9 : 0.3 + b.y * 0.03;
          P[i * 3] = b.cx + Math.sin(time * 1.7 + b.ph) * w;
          P[i * 3 + 1] = b.y0 + b.y;
          P[i * 3 + 2] = b.cz + Math.cos(time * 1.3 + b.ph) * w;
        });
        bubbles.geo.attributes.position.needsUpdate = true;
      },
    };
  },
};
