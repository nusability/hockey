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

/**
 * What separates a flick from a lift (`?control=flick`).
 *
 * The finger has four things to offer — direction, distance, timing, and how it leaves the
 * screen. Steering already spends direction and distance, so the shot is bought with the last
 * one: leave the screen fast and it is a shot along the flick; just let go and it is a pass to
 * whoever is marked. Measured over a short window rather than the last event, because a single
 * pointer sample is noise.
 */
export const FLICK = {
  /** px/s over `window` that counts as a flick rather than a lift */
  speed: 900,
  /** how far back to measure it */
  window: 0.08,
  /** history kept, a little longer than the window so there is always something in it */
  keep: 0.2,
};

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
    /** recent samples of the steering pointer, for telling a flick from a lift */
    this.hist = [];
    /** the last steering vector taken while the finger was not flicking (see `steer`) */
    this.slow = { dx: 0, dy: 0 };
    /** the last flick, in screen axes, for the overlay to replay (see releaseGesture) */
    this.lastFlick = null;

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
      this.hist.length = 0;
      this.slow = { dx: 0, dy: 0 };
      this.sample();
    }
    this.onHoldChange?.(true);
  }

  move(e) {
    if (e.pointerId !== this.steerId) return;
    this.curX = e.clientX;
    this.curY = e.clientY;
    this.sample();
    // Remember the heading from before the finger started moving flick-fast. A flick is a real
    // movement of the finger, so without this the shot gesture would also be a hard swerve —
    // the player would lurch sideways in the last 80 ms before the ball left them.
    if (this.fingerSpeed() < FLICK.speed) {
      this.slow = { dx: this.curX - this.originX, dy: this.curY - this.originY };
    }
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

  sample() {
    const now = performance.now() / 1000;
    this.hist.push({ t: now, x: this.curX, y: this.curY });
    while (this.hist.length > 1 && now - this.hist[0].t > FLICK.keep) this.hist.shift();
  }

  /** How fast the finger is travelling right now, in px/s, over the flick window. */
  fingerSpeed() {
    const g = this.gesture();
    return g ? g.speed : 0;
  }

  /**
   * The finger's movement over the last `FLICK.window`, as speed and direction, or null when
   * there is not enough history to say. Both the live steering freeze and the release decision
   * read this, so a flick is judged the same way whether it is being watched or acted on.
   */
  gesture() {
    const n = this.hist.length;
    if (n < 2) return null;
    const last = this.hist[n - 1];
    let first = this.hist[0];
    for (let i = n - 1; i >= 0; i--) {
      first = this.hist[i];
      if (last.t - this.hist[i].t >= FLICK.window) break;
    }
    const dt = last.t - first.t;
    if (dt < 1e-3) return null;
    const dx = last.x - first.x, dy = last.y - first.y;
    const d = Math.hypot(dx, dy);
    return { speed: d / dt, dx, dy, dist: d };
  }

  /**
   * What the lift meant. `flick` carries a direction in world axes (same mapping as `steer`);
   * a plain lift carries none, and the game passes to whoever is marked.
   */
  releaseGesture() {
    // A finger that has come to rest stops producing pointermove events, so the history can
    // still hold a fast movement from a moment ago. Without this, sweeping the player across
    // the pitch, pausing, and then calmly letting go would fire a shot.
    const last = this.hist[this.hist.length - 1];
    if (!last || performance.now() / 1000 - last.t > FLICK.window * 1.5) return { flick: false };
    const g = this.gesture();
    if (!g || g.speed < FLICK.speed || g.dist < 1e-3) return { flick: false };
    vibrate([10, 18, 14]);
    // Kept in *screen* axes as well, and with the ring's centre, so the overlay can show the
    // angle that was actually flicked once the finger has gone. A thumb cannot judge its own
    // angle to the precision a goal mouth wants, so the answer has to arrive after the fact.
    this.lastFlick = {
      dx: g.dx, dy: g.dy,
      cx: this.originX, cy: this.originY,
      at: performance.now() / 1000,
    };
    return { flick: true, x: -g.dx / g.dist, z: -g.dy / g.dist, speed: g.speed };
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
    // While the finger is flicking, steer on the heading from just before it started: the shot
    // gesture must not double as a swerve.
    const flicking = this.fingerSpeed() >= FLICK.speed;
    const dx = flicking ? this.slow.dx : this.curX - this.originX;
    const dy = flicking ? this.slow.dy : this.curY - this.originY;
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
    let gesture = { flick: false };
    if (e.pointerId === this.steerId) {
      // hand the steering pointer on to whichever finger is still down, from
      // neutral — lifting one of two fingers should not fling the player
      gesture = this.releaseGesture();
      this.steerId = this.active.size > 0 ? [...this.active][0] : null;
      this.originX = this.curX; this.originY = this.curY;
      this.zone = 'dead';
      this.hist.length = 0;
      this.slow = { dx: 0, dy: 0 };
    }
    if (this.active.size > 0) return;
    this.onHoldChange?.(false);
    const match = this.getMatch();
    if (match) match.userRelease(gesture);
  }

  clear() {
    this.active.clear();
    this.steerId = null;
    this.zone = 'dead';
    this.hist.length = 0;
    this.slow = { dx: 0, dy: 0 };
    this.onHoldChange?.(false);
  }
}
