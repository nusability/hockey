import RealityKit
import SmashCore
import simd

/// A side's kit colours, sRGB 0xRRGGBB.
struct TeamColours: Equatable {
    var primary: UInt32
    var secondary: UInt32
}

/// Everything that moves in a match, drawn from its snapshot (spec §5, §8): the twelve toys, the
/// ball or puck, the orbit ring and the aim line (§5.2). The twin of Android's Actors.kt.
///
/// Between ticks it extrapolates by at most one tick (`ahead`, match seconds) along the snapshot's
/// velocities — drawing only; the simulation is advanced by the core's tick clock alone (§4.2).
@MainActor
final class Actors {
    let root = Entity()
    private var figures: [ModelEntity] = []
    private let ball: ModelEntity
    private let orbit: ModelEntity
    private let aim: ModelEntity
    private let arrow: ModelEntity
    private let target: ModelEntity
    private let aimColours: [CustomMaterial]     // pass, shot, free
    private var aimKind = -1
    private let omega: Double

    init(first s: MatchSnapshot, colours: [TeamColours], sport: Sport, orbitPeriod: Double,
         materials: Materials, look: WorldLook) throws {
        omega = 2 * .pi / orbitPeriod
        typealias F = Presentation.Figure
        func slots(_ kit: MeshKit, _ colours: [Int: UInt32]) throws -> [RealityKit.Material] {
            try kit.usedSlots.map { try materials.actor(colours[$0]!, look: look) }
        }
        let outfield = Figures.outfield(), goalie = Figures.goalie()
        let dummy = Figures.dummy(height: Float(Presentation.Dummy.height))
        let meshes = (outfield: try outfield.resource(), goalie: try goalie.resource(), dummy: try dummy.resource())
        var palettes: [[Int: UInt32]] = []
        for c in colours {
            palettes.append([Figures.Slot.primary: c.primary, Figures.Slot.secondary: c.secondary,
                             Figures.Slot.skin: F.skin, Figures.Slot.stick: F.stick, Figures.Slot.dark: F.eye])
        }
        let teamMaterials = try palettes.map { (outfield: try slots(outfield, $0), goalie: try slots(goalie, $0)) }
        let dummyMaterials = try slots(dummy, [Figures.Slot.primary: Presentation.Dummy.cone,
                                               Figures.Slot.secondary: Presentation.Dummy.stripe,
                                               Figures.Slot.dark: Presentation.Dummy.base])
        for p in s.players {
            let e: ModelEntity
            switch p.role {
            case .goalie:
                e = ModelEntity(mesh: meshes.goalie, materials: teamMaterials[p.team].goalie)
                e.scale = SIMD3(repeating: Float(F.scale * F.goalieScale))
            case .dummy:
                e = ModelEntity(mesh: meshes.dummy, materials: dummyMaterials)
            case .defender, .forward:
                e = ModelEntity(mesh: meshes.outfield, materials: teamMaterials[p.team].outfield)
                e.scale = SIMD3(repeating: Float(F.scale))
            }
            root.addChild(e)
            figures.append(e)
        }

        let r = Float(s.ball.radius)
        if sport == .ice {
            ball = ModelEntity(mesh: try Figures.puck(radius: r, height: Float(Presentation.Ball.puckHeight)).resource(),
                               materials: [try materials.actor(Presentation.Ball.ice, look: look)])
        } else {
            ball = ModelEntity(mesh: try Figures.ball(radius: r).resource(),
                               materials: [try materials.actor(Presentation.Ball.field, look: look)])
        }
        root.addChild(ball)

        typealias A = Presentation.Aim
        func mark(_ kit: MeshKit, _ m: CustomMaterial) throws -> ModelEntity {
            let e = ModelEntity(mesh: try kit.resource(), materials: [m])
            e.components.set(DynamicLightShadowComponent(castsShadow: false))
            e.isEnabled = false
            return e
        }
        let orbitRadius = Float(Tuning.Orbit.radius)
        orbit = try mark(Figures.ring(width: Float(A.orbitWidth) / orbitRadius),
                         try materials.overlay(A.orbit, opacity: A.orbitOpacity, look: look))
        orbit.scale = SIMD3(orbitRadius, 1, orbitRadius)
        aimColours = try [A.pass, A.shot, A.free].map { try materials.overlay($0, opacity: A.opacity, look: look) }
        aim = try mark(Figures.strip(), aimColours[0])
        arrow = try mark(Figures.arrowhead(), aimColours[0])
        target = try mark(Figures.ring(width: 0.16), aimColours[0])
        for e in [orbit, aim, arrow, target] { root.addChild(e) }
    }

    /// Draws snapshot `s`, `ahead` match seconds past its tick (0 ≤ ahead < one tick).
    /// `celebrating` is the team that just scored, whose toys hop on real time `clock`.
    func update(_ s: MatchSnapshot, ahead: Double, celebrating: Int?, clock: Double) {
        typealias F = Presentation.Figure
        var positions: [SIMD2<Double>] = []
        for (i, p) in s.players.enumerated() {
            let pos = SIMD2(p.x + p.vx * ahead, p.z + p.vz * ahead)
            positions.append(pos)
            var y: Float = 0
            if let team = celebrating, team == p.team, p.role != .dummy {
                y = Float(F.hop * abs(sin(clock * F.hopRate + Double(i) * 0.9)))
            }
            let e = figures[i]
            e.position = SIMD3(Float(pos.x), y, Float(pos.y))
            e.orientation = simd_quatf(angle: Float(p.facing), axis: [0, 1, 0])
        }

        // The ball: on its orbit round the carrier (§5.1), else where it rolls.
        let b = s.ball
        var ballPos = SIMD2(b.x + b.vx * ahead, b.z + b.vz * ahead)
        var angle = b.orbit
        if let c = b.carrier {
            angle += b.orbitDirection * omega * ahead
            ballPos = positions[c] + Tuning.Orbit.radius * SIMD2(sin(angle), cos(angle))
            orbit.position = SIMD3(Float(positions[c].x), 0.04, Float(positions[c].y))
        }
        ball.position = SIMD3(Float(ballPos.x), 0, Float(ballPos.y))
        orbit.isEnabled = b.carrier != nil
        drawAim(s, positions: positions, ball: ballPos, angle: angle)
    }

    /// The aim line (§5.2): from the ball toward where a release now would go, coloured by what it
    /// would snap to — a pass (with a ring under the receiver), a shot, or nothing.
    private func drawAim(_ s: MatchSnapshot, positions: [SIMD2<Double>], ball: SIMD2<Double>, angle: Double) {
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
            target.position = SIMD3(Float(positions[m].x), 0.05, Float(positions[m].y))
            target.scale = SIMD3(repeating: Float(A.targetRing))
        case .shot:
            let goal = SIMD2(0.0, s.players[c].team == 0 ? Tuning.Pitch.goalLineZ : -Tuning.Pitch.goalLineZ)
            end = ball + simd_normalize(goal - me) * simd_distance(goal, ball)
            colour = 1
        case .unassisted:
            end = ball + A.freeLength * SIMD2(sin(angle), cos(angle))
        }
        if colour != aimKind {
            aimKind = colour
            for e in [aim, arrow, target] { e.model?.materials = [aimColours[colour]] }
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
