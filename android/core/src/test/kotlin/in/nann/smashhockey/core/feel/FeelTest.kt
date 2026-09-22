package `in`.nann.smashhockey.core.feel

import `in`.nann.smashhockey.core.generated.CopyKey
import `in`.nann.smashhockey.core.generated.Role
import `in`.nann.smashhockey.core.generated.SoundCue
import `in`.nann.smashhockey.core.generated.Spot
import `in`.nann.smashhockey.core.match.DrillInterruption
import `in`.nann.smashhockey.core.match.MatchEvent
import `in`.nann.smashhockey.core.match.MatchResult
import `in`.nann.smashhockey.core.match.MatchSnapshot
import `in`.nann.smashhockey.core.match.MatchState
import `in`.nann.smashhockey.core.match.ReleaseKind
import kotlin.math.PI
import kotlin.math.abs
import kotlin.math.pow
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * feel/ (spec §5.2, §8.8, §16.4): the arrow's length, what each event sets off, the countdown and the
 * aim window, the mix and the voices. iOS's `FeelTests` checks the same list.
 */
class FeelTest {
    private val arrow = AimArrow.Params(16.0, 2.5, 1.6, 1.2, 1.2, 0.6, 0.5)

    private val params = MatchCues.Params(
        banner = MatchCues.Params.Seconds(2.2, 1.5, 2.4, 1.8, 0.9, 1.2, 2.4, 1.5),
        shakeGoal = 1.2, shakePost = 0.5, hapticWindow = 0.35, releaseLow = 0.35, releaseHigh = 1.0,
        releaseSlow = 12.0, releaseFast = 30.0, hapticSharp = 0.9, hapticGoal = 1.0, goalPulses = listOf(0.0, 0.5, 1.0),
        hapticAgainst = 0.4, hapticTick = 0.25, shotSlow = 12.0, shotFast = 30.0, countdown = 5,
        stingDelay = 1.3,
    )

    private fun snapshot(
        state: MatchState = MatchState.PLAY, clock: Double = 60.0, period: Int = 1, overtime: Boolean = false,
        ballX: Double = 0.0, ballVx: Double = 0.0, carrier: Int? = null, aim: MatchSnapshot.Aim? = null,
        playerCarrier: Boolean = false,
    ): MatchSnapshot {
        val players = (0 until 12).map { i ->
            MatchSnapshot.Player(if (i < 6) 0 else 1, if (i % 6 == 0) Role.GOALIE else Role.FORWARD, 1.0, i.toDouble(), -i.toDouble(), 0.0, 0.0, 0.0)
        }
        val b = MatchSnapshot.Ball(ballX, 0.0, ballVx, 0.0, 0.36, carrier, 0.0, 1.0)
        return MatchSnapshot(state, players, b, aim, playerCarrier, clock, listOf(0, 0), period, overtime, 0.0, null)
    }

    private fun banners(cues: List<Cue>) = cues.filterIsInstance<Cue.Show>().map { it.banner }
    private val centre = MatchEvent.FaceOff(Spot(0.0, 0.0))
    private fun near(a: Double, b: Double) = assertTrue("$a ≠ $b", abs(a - b) < 1e-9)

    // ---- the arrow (§5.2)

    @Test fun freeArrowStopsShortOfTheBoards() {
        near(AimArrow.length(AimArrow.Kind.Free, 0.0, 0.0, 0.0, 2.0, arrow), 14.8)
        assertEquals(2.5, AimArrow.length(AimArrow.Kind.Free, 12.0, 0.0, PI / 2, 2.0, arrow), 0.0)
        assertEquals(2.0, AimArrow.boards(12.0, 0.0, PI / 2, 2.0, arrow), 0.0)
    }

