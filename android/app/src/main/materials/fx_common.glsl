// The effect shaders' shared formulas (ADR 0007) — the twin of iOS's FxMaterials graphs, written once
// for the six fx_*.mat (included, never compiled alone). Everything is in the asset's model space (the
// game's frame: X across, Y up, Z along); t is the renderer's clock in seconds. Reduce Motion is
// already folded into the parameters (WorldEffects scales amplitudes and rates).

// A vertex's motion data (w, p), carried inside its palette swatch (tools/worldkit.py: encode). `uv` is
// glTF's (V flipped), so (1 − v_blender) is uv.y.
vec2 fxData(vec2 uv) {
    return vec2((fract(uv.x * 32.0) - 0.05) / 0.9, (fract(uv.y * 32.0) - 0.05) / 0.9);
}

// base + a1·sin(ω1t + 2πp) + a2·sin(ω2t + 1.7·2πp)
float fxPulse(float t, float p, vec3 amp, vec3 rate) {
    float ph = 6.28318530718 * p;
    return amp.x + amp.y * sin(rate.x * t + ph) + amp.z * sin(rate.y * t + 1.7 * ph);
}

// The offset of a mesh vertex at `pos` with data d: an orbit about the vertical through `pivot` on
// ellipses (z : x = ellipse) at spin·k, then the sway. orbit = 1: w is the speed factor k = 2w − 1
// and the sway weight is 1; orbit = 0: w is the sway weight.
vec3 fxMotion(vec3 pos, vec2 d, float t, vec3 swayAmp, float swayRate, float orbit, float spin, vec3 pivot, float ellipse) {
    float k = mix(1.0, 2.0 * d.x - 1.0, orbit);
    float s = mix(d.x, 1.0, orbit);
    float theta = spin * k * t;
    float dx = pos.x - pivot.x;
    float dz = pos.z - pivot.z;
    float qz = dz / ellipse;
    float c = cos(theta);
    float sn = sin(theta);
    vec3 o = vec3(dx * c - qz * sn - dx, 0.0, (dx * sn + qz * c) * ellipse - dz);
    float wt = swayRate * t;
    float ph = 6.28318530718 * d.y;
    float s1 = sin(wt + ph);
    float s2 = sin(2.45 * wt + 1.9 * ph);
    float c1 = cos(0.82 * wt + 1.3 * ph);
    float a = 0.77 * s1 + 0.23 * s2;
    float b = 0.77 * c1 + 0.23 * s2;
    return o + swayAmp * vec3(a, a, b) * s;
}

// A sprite's offset this frame, from its baked corner vertex `pos` (corner from d, spawn point
// recovered with the half-size): travelling (wrapping every `wrap` m, fading at the ends), wobbling,
// sized by the pulse, turned to face `cam`. Its randomness is a hash of its spawn point.
vec3 fxParticle(vec3 pos, vec2 d, float t, vec3 cam, float size, float sizeSpread, vec3 travel, float wrap,
                vec3 wobble, float wobbleRate, vec3 pulseAmp, vec3 pulseRate) {
    vec2 q = vec2(step(0.5, d.x), step(0.5, d.y)) * 2.0 - 1.0;
    vec3 c = pos - vec3(q.x * size, 0.0, q.y * size);
    float r0 = fract(dot(c, vec3(12.9898, 78.233, 37.719)));
    float r1 = fract(dot(c, vec3(39.346, 11.135, 83.155)));
    float r2 = fract(dot(c, vec3(71.37, 27.91, 53.17)));
    float sp = 0.6 + 0.8 * r1;
    float len = length(travel);
    float f = fract(len * sp * t / max(wrap, 0.001) + r0);
    vec3 off = travel / max(len, 0.0001) * f * wrap;
    float fade = wrap > 0.0 ? smoothstep(0.0, 0.1, f) * (1.0 - smoothstep(0.8, 1.0, f)) : 1.0;
    float ph = 6.28318530718 * r0;
    float tt = t * wobbleRate * sp + ph;
    vec3 wob = wobble * vec3(0.56 * sin(tt) + 0.44 * sin(0.37 * tt + ph), sin(0.8 * tt + ph),
                             0.56 * cos(0.9 * tt) + 0.44 * cos(0.29 * tt + ph));
    float b = clamp(fxPulse(t, r2, pulseAmp, pulseRate), 0.0, 2.0);
    float s = size * (1.0 + sizeSpread * (2.0 * r1 - 1.0)) * b * fade;
    vec3 cc = c + off + wob;
    vec3 fwd = normalize(cam - cc);
    vec3 right = normalize(cross(vec3(0.0, 1.0, 0.0), fwd));
    vec3 up = cross(fwd, right);
    return cc + (right * q.x + up * q.y) * s - pos;
}

// A sprite's soft disc from its interpolated corner coordinates.
float fxDisc(vec2 d) {
    float a = 1.0 - smoothstep(0.1, 1.0, length(d * 2.0 - 1.0));
    return a * a;
}
