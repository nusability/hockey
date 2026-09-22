import Foundation

// Feel/ — the pure half of how a match looks, sounds and feels (spec §5.2, §8.8, §16.4): numbers
// and decisions the apps draw and play, taken out of the scene so a test can pin them. Nothing here
// is on the simulation path; it reads snapshots and events and never feeds a tick. Its tunables are
// the apps' presentation (presentation.toml), handed in by the caller. The Android twin is
// core/feel/.

/// The aim arrow's length (spec §5.2): how far the ribbon runs out from its start, which is the
/// orbit radius plus `Params.start` from the carrier's centre, along the orbit angle.
public enum AimArrow {
    public struct Params: Sendable, Hashable {
        public var maxLength: Double
        public var minLength: Double
        public var passShort: Double
        public var shotShort: Double
        public var boardMargin: Double
        public var boardProbe: Double
        public var probeStep: Double

        public init(maxLength: Double, minLength: Double, passShort: Double, shotShort: Double,
                    boardMargin: Double, boardProbe: Double, probeStep: Double) {
            self.maxLength = maxLength
            self.minLength = minLength
            self.passShort = passShort
            self.shotShort = shotShort
            self.boardMargin = boardMargin
            self.boardProbe = boardProbe
            self.probeStep = probeStep
        }
    }

    /// What the arrow is showing.
    public enum Kind: Sendable, Hashable {
        case free
        /// A pass to a team-mate standing at (x, z).
        case pass(x: Double, z: Double)
        /// A shot at the goal whose centre is at (0, goalZ).
        case shot(goalZ: Double)
    }

    /// The ribbon's length for a carrier at (x, z) with the ball at orbit `angle`, on a pitch whose
    /// corners have radius `corner` (§1).
    public static func length(_ kind: Kind, x: Double, z: Double, angle: Double, corner: Double, _ p: Params) -> Double {
        let r = Tuning.Orbit.radius
        var len = p.maxLength
        switch kind {
        case .free: break
        case .pass(let tx, let tz): len = Pitch.length(tx - x, tz - z) - r - p.passShort
        case .shot(let gz): len = Pitch.length(-x, gz - z) - r - p.shotShort
        }
        let toBoards = boards(x: x, z: z, angle: angle, corner: corner, p)
        return max(p.minLength, min(len, toBoards - r - p.boardMargin))
    }

    /// How far out along `angle` the pitch stays clear of the boards: marching from 1 m in steps of
    /// `probeStep` while under `maxLength + 2`, the last distance whose point is more than
    /// `boardProbe` inside the boundary; 0 if the first is not.
    public static func boards(x: Double, z: Double, angle: Double, corner: Double, _ p: Params) -> Double {
        let dx = sin(angle), dz = cos(angle)
        var clear = 0.0
        var d = 1.0
        while d < p.maxLength + 2 {
            if Pitch.boundary(x + dx * d, z + dz * d, corner: corner).distance > -p.boardProbe { break }
            clear = d
            d += p.probeStep
        }
        return clear
    }
}
