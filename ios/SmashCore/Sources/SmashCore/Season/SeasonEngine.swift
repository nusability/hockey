/// The season (spec §11): fixtures, simulated results, the table, the cup and the end — all drawn
/// from the season's own SplitMix64 stream, whose position the record keeps (§4.3, §15), so a
/// season reloaded from the save continues with exactly the draws it would have made. The
/// Android twin is `core/season/SeasonEngine.kt`; both replay shared/vectors/season/.

/// How a season ended (§11.4).
public struct SeasonEnd: Sendable, Hashable {
    public let champion: TeamKey
    public let cupWinner: TeamKey
}

/// A row of the league table (§11.4).
public struct TableRow: Sendable, Hashable {
    public let team: TeamKey
    public var played = 0, won = 0, drawn = 0, lost = 0, goalsFor = 0, goalsAgainst = 0
    public var points: Int { won * Tuning.Season.pointsWin + drawn * Tuning.Season.pointsDraw }
    public var goalDifference: Int { goalsFor - goalsAgainst }
}

extension SeasonRecord {
    /// A new season for `career` (§11.1), its stream seeded with `seed`: the league order and the
    /// cup order shuffled, every league fixture and the quarter-finals drawn.
    public static func start(seed: UInt64, career: CareerRecord) -> SeasonRecord {
        let teams = career.league
        var rng = SplitMix64(seed: seed)
        let order = shuffled(teams, &rng)
        let cupOrder = shuffled(teams, &rng)
        let rounds = leagueRounds(order)
        var fixtures: [Fixture] = []
        for (md, step) in Season.plan.enumerated() {
            switch step {
            case .league(let round):
                fixtures += rounds[round - 1].map { Fixture(home: $0.0, away: $0.1, matchday: md, score: nil) }
            case .cup(let round) where round == CupRound.allCases[0]:
                fixtures += pairs(cupOrder).map { Fixture(home: $0.0, away: $0.1, matchday: md, score: nil) }
            case .cup:
                break
            }
        }
        return SeasonRecord(seed: seed, stream: rng.state, teams: teams, matchday: 0, fixtures: fixtures)
    }

    /// Fisher–Yates from the last position down, `j = floor(u × (i + 1))`, i = n−1 … 1.
    static func shuffled(_ teams: [TeamKey], _ rng: inout SplitMix64) -> [TeamKey] {
        var a = teams
        for i in stride(from: a.count - 1, to: 0, by: -1) {
            let j = Int((rng.uniform() * Double(i + 1)).rounded(.down))
            a.swapAt(i, j)
        }
        return a
    }

    /// The circle method (§11.1): rounds 1–7 pair order[i] with order[7 − i], the first at home in
    /// even rounds; the order rotates with position 0 fixed. Rounds 8–14 swap home and away.
    static func leagueRounds(_ order: [TeamKey]) -> [[(TeamKey, TeamKey)]] {
        var o = order
        let n = o.count
        var first: [[(TeamKey, TeamKey)]] = []
        for r in 0..<(n - 1) {
            first.append((0..<(n / 2)).map { i in r % 2 == 0 ? (o[i], o[n - 1 - i]) : (o[n - 1 - i], o[i]) })
            o.insert(o.removeLast(), at: 1)
        }
        return first + first.map { $0.map { ($0.1, $0.0) } }
    }

    /// Consecutive pairs (0, 1), (2, 3), …, the first at home.
    static func pairs(_ teams: [TeamKey]) -> [(TeamKey, TeamKey)] {
        stride(from: 0, to: teams.count, by: 2).map { (teams[$0], teams[$0 + 1]) }
    }

    // MARK: - Reading

    public var isFinished: Bool { matchday >= Season.plan.count }

    /// The matchday to play next, or nil once the final is played.
    public var step: MatchdayStep? { isFinished ? nil : Season.plan[matchday] }

    /// The fixtures of matchday `md` (an index in `Season.plan`), in their drawn order.
    public func fixtures(on md: Int) -> [Fixture] { fixtures.filter { $0.matchday == md } }

    /// The player's unplayed fixture on the current matchday.
    public func playerFixture(_ player: TeamKey) -> Fixture? {
        playerFixtureIndex(player).map { fixtures[$0] }
    }

    func playerFixtureIndex(_ player: TeamKey) -> Int? {
        guard !isFinished else { return nil }
        return fixtures.indices.first {
            fixtures[$0].matchday == matchday && fixtures[$0].score == nil
                && (fixtures[$0].home == player || fixtures[$0].away == player)
        }
    }

    /// The league table after every league result so far — or only those up to and including
    /// matchday `through` — ranked by points, goal difference, goals for, then short code (§11.4).
    public func table(_ career: CareerRecord, through: Int? = nil) -> [TableRow] {
        var rows = Dictionary(uniqueKeysWithValues: teams.map { ($0, TableRow(team: $0)) })
        for f in fixtures {
            guard case .league = Season.plan[f.matchday], let s = f.score, f.matchday <= (through ?? Int.max) else { continue }
            rows[f.home]!.add(for: s.home, against: s.away)
            rows[f.away]!.add(for: s.away, against: s.home)
        }
        return rows.values.sorted { a, b in
            if a.points != b.points { return a.points > b.points }
            if a.goalDifference != b.goalDifference { return a.goalDifference > b.goalDifference }
            if a.goalsFor != b.goalsFor { return a.goalsFor > b.goalsFor }
            return career.short(of: a.team) < career.short(of: b.team)
        }
    }

