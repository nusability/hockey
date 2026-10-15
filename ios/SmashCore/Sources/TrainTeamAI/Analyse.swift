// Measures the things the owner actually asked for (SMASH-72).
//
// Every number the trainer optimises tonight was a proxy, and the proxies kept being wrong in ways
// that took hours to notice: `receivers` rose while the team got worse, `spread` fell under a
// reward that paid for it rising, and the lowest cloning loss of the night came from the worst
// team. So this file measures the stated objectives — **off-ball shape**, **legible roles**, **no
// ball-chasing** — as directly as they can be measured from a played match, and reports them for
// the learned side and for §7 side by side.
//
// None of these are trained on. That is deliberate: a measure you optimise stops being a measure.
import Foundation
import SmashCore

enum Analyse {

    struct Report {
        var matches = 0
        /// Mean distance from the ball to **every** outfield player on the side. Low means the
        /// whole team converges on the ball — §7.2's "pack of children following the ball".
        var swarm = 0.0
        /// How often, per minute of play, the pair of players nearest the ball changes. High means
        /// roles flip faster than a viewer can follow them, which is the thing §7.2's 0.7 s
        /// commitment exists to prevent.
        var roleChurn = 0.0
        /// Mean signed depth of the deepest defender relative to the ball, in the attacking
        /// direction: positive means the defender is **behind** the ball, between it and the goal,
        /// which is what "leave the defenders back" means in a number.
        var defensiveDepth = 0.0
        /// How often the deepest defender is goal-side of the ball at all, as a share of play.
        var defendersHome = 0.0
        /// Spread across the pitch's width: the standard deviation of outfield x. A team that uses
        /// the width looks like a team; one that files down the middle does not.
        var width = 0.0
        /// Mean distance between a player and their nearest team-mate, as before, for continuity
        /// with the training table.
        var spacing = 0.0

        static func mean(_ xs: [Report]) -> Report {
            guard !xs.isEmpty else { return Report() }
            let n = Double(xs.count)
            var m = Report()
            m.matches = xs.count
            m.swarm = xs.reduce(0) { $0 + $1.swarm } / n
            m.roleChurn = xs.reduce(0) { $0 + $1.roleChurn } / n
            m.defensiveDepth = xs.reduce(0) { $0 + $1.defensiveDepth } / n
            m.defendersHome = xs.reduce(0) { $0 + $1.defendersHome } / n
            m.width = xs.reduce(0) { $0 + $1.width } / n
            m.spacing = xs.reduce(0) { $0 + $1.spacing } / n
            return m
        }
    }

    /// Plays one match and measures team 0.
    static func match(_ nets: [PolicyNet?], setup: MatchSetup, stride: Int = 12) -> Report {
        var m = Match(setup)
        m.installPolicies(nets)

        var r = Report()
        var samples = 0.0
        var swarmTotal = 0.0, depthTotal = 0.0, widthTotal = 0.0, spacingTotal = 0.0
        var homeCount = 0.0
        var churn = 0.0
        var previousPair: [Int] = []
        var sinceSample = 0
        let maxTicks = Int(setup.periodSeconds * 120.0 * 9.0)

        func length(_ x: Double, _ z: Double) -> Double { (x * x + z * z).squareRoot() }

        while m.result == nil && m.ticks < maxTicks {
            m.tick()
            sinceSample += 1
            guard sinceSample >= stride else { continue }
            sinceSample = 0
            let s = m.snapshot
            guard s.state == .play else { continue }
            samples += 1

            let mine = s.players.indices.filter { s.players[$0].team == 0 && s.players[$0].role != .goalie }
            guard !mine.isEmpty else { continue }

            // Swarm: mean distance from the ball to every one of them.
            var toBall: [(d: Double, i: Int)] = mine.map {
                (length(s.players[$0].x - s.ball.x, s.players[$0].z - s.ball.z), $0)
            }
            swarmTotal += toBall.reduce(0) { $0 + $1.d } / Double(mine.count)

            // Role churn: has the nearest pair changed since the last sample?
            toBall.sort { $0.d < $1.d || ($0.d == $1.d && $0.i < $1.i) }
            let pair = toBall.prefix(2).map(\.i).sorted()
            if !previousPair.isEmpty && pair != previousPair { churn += 1 }
            previousPair = pair

            // Defensive depth: the deepest defender, measured goal-side of the ball. Team 0 attacks
            // +z, so "behind the ball" is a smaller z.
            let defenders = mine.filter { s.players[$0].role == .defender }
            if let deepest = defenders.min(by: { $0 < $1 ? s.players[$0].z < s.players[$1].z : false })
                ?? defenders.first {
                let behind = s.ball.z - s.players[deepest].z
                depthTotal += behind
                if behind > 0 { homeCount += 1 }
            }

            // Width: the spread of x across the outfield.
            let meanX = mine.reduce(0.0) { $0 + s.players[$1].x } / Double(mine.count)
            let variance = mine.reduce(0.0) { $0 + ($1 == 0 ? 0 : 0) + pow(s.players[$1].x - meanX, 2) } / Double(mine.count)
            widthTotal += variance.squareRoot()

            // Spacing: nearest team-mate.
            var near = 0.0
            for i in mine {
                var best = Double.greatestFiniteMagnitude
                for j in mine where j != i {
                    let d = length(s.players[i].x - s.players[j].x, s.players[i].z - s.players[j].z)
                    if d < best { best = d }
                }
                if best < .greatestFiniteMagnitude { near += best }
            }
            spacingTotal += near / Double(mine.count)
        }

        guard samples > 0 else { return r }
        r.matches = 1
        r.swarm = swarmTotal / samples
        // Samples are `stride` ticks apart at 120 ticks a second, so this converts to per minute.
        let minutes = samples * Double(stride) / 120.0 / 60.0
        r.roleChurn = minutes > 0 ? churn / minutes : 0
        r.defensiveDepth = depthTotal / samples
        r.defendersHome = homeCount / samples
        r.width = widthTotal / samples
        r.spacing = spacingTotal / samples
        return r
    }

    static func table(_ rows: [(String, Report)]) -> String {
        var out = "                 swarm   churn/min   depth   goal-side    width   spacing\n"
        for (label, r) in rows {
            out += String(format: "  %-12@ %6.2f m   %7.1f  %+6.2f m   %6.0f %%   %5.1f m   %5.1f m\n",
                          label as NSString, r.swarm, r.roleChurn, r.defensiveDepth,
                          100 * r.defendersHome, r.width, r.spacing)
        }
        return out
    }
}
