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

    canvas.style.touchAction = 'none';
    canvas.addEventListener('pointerdown', (e) => this.down(e));
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
    this.onHoldChange?.(true);
  }

  up(e) {
    if (!this.active.has(e.pointerId)) return;
    this.active.delete(e.pointerId);
    if (this.active.size > 0) return;
    this.onHoldChange?.(false);
    const match = this.getMatch();
    if (match) match.userRelease();
  }

  clear() { this.active.clear(); this.onHoldChange?.(false); }
}
