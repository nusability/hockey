/// The save as the game's one mutable state for the career, the season, training and the board
/// (spec §2.2, §10, §11, §12, §15): every change a player can make goes through here, so the
/// trophy counts, the board and the season can never disagree. The Android twin is
/// `core/season/Save.kt`.
extension SaveRecord {
    /// A device's first save: no career, no season, no drill won, the board at its defaults.
    public static var fresh: SaveRecord {
        SaveRecord(version: SaveFormat.version, career: nil, season: nil, training: TrainingRecord(won: []),
                   board: .defaults)
    }

    // MARK: - The file

    /// The canonical JSON (shared/data/save.toml) — byte for byte what Android writes.
    public func encoded() -> String { json().canonicalText() }

    /// Reads a save file. Fails, typed, on anything but a well-formed record of this version.
    public static func decode(_ bytes: [UInt8]) throws(SaveDecodeError) -> SaveRecord {
        let json = try JSONValue.parse(bytes)
        guard case .object(let members) = json else { throw .wrongType(path: "$") }
        guard let version = members.first(where: { $0.key == "version" })?.value else {
            throw .missingField(path: "$.version")
        }
        guard case .int(let v) = version else { throw .wrongType(path: "$.version") }
        guard v == SaveFormat.version else { throw .unknownVersion(v) }
        return try SaveRecord(json: json, at: "$")
    }

    public static func decode(_ text: String) throws(SaveDecodeError) -> SaveRecord {
        try decode(Array(text.utf8))
    }

    // MARK: - The career (§2.2)

    /// The player's team in league, cup and every match they play.
    public var playerTeam: TeamKey? { career?.team }

    /// Confirms the team the player created — there is no other way into a career (§2.2); the name
    /// is kept without its leading and trailing spaces.
    public mutating func createTeam(_ draft: TeamDraft) throws(GameError) {
        guard career == nil else { throw .careerExists }
        let issues = CreatedTeamRules.issues(draft)
        guard issues.isEmpty else { throw .invalidTeam(issues) }
        let team = CreatedTeam(name: CreatedTeamRules.trimmedName(draft.name), short: draft.short,
                               primary: draft.primary, secondary: draft.secondary, world: draft.world)
        career = CareerRecord(created: team, leagueTitles: 0, cups: 0)
        board.adoptTactics(.defaults)
    }

    /// Renames, re-kits or re-homes the team the player created (§2.2, §16.1). The rules are the
    /// ones creation is held to, and nothing else of the career moves: the season's fixtures name
    /// the team, never its name or its colours, so a change mid-season keeps every draw and every
    /// result exactly as it stood.
    public mutating func editTeam(_ draft: TeamDraft) throws(GameError) {
        guard var career else { throw .noCareer }
        let issues = CreatedTeamRules.issues(draft)
        guard issues.isEmpty else { throw .invalidTeam(issues) }
        career.created = CreatedTeam(name: CreatedTeamRules.trimmedName(draft.name), short: draft.short,
                                     primary: draft.primary, secondary: draft.secondary, world: draft.world)
        self.career = career
    }

    /// Ends the career, its season and its trophies. Training progress survives (§2.2).
    public mutating func startOver() {
        career = nil
        season = nil
    }

    // MARK: - The season (§11)

    /// Starts the first season, or the next once the last one is over, keeping the career and its
    /// trophies; each season's number is one more than the last's (§15). `seed` seeds the season's
    /// stream (§4.3); the app draws it, the vectors fix it.
    public mutating func startSeason(seed: UInt64) throws(GameError) {
        guard let career else { throw .noCareer }
        if let season, !season.isFinished { throw .seasonInProgress }
        var next = SeasonRecord.start(seed: seed, career: career, number: (season?.number ?? 0) + 1)
        _ = next.advance(career.team, career: career)
        season = next
    }

    /// The player's fixture on the current matchday.
    public var playerFixture: Fixture? {
        guard let career, let season else { return nil }
        return season.playerFixture(career.team)
    }

