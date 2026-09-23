import Foundation

/// The goal nets (spec §8.8): their shape, their cloth sway, a goal's ripple — and the box that
/// holds every vertex an app can ever write for them.
///
/// The net is the **apps'** (ADR 0008): a world's asset carries the goal frame — the two posts and
/// the crossbar — and nothing else, so that the whole net moves rather than a faint film swaying
/// behind cords baked into the scenery. Both apps build the same four sheets per goal from here and
/// move every one of their points by the same two formulas, so the nets are the same cloth on both
/// platforms. The Android twin is `core/feel/GoalNet.kt`.
public enum GoalNet {
    /// `presentation.toml [net]` and `[net.sway]`, handed in by the app that draws it.
    public struct Params: Sendable, Hashable {
        /// The net's height — the goal frame's (§1).
        public var height: Double
        /// Cells across the mouth, up the back and the sides, and along the goal's depth.
        public var columns: Int, rows: Int, depth: Int
        /// A cord's width, and how far it stands off its film so the two never fight.
        public var cord: Double, cordLift: Double
        /// The cloth: how far a sheet's middle sways, over how many seconds, with how much phase per
        /// metre of pitch, and what Reduce Motion keeps of it.
        public var sway: Double, swaySeconds: Double, wave: Double, calm: Double
        /// A goal's ripple: its amplitude, its decay, its frequency, its wave number, how far it
        /// reaches from the strike and how long it runs.
        public var ripple: Double, decay: Double, frequency: Double, k: Double, reach: Double, seconds: Double

        public init(height: Double, columns: Int, rows: Int, depth: Int, cord: Double, cordLift: Double,
                    sway: Double, swaySeconds: Double, wave: Double, calm: Double, ripple: Double,
                    decay: Double, frequency: Double, k: Double, reach: Double, seconds: Double) {
            self.height = height
            self.columns = columns
            self.rows = rows
            self.depth = depth
            self.cord = cord
            self.cordLift = cordLift
            self.sway = sway
            self.swaySeconds = swaySeconds
            self.wave = wave
            self.calm = calm
            self.ripple = ripple
            self.decay = decay
            self.frequency = frequency
            self.k = k
            self.reach = reach
            self.seconds = seconds
        }
    }

    /// A point in the game's frame (metres): x across, y up, z along.
    public struct Point: Sendable, Hashable {
        public var x: Double, y: Double, z: Double
        public init(_ x: Double, _ y: Double, _ z: Double) { (self.x, self.y, self.z) = (x, y, z) }
        public static func + (a: Point, b: Point) -> Point { Point(a.x + b.x, a.y + b.y, a.z + b.z) }
        public static func * (a: Point, s: Double) -> Point { Point(a.x * s, a.y * s, a.z * s) }
    }

    /// One sheet of a net: a grid of `columns` × `rows` cells spanning `origin + u·across + v·up`,
    /// swaying along its outward `normal`. `across` and `up` are the sheet's full edges.
    public struct Sheet: Sendable, Hashable {
        public var origin: Point, across: Point, up: Point, normal: Point
        public var columns: Int, rows: Int

        /// The resting point at grid node (i, j), 0 ≤ i ≤ columns, 0 ≤ j ≤ rows.
        public func point(_ i: Int, _ j: Int) -> Point {
            origin + across * (Double(i) / Double(columns)) + up * (Double(j) / Double(rows))
        }

        /// How freely that node may sway: 0 where the net is laced to its frame or to the next
        /// sheet, 1 in the middle — `sin(π·u)·sin(π·v)`. An edge is exactly 0, not `sin(π)`'s
        /// rounding: the sheets share those nodes and have to hold them at exactly the same place.
        public func bell(_ i: Int, _ j: Int) -> Double {
            guard i > 0, i < columns, j > 0, j < rows else { return 0 }
            return sin(.pi * Double(i) / Double(columns)) * sin(.pi * Double(j) / Double(rows))
        }

        /// The unit vector across the sheet's `across` edge, and across its `up` edge: what a cord
        /// running the other way is made wide by.
        public var acrossUnit: Point { unit(across) }
        public var upUnit: Point { unit(up) }

        private func unit(_ p: Point) -> Point {
            let len = (p.x * p.x + p.y * p.y + p.z * p.z).squareRoot()
            return len > 0 ? p * (1 / len) : p
        }
    }

