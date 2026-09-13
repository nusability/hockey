export const clamp = (v, a, b) => (v < a ? a : v > b ? b : v);
export const lerp = (a, b, t) => a + (b - a) * t;
export const len = (x, z) => Math.hypot(x, z);
export const dist = (a, b) => Math.hypot(a.x - b.x, a.z - b.z);
export const rand = (a = 0, b = 1) => a + Math.random() * (b - a);
export const randInt = (a, b) => Math.floor(rand(a, b + 1));
export const pick = (arr) => arr[Math.floor(Math.random() * arr.length)];

export function norm(x, z) {
  const l = Math.hypot(x, z);
  return l > 1e-6 ? { x: x / l, z: z / l } : { x: 0, z: 0 };
}

// Signed distance from (x,z) to the edge of an axis aligned rounded
// rectangle with half extents hw/hl and corner radius rr. Negative inside.
export function sdRoundRect(x, z, hw, hl, rr) {
  const qx = Math.abs(x) - (hw - rr);
  const qz = Math.abs(z) - (hl - rr);
  const ox = Math.max(qx, 0);
  const oz = Math.max(qz, 0);
  return Math.hypot(ox, oz) + Math.min(Math.max(qx, qz), 0) - rr;
}

// Outward normal of the rounded rectangle at (x,z).
export function roundRectNormal(x, z, hw, hl, rr) {
  const e = 0.01;
  const nx = sdRoundRect(x + e, z, hw, hl, rr) - sdRoundRect(x - e, z, hw, hl, rr);
  const nz = sdRoundRect(x, z + e, hw, hl, rr) - sdRoundRect(x, z - e, hw, hl, rr);
  return norm(nx, nz);
}

// Distance from point p to the segment a-b.
export function pointSegDist(p, a, b) {
  const abx = b.x - a.x, abz = b.z - a.z;
  const l2 = abx * abx + abz * abz;
  let t = l2 > 0 ? ((p.x - a.x) * abx + (p.z - a.z) * abz) / l2 : 0;
  t = clamp(t, 0, 1);
  return Math.hypot(p.x - (a.x + abx * t), p.z - (a.z + abz * t));
}

// Gaussian-ish noise from three uniforms.
export const noise = (s = 1) => (Math.random() + Math.random() + Math.random() - 1.5) * s;

export function fmtClock(sec) {
  sec = Math.max(0, Math.ceil(sec));
  const m = Math.floor(sec / 60);
  const s = sec % 60;
  return `${m}:${s < 10 ? '0' : ''}${s}`;
}