    @Test fun passAndShotArrowsReachTheirTarget() {
        near(AimArrow.length(AimArrow.Kind.Pass(0.0, 10.0), 0.0, 0.0, 0.0, 2.0, arrow), 6.9)
        near(AimArrow.length(AimArrow.Kind.Shot(26.0), 0.0, 14.0, 0.0, 2.0, arrow), 9.3)
        near(AimArrow.length(AimArrow.Kind.Pass(0.0, 25.0), 0.0, -5.0, 0.0, 2.0, arrow), 14.8)
    }

    @Test fun iceCornersStopTheArrowSooner() {
        val field = AimArrow.boards(10.0, 20.0, PI / 4, 2.0, arrow)
        val ice = AimArrow.boards(10.0, 20.0, PI / 4, 8.5, arrow)
        assertTrue(ice < field)
    }

    // ---- the scoreboard, 0:0 to 99:99 (§16.4)

    private val board = Scoreboard.metrics(0.14, 0.0112, 0.084, 0.30, 0.03)

    @Test fun everyScoreTheBoardCanShowKeepsItsLayout() {
        val want = 2 * Scoreboard.CARDS + 1
        for (home in 0..99) {
            for (away in listOf(0, 1, 9, 10, 11, 99)) {
                val text = Scoreboard.score(home, away)
                assertEquals("$home:$away is '$text'", want, text.length)
                assertEquals(1, text.count { it == ':' })
            }
        }
        assertEquals(" 0", Scoreboard.score(0))
        assertEquals(" 9", Scoreboard.score(9))
        assertEquals("10", Scoreboard.score(10))
        assertEquals("99", Scoreboard.score(99))
        assertEquals("99", Scoreboard.score(120))
        assertEquals(" 0", Scoreboard.score(-1))
        assertEquals(Scoreboard.BLANK, Scoreboard.score(9)[0])
        assertEquals('1', Scoreboard.score(10)[0])
    }

    @Test fun theTwoSidesAndTheirChipsNeverRunIntoEachOther() {
        val m = board
        assertTrue(m.scoreX - m.halfCards > 0)
        assertTrue(m.chipX - 0.30 / 2 >= m.scoreX + m.halfCards)
        assertTrue(m.boardWidth / 2 >= m.chipX + 0.30 / 2)
        assertTrue(m.halfCards > 0.14)
    }

    @Test fun aDrillsTargetSetsItsWidth() {
        assertEquals("0/3", Scoreboard.drill(0, 3))
        assertEquals("3/3", Scoreboard.drill(3, 3))
        assertEquals("3/3", Scoreboard.drill(9, 3))
        assertEquals(" 0/12", Scoreboard.drill(0, 12))
        assertEquals("10/12", Scoreboard.drill(10, 12))
        for (target in 1..99) {
            val width = Scoreboard.drill(0, target).length
            for (scored in 0..target) assertEquals(width, Scoreboard.drill(scored, target).length)
        }
    }

    // ---- the UI's arrivals and departures (conventions: UI)

    /** motion.json's `pop` in, `soft` out, `fade.seconds`. */
    private fun presence() = UIPresence(SpringToken(260.0, 13.0), SpringToken(160.0, 18.0))

    /** Runs [seconds] of 60 Hz frames. */
    private fun run(p: UIPresence, seconds: Double, reduceMotion: Boolean = false) {
        repeat((seconds * 60).toInt()) { p.advance(1.0 / 60, reduceMotion, FADE_SECONDS) }
    }

    @Test fun anArrivalEndsOnItsExactPose() {
        val p = presence()
        p.show()
        run(p, 0.1)
        assertTrue(p.phase == UIPresence.Phase.SHOWN && p.arrival < 1.0)
        run(p, 2.0)
        assertTrue(p.isSettledIn)
        assertEquals(1.0, p.arrival, 0.0)
    }

    @Test fun aLeaveAlwaysEndsHidden() {
        for (reduce in listOf(false, true)) {
            val p = presence()
            p.show()
            run(p, 2.0, reduce)
            p.hide()
            run(p, 0.05, reduce)
            assertEquals("$reduce", UIPresence.Phase.LEAVING, p.phase)
            run(p, 3.0, reduce)
            assertEquals("$reduce", UIPresence.Phase.HIDDEN, p.phase)
            assertTrue(!p.isVisible)
        }
    }

