import RealityKit
import SmashCore
import simd

/// The aim arrow and the lock-on marker (spec §5.2) — the prototype's arrow exactly, for the
/// player's own carrier only. Anchored at the carrier's centre and turned by the orbit angle, it
/// points out through the ball, never at the target: a tapered ribbon printed with scrolling
/// chevrons over an additive glow, a notched arrowhead over its glow; its length and colour say
/// what a release now would snap to (core `AimArrow`). When a snap begins the lock-on fades in:
/// for a pass the receiver's pulsing ring and a dotted line to where the pass would go, for a shot
/// a glow across the goal mouth. The twin of Android's AimArrow.kt.
///
/// The three meshes whose shape changes every frame — the chevron ribbon, the receiver's ring and
/// the dotted line — are written **in pitch coordinates**, on entities that never move, as the
/// ball's trail is. A mesh written in place carries its own bounds and the renderer culls the
/// entity against them, so bounds in a frame that moves with the carrier go stale and the arrow
/// stops being drawn once it has travelled (SMASH-24's follow-up: it drew in one half only). One
/// fixed box round the whole pitch — core `AimArrow.extent`, which a test walks every carrier and
/// every direction against — cannot go stale, because neither it nor its entity moves.
@MainActor
final class AimArrowView {
    typealias A = Presentation.Aim
    typealias L = Presentation.Aim.Lock
    let root = Entity()
    private let arrow = Entity()
    private let ribbon: ModelEntity
    private let glow: ModelEntity
    private let head: ModelEntity
    private let headGlow: ModelEntity
    private let target: ModelEntity
    private let dotted: ModelEntity
    private let mouth: ModelEntity
    private let strip: ModelEntity
    private var chevron: ShaderGraphMaterial
    private var glowMaterial: ShaderGraphMaterial
    private var headMaterial: ShaderGraphMaterial
    private var headGlowMaterial: ShaderGraphMaterial
    private var mouthMaterial: ShaderGraphMaterial
    private var stripMaterial: ShaderGraphMaterial
    private var targetMaterial: ShaderGraphMaterial
    private var dotMaterial: ShaderGraphMaterial
    /// The receiver's ring and the dotted line: their vertices carry the lock-on's fade, so neither
    /// is handed a material while it fades (SMASH-24).
    private let targetMesh: DynamicMesh
    private let dotsMesh: DynamicMesh
    private let corner: Double
    private let params = AimArrow.Params(maxLength: A.maxLength, minLength: A.minLength, passShort: A.passShort,
                                         shotShort: A.shotShort, boardMargin: A.boardMargin, boardProbe: A.boardProbe,
                                         probeStep: A.probeStep)
    /// What the arrow shows, decided by the core's state machine (both apps share the rules).
    private var showing = AimArrow.Showing()
    /// What each material currently says, so a material is written only when that changes.
    private var kindShown = -1
    private var mouthFade = -1.0
    /// The ribbon's vertices, rewritten in place each frame (no resource is built).
    private let ribbonMesh: DynamicMesh

