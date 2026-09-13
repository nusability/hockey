/**
 * Synthesised sound effects. No assets, no music: every sound is a short
 * one-shot built from oscillators and noise bursts.
 *
 * Mobile browsers start an AudioContext suspended and only let it start from
 * inside a user gesture, so `unlock()` both creates and resumes it, and plays
 * a silent buffer, which is what actually wakes audio up on iOS.
 */
export class Sfx {
  constructor() {
    this.ctx = null;
    this.master = null;
    this.enabled = true;
    this.volume = 0.9;
  }

  unlock() {
    try {
      if (!this.ctx) {
        const AC = window.AudioContext || window.webkitAudioContext;
        if (!AC) return;
        this.ctx = new AC();
        this.master = this.ctx.createGain();
        this.master.gain.value = this.volume;
        this.master.connect(this.ctx.destination);
        // silent buffer: the handshake iOS actually needs
        const b = this.ctx.createBuffer(1, 1, 22050);
        const src = this.ctx.createBufferSource();
        src.buffer = b;
        src.connect(this.master);
        src.start(0);
      }
      if (this.ctx.state !== 'running') this.ctx.resume();
    } catch (e) { this.ctx = null; }
  }

  get ready() { return !!this.ctx && this.enabled && this.ctx.state === 'running'; }
  get now() { return this.ctx.currentTime; }

  /** One oscillator with an attack/decay envelope. */
  tone({ freq = 440, type = 'sine', dur = 0.1, gain = 0.2, slide = 0, delay = 0, attack = 0.006 }) {
    if (!this.ready) return;
    const c = this.ctx, t = c.currentTime + delay;
    const o = c.createOscillator(), g = c.createGain();
    o.type = type;
    o.frequency.setValueAtTime(freq, t);
    if (slide) o.frequency.exponentialRampToValueAtTime(Math.max(20, freq + slide), t + dur);
    g.gain.setValueAtTime(0.0001, t);
    g.gain.exponentialRampToValueAtTime(Math.max(0.0002, gain), t + attack);
    g.gain.exponentialRampToValueAtTime(0.0001, t + dur);
    o.connect(g).connect(this.master);
    o.start(t); o.stop(t + dur + 0.03);
  }

  /** A filtered noise burst: impacts, crowd, scrapes. */
  noise({ dur = 0.08, gain = 0.15, delay = 0, type = 'highpass', freq = 1200, q = 0.7, sweep = 0 }) {
    if (!this.ready) return;
    const c = this.ctx, t = c.currentTime + delay;
    const len = Math.max(1, Math.ceil(c.sampleRate * dur));
    const buf = c.createBuffer(1, len, c.sampleRate);
    const d = buf.getChannelData(0);
    for (let i = 0; i < len; i++) d[i] = (Math.random() * 2 - 1) * (1 - i / len);
    const src = c.createBufferSource(); src.buffer = buf;
    const f = c.createBiquadFilter(); f.type = type; f.frequency.setValueAtTime(freq, t); f.Q.value = q;
    if (sweep) f.frequency.exponentialRampToValueAtTime(Math.max(40, freq + sweep), t + dur);
    const g = c.createGain();
    g.gain.setValueAtTime(gain, t);
    g.gain.exponentialRampToValueAtTime(0.0001, t + dur);
    src.connect(f).connect(g).connect(this.master);
    src.start(t);
  }

  // ---------------------------------------------------------------- the kit
  /** Stick on ball. Harder shots crack louder and brighter. */
  shot(speed = 24) {
    const k = Math.min(1, Math.max(0, (speed - 12) / 18));
    this.noise({ dur: 0.05, gain: 0.22 + k * 0.2, type: 'bandpass', freq: 1700 + k * 1400, q: 1.1 });
    this.tone({ freq: 240 + k * 90, type: 'triangle', dur: 0.09, gain: 0.26 + k * 0.12, slide: -170 });
  }

  /** A pass: softer, drier, no crack. */
  pass() {
    this.noise({ dur: 0.035, gain: 0.13, type: 'bandpass', freq: 1150, q: 1.4 });
    this.tone({ freq: 190, type: 'triangle', dur: 0.05, gain: 0.1, slide: -60 });
  }

  /** Collecting the ball. */
  receive() {
    this.tone({ freq: 420, type: 'sine', dur: 0.05, gain: 0.09, slide: 120 });
  }

