package `in`.nann.smashhockey.core.telemetry

import `in`.nann.smashhockey.core.generated.Competition
import `in`.nann.smashhockey.core.generated.Env
import `in`.nann.smashhockey.core.generated.Envelope
import `in`.nann.smashhockey.core.generated.FeedbackRow
import `in`.nann.smashhockey.core.generated.Formation
import `in`.nann.smashhockey.core.generated.LoveAnswerKind
import `in`.nann.smashhockey.core.generated.LoveRow
import `in`.nann.smashhockey.core.generated.LoveTriggerKind
import `in`.nann.smashhockey.core.generated.MatchOutcome
import `in`.nann.smashhockey.core.generated.MatchRow
import `in`.nann.smashhockey.core.generated.Platform
import `in`.nann.smashhockey.core.generated.SeasonRow
import `in`.nann.smashhockey.core.generated.Sport
import `in`.nann.smashhockey.core.generated.World
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * The sending path (spec §18): the bounded outbox, where a row goes, which dataset it lands in, and
 * the exact bytes of each of the four rows. SmashCore's `TelemetrySendingTests` asserts the *same
 * expected JSON*, which is what makes the two builds' rows one dataset rather than two that look
 * alike.
 */
class SendingTest {

    // --- The fixture

    /**
     * One envelope, fixed. It says `ios` in both suites on purpose: the bytes are the contract, not a
     * fact about which machine ran the test.
     */
    private val envelope = Envelope(
        installId = "7c9e6f81-3b4a-4d2e-8a15-0f6b5c2d9e13",
        commit = "0123456789",
        at = 1_772_367_780_000L,
        platform = Platform.IOS,
        env = Env.STAGING,
        language = "en",
        synthetic = true,
    )

    private val match = TelemetryRow.Match(
        MatchRow.Body(
            sport = Sport.FIELD, world = World.MAGICWOOD, competition = Competition.LEAGUE,
            seasonNumber = 2, matchday = 5, goalsFor = 3, goalsAgainst = 2, result = MatchOutcome.WON,
            overtime = false, forfeit = false, durationMs = 360_000, periodMs = 120_000,
            formation = Formation.BALANCED, matchesPlayed = 21, trailed = true, hardFought = true,
        ),
    )

    private val season = TelemetryRow.Season(
        SeasonRow.Body(
            seasonNumber = 2, position = 1, points = 30, played = 14, won = 9, drawn = 3, lost = 2,
            goalsFor = 28, goalsAgainst = 14, champion = true, cupWon = false, matchesPlayed = 21,
        ),
    )

    private val love = TelemetryRow.Love(
        LoveRow.Body(
            trigger = LoveTriggerKind.HARD_FOUGHT, answer = LoveAnswerKind.POSITIVE,
            shownAt = 1_772_367_700_000L, matchesPlayed = 21,
        ),
    )

    private val feedback = TelemetryRow.Feedback(
        FeedbackRow.Body(
            message = "the goalie \"cheats\"\nfix it", trigger = LoveTriggerKind.HARD_FOUGHT,
            matchesPlayed = 21,
        ),
    )

    // --- The outbox (§18.8)

    @Test
    fun theOutboxKeepsWhatItIsGivenInOrder() {
        val outbox = Outbox()
        assertTrue(outbox.isEmpty)
        outbox.append(match)
        outbox.append(season)
        assertEquals(2, outbox.count)
        assertEquals(listOf(match, season), outbox.rows)
    }

    /**
     * The bound and the drop order together: past the bound the oldest goes, and the newest row — the
     * one that just happened — is always still there.
     */
    @Test
    fun pastTheBoundTheOldestRowGoes() {
        val outbox = Outbox()
        for (i in 0 until Outbox.BOUND + 5) {
            outbox.append(
                TelemetryRow.Love(
                    LoveRow.Body(LoveTriggerKind.CUP, LoveAnswerKind.DISMISSED, i.toLong(), i),
                ),
            )
        }
        assertEquals(Outbox.BOUND, outbox.count)
        // Five appended past the bound ⇒ the first five are gone, the last is the newest.
        assertEquals(5L, (outbox.rows.first() as TelemetryRow.Love).body.shownAt)
        assertEquals((Outbox.BOUND + 4).toLong(), (outbox.rows.last() as TelemetryRow.Love).body.shownAt)
    }

    @Test
    fun drainingTakesTheRowsAwayWithIt() {
        val outbox = Outbox()
        outbox.append(match)
        assertEquals(listOf(match), outbox.drain())
        // A failed send drops its rows (§18.8); it must not be able to find them again.
        assertTrue(outbox.isEmpty)
        assertTrue(outbox.drain().isEmpty())
    }

    // --- Where a row goes (§18.6)

