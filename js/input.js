import { ORBIT } from './config.js';

/**
 * One-touch control. Touching anywhere keeps the puck circling the carrier;
 * lifting the last finger releases it. Nothing needs to be aimed at.
 */
export class Input {
  constructor(canvas, getMatch) {
    this.canvas = canvas;
    this.getMatch = getMatch;
    this.active = new Set();
    this.holding = false;
    this.onHoldChange = null;
    this.primary = null;      // the first finger: its travel sets the power
    this.power = ORBIT.powerDefault;

    canvas.style.touchAction = 'none';
    canvas.addEventListener('pointerdown', (e) => this.down(e));
    window.addEventListener('pointermove', (e) => this.move(e));
    window.addEventListener('pointerup', (e) => this.up(e));
    window.addEventListener('pointercancel', (e) => this.up(e));
    window.addEventListener('blur', () => this.clear());
    canvas.addEventListener('contextmenu', (e) => e.preventDefault());
  }

  get isHolding() { return this.active.size > 0; }

  down(e) {
    const match = this.getMatch();
    if (!match || match.ended) return;
    e.preventDefault();
    this.active.add(e.pointerId);
    if (this.primary == null) { this.primary = { id: e.pointerId, x: e.clientX, y: e.clientY }; this.power = ORBIT.powerDefault; }
    this.onHoldChange?.(true);
  }

  move(e) {
    if (!this.primary || e.pointerId !== this.primary.id) return;
    const d = Math.hypot(e.clientX - this.primary.x, e.clientY - this.primary.y);
    // a still finger keeps the default power; dragging away charges the shot
    const t = Math.min(1, Math.max(0, (d - 12) / ORBIT.dragPixels));
    this.power = d < 12 ? ORBIT.powerDefault : t;
  }

  up(e) {
    if (!this.active.has(e.pointerId)) return;
    this.active.delete(e.pointerId);
    if (this.active.size > 0) return;
    this.onHoldChange?.(false);
    const match = this.getMatch();
    const power = this.power;
    this.primary = null;
    if (match) match.userRelease(power);
    this.power = ORBIT.powerDefault;
  }

  clear() { this.active.clear(); this.primary = null; this.power = ORBIT.powerDefault; this.onHoldChange?.(false); }
}