    /**
     * The bug that left a piece of UI hanging in the air: Reduce Motion is read every frame on
     * Android (the system animator scale, battery saver), so it can turn on or off in the middle of a
     * transition. Neither way of playing a leave may strand the other's.
     */
    @Test fun reduceMotionTurningOnOrOffMidLeaveStillFinishes() {
        for ((before, after) in listOf(false to true, true to false)) {
            val p = presence()
            p.show()
            run(p, 2.0, before)
            p.hide()
            run(p, 0.1, before)
            assertEquals("$before then $after", UIPresence.Phase.LEAVING, p.phase)
            run(p, 5.0, after)
            assertEquals("$before then $after", UIPresence.Phase.HIDDEN, p.phase)
        }
    }

    @Test fun aLeaveInterruptedByAShowComesBackAndCanLeaveAgain() {
        val p = presence()
        p.show()
        run(p, 2.0)
        p.hide()
        run(p, 0.1)
        p.show()
        run(p, 2.0)
        assertTrue(p.isSettledIn)
        assertEquals(1.0, p.arrival, 0.0)
        p.hide()
        run(p, 3.0)
        assertEquals(UIPresence.Phase.HIDDEN, p.phase)
    }

    @Test fun hidingBeforeAnArrivalBeginsCancelsIt() {
        val p = presence()
        p.show(0.5)
        p.hide()
        run(p, 2.0)
        assertTrue(p.phase == UIPresence.Phase.HIDDEN && !p.isVisible)
    }

    // ---- what the arrow shows, transition by transition (§5.2)

    /** One frame of the arrow, 1/60 s after the last. */
    private class Rig {
        val showing = AimArrow.Showing()
        var clock = 0.0

        fun frame(
            state: MatchState = MatchState.PLAY,
            playerCarrier: Boolean = true,
            carrier: Int? = 1,
            aim: MatchSnapshot.Aim? = MatchSnapshot.Aim.Unassisted,
        ): AimArrow.Look {
            clock += 1.0 / 60
            return showing.frame(state, playerCarrier, carrier, aim, clock, FADE_IN)
        }

        companion object { const val FADE_IN = 0.08 }
    }

    @Test fun theArrowShowsOnlyForThePlayersOwnCarrierInPlay() {
        val r = Rig()
        for (state in MatchState.entries) {
            assertEquals(state.name, state == MatchState.PLAY || state == MatchState.READY, r.frame(state).arrow)
        }
        assertTrue(!r.frame(playerCarrier = false).arrow)
        assertTrue(!r.frame(carrier = null).arrow)
        assertTrue(!r.frame(aim = null).arrow)
        assertTrue(r.frame().arrow)
    }

    @Test fun theArrowsColourSaysWhatAReleaseWouldDo() {
        val r = Rig()
        assertEquals(0, r.frame(aim = MatchSnapshot.Aim.Unassisted).colour)
        assertEquals(1, r.frame(aim = MatchSnapshot.Aim.Pass(3)).colour)
        assertEquals(2, r.frame(aim = MatchSnapshot.Aim.Shot).colour)
        assertTrue(!r.frame(aim = MatchSnapshot.Aim.Unassisted).snapped)
        assertTrue(r.frame(aim = MatchSnapshot.Aim.Shot).snapped)
    }

