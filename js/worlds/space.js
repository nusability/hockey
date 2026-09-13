// Deep Space — a floating arena platform drifting between the stars.
//
// Layers (far to near): a sky sphere with a painted milky way, a twinkling
// starfield (Points), additive nebula puffs, a huge banded gas giant below the
// far goal, a ringed ice planet and a cratered moon low beside the side walls,
// a slowly turning asteroid belt, a wheel station and two orbiting satellites;
// then the arena hull with outrigger thruster pods, floodlight masts, holo
// boards, glowing halo rings and pulsing neon edge lights.
//
// Budget: ~45k triangles, ~28 draw calls. update() only rotates a few groups,
// pokes a handful of uniforms/opacities and recolours 72 light studs.

const TAU = Math.PI * 2;

function canvas(w, h) {
  const c = document.createElement('canvas');
  c.width = w; c.height = h;
  return [c, c.getContext('2d')];
}

// Merge a list of (already transformed) geometries into one non-indexed geometry.
function merge(THREE, geos) {
  const parts = geos.map((g) => (g.index ? g.toNonIndexed() : g));
  let n = 0;
  for (const g of parts) n += g.attributes.position.count;
  const pos = new Float32Array(n * 3), nor = new Float32Array(n * 3), uv = new Float32Array(n * 2);
  const hasColor = parts.some((g) => g.attributes.color);
  const col = hasColor ? new Float32Array(n * 3).fill(1) : null;
  let o = 0;
  for (const g of parts) {
    const c = g.attributes.position.count;
    pos.set(g.attributes.position.array, o * 3);
    if (g.attributes.normal) nor.set(g.attributes.normal.array, o * 3);
    if (g.attributes.uv) uv.set(g.attributes.uv.array, o * 2);
    if (col && g.attributes.color) col.set(g.attributes.color.array, o * 3);
    o += c;
  }
  const out = new THREE.BufferGeometry();
  out.setAttribute('position', new THREE.BufferAttribute(pos, 3));
  out.setAttribute('normal', new THREE.BufferAttribute(nor, 3));
  out.setAttribute('uv', new THREE.BufferAttribute(uv, 2));
  if (col) out.setAttribute('color', new THREE.BufferAttribute(col, 3));
  for (const g of parts) g.dispose();
  return out;
}

// Give every vertex of a geometry the same colour (for vertex-coloured merges).
function tint(THREE, g, hex) {
  const c = new THREE.Color(hex);
  const n = g.attributes.position.count;
  const a = new Float32Array(n * 3);
  for (let i = 0; i < n; i++) { a[i * 3] = c.r; a[i * 3 + 1] = c.g; a[i * 3 + 2] = c.b; }
  g.setAttribute('color', new THREE.BufferAttribute(a, 3));
  return g;
}

// Move/rotate/scale a geometry in place (rotation order X, Y, Z).
function place(g, x, y, z, rx = 0, ry = 0, rz = 0, s = 1) {
  if (s !== 1) g.scale(s, s, s);
  if (rx) g.rotateX(rx);
  if (ry) g.rotateY(ry);
  if (rz) g.rotateZ(rz);
  g.translate(x, y, z);
  return g;
}

function roundedRectShape(THREE, hw, hl, r) {
  const s = new THREE.Shape();
  s.moveTo(-hw + r, -hl);
  s.lineTo(hw - r, -hl);
  s.absarc(hw - r, -hl + r, r, -Math.PI / 2, 0, false);
  s.lineTo(hw, hl - r);
  s.absarc(hw - r, hl - r, r, 0, Math.PI / 2, false);
  s.lineTo(-hw + r, hl);
  s.absarc(-hw + r, hl - r, r, Math.PI / 2, Math.PI, false);
  s.lineTo(-hw, -hl + r);
  s.absarc(-hw + r, -hl + r, r, Math.PI, Math.PI * 1.5, false);
  return s;
}

// n points evenly spaced along the outline of a rounded rectangle (x, z pairs).
function roundedRectPoints(hw, hl, r, n) {
  const straightX = 2 * (hw - r), straightZ = 2 * (hl - r), arc = (Math.PI / 2) * r;
  const L = 2 * straightX + 2 * straightZ + 4 * arc;
  const pts = [];
  for (let i = 0; i < n; i++) {
    let t = (i / n) * L;
    // walk: bottom side (-z) left->right, arc, right side, arc, top side, arc, left side, arc
    if (t < straightX) { pts.push([-hw + r + t, -hl]); continue; } t -= straightX;
    if (t < arc) { const a = -Math.PI / 2 + t / r; pts.push([hw - r + Math.cos(a) * r, -hl + r + Math.sin(a) * r]); continue; } t -= arc;
    if (t < straightZ) { pts.push([hw, -hl + r + t]); continue; } t -= straightZ;
    if (t < arc) { const a = t / r; pts.push([hw - r + Math.cos(a) * r, hl - r + Math.sin(a) * r]); continue; } t -= arc;
    if (t < straightX) { pts.push([hw - r - t, hl]); continue; } t -= straightX;
    if (t < arc) { const a = Math.PI / 2 + t / r; pts.push([-hw + r + Math.cos(a) * r, hl - r + Math.sin(a) * r]); continue; } t -= arc;
    if (t < straightZ) { pts.push([-hw, hl - r - t]); continue; } t -= straightZ;
    const a = Math.PI + t / r; pts.push([-hw + r + Math.cos(a) * r, -hl + r + Math.sin(a) * r]);
  }
  return pts;
}

