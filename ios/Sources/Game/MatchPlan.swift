import Foundation
import SmashCore

/// A match to put on the pitch (spec §8–§11): which one it is, and — with the save — everything it
/// is made of. The core decides the teams, rules and settings (`SaveRecord.seasonMatch` & co.);
/// this adds what only the screen needs: the world, the kits, the short codes. The twin of
/// Android's MatchPlan.kt.
enum MatchPlan: Equatable {
    /// The player's fixture of the current matchday (§11.2).
    case season
    /// A friendly against a drawn club in a drawn world (§11.5).
    case quick(QuickMatch)
    /// A drill (§10).
    case drill(Drill)
    /// The demo behind the menus (§9): the n-th, in the worlds in turn, against `opponent`.
    case demo(round: Int, opponent: Club)
    /// A developer shortcut (`-scene match -quick home,away,world`): two named clubs, the player
    /// on the first.
    case friendly(home: Club, away: Club, world: World)

    var isSeason: Bool { self == .season }
    var isDemo: Bool { if case .demo = self { true } else { false } }
    var drill: Drill? { if case .drill(let d) = self { d } else { nil } }

    /// A demo against a random club other than the player's own (§9) — presentation's own draw,
    /// never a simulation stream (§4.3).
    static func demo(round: Int, save: SaveRecord) -> MatchPlan {
        let others = Club.allCases.filter { $0 != save.sideTeam.club }
        return .demo(round: round, opponent: others.randomElement()!)
    }

    /// The match itself and how it looks; nil when there is nothing to play (no fixture).
    func kickoff(_ save: SaveRecord, seed: UInt64) -> Kickoff? {
        let career = save.career
        let mine = career.map { $0.kit(of: $0.team) } ?? (Career.demoClub.primary, Career.demoClub.secondary)
        let myCode = career.map { $0.short(of: $0.team) } ?? Career.demoClub.short
        let myName = career.map { Names.team($0.team, $0) } ?? L(Career.demoClub.nameKey).uppercased()
        func kit(_ c: Club) -> TeamColours { TeamColours(primary: c.primary, secondary: c.secondary) }
        let me = TeamColours(primary: mine.0, secondary: mine.1)
        switch self {
        case .season:
            guard let career, let setup = save.seasonMatch(seed: seed), let f = save.playerFixture else { return nil }
            let them = f.home == career.team ? f.away : f.home
            let k = career.kit(of: them)
            return Kickoff(match: Match(setup), orbitPeriod: setup.orbitPeriod, world: career.homeWorld(of: f.home),
                           colours: Self.dress(me, TeamColours(primary: k.primary, secondary: k.secondary)),
                           codes: [myCode, career.short(of: them)], drillGoals: nil,
                           names: [Names.team(f.home, career), Names.team(f.away, career)])
        case .quick(let q):
            let setup = save.quickMatch(q, seed: seed)
            return Kickoff(match: Match(setup), orbitPeriod: setup.orbitPeriod, world: q.world,
                           colours: Self.dress(me, kit(q.opponent)), codes: [myCode, q.opponent.short], drillGoals: nil,
                           names: [myName, L(q.opponent.nameKey).uppercased()])
        case .drill(let d):
            let setup = save.drill(d, seed: seed)
            let sparring = TeamColours(primary: Presentation.Player.sparringPrimary,
                                       secondary: Presentation.Player.sparringSecondary)
            return Kickoff(match: Match(setup), orbitPeriod: setup.orbitPeriod, world: d.world,
                           colours: Self.dress(me, sparring), codes: nil, drillGoals: d.goals, names: nil)
        case .demo(let round, let opponent):
            let world = World.allCases[round % World.allCases.count]
            let setup = save.demo(world: world, opponent: opponent, seed: seed)
            return Kickoff(match: Match(setup), orbitPeriod: setup.orbitPeriod, world: world,
                           colours: Self.dress(me, kit(opponent)), codes: [myCode, opponent.short], drillGoals: nil, names: nil)
        case .friendly(let home, let away, let world):
            let setup = MatchSetup(seed: seed, sport: world.sport, home: .club(home), away: .club(away),
                                   periodSeconds: save.board.periodSeconds, orbitPeriod: save.board.ballSpinSeconds,
                                   cup: false, control: .player)
            return Kickoff(match: Match(setup), orbitPeriod: setup.orbitPeriod, world: world,
                           colours: Self.dress(kit(home), kit(away)), codes: [home.short, away.short], drillGoals: nil,
                           names: [L(home.nameKey).uppercased(), L(away.nameKey).uppercased()])
        }
    }

    /// The away side changes into its secondary when the primaries clash.
    static func dress(_ home: TeamColours, _ away: TeamColours) -> [TeamColours] {
        [home, clash(home.primary, away.primary) ? TeamColours(primary: away.secondary, secondary: away.primary) : away]
    }

    static func clash(_ a: UInt32, _ b: UInt32) -> Bool {
        func c(_ v: UInt32, _ s: UInt32) -> Double { Double((v >> s) & 0xFF) }
        let d = [16, 8, 0].map { s in c(a, UInt32(s)) - c(b, UInt32(s)) }
        return (d[0] * d[0] + d[1] * d[1] + d[2] * d[2]).squareRoot() < Presentation.Player.kitClash
    }

    static func seed() -> UInt64 { UInt64.random(in: .min ... .max) }
}

/// A match ready to play, and what the screen needs to draw it.
struct Kickoff {
    var match: Match
    let orbitPeriod: Double
    let world: World
    /// The two sides' kits, the player's first.
    let colours: [TeamColours]
    /// The short codes above the score; nil in a drill.
    let codes: [String]?
    /// A drill's goal target; nil in a match.
    let drillGoals: Int?
    /// The two sides' names for the intro banner (§16.4), home first; nil in a drill or the demo.
    let names: [String]?
}

/// Where the app opens (the developer shortcuts; a player's launch has none of these). Launch
/// arguments, which the system also files in `UserDefaults`:
///
///     -scene match -quick mossfoxes,glowowls,space   straight into a friendly, the player on the first club
///     -scene match -drill 1                          straight into a drill, by number (§10)
///     -scene match -demo                             the menus, as on any launch (the demo plays behind them)
///
/// Android reads the same names from intent extras. A malformed argument fails loud.
enum Launch {
    static func plan(_ d: UserDefaults = .standard) throws -> MatchPlan? {
        guard d.string(forKey: "scene") == "match" else { return nil }
        if let q = d.string(forKey: "quick") {
            let parts = q.split(separator: ",").map(String.init)
            guard parts.count == 3, let home = Club(rawValue: parts[0]), let away = Club(rawValue: parts[1]),
                  let world = World(rawValue: parts[2]), home != away else {
                throw LaunchError.bad("-quick wants home,away,world — two different clubs and a world, got '\(q)'")
            }
            return .friendly(home: home, away: away, world: world)
        }
        if let n = d.string(forKey: "drill") {
            guard let i = Int(n), let drill = Drill.allCases.first(where: { $0.number == i }) else {
                throw LaunchError.bad("-drill wants a drill number 1…\(Drill.allCases.count), got '\(n)'")
            }
            return .drill(drill)
        }
        return nil
    }
}

enum LaunchError: Error, CustomStringConvertible {
    case bad(String)
    var description: String { if case .bad(let s) = self { "launch: \(s)" } else { "launch" } }
}