    /**
     * The whole reason the arrow has a state machine: a snap's fade must start at every beginning and
     * at no other time, and it must never run on for ever.
     */
    @Test fun theLockOnFadesInAtEverySnapBeginning() {
        val r = Rig()
        assertEquals(AimArrow.Lock.None, r.frame(aim = MatchSnapshot.Aim.Unassisted).lock)
        assertTrue(r.frame(aim = MatchSnapshot.Aim.Shot).fade < 0.3)
        repeat(4) { r.frame(aim = MatchSnapshot.Aim.Shot) }
        assertEquals(1.0, r.frame(aim = MatchSnapshot.Aim.Shot).fade, 0.0)
        repeat(600) { r.frame(aim = MatchSnapshot.Aim.Shot) }
        assertEquals(1.0, r.frame(aim = MatchSnapshot.Aim.Shot).fade, 0.0)
        val pass = MatchSnapshot.Aim.Pass(3)
        repeat(21) { r.frame(aim = pass) }
        assertEquals(1.0, r.frame(aim = pass).fade, 0.0)
        assertTrue(r.frame(carrier = 2, aim = pass).fade < 1.0)
        repeat(20) { r.frame(carrier = 2, aim = pass) }
        assertEquals(1.0, r.frame(carrier = 2, aim = pass).fade, 0.0)
        r.frame(state = MatchState.WHISTLE, aim = pass)
        assertTrue(r.frame(carrier = 2, aim = pass).fade < 1.0)
    }

    @Test fun aRestartedSceneClockDoesNotStickTheLockOn() {
        val r = Rig()
        repeat(20) { r.frame(aim = MatchSnapshot.Aim.Shot) }
        assertEquals(1.0, r.frame(aim = MatchSnapshot.Aim.Shot).fade, 0.0)
        r.clock = 0.0
        val look = r.frame(aim = MatchSnapshot.Aim.Shot)
        assertTrue(look.fade >= 0.0 && look.fade <= 1.0)
    }

    // ---- banners (§16.4)

    @Test fun theDrillsGetReadySaysWhy() {
        val c = MatchCues(params, drill = true, audible = true)
        val s = snapshot(state = MatchState.READY)
        assertEquals(listOf(CopyKey.EVENT_GET_READY), banners(c.hear(MatchEvent.Ready, s)).map { it.key })
        c.hear(MatchEvent.Goal(0, 1, null, false), snapshot(state = MatchState.GOAL))
        assertEquals(listOf(CopyKey.EVENT_NICE_AGAIN), banners(c.hear(MatchEvent.Ready, s)).map { it.key })
        val lost = banners(c.hear(MatchEvent.DrillInterrupted(DrillInterruption.SAVED), snapshot(state = MatchState.LOST)))
        assertEquals(listOf(Banner(CopyKey.EVENT_SAVED, style = Banner.Style.BAD, seconds = 1.2)), lost)
        assertEquals(listOf(CopyKey.EVENT_AGAIN), banners(c.hear(MatchEvent.Ready, s)).map { it.key })
        assertEquals(listOf(CopyKey.EVENT_RESET),
            banners(c.hear(MatchEvent.DrillInterrupted(DrillInterruption.DEAD_BALL), snapshot(state = MatchState.LOST))).map { it.key })
    }

    @Test fun periodsAreAnnounced() {
        val c = MatchCues(params, drill = false, audible = true)
        assertTrue(banners(c.hear(centre, snapshot(state = MatchState.FACE_OFF))).isEmpty())
        assertEquals(listOf(Banner(CopyKey.EVENT_PERIOD_END, listOf("1"), Banner.Style.INFO, 2.4)),
            banners(c.hear(MatchEvent.PeriodEnd(1), snapshot(state = MatchState.PERIOD_END))))
        assertEquals(listOf(Banner(CopyKey.EVENT_PERIOD, listOf("2"), Banner.Style.INFO, 1.5)),
            banners(c.hear(centre, snapshot(state = MatchState.FACE_OFF, period = 2))))
        assertEquals(listOf(CopyKey.EVENT_OVERTIME),
            banners(c.hear(MatchEvent.PeriodEnd(3), snapshot(state = MatchState.PERIOD_END, period = 3))).map { it.key })
        assertEquals(listOf(CopyKey.EVENT_SUDDEN_DEATH),
            banners(c.hear(centre, snapshot(state = MatchState.FACE_OFF, period = 3, overtime = true))).map { it.key })
        c.hear(MatchEvent.Goal(1, 7, null, false), snapshot(state = MatchState.GOAL))
        assertTrue(banners(c.hear(centre, snapshot(state = MatchState.FACE_OFF))).isEmpty())
    }

