import Testing
@testable import SmashCore

/// The contracts of the career, the season and the save (spec §2.2, §8.7, §11, §12, §15).
@Suite struct SeasonTests {
    static let jet = Career.kitPalette[0]

    static func draft(_ name: String = "Moss Giants", short: String = "MOG") -> TeamDraft {
        TeamDraft(name: name, short: short, primary: jet.primary, secondary: jet.secondary, world: .ocean)
    }

    static func clubSeason(_ club: Club = .falcons, seed: UInt64 = 7) throws -> SaveRecord {
        var save = SaveRecord.fresh
        try save.chooseClub(club)
        try save.startSeason(seed: seed)
        return save
    }

    // MARK: - §11.1 fixtures

    @Test(arguments: [UInt64(0), 1, 42, 0xDEAD_BEEF])
    func everyTeamPlaysEveryOtherTwiceWithSwappedVenues(_ seed: UInt64) throws {
        for career in [CareerRecord.picked(.nebula), CareerRecord(team: .created, created: CreatedTeam(
            name: "Moss Giants", short: "MOG", primary: Self.jet.primary, secondary: Self.jet.secondary, world: .ocean),
            leagueTitles: 0, cups: 0)] {
            let s = SeasonRecord.start(seed: seed, career: career)
            let league = s.fixtures.filter { if case .league = Season.plan[$0.matchday] { true } else { false } }
            #expect(league.count == 56)
            #expect(Set(s.teams) == Set(career.league) && s.teams.count == 8)
            var venues: [String: Int] = [:]
            for f in league { venues["\(f.home.rawValue)>\(f.away.rawValue)", default: 0] += 1 }
            for a in s.teams { for b in s.teams where a != b { #expect(venues["\(a.rawValue)>\(b.rawValue)"] == 1) } }
            for (md, step) in Season.plan.enumerated() {
                guard case .league(let round) = step else { continue }
                let teams = s.fixtures(on: md).flatMap { [$0.home, $0.away] }
                #expect(Set(teams).count == 8 && teams.count == 8, "every team once in round \(round)")
                if round > 7 {   // rounds 8–14 mirror 1–7
                    let mirror = s.fixtures(on: Season.plan.firstIndex(of: .league(round: round - 7))!)
                    #expect(s.fixtures(on: md).map { [$0.away, $0.home] } == mirror.map { [$0.home, $0.away] })
                }
            }
            #expect(s.cupTies(.quarterFinal).count == 4 && s.cupTies(.semiFinal).isEmpty)
            #expect(Set(s.cupTies(.quarterFinal).flatMap { [$0.home, $0.away] }) == Set(s.teams))
        }
    }

    @Test func aCreatedTeamReplacesGlacierWolvesInTheirPlace() throws {
        var save = SaveRecord.fresh
        try save.createTeam(Self.draft())
        let league = save.career!.league
        #expect(league.count == 8 && !league.contains(.wolves) && league[6] == .created)
        #expect(save.career!.rating(of: .created) == 77)
    }

    @Test func theCircleMethodAsSpecified() {
        let order: [TeamKey] = [.mossfoxes, .glowowls, .nebula, .rocketlynx, .scorpions, .falcons, .wolves, .kraken]
        let rounds = SeasonRecord.leagueRounds(order)
        #expect(rounds.count == 14)
        // Round 0: order[i] at home against order[7 − i].
        #expect(rounds[0].map { [$0.0, $0.1] } == [[.mossfoxes, .kraken], [.glowowls, .wolves], [.nebula, .falcons], [.rocketlynx, .scorpions]])
        // Round 1: rotated (kraken to position 1), order[7 − i] at home.
        #expect(rounds[1].map { [$0.0, $0.1] } == [[.wolves, .mossfoxes], [.falcons, .kraken], [.scorpions, .glowowls], [.rocketlynx, .nebula]])
    }

    // MARK: - §11.2–11.4 playing

    @Test func theCupAdvancesWinnersInBracketOrder() throws {
        var save = try Self.clubSeason()
        while !save.season!.isFinished {
            let cup: Bool
            if case .cup = save.season!.step! { cup = true } else { cup = false }
            try save.recordPlayed(goalsFor: 2, goalsAgainst: cup ? 1 : 2)
        }
        let s = save.season!
        let qf = s.cupTies(.quarterFinal), sf = s.cupTies(.semiFinal), f = s.cupTies(.final)
        #expect(qf.count == 4 && sf.count == 2 && f.count == 1)
        let qfWinners = qf.map { SeasonRecord.winner($0)! }
        #expect(sf.map { [$0.home, $0.away] } == [[qfWinners[0], qfWinners[1]], [qfWinners[2], qfWinners[3]]])
        #expect([f[0].home, f[0].away] == sf.map { SeasonRecord.winner($0)! })
        #expect(s.cupWinner == .falcons && save.career!.cups == 1)
        for tie in qf + sf + f { #expect(tie.score!.home != tie.score!.away) }
    }

    @Test func afterACupExitTheRestIsSimulatedStraightThrough() throws {
        var save = try Self.clubSeason()
        var played = 0
        while !save.season!.isFinished {
            if case .cup = save.season!.step! { try save.forfeit() } else { try save.recordPlayed(goalsFor: 1, goalsAgainst: 1) }
            played += 1
        }
        #expect(played == 15)   // 14 league matches and the quarter-final
        let qf = save.season!.cupTies(.quarterFinal).first { $0.home == .falcons || $0.away == .falcons }!
        #expect(qf.score == (qf.home == .falcons ? Score(home: 0, away: 3, overtime: false) : Score(home: 3, away: 0, overtime: false)))
    }

    @Test func theTableBreaksTiesByGoalDifferenceGoalsForThenShortCode() {
        let career = CareerRecord.picked(.mossfoxes)
        let teams = career.league
        var s = SeasonRecord(seed: 0, stream: 0, teams: teams, matchday: 1, fixtures: [
            Fixture(home: .rocketlynx, away: .glowowls, matchday: 0, score: Score(home: 3, away: 1, overtime: false)),
            Fixture(home: .nebula, away: .kraken, matchday: 0, score: Score(home: 2, away: 0, overtime: false)),
            Fixture(home: .mossfoxes, away: .falcons, matchday: 0, score: Score(home: 2, away: 0, overtime: false)),
            Fixture(home: .scorpions, away: .wolves, matchday: 0, score: Score(home: 1, away: 1, overtime: false)),
        ])
        // ROC, MOS and NEB on 3 points and +2: ROC ahead on goals for, MOS before NEB on short code;
        // DUN before GLW, and COR before MIR, on short code alone.
        let expected: [TeamKey] = [.rocketlynx, .mossfoxes, .nebula, .scorpions, .wolves, .glowowls, .kraken, .falcons]
        #expect(s.table(career).map(\.team) == expected)
        #expect(s.table(career)[0].points == 3 && s.table(career)[3].points == 1 && s.table(career)[3].drawn == 1)
        // A cup result never counts in the table.
        s.fixtures.append(Fixture(home: .falcons, away: .kraken, matchday: 4, score: Score(home: 5, away: 0, overtime: false)))
        #expect(s.table(career).map(\.team) == expected)
    }

    @Test func thePlayersScoreIsCheckedAndForfeitIsNilThree() throws {
        var save = try Self.clubSeason()
        #expect(throws: GameError.negativeGoals) { try save.recordPlayed(goalsFor: -1, goalsAgainst: 0) }
        #expect(throws: GameError.overtimeOutsideCup) { try save.recordPlayed(goalsFor: 2, goalsAgainst: 1, overtime: true) }
        let f = save.playerFixture!
        try save.forfeit()
        let recorded = save.season!.fixtures.first { $0.home == f.home && $0.away == f.away && $0.matchday == f.matchday }!
        #expect(recorded.score == (f.home == .falcons ? Score(home: 0, away: 3, overtime: false) : Score(home: 3, away: 0, overtime: false)))
        while case .league = save.season!.step! { try save.recordPlayed(goalsFor: 0, goalsAgainst: 0) }
        #expect(throws: GameError.cupScoreLevel) { try save.recordPlayed(goalsFor: 1, goalsAgainst: 1) }
        #expect(throws: GameError.overtimeNotByOneGoal) { try save.recordPlayed(goalsFor: 3, goalsAgainst: 1, overtime: true) }
        try save.recordPlayed(goalsFor: 3, goalsAgainst: 2, overtime: true)
    }

    @Test func aNewSeasonKeepsTheCareerAndItsTrophies() throws {
        var save = try Self.clubSeason(.rocketlynx, seed: 3)
        #expect(throws: GameError.seasonInProgress) { try save.startSeason(seed: 4) }
        while !save.season!.isFinished {
            if case .cup = save.season!.step! { try save.recordPlayed(goalsFor: 9, goalsAgainst: 0) }
            else { try save.recordPlayed(goalsFor: 9, goalsAgainst: 0) }
        }
        #expect(save.career!.leagueTitles == 1 && save.career!.cups == 1)
        #expect(throws: GameError.seasonFinished) { try save.recordPlayed(goalsFor: 1, goalsAgainst: 0) }
        try save.startSeason(seed: 4)
        #expect(save.season!.matchday == 0 && save.season!.seed == 4)
        #expect(save.career!.leagueTitles == 1 && save.career!.cups == 1 && save.career!.team == .rocketlynx)
    }

    // MARK: - §2.2 the career

    @Test func aCareerIsChosenOnceAndStartingOverKeepsTraining() throws {
        var save = SaveRecord.fresh
        #expect(throws: GameError.noCareer) { try save.startSeason(seed: 1) }
        try save.chooseClub(.glowowls)
        #expect(save.board.pressing == 0.65 && save.board.covering == 0.65)   // the club's tactics (§2.2)
        #expect(throws: GameError.careerExists) { try save.chooseClub(.nebula) }
        #expect(throws: GameError.careerExists) { try save.createTeam(Self.draft()) }
        try save.startSeason(seed: 1)
        try save.recordPlayed(goalsFor: 1, goalsAgainst: 0)
        save.won(.shot)
        save.won(.pass)
        save.won(.shot)
        save.startOver()
        #expect(save.career == nil && save.season == nil)
        #expect(save.training.won == [.shot, .pass])
        try save.createTeam(Self.draft("  Moss Giants "))
        #expect(save.career!.created!.name == "Moss Giants")
        #expect(save.board.pressing == Tactics.defaults.pressing)
    }

    @Test func aDraftsIssuesAreTyped() throws {
        var save = SaveRecord.fresh
        #expect(throws: GameError.invalidTeam([.nameTooShort, .shortCodeIsAClubs])) {
            try save.createTeam(Self.draft("M", short: "MOS"))
        }
        #expect(save.career == nil)
        #expect(CreatedTeamRules.issues(Self.draft()).isEmpty)
    }

    @Test func thePaletteNeverClashesWithAClub() {
        #expect(Career.kitPalette.count == 12)
        let clubPrimaries = Set(Club.allCases.map(\.primary))
        #expect(Career.kitPalette.allSatisfy { !clubPrimaries.contains($0.primary) })
    }

    // MARK: - §12 the board, §11.5 quick match

    @Test func resetRestoresTheDefaultsOrThePickedClubsTactics() {
        #expect(BoardRecord.reset(for: nil) == .defaults)
        let rocket = BoardRecord.reset(for: .picked(.rocketlynx))
        #expect(rocket.pressing == 0.7 && rocket.pushUp == 0.75 && rocket.formation == .balanced && rocket.periodSeconds == 120)
    }

    @Test func aQuickMatchNeverDrawsThePlayersClubNorTouchesTheSeason() throws {
        let save = try Self.clubSeason(.kraken)
        for seed in UInt64(0)..<200 {
            #expect(QuickMatch(seed: seed, player: .kraken).opponent != .kraken)
        }
        #expect(Set((UInt64(0)..<200).map { QuickMatch(seed: $0, player: .created).opponent }).contains(.wolves))
        #expect(try Self.clubSeason(.kraken) == save)
    }
}