    init(sport: Sport, feel: FeelMaterials.Set) throws {
        corner = sport.cornerRadius
        chevron = feel.chevron
        glowMaterial = feel.glow
        headGlowMaterial = feel.glow
        mouthMaterial = feel.glow
        stripMaterial = feel.glow
        headMaterial = feel.flat
        targetMaterial = feel.trail
        dotMaterial = feel.trail
        FeelMaterials.colour(&mouthMaterial, A.shot)
        FeelMaterials.colour(&stripMaterial, A.shot)
        FeelMaterials.colour(&headMaterial, A.free)
        FeelMaterials.set(&headMaterial, "Opacity", A.opacityFree)
        FeelMaterials.colour(&targetMaterial, Presentation.Player.target)
        FeelMaterials.set(&targetMaterial, "Opacity", Presentation.Player.targetOpacity)
        FeelMaterials.colour(&dotMaterial, A.pass)
        FeelMaterials.set(&dotMaterial, "Opacity", L.dotOpacity)
        func model(_ kit: MeshKit, _ m: RealityKit.Material, order: Int32) throws -> ModelEntity {
            let e = ModelEntity(mesh: try kit.resource(), materials: [m])
            DrawOrder.set(e, order)
            return e
        }
        glow = try model(Self.ribbon(A.glowNear, A.glowFar), glowMaterial, order: DrawOrder.arrowGlow)
        // The chevron ribbon is the one part whose shape changes every frame, so it is a low-level
        // mesh written in place — as the ball's trail is — rather than a scaled one whose chevron
        // count would have to be told to its material (SMASH-24).
        var strips: [UInt16] = []
        for i in 0..<Self.ribbonSteps {
            let a = UInt16(2 * i)
            strips += [a, a + 1, a + 2, a + 1, a + 3, a + 2]
        }
        ribbonMesh = try DynamicMesh(vertexCount: 2 * (Self.ribbonSteps + 1), triangles: strips,
                                     bounds: Self.pitchBounds)
        ribbon = ModelEntity(mesh: ribbonMesh.resource, materials: [chevron])
        DrawOrder.set(ribbon, DrawOrder.arrow)
        headGlow = try model(Self.head(), headGlowMaterial, order: DrawOrder.headGlow)
        head = try model(Self.head(), headMaterial, order: DrawOrder.head)
        let start = Float(Tuning.Orbit.radius + A.start)
        glow.position = [0, Float(A.lift) - 0.005, start]
        for e in [glow, headGlow, head] { arrow.addChild(e) }
        root.addChild(arrow)
        root.addChild(ribbon)

        var ringTris: [UInt16] = []
        for i in 0..<Self.ringSteps {
            let a = UInt16(2 * i)
            ringTris += [a, a + 1, a + 2, a + 1, a + 3, a + 2]
        }
        targetMesh = try DynamicMesh(vertexCount: 2 * (Self.ringSteps + 1), triangles: ringTris,
                                     bounds: Self.pitchBounds)
        target = ModelEntity(mesh: targetMesh.resource, materials: [targetMaterial])
        DrawOrder.set(target, DrawOrder.lock)
        root.addChild(target)
        // One mesh for all the dots, not one entity each: the line is redrawn into its vertices.
        var dotTris: [UInt16] = []
        for d in 0..<Self.dotCount {
            let base = UInt16(d * (Self.dotSteps + 1))
            for i in 0..<Self.dotSteps {
                dotTris += [base, base + UInt16(1 + i), base + UInt16(1 + (i + 1) % Self.dotSteps)]
            }
        }
        dotsMesh = try DynamicMesh(vertexCount: Self.dotCount * (Self.dotSteps + 1), triangles: dotTris,
                                   bounds: Self.pitchBounds)
        dotted = ModelEntity(mesh: dotsMesh.resource, materials: [dotMaterial])
        DrawOrder.set(dotted, DrawOrder.lock)
        root.addChild(dotted)
        let half = Float(Tuning.Pitch.goalMouthWidth / 2)
        var sheet = MeshKit()
        sheet.quad([-half, 0, 0], [half, 0, 0], [half, Float(L.mouthHeight), 0], [-half, Float(L.mouthHeight), 0])
        mouth = try model(sheet, mouthMaterial, order: DrawOrder.lock)
        var ground = MeshKit()
        ground.quad([-half, 0, 0], [-half, 0, 1], [half, 0, 1], [half, 0, 0])
        strip = try model(ground, stripMaterial, order: DrawOrder.lock)
        for e in [mouth, strip] { root.addChild(e) }
        hide()
    }

    /// What the arrow spreads over, for the box its written meshes are bounded by. `lock` is the
    /// furthest the lock-on ever draws from the team-mate it marks: a lead point is
    /// `lead_velocity_factor` × the player's velocity × the pass's flight, which no outfielder can
    /// push past 9.5 m, and the pulsing ring is nearer than that.
    static let drawing = AimArrow.Drawing(start: Tuning.Orbit.radius + A.start,
                                          across: max(A.width * max(A.ribbonNear, A.ribbonFar) / 2,
                                                      A.head[2] * A.headScale),
                                          head: A.head[1] * A.headScale, lock: 9.5)

