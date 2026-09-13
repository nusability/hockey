import * as THREE from '../vendor/three.module.js';
import { RINK, ORBIT, FACEOFF_SPOTS, SPORTS } from './config.js';
import { clamp, lerp, rand, pick, noise, sdRoundRect } from './math.js';

const HW = RINK.width / 2;
const HL = RINK.length / 2;

function roundedRectShape(hw, hl, r) {
  r = Math.max(0.01, Math.min(r, hw, hl));
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

export function ringGeometry(innerHW, innerHL, innerR, outerHW, outerHL, outerR, height) {
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
    this.camera = new THREE.PerspectiveCamera(60, 1, 1, 500);
    this.focusZ = 0;
    this.shake = 0;
    this.camParams = { y: 36, back: 20, look: -4, nearZ: 8, rangeMin: -7, rangeMax: 14, minFov: 45, maxFov: 78 };
    this.raycaster = new THREE.Raycaster();
    this.plane = new THREE.Plane(new THREE.Vector3(0, 1, 0), 0);
    this.playerMeshes = new Map();
    this.time = 0;
    this.world = null;
    this.sceneryHandle = null;

    this.buildLights();
    this.rinkGroup = new THREE.Group();
    this.scene.add(this.rinkGroup);
    this.sceneryGroup = new THREE.Group();
    this.scene.add(this.sceneryGroup);
    this.buildBall();
    this.buildAim();
    this.buildConfetti();
    this.resize();
    window.addEventListener('resize', () => this.resize());
  }

  // ---------------------------------------------------------------- lights
  buildLights() {
    this.hemi = new THREE.HemisphereLight(0xe0f2fe, 0x475569, 1.1);
    this.scene.add(this.hemi);
    const sun = new THREE.DirectionalLight(0xfff7e6, 2.0);
    sun.position.set(18, 60, -20);
    sun.castShadow = true;
    sun.shadow.mapSize.set(2048, 2048);
    sun.shadow.camera.left = -45; sun.shadow.camera.right = 45;
    sun.shadow.camera.top = 45; sun.shadow.camera.bottom = -45;
    sun.shadow.camera.near = 10; sun.shadow.camera.far = 160;
    sun.shadow.bias = -0.0008;
    this.scene.add(sun);
    this.sun = sun;
  }

  // ---------------------------------------------------------------- world
  /** Rebuild everything that depends on the world (sky, pitch, wall, ball, scenery). */
  setWorld(world) {
    if (this.world === world) return;
    this.world = world;
    const sport = SPORTS[world.sport] || SPORTS.field;
    this.sport = sport;
    this.corner = sport.corner;
    document.body.style.background = world.sky;
    // lights
    const L = world.light || {};
    this.hemi.color.setHex(L.hemiSky ?? 0xe0f2fe);
    this.hemi.groundColor.setHex(L.hemiGround ?? 0x475569);
    this.hemi.intensity = L.hemiIntensity ?? 1.1;
    this.sun.color.setHex(L.sun ?? 0xfff7e6);
    this.sun.intensity = L.sunIntensity ?? 2.0;
    if (L.sunPos) this.sun.position.set(...L.sunPos);
    this.scene.fog = L.fog ? new THREE.Fog(L.fog.color, L.fog.near, L.fog.far) : null;
    // pitch + wall + goals
    this.disposeGroup(this.rinkGroup);
    this.buildRink(world, sport);
    // ball look
    this.buildBall();
    // scenery
    this.disposeGroup(this.sceneryGroup);
    this.sceneryHandle = null;
    if (world.buildScenery) {
      const ctx = { THREE, RINK, HW, HL, corner: this.corner, rand, pick, lerp, noise, ringGeometry };
      try { this.sceneryHandle = world.buildScenery(this.sceneryGroup, ctx) || null; }
      catch (e) { console.error(`world ${world.id} scenery failed`, e); }
    }
  }

  disposeGroup(group) {
    group.traverse((o) => {
      if (o.geometry) o.geometry.dispose();
      if (o.material) { const ms = Array.isArray(o.material) ? o.material : [o.material]; for (const m of ms) { if (m.map) m.map.dispose(); m.dispose(); } }
    });
    while (group.children.length) group.remove(group.children[0]);
  }

  // ---------------------------------------------------------------- pitch
  makeSurfaceTexture(world, sport) {
    const W = 1024, H = 2048;
    const c = document.createElement('canvas');
    c.width = W; c.height = H;
    const ctx = c.getContext('2d');
    const sx = W / RINK.width, sz = H / RINK.length;
    const X = (x) => (x + HW) * sx;
    const Z = (z) => (z + HL) * sz;
    const S = world.surface || {};
    const base = S.base || (sport.id === 'ice' ? '#eef8ff' : '#3f8f3f');
    const stripe = S.stripe || base;
    const lines = S.lines || (sport.id === 'ice' ? '#1d4ed8' : '#ffffff');
    // outside the rounded corners: the wall base colour
    ctx.fillStyle = '#' + (world.border?.base ?? 0x1e1b4b).toString(16).padStart(6, '0');
    ctx.fillRect(0, 0, W, H);
    ctx.save();
    ctx.beginPath();
    ctx.roundRect(0, 0, W, H, sport.corner * sx);
    ctx.clip();
    ctx.fillStyle = base;
    ctx.fillRect(0, 0, W, H);
    if (sport.id === 'field') {
      // mowing stripes
      ctx.fillStyle = stripe;
      const bands = 12;
      for (let i = 0; i < bands; i += 2) ctx.fillRect(0, (H / bands) * i, W, H / bands);
    } else {
      // skating marks
      ctx.strokeStyle = 'rgba(180,210,235,0.35)';
      ctx.lineWidth = 2;
      for (let i = 0; i < 140; i++) {
        ctx.beginPath();
        const x0 = Math.random() * W, y0 = Math.random() * H;
        ctx.moveTo(x0, y0);
        ctx.quadraticCurveTo(x0 + rand(-120, 120), y0 + rand(-120, 120), x0 + rand(-200, 200), y0 + rand(-200, 200));
        ctx.stroke();
      }
    }
    if (S.decorate) { try { S.decorate(ctx, W, H, { X, Z, sx, sz, rand }); } catch (e) { console.error('decorate failed', e); } }
    ctx.restore();

    const line = (z, color, w) => { ctx.fillStyle = color; ctx.fillRect(0, Z(z) - w / 2, W, w); };
    const circle = (x, z, rad, color, w, fill) => {
      ctx.beginPath(); ctx.arc(X(x), Z(z), rad * sx, 0, Math.PI * 2);
      if (fill) { ctx.fillStyle = fill; ctx.fill(); }
      ctx.strokeStyle = color; ctx.lineWidth = w; ctx.stroke();
    };
    const dot = (x, z, color, r = 0.45) => { ctx.beginPath(); ctx.arc(X(x), Z(z), r * sx, 0, Math.PI * 2); ctx.fillStyle = color; ctx.fill(); };
    if (sport.id === 'ice') {
      line(-RINK.goalLineZ, '#ef4444', 6); line(RINK.goalLineZ, '#ef4444', 6);
      line(-RINK.blueLineZ, '#3b82f6', 14); line(RINK.blueLineZ, '#3b82f6', 14);
      line(0, '#ef4444', 12);
      circle(0, 0, RINK.faceoffRadius, '#3b82f6', 8); dot(0, 0, '#3b82f6');
      for (const s of FACEOFF_SPOTS.end) { circle(s.x, s.z, RINK.faceoffRadius, '#ef4444', 8); dot(s.x, s.z, '#ef4444'); }
      for (const s of FACEOFF_SPOTS.neutral) dot(s.x, s.z, '#ef4444');
      for (const sgn of [-1, 1]) {
        const gz = sgn * RINK.goalLineZ;
        ctx.beginPath();
        ctx.arc(X(0), Z(gz), RINK.creaseRadius * sx, sgn > 0 ? Math.PI : 0, sgn > 0 ? Math.PI * 2 : Math.PI);
        ctx.closePath();
        ctx.fillStyle = 'rgba(96,165,250,0.45)'; ctx.fill();
        ctx.strokeStyle = '#ef4444'; ctx.lineWidth = 6; ctx.stroke();
      }
    } else {
      // field hockey: outline, centre line, 23 m lines, shooting circles (D), penalty spots
      const w = 7;
      ctx.strokeStyle = lines; ctx.lineWidth = w; ctx.fillStyle = lines;
      ctx.strokeRect(X(-HW + 0.6), Z(-HL + 0.6), (RINK.width - 1.2) * sx, (RINK.length - 1.2) * sz);
      line(0, lines, w);
      line(-RINK.blueLineZ, lines, w); line(RINK.blueLineZ, lines, w);
      line(-RINK.goalLineZ, lines, w); line(RINK.goalLineZ, lines, w);
      dot(0, 0, lines, 0.35);
      const dRadius = 9.5;
      for (const sgn of [-1, 1]) {
        const gz = sgn * RINK.goalLineZ;
        const half = RINK.goalWidth / 2;
        // D: straight segment in front of the goal joined by quarter arcs
        ctx.beginPath();
        ctx.moveTo(X(-half), Z(gz - sgn * dRadius));
        ctx.lineTo(X(half), Z(gz - sgn * dRadius));
        ctx.arc(X(half), Z(gz), dRadius * sx, sgn > 0 ? Math.PI * 1.5 : Math.PI * 0.5, sgn > 0 ? Math.PI * 2 : Math.PI, sgn < 0);
        ctx.moveTo(X(-half), Z(gz - sgn * dRadius));
        ctx.arc(X(-half), Z(gz), dRadius * sx, sgn > 0 ? Math.PI * 1.5 : Math.PI * 0.5, sgn > 0 ? Math.PI : 0, sgn > 0);
        ctx.stroke();
        // dashed outer D
        ctx.save(); ctx.setLineDash([26, 26]); ctx.lineWidth = 4;
        ctx.beginPath();
        ctx.moveTo(X(-half), Z(gz - sgn * (dRadius + 3)));
        ctx.lineTo(X(half), Z(gz - sgn * (dRadius + 3)));
        ctx.arc(X(half), Z(gz), (dRadius + 3) * sx, sgn > 0 ? Math.PI * 1.5 : Math.PI * 0.5, sgn > 0 ? Math.PI * 2 : Math.PI, sgn < 0);
        ctx.moveTo(X(-half), Z(gz - sgn * (dRadius + 3)));
        ctx.arc(X(-half), Z(gz), (dRadius + 3) * sx, sgn > 0 ? Math.PI * 1.5 : Math.PI * 0.5, sgn > 0 ? Math.PI : 0, sgn > 0);
        ctx.stroke(); ctx.restore();
        dot(0, gz - sgn * 6.4, lines, 0.3);
      }
    }
    const tex = new THREE.CanvasTexture(c);
    tex.colorSpace = THREE.SRGBColorSpace;
    tex.anisotropy = 4;
    return tex;
  }

  buildRink(world, sport) {
    const g = this.rinkGroup;
    const B = world.border || {};
    const height = B.height ?? 1.1;
    const corner = sport.corner;
    const surf = new THREE.Mesh(
      new THREE.PlaneGeometry(RINK.width, RINK.length),
      new THREE.MeshLambertMaterial({ map: this.makeSurfaceTexture(world, sport) }),
    );
    surf.rotation.x = -Math.PI / 2;
    surf.receiveShadow = true;
    g.add(surf);
    const baseColor = B.base ?? 0x1e1b4b;
    const base = new THREE.Mesh(ringGeometry(HW + 0.4, HL + 0.4, corner + 0.4, HW + 2.2, HL + 2.2, corner + 2.2, 0.6), new THREE.MeshLambertMaterial({ color: baseColor }));
    base.position.y = -0.6;
    g.add(base);
    const under = new THREE.Mesh(new THREE.PlaneGeometry(RINK.width + 4.4, RINK.length + 4.4), new THREE.MeshLambertMaterial({ color: baseColor }));
    under.rotation.x = -Math.PI / 2; under.position.y = -0.62;
    g.add(under);
    // wall
    const wall = new THREE.Mesh(ringGeometry(HW, HL, corner, HW + 0.4, HL + 0.4, corner + 0.4, height), new THREE.MeshLambertMaterial({ color: B.color ?? 0xf8fafc }));
    wall.castShadow = true; wall.receiveShadow = true;
    g.add(wall);
    const rail = new THREE.Mesh(ringGeometry(HW - 0.02, HL - 0.02, corner, HW + 0.42, HL + 0.42, corner + 0.42, 0.12), new THREE.MeshLambertMaterial({ color: B.top ?? 0xfacc15 }));
    rail.position.y = height;
    g.add(rail);
    if (B.glass) {
      const glass = new THREE.Mesh(ringGeometry(HW + 0.05, HL + 0.05, corner, HW + 0.3, HL + 0.3, corner + 0.3, 1.5),
        new THREE.MeshLambertMaterial({ color: 0xbae6fd, transparent: true, opacity: 0.18, depthWrite: false }));
      glass.position.y = height;
      g.add(glass);
      const top = new THREE.Mesh(ringGeometry(HW + 0.02, HL + 0.02, corner, HW + 0.36, HL + 0.36, corner + 0.36, 0.1), new THREE.MeshLambertMaterial({ color: B.top ?? 0x0ea5e9 }));
      top.position.y = height + 1.5;
      g.add(top);
    }
    for (const sgn of [-1, 1]) this.buildGoal(g, sgn, world.goal || {});
  }

  buildGoal(parent, sgn, G) {
    const g = new THREE.Group();
    const gz = sgn * RINK.goalLineZ;
    const hw = RINK.goalWidth / 2, depth = RINK.goalDepth, height = 1.9;
    const postMat = new THREE.MeshToonMaterial({ color: G.post ?? 0xef4444 });
    const post = new THREE.CylinderGeometry(0.13, 0.13, height, 10);
    for (const sx of [-1, 1]) {
      const p = new THREE.Mesh(post, postMat);
      p.position.set(sx * hw, height / 2, gz);
      p.castShadow = true;
      g.add(p);
    }
    const bar = new THREE.Mesh(new THREE.CylinderGeometry(0.12, 0.12, hw * 2 + 0.26, 10), postMat);
    bar.rotation.z = Math.PI / 2;
    bar.position.set(0, height, gz);
    bar.castShadow = true;
    g.add(bar);
    const netColor = G.net ?? 0xffffff;
    const netMat = new THREE.MeshBasicMaterial({ color: netColor, transparent: true, opacity: 0.35, side: THREE.DoubleSide, depthWrite: false });
    const back = new THREE.Mesh(new THREE.PlaneGeometry(hw * 2, height), netMat);
    back.position.set(0, height / 2, gz + sgn * depth);
    g.add(back);
    const top = new THREE.Mesh(new THREE.PlaneGeometry(hw * 2, depth), netMat);
    top.rotation.x = -Math.PI / 2;
    top.position.set(0, height, gz + sgn * depth / 2);
    g.add(top);
    for (const sx of [-1, 1]) {
      const side = new THREE.Mesh(new THREE.PlaneGeometry(depth, height), netMat);
      side.rotation.y = Math.PI / 2;
      side.position.set(sx * hw, height / 2, gz + sgn * depth / 2);
      g.add(side);
    }
    const grid = new THREE.LineSegments(this.netLines(hw, depth, height, gz, sgn), new THREE.LineBasicMaterial({ color: netColor, transparent: true, opacity: 0.55 }));
    g.add(grid);
    parent.add(g);
  }

  netLines(hw, depth, height, gz, sgn) {
    const pts = [];
    const zb = gz + sgn * depth;
    for (let x = -hw; x <= hw + 0.01; x += 0.4) { pts.push(x, 0, zb, x, height, zb); pts.push(x, height, gz, x, height, zb); }
    for (let y = 0; y <= height + 0.01; y += 0.4) { pts.push(-hw, y, zb, hw, y, zb); pts.push(-hw, y, gz, -hw, y, zb); pts.push(hw, y, gz, hw, y, zb); }
    const geo = new THREE.BufferGeometry();
    geo.setAttribute('position', new THREE.Float32BufferAttribute(pts, 3));
    return geo;
  }

  // ---------------------------------------------------------------- ball
  buildBall() {
    if (this.ball) { this.scene.remove(this.ball); this.ball.geometry.dispose(); this.ball.material.dispose(); }
    const isIce = this.sport?.id === 'ice';
    const color = this.world?.ball?.color ?? (isIce ? 0x0f172a : 0xffffff);
    const emissive = this.world?.ball?.emissive ?? 0x000000;
    const r = 0.36;
    this.ball = new THREE.Mesh(
      isIce ? new THREE.CylinderGeometry(r, r, 0.2, 18) : new THREE.SphereGeometry(r, 18, 14),
      new THREE.MeshToonMaterial({ color, emissive }),
    );
    this.ball.castShadow = true;
    this.ball.position.y = isIce ? 0.1 : r;
    this.scene.add(this.ball);
    if (!this.ballGlow) {
      this.ballGlow = new THREE.Mesh(new THREE.CircleGeometry(0.8, 20), new THREE.MeshBasicMaterial({ color: 0xfacc15, transparent: true, opacity: 0.35, depthWrite: false }));
      this.ballGlow.rotation.x = -Math.PI / 2;
      this.ballGlow.position.y = 0.02;
      this.scene.add(this.ballGlow);
      this.trail = [];
      for (let i = 0; i < 12; i++) {
        const t = new THREE.Mesh(new THREE.CircleGeometry(0.3, 12), new THREE.MeshBasicMaterial({ color: 0xfde68a, transparent: true, opacity: 0, depthWrite: false }));
        t.rotation.x = -Math.PI / 2;
        t.position.y = 0.015;
        this.scene.add(t);
        this.trail.push(t);
      }
    }
  }

  buildConfetti() {
    const n = 160;
    this.confetti = new THREE.InstancedMesh(new THREE.BoxGeometry(0.3, 0.07, 0.42), new THREE.MeshLambertMaterial({ color: 0xffffff }), n);
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

  // ---------------------------------------------------------------- aim
  buildAim() {
    this.orbitRing = new THREE.Mesh(new THREE.RingGeometry(ORBIT.radius - 0.05, ORBIT.radius + 0.05, 48),
      new THREE.MeshBasicMaterial({ color: 0xffffff, transparent: true, opacity: 0.5, depthWrite: false, side: THREE.DoubleSide }));
    this.orbitRing.rotation.x = -Math.PI / 2;
    this.orbitRing.position.y = 0.025;
    this.orbitRing.visible = false;
    this.scene.add(this.orbitRing);

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
    this.aimHead.rotation.z = Math.PI;
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
    let len = 6 + power * (this.aimLenMax - 6);
    if (snap?.kind === 'pass') len = Math.hypot(snap.target.x - c.x, snap.target.z - c.z) - ORBIT.radius - 1.6;
    else if (snap?.kind === 'goal') len = Math.hypot(c.x, match.attackGoalZ(c.team) - c.z) - ORBIT.radius - 1.2;
    const dx = Math.sin(match.puck.orbit), dz = Math.cos(match.puck.orbit);
    let toBoards = 0;
    for (let d = 1; d < this.aimLenMax + 2; d += 0.5) {
      if (sdRoundRect(c.x + dx * d, c.z + dz * d, HW, HL, this.corner ?? RINK.corner) > -0.6) break;
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

  updateCamera(match, dt, override) {
    const puck = match.puck;
    const c = this.camParams;
    const wantFocus = clamp(puck.z * 0.85, c.rangeMin, c.rangeMax);
    this.focusZ = lerp(this.focusZ, wantFocus, 1 - Math.exp(-dt * 2.2));
    const pos = this.cameraPosition(this.focusZ);
    const look = new THREE.Vector3(0, 0, this.focusZ + c.look);
    this.fitCamera();
    let fov = this.camera.fov;
    if (override && override.weight > 0.001) {
      const w = override.weight;
      pos.lerp(override.pos, w);
      look.lerp(override.look, w);
      fov = lerp(fov, override.fov, w);
    }
    if (this.shake > 0) {
      pos.x += (Math.random() - 0.5) * this.shake;
      pos.y += (Math.random() - 0.5) * this.shake;
      this.shake = Math.max(0, this.shake - dt * 2.5);
    }
    this.camera.position.copy(pos);
    this.camera.lookAt(look);
    this.camera.fov = fov;
    this.camera.updateProjectionMatrix();
  }

  update(match, dt, override) {
    this.time += dt;
    if (match) {
      this.updateCamera(match, dt, override);
      for (const p of match.players) {
        const m = this.playerMeshes.get(p.id);
        if (!m) continue;
        m.group.position.set(p.x, 0, p.z);
        const sp = Math.hypot(p.vx, p.vz);
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
      const isIce = this.sport?.id === 'ice';
      this.ball.position.set(puck.x, isIce ? 0.1 : 0.36, puck.z);
      if (isIce) this.ball.rotation.y += dt * 4;
      else {
        // roll the ball along its travel direction
        const r = 0.36;
        this.ball.rotation.x += (puck.vz * dt) / r;
        this.ball.rotation.z -= (puck.vx * dt) / r;
      }
      this.ballGlow.position.set(puck.x, 0.02, puck.z);
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
    if (this.sceneryHandle?.update) { try { this.sceneryHandle.update(dt, this.time); } catch (e) { this.sceneryHandle = null; console.error(e); } }
    this.updateConfetti(dt);
    this.renderer.render(this.scene, this.camera);
  }

  // ---------------------------------------------------------------- effects
  celebrate(team, colors, gz) {
    this.shake = 1.2;
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