  /** Ball into the boards or a dummy. */
  board() {
    this.tone({ freq: 110, type: 'triangle', dur: 0.13, gain: 0.2, slide: -55 });
    this.noise({ dur: 0.05, gain: 0.1, type: 'lowpass', freq: 900 });
  }

  /** Ringing off the post. */
  post() {
    this.tone({ freq: 1620, type: 'sine', dur: 0.5, gain: 0.2, slide: -140 });
    this.tone({ freq: 2430, type: 'sine', dur: 0.3, gain: 0.08, slide: -200, delay: 0.005 });
  }

  /** Keeper save: a padded thud. */
  save() {
    this.tone({ freq: 150, type: 'sine', dur: 0.14, gain: 0.22, slide: -70 });
    this.noise({ dur: 0.09, gain: 0.14, type: 'lowpass', freq: 620 });
  }

  /** Losing the ball to a tackle. */
  steal() {
    this.noise({ dur: 0.11, gain: 0.16, type: 'bandpass', freq: 900, q: 0.8, sweep: 900 });
    this.tone({ freq: 300, type: 'square', dur: 0.07, gain: 0.07, slide: 170 });
  }

  whistle() {
    this.tone({ freq: 2350, type: 'square', dur: 0.34, gain: 0.075 });
    this.tone({ freq: 2385, type: 'square', dur: 0.34, gain: 0.05, delay: 0.015 });
    this.noise({ dur: 0.34, gain: 0.03, type: 'bandpass', freq: 2400, q: 6 });
  }

  /** Ball dropped / drill starts. */
  drop() {
    this.tone({ freq: 560, type: 'sine', dur: 0.08, gain: 0.14, slide: -220 });
  }

  /** Goal: air horn plus a crowd swell. No melody, no music. */
  goal() {
    for (let i = 0; i < 3; i++) {
      const f = i === 1 ? 294 : 196;
      this.tone({ freq: f, type: 'sawtooth', dur: 0.45, gain: 0.16, delay: i * 0.5 });
      this.tone({ freq: f * 1.5, type: 'sawtooth', dur: 0.45, gain: 0.07, delay: i * 0.5 });
    }
    this.crowd(1.6, 0.2);
  }

  /** Conceding: a duller, lower horn. */
  goalAgainst() {
    this.tone({ freq: 150, type: 'sawtooth', dur: 0.7, gain: 0.13, slide: -40 });
    this.tone({ freq: 112, type: 'sawtooth', dur: 0.8, gain: 0.1, slide: -30, delay: 0.06 });
  }

  /** A swell of filtered noise that reads as a crowd. */
  crowd(dur = 1.4, gain = 0.16) {
    if (!this.ready) return;
    const c = this.ctx, t = c.currentTime;
    const len = Math.ceil(c.sampleRate * dur);
    const buf = c.createBuffer(1, len, c.sampleRate);
    const d = buf.getChannelData(0);
    for (let i = 0; i < len; i++) {
      const p = i / len;
      const env = Math.min(1, p * 6) * (1 - p) ** 1.4;      // fast swell, slow fall
      d[i] = (Math.random() * 2 - 1) * env;
    }
    const src = c.createBufferSource(); src.buffer = buf;
    const f = c.createBiquadFilter(); f.type = 'bandpass'; f.frequency.value = 900; f.Q.value = 0.5;
    const g = c.createGain(); g.gain.value = gain;
    src.connect(f).connect(g).connect(this.master);
    src.start(t);
  }

  /** Short rising fanfare when a drill is completed. */
  success() {
    [523, 659, 784, 1047].forEach((f, i) =>
      this.tone({ freq: f, type: 'triangle', dur: 0.16, gain: 0.14, delay: i * 0.085 }));
  }

  /** Short falling figure when a drill runs out of time. */
  fail() {
    [440, 370, 294].forEach((f, i) =>
      this.tone({ freq: f, type: 'triangle', dur: 0.2, gain: 0.12, delay: i * 0.11 }));
  }

  /** Menu / button feedback. */
  click() {
    this.tone({ freq: 900, type: 'sine', dur: 0.035, gain: 0.07 });
  }

  /** The last seconds of a period. */
  tick() {
    this.tone({ freq: 1250, type: 'square', dur: 0.035, gain: 0.06 });
  }
}
