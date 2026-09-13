// Tiny synthesised sound effects (no assets needed). Unlocked on first touch.
export class Sfx {
  constructor() { this.ctx = null; this.enabled = true; }

  unlock() {
    if (this.ctx) { if (this.ctx.state === 'suspended') this.ctx.resume(); return; }
    try { this.ctx = new (window.AudioContext || window.webkitAudioContext)(); } catch (e) { this.ctx = null; }
  }

  tone({ freq = 440, type = 'sine', dur = 0.1, gain = 0.2, slide = 0, delay = 0 }) {
    if (!this.ctx || !this.enabled) return;
    const c = this.ctx, t = c.currentTime + delay;
    const o = c.createOscillator(), g = c.createGain();
    o.type = type; o.frequency.setValueAtTime(freq, t);
    if (slide) o.frequency.exponentialRampToValueAtTime(Math.max(30, freq + slide), t + dur);
    g.gain.setValueAtTime(0.0001, t);
    g.gain.exponentialRampToValueAtTime(gain, t + 0.01);
    g.gain.exponentialRampToValueAtTime(0.0001, t + dur);
    o.connect(g).connect(c.destination);
    o.start(t); o.stop(t + dur + 0.02);
  }

  noise({ dur = 0.08, gain = 0.15, delay = 0 }) {
    if (!this.ctx || !this.enabled) return;
    const c = this.ctx, t = c.currentTime + delay;
    const buf = c.createBuffer(1, Math.ceil(c.sampleRate * dur), c.sampleRate);
    const d = buf.getChannelData(0);
    for (let i = 0; i < d.length; i++) d[i] = (Math.random() * 2 - 1) * (1 - i / d.length);
    const src = c.createBufferSource(); src.buffer = buf;
    const g = c.createGain(); g.gain.value = gain;
    const f = c.createBiquadFilter(); f.type = 'highpass'; f.frequency.value = 1200;
    src.connect(f).connect(g).connect(c.destination);
    src.start(t);
  }

  whistle() { this.tone({ freq: 2400, type: 'square', dur: 0.35, gain: 0.08 }); this.tone({ freq: 2380, type: 'square', dur: 0.35, gain: 0.05, delay: 0.02 }); }
  horn() { for (let i = 0; i < 3; i++) this.tone({ freq: 196 * (i === 1 ? 1.5 : 1), type: 'sawtooth', dur: 0.5, gain: 0.12, delay: i * 0.55 }); }
  shot() { this.noise({ dur: 0.06, gain: 0.25 }); this.tone({ freq: 180, type: 'triangle', dur: 0.08, gain: 0.2, slide: -120 }); }
  pass() { this.noise({ dur: 0.04, gain: 0.12 }); }
  board() { this.tone({ freq: 120, type: 'triangle', dur: 0.12, gain: 0.18, slide: -60 }); this.noise({ dur: 0.05, gain: 0.1 }); }
  post() { this.tone({ freq: 1500, type: 'sine', dur: 0.25, gain: 0.15, slide: -200 }); }
  steal() { this.tone({ freq: 300, type: 'square', dur: 0.06, gain: 0.08, slide: 150 }); }
  drop() { this.tone({ freq: 500, type: 'sine', dur: 0.08, gain: 0.12, slide: -200 }); }
}