    /// The pitch grown by the arrow's reach — every vertex any of the three meshes ever holds.
    static var pitchBounds: BoundingBox {
        let e = AimArrow.extent(AimArrow.Params(maxLength: A.maxLength, minLength: A.minLength, passShort: A.passShort,
                                                shotShort: A.shotShort, boardMargin: A.boardMargin,
                                                boardProbe: A.boardProbe, probeStep: A.probeStep), drawing)
        return BoundingBox(min: [Float(-e.x), -1, Float(-e.z)], max: [Float(e.x), 1, Float(e.z)])
    }

    /// How many dots the line can hold, and the facets of one dot and of the receiver's ring.
    static let dotCount = 40
    static let dotSteps = 12
    static let ringSteps = 32

    /// Redraws the receiver's ring with the lock-on's `fade` in every vertex's `u` — the shader
    /// multiplies its opacity by it (the Trail graph), so fading costs no material.
    private func writeRing(at centre: SIMD2<Double>, scale: Float, fade: Float) {
        typealias P = Presentation.Player
        let rr = Float(Tuning.Player.outfieldRadius)
        let inner = (rr + Float(P.targetInner)) * scale, outer = (rr + Float(P.targetOuter)) * scale
        let (cx, cz) = (Float(centre.x), Float(centre.y))
        let n = Self.ringSteps
        targetMesh.write { v in
            for i in 0...n {
                let a = Float(i) / Float(n) * 2 * .pi
                let (s, c) = (sin(a), cos(a))
                v[2 * i] = .init(position: [cx + inner * s, 0.03, cz + inner * c], uv: [fade, 0])
                v[2 * i + 1] = .init(position: [cx + outer * s, 0.03, cz + outer * c], uv: [fade, 1])
            }
        }
    }

    /// Redraws the dotted line: `count` discs at `at(i)`, the rest collapsed to a point so they
    /// cover nothing. `fade` rides in `u`, as the ring's does.
    private func writeDots(count: Int, fade: Float, home: SIMD3<Float>, at: (Int) -> SIMD3<Float>) {
        let r = Float(L.dot) / 2
        let n = Self.dotSteps
        dotsMesh.write { v in
            for d in 0..<Self.dotCount {
                let base = d * (n + 1)
                let centre = d < count ? at(d) : home
                let size = d < count ? r : 0
                v[base] = .init(position: centre, uv: [fade, 0])
                for i in 0..<n {
                    let a = Float(i) / Float(n) * 2 * .pi
                    v[base + 1 + i] = .init(position: centre + [size * sin(a), 0, size * cos(a)], uv: [fade, 0])
                }
            }
        }
    }

    /// Segments along a ribbon, the chevron one and the glow under it alike.
    static let ribbonSteps = 12

    /// Rewrites the chevron ribbon `len` metres long: `u` is metres from its start (the chevrons are
    /// printed from it), `v` runs 0…1 across it, and the taper is in the vertices.
    private func writeRibbon(from me: SIMD2<Double>, angle: Double, length len: Float) {
        let n = Self.ribbonSteps
        let w = Float(A.width)
        let (sa, ca) = (Float(sin(angle)), Float(cos(angle)))
        let (ox, oz) = (Float(me.x), Float(me.y))
        let lift = Float(A.lift), start = Float(Tuning.Orbit.radius + A.start)
        // (across, along) in the aim's frame, put down on the pitch.
        func at(_ across: Float, _ along: Float) -> SIMD3<Float> {
            [ox + across * ca + along * sa, lift, oz - across * sa + along * ca]
        }
        ribbonMesh.write { v in
            for i in 0...n {
                let t = Float(i) / Float(n)
                let half = Float(A.ribbonNear + (A.ribbonFar - A.ribbonNear) * Double(t)) / 2 * w
                let u = len * t
                v[2 * i] = .init(position: at(-half, start + u), uv: [u, 0])
                v[2 * i + 1] = .init(position: at(half, start + u), uv: [u, 1])
            }
        }
    }

