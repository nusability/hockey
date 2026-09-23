import Foundation
import Testing
@testable import SmashCore

/// What a started match is made of (spec §2.2, §9, §10, §11, §12), and the save on the device (§15).
@Suite struct KickoffTests {
    static let jet = Career.kitPalette[0]

    static func season() throws -> SaveRecord {
        var save = SaveRecord.fresh
        try save.createTeam(TeamDraft(name: "Moss Giants", short: "MOG", primary: jet.primary,
                                      secondary: jet.secondary, world: .ocean))
        try save.startSeason(seed: 11)
        return save
    }

    @Test func theSeasonMatchIsTheFixtureInTheHomeTeamsWorldWithTheBoard() throws {
        var save = try Self.season()
        save.board.formation = .diamond
        save.board.periodSeconds = 90
        save.board.ballSpinSeconds = Tuning.Board.ballSpinSeconds[0]
        let fixture = save.playerFixture!
        let setup = save.seasonMatch(seed: 5)!
        let opponent = fixture.home == .created ? fixture.away : fixture.home
        #expect(setup.sport == save.career!.homeWorld(of: fixture.home).sport)
        #expect(setup.home.formation == .diamond && setup.home.rating == Career.createdRating)
        #expect(setup.away == .club(opponent.club!))
        #expect(setup.periodSeconds == 90 && setup.orbitPeriod == Tuning.Board.ballSpinSeconds[0])
        #expect(!setup.cup && setup.control == .player)
        // Passing and shooting stay the team's own — the defaults (§2.2); the rest is the board's (§12).
        #expect(setup.home.tactics.passing == Tactics.defaults.passing)
        #expect(setup.home.tactics.pressing == save.board.pressing)
    }

    @Test func aCupTieIsPlayedWithSuddenDeath() throws {
        var save = try Self.season()
        while case .league = Season.plan[save.season!.matchday] { try save.recordPlayed(goalsFor: 1, goalsAgainst: 0) }
        #expect(save.seasonMatch(seed: 1)!.cup)
    }

    @Test func beforeACareerThePlayerIsTheMossFoxes() {
        let save = SaveRecord.fresh
        #expect(save.sideTeam == TeamKey(Career.demoClub))
        #expect(save.seasonMatch(seed: 1) == nil)
        let quick = QuickMatch(seed: 3, player: save.sideTeam)
        let setup = save.quickMatch(quick, seed: 9)
        #expect(setup.home.rating == Career.demoClub.rating && setup.away == .club(quick.opponent))
        #expect(setup.sport == quick.world.sport && !setup.cup)
    }

    @Test func thePlayersTeamPlaysAtItsFixedRating() throws {
        var save = SaveRecord.fresh
        let jet = Self.jet
        try save.createTeam(TeamDraft(name: "Moss Giants", short: "MOG", primary: jet.primary, secondary: jet.secondary, world: .ocean))
        #expect(save.playerSide.rating == Career.createdRating)
        #expect(save.career!.homeWorld(of: .created) == .ocean)
        #expect(save.career!.kit(of: .created).primary == jet.primary)
    }

    @Test func drillsOpenInOrder() {
        var save = SaveRecord.fresh
        #expect(save.isOpen(Drill.allCases[0]) && !save.isOpen(Drill.allCases[1]))
        save.won(Drill.allCases[0])
        #expect(save.isOpen(Drill.allCases[1]) && !save.isOpen(Drill.allCases[2]))
        #expect(save.drill(Drill.allCases[1], seed: 1).orbitPeriod == save.board.ballSpinSeconds)
    }

    @Test func theBoardTakesOnlyItsOwnValues() throws {
        var save = SaveRecord.fresh
        var board = save.board
        board.periodSeconds = 100
        #expect(throws: GameError.notABoardValue) { try save.setBoard(board) }
        board.periodSeconds = 150
        board.pressing = 0.9
        try save.setBoard(board)
        #expect(save.board.pressing == 0.9)
        try save.createTeam(TeamDraft(name: "Moss Giants", short: "MOG", primary: Self.jet.primary,
                                      secondary: Self.jet.secondary, world: .ocean))
        save.resetBoard()
        #expect(save.board.pressing == Tactics.defaults.pressing && save.board.periodSeconds == Tuning.Board.periodSecondsDefault)
    }

    // MARK: - §15 the file

    static func directory() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("smash-save-\(UUID().uuidString)")
    }

    @Test func aMissingSaveIsANewPlayerAndAWrittenOneReadsBack() throws {
        let store = SaveStore(directory: Self.directory())
        #expect(store.load() == .new(.fresh))
        let save = try Self.season()
        try store.write(save)
        #expect(store.load() == .loaded(save))
        let names = try FileManager.default.contentsOfDirectory(atPath: store.directory.path)
        #expect(names == [SaveStore.fileName], "nothing but the save is left behind")
        #expect(try String(contentsOf: store.file, encoding: .utf8) == save.encoded())
    }

    @Test func aRefusedSaveIsKeptBesideTheNewOne() throws {
        let store = SaveStore(directory: Self.directory())
        try FileManager.default.createDirectory(at: store.directory, withIntermediateDirectories: true)
        let bad = Data("{\"version\": 99}".utf8)
        try bad.write(to: store.file)
        guard case .refused(let why) = store.load() else { Issue.record("a bad save must be refused"); return }
        #expect(why == "unknownVersion 99")
        #expect(try Data(contentsOf: store.file) == bad, "loading never touches the file")
        let (fresh, kept) = try store.replaceRefused()
        #expect(fresh == .fresh && kept?.lastPathComponent == "save.refused-1.json")
        #expect(try Data(contentsOf: kept!) == bad)
        #expect(store.load() == .loaded(.fresh))
        try bad.write(to: store.file)
        #expect(try store.replaceRefused().keptAt?.lastPathComponent == "save.refused-2.json")
    }
}