    @Test
    fun eachRowNamesItsOwnTable() {
        assertEquals("matches", match.table)
        assertEquals("seasons", season.table)
        assertEquals("love", love.table)
        assertEquals("feedback", feedback.table)
    }

    @Test
    fun theTableIsTheRoute() {
        val ingest = Ingest.resolve("https://ingest.nann.in/smash/", "t", "0123456789", testRun = false)!!
        assertEquals("https://ingest.nann.in/smash", ingest.endpoint)
        assertEquals("https://ingest.nann.in/smash/matches", ingest.url(match))
        assertEquals("https://ingest.nann.in/smash/feedback", ingest.url(feedback))
    }

    // --- Staging, production, and silence in tests (§18.7)

    @Test
    fun onlyAReleaseBuildOfAStoreInstallReportsProduction() {
        assertEquals(Env.PRODUCTION, TelemetryEnv.of(debugBuild = false, storeInstall = true))
        assertEquals(Env.STAGING, TelemetryEnv.of(debugBuild = true, storeInstall = true))
        assertEquals(Env.STAGING, TelemetryEnv.of(debugBuild = false, storeInstall = false))
        assertEquals(Env.STAGING, TelemetryEnv.of(debugBuild = true, storeInstall = false))
    }

    /**
     * The teeth on §18.7: a fully configured client is **still** refused under a test run. Delete the
     * `testRun` gate and this fails — which is the point, because ../flashybird learned it the other
     * way round, with 329 events and 65 rows in production out of one `xcodebuild test`.
     */
    @Test
    fun aTestRunIsRefusedEvenFullyConfigured() {
        assertNull(Ingest.resolve("https://ingest.nann.in/smash", "t", "c", testRun = true))
    }

    @Test
    fun withoutConfigurationTheClientIsInert() {
        assertNull(Ingest.resolve(null, "t", "c", testRun = false))
        assertNull(Ingest.resolve("https://ingest.nann.in/smash", null, "c", testRun = false))
        assertNull(Ingest.resolve("https://ingest.nann.in/smash", "t", null, testRun = false))
        // An unsubstituted or empty build setting is an unset one, never an endpoint.
        assertNull(Ingest.resolve("  ", "t", "c", testRun = false))
        assertNull(Ingest.resolve("https://x/y", "", "c", testRun = false))
        // http:// is not a typo to forgive: the rows would go out in the clear.
        assertNull(Ingest.resolve("http://ingest.nann.in/smash", "t", "c", testRun = false))
    }

    // --- The bytes (§18.6)

    @Test
    fun aMatchRowIsTheseBytes() {
        assertEquals(
            """
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

            """.trimIndent(),
            match.encoded(envelope),
        )
    }

    @Test
    fun aSeasonRowIsTheseBytes() {
        assertEquals(
            """
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

            """.trimIndent(),
            season.encoded(envelope),
        )
    }

    @Test
    fun aLoveRowIsTheseBytes() {
        assertEquals(
            """
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

            """.trimIndent(),
            love.encoded(envelope),
        )
    }

    /**
     * The one row that carries a player's words (§18.5) — quotes and newlines and all, escaped by the
     * save's own writer rather than by anything invented here.
     */
    @Test
    fun aFeedbackRowIsTheseBytes() {
        assertEquals(
            """
            {
              "install_id": "7c9e6f81-3b4a-4d2e-8a15-0f6b5c2d9e13",
              "commit": "0123456789",
              "at": 1772367780000,
              "platform": "ios",
              "env": "staging",
              "language": "en",
              "synthetic": true,
              "message": "the goalie \"cheats\"\nfix it",
              "trigger": "hardFought",
              "matches_played": 21
            }

            """.trimIndent(),
            feedback.encoded(envelope),
        )
    }

    // --- Match time (§17.2, §18.2)

    @Test
    fun theClockIsMatchTimeAndNotWallTime() {
        // Three 120 s periods: the whole match is 360 000 ms.
        assertEquals(0, LoveMatch.elapsedMillis(1, 120.0, 120.0, overtime = false))
        assertEquals(60_000, LoveMatch.elapsedMillis(1, 60.0, 120.0, overtime = false))
        assertEquals(360_000, LoveMatch.elapsedMillis(3, 0.0, 120.0, overtime = false))
        assertEquals(210_000, LoveMatch.elapsedMillis(2, 30.0, 120.0, overtime = false))
        // Overtime reads as the whole match having run — a golden goal is the last goal there is.
        assertEquals(360_000, LoveMatch.elapsedMillis(3, 0.0, 120.0, overtime = true))
        // A late goal of a one-goal win is what arms the question (§17.2), and this is the boundary.
        assertTrue(LoveMatch(listOf(LoveMatch.Goal(true, 240_000)), 360_000).winningGoalWasLate)
        assertTrue(!LoveMatch(listOf(LoveMatch.Goal(true, 239_999)), 360_000).winningGoalWasLate)
    }
}
