import * as THREE from '../vendor/three.module.js';
import { RINK, ORBIT, FACEOFF_SPOTS } from './config.js';
import { clamp, lerp, rand, pick, sdRoundRect } from './math.js';

const HW = RINK.width / 2;
const HL = RINK.length / 2;


function roundedRectShape(hw, hl, r) {
  const s = new THREE.Shape();
  s.moveTo(-hw + r, -hl);
  s.lineTo(hw - r, -hl);
  s.absarc(hw - r, -hl + r, r, -Math.PI / 2, 0, false);
  s.lineTo(hw, hl - r);
  s.absarc(hw - r, hl - r, r, 0, Math.PI / 2, false);
  s.lineTo(-hw + r, hl);
  s.absarc(-hw + r, hl - r, r, Math.PI / 2, Math.PI, false);
  s.lineTo(-hw, -hl + r);
  s.absarc(-hw + r, -hl + r, r, Math.PI, Math.PI * 1.5, false);
  return s;
}

function ringGeometry(innerHW, innerHL, innerR, outerHW, outerHL, outerR, height) {
  const outer = roundedRectShape(outerHW, outerHL, outerR);
  const inner = roundedRectShape(innerHW, innerHL, innerR);
  outer.holes.push(inner);
  const g = new THREE.ExtrudeGeometry(outer, { depth: height, bevelEnabled: false, curveSegments: 14 });
  g.rotateX(-Math.PI / 2);
  return g;
}

export class Renderer {
  constructor(canvas) {
    this.canvas = canvas;
    this.renderer = new THREE.WebGLRenderer({ canvas, antialias: true, alpha: true, powerPreference: 'high-performance' });
    this.renderer.setPixelRatio(Math.min(window.devicePixelRatio || 1, 2));
    this.renderer.shadowMap.enabled = true;
    this.renderer.shadowMap.type = THREE.PCFSoftShadowMap;
    this.renderer.outputColorSpace = THREE.SRGBColorSpace;
    this.renderer.setClearColor(0x000000, 0);

    this.scene = new THREE.Scene();
    this.camera = new THREE.PerspectiveCamera(60, 1, 1, 400);
    this.focusZ = 0;
    this.shake = 0;
    // camera rig: height, distance behind the focus point, look-ahead, width fit distance
    this.camParams = { y: 36, back: 20, look: -4, nearZ: 8, rangeMin: -7, rangeMax: 14, minFov: 45, maxFov: 78 };
    this.raycaster = new THREE.Raycaster();
    this.plane = new THREE.Plane(new THREE.Vector3(0, 1, 0), 0);
    this.playerMeshes = new Map();
    this.effects = [];
    this.time = 0;

    this.buildLights();
    this.buildRink();
    this.buildPuck();
    this.buildAim();
    this.buildConfetti();
    this.resize();
    window.addEventListener('resize', () => this.resize());
  }

  // ---------------------------------------------------------------- scene
  buildLights() {
    const hemi = new THREE.HemisphereLight(0xe0f2fe, 0x475569, 1.1);
    this.scene.add(hemi);
    const sun = new THREE.DirectionalLight(0xfff7e6, 2.0);
    sun.position.set(18, 60, -20);
    sun.castShadow = true;
    sun.shadow.mapSize.set(2048, 2048);
    sun.shadow.camera.left = -45; sun.shadow.camera.right = 45;
    sun.shadow.camera.top = 45; sun.shadow.camera.bottom = -45;
    sun.shadow.camera.near = 10; sun.shadow.camera.far = 140;
    sun.shadow.bias = -0.0008;
    this.scene.add(sun);
    this.sun = sun;
  }

