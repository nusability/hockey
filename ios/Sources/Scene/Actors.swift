import RealityKit
import SmashCore
import simd

/// A side's kit colours, sRGB 0xRRGGBB.
struct TeamColours: Equatable {
    var primary: UInt32
    var secondary: UInt32
}

/// Everything that moves in a match, drawn from its snapshot (spec §5, §8): the twelve players as
/// the prototype's disks (ADR 0006), the ball or puck, the orbit ring and the aim line (§5.2). The
/// twin of Android's Actors.kt.
///
/// Between ticks it extrapolates by at most one tick (`ahead`, match seconds) along the snapshot's
/// velocities — drawing only; the simulation is advanced by the core's tick clock alone (§4.2).
@MainActor
final class Actors {
    typealias P = Presentation.Player
    let root = Entity()
    private var players: [Entity] = []
    private var shadows: [(entity: ModelEntity, rest: UnlitMaterial, carrier: UnlitMaterial)] = []
    private var carrierShown: Int?
    private let ball: ModelEntity
    private let ballDisc: ModelEntity
    private let orbit: ModelEntity
    private let aim: ModelEntity
    private let arrow: ModelEntity
    private let target: ModelEntity
    private let aimColours: [UnlitMaterial]     // pass, shot, free
    private var aimKind = -1
    private let omega: Double

    init(first s: MatchSnapshot, colours: [TeamColours], sport: Sport, orbitPeriod: Double,
         materials: Materials, look: WorldLook) throws {
        omega = 2 * .pi / orbitPeriod
        typealias D = Presentation.Dummy
        var meshes: [String: MeshResource] = [:]
        func mesh(_ key: String, _ kit: @autoclosure () -> MeshKit) throws -> MeshResource {
            if let m = meshes[key] { return m }
            let m = try kit().resource()
            meshes[key] = m
            return m
        }
        func model(_ mesh: MeshResource, _ material: RealityKit.Material) -> ModelEntity {
            ModelEntity(mesh: mesh, materials: [material])
        }

        for p in s.players {
            let r = Float(p.radius)
            let group = Entity()
            let dummy = p.role == .dummy
            let primary = dummy ? D.body : colours[p.team].primary
            let secondary = dummy ? D.stripe : colours[p.team].secondary
            let h = Float(dummy ? D.height : P.height)
            group.addChild(model(try mesh("body\(r)/\(h)", Shapes.body(radius: r, height: h)),
                                 try materials.toon(primary, look: look)))
            switch p.role {
            case .goalie:
                group.addChild(model(try mesh("ring\(r)", Shapes.goalieRing(radius: r, height: h)), Materials.flat(secondary)))
            case .dummy:
                group.addChild(model(try mesh("stripe\(r)", Shapes.stripe(radius: r)), try materials.toon(secondary, look: look)))
            case .defender, .forward:
                group.addChild(model(try mesh("dot\(r)", Shapes.dot(radius: r, height: h)), Materials.flat(secondary)))
            }
            let rest = Materials.flat(primary, opacity: P.shadowOpacity)
            let shadow = model(try mesh("shadow\(r)", Shapes.shadow(radius: r)), rest)
            group.addChild(shadow)
            shadows.append((shadow, rest, Materials.flat(primary, opacity: P.carrierShadowOpacity)))
            root.addChild(group)
            players.append(group)
        }

        typealias B = Presentation.Ball
        let r = Float(s.ball.radius)
        if sport == .ice {
            ball = model(try Shapes.puck(radius: r, height: Float(B.puckHeight)).resource(), try materials.toon(B.ice, look: look))
        } else {
            ball = model(try Shapes.ball(radius: r).resource(), try materials.toon(B.field, look: look))
        }
        ballDisc = model(try Shapes.disc().resource(), Materials.flat(B.disc, opacity: B.discOpacity))
        ballDisc.scale = SIMD3(repeating: Float(B.discRadius))
        root.addChild(ballDisc)
        root.addChild(ball)

        typealias A = Presentation.Aim
        func mark(_ kit: MeshKit, _ m: UnlitMaterial) throws -> ModelEntity {
            let e = ModelEntity(mesh: try kit.resource(), materials: [m])
            e.isEnabled = false
            return e
        }
        let orbitRadius = Float(Tuning.Orbit.radius), half = Float(A.orbitWidth) / 2
        orbit = try mark(Shapes.ring(inner: orbitRadius - half, outer: orbitRadius + half, segments: 48),
                         Materials.flat(A.orbit, opacity: A.orbitOpacity))
        aimColours = [A.pass, A.shot, A.free].map { Materials.flat($0, opacity: A.opacity) }
        aim = try mark(Shapes.strip(), aimColours[0])
        arrow = try mark(Shapes.arrowhead(), aimColours[0])
        let rr = Float(Tuning.Player.outfieldRadius)
        target = try mark(Shapes.ring(inner: rr + Float(P.targetInner), outer: rr + Float(P.targetOuter), segments: 32),
                          Materials.flat(P.target, opacity: P.targetOpacity))
        for e in [orbit, aim, arrow, target] { root.addChild(e) }
    }

