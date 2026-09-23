import Testing
@testable import SmashCore

/// The sending path (spec §18): the bounded outbox, where a row goes, which dataset it lands in, and
/// the exact bytes of each of the four rows. `android/core`'s `OutboxTest` and `IngestTest` assert the
/// *same expected JSON*, which is what makes the two builds' rows one dataset rather than two that
/// look alike.
@Suite struct TelemetrySendingTests {

    // MARK: - The fixture

    /// One envelope, fixed. It says `ios` in both suites on purpose: the bytes are the contract, not
    /// a fact about which machine ran the test.
    static let envelope = Envelope(installId: "7c9e6f81-3b4a-4d2e-8a15-0f6b5c2d9e13", commit: "0123456789",
                                   at: 1_772_367_780_000, platform: .ios, env: .staging, language: "en",
                                   synthetic: true)

    static let match = TelemetryRow.match(MatchRow.Body(
        sport: .field, world: .magicwood, competition: .league, seasonNumber: 2, matchday: 5,
        goalsFor: 3, goalsAgainst: 2, result: .won, overtime: false, forfeit: false, durationMs: 360_000,
        periodMs: 120_000, formation: .balanced, matchesPlayed: 21, trailed: true, hardFought: true))

    static let season = TelemetryRow.season(SeasonRow.Body(
        seasonNumber: 2, position: 1, points: 30, played: 14, won: 9, drawn: 3, lost: 2,
        goalsFor: 28, goalsAgainst: 14, champion: true, cupWon: false, matchesPlayed: 21))

    static let love = TelemetryRow.love(LoveRow.Body(
        trigger: .hardFought, answer: .positive, shownAt: 1_772_367_700_000, matchesPlayed: 21))

    static let feedback = TelemetryRow.feedback(FeedbackRow.Body(
        message: "the goalie \"cheats\"\nfix it", trigger: .hardFought, matchesPlayed: 21))

    // MARK: - The outbox (§18.8)

    @Test func theOutboxKeepsWhatItIsGivenInOrder() {
        var outbox = Outbox()
        #expect(outbox.isEmpty)
        outbox.append(Self.match)
        outbox.append(Self.season)
        #expect(outbox.count == 2)
        #expect(outbox.rows == [Self.match, Self.season])
    }

    /// The bound and the drop order together: past the bound the oldest goes, and the newest row —
    /// the one that just happened — is always still there.
    @Test func pastTheBoundTheOldestRowGoes() {
        var outbox = Outbox()
        for i in 0..<(Outbox.bound + 5) {
            outbox.append(.love(LoveRow.Body(trigger: .cup, answer: .dismissed, shownAt: Int64(i), matchesPlayed: i)))
        }
        #expect(outbox.count == Outbox.bound)
        guard case .love(let first) = outbox.rows.first, case .love(let last) = outbox.rows.last else {
            Issue.record("the outbox lost the rows' kind")
            return
        }
        // Five appended past the bound ⇒ the first five are gone, the last is the newest.
        #expect(first.shownAt == 5)
        #expect(last.shownAt == Int64(Outbox.bound + 4))
    }

    @Test func drainingTakesTheRowsAwayWithIt() {
        var outbox = Outbox()
        outbox.append(Self.match)
        let batch = outbox.drain()
        #expect(batch == [Self.match])
        // A failed send drops its rows (§18.8); it must not be able to find them again.
        #expect(outbox.isEmpty)
        #expect(outbox.drain().isEmpty)
    }

    // MARK: - Where a row goes (§18.6)

    @Test func eachRowNamesItsOwnTable() {
        #expect(Self.match.table == "matches")
        #expect(Self.season.table == "seasons")
        #expect(Self.love.table == "love")
        #expect(Self.feedback.table == "feedback")
    }