  makeIceTexture() {
    const W = 1024, H = 2048;
    const c = document.createElement('canvas');
    c.width = W; c.height = H;
    const ctx = c.getContext('2d');
    const sx = W / RINK.width, sz = H / RINK.length;
    const X = (x) => (x + HW) * sx;
    const Z = (z) => (z + HL) * sz;
    // floor outside of the rounded corners
    ctx.fillStyle = '#334155';
    ctx.fillRect(0, 0, W, H);
    // ice
    ctx.fillStyle = '#eef8ff';
    const r = RINK.corner * sx;
    ctx.beginPath();
    ctx.roundRect(0, 0, W, H, r);
    ctx.fill();
    // subtle skating marks
    ctx.strokeStyle = 'rgba(180,210,235,0.35)';
    ctx.lineWidth = 2;
    for (let i = 0; i < 140; i++) {
      ctx.beginPath();
      const x0 = Math.random() * W, y0 = Math.random() * H;
      ctx.moveTo(x0, y0);
      ctx.quadraticCurveTo(x0 + rand(-120, 120), y0 + rand(-120, 120), x0 + rand(-200, 200), y0 + rand(-200, 200));
      ctx.stroke();
    }
    const line = (z, color, w) => { ctx.fillStyle = color; ctx.fillRect(0, Z(z) - w / 2, W, w); };
    // goal lines, blue lines, centre line
    line(-RINK.goalLineZ, '#ef4444', 6);
    line(RINK.goalLineZ, '#ef4444', 6);
    line(-RINK.blueLineZ, '#3b82f6', 14);
    line(RINK.blueLineZ, '#3b82f6', 14);
    line(0, '#ef4444', 12);
    // circles
    const circle = (x, z, rad, color, w, fill) => {
      ctx.beginPath(); ctx.arc(X(x), Z(z), rad * sx, 0, Math.PI * 2);
      if (fill) { ctx.fillStyle = fill; ctx.fill(); }
      ctx.strokeStyle = color; ctx.lineWidth = w; ctx.stroke();
    };
    const dot = (x, z, color) => { ctx.beginPath(); ctx.arc(X(x), Z(z), 0.45 * sx, 0, Math.PI * 2); ctx.fillStyle = color; ctx.fill(); };
    circle(0, 0, RINK.faceoffRadius, '#3b82f6', 8);
    dot(0, 0, '#3b82f6');
    for (const s of FACEOFF_SPOTS.end) { circle(s.x, s.z, RINK.faceoffRadius, '#ef4444', 8); dot(s.x, s.z, '#ef4444'); }
    for (const s of FACEOFF_SPOTS.neutral) dot(s.x, s.z, '#ef4444');
    // creases
    for (const sgn of [-1, 1]) {
      const gz = sgn * RINK.goalLineZ;
      ctx.beginPath();
      ctx.arc(X(0), Z(gz), RINK.creaseRadius * sx, sgn > 0 ? Math.PI : 0, sgn > 0 ? Math.PI * 2 : Math.PI);
      ctx.closePath();
      ctx.fillStyle = 'rgba(96,165,250,0.45)'; ctx.fill();
      ctx.strokeStyle = '#ef4444'; ctx.lineWidth = 6; ctx.stroke();
    }
    // centre logo
    ctx.save();
    ctx.translate(X(0), Z(0));
    ctx.globalAlpha = 0.18;
    ctx.fillStyle = '#1d4ed8';
    ctx.beginPath(); ctx.arc(0, 0, 2.6 * sx, 0, Math.PI * 2); ctx.fill();
    ctx.restore();
    const tex = new THREE.CanvasTexture(c);
    tex.colorSpace = THREE.SRGBColorSpace;
    tex.anisotropy = 4;
    return tex;
  }

