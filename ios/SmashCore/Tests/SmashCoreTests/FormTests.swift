import Testing
@testable import SmashCore

/// The team detail behind a table row (spec §16.3a) and editing the created team (§2.2, §16.1).
@Suite struct FormTests {
    static func season(seed: UInt64 = 7) throws -> SaveRecord {
        var save = SaveRecord.fresh
        try save.createTeam(SeasonTests.draft())
        try save.startSeason(seed: seed)
        return save
    }

    /// Plays the player's league fixtures with the given scores, in order.
    static func play(_ save: inout SaveRecord, _ scores: [(Int, Int)]) throws {
        for (f, a) in scores { try save.recordPlayed(goalsFor: f, goalsAgainst: a) }
    }

    // MARK: - §16.3a the detail

    @Test func beforeAnythingIsPlayedTheFormIsEmptyAndTheNextFixtureIsTheFirst() throws {
        let save = try Self.season()
        let d = save.season!.detail(of: .created, career: save.career!)
        #expect(d.form.isEmpty)
        #expect(d.row.played == 0 && d.row.points == 0 && d.row.goalDifference == 0)
        #expect(d.next == save.playerFixture)
        #expect((1...8).contains(d.position))
        // Every club's detail is empty too, and each has a first fixture.
        for team in save.season!.teams {
            let c = save.season!.detail(of: team, career: save.career!)
            #expect(c.form.isEmpty && c.next?.matchday == 0)
        }
    }

    @Test func theFormIsTheLastThreeMostRecentFirstWithFewerEarlyOn() throws {
        var save = try Self.season()
        let career = save.career!
        try Self.play(&save, [(1, 0)])
        var d = save.season!.detail(of: .created, career: career)
        #expect(d.form.count == 1 && d.form[0].kind == .won && d.form[0].goalsFor == 1 && d.form[0].goalsAgainst == 0)
        #expect(d.row.played == 1 && d.row.won == 1 && d.row.points == 3)

        try Self.play(&save, [(0, 0), (0, 2)])
        d = save.season!.detail(of: .created, career: career)
        #expect(d.form.count == 3)
        #expect(d.form.map(\.kind) == [.lost, .drawn, .won])            // most recent first
        #expect(d.row.played == 3 && d.row.won == 1 && d.row.drawn == 1 && d.row.lost == 1)
        #expect(d.row.goalsFor == 1 && d.row.goalsAgainst == 2 && d.row.points == 4)

        try Self.play(&save, [(4, 1)])
        d = save.season!.detail(of: .created, career: career)
        #expect(d.form.count == Tuning.Season.formMatches)              // never more than three
        #expect(d.form.map(\.kind) == [.won, .lost, .drawn])
        #expect(d.form[0].goalsFor == 4 && d.form[0].goalsAgainst == 1 && !d.form[0].cup)
        // The detail's row is the team's row of the table, and its position the table's place.
        let standings = save.season!.table(career)
        #expect(standings[d.position - 1].team == .created && standings[d.position - 1] == d.row)
        // Its next fixture is the cup quarter-final it has not played (§11.1).
        #expect(d.next?.matchday == 4 && d.next?.score == nil)
        // A form match's side is the team's own: home and away agree with the fixture.
        for m in d.form { #expect(m.opponent != .created) }
    }

    @Test func aForfeitedCupTieIsTheMostRecentFormEntryAndNeverInTheTable() throws {
        var save = try Self.season()
        let career = save.career!
        try Self.play(&save, [(1, 0), (2, 0), (3, 0), (4, 0)])
        let before = save.season!.detail(of: .created, career: career).row
        #expect(save.season!.step == .cup(.quarterFinal))
        try save.forfeit()
        let d = save.season!.detail(of: .created, career: career)
        #expect(d.form[0].cup && d.form[0].kind == .lost)
        #expect(d.form[0].goalsFor == Tuning.Match.forfeitFor && d.form[0].goalsAgainst == Tuning.Match.forfeitAgainst)
        #expect(!d.form[0].overtime)
        // A cup result never moves the table (§11.4), so played, points and goals stand still.
        #expect(d.row == before)
        // Knocked out: the next fixture is a league round again.
        #expect(d.next.map { if case .league = Season.plan[$0.matchday] { true } else { false } } == true)
    }

    @Test func aClubsFormIsItsSimulatedResults() throws {
        var save = try Self.season()
        let career = save.career!
        try Self.play(&save, [(1, 0), (1, 0)])
        for team in save.season!.teams where team != .created {
            let d = save.season!.detail(of: team, career: career)
            #expect(d.form.count == 2 && d.row.played == 2)
            #expect(d.row.won + d.row.drawn + d.row.lost == 2)
            #expect(d.form.allSatisfy { !$0.cup && $0.opponent != team })
        }
    }

    @Test func atTheSeasonsEndThereIsNoNextFixture() throws {
        var save = try Self.season()
        while !save.season!.isFinished {
            if case .cup = save.season!.step! { try save.recordPlayed(goalsFor: 2, goalsAgainst: 1) }
            else { try save.recordPlayed(goalsFor: 2, goalsAgainst: 1) }
        }
        let d = save.season!.detail(of: .created, career: save.career!)
        #expect(d.next == nil && d.form.count == 3)
        #expect(d.row.played == 14 && d.row.won == 14)
    }

    // MARK: - §2.2, §16.1 editing the team

    @Test func editingKeepsTheSeasonAndItsResults() throws {
        var save = try Self.season()
        try Self.play(&save, [(3, 1), (0, 2)])
        let fixtures = save.season!.fixtures
        let titles = save.career!.leagueTitles
        var draft = save.career!.draft
        draft.name = "  Iron Puffins "
        draft.short = "IRP"
        draft.primary = Career.kitPalette[3].primary
        draft.secondary = Career.kitPalette[5].secondary
        draft.world = .himalaya
        try save.editTeam(draft)
        let c = save.career!
        #expect(c.created.name == "Iron Puffins")                       // kept without its spaces
        #expect(c.short(of: .created) == "IRP" && c.homeWorld(of: .created) == .himalaya)
        #expect(c.kit(of: .created) == (Career.kitPalette[3].primary, Career.kitPalette[5].secondary))
        // The season's fixtures name the team, not its name: nothing moved.
        #expect(save.season!.fixtures == fixtures && save.career!.leagueTitles == titles)
        #expect(save.season!.detail(of: .created, career: c).row.played == 2)
        #expect(save.season!.teams.contains(.created))
        // And it round-trips through the save file.
        let reread = try SaveRecord.decode(save.encoded())
        #expect(reread == save)
    }

    @Test func editingIsHeldToTheRulesOfCreating() throws {
        var save = try Self.season()
        let before = save.career!.created
        #expect(throws: GameError.invalidTeam([.nameTooShort, .shortCodeIsAClubs])) {
            var d = save.career!.draft
            d.name = "M"
            d.short = "GLW"                                             // the club it replaced still owns it
            try save.editTeam(d)
        }
        #expect(throws: GameError.invalidTeam([.primaryNotInPalette])) {
            var d = save.career!.draft
            d.primary = 0x00FF00
            try save.editTeam(d)
        }
        #expect(save.career!.created == before)
        var fresh = SaveRecord.fresh
        #expect(throws: GameError.noCareer) { try fresh.editTeam(SeasonTests.draft()) }
    }
}