// ------------------------------------------------------------------ textures
function skyTexture(THREE, rand, pick) {
  const W = 2048, H = 1024;
  const [c, g] = canvas(W, H);
  const grad = g.createLinearGradient(0, 0, 0, H);
  grad.addColorStop(0, '#02030a');
  grad.addColorStop(0.42, '#060a1f');
  grad.addColorStop(0.62, '#0b0b2c');
  grad.addColorStop(0.85, '#170c3a');
  grad.addColorStop(1, '#1f0f3f');
  g.fillStyle = grad;
  g.fillRect(0, 0, W, H);
  const blob = (x, y, r, rgb, a) => {
    const rg = g.createRadialGradient(x, y, 0, x, y, r);
    rg.addColorStop(0, `rgba(${rgb},${a})`);
    rg.addColorStop(1, `rgba(${rgb},0)`);
    g.fillStyle = rg;
    g.fillRect(x - r, y - r, r * 2, r * 2);
  };
  // broad colour washes low in the sky (the goal camera looks down there)
  blob(W * 0.15, H * 0.62, 520, '90,40,160', 0.22);
  blob(W * 0.55, H * 0.72, 600, '20,90,150', 0.2);
  blob(W * 0.85, H * 0.58, 460, '150,50,110', 0.16);
  blob(W * 0.38, H * 0.3, 420, '40,60,140', 0.14);
  // milky way: a tilted great circle -> sinusoid in equirect space
  const band = (u) => 0.5 + 0.21 * Math.sin(u * TAU + 0.9);
  const warm = ['255,238,214', '216,226,255', '236,214,255', '255,224,200', '255,255,255'];
  for (let i = 0; i < 900; i++) {
    const u = rand(0, 1);
    const v = band(u) + (rand(0, 1) + rand(0, 1) - 1) * 0.1;
    const wrapX = (u * W + rand(-40, 40) + W) % W;
    blob(wrapX, v * H, rand(16, 80), pick(warm), rand(0.012, 0.05));
  }
  for (let i = 0; i < 260; i++) {
    const u = rand(0, 1);
    const v = band(u) + (rand(0, 1) + rand(0, 1) - 1) * 0.035;
    blob(u * W, v * H, rand(10, 46), '4,3,12', rand(0.04, 0.09));
  }
  // thousands of faint distant stars, denser along the band
  for (let i = 0; i < 9000; i++) {
    const u = rand(0, 1), v = rand(0, 1);
    const near = Math.exp(-Math.pow((v - band(u)) / 0.16, 2));
    if (rand(0, 1) > 0.35 + near) continue;
    const a = rand(0.2, 0.9), r = rand(0.5, 1.4);
    g.fillStyle = `rgba(${pick(warm)},${a})`;
    g.beginPath(); g.arc(u * W, v * H, r, 0, TAU); g.fill();
  }
  const t = new THREE.CanvasTexture(c);
  t.colorSpace = THREE.SRGBColorSpace;
  return t;
}

function gasGiantTexture(THREE, rand, pick) {
  const W = 1024, H = 512;
  const [c, g] = canvas(W, H);
  const palette = ['#f3dcae', '#e6b98a', '#c9776a', '#f6e7c9', '#a45c6b', '#e2a27c', '#6f4c8f', '#f1d4b2', '#d98a6a', '#8b5a97'];
  // bands with wavy edges
  let y = 0, i = 0;
  const bands = [];
  while (y < H) {
    const h = rand(14, 58);
    bands.push({ y, h, col: palette[i % palette.length] });
    y += h; i++;
  }
  g.fillStyle = palette[0]; g.fillRect(0, 0, W, H);
  for (const b of bands) {
    g.fillStyle = b.col;
    g.beginPath();
    const amp = rand(3, 10), f = rand(2, 5), ph = rand(0, TAU);
    g.moveTo(0, b.y);
    for (let x = 0; x <= W; x += 16) g.lineTo(x, b.y + Math.sin((x / W) * TAU * f + ph) * amp);
    g.lineTo(W, H); g.lineTo(0, H); g.closePath();
    g.fill();
  }
  // soft streaks + turbulence
  for (let k = 0; k < 340; k++) {
    const yy = rand(0, H), len = rand(40, 260), hh = rand(2, 9);
    g.fillStyle = `rgba(${pick(['255,245,225', '120,60,90', '255,200,160', '90,60,120'])},${rand(0.06, 0.22)})`;
    g.beginPath();
    g.ellipse(rand(0, W), yy, len, hh, 0, 0, TAU);
    g.fill();
  }
  // great storm
  const sx = W * 0.62, sy = H * 0.6;
  for (let r = 0; r < 7; r++) {
    g.strokeStyle = `rgba(${r % 2 ? '255,240,225' : '150,70,80'},${0.55 - r * 0.06})`;
    g.lineWidth = 5;
    g.beginPath(); g.ellipse(sx, sy, 62 - r * 7, 34 - r * 4, 0, 0, TAU); g.stroke();
  }
  g.fillStyle = 'rgba(250,215,190,0.8)';
  g.beginPath(); g.ellipse(sx, sy, 18, 9, 0, 0, TAU); g.fill();
  // subtle polar darkening
  const pg = g.createLinearGradient(0, 0, 0, H);
  pg.addColorStop(0, 'rgba(40,20,60,0.55)'); pg.addColorStop(0.18, 'rgba(40,20,60,0)');
  pg.addColorStop(0.82, 'rgba(40,20,60,0)'); pg.addColorStop(1, 'rgba(40,20,60,0.55)');
  g.fillStyle = pg; g.fillRect(0, 0, W, H);
  const t = new THREE.CanvasTexture(c);
  t.colorSpace = THREE.SRGBColorSpace;
  return t;
}

function icePlanetTexture(THREE, rand, pick) {
  const W = 512, H = 256;
  const [c, g] = canvas(W, H);
  g.fillStyle = '#cfe6ff'; g.fillRect(0, 0, W, H);
  const cols = ['#a9cdf7', '#e6f2ff', '#7fb0e6', '#bfdcff', '#d9ecff', '#8fbdf0'];
  let y = 0, i = 0;
  while (y < H) { const h = rand(8, 40); g.fillStyle = cols[i % cols.length]; g.fillRect(0, y, W, h); y += h; i++; }
  for (let k = 0; k < 160; k++) {
    g.fillStyle = `rgba(${pick(['255,255,255', '90,140,210', '200,230,255'])},${rand(0.08, 0.3)})`;
    g.beginPath(); g.ellipse(rand(0, W), rand(0, H), rand(20, 120), rand(2, 7), 0, 0, TAU); g.fill();
  }
  const t = new THREE.CanvasTexture(c);
  t.colorSpace = THREE.SRGBColorSpace;
  return t;
}

function moonTexture(THREE, rand) {
  const W = 512, H = 256;
  const [c, g] = canvas(W, H);
  g.fillStyle = '#9b9ca8'; g.fillRect(0, 0, W, H);
  for (let k = 0; k < 90; k++) {
    g.fillStyle = `rgba(${k % 3 ? '120,118,135' : '180,178,190'},${rand(0.2, 0.5)})`;
    g.beginPath(); g.ellipse(rand(0, W), rand(0, H), rand(20, 90), rand(14, 60), 0, 0, TAU); g.fill();
  }
  for (let k = 0; k < 140; k++) {
    const x = rand(0, W), y = rand(0, H), r = rand(3, 22);
    g.fillStyle = 'rgba(70,68,88,0.55)';
    g.beginPath(); g.arc(x, y, r, 0, TAU); g.fill();
    g.strokeStyle = 'rgba(220,220,235,0.6)'; g.lineWidth = Math.max(1, r * 0.18);
    g.beginPath(); g.arc(x, y, r, Math.PI * 1.1, Math.PI * 1.9); g.stroke();
  }
  const t = new THREE.CanvasTexture(c);
  t.colorSpace = THREE.SRGBColorSpace;
  return t;
}