  buildRink() {
    // ice
    const ice = new THREE.Mesh(
      new THREE.PlaneGeometry(RINK.width, RINK.length),
      new THREE.MeshLambertMaterial({ map: this.makeIceTexture() }),
    );
    ice.rotation.x = -Math.PI / 2;
    ice.receiveShadow = true;
    this.scene.add(ice);

    // thin dark base so the rink reads as a floating slab
    const base = new THREE.Mesh(
      ringGeometry(HW + 0.4, HL + 0.4, RINK.corner + 0.4, HW + 2.2, HL + 2.2, RINK.corner + 2.2, 0.6),
      new THREE.MeshLambertMaterial({ color: 0x1e1b4b }),
    );
    base.position.y = -0.6;
    this.scene.add(base);
    const under = new THREE.Mesh(new THREE.PlaneGeometry(RINK.width + 4.4, RINK.length + 4.4), new THREE.MeshLambertMaterial({ color: 0x1e1b4b }));
    under.rotation.x = -Math.PI / 2; under.position.y = -0.62;
    this.scene.add(under);

    // boards
    const boards = new THREE.Mesh(
      ringGeometry(HW, HL, RINK.corner, HW + 0.4, HL + 0.4, RINK.corner + 0.4, RINK.boardHeight),
      new THREE.MeshLambertMaterial({ color: 0xf8fafc }),
    );
    boards.castShadow = true; boards.receiveShadow = true;
    this.scene.add(boards);
    // kick plate (yellow strip at the bottom)
    const kick = new THREE.Mesh(
      ringGeometry(HW - 0.02, HL - 0.02, RINK.corner, HW + 0.42, HL + 0.42, RINK.corner + 0.42, 0.22),
      new THREE.MeshLambertMaterial({ color: 0xfacc15 }),
    );
    this.scene.add(kick);
    // glass
    const glass = new THREE.Mesh(
      ringGeometry(HW + 0.05, HL + 0.05, RINK.corner, HW + 0.3, HL + 0.3, RINK.corner + 0.3, 1.5),
      new THREE.MeshLambertMaterial({ color: 0xbae6fd, transparent: true, opacity: 0.18, depthWrite: false }),
    );
    glass.position.y = RINK.boardHeight;
    this.scene.add(glass);
    // rail on top of the glass
    const rail = new THREE.Mesh(
      ringGeometry(HW + 0.02, HL + 0.02, RINK.corner, HW + 0.36, HL + 0.36, RINK.corner + 0.36, 0.1),
      new THREE.MeshLambertMaterial({ color: 0x0ea5e9 }),
    );
    rail.position.y = RINK.boardHeight + 1.5;
    this.scene.add(rail);

    for (const sgn of [-1, 1]) this.buildGoal(sgn);
  }

  buildGoal(sgn) {
    const g = new THREE.Group();
    const gz = sgn * RINK.goalLineZ;
    const hw = RINK.goalWidth / 2, depth = RINK.goalDepth, height = 1.9;
    const red = new THREE.MeshToonMaterial({ color: 0xef4444 });
    const post = new THREE.CylinderGeometry(0.13, 0.13, height, 10);
    for (const sx of [-1, 1]) {
      const p = new THREE.Mesh(post, red);
      p.position.set(sx * hw, height / 2, gz);
      p.castShadow = true;
      g.add(p);
    }
    const bar = new THREE.Mesh(new THREE.CylinderGeometry(0.12, 0.12, hw * 2 + 0.26, 10), red);
    bar.rotation.z = Math.PI / 2;
    bar.position.set(0, height, gz);
    bar.castShadow = true;
    g.add(bar);
    // net panels
    const netMat = new THREE.MeshBasicMaterial({ color: 0xffffff, transparent: true, opacity: 0.35, side: THREE.DoubleSide, depthWrite: false });
    const back = new THREE.Mesh(new THREE.PlaneGeometry(hw * 2, height), netMat);
    back.position.set(0, height / 2, gz - sgn * depth);
    g.add(back);
    const top = new THREE.Mesh(new THREE.PlaneGeometry(hw * 2, depth), netMat);
    top.rotation.x = -Math.PI / 2;
    top.position.set(0, height, gz - sgn * depth / 2);
    g.add(top);
    for (const sx of [-1, 1]) {
      const side = new THREE.Mesh(new THREE.PlaneGeometry(depth, height), netMat);
      side.rotation.y = Math.PI / 2;
      side.position.set(sx * hw, height / 2, gz - sgn * depth / 2);
      g.add(side);
    }
    // mesh lines for a stylised net
    const grid = new THREE.LineSegments(this.netLines(hw, depth, height, gz, sgn), new THREE.LineBasicMaterial({ color: 0xffffff, transparent: true, opacity: 0.55 }));
    g.add(grid);
    this.scene.add(g);
  }

