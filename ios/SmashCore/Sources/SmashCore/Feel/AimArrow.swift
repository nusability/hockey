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

    /// What the lock-on marker shows (spec §5.2).
    public enum Lock: Sendable, Hashable {
        case none
        /// The receiver's ring and the dotted line to their lead point.
        case pass(Int)
        /// The glow across the goal mouth.
        case shot
    }

    /// What the arrow shows this frame.
    public struct Look: Sendable, Hashable {
        /// The ribbon, its glow, the arrowhead and the ring the ball circles on are drawn.
        public var arrow: Bool
        /// 0 free (yellow), 1 a pass (green), 2 a shot (pink) — `[aim]`'s three colours in order.
        public var colour: Int
        public var lock: Lock
        /// 0…1 — how far the lock-on has faded in since this snap began.
        public var fade: Double
        /// Whether a release now would snap: the arrow pulses and its glow lifts.
        public var snapped: Bool { colour != 0 }

        public static let hidden = Look(arrow: false, colour: 0, lock: .none, fade: 0)
    }

    /// The arrow's state between frames (spec §5.2) — which snap is being shown and since when — so
    /// the arrow is right at **every** transition: the match leaving and re-entering play, a snap
    /// beginning, changing or ending, the ball changing hands, a restart. Both apps drive their
    /// arrow from this; nothing about it is a platform's own.
    public struct Showing: Sendable, Hashable {
        /// The snap on screen: whose it is and what it aims at. Nil while the arrow is hidden, so
        /// the next one fades in from nothing rather than appearing fully lit.
        private var carrier: Int?
        private var aim: MatchSnapshot.Aim?
        /// The real second the snap on screen began.
        private var since = 0.0

        public init() {}

        /// One frame. `clock` is real seconds, monotonic for the life of the match scene; `fadeIn`
        /// is the lock-on's fade (`[aim.lock] fade_in`).
        public mutating func frame(state: MatchState, playerCarrier: Bool, carrier: Int?,
                                   aim: MatchSnapshot.Aim?, clock: Double, fadeIn: Double) -> Look {
            guard playerCarrier, let carrier, let aim, state == .play || state == .ready else {
                self.carrier = nil
                self.aim = nil
                return .hidden
            }
            // A snap begins when what it aims at changes — and when the ball changes hands, which is
            // a new snap even when it aims at the same place.
            if self.carrier != carrier || self.aim != aim {
                (self.carrier, self.aim, since) = (carrier, aim, clock)
            }
            // Never run backwards: a clock that jumps back (a new scene) restarts the fade.
            if clock < since { since = clock }
            let fade = fadeIn > 0 ? min(1, (clock - since) / fadeIn) : 1
            switch aim {
            case .unassisted: return Look(arrow: true, colour: 0, lock: .none, fade: 0)
            case .pass(let to): return Look(arrow: true, colour: 1, lock: .pass(to), fade: fade)
            case .shot: return Look(arrow: true, colour: 2, lock: .shot, fade: fade)
            }
        }
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
