/// The pitch's geometry and the small helpers every rule is written in (spec §1, §4.4).
///
/// Every helper evaluates in one fixed order, the order Android's `Pitch.kt` uses too; that order,
/// not merely the formula, is what keeps the two simulations bit-identical. `min`, `max` and
/// `clamp` are spelled out rather than taken from the standard library so a signed zero comes out
/// the same on both platforms.
struct Vec: Sendable, Hashable {
    var x: Double
    var z: Double

    static let zero = Vec(x: 0, z: 0)
}

enum Pitch {
    static let pi = Double.pi
    static let twoPi = 2.0 * Double.pi

    /// `sqrt(x² + z²)` (§4.4).
    static func length(_ x: Double, _ z: Double) -> Double { DetMath.length(x, z) }

    static func distance(_ a: Vec, _ b: Vec) -> Double { DetMath.length(a.x - b.x, a.z - b.z) }

    static func lesser(_ a: Double, _ b: Double) -> Double { b < a ? b : a }
    static func greater(_ a: Double, _ b: Double) -> Double { b > a ? b : a }
    static func clamp(_ v: Double, _ lo: Double, _ hi: Double) -> Double { v < lo ? lo : (v > hi ? hi : v) }

    /// The unit vector along (x, z), or zero when it is shorter than the direction epsilon.
    static func unit(_ x: Double, _ z: Double) -> Vec {
        let l = length(x, z)
        return l > Tuning.Sim.directionEpsilon ? Vec(x: x / l, z: z / l) : .zero
    }

    /// a − b wrapped into [−π, π].
    static func angleDiff(_ a: Double, _ b: Double) -> Double {
        var d = a - b
        while d > pi { d -= twoPi }
        while d < -pi { d += twoPi }
        return d
    }

    /// An angle wrapped into (−π, π].
    static func wrap(_ a: Double) -> Double {
        var w = a
        while w > pi { w -= twoPi }
        while w <= -pi { w += twoPi }
        return w
    }

    /// The direction angle of (x, z): `0` points down +Z (§ Behavior).
    static func heading(_ x: Double, _ z: Double) -> Double { DetMath.atan2(x, z) }

    /// Distance from `p` to the segment a–b.
    static func segmentDistance(_ p: Vec, _ a: Vec, _ b: Vec) -> Double {
        let abx = b.x - a.x
        let abz = b.z - a.z
        let l2 = abx * abx + abz * abz
        var t = 0.0
        if l2 > 0 {
            let dot = (p.x - a.x) * abx + (p.z - a.z) * abz
            t = clamp(dot / l2, 0, 1)
        }
        let cx = a.x + abx * t
        let cz = a.z + abz * t
        return length(p.x - cx, p.z - cz)
    }

    /// The +Z-attacking direction of a team: +1 for team 0, −1 for team 1.
    static func direction(_ team: Int) -> Double { team == 0 ? 1 : -1 }

    /// The goal line a team defends (team 0: −26) and the one it attacks.
    static func ownGoalZ(_ team: Int) -> Double { -direction(team) * Tuning.Pitch.goalLineZ }
    static func attackGoalZ(_ team: Int) -> Double { direction(team) * Tuning.Pitch.goalLineZ }

    /// Pushes a point out of the net `team` defends, by the nearest way out of the three the net has
    /// — its **mouth**, its **back** or one of its **sides** — with the point kept `r` clear of the
    /// cloth. Returns the point untouched when it is already outside.
    ///
    /// This is where a **carried** ball is kept out of the net (§5.1). The loose-ball solver (§6.2)
    /// uses the same frame but not this function, because for a loose ball the mouth is not a way
    /// out: crossing it is the goal test. A carried ball is the other case — the orbit can carry it
    /// over the goal line through the open mouth, which is allowed and is not a goal, so the mouth
    /// is the nearest way out from in there and it has to be one of the three.
    static func pushOutOfNet(_ p: Vec, team: Int, radius r: Double) -> Vec {
        typealias P = Tuning.Pitch
        let gz = ownGoalZ(team)
        let dir = direction(team)
        let hw = P.goalMouthWidth / 2 + P.netFrameMargin + r
        let deep = P.goalDepth + P.netFrameMargin + r
        // How far past the goal line, into the net, the point is.
        let into = -dir * (p.z - gz)
        guard p.x.magnitude < hw && into > -r && into < deep else { return p }
        let outMouth = into + r
        let outBack = deep - into
        let outSide = hw - p.x.magnitude
        let least = lesser(lesser(outMouth, outBack), outSide)
        if least == outSide { return Vec(x: p.x >= 0 ? hw : -hw, z: p.z) }
        if least == outMouth { return Vec(x: p.x, z: gz + dir * r) }
        return Vec(x: p.x, z: gz - dir * deep)
    }

    /// The boundary (§1): signed distance to the rounded rectangle at the half-extents (negative
    /// inside) and its outward normal.
    static func boundary(_ x: Double, _ z: Double, corner: Double) -> (distance: Double, normal: Vec) {
        let qx = x.magnitude - (Tuning.Pitch.halfWidth - corner)
        let qz = z.magnitude - (Tuning.Pitch.halfLength - corner)
        let sx: Double = x >= 0 ? 1 : -1
        let sz: Double = z >= 0 ? 1 : -1
        if qx > 0 && qz > 0 {
            let l = length(qx, qz)
            return (l - corner, Vec(x: sx * (qx / l), z: sz * (qz / l)))
        }
        if qx >= qz { return (qx - corner, Vec(x: sx, z: 0)) }
        return (qz - corner, Vec(x: 0, z: sz))
    }

    /// The nine face-off spots (§1): the centre, then the neutral and the end spots.
    static let faceOffSpots: [Spot] = [Tuning.Pitch.faceoffCenter] + Tuning.Pitch.faceoffNeutral + Tuning.Pitch.faceoffEnd
}
