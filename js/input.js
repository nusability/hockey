import { clamp } from './math.js';

const TAP_MS = 220;
const TAP_PX = 14;
const MAX_FINGERS = 2;

/**
 * Pointer handling. Each finger grabs the nearest free skater of the user's
 * team and drags it relative to the finger's movement. A tap passes the puck
 * to the team-mate nearest the tap (or shoots when tapping at the goal).
 * Releasing a finger with a quick flick fires the puck in the flick direction.
 */
export class Input {
  constructor(canvas, renderer, getMatch) {
    this.canvas = canvas;
    this.renderer = renderer;
    this.getMatch = getMatch;
    this.pointers = new Map();
    this.enabled = true;

    canvas.style.touchAction = 'none';
    canvas.addEventListener('pointerdown', (e) => this.down(e));
    canvas.addEventListener('pointermove', (e) => this.move(e));
    canvas.addEventListener('pointerup', (e) => this.up(e));
    canvas.addEventListener('pointercancel', (e) => this.up(e));
    canvas.addEventListener('contextmenu', (e) => e.preventDefault());
  }

  releaseAll() {
    const match = this.getMatch();
    for (const s of this.pointers.values()) {
      if (s.player && match) { s.player.controlled = null; s.player.target = null; }
    }
    this.pointers.clear();
  }

  down(e) {
    if (!this.enabled) return;
    const match = this.getMatch();
    if (!match || match.ended) return;
    if (this.pointers.size >= MAX_FINGERS) return;
    e.preventDefault();
    this.canvas.setPointerCapture?.(e.pointerId);
    const w = this.renderer.screenToWorld(e.clientX, e.clientY);
    if (!w) return;
    const player = match.pickPlayer(w.x, w.z);
    const s = {
      id: e.pointerId, player, t0: performance.now(), x0: e.clientX, y0: e.clientY,
      lastX: e.clientX, lastY: e.clientY, world: w,
      samples: [{ t: performance.now(), x: e.clientX, y: e.clientY }], moved: false,
    };
    if (player) {
      player.controlled = e.pointerId;
      player.target = { x: player.x, z: player.z };
    }
    this.pointers.set(e.pointerId, s);
  }

  move(e) {
    const s = this.pointers.get(e.pointerId);
    if (!s) return;
    e.preventDefault();
    const match = this.getMatch();
    if (!match) return;
    const w = this.renderer.screenToWorld(e.clientX, e.clientY);
    if (!w) return;
    const dxPx = e.clientX - s.x0, dyPx = e.clientY - s.y0;
    if (Math.hypot(dxPx, dyPx) > TAP_PX) s.moved = true;
    // world-space delta of this finger movement, evaluated with the *current*
    // camera so that camera panning never moves the dragged player
    const prev = this.renderer.screenToWorld(s.lastX, s.lastY) || w;
    const dx = w.x - prev.x, dz = w.z - prev.z;
    s.world = w;
    s.lastX = e.clientX; s.lastY = e.clientY;
    const now = performance.now();
    s.samples.push({ t: now, x: e.clientX, y: e.clientY });
    while (s.samples.length > 10) s.samples.shift();
    const p = s.player;
    if (p && p.controlled === e.pointerId && match.state === 'play') {
      if (!p.target) p.target = { x: p.x, z: p.z };
      // relative drag: move the target by the finger's world-space delta, but
      // never let it run away from the player (keeps control responsive)
      p.target.x += dx; p.target.z += dz;
      const ox = p.target.x - p.x, oz = p.target.z - p.z;
      const od = Math.hypot(ox, oz);
      const maxLead = 2.2;
      if (od > maxLead) { p.target.x = p.x + (ox / od) * maxLead; p.target.z = p.z + (oz / od) * maxLead; }
    }
  }

  up(e) {
    const s = this.pointers.get(e.pointerId);
    if (!s) return;
    e.preventDefault();
    this.pointers.delete(e.pointerId);
    const match = this.getMatch();
    const now = performance.now();
    const p = s.player;
    if (p) { p.controlled = null; p.target = null; }
    if (!match || match.state !== 'play') return;

    const isTap = !s.moved && now - s.t0 < TAP_MS;
    if (isTap) {
      match.userTap(s.world.x, s.world.z);
      return;
    }
    // flick: velocity over the last ~120 ms (or the last two samples) in world units
    if (p && match.puck.carrier === p && s.samples.length >= 2) {
      const last = s.samples[s.samples.length - 1];
      let first = s.samples[s.samples.length - 2];
      for (const smp of s.samples) { if (last.t - smp.t <= 120) { first = smp; break; } }
      if (first === last) first = s.samples[s.samples.length - 2];
      const dt = (last.t - first.t) / 1000;
      // convert both screen samples with the current camera so panning can't fake a flick
      const wa = this.renderer.screenToWorld(first.x, first.y), wb = this.renderer.screenToWorld(last.x, last.y);
      if (dt > 0.005 && wa && wb) {
        const vx = (wb.x - wa.x) / dt, vz = (wb.z - wa.z) / dt;
        const sp = Math.hypot(vx, vz);
        if (sp > 9) match.userFlick(p, vx, vz, clamp(sp * 0.75, 13, 27));
      }
    }
  }
}