  netLines(hw, depth, height, gz, sgn) {
    const pts = [];
    const zb = gz - sgn * depth;
    for (let x = -hw; x <= hw + 0.01; x += 0.4) { pts.push(x, 0, zb, x, height, zb); pts.push(x, height, gz, x, height, zb); }
    for (let y = 0; y <= height + 0.01; y += 0.4) { pts.push(-hw, y, zb, hw, y, zb); pts.push(-hw, y, gz, -hw, y, zb); pts.push(hw, y, gz, hw, y, zb); }
    const geo = new THREE.BufferGeometry();
    geo.setAttribute('position', new THREE.Float32BufferAttribute(pts, 3));
    return geo;
  }

  buildPuck() {
    this.puck = new THREE.Mesh(
      new THREE.CylinderGeometry(0.36, 0.36, 0.2, 18),
      new THREE.MeshToonMaterial({ color: 0x0f172a }),
    );
    this.puck.castShadow = true;
    this.puck.position.y = 0.1;
    this.scene.add(this.puck);
    // glow disc so the puck is easy to see from above
    this.puckGlow = new THREE.Mesh(
      new THREE.CircleGeometry(0.8, 20),
      new THREE.MeshBasicMaterial({ color: 0xfacc15, transparent: true, opacity: 0.35, depthWrite: false }),
    );
    this.puckGlow.rotation.x = -Math.PI / 2;
    this.puckGlow.position.y = 0.02;
    this.scene.add(this.puckGlow);
    this.trail = [];
    for (let i = 0; i < 12; i++) {
      const t = new THREE.Mesh(
        new THREE.CircleGeometry(0.3, 12),
        new THREE.MeshBasicMaterial({ color: 0xfde68a, transparent: true, opacity: 0, depthWrite: false }),
      );
      t.rotation.x = -Math.PI / 2;
      t.position.y = 0.015;
      this.scene.add(t);
      this.trail.push(t);
    }
  }

  buildConfetti() {
    const n = 160;
    this.confetti = new THREE.InstancedMesh(new THREE.BoxGeometry(0.35, 0.08, 0.5), new THREE.MeshLambertMaterial({ color: 0xffffff }), n);
    this.confetti.count = 0;
    this.confetti.frustumCulled = false;
    this.confettiData = [];
    this.scene.add(this.confetti);
  }

  // ---------------------------------------------------------------- players
  buildPlayers(match) {
    for (const m of this.playerMeshes.values()) this.scene.remove(m.group);
    this.playerMeshes.clear();
    for (const p of match.players) {
      const team = match.teams[p.team];
      const g = this.makePlayerMesh(p, team);
      this.scene.add(g.group);
      this.playerMeshes.set(p.id, g);
    }
  }

