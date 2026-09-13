import { RINK } from './config.js';
import { clamp, lerp } from './math.js';

/**
 * Camera director: slows time as a shot is about to cross the line, plays
 * the goal in slow motion from a low camera behind the net that cranes
 * around it, and eases everything back to the play camera. All blends are
 * continuous: the play camera is never cut.
 */
export class Director {
  constructor() {
    this.timeScale = 1;
    this.weight = 0;          // 0 = play camera, 1 = dramatic camera
    this.mode = 'play';       // play | buildup | goal | return
    this.t = 0;               // real seconds in the current mode
    this.pose = { pos: { x: 0, y: 30, z: -20 }, look: { x: 0, y: 0, z: 0 }, fov: 50 };
    this.goal = null;
  }

  /** A goal was scored: e.goalZ is the line the puck crossed. */
  onGoal(match, e) {
    const puck = match.puck;
    const gz = e.goalZ;
    const outward = Math.sign(gz);                // +1 far goal, -1 near goal
    // start on the side the puck came from, slightly behind the net
    const side = puck.x >= 0 ? 1 : -1;
    this.goal = { gz, outward, side, x: clamp(puck.x, -1.5, 1.5) };
    this.mode = 'goal';
    this.t = 0;
  }

  update(dt, match) {
    const wasMode = this.mode;
    this.t += dt;
    let targetScale = 1, targetWeight = 0, k = 2.5;

    if (this.mode === 'goal') {
      // slow motion, then ease back to real time over the celebration
      const s = this.t < 1.3 ? 0.18 : this.t < 2.6 ? lerp(0.18, 1, (this.t - 1.3) / 1.3) : 1;
      targetScale = s;
      targetWeight = 1;
      k = 4;
      this.dramaPose(match, this.t);
      if (match.state !== 'goal') { this.mode = 'return'; this.t = 0; }
    } else if (this.mode === 'return') {
      targetScale = 1; targetWeight = 0; k = 1.6;
      if (this.weight < 0.02) this.mode = 'play';
    } else {
      // watch for a shot about to cross the goal line
      const hit = this.incoming(match);
      if (hit) {
        this.mode = 'buildup';
        targetScale = 0.45; targetWeight = 0.35; k = 6;
        this.buildupPose(match, hit);
      } else {
        this.mode = 'play';
        targetScale = 1; targetWeight = 0; k = 5;
      }
    }
    if (wasMode === 'goal' && this.mode === 'return') this.timeScale = Math.max(this.timeScale, 0.6);
    const ks = this.mode === 'goal' ? 8 : 4;
    this.timeScale += (targetScale - this.timeScale) * (1 - Math.exp(-dt * ks));
    this.weight += (targetWeight - this.weight) * (1 - Math.exp(-dt * k));
  }

  /** Puck flying at a goal mouth, crossing within ~0.6 s? */
  incoming(match) {
    const p = match.puck;
    if (match.state !== 'play' || p.carrier) return null;
    const sp = Math.hypot(p.vx, p.vz);
    if (sp < 8) return null;
    for (const gz of [RINK.goalLineZ, -RINK.goalLineZ]) {
      const t = (gz - p.z) / p.vz;
      if (!(t > 0 && t < 0.6)) continue;
      const x = p.x + p.vx * t;
      if (Math.abs(x) < RINK.goalWidth / 2 + 0.8) return { gz, x, t };
    }
    return null;
  }

  buildupPose(match, hit) {
    const outward = Math.sign(hit.gz);
    const p = match.puck;
    // drop lower and closer, looking along the shot towards the net
    this.pose = {
      pos: { x: p.x * 0.6, y: 9, z: hit.gz - outward * 20 },
      look: { x: hit.x * 0.5, y: 0.6, z: hit.gz },
      fov: 42,
    };
  }

  dramaPose(match, t) {
    const g = this.goal;
    const p = match.puck;
    // classic goal cam: low beside the goal line on the side the puck came
    // from, sweeping round behind the net and rising above the glass
    const a = 1.8 - Math.min(t, 4.5) * 0.14;           // ~103deg -> ~67deg from the outward axis
    const r = 14;
    const y = 4.5 + Math.min(t, 4.5) * 1.1;
    this.pose = {
      pos: { x: g.x + g.side * Math.sin(a) * r, y, z: g.gz + g.outward * Math.cos(a) * r },
      look: { x: lerp(p.x, 0, 0.6), y: 0.4, z: g.gz - g.outward * 0.5 },
      fov: 46,
    };
  }

  /** What the renderer blends towards. */
  override() {
    if (this.weight < 0.001) return null;
    return { pos: new Vec(this.pose.pos), look: new Vec(this.pose.look), fov: this.pose.fov, weight: this.weight };
  }
}

// Tiny Vector3-compatible object (has x, y, z; the renderer lerps into THREE vectors)
class Vec { constructor(o) { this.x = o.x; this.y = o.y; this.z = o.z; } }