    @Test fun theLastPeriodsEndIsTheEndsBanner() {
        val c = MatchCues(params, drill = false, audible = true)
        assertTrue(banners(c.hear(MatchEvent.PeriodEnd(3), snapshot(state = MatchState.ENDED, period = 3))).isEmpty())
        val end = c.hear(MatchEvent.End(MatchResult.LOST), snapshot(state = MatchState.ENDED, period = 3))
        assertEquals(listOf(Banner(CopyKey.EVENT_FINAL, style = Banner.Style.BAD, seconds = 1.5)), banners(end))
        assertTrue(Cue.Sound(SoundCue.MATCH_RESULT_LOSE, null, 1.3) in end)
        assertTrue(Cue.Sound(SoundCue.MATCH_WHISTLE_END, null, 0.0) in end)
        val d = MatchCues(params, drill = true, audible = true)
        val won = d.hear(MatchEvent.End(MatchResult.WON), snapshot(state = MatchState.ENDED))
        assertEquals(listOf(Banner(CopyKey.RESULT_DRILL_WON, style = Banner.Style.GOOD, seconds = 1.5)), banners(won))
        assertTrue(Cue.Sound(SoundCue.MATCH_RESULT_WIN, null, 1.3) in won)
    }

    @Test fun goalsShakeAndCelebrate() {
        val c = MatchCues(params, drill = false, audible = true)
        val ours = c.hear(MatchEvent.Goal(0, 3, null, false), snapshot(state = MatchState.GOAL))
        assertTrue(Cue.Shake(1.2) in ours)
        assertEquals(listOf(Banner(CopyKey.EVENT_GOAL, style = Banner.Style.GOOD, seconds = 2.4)), banners(ours))
        assertEquals(3, ours.count { it is Cue.Feel && it.haptic == Haptic.Impact(1.0) })
        assertTrue(Cue.Feel(Haptic.Impact(1.0), 0.5) in ours)
        val theirs = c.hear(MatchEvent.Goal(1, 8, null, false), snapshot(state = MatchState.GOAL))
        assertEquals(listOf(Banner.Style.BAD), banners(theirs).map { it.style })
        assertTrue(Cue.Sound(SoundCue.MATCH_GOAL_AGAINST, null, 0.0) in theirs)
        assertTrue(Cue.Sound(SoundCue.MATCH_GOAL_HORN, null, 0.0) in ours && Cue.Sound(SoundCue.MATCH_GOAL_CHEER, null, 0.0) in ours)
        assertEquals(listOf(Cue.Show(Banner(CopyKey.EVENT_VERSUS, listOf("MOSS FOXES", "GLOW OWLS"), Banner.Style.INFO, 2.2))),
            c.intro("MOSS FOXES", "GLOW OWLS"))
    }

    @Test fun theDemoIsOnlySeen() {
        val c = MatchCues(params, drill = false, audible = false)
        assertEquals(listOf(Cue.Shake(1.2)), c.hear(MatchEvent.Goal(0, 3, null, false), snapshot(state = MatchState.GOAL)))
        assertEquals(listOf(Cue.Pop(PopKind.SAVE, 6.0, -6.0)), c.hear(MatchEvent.Save(6), snapshot()))
        assertTrue(c.intro("A", "B").isEmpty())
        assertTrue(c.frame(snapshot(clock = 3.0)).isEmpty())
    }

    @Test fun thePostShakesTheBoardsDoNot() {
        val c = MatchCues(params, drill = false, audible = true)
        assertEquals(listOf(Cue.Shake(0.5), Cue.Sound(SoundCue.MATCH_POST, 3.0, 0.0), Cue.Feel(Haptic.Sharp(0.9), 0.0)),
            c.hear(MatchEvent.Post, snapshot(ballX = 3.0)))
        assertEquals(listOf(Cue.Sound(SoundCue.MATCH_BOARD, -15.0, 0.0)), c.hear(MatchEvent.Board(20.0), snapshot(ballX = -15.0)))
    }