  makePlayerMesh(p, team) {
    const group = new THREE.Group();
    const isG = p.role === 'G', isO = p.role === 'O';
    const primary = new THREE.Color(isO ? '#94a3b8' : team.primary);
    const secondary = new THREE.Color(isO ? '#f97316' : team.secondary);
    const r = p.r;
    const h = isO ? 0.7 : 0.45;
    const body = new THREE.Mesh(new THREE.CylinderGeometry(r, r * 0.92, h, 28), new THREE.MeshToonMaterial({ color: primary }));
    body.position.y = h / 2;
    body.castShadow = true;
    group.add(body);
    // top marking: a small centre disc (goalies get a wide ring, dummies a stripe)
    if (isG) {
      const ring = new THREE.Mesh(new THREE.RingGeometry(r * 0.45, r * 0.8, 28), new THREE.MeshBasicMaterial({ color: secondary, side: THREE.DoubleSide }));
      ring.rotation.x = -Math.PI / 2; ring.position.y = h + 0.01;
      group.add(ring);
    } else if (isO) {
      const stripe = new THREE.Mesh(new THREE.CylinderGeometry(r * 1.01, r * 1.01, 0.18, 28, 1, true), new THREE.MeshToonMaterial({ color: secondary }));
      stripe.position.y = h * 0.6;
      group.add(stripe);
    } else {
      const dot = new THREE.Mesh(new THREE.CircleGeometry(r * 0.45, 24), new THREE.MeshBasicMaterial({ color: secondary }));
      dot.rotation.x = -Math.PI / 2; dot.position.y = h + 0.01;
      group.add(dot);
    }
    // pass-target highlight ring
    const ring = new THREE.Mesh(new THREE.RingGeometry(r + 0.25, r + 0.55, 32), new THREE.MeshBasicMaterial({ color: 0x4ade80, transparent: true, opacity: 0.9, depthWrite: false, side: THREE.DoubleSide }));
    ring.rotation.x = -Math.PI / 2;
    ring.position.y = 0.03;
    ring.visible = false;
    group.add(ring);
    const disc = new THREE.Mesh(new THREE.CircleGeometry(r + 0.2, 24), new THREE.MeshBasicMaterial({ color: primary, transparent: true, opacity: 0.2, depthWrite: false }));
    disc.rotation.x = -Math.PI / 2;
    disc.position.y = 0.02;
    group.add(disc);
    return { group, body, ring, disc, baseY: h / 2 };
  }