function ringTexture(THREE, rand) {
  const S = 512;
  const [c, g] = canvas(S, S);
  g.clearRect(0, 0, S, S);
  const cx = S / 2;
  // concentric bands; inner radius ~ 0.55, outer 1.0 of the canvas half size
  for (let r = cx * 0.55; r < cx; r += 1.5) {
    const t = (r - cx * 0.55) / (cx * 0.45);
    const gap = Math.sin(t * 40) * 0.5 + Math.sin(t * 7.3) * 0.5;
    const a = Math.max(0, 0.15 + 0.55 * (0.5 + 0.5 * gap)) * (t > 0.93 ? (1 - t) / 0.07 : 1);
    const col = t < 0.35 ? '215,200,255' : t < 0.7 ? '250,235,205' : '180,215,255';
    g.strokeStyle = `rgba(${col},${a * rand(0.8, 1)})`;
    g.lineWidth = 1.6;
    g.beginPath(); g.arc(cx, cx, r, 0, TAU); g.stroke();
  }
  const t = new THREE.CanvasTexture(c);
  t.colorSpace = THREE.SRGBColorSpace;
  return t;
}

function softTexture(THREE, rand) {
  const S = 256;
  const [c, g] = canvas(S, S);
  g.clearRect(0, 0, S, S);
  const rg = g.createRadialGradient(S / 2, S / 2, 0, S / 2, S / 2, S / 2);
  rg.addColorStop(0, 'rgba(255,255,255,0.75)');
  rg.addColorStop(0.35, 'rgba(255,255,255,0.32)');
  rg.addColorStop(1, 'rgba(255,255,255,0)');
  g.fillStyle = rg; g.fillRect(0, 0, S, S);
  for (let k = 0; k < 26; k++) {
    const r = rand(18, 60), x = rand(r, S - r), y = rand(r, S - r);
    const d = Math.hypot(x - S / 2, y - S / 2) / (S / 2);
    const g2 = g.createRadialGradient(x, y, 0, x, y, r);
    g2.addColorStop(0, `rgba(255,255,255,${0.3 * (1 - d)})`);
    g2.addColorStop(1, 'rgba(255,255,255,0)');
    g.fillStyle = g2; g.fillRect(x - r, y - r, r * 2, r * 2);
  }
  return new THREE.CanvasTexture(c);
}

function glowTexture(THREE) {
  const S = 128;
  const [c, g] = canvas(S, S);
  g.clearRect(0, 0, S, S);
  const rg = g.createRadialGradient(S / 2, S / 2, 0, S / 2, S / 2, S / 2);
  rg.addColorStop(0, 'rgba(255,255,255,1)');
  rg.addColorStop(0.25, 'rgba(255,255,255,0.55)');
  rg.addColorStop(1, 'rgba(255,255,255,0)');
  g.fillStyle = rg; g.fillRect(0, 0, S, S);
  return new THREE.CanvasTexture(c);
}

function dashTexture(THREE) {
  const [c, g] = canvas(256, 8);
  g.clearRect(0, 0, 256, 8);
  g.fillStyle = '#fff';
  g.fillRect(0, 0, 150, 8);
  g.fillRect(176, 0, 30, 8);
  const t = new THREE.CanvasTexture(c);
  t.wrapS = THREE.RepeatWrapping; t.wrapT = THREE.RepeatWrapping;
  return t;
}

function holoTexture(THREE, rand) {
  const W = 512, H = 256;
  const [c, g] = canvas(W, H);
  g.clearRect(0, 0, W, H);
  g.fillStyle = 'rgba(8,22,60,0.72)';
  g.beginPath(); g.roundRect(4, 4, W - 8, H - 8, 18); g.fill();
  g.strokeStyle = 'rgba(125,249,255,0.9)'; g.lineWidth = 6;
  g.beginPath(); g.roundRect(4, 4, W - 8, H - 8, 18); g.stroke();
  // planet emblem
  g.fillStyle = 'rgba(244,114,182,0.9)';
  g.beginPath(); g.arc(110, 128, 54, 0, TAU); g.fill();
  g.strokeStyle = 'rgba(125,249,255,0.95)'; g.lineWidth = 9;
  g.beginPath(); g.ellipse(110, 128, 92, 22, -0.35, 0, TAU); g.stroke();
  // bar graph / ticker
  for (let i = 0; i < 9; i++) {
    const h = rand(30, 120);
    g.fillStyle = i % 2 ? 'rgba(125,249,255,0.85)' : 'rgba(240,171,252,0.85)';
    g.fillRect(230 + i * 28, 200 - h, 18, h);
  }
  // chevrons
  g.strokeStyle = 'rgba(250,240,138,0.9)'; g.lineWidth = 8;
  for (let i = 0; i < 4; i++) {
    const x = 250 + i * 60;
    g.beginPath(); g.moveTo(x, 34); g.lineTo(x + 26, 56); g.lineTo(x, 78); g.stroke();
  }
  const t = new THREE.CanvasTexture(c);
  t.colorSpace = THREE.SRGBColorSpace;
  return t;
}

// ------------------------------------------------------------------ shaders
function starMaterial(THREE) {
  return new THREE.ShaderMaterial({
    uniforms: { uTime: { value: 0 }, uScale: { value: Math.min(window.devicePixelRatio || 1, 2) } },
    vertexShader: `
      attribute float aSize; attribute float aTw; attribute float aPhase; attribute vec3 aColor;
      uniform float uTime; uniform float uScale;
      varying vec3 vColor; varying float vA;
      void main() {
        float tw = 1.0 - aTw * (0.5 + 0.5 * sin(uTime * (0.9 + aPhase * 0.7) + aPhase * 9.0));
        vColor = aColor; vA = tw;
        gl_PointSize = aSize * uScale * (0.7 + 0.3 * tw);
        gl_Position = projectionMatrix * modelViewMatrix * vec4(position, 1.0);
      }`,
    fragmentShader: `
      varying vec3 vColor; varying float vA;
      void main() {
        vec2 d = gl_PointCoord - 0.5;
        float r = length(d) * 2.0;
        float a = smoothstep(1.0, 0.1, r); a *= a * vA;
        gl_FragColor = vec4(vColor * a, a);
        #include <colorspace_fragment>
      }`,
    transparent: true, depthWrite: false, blending: THREE.AdditiveBlending,
  });
}

