import RealityKit
import SmashCore
import simd

/// A side's kit colours, sRGB 0xRRGGBB.
struct TeamColours: Equatable {
    var primary: UInt32
    var secondary: UInt32
}

/// Everything that moves in a match, drawn from its snapshot (spec §5, §8): the twelve players as
/// the prototype's disks (ADR 0006), the ball or puck (rolling or spinning, with its trail), the
/// orbit ring and the aim arrow round the player's carrier (§5.2). The twin of Android's Actors.kt.
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
    private let aim: AimArrowView
    private let trail: BallTrail
    private var spin = BallSpin()
    private let isPuck: Bool
    private let omega: Double

    init(first s: MatchSnapshot, colours: [TeamColours], sport: Sport, orbitPeriod: Double,
         materials: Materials, feel: FeelMaterials.Set, look: WorldLook) throws {
        omega = 2 * .pi / orbitPeriod
        isPuck = sport == .ice
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
        if isPuck {
            ball = model(try Shapes.puck(radius: r, height: Float(B.puckHeight)).resource(), try materials.toon(B.ice, look: look))
        } else {
            ball = model(try Shapes.ball(radius: r).resource(), try materials.toon(B.field, look: look))
        }
        ballDisc = model(try Shapes.disc().resource(), Materials.flat(B.disc, opacity: B.discOpacity))
        ballDisc.scale = SIMD3(repeating: Float(B.discRadius))
        root.addChild(ballDisc)
        root.addChild(ball)

        typealias A = Presentation.Aim
        let orbitRadius = Float(Tuning.Orbit.radius), half = Float(A.orbitWidth) / 2
        orbit = model(try Shapes.ring(inner: orbitRadius - half, outer: orbitRadius + half, segments: 48).resource(),
                      Materials.flat(A.orbit, opacity: A.orbitOpacity))
        orbit.isEnabled = false
        aim = try AimArrowView(sport: sport, feel: feel)
        trail = try BallTrail(ballRadius: s.ball.radius, feel: feel)
        for e in [orbit, aim.root, trail.entity] { root.addChild(e) }
    }

    /// Draws snapshot `s`, `ahead` match seconds past its tick (0 ≤ ahead < one tick), `dt` real
    /// seconds after the last frame. `celebrating` is the team that just scored, whose players hop on
    /// real time `clock`.
    func update(_ s: MatchSnapshot, ahead: Double, dt: Double, celebrating: Int?, clock: Double) {
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

        // The ball: on its orbit round the carrier (§5.1), else where it rolls; it turns as it goes.
        let b = s.ball
        var ballPos = SIMD2(b.x + b.vx * ahead, b.z + b.vz * ahead)
        var angle = b.orbit
        if let c = b.carrier {
            angle += b.orbitDirection * omega * ahead
            ballPos = positions[c] + Tuning.Orbit.radius * SIMD2(sin(angle), cos(angle))
            orbit.position = SIMD3(Float(positions[c].x), 0.025, Float(positions[c].y))
        }
        ball.position = SIMD3(Float(ballPos.x), isPuck ? 0 : Float(b.radius), Float(ballPos.y))
        ball.orientation = spin.advance(to: ballPos, radius: b.radius, puck: isPuck, realDt: dt)
        // The ring the ball circles on: only round the player's own carrier (§5.2).
        orbit.isEnabled = b.carrier != nil && s.playerCarrier && (s.state == .play || s.state == .ready)
        ballDisc.position = SIMD3(Float(ballPos.x), 0.02, Float(ballPos.y))
        trail.update(ball: ballPos, time: s.time + ahead, loose: b.carrier == nil,
                     speed: (b.vx * b.vx + b.vz * b.vz).squareRoot())
        aim.update(s, positions: positions, angle: angle, clock: clock, dt: dt)
    }
}