    /// The four sheets of the goal behind the goal line on the `sign` side (−1 is the player's own
    /// end): the back, the roof and the two sides. Every sheet's edge sits where the net is laced —
    /// to the frame, to the ground or to the next sheet — so the four move as one skin.
    public static func sheets(_ sign: Double, _ p: Params) -> [Sheet] {
        let hw = Tuning.Pitch.goalMouthWidth / 2, h = p.height
        let line = sign * Tuning.Pitch.goalLineZ, back = sign * (Tuning.Pitch.goalLineZ + Tuning.Pitch.goalDepth)
        let deep = back - line
        var out = [
            // The back: across the mouth, up from the ground, facing away from the pitch.
            Sheet(origin: Point(-hw, 0, back), across: Point(2 * hw, 0, 0), up: Point(0, h, 0),
                  normal: Point(0, 0, sign), columns: p.columns, rows: p.rows),
            // The roof: across the mouth, from the crossbar back, facing up.
            Sheet(origin: Point(-hw, h, line), across: Point(2 * hw, 0, 0), up: Point(0, 0, deep),
                  normal: Point(0, 1, 0), columns: p.columns, rows: p.depth),
        ]
        for sx in [Double(-1), 1] {
            // A side: from the post back, up from the ground, facing out across the pitch.
            out.append(Sheet(origin: Point(sx * hw, 0, line), across: Point(0, 0, deep), up: Point(0, h, 0),
                             normal: Point(sx, 0, 0), columns: p.depth, rows: p.rows))
        }
        return out
    }

    /// How far the node at (`x`, `y`, `z`) stands off its sheet at real time `t`: the cloth's sway,
    /// and a goal's ripple on top of it. `age` is the real seconds since the ball struck at
    /// (`strikeX`, `strikeY`, `strikeZ`) — negative, or past `seconds`, for a net that is only
    /// breathing. Reduce Motion keeps `calm` of the sway — calmer, never frozen. Scalars, not
    /// points: this runs for every vertex of both nets on every frame, on both platforms.
    public static func offset(x: Double, y: Double, z: Double, bell: Double, t: Double, reduceMotion: Bool,
                              strikeX: Double, strikeY: Double, strikeZ: Double, age: Double,
                              _ p: Params) -> Double {
        let amplitude = p.sway * (reduceMotion ? p.calm : 1)
        var d = amplitude * bell * sin(2 * .pi * t / p.swaySeconds + p.wave * (x + z))
        if age >= 0, age < p.seconds {
            let (dx, dy, dz) = (x - strikeX, y - strikeY, z - strikeZ)
            let distance = (dx * dx + dy * dy + dz * dz).squareRoot()
            d += p.ripple * exp(-p.decay * age) * sin(p.frequency * age - p.k * distance)
                * exp(-distance / p.reach)
        }
        return d
    }

    /// Where a goal's ripple starts: the middle of the back sheet's height, at the ball's x across
    /// the mouth, on the goal line `goalZ` names.
    public static func strike(goalZ: Double, ballX: Double, _ p: Params) -> Point {
        let hw = Tuning.Pitch.goalMouthWidth / 2
        let sign = goalZ > 0 ? 1.0 : -1.0
        return Point(min(max(ballX, -hw), hw), 0.36, sign * (Tuning.Pitch.goalLineZ + Tuning.Pitch.goalDepth))
    }

    /// How far off its sheet any point can ever be pushed: the sway at full stretch, a fresh goal's
    /// ripple, and the cord that stands off the film and is half its own width wide.
    public static func reach(_ p: Params) -> Double {
        p.sway + p.ripple + p.cordLift + p.cord / 2
    }

    /// The box in the game's frame holding **every** vertex an app writes for both nets — the four
    /// sheets of each goal, their films and their cords, at every moment of the sway and of a
    /// goal's ripple. It exists because a mesh written in place carries its own bounds and the
    /// renderer culls the entity against them (SMASH-33): the nets are written in the pitch's frame
    /// on entities that never move, so this box can never go stale.
    public static func extent(_ p: Params) -> (x: Double, yLow: Double, yHigh: Double, z: Double) {
        let r = reach(p)
        return (Tuning.Pitch.goalMouthWidth / 2 + r, -r, p.height + r,
                Tuning.Pitch.goalLineZ + Tuning.Pitch.goalDepth + r)
    }
}