function haloMaterial(THREE, color, c, p) {
  return new THREE.ShaderMaterial({
    uniforms: { uColor: { value: new THREE.Color(color) }, uC: { value: c }, uP: { value: p } },
    vertexShader: `
      varying vec3 vN;
      void main() { vN = normalize(normalMatrix * normal); gl_Position = projectionMatrix * modelViewMatrix * vec4(position, 1.0); }`,
    fragmentShader: `
      uniform vec3 uColor; uniform float uC; uniform float uP; varying vec3 vN;
      void main() { float i = pow(max(uC - vN.z, 0.0), uP); gl_FragColor = vec4(uColor * i, i);
        #include <colorspace_fragment> }`,
    side: THREE.BackSide, transparent: true, depthWrite: false, blending: THREE.AdditiveBlending,
  });
}

// ------------------------------------------------------------------ world
export default {
  id: 'space',
  sport: 'field',
  name: { en: 'Deep Space', de: 'Tiefer Weltraum' },
  tagline: { en: 'A floating arena adrift among the stars.', de: 'Eine schwebende Arena zwischen den Sternen.' },
  sky: 'linear-gradient(180deg, #02030a 0%, #070b22 55%, #1a0d3d 100%)',
  light: {
    hemiSky: 0x9fd0ff, hemiGround: 0x1a1240, hemiIntensity: 1.05,
    sun: 0xfff1d8, sunIntensity: 1.9, sunPos: [18, 60, -20],
  },
  surface: {
    base: '#151c33',
    stripe: '#121829',
    lines: '#7df9ff',
    decorate(c, W, H, h) {
      const sx = h.sx;
      // cyan energy haze creeping in from the edges
      const haze = (x0, y0, x1, y1, col) => {
        const g = c.createLinearGradient(x0, y0, x1, y1);
        g.addColorStop(0, col); g.addColorStop(1, 'rgba(56,189,248,0)');
        c.fillStyle = g; c.fillRect(0, 0, W, H);
      };
      haze(0, 0, W * 0.2, 0, 'rgba(56,189,248,0.26)');
      haze(W, 0, W * 0.8, 0, 'rgba(56,189,248,0.26)');
      haze(0, 0, 0, H * 0.1, 'rgba(56,189,248,0.26)');
      haze(0, H, 0, H * 0.9, 'rgba(56,189,248,0.26)');
      // scanlines
      c.fillStyle = 'rgba(0,0,0,0.09)';
      for (let y = 0; y < H; y += 6) c.fillRect(0, y, W, 2);
      // hex grid, brighter towards the edges
      const R = 1.25 * sx, dx = R * Math.sqrt(3), dy = R * 1.5;
      c.lineWidth = 2;
      let row = 0;
      for (let y = -dy; y < H + dy; y += dy, row++) {
        const off = row % 2 ? dx / 2 : 0;
        for (let x = -dx; x < W + dx; x += dx) {
          const cx = x + off, cy = y;
          const d = Math.min(cx, W - cx, cy, H - cy) / sx;
          const f = Math.max(0, 1 - d / 9);
          const a = 0.03 + 0.24 * f * f;
          c.strokeStyle = `rgba(125,249,255,${a})`;
          c.beginPath();
          for (let k = 0; k < 6; k++) {
            const ang = Math.PI / 6 + (k * Math.PI) / 3;
            const px = cx + R * Math.cos(ang), py = cy + R * Math.sin(ang);
            if (k === 0) c.moveTo(px, py); else c.lineTo(px, py);
          }
          c.closePath(); c.stroke();
        }
      }
      // soft pink glow in both shooting circles
      for (const z of [-26, 26]) {
        const g = c.createRadialGradient(h.X(0), h.Z(z), 0, h.X(0), h.Z(z), 11 * sx);
        g.addColorStop(0, 'rgba(244,114,182,0.2)'); g.addColorStop(1, 'rgba(244,114,182,0)');
        c.fillStyle = g; c.fillRect(0, 0, W, H);
      }
      // centre orbit rings
      c.strokeStyle = 'rgba(240,171,252,0.35)'; c.lineWidth = 3;
      for (const r of [4.2, 5.6]) { c.beginPath(); c.arc(h.X(0), h.Z(0), r * sx, 0, TAU); c.stroke(); }
      c.setLineDash([12, 18]);
      c.strokeStyle = 'rgba(125,249,255,0.45)'; c.lineWidth = 4;
      c.beginPath(); c.arc(h.X(0), h.Z(0), 7.2 * sx, 0, TAU); c.stroke();
      c.setLineDash([]);
    },
  },
  border: { color: 0x0369a1, top: 0x67e8f9, height: 1.1, glass: false, base: 0x121a38 },
  ball: { color: 0xfef08a, emissive: 0x3a2f00 },
  goal: { post: 0xf472b6, net: 0xbae6fd },

  buildScenery(group, ctx) {
    const { THREE, HW, HL, corner, rand, pick } = ctx;
    const anim = [];           // functions (dt, time) => void

    // ------------------------------------------------ sky sphere
    const sky = new THREE.Mesh(
      new THREE.SphereGeometry(440, 48, 28),
      new THREE.MeshBasicMaterial({ map: skyTexture(THREE, rand, pick), side: THREE.BackSide, fog: false }),
    );
    sky.rotation.y = 0.6;
    group.add(sky);

    // ------------------------------------------------ starfield
    {
      const N = 3400;
      const pos = new Float32Array(N * 3), col = new Float32Array(N * 3), size = new Float32Array(N), tw = new Float32Array(N), ph = new Float32Array(N);
      const tints = [[1, 1, 1], [1, 1, 1], [0.8, 0.88, 1], [1, 0.92, 0.78], [1, 0.8, 0.6], [0.75, 0.85, 1]];
      for (let i = 0; i < N; i++) {
        const y = rand(-1, 1), t = rand(0, TAU), rr = Math.sqrt(1 - y * y), R = rand(392, 412);
        pos[i * 3] = rr * Math.cos(t) * R; pos[i * 3 + 1] = y * R; pos[i * 3 + 2] = rr * Math.sin(t) * R;
        const tint = pick(tints), b = rand(0.55, 1);
        col[i * 3] = tint[0] * b; col[i * 3 + 1] = tint[1] * b; col[i * 3 + 2] = tint[2] * b;
        const big = rand(0, 1);
        size[i] = big > 0.985 ? rand(3.6, 5.2) : big > 0.9 ? rand(2.4, 3.4) : rand(1.1, 2.2);
        tw[i] = rand(0, 1) > 0.8 ? rand(0.45, 0.9) : 0;
        ph[i] = rand(0, 6.28);
      }
      const g = new THREE.BufferGeometry();
      g.setAttribute('position', new THREE.BufferAttribute(pos, 3));
      g.setAttribute('aColor', new THREE.BufferAttribute(col, 3));
      g.setAttribute('aSize', new THREE.BufferAttribute(size, 1));
      g.setAttribute('aTw', new THREE.BufferAttribute(tw, 1));
      g.setAttribute('aPhase', new THREE.BufferAttribute(ph, 1));
      const mat = starMaterial(THREE);
      const stars = new THREE.Points(g, mat);
      stars.frustumCulled = false;
      group.add(stars);
      anim.push((dt, t) => { mat.uniforms.uTime.value = t; });
    }

    // ------------------------------------------------ nebula puffs (one merged additive mesh)
    {
      const puffs = [];
      const cluster = (dir, spread, n, cols, sMin, sMax, bright) => {
        const d = new THREE.Vector3(...dir).normalize();
        for (let i = 0; i < n; i++) {
          const p = d.clone().add(new THREE.Vector3(rand(-spread, spread), rand(-spread, spread) * 0.6, rand(-spread, spread))).normalize().multiplyScalar(rand(350, 372));
          puffs.push({ p, s: rand(sMin, sMax), c: new THREE.Color(pick(cols)).multiplyScalar(rand(bright * 0.6, bright)) });
        }
      };
      // behind the gas giant (play camera), around the ringed planet (-X) and the moon (+X)
      cluster([0.2, -0.45, 1], 0.55, 16, [0x7c3aed, 0x22d3ee, 0xdb2777, 0x4f46e5], 70, 150, 0.32);
      cluster([-1, -0.25, 0.15], 0.5, 14, [0xd946ef, 0x7c3aed, 0xf472b6, 0x38bdf8], 70, 140, 0.34);
      cluster([-0.65, -0.6, 0.6], 0.45, 14, [0xe11d48, 0xa855f7, 0x22d3ee, 0xf97316], 70, 150, 0.36);
      cluster([1, -0.2, 0.2], 0.5, 12, [0xf97316, 0xec4899, 0x8b5cf6, 0x22d3ee], 60, 130, 0.28);
      cluster([0, 0.5, -1], 0.7, 10, [0x4f46e5, 0x0ea5e9, 0x9333ea], 60, 120, 0.2);
      cluster([0, -1, 0], 0.9, 12, [0x6d28d9, 0x1d4ed8, 0xbe185d], 80, 160, 0.22);
      const n = puffs.length;
      const pos = new Float32Array(n * 12), col = new Float32Array(n * 12), uv = new Float32Array(n * 8);
      const idx = [];
      const up0 = new THREE.Vector3(0, 1, 0), right = new THREE.Vector3(), up = new THREE.Vector3(), nrm = new THREE.Vector3();
      puffs.forEach((q, i) => {
        nrm.copy(q.p).negate().normalize();
        right.crossVectors(up0, nrm).normalize();
        up.crossVectors(nrm, right).normalize();
        const a = rand(0, TAU), ca = Math.cos(a), sa = Math.sin(a);
        const r2 = right.clone().multiplyScalar(ca).addScaledVector(up, sa);
        const u2 = up.clone().multiplyScalar(ca).addScaledVector(right, -sa);
        const corners = [[-1, -1], [1, -1], [1, 1], [-1, 1]];
        corners.forEach(([x, y], k) => {
          const v = q.p.clone().addScaledVector(r2, x * q.s).addScaledVector(u2, y * q.s * rand(0.6, 1));
          pos.set([v.x, v.y, v.z], i * 12 + k * 3);
          col.set([q.c.r, q.c.g, q.c.b], i * 12 + k * 3);
          uv.set([(x + 1) / 2, (y + 1) / 2], i * 8 + k * 2);
        });
        const b = i * 4;
        idx.push(b, b + 1, b + 2, b, b + 2, b + 3);
      });
      const g = new THREE.BufferGeometry();
      g.setAttribute('position', new THREE.BufferAttribute(pos, 3));
      g.setAttribute('color', new THREE.BufferAttribute(col, 3));
      g.setAttribute('uv', new THREE.BufferAttribute(uv, 2));
      g.setIndex(idx);
      const neb = new THREE.Mesh(g, new THREE.MeshBasicMaterial({
        map: softTexture(THREE, rand), vertexColors: true, transparent: true, depthWrite: false,
        blending: THREE.AdditiveBlending, side: THREE.DoubleSide, fog: false,
      }));
      neb.frustumCulled = false;
      group.add(neb);
    }

    // ------------------------------------------------ gas giant below the far goal
    {
      const R = 74;
      const planet = new THREE.Mesh(
        new THREE.SphereGeometry(R, 48, 32),
        new THREE.MeshLambertMaterial({ map: gasGiantTexture(THREE, rand, pick), emissive: 0x2a1630, emissiveIntensity: 0.55 }),
      );
      planet.position.set(38, -200, 252);
      planet.rotation.z = 0.28;
      group.add(planet);
      const halo = new THREE.Mesh(new THREE.SphereGeometry(R * 1.22, 32, 24), haloMaterial(THREE, 0xffb07a, 0.42, 4.5));
      halo.position.copy(planet.position);
      group.add(halo);
      anim.push((dt) => { planet.rotation.y += dt * 0.012; });
    }

    // ------------------------------------------------ ringed ice planet beside the -X wall
    {
      const R = 40;
      const pos = new THREE.Vector3(-282, -56, 12);
      const planet = new THREE.Mesh(
        new THREE.SphereGeometry(R, 40, 28),
        new THREE.MeshLambertMaterial({ map: icePlanetTexture(THREE, rand, pick), emissive: 0x16305a, emissiveIntensity: 0.7 }),
      );
      planet.position.copy(pos);
      group.add(planet);
      const halo = new THREE.Mesh(new THREE.SphereGeometry(R * 1.25, 32, 24), haloMaterial(THREE, 0x8fd3ff, 0.4, 4.0));
      halo.position.copy(pos);
      group.add(halo);
      const rings = new THREE.Mesh(
        new THREE.RingGeometry(R * 1.35, R * 2.45, 96, 1),
        new THREE.MeshBasicMaterial({ map: ringTexture(THREE, rand), transparent: true, depthWrite: false, side: THREE.DoubleSide, fog: false }),
      );
      // planar UVs of RingGeometry map the -1..1 square onto the 0..1 canvas
      rings.position.copy(pos);
      rings.lookAt(pos.x + 0.55, pos.y + 0.8, pos.z + 0.25);   // open the ring plane towards the arena
      group.add(rings);
      anim.push((dt) => { planet.rotation.y += dt * 0.02; });
    }

    // ------------------------------------------------ moons beside the +X wall
    {
      const moonTex = moonTexture(THREE, rand);
      // the big moon sits low off the far-left corner (seen while the goal camera swings in)
      const big = new THREE.Mesh(new THREE.SphereGeometry(26, 28, 20), new THREE.MeshLambertMaterial({ map: moonTex, emissive: 0x1a1a2e, emissiveIntensity: 0.5 }));
      big.position.set(-132, -100, 110);
      big.rotation.z = 0.4;
      group.add(big);
      // a smaller tan moon on the +X horizon
      const small = new THREE.Mesh(new THREE.SphereGeometry(14, 22, 16), new THREE.MeshLambertMaterial({ map: moonTex, color: 0xd8c8b0, emissive: 0x3a3048, emissiveIntensity: 0.8 }));
      small.position.set(248, -28, -14);
      group.add(small);
      anim.push((dt) => { big.rotation.y += dt * 0.03; small.rotation.y -= dt * 0.05; });
    }

    // ------------------------------------------------ asteroid belt (two instanced rock shapes)
    {
      const belt = new THREE.Group();
      belt.rotation.set(0.5, 0, 0.35);   // lowest point between -X and +Z
      const rockGeo = (seed) => {
        const g = new THREE.IcosahedronGeometry(1, 1);
        const p = g.attributes.position;
        const v = new THREE.Vector3();
        for (let i = 0; i < p.count; i++) {
          v.fromBufferAttribute(p, i);
          const f = 0.78 + 0.16 * Math.sin(v.x * 5.1 + seed) * Math.cos(v.y * 4.3 - seed) + 0.14 * Math.sin(v.z * 6.7 + v.x * 2.2 + seed * 1.7);
          v.multiplyScalar(f);
          p.setXYZ(i, v.x, v.y, v.z);
        }
        g.computeVertexNormals();
        return g;
      };
      const mat = new THREE.MeshLambertMaterial({ color: 0x8b7f78, emissive: 0x241a20, emissiveIntensity: 0.6 });
      const dummy = new THREE.Object3D();
      for (let k = 0; k < 2; k++) {
        const n = 120;
        const im = new THREE.InstancedMesh(rockGeo(k * 3.7 + 1), mat, n);
        for (let i = 0; i < n; i++) {
          const a = rand(0, TAU), r = 132 + rand(-18, 26) + (rand(0, 1) > 0.85 ? rand(20, 40) : 0);
          dummy.position.set(Math.cos(a) * r, rand(-9, 9), Math.sin(a) * r);
          dummy.rotation.set(rand(0, TAU), rand(0, TAU), rand(0, TAU));
          const s = rand(1.2, 4.0) * (rand(0, 1) > 0.92 ? 1.6 : 1);
          dummy.scale.set(s * rand(0.7, 1.3), s * rand(0.7, 1.3), s * rand(0.7, 1.3));
          dummy.updateMatrix();
          im.setMatrixAt(i, dummy.matrix);
        }
        im.frustumCulled = false;
        belt.add(im);
      }
      group.add(belt);
      anim.push((dt) => { belt.rotation.y += dt * 0.012; });
    }

    // ------------------------------------------------ wheel station (+X, low)
    {
      const parts = [];
      parts.push(new THREE.TorusGeometry(12, 1.5, 10, 40));
      parts.push(place(new THREE.CylinderGeometry(3, 3, 6, 16), 0, 0, 0, Math.PI / 2));
      for (let i = 0; i < 6; i++) parts.push(place(new THREE.BoxGeometry(0.7, 12, 0.7), 0, 6, 0, 0, 0, 0).rotateZ((i / 6) * TAU));
      parts.push(place(new THREE.CylinderGeometry(1, 1, 44, 10), 0, 0, 0, Math.PI / 2));
      for (const s of [-1, 1]) {
        parts.push(place(new THREE.BoxGeometry(16, 0.25, 6), 0, 0, s * 17));
        parts.push(place(new THREE.BoxGeometry(2.4, 2.4, 3), 0, 0, s * 21));
      }
      const station = new THREE.Mesh(merge(THREE, parts), new THREE.MeshLambertMaterial({ color: 0xc7ccd6, emissive: 0x1c2a44, emissiveIntensity: 0.6 }));
      station.position.set(214, -18, 24);
      station.rotation.set(0.25, -0.7, 0.15);
      group.add(station);
      anim.push((dt) => { station.rotation.z += dt * 0.12; });
    }

    // ------------------------------------------------ two satellites orbiting the arena
    {
      const sat = (x, z, ry) => {
        const ps = [
          place(new THREE.BoxGeometry(1.4, 1.4, 2.0), 0, 0, 0),
          place(new THREE.BoxGeometry(3.6, 0.08, 1.4), 2.6, 0, 0),
          place(new THREE.BoxGeometry(3.6, 0.08, 1.4), -2.6, 0, 0),
          place(new THREE.ConeGeometry(0.8, 0.5, 12, 1, true), 0, 1.0, 0),
        ];
        return ps.map((g) => place(g, 0, 0, 0, 0, ry).translate(x, 0, z));
      };
      const geo = merge(THREE, [...sat(60, 0, 0.3), ...sat(-40, 52, 1.9)]);
      const sats = new THREE.Mesh(geo, new THREE.MeshLambertMaterial({ color: 0xd9dee8, emissive: 0x1e3a8a, emissiveIntensity: 0.5 }));
      sats.position.y = -5.5;
      group.add(sats);
      anim.push((dt) => { sats.rotation.y += dt * 0.05; });
    }

    // ------------------------------------------------ arena hull below the pitch
    const hullMat = new THREE.MeshLambertMaterial({ color: 0x1b2542, emissive: 0x0b1024, emissiveIntensity: 0.8 });
    {
      const shape = roundedRectShape(THREE, HW + 2.2, HL + 2.2, corner + 2.2);
      const g = new THREE.ExtrudeGeometry(shape, { depth: 2.2, bevelEnabled: true, bevelThickness: 0.9, bevelSize: 1.2, bevelSegments: 3, curveSegments: 10 });
      g.rotateX(Math.PI / 2);
      g.translate(0, -0.7 - 0.9, 0);
      // plus a keel: a slimmer deck below with a central spine (one mesh with the hull)
      const hull = new THREE.Mesh(merge(THREE, [
        g,
        place(new THREE.BoxGeometry(HW * 1.4, 1.6, HL * 1.9), 0, -5.4, 0),
        place(new THREE.CylinderGeometry(1.6, 1.6, HL * 2.3, 12), 0, -6.6, 0, Math.PI / 2),
        place(new THREE.CylinderGeometry(1.2, 1.2, HW * 2.6, 12), 0, -6.6, 0, 0, 0, Math.PI / 2),
      ]), hullMat);
      group.add(hull);
    }
    const glowTex = glowTexture(THREE);
    const neon = [], glows = [];          // merged later: pulsing neon parts, additive glow quads

    // ------------------------------------------------ outrigger arms + thruster pods
    const podSpots = [
      [HW + 9.5, -1.5, -12, 0], [HW + 9.5, -1.5, 12, 0], [-HW - 9.5, -1.5, -12, 0], [-HW - 9.5, -1.5, 12, 0],
      [9, -1.5, HL + 13, 1], [-9, -1.5, HL + 13, 1], [9, -1.5, -HL - 13, 1], [-9, -1.5, -HL - 13, 1],
    ];
    {
      const arms = [], flames = [];
      for (const [x, y, z, axis] of podSpots) {
        // arm from the hull edge to the pod
        if (axis === 0) arms.push(place(new THREE.BoxGeometry(9, 1.0, 2.6), Math.sign(x) * (HW + 5.5), y, z));
        else arms.push(place(new THREE.BoxGeometry(2.6, 1.0, 12), x, y, Math.sign(z) * (HL + 6.5)));
        arms.push(place(new THREE.CylinderGeometry(1.5, 1.7, 3.0, 14), x, y, z));
        arms.push(place(new THREE.CylinderGeometry(0.09, 0.09, 1.8, 6), x, y + 2.3, z));
        neon.push(place(new THREE.TorusGeometry(1.62, 0.13, 6, 24), x, y + 0.2, z, Math.PI / 2));
        neon.push(place(new THREE.CylinderGeometry(1.1, 1.1, 0.16, 14), x, y + 1.55, z));
        neon.push(place(new THREE.SphereGeometry(0.3, 10, 8), x, y + 3.3, z));
        flames.push(place(new THREE.ConeGeometry(1.1, 5.0, 12, 1, true), x, y - 4.0, z, Math.PI));
      }
      const armMesh = new THREE.Mesh(merge(THREE, arms), new THREE.MeshLambertMaterial({ color: 0x4b5b8c, emissive: 0x141c3c, emissiveIntensity: 0.9 }));
      armMesh.castShadow = true;
      group.add(armMesh);
      const flameMat = new THREE.MeshBasicMaterial({ color: 0x60c8ff, transparent: true, opacity: 0.55, depthWrite: false, blending: THREE.AdditiveBlending, side: THREE.DoubleSide, fog: false });
      group.add(new THREE.Mesh(merge(THREE, flames), flameMat));
      anim.push((dt, t) => { flameMat.opacity = 0.45 + 0.2 * Math.sin(t * 9.1) * Math.sin(t * 3.7) + 0.1 * Math.sin(t * 17); });
      // exhaust glow discs under the pods (billboards are not needed from above)
      for (const [x, y, z] of podSpots) glows.push(place(new THREE.PlaneGeometry(6.5, 6.5), x, y - 1.7, z, -Math.PI / 2));
    }

    // ------------------------------------------------ neon edge strips (pulsing)
    {
      const strips = new THREE.Mesh(merge(THREE, [
        tint(THREE, ctx.ringGeometry(HW + 0.55, HL + 0.55, corner + 0.55, HW + 0.85, HL + 0.85, corner + 0.85, 0.08).translate(0, 0.001, 0), 0x22d3ee),
        tint(THREE, ctx.ringGeometry(HW + 1.85, HL + 1.85, corner + 1.85, HW + 2.2, HL + 2.2, corner + 2.2, 0.08).translate(0, 0.001, 0), 0xe879f9),
        tint(THREE, ctx.ringGeometry(HW + 3.35, HL + 3.35, corner + 3.35, HW + 3.65, HL + 3.65, corner + 3.65, 0.3).translate(0, -2.15, 0), 0x38bdf8),
      ]), new THREE.MeshBasicMaterial({ color: 0xffffff, vertexColors: true, fog: false }));
      group.add(strips);
      // translucent energy barrier rising just outside the wall
      const barrier = new THREE.Mesh(ctx.ringGeometry(HW + 0.5, HL + 0.5, corner + 0.5, HW + 0.58, HL + 0.58, corner + 0.58, 1.9),
        new THREE.MeshBasicMaterial({ color: 0x67e8f9, transparent: true, opacity: 0.14, depthWrite: false, blending: THREE.AdditiveBlending, side: THREE.DoubleSide, fog: false }));
      barrier.position.y = 0.05;
      group.add(barrier);
      anim.push((dt, t) => {
        const p = 0.5 + 0.5 * Math.sin(t * 2.1);
        strips.material.color.setScalar(0.75 + 0.35 * p);
        barrier.material.opacity = 0.11 + 0.06 * p + 0.03 * Math.sin(t * 9);
      });
    }

    // ------------------------------------------------ 72 light studs running around the slab
    {
      const pts = roundedRectPoints(HW + 1.4, HL + 1.4, corner + 1.4, 72);
      const studs = new THREE.InstancedMesh(new THREE.SphereGeometry(0.2, 8, 6), new THREE.MeshBasicMaterial({ color: 0xffffff, fog: false }), pts.length);
      const dummy = new THREE.Object3D();
      pts.forEach(([x, z], i) => { dummy.position.set(x, 0.12, z); dummy.updateMatrix(); studs.setMatrixAt(i, dummy.matrix); });
      const col = new THREE.Color();
      for (let i = 0; i < pts.length; i++) studs.setColorAt(i, col.set(0x7df9ff));
      group.add(studs);
      anim.push((dt, t) => {
        for (let i = 0; i < pts.length; i++) {
          const w = 0.5 + 0.5 * Math.sin(t * 3 - i * 0.35);
          col.setHSL(0.5 + 0.35 * w, 1, 0.3 + 0.55 * w);
          studs.setColorAt(i, col);
        }
        studs.instanceColor.needsUpdate = true;
      });
    }

    // ------------------------------------------------ floodlight masts around the pitch
    {
      const spots = [[HW + 4.2, -22], [HW + 4.2, 0], [HW + 4.2, 22], [-HW - 4.2, -22], [-HW - 4.2, 0], [-HW - 4.2, 22]];
      const poles = [];
      for (const [x, z] of spots) {
        const inward = x > 0 ? Math.PI / 2 : -Math.PI / 2;
        poles.push(place(new THREE.CylinderGeometry(0.14, 0.22, 8.5, 7), x, 4.25, z));
        poles.push(place(new THREE.BoxGeometry(2.4, 0.5, 0.7), x - Math.sign(x) * 0.6, 8.6, z, 0, 0, -Math.sign(x) * 0.35));
        neon.push(place(new THREE.BoxGeometry(2.1, 0.12, 0.5), x - Math.sign(x) * 0.6, 8.3, z, 0, 0, -Math.sign(x) * 0.35));
        glows.push(place(new THREE.PlaneGeometry(6, 6), x - Math.sign(x) * 1.2, 8.4, z, 0, inward));
        glows.push(place(new THREE.PlaneGeometry(6, 6), x - Math.sign(x) * 1.2, 8.4, z, 0, 0));
      }
      group.add(new THREE.Mesh(merge(THREE, poles), new THREE.MeshLambertMaterial({ color: 0x64748b, emissive: 0x1e2a4a, emissiveIntensity: 0.9 })));
    }

    // ------------------------------------------------ merged neon parts + additive glows
    {
      const neonMat = new THREE.MeshBasicMaterial({ color: 0x7df9ff, fog: false });
      group.add(new THREE.Mesh(merge(THREE, neon), neonMat));
      const glowMat = new THREE.MeshBasicMaterial({ map: glowTex, color: 0x7dd3fc, transparent: true, opacity: 0.8, depthWrite: false, blending: THREE.AdditiveBlending, side: THREE.DoubleSide, fog: false });
      group.add(new THREE.Mesh(merge(THREE, glows), glowMat));
      anim.push((dt, t) => {
        neonMat.color.setHSL(0.5 + 0.08 * Math.sin(t * 1.3), 1, 0.62 + 0.14 * Math.sin(t * 4));
        glowMat.opacity = 0.65 + 0.2 * Math.sin(t * 6.3);
      });
    }

    // ------------------------------------------------ holographic boards, bobbing
    {
      const tex = holoTexture(THREE, rand);
      const boards = [];
      for (const [x, z] of [[HW + 6.5, -11], [HW + 6.5, 11], [-HW - 6.5, -11], [-HW - 6.5, 11]]) {
        boards.push(place(new THREE.PlaneGeometry(7, 3.5), x, 4.2, z, 0, x > 0 ? -Math.PI / 2 : Math.PI / 2));
      }
      const holo = new THREE.Mesh(merge(THREE, boards), new THREE.MeshBasicMaterial({ map: tex, transparent: true, side: THREE.DoubleSide, depthWrite: false, fog: false }));
      group.add(holo);
      anim.push((dt, t) => { holo.position.y = 0.25 * Math.sin(t * 0.9); holo.material.opacity = 0.85 + 0.12 * Math.sin(t * 11); });
    }

    // ------------------------------------------------ glowing halo rings around the arena
    {
      const dash = dashTexture(THREE);
      dash.repeat.set(28, 1);
      const r1 = new THREE.Mesh(new THREE.TorusGeometry(46, 0.32, 5, 120), new THREE.MeshBasicMaterial({ map: dash, color: 0x7df9ff, transparent: true, blending: THREE.AdditiveBlending, depthWrite: false, fog: false }));
      r1.rotation.x = Math.PI / 2; r1.position.y = -10;
      const dash2 = dashTexture(THREE);
      dash2.repeat.set(10, 1);
      const r2 = new THREE.Mesh(new THREE.TorusGeometry(53, 0.2, 5, 120), new THREE.MeshBasicMaterial({ map: dash2, color: 0xf0abfc, transparent: true, blending: THREE.AdditiveBlending, depthWrite: false, fog: false }));
      r2.rotation.x = Math.PI / 2; r2.position.y = -14;
      group.add(r1, r2);
      anim.push((dt) => { r1.rotation.z += dt * 0.12; r2.rotation.z -= dt * 0.07; });
    }

    // ------------------------------------------------ a slow comet crossing the low sky
    {
      const tail = place(new THREE.PlaneGeometry(46, 6), 23, 0, 0);
      const uv = tail.attributes.uv;
      const head = new THREE.CircleGeometry(2.6, 16);
      const comet = new THREE.Mesh(merge(THREE, [tail, head]), new THREE.MeshBasicMaterial({
        map: (() => { const [c, g] = canvas(256, 32); g.clearRect(0, 0, 256, 32); const lg = g.createLinearGradient(0, 0, 256, 0); lg.addColorStop(0, 'rgba(255,255,255,0.9)'); lg.addColorStop(0.15, 'rgba(180,230,255,0.5)'); lg.addColorStop(1, 'rgba(120,180,255,0)'); g.fillStyle = lg; g.fillRect(0, 0, 256, 32); const vg = g.createLinearGradient(0, 0, 0, 32); vg.addColorStop(0, 'rgba(0,0,0,1)'); vg.addColorStop(0.5, 'rgba(0,0,0,0)'); vg.addColorStop(1, 'rgba(0,0,0,1)'); g.globalCompositeOperation = 'destination-out'; g.fillStyle = vg; g.fillRect(0, 0, 256, 32); return new THREE.CanvasTexture(c); })(),
        transparent: true, depthWrite: false, blending: THREE.AdditiveBlending, side: THREE.DoubleSide, fog: false,
      }));
      void uv;
      group.add(comet);
      const R = 330, y0 = -30;
      anim.push((dt, t) => {
        const a = (t * 0.045) % TAU;                       // one lap every ~140 s
        comet.position.set(Math.cos(a) * R, y0 + 40 * Math.sin(a * 2), Math.sin(a) * R);
        comet.lookAt(0, comet.position.y - 20, 0);
        comet.rotateY(Math.PI / 2 + 0.25);                   // tail trails behind the motion
      });
    }

    return {
      update(dt, time) {
        for (const f of anim) f(dt, time);
      },
    };
  },
};
