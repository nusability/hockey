import Foundation
import SmashCore

/// What to put on screen — a debug entry until the menus exist (SMASH-11): a quick match between
/// two named clubs in a named world, any drill, or the demo (§9). Read from launch arguments, which
/// the system also files in `UserDefaults` (`-scene match -drill 1`); Android reads the same names
/// from intent extras.
///
///     -scene match -quick mossfoxes,glowowls,space   a quick match, the player on the first club
///     -scene match -drill 1                          a drill, by number (§10)
///     -scene match -demo                             the demo (§9), both sides automatic
///     -seed 42                                       optional: the match stream's seed (§4.3)
enum MatchPlan: Equatable {
    case quick(home: Club, away: Club, world: World)
    case drill(Drill)
    /// The demo's n-th match: the worlds in turn (§9).
    case demo(round: Int)

    /// The plan the launch asks for; nil unless `-scene match`. A malformed argument fails loud.
    static func fromLaunch(_ d: UserDefaults = .standard) throws -> MatchPlan? {
        guard d.string(forKey: "scene") == "match" else { return nil }
        if let q = d.string(forKey: "quick") {
            let parts = q.split(separator: ",").map(String.init)
            guard parts.count == 3, let home = Club(rawValue: parts[0]), let away = Club(rawValue: parts[1]),
                  let world = World(rawValue: parts[2]), home != away else {
                throw LaunchError.bad("-quick wants home,away,world — two different clubs and a world, got '\(q)'")
            }
            return .quick(home: home, away: away, world: world)
        }
        if let n = d.string(forKey: "drill") {
            guard let i = Int(n), let drill = Drill.allCases.first(where: { $0.number == i }) else {
                throw LaunchError.bad("-drill wants a drill number 1…\(Drill.allCases.count), got '\(n)'")
            }
            return .drill(drill)
        }
        return .demo(round: 0)
    }

    static func seed(_ d: UserDefaults = .standard) -> UInt64 {
        d.string(forKey: "seed").flatMap(UInt64.init) ?? UInt64.random(in: .min ... .max)
    }

    var world: World {
        switch self {
        case .quick(_, _, let w): w
        case .drill(let d): d.world
        case .demo(let n): World.allCases[n % World.allCases.count]
        }
    }

    /// The demo's opponent for round n: any club but the player's, drawn for presentation.
    private static func demoOpponent(_ seed: UInt64) -> Club {
        let others = Club.allCases.filter { $0 != Career.demoClub }
        return others[Int(seed % UInt64(others.count))]
    }

    /// The match, set up with the coach's defaults (no board is saved yet, §12).
    func start(seed: UInt64) -> (match: Match, orbitPeriod: Double) {
        let spin = Tuning.Board.ballSpinSecondsDefault
        switch self {
        case .quick(let home, let away, let world):
            let setup = MatchSetup(seed: seed, sport: world.sport, home: .club(home), away: .club(away),
                                   periodSeconds: Tuning.Board.periodSecondsDefault, orbitPeriod: spin, cup: false,
                                   control: .player)
            return (Match(setup), spin)
        case .drill(let drill):
            return (Match(DrillSetup(drill: drill, seed: seed, tactics: .defaults, orbitPeriod: spin)), spin)
        case .demo:
            let setup = MatchSetup.demo(seed: seed, world: world, home: .club(Career.demoClub),
                                        away: .club(MatchPlan.demoOpponent(seed)),
                                        periodSeconds: Tuning.Board.periodSecondsDefault)
            return (Match(setup), Tuning.Orbit.demoPeriod)
        }
    }

    /// The two sides' kits; the away side changes into its secondary when the primaries clash.
    func colours(seed: UInt64) -> [TeamColours] {
        func kit(_ c: Club) -> TeamColours { TeamColours(primary: c.primary, secondary: c.secondary) }
        let sides: [TeamColours]
        switch self {
        case .quick(let home, let away, _): sides = [kit(home), kit(away)]
        case .drill: sides = [kit(Career.demoClub), TeamColours(primary: Presentation.Figure.sparringPrimary,
                                                                secondary: Presentation.Figure.sparringSecondary)]
        case .demo: sides = [kit(Career.demoClub), kit(MatchPlan.demoOpponent(seed))]
        }
        return [sides[0], MatchPlan.clash(sides[0].primary, sides[1].primary)
            ? TeamColours(primary: sides[1].secondary, secondary: sides[1].primary) : sides[1]]
    }

    /// The short codes above the score, for a match between clubs.
    func codes(seed: UInt64) -> [String]? {
        switch self {
        case .quick(let home, let away, _): [home.short, away.short]
        case .drill: nil
        case .demo: [Career.demoClub.short, MatchPlan.demoOpponent(seed).short]
        }
    }

    static func clash(_ a: UInt32, _ b: UInt32) -> Bool {
        func c(_ v: UInt32, _ s: UInt32) -> Double { Double((v >> s) & 0xFF) }
        let d = [16, 8, 0].map { s in c(a, UInt32(s)) - c(b, UInt32(s)) }
        return (d[0] * d[0] + d[1] * d[1] + d[2] * d[2]).squareRoot() < Presentation.Figure.kitClash
    }
}

enum LaunchError: Error, CustomStringConvertible {
    case bad(String)
    var description: String { if case .bad(let s) = self { "launch: \(s)" } else { "launch" } }
}