    /// A tapered strip: z from 0 to 1, `near` wide at its start and `far` at its end (12 segments).
    static func ribbon(_ near: Double, _ far: Double) -> MeshKit {
        var k = MeshKit()
        let n = ribbonSteps
        for i in 0..<n {
            let t0 = Float(i) / Float(n), t1 = Float(i + 1) / Float(n)
            let h0 = Float(near + (far - near) * Double(t0)) / 2, h1 = Float(near + (far - near) * Double(t1)) / 2
            k.quad([-h0, 0, t0], [-h1, 0, t1], [h1, 0, t1], [h0, 0, t0])
        }
        return k
    }

    /// The notched arrowhead: the outline `head` (tip, wing, notch; the other wing mirrored), pointing down +Z.
    static func head() -> MeshKit {
        let h = A.head.map(Float.init)
        let tip = SIMD3<Float>(h[0], 0, h[1]), wing = SIMD3<Float>(h[2], 0, h[3]), notch = SIMD3<Float>(h[4], 0, h[5])
        var k = MeshKit()
        k.triangle(tip, notch, wing)
        k.triangle(tip, [-wing.x, 0, wing.z], notch)
        return k
    }

    /// Hands `m` to `e` — one more material the renderer takes ownership of (`Diagnostics`).
    private func paint(_ e: ModelEntity, _ m: ShaderGraphMaterial) {
        e.model?.materials = [m]
        Diagnostics.materialWritten()
    }

    private func hide() {
        arrow.isEnabled = false
        ribbon.isEnabled = false
        target.isEnabled = false
        mouth.isEnabled = false
        strip.isEnabled = false
        dotted.isEnabled = false
    }