  /** Orbit ring around the carrier and the release arrow through the puck. */
  buildAim() {
    this.orbitRing = new THREE.Mesh(new THREE.RingGeometry(ORBIT.radius - 0.05, ORBIT.radius + 0.05, 48),
      new THREE.MeshBasicMaterial({ color: 0xffffff, transparent: true, opacity: 0.5, depthWrite: false, side: THREE.DoubleSide }));
    this.orbitRing.rotation.x = -Math.PI / 2;
    this.orbitRing.position.y = 0.025;
    this.orbitRing.visible = false;
    this.scene.add(this.orbitRing);

    // Tapered ribbon of unit length along +Z (scaled per frame), with a flowing
    // dash texture, a chevron head and a soft additive glow underneath.
    const tapered = (w0, w1, segs = 12) => {
      const pos = [], uv = [], idx = [];
      for (let i = 0; i <= segs; i++) {
        const t = i / segs;
        const w = w0 + (w1 - w0) * t;
        pos.push(-w / 2, 0, t, w / 2, 0, t);
        uv.push(0, t, 1, t);
        if (i < segs) { const a = i * 2; idx.push(a, a + 1, a + 2, a + 1, a + 3, a + 2); }
      }
      const g = new THREE.BufferGeometry();
      g.setAttribute('position', new THREE.Float32BufferAttribute(pos, 3));
      g.setAttribute('uv', new THREE.Float32BufferAttribute(uv, 2));
      g.setIndex(idx);
      return g;
    };
    const dashTex = (() => {
      const c = document.createElement('canvas');
      c.width = 64; c.height = 128;
      const ctx = c.getContext('2d');
      ctx.clearRect(0, 0, 64, 128);
      // one chevron-shaped dash per tile, pointing along +v
      ctx.fillStyle = '#fff';
      ctx.beginPath();
      ctx.moveTo(2, 34); ctx.lineTo(32, 6); ctx.lineTo(62, 34); ctx.lineTo(62, 70); ctx.lineTo(32, 42); ctx.lineTo(2, 70); ctx.closePath();
      ctx.fill();
      const t = new THREE.CanvasTexture(c);
      t.wrapS = THREE.RepeatWrapping; t.wrapT = THREE.RepeatWrapping;
      t.minFilter = THREE.LinearFilter;
      return t;
    })();
    this.aimGroup = new THREE.Group();
    this.aimGroup.visible = false;
    this.aimRibbon = new THREE.Mesh(tapered(0.62, 0.3),
      new THREE.MeshBasicMaterial({ map: dashTex, color: 0xfacc15, transparent: true, opacity: 0.95, depthWrite: false, side: THREE.DoubleSide }));
    this.aimRibbon.position.y = 0.04;
    this.aimGlow = new THREE.Mesh(tapered(1.0, 0.5),
      new THREE.MeshBasicMaterial({ color: 0xfacc15, transparent: true, opacity: 0.18, depthWrite: false, side: THREE.DoubleSide, blending: THREE.AdditiveBlending }));
    this.aimGlow.position.y = 0.035;
    const head = new THREE.Shape();
    head.moveTo(0, 1.3); head.lineTo(-0.95, -0.2); head.lineTo(0, 0.25); head.lineTo(0.95, -0.2); head.closePath();
    this.aimHead = new THREE.Mesh(new THREE.ShapeGeometry(head),
      new THREE.MeshBasicMaterial({ color: 0xfacc15, transparent: true, opacity: 0.95, depthWrite: false, side: THREE.DoubleSide }));
    this.aimHead.rotation.x = -Math.PI / 2;
    this.aimHead.rotation.z = Math.PI; // shape +y -> world -z after the tilt, so flip it
    this.aimHead.position.y = 0.045;
    this.aimHeadGlow = new THREE.Mesh(new THREE.ShapeGeometry(head),
      new THREE.MeshBasicMaterial({ color: 0xfacc15, transparent: true, opacity: 0.25, depthWrite: false, side: THREE.DoubleSide, blending: THREE.AdditiveBlending }));
    this.aimHeadGlow.rotation.copy(this.aimHead.rotation);
    this.aimHeadGlow.scale.setScalar(1.3);
    this.aimHeadGlow.position.y = 0.04;
    this.aimGroup.add(this.aimGlow, this.aimRibbon, this.aimHeadGlow, this.aimHead);
    this.scene.add(this.aimGroup);
    this.dashTex = dashTex;
    this.aimLenMax = 16;
  }