    @Test func theTableIsTheRoute() throws {
        let ingest = try #require(Ingest.resolve(endpoint: "https://ingest.nann.in/smash/", token: "t",
                                                 commit: "0123456789", testRun: false))
        #expect(ingest.endpoint == "https://ingest.nann.in/smash")
        #expect(ingest.url(for: Self.match) == "https://ingest.nann.in/smash/matches")
        #expect(ingest.url(for: Self.feedback) == "https://ingest.nann.in/smash/feedback")
    }

    // MARK: - Staging, production, and silence in tests (§18.7)

    @Test func onlyAReleaseBuildOfAStoreInstallReportsProduction() {
        #expect(TelemetryEnv.of(debugBuild: false, storeInstall: true) == .production)
        #expect(TelemetryEnv.of(debugBuild: true, storeInstall: true) == .staging)
        #expect(TelemetryEnv.of(debugBuild: false, storeInstall: false) == .staging)
        #expect(TelemetryEnv.of(debugBuild: true, storeInstall: false) == .staging)
    }

    /// The teeth on §18.7: a fully configured client is **still** refused under a test run. Delete the
    /// `testRun` gate and this fails — which is the point, because `../flashybird` learned it the
    /// other way round, with 329 events and 65 rows in production out of one `xcodebuild test`.
    @Test func aTestRunIsRefusedEvenFullyConfigured() {
        #expect(Ingest.resolve(endpoint: "https://ingest.nann.in/smash", token: "t", commit: "c",
                              testRun: true) == nil)
    }

    @Test func withoutConfigurationTheClientIsInert() {
        #expect(Ingest.resolve(endpoint: nil, token: "t", commit: "c", testRun: false) == nil)
        #expect(Ingest.resolve(endpoint: "https://ingest.nann.in/smash", token: nil, commit: "c", testRun: false) == nil)
        #expect(Ingest.resolve(endpoint: "https://ingest.nann.in/smash", token: "t", commit: nil, testRun: false) == nil)
        // An unsubstituted or empty build setting is an unset one, never an endpoint.
        #expect(Ingest.resolve(endpoint: "  ", token: "t", commit: "c", testRun: false) == nil)
        #expect(Ingest.resolve(endpoint: "https://x/y", token: "", commit: "c", testRun: false) == nil)
        // http:// is not a typo to forgive: the rows would go out in the clear.
        #expect(Ingest.resolve(endpoint: "http://ingest.nann.in/smash", token: "t", commit: "c", testRun: false) == nil)
    }

    // MARK: - The bytes (§18.6)

    @Test func aMatchRowIsTheseBytes() {
        #expect(Self.match.encoded(Self.envelope) == """
        {
          "install_id": "7c9e6f81-3b4a-4d2e-8a15-0f6b5c2d9e13",
          "commit": "0123456789",
          "at": 1772367780000,
          "platform": "ios",
          "env": "staging",
          "language": "en",
          "synthetic": true,
          "sport": "field",
          "world": "magicwood",
          "competition": "league",
          "season_number": 2,
          "matchday": 5,
          "goals_for": 3,
          "goals_against": 2,
          "result": "won",
          "overtime": false,
          "forfeit": false,
          "duration_ms": 360000,
          "period_ms": 120000,
          "formation": "balanced",
          "matches_played": 21,
          "trailed": true,
          "hard_fought": true
        }

        """)
    }

    @Test func aSeasonRowIsTheseBytes() {
        #expect(Self.season.encoded(Self.envelope) == """
        {
          "install_id": "7c9e6f81-3b4a-4d2e-8a15-0f6b5c2d9e13",
          "commit": "0123456789",
          "at": 1772367780000,
          "platform": "ios",
          "env": "staging",
          "language": "en",
          "synthetic": true,
          "season_number": 2,
          "position": 1,
          "points": 30,
          "played": 14,
          "won": 9,
          "drawn": 3,
          "lost": 2,
          "goals_for": 28,
          "goals_against": 14,
          "champion": true,
          "cup_won": false,
          "matches_played": 21
        }

        """)
    }

    @Test func aLoveRowIsTheseBytes() {
        #expect(Self.love.encoded(Self.envelope) == """
        {
          "install_id": "7c9e6f81-3b4a-4d2e-8a15-0f6b5c2d9e13",
          "commit": "0123456789",
          "at": 1772367780000,
          "platform": "ios",
          "env": "staging",
          "language": "en",
          "synthetic": true,
          "trigger": "hardFought",
          "answer": "positive",
          "shown_at": 1772367700000,
          "matches_played": 21
        }

        """)
    }

    /// The one row that carries a player's words (§18.5) — quotes and newlines and all, escaped by the
    /// save's own writer rather than by anything invented here.
    @Test func aFeedbackRowIsTheseBytes() {
        #expect(Self.feedback.encoded(Self.envelope) == """
        {
          "install_id": "7c9e6f81-3b4a-4d2e-8a15-0f6b5c2d9e13",
          "commit": "0123456789",
          "at": 1772367780000,
          "platform": "ios",
          "env": "staging",
          "language": "en",
          "synthetic": true,
          "message": "the goalie \\"cheats\\"\\nfix it",
          "trigger": "hardFought",
          "matches_played": 21
        }

        """)
    }

    // MARK: - Match time (§17.2, §18.2)

    @Test func theClockIsMatchTimeAndNotWallTime() {
        // Three 120 s periods: the whole match is 360 000 ms.
        #expect(LoveMatch.elapsedMillis(period: 1, remainingSeconds: 120, periodSeconds: 120, overtime: false) == 0)
        #expect(LoveMatch.elapsedMillis(period: 1, remainingSeconds: 60, periodSeconds: 120, overtime: false) == 60_000)
        #expect(LoveMatch.elapsedMillis(period: 3, remainingSeconds: 0, periodSeconds: 120, overtime: false) == 360_000)
        #expect(LoveMatch.elapsedMillis(period: 2, remainingSeconds: 30, periodSeconds: 120, overtime: false) == 210_000)
        // Overtime reads as the whole match having run — a golden goal is the last goal there is.
        #expect(LoveMatch.elapsedMillis(period: 3, remainingSeconds: 0, periodSeconds: 120, overtime: true) == 360_000)
        // A late goal of a one-goal win is what arms the question (§17.2), and this is the boundary.
        let late = LoveMatch(goals: [.init(mine: true, atMillis: 240_000)], durationMillis: 360_000)
        #expect(late.winningGoalWasLate)
        let early = LoveMatch(goals: [.init(mine: true, atMillis: 239_999)], durationMillis: 360_000)
        #expect(!early.winningGoalWasLate)
    }
}