    @Test fun releasesScaleWithSpeedAndOnlyThePlayersBuzz() {
        val c = MatchCues(params, drill = false, audible = true)
        assertEquals(listOf(Cue.Sound(SoundCue.MATCH_SHOT_SOFT, 0.0, 0.0), Cue.Feel(Haptic.Impact(0.35), 0.0)),
            c.hear(MatchEvent.Shot(2, ReleaseKind.SHOT), snapshot(ballVx = 12.0)))
        assertEquals(Cue.Sound(SoundCue.MATCH_SHOT_MEDIUM, 0.0, 0.0), c.hear(MatchEvent.Shot(2, ReleaseKind.SHOT), snapshot(ballVx = 21.0))[0])
        assertEquals(listOf(Cue.Sound(SoundCue.MATCH_SHOT_HARD, 0.0, 0.0), Cue.Feel(Haptic.Impact(1.0), 0.0)),
            c.hear(MatchEvent.Shot(2, ReleaseKind.SHOT), snapshot(ballVx = 30.0)))
        assertEquals(1, c.hear(MatchEvent.Shot(0, ReleaseKind.SHOT), snapshot(ballVx = 20.0)).size)
        assertEquals(1, c.hear(MatchEvent.Pass(8, 9), snapshot(ballVx = 20.0)).size)
    }

    @Test fun theLastFiveSecondsTick() {
        val c = MatchCues(params, drill = false, audible = true)
        assertTrue(c.frame(snapshot(clock = 5.5)).isEmpty())
        assertEquals(2, c.frame(snapshot(clock = 4.99)).size)
        assertTrue(c.frame(snapshot(clock = 4.2)).isEmpty())
        assertEquals(2, c.frame(snapshot(clock = 3.99)).size)
        assertTrue(c.frame(snapshot(clock = 0.5, overtime = true)).isEmpty())
        assertTrue(c.frame(snapshot(state = MatchState.PERIOD_END, clock = 0.0)).isEmpty())
    }

    @Test fun enteringAWindowTicks() {
        val c = MatchCues(params, drill = false, audible = true)
        val tick = listOf(Cue.Feel(Haptic.Tick(0.35), 0.0))
        assertTrue(c.frame(snapshot(carrier = 1, aim = MatchSnapshot.Aim.Unassisted, playerCarrier = true)).isEmpty())
        assertEquals(tick, c.frame(snapshot(carrier = 1, aim = MatchSnapshot.Aim.Pass(2), playerCarrier = true)))
        assertTrue(c.frame(snapshot(carrier = 1, aim = MatchSnapshot.Aim.Pass(2), playerCarrier = true)).isEmpty())
        assertEquals(tick, c.frame(snapshot(carrier = 1, aim = MatchSnapshot.Aim.Shot, playerCarrier = true)))
        assertTrue(c.frame(snapshot(carrier = 7, aim = MatchSnapshot.Aim.Pass(8), playerCarrier = false)).isEmpty())
    }

    // ---- the mix (§8.8)

    @Test fun theMix() {
        assertTrue(abs(SoundMix.amplitude(-6.0) - 0.501187) < 1e-6)
        assertEquals(0.5, SoundMix.rate(1.05, 0.18, true, 0.5, 2.0), 0.0)
        assertEquals(1.05, SoundMix.rate(1.05, 0.18, false, 0.5, 2.0), 0.0)
        assertTrue(abs(SoundMix.rate(1.2, 0.45, true, 0.5, 2.0) - 0.54) < 1e-12)
        assertEquals(0.6, SoundMix.pan(15.0, 0.6), 0.0)
        assertEquals(-0.3, SoundMix.pan(-7.5, 0.6), 0.0)
        assertEquals(0.0, SoundMix.pan(null, 0.6), 0.0)
        val (l, r) = SoundMix.stereo(0.0)
        assertTrue(abs(l - r) < 1e-12 && abs(l * l + r * r - 1) < 1e-12)
        // ± semitones, uniformly: the ends and the middle of the draw.
        assertTrue(abs(SoundMix.pitch(1.0, 0.0) - 2.0.pow(-1.0 / 12)) < 1e-12)
        assertEquals(1.0, SoundMix.pitch(1.0, 0.5), 0.0)
        assertEquals(1.0, SoundMix.pitch(0.0, 0.9), 0.0)
    }

