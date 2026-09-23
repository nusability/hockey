import Foundation

/// The goal nets (spec §8.8): their shape, their cloth sway, the ripple the ball knocks into them —
/// and the box that holds every vertex an app can ever write for them.
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
        /// A contact's ripple: the dent a ball at full speed makes, its decay, its frequency, its
        /// wave number, how far it reaches from the contact and how long it runs.
        public var ripple: Double, decay: Double, frequency: Double, k: Double, reach: Double, seconds: Double
        /// The speed **into** a sheet that dents it the full `ripple`, and the least speed the cloth
        /// answers at all — below it the ball is leaning on the net, not striking it.
        public var hitSpeed: Double, hitLeast: Double

        public init(height: Double, columns: Int, rows: Int, depth: Int, cord: Double, cordLift: Double,
                    sway: Double, swaySeconds: Double, wave: Double, calm: Double, ripple: Double,
                    decay: Double, frequency: Double, k: Double, reach: Double, seconds: Double,
                    hitSpeed: Double, hitLeast: Double) {
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
            self.hitSpeed = hitSpeed
            self.hitLeast = hitLeast
        }
    }

    /// A point in the game's frame (metres): x across, y up, z along.
    public struct Point: Sendable, Hashable {
        public var x: Double, y: Double, z: Double
        public init(_ x: Double, _ y: Double, _ z: Double) { (self.x, self.y, self.z) = (x, y, z) }
        public static func + (a: Point, b: Point) -> Point { Point(a.x + b.x, a.y + b.y, a.z + b.z) }
        public static func - (a: Point, b: Point) -> Point { Point(a.x - b.x, a.y - b.y, a.z - b.z) }
        public static func * (a: Point, s: Double) -> Point { Point(a.x * s, a.y * s, a.z * s) }
        public func dot(_ b: Point) -> Double { x * b.x + y * b.y + z * b.z }
        public var length: Double { dot(self).squareRoot() }
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

    // MARK: what the ball does to the cloth

    /// The ball meeting a net: which goal (0 is the −z end, 1 the +z end), which of that goal's
    /// `sheets` it struck, where on it, how fast it was going **into** the sheet, and what share of a
    /// full-speed dent that is.
    public struct Touch: Sendable, Hashable {
        public var goal: Int, sheet: Int
        public var point: Point
        public var speed: Double, strength: Double

        public init(goal: Int, sheet: Int, point: Point, speed: Double, strength: Double) {
            (self.goal, self.sheet, self.point, self.speed, self.strength) = (goal, sheet, point, speed, strength)
        }
    }

    /// Where the ball meets the cloth over one frame of the match: its place and velocity at the
    /// frame's start, and how many **match** seconds the frame ran for.
    ///
    /// §6.2 resolves the collision itself — the net is solid, the ball is pushed out and bounced —
    /// and does it per tick, twice a frame, so by the time an app reads the snapshot the ball has
    /// already left the cloth. So this sweeps the ball along the path it *would* have taken had
    /// nothing stopped it and asks where that path first reaches a sheet: the same answer the
    /// physics gave, a frame later and in the app's own hands. It answers on the **rising edge** —
    /// the frame the path first reaches a sheet the ball was not already standing on — so a shot
    /// into the side netting, a rebound off the back from inside and a goal are each one contact,
    /// and a ball leaning on the net is none. `ballY` is the height the app draws the ball's centre
    /// at; a ball on the ice can only ever reach the back and the sides, and the roof is written the
    /// same way for the day it can. Nil when the ball misses, or when it is only brushing the net
    /// slower than `hitLeast`.
    public static func touch(x: Double, z: Double, vx: Double, vz: Double, seconds: Double,
                             ballY: Double, radius: Double, _ p: Params) -> Touch? {
        guard seconds > 0 else { return nil }
        // The net's cloth is drawn on the goal frame's own lines, while §6.2 holds the ball off a
        // box `netFrameMargin` outside it — so a ball resting against the net sits that much proud
        // of its sheet. The band a ball counts as touching a sheet in is that gap on the outside and
        // its own radius on the inside.
        let slack = radius + Tuning.Pitch.netFrameMargin
        let from = Point(x, ballY, z), free = Point(x + vx * seconds, ballY, z + vz * seconds)
        var best: (when: Double, touch: Touch)?
        for (goal, sign) in [Double(-1), 1].enumerated() {
            guard max(sign * z, sign * free.z) > Tuning.Pitch.goalLineZ - slack else { continue }
            for (index, sheet) in sheets(sign, p).enumerated() {
                let s0 = (from - sheet.origin).dot(sheet.normal)
                let s1 = (free - sheet.origin).dot(sheet.normal)
                if s0 >= -radius, s0 <= slack { continue }         // already on this sheet
                guard min(s0, s1) <= slack, max(s0, s1) >= -radius else { continue }
                // Where along the path the ball's surface first meets the sheet: from outside that
                // is the band's outer edge, from inside it is its inner one.
                let edge = s1 < s0 ? slack : -radius
                let when = s1 == s0 ? 0 : min(max((edge - s0) / (s1 - s0), 0), 1)
                let at = from + (free - from) * when
                let d = at - sheet.origin
                let (a, u) = (d.dot(sheet.acrossUnit), d.dot(sheet.upUnit))
                let (la, lu) = (sheet.across.length, sheet.up.length)
                guard a >= -slack, a <= la + slack, u >= -slack, u <= lu + slack else { continue }
                // The ball's speed into the sheet — its size, not its sign: a sheet is struck from
                // either side, and the rising edge is what says the ball was on its way into it.
                let speed = abs(vx * sheet.normal.x + vz * sheet.normal.z)
                guard speed >= p.hitLeast else { continue }
                guard best == nil || when < best!.when else { continue }
                let point = sheet.origin + sheet.acrossUnit * min(max(a, 0), la)
                    + sheet.upUnit * min(max(u, 0), lu)
                best = (when, Touch(goal: goal, sheet: index, point: point, speed: speed,
                                    strength: min(1, speed / p.hitSpeed)))
            }
        }
        return best?.touch
    }

    /// How far the node at (`x`, `y`, `z`) stands off its sheet at real time `t`: the cloth's sway,
    /// and the ripple of the ball's last contact on top of it. `age` is the real seconds since the
    /// ball struck at (`strikeX`, `strikeY`, `strikeZ`) at `strength` of a full-speed dent —
    /// negative, or past `seconds`, for a net that is only breathing. Both terms are bound by the
    /// node's `bell`, so the edges the net is laced along never move and the four sheets stay one
    /// skin. Reduce Motion keeps `calm` of the sway and the same share of a dent — calmer, never
    /// frozen. Scalars, not points: this runs for every vertex of both nets on every frame, on both
    /// platforms.
    public static func offset(x: Double, y: Double, z: Double, bell: Double, t: Double, reduceMotion: Bool,
                              strikeX: Double, strikeY: Double, strikeZ: Double, age: Double,
                              strength: Double, _ p: Params) -> Double {
        let calm = reduceMotion ? p.calm : 1
        var d = p.sway * calm * bell * sin(2 * .pi * t / p.swaySeconds + p.wave * (x + z))
        if age >= 0, age < p.seconds, strength > 0 {
            let (dx, dy, dz) = (x - strikeX, y - strikeY, z - strikeZ)
            let distance = (dx * dx + dy * dy + dz * dz).squareRoot()
            d += p.ripple * strength * calm * bell * exp(-p.decay * age)
                * sin(p.frequency * age - p.k * distance) * exp(-distance / p.reach)
        }
        return d
    }

    /// How far off its sheet any point can ever be pushed: the sway at full stretch, the deepest dent
    /// a ball can knock into it, and the cord that stands off the film and is half its own width wide.
    public static func reach(_ p: Params) -> Double {
        p.sway + p.ripple + p.cordLift + p.cord / 2
    }

    /// The box in the game's frame holding **every** vertex an app writes for both nets — the four
    /// sheets of each goal, their films and their cords, at every moment of the sway and of the
    /// hardest contact. It exists because a mesh written in place carries its own bounds and the
    /// renderer culls the entity against them (SMASH-33): the nets are written in the pitch's frame
    /// on entities that never move, so this box can never go stale.
    public static func extent(_ p: Params) -> (x: Double, yLow: Double, yHigh: Double, z: Double) {
        let r = reach(p)
        return (Tuning.Pitch.goalMouthWidth / 2 + r, -r, p.height + r,
                Tuning.Pitch.goalLineZ + Tuning.Pitch.goalDepth + r)
    }
}
