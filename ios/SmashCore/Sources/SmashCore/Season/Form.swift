/// A team's detail behind its row in the league table (spec §16.3a): what it has played, won,
/// drawn and lost, where it stands, how its last matches went and what it plays next — all read
/// off the season record's fixtures (§15), one computation for both platforms like `Scoreboard`
/// and `TextLayout`. The Android twin is `core/season/Form.kt`.

/// How a match went for the team the detail is about (§16.3a).
public enum FormKind: String, Sendable, Hashable, CaseIterable {
    case won, drawn, lost
}

/// One of a team's recent matches (§16.3a), from that team's side.
public struct FormMatch: Sendable, Hashable {
    public let opponent: TeamKey
    /// The team played this one at home.
    public let home: Bool
    public let goalsFor: Int
    public let goalsAgainst: Int
    /// A cup tie rather than a league round (§11.1).
    public let cup: Bool
    /// The cup tie was decided in sudden death (§8.4).
    public let overtime: Bool

    public var kind: FormKind {
        if goalsFor > goalsAgainst { return .won }
        return goalsFor == goalsAgainst ? .drawn : .lost
    }
}

/// Everything a team's detail shows (spec §16.3a).
public struct TeamDetail: Sendable, Hashable {
    public let team: TeamKey
    /// Its place in the table, 1-based (§11.4).
    public let position: Int
    /// Played, won, drawn, lost, goals for and against, goal difference and points — the league
    /// only, exactly as the table counts them (§11.4).
    public let row: TableRow
    /// Its last matches, most recent first — at most `Tuning.Season.formMatches`, league and cup
    /// alike, fewer early in a season.
    public let form: [FormMatch]
    /// The team's next fixture, league or cup; nil once it has none left this season.
    public let next: Fixture?
}

extension SeasonRecord {
    /// The detail of `team` (§16.3a). The fixtures are read in the order they were drawn (§11.1):
    /// a matchday's later, so the most recent result is the last played fixture of the highest
    /// matchday, and the next fixture the first unplayed one of the lowest.
    public func detail(of team: TeamKey, career: CareerRecord) -> TeamDetail {
        let standings = table(career)
        let place = standings.firstIndex { $0.team == team }
        var form: [FormMatch] = []
        var next: Fixture?
        // Fixtures are appended matchday by matchday, so index order is drawn order within one.
        let mine = fixtures.enumerated().filter { $0.element.home == team || $0.element.away == team }
            .sorted { ($0.element.matchday, $0.offset) < ($1.element.matchday, $1.offset) }
        for (_, f) in mine.reversed() {
            guard let s = f.score else { continue }
            guard form.count < Tuning.Season.formMatches else { break }
            let home = f.home == team
            let cup: Bool
            if case .cup = Season.plan[f.matchday] { cup = true } else { cup = false }
            form.append(FormMatch(opponent: home ? f.away : f.home, home: home,
                                  goalsFor: home ? s.home : s.away, goalsAgainst: home ? s.away : s.home,
                                  cup: cup, overtime: s.overtime))
        }
        for (_, f) in mine where f.score == nil {
            next = f
            break
        }
        return TeamDetail(team: team, position: (place ?? 0) + 1,
                          row: place.map { standings[$0] } ?? TableRow(team: team), form: form, next: next)
    }
}
