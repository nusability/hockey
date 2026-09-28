/**
 * Touch control for the prototype. Two schemes live here, chosen by `?control=`
 * (see match.js) and both driven by the same pointer stream, so they can be
 * played back to back on one build.
 *
 * **One-touch** (`?control=touch`, the default, and what the spec §5 describes):
 * touching anywhere keeps the ball circling the carrier; lifting the last
 * finger releases it. There is nothing to aim and nothing to charge.
 *
 * **Direct player control** (`?control=drag`, SMASH-71): the same touch and the
 * same release, plus the finger now *steers* the player it is holding. The
 * vector from where the finger went down to where it is now is a direction and
 * a speed:
 *
 *   - inside the deadzone the player is not being steered at all and keeps
 *     playing itself (the AI keeps its target);
 *   - past the deadzone the player runs along that vector, at a speed that
 *     ramps with how far the finger has travelled;
 *   - at the far distance it is running flat out, and dragging further does
 *     nothing but hold the heading.
 *
 * Both edges are announced: a tick of haptics on crossing out of the deadzone,
 * a double tick on reaching full speed, and the steering triangle says the same
 * thing visually (render.js) — which is the only cue on iOS, where the web has
 * no haptic API at all. `navigator.vibrate` is Android-only; the calls below are
 * no-ops on an iPhone and the visual has to carry it there.
 *
 * The aim is untouched by any of this. The ball still circles by itself, and
 * the release is still §5.3 — the finger moves the player's legs, never the
 * arrow. That separation is the point: it keeps the release a pure question of
 * timing, which is what the prototype exists to answer.
 */

/** Drag distances in CSS pixels, measured from where the finger went down. */
export const DRAG = {
  /** inside this the player is not steered at all — the AI still has it */
  deadzone: 16,
  /** at this distance and beyond the player runs flat out */
  full: 96,
  /** speed floor the moment the deadzone is crossed, so the step off it is felt */
  minSpeed: 0.35,
};

function vibrate(pattern) {
  try { navigator.vibrate?.(pattern); } catch (e) { /* unsupported, or blocked */ }
}

export class Input {
  constructor(canvas, getMatch) {
    this.canvas = canvas;
    this.getMatch = getMatch;
    this.active = new Set();
    this.onHoldChange = null;

    /** the pointer we steer with: the first one down, until it lifts */
    this.steerId = null;
    this.originX = 0; this.originY = 0;
    this.curX = 0; this.curY = 0;
    /** which edge we last announced, so haptics fire on the crossing only */
    this.zone = 'dead';

    canvas.style.touchAction = 'none';
    canvas.addEventListener('pointerdown', (e) => this.down(e));
    canvas.addEventListener('pointermove', (e) => this.move(e));
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
    if (this.steerId === null) {
      this.steerId = e.pointerId;
      this.originX = this.curX = e.clientX;
      this.originY = this.curY = e.clientY;
      this.zone = 'dead';
    }
    this.onHoldChange?.(true);
  }

  move(e) {
    if (e.pointerId !== this.steerId) return;
    this.curX = e.clientX;
    this.curY = e.clientY;
    const z = this.zoneOf(Math.hypot(this.curX - this.originX, this.curY - this.originY));
    if (z !== this.zone) {
      // only the outward crossings are worth a buzz; sliding back in is silent
      if (z === 'steer' && this.zone === 'dead') vibrate(12);
      else if (z === 'full') vibrate([8, 26, 8]);
      this.zone = z;
    }
  }

  zoneOf(d) {
    if (d < DRAG.deadzone) return 'dead';
    return d >= DRAG.full ? 'full' : 'steer';
  }

  /**
   * Move the origin to where the finger is now, so a held finger starts the
   * next player from neutral. Called whenever control hands over (match.js) —
   * the player never has to lift.
   */
  recentre() {
    this.originX = this.curX;
    this.originY = this.curY;
    this.zone = 'dead';
  }

  /**
   * The current steering order, or null when nothing is being steered.
   *
   * The camera looks straight down +Z and never yaws (render.js
   * `cameraPosition`), so screen up is world +z — and screen right is world
   * **−x**, not +x. Looking along +Z with up +Y mirrors the x axis: a player
   * standing at x = +10 is drawn on the *left* of the screen. (Checked by
   * projecting through the game's own camera, not reasoned about — reasoning
   * about it is what got the sign wrong the first time and made dragging right
   * run the player left.)
   *
   * This stays this simple only while the camera has no yaw; a rotating camera
   * would have to rotate this vector by the camera's heading instead.
   */
  get steer() {
    if (this.steerId === null) return null;
    const dx = this.curX - this.originX;
    const dy = this.curY - this.originY;
    const d = Math.hypot(dx, dy);
    if (d < DRAG.deadzone) return null;
    const span = Math.max(1e-3, DRAG.full - DRAG.deadzone);
    const t = Math.min(1, (d - DRAG.deadzone) / span);
    return {
      x: -dx / d,
      z: -dy / d,
      speed: DRAG.minSpeed + (1 - DRAG.minSpeed) * t,
      atFull: d >= DRAG.full,
    };
  }

  up(e) {
    if (!this.active.has(e.pointerId)) return;
    this.active.delete(e.pointerId);
    if (e.pointerId === this.steerId) {
      // hand the steering pointer on to whichever finger is still down, from
      // neutral — lifting one of two fingers should not fling the player
      this.steerId = this.active.size > 0 ? [...this.active][0] : null;
      this.originX = this.curX; this.originY = this.curY;
      this.zone = 'dead';
    }
    if (this.active.size > 0) return;
    this.onHoldChange?.(false);
    const match = this.getMatch();
    if (match) match.userRelease();
  }

  clear() {
    this.active.clear();
    this.steerId = null;
    this.zone = 'dead';
    this.onHoldChange?.(false);
  }
}
