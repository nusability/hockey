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
    private var dots: [ModelEntity] = []
    private let mouth: ModelEntity
    private let strip: ModelEntity
    private var chevron: ShaderGraphMaterial
    private var glowMaterial: ShaderGraphMaterial
    private var headGlowMaterial: ShaderGraphMaterial
    private var mouthMaterial: ShaderGraphMaterial
    private var stripMaterial: ShaderGraphMaterial
    private let corner: Double
    private let params = AimArrow.Params(maxLength: A.maxLength, minLength: A.minLength, passShort: A.passShort,
                                         shotShort: A.shotShort, boardMargin: A.boardMargin, boardProbe: A.boardProbe,
                                         probeStep: A.probeStep)
    /// The snap being shown, and real seconds since it began (the lock-on's fade).
    private var snap: MatchSnapshot.Aim?
    private var snapAge = 0.0
    private var kindShown = -1
    private var dotsOpacity = -1.0

    init(sport: Sport, feel: FeelMaterials.Set) throws {
        corner = sport.cornerRadius
        chevron = feel.chevron
        FeelMaterials.set(&chevron, "Near", A.ribbonNear)
        FeelMaterials.set(&chevron, "Far", A.ribbonFar)
        glowMaterial = feel.glow
        headGlowMaterial = feel.glow
        mouthMaterial = feel.glow
        stripMaterial = feel.glow
        FeelMaterials.colour(&mouthMaterial, A.shot)
        FeelMaterials.colour(&stripMaterial, A.shot)
        let sort = ModelSortGroup(depthPass: nil)
        func model(_ kit: MeshKit, _ m: RealityKit.Material, order: Int32) throws -> ModelEntity {
            let e = ModelEntity(mesh: try kit.resource(), materials: [m])
            e.components.set(ModelSortGroupComponent(group: sort, order: order))
            return e
        }
        glow = try model(Self.ribbon(A.glowNear, A.glowFar), glowMaterial, order: 0)
        ribbon = try model(Self.ribbon(A.ribbonNear, A.ribbonFar), chevron, order: 1)
        headGlow = try model(Self.head(), headGlowMaterial, order: 2)
        head = try model(Self.head(), Materials.flat(A.free, opacity: A.opacityFree), order: 3)
        let start = Float(Tuning.Orbit.radius + A.start)
        glow.position = [0, Float(A.lift) - 0.005, start]
        ribbon.position = [0, Float(A.lift), start]
        for e in [glow, ribbon, headGlow, head] { arrow.addChild(e) }
        root.addChild(arrow)

        typealias P = Presentation.Player
        let rr = Float(Tuning.Player.outfieldRadius)
        target = try model(Shapes.ring(inner: rr + Float(P.targetInner), outer: rr + Float(P.targetOuter), segments: 32),
                           Materials.flat(P.target, opacity: P.targetOpacity), order: 0)
        root.addChild(target)
        var disc = MeshKit()
        disc.disc(radius: Float(L.dot) / 2, y: 0, segments: 12)
        let dotMesh = try disc.resource()
        for _ in 0..<40 {
            let d = ModelEntity(mesh: dotMesh, materials: [Materials.flat(A.pass, opacity: L.dotOpacity)])
            d.isEnabled = false
            root.addChild(d)
            dots.append(d)
        }
        let half = Float(Tuning.Pitch.goalMouthWidth / 2)
        var sheet = MeshKit()
        sheet.quad([-half, 0, 0], [half, 0, 0], [half, Float(L.mouthHeight), 0], [-half, Float(L.mouthHeight), 0])
        mouth = try model(sheet, mouthMaterial, order: 0)
        var ground = MeshKit()
        ground.quad([-half, 0, 0], [-half, 0, 1], [half, 0, 1], [half, 0, 0])
        strip = try model(ground, stripMaterial, order: 0)
        for e in [mouth, strip] { root.addChild(e) }
        hide()
    }

    /// A tapered strip: z from 0 to 1, `near` wide at its start and `far` at its end (12 segments).
    static func ribbon(_ near: Double, _ far: Double) -> MeshKit {
        var k = MeshKit()
        let n = 12
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

    private func hide() {
        arrow.isEnabled = false
        target.isEnabled = false
        mouth.isEnabled = false
        strip.isEnabled = false
        for d in dots { d.isEnabled = false }
        snap = nil
    }

    /// One frame: `positions` are the players' drawn positions, `angle` the drawn orbit angle,
    /// `clock` real seconds (the pulses), `dt` this frame's real seconds.
    func update(_ s: MatchSnapshot, positions: [SIMD2<Double>], angle: Double, clock: Double, dt: Double) {
        guard s.playerCarrier, let c = s.ball.carrier, let aim = s.aim, s.state == .play || s.state == .ready else {
            hide()
            return
        }
        let me = positions[c]
        let team = s.players[c].team
        let goalZ = team == 0 ? Tuning.Pitch.goalLineZ : -Tuning.Pitch.goalLineZ
        var kind = AimArrow.Kind.free
        var colour = 0
        switch aim {
        case .pass(let m): kind = .pass(x: positions[m].x, z: positions[m].y); colour = 1
        case .shot: kind = .shot(goalZ: goalZ); colour = 2
        case .unassisted: break
        }
        let len = AimArrow.length(kind, x: me.x, z: me.y, angle: angle, corner: corner, params)
        let snapped = colour != 0
        if aim != snap { snap = aim; snapAge = 0 } else { snapAge += dt }
        let fade = snapped ? min(1, snapAge / L.fadeIn) : 0

        // The arrow.
        arrow.isEnabled = true
        root.position = SIMD3(Float(me.x), 0, Float(me.y))
        root.orientation = simd_quatf(angle: 0, axis: [0, 1, 0])
        arrow.orientation = simd_quatf(angle: Float(angle), axis: [0, 1, 0])
        let rgb = [A.free, A.pass, A.shot][colour]
        if colour != kindShown {
            kindShown = colour
            FeelMaterials.colour(&chevron, rgb)
            FeelMaterials.colour(&glowMaterial, rgb)
            FeelMaterials.colour(&headGlowMaterial, rgb)
        }
        let opacity = snapped ? A.opacitySnapped + sin(clock * A.pulseRate) * A.pulse : A.opacityFree
        FeelMaterials.set(&chevron, "Opacity", opacity)
        FeelMaterials.set(&chevron, "Repeat", len / A.chevron)
        FeelMaterials.set(&glowMaterial, "Opacity", snapped ? A.glowSnapped : A.glowFree)
        FeelMaterials.set(&headGlowMaterial, "Opacity", snapped ? A.headGlowSnapped : A.headGlowFree)
        ribbon.model?.materials = [chevron]
        glow.model?.materials = [glowMaterial]
        headGlow.model?.materials = [headGlowMaterial]
        head.model?.materials = [Materials.flat(rgb, opacity: opacity)]
        let w = Float(A.width), l = Float(len), start = Float(Tuning.Orbit.radius + A.start)
        ribbon.scale = [w, 1, l]
        glow.scale = [w, 1, l]
        let hs = Float(A.headScale)
        head.position = [0, Float(A.lift) + 0.005, start + l]
        head.scale = SIMD3(repeating: hs)
        headGlow.position = [0, Float(A.lift) - 0.005, start + l]
        headGlow.scale = SIMD3(repeating: hs * Float(A.headGlow))

        // The lock-on marker, in the pitch's frame (undo the carrier's offset).
        let dir = SIMD2(sin(angle), cos(angle))
        target.isEnabled = false
        mouth.isEnabled = false
        strip.isEnabled = false
        var dotsWanted = 0
        switch aim {
        case .pass(let m):
            typealias P = Presentation.Player
            let r = positions[m]
            target.isEnabled = true
            target.position = local(r, y: 0.03, me)
            target.scale = SIMD3(repeating: Float(1 + sin(clock * P.targetPulseRate) * P.targetPulse))
            target.model?.materials = [Materials.flat(P.target, opacity: P.targetOpacity * fade)]
            let p = s.players[m]
            let d = simd_distance(r, me)
            let o = Tuning.Orbit.self
            let t = d / max(o.leadSpeedMin, o.leadSpeedBase + o.leadSpeedPerMetre * d)
            let lead = r + o.leadVelocityFactor * SIMD2(p.vx, p.vz) * t
            let tip = me + dir * (Tuning.Orbit.radius + A.start + len + A.head[1] * A.headScale)
            let span = simd_distance(lead, tip)
            let count = min(dots.count, Int(span / L.dotGap))
            let step = count > 0 ? (lead - tip) / Double(count) : .zero
            for i in 0..<count {
                dots[i].isEnabled = true
                dots[i].position = local(tip + step * (Double(i) + 0.5), y: Float(A.lift), me)
            }
            dotsWanted = count
            let o2 = (L.dotOpacity * fade * 50).rounded() / 50
            if o2 != dotsOpacity {
                dotsOpacity = o2
                let mat = Materials.flat(A.pass, opacity: max(o2, 0.001))
                for d in dots { d.model?.materials = [mat] }
            }
        case .shot:
            let breathe = 1 + L.mouthPulse * sin(clock * A.pulseRate)
            mouth.isEnabled = true
            mouth.position = local(SIMD2(0, goalZ), y: 0, me)
            FeelMaterials.set(&mouthMaterial, "Opacity", L.mouthOpacity * fade * breathe)
            mouth.model?.materials = [mouthMaterial]
            strip.isEnabled = true
            strip.position = local(SIMD2(0, goalZ), y: Float(A.lift) - 0.01, me)
            strip.scale = [1, 1, Float(-(goalZ > 0 ? 1 : -1) * L.mouthDepth)]
            FeelMaterials.set(&stripMaterial, "Opacity", L.stripOpacity * fade * breathe)
            strip.model?.materials = [stripMaterial]
        case .unassisted:
            break
        }
        for i in dotsWanted..<dots.count { dots[i].isEnabled = false }
    }

    /// A pitch point in the root's frame (the root stands on the carrier, unturned).
    private func local(_ p: SIMD2<Double>, y: Float, _ origin: SIMD2<Double>) -> SIMD3<Float> {
        SIMD3(Float(p.x - origin.x), y, Float(p.y - origin.y))
    }
}