    /// Draws snapshot `s`, `ahead` match seconds past its tick (0 ≤ ahead < one tick).
    /// `celebrating` is the team that just scored, whose players hop on real time `clock`.
    func update(_ s: MatchSnapshot, ahead: Double, celebrating: Int?, clock: Double) {
        var positions: [SIMD2<Double>] = []
        for (i, p) in s.players.enumerated() {
            let pos = SIMD2(p.x + p.vx * ahead, p.z + p.vz * ahead)
            positions.append(pos)
            var y: Float = 0
            if let team = celebrating, team == p.team, p.role != .dummy {
                y = Float(P.hop * abs(sin(clock * P.hopRate + Double(i) * 0.9)))
            }
            let e = players[i]
            e.position = SIMD3(Float(pos.x), y, Float(pos.y))
            // A running player leans into its run, as the prototype's did.
            let speed = (p.vx * p.vx + p.vz * p.vz).squareRoot()
            let lean = speed > 0.5 ? min(speed * P.lean, P.maxLean) : 0
            let pitch = speed > 0.5 ? Float(p.vz / speed * lean) : 0, roll = speed > 0.5 ? Float(-p.vx / speed * lean) : 0
            e.orientation = simd_quatf(angle: pitch, axis: [1, 0, 0]) * simd_quatf(angle: roll, axis: [0, 0, 1])
        }

        // The disc under the carrier darkens.
        let carrier = s.ball.carrier
        if carrier != carrierShown {
            if let old = carrierShown { shadows[old].entity.model?.materials = [shadows[old].rest] }
            if let c = carrier { shadows[c].entity.model?.materials = [shadows[c].carrier] }
            carrierShown = carrier
        }

        // The ball: on its orbit round the carrier (§5.1), else where it rolls.
        let b = s.ball
        var ballPos = SIMD2(b.x + b.vx * ahead, b.z + b.vz * ahead)
        var angle = b.orbit
        if let c = b.carrier {
            angle += b.orbitDirection * omega * ahead
            ballPos = positions[c] + Tuning.Orbit.radius * SIMD2(sin(angle), cos(angle))
            orbit.position = SIMD3(Float(positions[c].x), 0.025, Float(positions[c].y))
        }
        ball.position = SIMD3(Float(ballPos.x), 0, Float(ballPos.y))
        orbit.isEnabled = b.carrier != nil
        ballDisc.position = SIMD3(Float(ballPos.x), 0.02, Float(ballPos.y))
        drawAim(s, positions: positions, ball: ballPos, angle: angle, clock: clock)
    }

    /// The aim line (§5.2): from the ball toward where a release now would go, coloured by what it
    /// would snap to — a pass (with the green ring under the receiver), a shot, or nothing.
    private func drawAim(_ s: MatchSnapshot, positions: [SIMD2<Double>], ball: SIMD2<Double>, angle: Double, clock: Double) {
        typealias A = Presentation.Aim
        guard s.playerCarrier, let c = s.ball.carrier, let kind = s.aim, s.state == .play || s.state == .ready else {
            aim.isEnabled = false; arrow.isEnabled = false; target.isEnabled = false
            return
        }
        let me = positions[c]
        var end: SIMD2<Double>
        var colour = 2
        target.isEnabled = false
        switch kind {
        case .pass(let m):
            let p = s.players[m]
            let d = simd_distance(positions[m], me)
            let t = d / max(Tuning.Orbit.leadSpeedMin, Tuning.Orbit.leadSpeedBase + Tuning.Orbit.leadSpeedPerMetre * d)
            let lead = positions[m] + Tuning.Orbit.leadVelocityFactor * SIMD2(p.vx, p.vz) * t
            end = ball + simd_normalize(lead - me) * simd_distance(lead, ball)
            colour = 0
            target.isEnabled = true
            target.position = SIMD3(Float(positions[m].x), 0.03, Float(positions[m].y))
            target.scale = SIMD3(repeating: Float(1 + sin(clock * P.targetPulseRate) * P.targetPulse))
        case .shot:
            let goal = SIMD2(0.0, s.players[c].team == 0 ? Tuning.Pitch.goalLineZ : -Tuning.Pitch.goalLineZ)
            end = ball + simd_normalize(goal - me) * simd_distance(goal, ball)
            colour = 1
        case .unassisted:
            end = ball + A.freeLength * SIMD2(sin(angle), cos(angle))
        }
        if colour != aimKind {
            aimKind = colour
            for e in [aim, arrow] { e.model?.materials = [aimColours[colour]] }
        }
        let v = end - ball
        let length = Float(simd_length(v))
        let head = min(Float(A.width) * 3, length * 0.5)
        let yaw = simd_quatf(angle: Float(atan2(v.x, v.y)), axis: [0, 1, 0])
        let start = SIMD3(Float(ball.x), 0.07, Float(ball.y))
        let dir = SIMD3(Float(v.x), 0, Float(v.y)) / max(length, 1e-4)
        aim.isEnabled = true
        aim.position = start
        aim.orientation = yaw
        aim.scale = SIMD3(Float(A.width), 1, max(length - head, 0.01))
        arrow.isEnabled = true
        arrow.position = start + dir * (length - head)
        arrow.orientation = yaw
        arrow.scale = SIMD3(Float(A.width) * 2.6, 1, head)
    }
}