    /// One frame: `positions` are the players' drawn positions, `angle` the drawn orbit angle,
    /// `clock` real seconds (the pulses and the lock-on's fade).
    func update(_ s: MatchSnapshot, positions: [SIMD2<Double>], angle: Double, clock: Double) {
        let look = showing.frame(state: s.state, playerCarrier: s.playerCarrier, carrier: s.ball.carrier,
                                 aim: s.aim, clock: clock, fadeIn: L.fadeIn)
        guard look.arrow, let c = s.ball.carrier, let aim = s.aim else {
            hide()
            Diagnostics.second(clock) { "arrow=off state=\(s.state) mine=\(s.playerCarrier) carrier=\(String(describing: s.ball.carrier))" }
            return
        }
        let me = positions[c]
        let team = s.players[c].team
        let goalZ = team == 0 ? Tuning.Pitch.goalLineZ : -Tuning.Pitch.goalLineZ
        var kind = AimArrow.Kind.free
        switch aim {
        case .pass(let m): kind = .pass(x: positions[m].x, z: positions[m].y)
        case .shot: kind = .shot(goalZ: goalZ)
        case .unassisted: break
        }
        let len = AimArrow.length(kind, x: me.x, z: me.y, angle: angle, corner: corner, params)
        let colour = look.colour, snapped = look.snapped, fade = look.fade

        // The arrow.
        arrow.isEnabled = true
        ribbon.isEnabled = true
        // The root stands at the pitch's origin: only the parts drawn from a static mesh are moved
        // onto the carrier, and the three written in place carry the carrier in their vertices.
        arrow.position = SIMD3(Float(me.x), 0, Float(me.y))
        arrow.orientation = simd_quatf(angle: Float(angle), axis: [0, 1, 0])
        // Colour and the pulse are all these four materials say, and both follow `colour` alone —
        // the beat itself runs in the shader — so on every other frame nothing is handed to the
        // renderer (SMASH-24: a material written per frame is never given back).
        if colour != kindShown {
            kindShown = colour
            let rgb = [A.free, A.pass, A.shot][colour]
            let lit = snapped ? A.opacitySnapped : A.opacityFree
            let beat = snapped ? A.pulse / A.opacitySnapped : 0
            FeelMaterials.colour(&chevron, rgb)
            FeelMaterials.opacity(&chevron, lit, pulse: beat, rate: A.pulseRate)
            paint(ribbon, chevron)
            FeelMaterials.colour(&glowMaterial, rgb)
            FeelMaterials.opacity(&glowMaterial, snapped ? A.glowSnapped : A.glowFree)
            paint(glow, glowMaterial)
            FeelMaterials.colour(&headGlowMaterial, rgb)
            FeelMaterials.opacity(&headGlowMaterial, snapped ? A.headGlowSnapped : A.headGlowFree)
            paint(headGlow, headGlowMaterial)
            FeelMaterials.colour(&headMaterial, rgb)
            FeelMaterials.opacity(&headMaterial, lit, pulse: beat, rate: A.pulseRate)
            paint(head, headMaterial)
        }
        let w = Float(A.width), l = Float(len), start = Float(Tuning.Orbit.radius + A.start)
        // The ribbon's length is written into its vertices, not into its material: the chevrons are
        // printed from its texture coordinates (u in metres), so nothing about it is a resource.
        writeRibbon(from: me, angle: angle, length: l)
        glow.scale = [w, 1, l]
        let hs = Float(A.headScale)
        head.position = [0, Float(A.lift) + 0.005, start + l]
        head.scale = SIMD3(repeating: hs)
        headGlow.position = [0, Float(A.lift) - 0.005, start + l]
        headGlow.scale = SIMD3(repeating: hs * Float(A.headGlow))

        // The lock-on marker, drawn in the pitch's frame like the ribbon.
        let dir = SIMD2(sin(angle), cos(angle))
        target.isEnabled = false
        dotted.isEnabled = false
        mouth.isEnabled = false
        strip.isEnabled = false
        var dotsWanted = 0
        switch aim {
        case .pass(let m):
            typealias P = Presentation.Player
            let r = positions[m]
            target.isEnabled = true
            writeRing(at: r, scale: Float(1 + sin(clock * P.targetPulseRate) * P.targetPulse), fade: Float(fade))
            let p = s.players[m]
            let d = simd_distance(r, me)
            let o = Tuning.Orbit.self
            let t = d / max(o.leadSpeedMin, o.leadSpeedBase + o.leadSpeedPerMetre * d)
            let lead = r + o.leadVelocityFactor * SIMD2(p.vx, p.vz) * t
            let tip = me + dir * (Tuning.Orbit.radius + A.start + len + A.head[1] * A.headScale)
            let span = simd_distance(lead, tip)
            let count = min(Self.dotCount, Int(span / L.dotGap))
            let step = count > 0 ? (lead - tip) / Double(count) : .zero
            dotted.isEnabled = count > 0
            writeDots(count: count, fade: Float(fade), home: SIMD3(Float(me.x), Float(A.lift), Float(me.y))) { i in
                let q = tip + step * (Double(i) + 0.5)
                return SIMD3(Float(q.x), Float(A.lift), Float(q.y))
            }
            dotsWanted = count
        case .shot:
            mouth.isEnabled = true
            mouth.position = [0, 0, Float(goalZ)]
            strip.isEnabled = true
            strip.position = [0, Float(A.lift) - 0.01, Float(goalZ)]
            // The strip lies from the line back toward the play. It is turned round rather than
            // scaled by a negative, as Android's is: a mirrored scale leaves the renderer an
            // inside-out box to bound and sort the part by.
            strip.orientation = simd_quatf(angle: goalZ > 0 ? .pi : 0, axis: [0, 1, 0])
            strip.scale = [1, 1, Float(L.mouthDepth)]
            // Only the fade is ours — the breathing is the shader's — so the two materials are
            // written over the 0.08 s a snap fades in and never again while it stands.
            let f = (fade * 50).rounded() / 50
            if f != mouthFade {
                mouthFade = f
                FeelMaterials.opacity(&mouthMaterial, L.mouthOpacity * f, pulse: L.mouthPulse, rate: A.pulseRate)
                paint(mouth, mouthMaterial)
                FeelMaterials.opacity(&stripMaterial, L.stripOpacity * f, pulse: L.mouthPulse, rate: A.pulseRate)
                paint(strip, stripMaterial)
            }
        case .unassisted:
            break
        }
        Diagnostics.second(clock) {
            "arrow=on enabled=\(arrow.isEnabled) colour=\(colour) len=\(String(format: "%.2f", len)) "
                + "fade=\(String(format: "%.2f", fade)) parts=\(root.children.count) dots=\(dotsWanted)"
        }
    }
}