    @Test fun aVariantIsNeverTheSameTwiceInARow() {
        assertEquals(0, SoundMix.variant(1, 0, 0.7))
        assertEquals(2, SoundMix.variant(3, null, 0.99))
        for (last in 0 until 4) for (k in 0 until 100) {
            val v = SoundMix.variant(4, last, k / 100.0)
            assertTrue(v != last && v in 0 until 4)
        }
        // Every other variant is reachable.
        assertEquals(setOf(0, 2), (0 until 100).map { SoundMix.variant(3, 1, it / 100.0) }.toSet())
    }

    @Test fun voicesAreSharedByPriority() {
        val pool = VoicePool(3)
        // The face-off drop has one voice: a second play steals the first.
        assertEquals(0, pool.claim(SoundCue.MATCH_FACEOFF_DROP, 0.0, 1.0))
        assertEquals(0, pool.claim(SoundCue.MATCH_FACEOFF_DROP, 0.1, 1.0))
        assertEquals(1, pool.claim(SoundCue.UI_DIGIT_FLIP, 0.2, 1.0))      // priority 40
        assertEquals(2, pool.claim(SoundCue.UI_SLIDER_TICK, 0.3, 1.0))     // priority 30
        // Full: a higher priority steals the lowest; nothing lower, the play is dropped.
        assertEquals(2, pool.claim(SoundCue.MATCH_GOAL_HORN, 0.4, 1.0))
        assertNull(pool.claim(SoundCue.UI_DIGIT_FLIP, 0.5, 1.0))
        // A finished voice is free again.
        assertEquals(0, pool.claim(SoundCue.UI_DIGIT_FLIP, 1.15, 1.0))
    }

    /** Every event the match or the kit plays is declared in the bank (shared/data/sounds.toml). */
    @Test fun theBankHasEveryEventThePlayUses() {
        val used = listOf(SoundCue.MATCH_SHOT_SOFT, SoundCue.MATCH_SHOT_MEDIUM, SoundCue.MATCH_SHOT_HARD, SoundCue.MATCH_PASS,
            SoundCue.MATCH_RECEIVE, SoundCue.MATCH_BOARD, SoundCue.MATCH_BLOCK, SoundCue.MATCH_POST, SoundCue.MATCH_SAVE,
            SoundCue.MATCH_STEAL, SoundCue.MATCH_WHISTLE_SHORT, SoundCue.MATCH_WHISTLE_END, SoundCue.MATCH_FACEOFF_DROP,
            SoundCue.MATCH_GOAL_HORN, SoundCue.MATCH_GOAL_CHEER, SoundCue.MATCH_GOAL_AGAINST, SoundCue.MATCH_COUNTDOWN_TICK,
            SoundCue.MATCH_RESULT_WIN, SoundCue.MATCH_RESULT_LOSE, SoundCue.UI_BUTTON_PRESS, SoundCue.UI_DIGIT_FLIP,
            SoundCue.UI_PANEL_POP, SoundCue.UI_CAMERA_WHOOSH_LONG, SoundCue.UI_CAMERA_WHOOSH_SHORT, SoundCue.UI_ERROR,
            SoundCue.UI_SLIDER_TICK, SoundCue.UI_CONFETTI_POP)
        for (cue in used) assertTrue("${cue.key} has no files", cue.spec.field.isNotEmpty() && cue.spec.ice.isNotEmpty())
    }

    private companion object { const val FADE_SECONDS = 0.18 }
}