  updateAim(match, dt) {
    const c = match.puck.carrier;
    const show = c && match.isUserCarrier(c) && (match.state === 'play' || match.state === 'ready');
    this.orbitRing.visible = !!show;
    this.aimGroup.visible = !!show;
    for (const m of this.playerMeshes.values()) m.ring.visible = false;
    if (!show) return;
    this.orbitRing.position.x = c.x; this.orbitRing.position.z = c.z;
    this.aimGroup.position.set(c.x, 0, c.z);
    this.aimGroup.rotation.y = match.puck.orbit;
    const snap = match.aimTarget(c);
    const power = match.userPower ?? ORBIT.powerDefault;
    const color = snap ? (snap.kind === 'goal' ? 0xf472b6 : 0x4ade80) : 0xfacc15;
    for (const m of [this.aimRibbon, this.aimGlow, this.aimHead, this.aimHeadGlow]) m.material.color.setHex(color);
    const pulse = snap ? 0.85 + Math.sin(this.time * 14) * 0.15 : 0.7;
    this.aimRibbon.material.opacity = pulse;
    this.aimHead.material.opacity = pulse;
    this.aimGlow.material.opacity = 0.06 + power * 0.12 + (snap ? 0.06 : 0);
    this.aimHeadGlow.material.opacity = 0.1 + power * 0.15;
    if (snap?.kind === 'pass') {
      const m = this.playerMeshes.get(snap.target.id);
      if (m) { m.ring.visible = true; m.ring.scale.setScalar(1 + Math.sin(this.time * 10) * 0.08); }
    }
    // length: to the target when locked, otherwise grows with the charged power
    let len = 6 + power * (this.aimLenMax - 6);
    if (snap?.kind === 'pass') len = Math.hypot(snap.target.x - c.x, snap.target.z - c.z) - ORBIT.radius - 1.6;
    else if (snap?.kind === 'goal') len = Math.hypot(c.x, match.attackGoalZ(c.team) - c.z) - ORBIT.radius - 1.2;
    // never draw past the boards
    const dx = Math.sin(match.puck.orbit), dz = Math.cos(match.puck.orbit);
    let toBoards = 0;
    for (let d = 1; d < this.aimLenMax + 2; d += 0.5) {
      if (sdRoundRect(c.x + dx * d, c.z + dz * d, HW, HL, RINK.corner) > -0.6) break;
      toBoards = d;
    }
    len = Math.max(2.5, Math.min(len, toBoards - ORBIT.radius - 1.2));
    const width = 0.8 + power * 0.6;
    const start = ORBIT.radius + 0.35;
    for (const r of [this.aimRibbon, this.aimGlow]) { r.scale.set(width, 1, len); r.position.z = start; }
    this.aimHead.position.z = start + len;
    this.aimHeadGlow.position.z = start + len;
    const hs = 0.8 + power * 0.5;
    this.aimHead.scale.setScalar(hs);
    this.aimHeadGlow.scale.setScalar(hs * 1.3);
    // flowing dashes: repeat with length, scroll along the arrow
    this.dashTex.repeat.set(1, len / 1.3);
    this.dashTex.offset.y -= dt * (1.2 + power * 1.5);
  }

  // ---------------------------------------------------------------- frame
  resize() {
    const w = this.canvas.clientWidth || window.innerWidth;
    const h = this.canvas.clientHeight || window.innerHeight;
    this.renderer.setSize(w, h, false);
    this.camera.aspect = w / h;
    this.fitCamera();
  }

  /** Pick a vertical fov so the rink width always fits on screen. */
  fitCamera() {
    const aspect = this.camera.aspect;
    const camPos = this.cameraPosition(this.focusZ);
    const c = this.camParams;
    const nearPoint = new THREE.Vector3(0, 0, this.focusZ - c.nearZ);
    const d = camPos.distanceTo(nearPoint);
    const halfWidth = HW + 1.5;
    const hfov = 2 * Math.atan(halfWidth / d);
    let vfov = 2 * Math.atan(Math.tan(hfov / 2) / aspect);
    vfov = clamp((vfov * 180) / Math.PI, c.minFov, c.maxFov);
    this.camera.fov = vfov;
    this.camera.updateProjectionMatrix();
  }

  cameraPosition(focusZ) {
    const c = this.camParams;
    return new THREE.Vector3(0, c.y, focusZ - c.back);
  }

  updateCamera(match, dt) {
    const puck = match.puck;
    const c = this.camParams;
    const wantFocus = clamp(puck.z * 0.85, c.rangeMin, c.rangeMax);
    this.focusZ = lerp(this.focusZ, wantFocus, 1 - Math.exp(-dt * 2.2));
    const pos = this.cameraPosition(this.focusZ);
    if (this.shake > 0) {
      pos.x += (Math.random() - 0.5) * this.shake;
      pos.y += (Math.random() - 0.5) * this.shake;
      this.shake = Math.max(0, this.shake - dt * 2.5);
    }
    this.camera.position.copy(pos);
    this.camera.lookAt(0, 0, this.focusZ + this.camParams.look);
    this.fitCamera();
  }

