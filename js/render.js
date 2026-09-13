import * as THREE from '../vendor/three.module.js';
import { RINK, PLAYER, FACEOFF_SPOTS } from './config.js';
import { clamp, lerp, sdRoundRect, rand, pick } from './math.js';

const HW = RINK.width / 2;
const HL = RINK.length / 2;

const PASTELS = ['#f9a8d4', '#a5b4fc', '#fcd34d', '#86efac', '#fda4af', '#93c5fd', '#fdba74', '#c4b5fd', '#f8fafc', '#5eead4'];

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

function cylinderBetween(a, b, radius, material) {
  const dir = new THREE.Vector3().subVectors(b, a);
  const len = dir.length();
  const geo = new THREE.CylinderGeometry(radius, radius, len, 8);
  const m = new THREE.Mesh(geo, material);
  m.position.copy(a).addScaledVector(dir, 0.5);
  m.quaternion.setFromUnitVectors(new THREE.Vector3(0, 1, 0), dir.normalize());
  m.castShadow = true;
  return m;
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
    this.camParams = { y: 25, back: 22, look: 8, nearZ: 10, range: 15, minFov: 45, maxFov: 78 };
    this.raycaster = new THREE.Raycaster();
    this.plane = new THREE.Plane(new THREE.Vector3(0, 1, 0), 0);
    this.playerMeshes = new Map();
    this.effects = [];
    this.time = 0;

    this.buildLights();
    this.buildRink();
    this.buildStands();
    this.buildPuck();
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

    // floor slab under everything
    const slab = new THREE.Mesh(
      new THREE.BoxGeometry(RINK.width + 40, 3, RINK.length + 40),
      new THREE.MeshLambertMaterial({ color: 0x1e293b }),
    );
    slab.position.y = -1.55;
    slab.receiveShadow = true;
    this.scene.add(slab);

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

  buildStands() {
    const group = new THREE.Group();
    const crowdPos = [];
    const tiers = 5;
    for (let i = 0; i < tiers; i++) {
      const inner = 1.6 + i * 2.4;
      const outer = inner + 2.5;
      const base = 0.2 + i * 1.35;
      const h = 1.35;
      const geo = ringGeometry(HW + inner, HL + inner, RINK.corner + inner, HW + outer, HL + outer, RINK.corner + outer, h);
      const color = new THREE.Color(PASTELS[(i * 3) % PASTELS.length]).multiplyScalar(0.75);
      const m = new THREE.Mesh(geo, new THREE.MeshLambertMaterial({ color }));
      m.position.y = base;
      m.receiveShadow = true;
      group.add(m);
      // crowd sample positions on this tier
      const count = 220 + i * 40;
      let tries = 0, placed = 0;
      while (placed < count && tries < 8000) {
        tries++;
        const x = rand(-(HW + outer), HW + outer);
        const z = rand(-(HL + outer), HL + outer);
        const sdI = sdRoundRect(x, z, HW + inner + 0.6, HL + inner + 0.6, RINK.corner + inner + 0.6);
        const sdO = sdRoundRect(x, z, HW + outer - 0.6, HL + outer - 0.6, RINK.corner + outer - 0.6);
        if (sdI > 0 && sdO < 0) { crowdPos.push({ x, y: base + h + 0.45, z }); placed++; }
      }
    }
    this.scene.add(group);

    const geo = new THREE.SphereGeometry(0.45, 6, 5);
    const mat = new THREE.MeshLambertMaterial({ color: 0xffffff });
    const crowd = new THREE.InstancedMesh(geo, mat, crowdPos.length);
    const dummy = new THREE.Object3D();
    const col = new THREE.Color();
    crowdPos.forEach((c, i) => {
      dummy.position.set(c.x, c.y, c.z);
      dummy.scale.setScalar(rand(0.8, 1.2));
      dummy.updateMatrix();
      crowd.setMatrixAt(i, dummy.matrix);
      crowd.setColorAt(i, col.set(pick(PASTELS)));
    });
    crowd.instanceMatrix.needsUpdate = true;
    this.crowd = crowd;
    this.crowdPos = crowdPos;
    this.crowdExcite = 0;
    this.scene.add(crowd);
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
    const primary = new THREE.Color(team.primary);
    const secondary = new THREE.Color(team.secondary);
    const isG = p.role === 'G';
    const bodyMat = new THREE.MeshToonMaterial({ color: primary });
    const secMat = new THREE.MeshToonMaterial({ color: secondary });
    const dark = new THREE.MeshToonMaterial({ color: 0x1e293b });
    const skin = new THREE.MeshToonMaterial({ color: 0xfcd5b5 });

    const body = new THREE.Mesh(new THREE.CapsuleGeometry(isG ? 0.8 : 0.62, isG ? 0.8 : 0.85, 4, 14), bodyMat);
    body.position.y = isG ? 1.05 : 1.08;
    body.castShadow = true;
    group.add(body);
    // stripe
    const stripe = new THREE.Mesh(new THREE.CylinderGeometry(isG ? 0.83 : 0.65, isG ? 0.83 : 0.65, 0.22, 16, 1, true), secMat);
    stripe.position.y = 1.25;
    group.add(stripe);
    // shoulders / arms
    for (const sx of [-1, 1]) {
      const arm = new THREE.Mesh(new THREE.CapsuleGeometry(0.2, 0.55, 3, 8), bodyMat);
      arm.position.set(sx * (isG ? 0.95 : 0.75), 1.15, 0.1);
      arm.rotation.z = sx * 0.35;
      arm.castShadow = true;
      group.add(arm);
      const glove = new THREE.Mesh(new THREE.SphereGeometry(0.22, 8, 8), secMat);
      glove.position.set(sx * (isG ? 1.05 : 0.85), 0.8, 0.25);
      group.add(glove);
    }
    // head + helmet
    const head = new THREE.Mesh(new THREE.SphereGeometry(0.42, 12, 12), skin);
    head.position.y = isG ? 2.05 : 2.02;
    group.add(head);
    const helmet = new THREE.Mesh(new THREE.SphereGeometry(0.48, 14, 10, 0, Math.PI * 2, 0, Math.PI * 0.6), secMat);
    helmet.position.y = head.position.y + 0.02;
    helmet.castShadow = true;
    group.add(helmet);
    if (isG) {
      const cage = new THREE.Mesh(new THREE.SphereGeometry(0.5, 10, 8, 0, Math.PI * 2, Math.PI * 0.35, Math.PI * 0.4), new THREE.MeshToonMaterial({ color: 0xffffff, wireframe: true }));
      cage.position.y = head.position.y;
      group.add(cage);
      // leg pads
      for (const sx of [-1, 1]) {
        const pad = new THREE.Mesh(new THREE.BoxGeometry(0.5, 1.0, 0.45), secMat);
        pad.position.set(sx * 0.42, 0.5, 0.15);
        pad.castShadow = true;
        group.add(pad);
      }
    } else {
      for (const sx of [-1, 1]) {
        const leg = new THREE.Mesh(new THREE.CapsuleGeometry(0.2, 0.4, 3, 8), dark);
        leg.position.set(sx * 0.3, 0.42, 0);
        group.add(leg);
      }
    }
    // skates
    for (const sx of [-1, 1]) {
      const skate = new THREE.Mesh(new THREE.BoxGeometry(0.22, 0.12, 0.6), new THREE.MeshToonMaterial({ color: 0xe2e8f0 }));
      skate.position.set(sx * 0.32, 0.06, 0.05);
      group.add(skate);
    }
    // stick: from the right glove down to the ice in front
    const stickMat = new THREE.MeshToonMaterial({ color: 0xd97706 });
    const hand = new THREE.Vector3(0.6, 0.85, 0.35);
    const bladeStart = new THREE.Vector3(0.1, 0.06, PLAYER.carryOffset - 0.15);
    group.add(cylinderBetween(hand, bladeStart, 0.05, stickMat));
    const blade = new THREE.Mesh(new THREE.BoxGeometry(0.55, 0.12, 0.13), dark);
    blade.position.set(bladeStart.x - 0.1, 0.06, bladeStart.z + 0.05);
    blade.rotation.y = 0.25;
    group.add(blade);

    // control ring + carrier marker under the feet
    const ring = new THREE.Mesh(new THREE.RingGeometry(0.95, 1.2, 28), new THREE.MeshBasicMaterial({ color: 0xfacc15, transparent: true, opacity: 0.9, depthWrite: false, side: THREE.DoubleSide }));
    ring.rotation.x = -Math.PI / 2;
    ring.position.y = 0.03;
    ring.visible = false;
    group.add(ring);
    const shadowDisc = new THREE.Mesh(new THREE.CircleGeometry(0.95, 20), new THREE.MeshBasicMaterial({ color: primary, transparent: true, opacity: 0.25, depthWrite: false }));
    shadowDisc.rotation.x = -Math.PI / 2;
    shadowDisc.position.y = 0.02;
    group.add(shadowDisc);

    return { group, body, ring, disc: shadowDisc, bob: Math.random() * 6 };
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
    const wantFocus = clamp(puck.z * 0.85, -c.range, c.range);
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
        m.group.rotation.y = p.facing;
        const sp = Math.hypot(p.vx, p.vz);
        m.group.rotation.x = clamp(sp * 0.03, 0, 0.3);
        m.body.position.y = (p.role === 'G' ? 1.05 : 1.08) + Math.sin(this.time * 10 + m.bob) * sp * 0.006;
        m.ring.visible = p.controlled != null;
        if (m.ring.visible) m.ring.scale.setScalar(1 + Math.sin(this.time * 8) * 0.06);
        m.disc.material.opacity = match.puck.carrier === p ? 0.6 : 0.22;
      }
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
    this.updateCrowd(dt);
    this.renderer.render(this.scene, this.camera);
  }

  // ---------------------------------------------------------------- effects
  celebrate(team, colors, gz) {
    this.shake = 1.4;
    this.crowdExcite = 2.5;
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

  updateCrowd(dt) {
    if (this.crowdExcite <= 0) return;
    this.crowdExcite -= dt;
    const dummy = new THREE.Object3D();
    const amp = Math.min(1, this.crowdExcite) * 0.6;
    this.crowdPos.forEach((c, i) => {
      dummy.position.set(c.x, c.y + Math.abs(Math.sin(this.time * 9 + i)) * amp, c.z);
      dummy.updateMatrix();
      this.crowd.setMatrixAt(i, dummy.matrix);
    });
    this.crowd.instanceMatrix.needsUpdate = true;
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
