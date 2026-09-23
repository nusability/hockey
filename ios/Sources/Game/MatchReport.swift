import SmashCore

/// What a finished match and a finished season report (spec §18.2, §18.3), built from what the game
/// is already holding at the moment it records the result. The Android twin is `game/MatchReport.kt`.
///
/// Nothing is recomputed here that the core already decides: `trailed` and `hard_fought` come off
/// `LoveMatch`, the same value the love dialog's arming reads (§17.2), so the column and the question
/// can never disagree about what a hard-fought win was.
enum MatchReport {
    /// One played match. `love` carries the goal tape the game collected as the match ran; `season` is
    /// the season **as it stood before this result was recorded**, which is where the matchday and the
    /// competition come from.
    static func match(plan: MatchPlan, world: World, periodSeconds: Double, result: MatchResult,
                      snapshot: MatchSnapshot, love: LoveMatch, board: BoardRecord,
                      season: SeasonRecord?, matchesPlayed: Int, forfeit: Bool) -> MatchRow.Body {
        let drill = plan.drill
        let competition: Competition
        switch plan {
        case .season: competition = season.map { isCup($0) ? .cup : .league } ?? .league
        case .drill: competition = .drill
        default: competition = .quick
        }
        let periods = drill == nil ? Tuning.Match.periods : 1
        let elapsed = LoveMatch.elapsedMillis(period: snapshot.period, remainingSeconds: snapshot.clock,
                                              periodSeconds: periodSeconds, overtime: snapshot.overtime,
                                              periods: periods)
        return MatchRow.Body(
            sport: world.sport, world: world, competition: competition,
            seasonNumber: competition == .league || competition == .cup ? season?.number : nil,
            // 1-based, as the player is shown it (§16.3); nil outside a season.
            matchday: competition == .league || competition == .cup ? season.map { $0.matchday + 1 } : nil,
            goalsFor: snapshot.score[0], goalsAgainst: snapshot.score[1], result: outcome(result),
            overtime: snapshot.overtime, forfeit: forfeit, durationMs: elapsed,
            periodMs: Int((periodSeconds * 1000).rounded()), formation: board.formation,
            matchesPlayed: matchesPlayed, trailed: love.trailed, hardFought: love.wasHardFought)
    }

    /// One finished season (§18.3), read off the table the season ended with.
    static func season(_ end: SeasonEnd, season: SeasonRecord, career: CareerRecord,
                       matchesPlayed: Int) -> SeasonRow.Body? {
        let table = season.table(career)
        guard let place = table.firstIndex(where: { $0.team == career.team }) else { return nil }
        let row = table[place]
        return SeasonRow.Body(seasonNumber: season.number, position: place + 1, points: row.points,
                              played: row.played, won: row.won, drawn: row.drawn, lost: row.lost,
                              goalsFor: row.goalsFor, goalsAgainst: row.goalsAgainst,
                              champion: end.champion == career.team, cupWon: end.cupWinner == career.team,
                              matchesPlayed: matchesPlayed)
    }

    private static func isCup(_ season: SeasonRecord) -> Bool {
        guard season.matchday < Season.plan.count, case .cup = Season.plan[season.matchday] else { return false }
        return true
    }

    private static func outcome(_ result: MatchResult) -> MatchOutcome {
        switch result {
        case .won: .won
        case .drawn: .drew
        case .lost: .lost
        }
    }
}