    /// The ties of a cup round, in bracket order (empty until drawn).
    public func cupTies(_ round: CupRound) -> [Fixture] {
        fixtures(on: Season.plan.firstIndex(of: .cup(round))!)
    }

    /// The cup winner, once the final is played.
    public var cupWinner: TeamKey? { cupTies(CupRound.allCases.last!).first.flatMap(Self.winner) }

    static func winner(_ f: Fixture) -> TeamKey? {
        guard let s = f.score, s.home != s.away else { return nil }
        return s.home > s.away ? f.home : f.away
    }

    // MARK: - Playing

    /// Records the player's result on the current matchday (goals from the player's side), closes
    /// the matchday and simulates every matchday after it on which the player has no fixture.
    /// Returns how the season ended if it did.
    mutating func recordPlayed(_ player: TeamKey, goalsFor: Int, goalsAgainst: Int, overtime: Bool,
                               career: CareerRecord) throws(GameError) -> SeasonEnd? {
        guard !isFinished else { throw .seasonFinished }
        guard let index = playerFixtureIndex(player) else { throw .noPlayerFixture }
        guard goalsFor >= 0, goalsAgainst >= 0 else { throw .negativeGoals }
        let cup: Bool
        if case .cup = Season.plan[matchday] { cup = true } else { cup = false }
        if cup, goalsFor == goalsAgainst { throw .cupScoreLevel }
        if overtime, !cup { throw .overtimeOutsideCup }
        if overtime, abs(goalsFor - goalsAgainst) != 1 { throw .overtimeNotByOneGoal }
        let home = fixtures[index].home == player
        fixtures[index].score = Score(home: home ? goalsFor : goalsAgainst, away: home ? goalsAgainst : goalsFor,
                                      overtime: overtime)
        return advance(player, career: career)
    }

    /// Closes matchdays until the player has a fixture to play or the season is over (§11.2).
    mutating func advance(_ player: TeamKey, career: CareerRecord) -> SeasonEnd? {
        while !isFinished {
            if playerFixtureIndex(player) != nil { return nil }
            closeMatchday(career)
        }
        return SeasonEnd(champion: table(career)[0].team, cupWinner: cupWinner!)
    }

    /// Simulates every unplayed fixture of the current matchday in drawn order (§11.3), draws the
    /// next cup round after a cup matchday, and moves on.
    mutating func closeMatchday(_ career: CareerRecord) {
        var rng = SplitMix64(state: stream)
        let step = Season.plan[matchday]
        let cup: Bool
        if case .cup = step { cup = true } else { cup = false }
        for i in fixtures.indices where fixtures[i].matchday == matchday && fixtures[i].score == nil {
            fixtures[i].score = Self.simulate(home: career.rating(of: fixtures[i].home),
                                              away: career.rating(of: fixtures[i].away), cup: cup, &rng)
        }
        stream = rng.state
        if case .cup(let round) = step, let next = CupRound.allCases.firstIndex(of: round).map({ $0 + 1 }),
           next < CupRound.allCases.count {
            let winners = cupTies(round).map { Self.winner($0)! }
            let md = Season.plan.firstIndex(of: .cup(CupRound.allCases[next]))!
            fixtures += Self.pairs(winners).map { Fixture(home: $0.0, away: $0.1, matchday: md, score: nil) }
        }
        matchday += 1
    }

    /// A simulated result (§11.3): each side's goals Poisson-distributed by Knuth's method, the
    /// home side's drawn first; a level cup match goes to the home side when a draw is below
    /// `home mean / (home mean + away mean)`, else to the away side, by one goal in overtime.
    public static func simulate(home: Int, away: Int, cup: Bool, _ rng: inout SplitMix64) -> Score {
        let homeMean = Tuning.Season.goalMean * DetMath.exp(Double(home - away) / Tuning.Season.goalMeanScale)
            + Tuning.Season.homeBonus
        let awayMean = Tuning.Season.goalMean * DetMath.exp(Double(away - home) / Tuning.Season.goalMeanScale)
        var h = poisson(homeMean, &rng)
        var a = poisson(awayMean, &rng)
        guard cup, h == a else { return Score(home: h, away: a, overtime: false) }
        if rng.uniform() < homeMean / (homeMean + awayMean) { h += 1 } else { a += 1 }
        return Score(home: h, away: a, overtime: true)
    }

    /// Knuth: multiply uniforms until the product is no longer above e^−mean; the count − 1.
    static func poisson(_ mean: Double, _ rng: inout SplitMix64) -> Int {
        let limit = DetMath.exp(-mean)
        var k = 0
        var p = 1.0
        repeat {
            k += 1
            p = p * rng.uniform()
        } while p > limit
        return k - 1
    }
}

extension TableRow {
    mutating func add(for gf: Int, against ga: Int) {
        played += 1
        goalsFor += gf
        goalsAgainst += ga
        if gf > ga { won += 1 } else if gf == ga { drawn += 1 } else { lost += 1 }
    }
}