  update(match, dt) {
    this.time += dt;
    if (match) {
      this.updateCamera(match, dt);
      for (const p of match.players) {
        const m = this.playerMeshes.get(p.id);
        if (!m) continue;
        m.group.position.set(p.x, 0, p.z);
        const sp = Math.hypot(p.vx, p.vz);
        // lean into the movement direction a touch
        m.group.rotation.set(0, 0, 0);
        if (sp > 0.5) {
          const lean = clamp(sp * 0.02, 0, 0.18);
          m.group.rotation.x = (p.vz / sp) * lean;
          m.group.rotation.z = -(p.vx / sp) * lean;
        }
        m.disc.material.opacity = match.puck.carrier === p ? 0.55 : 0.2;
      }
      this.updateAim(match, dt);
      const puck = match.puck;
      this.puck.position.set(puck.x, 0.1, puck.z);
      this.puck.rotation.y += dt * 4;
      this.puckGlow.position.set(puck.x, 0.02, puck.z);
      const psp = Math.hypot(puck.vx, puck.vz);
      const tr = puck.trail;
      for (let i = 0; i < this.trail.length; i++) {
        const src = tr[tr.length - 1 - i];
        const t = this.trail[i];
        if (src && !puck.carrier && psp > 6) {
          t.position.x = src.x; t.position.z = src.z;
          const f = 1 - i / this.trail.length;
          t.material.opacity = 0.45 * f;
          t.scale.setScalar(0.4 + f * 0.8);
        } else t.material.opacity = 0;
      }
    }
    this.updateConfetti(dt);
    this.renderer.render(this.scene, this.camera);
  }

  // ---------------------------------------------------------------- effects
  celebrate(team, colors, gz) {
    this.shake = 1.4;
    const dummy = new THREE.Object3D();
    const col = new THREE.Color();
    this.confettiData = [];
    for (let i = 0; i < 160; i++) {
      const d = {
        x: rand(-4, 4), y: rand(1, 3), z: gz + rand(-2, 2),
        vx: rand(-9, 9), vy: rand(6, 16), vz: rand(-9, 9),
        rx: rand(0, 6), ry: rand(0, 6), rvx: rand(-6, 6), rvy: rand(-6, 6), life: rand(1.8, 2.8),
      };
      this.confettiData.push(d);
      this.confetti.setColorAt(i, col.set(pick(colors)));
    }
    this.confetti.instanceColor.needsUpdate = true;
    this.confetti.count = 160;
  }

  updateConfetti(dt) {
    if (!this.confettiData.length) return;
    const dummy = new THREE.Object3D();
    let alive = 0;
    this.confettiData.forEach((d, i) => {
      d.life -= dt;
      if (d.life <= 0) { dummy.scale.setScalar(0); }
      else {
        alive++;
        d.vy -= 18 * dt; d.x += d.vx * dt; d.y += d.vy * dt; d.z += d.vz * dt;
        if (d.y < 0.1) { d.y = 0.1; d.vy *= -0.3; d.vx *= 0.8; d.vz *= 0.8; }
        d.rx += d.rvx * dt; d.ry += d.rvy * dt;
        dummy.scale.setScalar(1);
      }
      dummy.position.set(d.x, d.y, d.z);
      dummy.rotation.set(d.rx, d.ry, 0);
      dummy.updateMatrix();
      this.confetti.setMatrixAt(i, dummy.matrix);
    });
    this.confetti.instanceMatrix.needsUpdate = true;
    if (!alive) { this.confettiData = []; this.confetti.count = 0; }
  }

  // ---------------------------------------------------------------- picking
  screenToWorld(px, py) {
    const rect = this.canvas.getBoundingClientRect();
    const nx = ((px - rect.left) / rect.width) * 2 - 1;
    const ny = -((py - rect.top) / rect.height) * 2 + 1;
    this.raycaster.setFromCamera(new THREE.Vector2(nx, ny), this.camera);
    const hit = new THREE.Vector3();
    if (!this.raycaster.ray.intersectPlane(this.plane, hit)) return null;
    return { x: hit.x, z: hit.z };
  }
}