    /// Records the player's match (goals from their side; `overtime` when a cup match was decided
    /// in sudden death), closes the matchday and simulates on to the player's next fixture. At the
    /// season's end the trophies grow when they are the player's; the end is returned.
    @discardableResult
    public mutating func recordPlayed(goalsFor: Int, goalsAgainst: Int, overtime: Bool = false) throws(GameError) -> SeasonEnd? {
        guard var career else { throw .noCareer }
        guard var season else { throw .noSeason }
        let end = try season.recordPlayed(career.team, goalsFor: goalsFor, goalsAgainst: goalsAgainst,
                                          overtime: overtime, career: career)
        if let end {
            if end.champion == career.team { career.leagueTitles += 1 }
            if end.cupWinner == career.team { career.cups += 1 }
        }
        self.season = season
        self.career = career
        return end
    }

    /// Quitting a season match forfeits it as a 0–3 loss (§8.7).
    @discardableResult
    public mutating func forfeit() throws(GameError) -> SeasonEnd? {
        try recordPlayed(goalsFor: Tuning.Match.forfeitFor, goalsAgainst: Tuning.Match.forfeitAgainst)
    }

    // MARK: - Training (§10)

    /// Records a won drill (once).
    public mutating func won(_ drill: Drill) {
        if !training.won.contains(drill) { training.won.append(drill) }
    }
}

// MARK: - The rules a decoded save is checked against

extension SaveRecord {
    func validate(at path: String) throws(SaveDecodeError) {
        guard let season else { return }
        guard let career else { throw .brokenRule(path: path + ".season", .seasonWithoutCareer) }
        guard season.teams == career.league else { throw .brokenRule(path: path + ".season.teams", .leagueIsNotTheCareers) }
    }
}

extension CareerRecord {
    func validate(at path: String) throws(SaveDecodeError) {
        guard leagueTitles >= 0, cups >= 0 else { throw .brokenRule(path: path, .negativeCount) }
        let c = created
        let draft = TeamDraft(name: c.name, short: c.short, primary: c.primary, secondary: c.secondary, world: c.world)
        guard CreatedTeamRules.issues(draft).isEmpty, CreatedTeamRules.trimmedName(c.name) == c.name else {
            throw .brokenRule(path: path + ".created", .createdTeamInvalid)
        }
    }
}

extension SeasonRecord {
    func validate(at path: String) throws(SaveDecodeError) {
        guard number >= 1 else { throw .brokenRule(path: path + ".number", .seasonNumber) }
        guard Set(teams).count == teams.count, teams.count == Tuning.Season.leagueTeams else {
            throw .brokenRule(path: path + ".teams", .leagueIsNotTheCareers)
        }
        guard (0...Season.plan.count).contains(matchday) else { throw .brokenRule(path: path + ".matchday", .matchdayOutOfRange) }
        for (i, f) in fixtures.enumerated() {
            let at = path + ".fixtures[\(i)]"
            guard Season.plan.indices.contains(f.matchday) else { throw .brokenRule(path: at + ".matchday", .matchdayOutOfRange) }
            guard teams.contains(f.home), teams.contains(f.away), f.home != f.away else {
                throw .brokenRule(path: at, .fixtureNotInLeague)
            }
            guard let s = f.score else { continue }
            guard s.home >= 0, s.away >= 0 else { throw .brokenRule(path: at + ".score", .negativeCount) }
            if case .cup = Season.plan[f.matchday] {
                guard s.home != s.away else { throw .brokenRule(path: at + ".score", .cupScoreLevel) }
            } else if s.overtime {
                throw .brokenRule(path: at + ".score", .overtimeOutsideCup)
            }
        }
    }
}

extension TrainingRecord {
    func validate(at path: String) throws(SaveDecodeError) {
        guard Set(won).count == won.count else { throw .brokenRule(path: path + ".won", .drillWonTwice) }
    }
}

extension BoardRecord {
    func validate(at path: String) throws(SaveDecodeError) {
        for (key, v) in [("pressing", pressing), ("covering", covering), ("push_up", pushUp), ("discipline", discipline)]
        where !(v >= Tuning.Board.tacticMin && v <= Tuning.Board.tacticMax) {
            throw .brokenRule(path: path + "." + key, .tacticOutOfRange)
        }
        guard Tuning.Board.periodSeconds.contains(periodSeconds) else {
            throw .brokenRule(path: path + ".period_seconds", .notABoardChoice)
        }
        guard Tuning.Board.ballSpinSeconds.contains(ballSpinSeconds) else {
            throw .brokenRule(path: path + ".ball_spin_seconds", .notABoardChoice)
        }
    }
}
