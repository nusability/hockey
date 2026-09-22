package `in`.nann.smashhockey.core.match

import `in`.nann.smashhockey.core.generated.Club
import `in`.nann.smashhockey.core.generated.Drill
import `in`.nann.smashhockey.core.generated.Sport
import `in`.nann.smashhockey.core.generated.Tactics
import `in`.nann.smashhockey.core.generated.Tuning
import `in`.nann.smashhockey.core.generated.World
import `in`.nann.smashhockey.core.math.DetMath
import kotlin.math.PI
import kotlin.math.abs
import kotlin.math.ceil
import kotlin.math.roundToInt
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * The simulation's contracts that are easy to state (spec §4–§10), checked directly rather than
 * through the golden vectors. iOS's `MatchContractTests` checks the same list.
 */
class MatchContractTest {
    private val dt = Tuning.Time.stepSeconds

    private fun drill(d: Drill, seed: Long = 7): Match {
        val m = Match(DrillSetup(d, seed, Tactics.defaults, 2.0))
        while (m.state != MatchState.PLAY) m.tick()
        m.drainEvents()
        return m
    }

    private val match = MatchSetup(
        42, Sport.FIELD, SideSetup.club(Club.MOSSFOXES), SideSetup.club(Club.ROCKETLYNX), 60.0, 2.0, cup = false,
        control = Control.PLAYER,
    )

    /** Carrier 0 at the origin, team-mate 1 at (10, 0), both still: the pass lies at π/2, the goal at 0. */
    private fun passAtRightAngle(): Match {
        val m = drill(Drill.PASS)
        m.players[0].pos = Vec(0.0, 0.0)
        m.players[0].vel = Vec.ZERO
        m.players[1].pos = Vec(10.0, 0.0)
        m.players[1].vel = Vec.ZERO
        m.ball.orbitDirection = 1.0
        return m
    }

    /** Team-mate 1 at (−10, 0): the pass at −π/2, approached from below with nothing behind. */
    private fun passAhead(): Match {
        val m = passAtRightAngle()
        m.players[1].pos = Vec(-10.0, 0.0)
        m.ball.orbit = -PI / 2 - 0.36 - m.omega * 0.12
        return m
    }

    private fun lift(m: Match) {
        m.hold(true)
        m.hold(false)
        m.tick()
    }

    // §4.1–§4.2 — time

    @Test fun sixtyAndOneTwentyHertzRunTheSameTicks() {
        for (scale in listOf(1.0, 0.45, 0.18)) {
            val a = Match(match)
            val b = Match(match)
            for (frame in 0 until 3600) {
                if (frame % 97 == 10) { a.hold(true); b.hold(true) }
                if (frame % 97 == 60) { a.hold(false); b.hold(false) }
                a.advance(1.0 / 60.0, scale)
                b.advance(1.0 / 120.0, scale)
                b.advance(1.0 / 120.0, scale)
                assertEquals(a.ticks, b.ticks)
                assertEquals(a.drainEvents(), b.drainEvents())
                assertEquals(MatchVector.sample(a), MatchVector.sample(b))
            }
            assertEquals((3600.0 / 60.0 * 120.0 * scale).roundToInt(), a.ticks)
        }
    }

    @Test fun aFrameGapIsClampedToATenthOfASecond() {
        val m = Match(match)
        assertEquals(12, m.advance(5.0, 1.0))
        assertEquals(0, m.advance(1.0 / 60.0, 0.0))
    }

    @Test fun aTapShorterThanATickStillReleases() {
        val m = passAtRightAngle()
        m.ball.orbit = PI / 2
        lift(m)
        assertTrue(m.drainEvents().contains(MatchEvent.Pass(0, 1)))
    }

    // §4.6 — restarts

    @Test fun aFaceOffClearsWhatARestartClearsAndKeepsThinkTimers() {
        val m = Match(MatchSetup.demo(3, World.MAGICWOOD, SideSetup.club(Club.MOSSFOXES), SideSetup.club(Club.ROCKETLYNX), 120.0))
        while (m.state != MatchState.GOAL) m.tick()
        val timers = m.players.map { it.thinkTimer }
        while (m.state == MatchState.GOAL) m.tick()
        assertEquals(MatchState.FACE_OFF, m.state)
        assertTrue(m.ball.carrier == null && m.ball.vel == Vec.ZERO && m.ball.lastTouch == null && m.ball.lastReleaser == null)
        assertTrue(m.ball.assist == null && m.ball.pending == null && m.looseTimer == 0.0)
        assertEquals(Vec(0.0, 0.0), m.ball.pos)
        for (p in m.players) {
            assertTrue(p.vel == Vec.ZERO && p.target == null && p.pickupCooldown == 0.0 && p.holdTime == 0.0)
            assertTrue(p.decision == null && p.mark == null && p.expectPass == 0.0 && p.stealContact == 0.0 && p.challengeUntil == 0.0)
        }
        assertEquals(timers, m.players.map { it.thinkTimer })
        assertEquals(Vec(0.0, -1.5), m.players[4].pos)
        assertTrue(m.players[6].pos.x == 0.0 && abs(m.players[6].pos.z - 24.7) < 1e-12)
    }

    @Test fun aDrillResetPutsEveryoneBackAndTheBallBehindThePlayer() {
        val m = drill(Drill.GOALIE)
        m.ball.carrier = null
        m.ball.pos = Vec(0.0, 23.2)
        m.ball.vel = Vec.ZERO
        m.tick()
        assertTrue(m.drainEvents().contains(MatchEvent.DrillInterrupted(DrillInterruption.SAVED)))
        while (m.state == MatchState.LOST) m.tick()
        assertEquals(MatchState.READY, m.state)
        assertEquals(m.players.map { it.start }, m.players.map { it.pos })
        assertEquals(0, m.ball.carrier)
    }

    // §5.2 — snapping

    @Test fun aPassSnapsWithinPoint36() {
        val m = passAtRightAngle()
        assertEquals(Snap.Pass(1), m.snap(0, PI / 2 + 0.35))
        assertEquals(Snap.Pass(1), m.snap(0, PI / 2 - 0.35))
        assertNull(m.snap(0, PI / 2 + 0.37))
        m.players[1].vel = Vec(0.0, 5.0)
        val lead = Pitch.heading(10.0, 0.8 * 5 * (10 / 16.5))
        assertEquals(Snap.Pass(1), m.snap(0, lead + 0.355))
        assertNull(m.snap(0, lead + 0.365))
    }

    @Test fun theGoalWindowWidensFrom14To0Away() {
        val m = passAtRightAngle()
        assertEquals(Snap.Shot, m.snap(0, 0.39))
        assertNull(m.snap(0, 0.41))
        m.players[0].pos = Vec(0.0, 19.0)
        m.players[1].pos = Vec(10.0, 19.0)
        assertEquals(Snap.Shot, m.snap(0, 0.54))
        assertNull(m.snap(0, 0.56))
    }

    @Test fun theGoalBeatsAPassOnlyWhenClearlyCloserInAngleOrWithin9() {
        val m = passAtRightAngle()
        m.players[1].pos = Vec(10 * DetMath.sin(0.2), 10 * DetMath.cos(0.2))
        assertEquals(Snap.Pass(1), m.snap(0, 0.1))
        assertEquals(Snap.Shot, m.snap(0, 0.05))
        m.players[0].pos = Vec(0.0, 18.0)
        m.players[1].pos = Vec(10 * DetMath.sin(0.2), 18 + 10 * DetMath.cos(0.2))
        assertEquals(Snap.Shot, m.snap(0, 0.19))
    }

    // §5.3 — late grace and pending

    @Test fun aLiftJustAfterTheWindowGoesThroughTheLateGrace() {
        val m = passAtRightAngle()
        m.ball.orbit = PI / 2 + 0.36 + m.omega * 0.1
        assertEquals(LiftOutcome.LATE_GRACE, m.previewLift())
        lift(m)
        assertTrue(m.drainEvents().contains(MatchEvent.Pass(0, 1)))
    }

    @Test fun aLiftJustBeforeTheWindowIsHeldPendingAndFiresOnTheSnap() {
        val m = passAhead()
        assertEquals(LiftOutcome.PENDING, m.previewLift())
        lift(m)
        assertTrue(m.ball.pending != null && m.ball.carrier == 0)
        m.hold(true)                                    // a new touch does not cancel it
        var fired = emptyList<MatchEvent>()
        for (i in 0 until 30) {
            if (fired.isNotEmpty()) break
            m.tick()
            fired = m.drainEvents().filterIsInstance<MatchEvent.Pass>()
        }
        assertEquals(listOf(MatchEvent.Pass(0, 1)), fired)
    }

    @Test fun aPendingReleaseIsCancelledWhenThePlayerLosesTheBall() {
        val m = passAhead()
        lift(m)
        assertNotNull(m.ball.pending)
        m.takeBall(1, reorient = true)
        assertNull(m.ball.pending)
    }

    @Test fun aLiftWithNothingToSnapLeavesUnassistedAt24() {
        val m = passAtRightAngle()
        m.ball.orbit = -PI / 2
        assertEquals(LiftOutcome.UNASSISTED, m.previewLift())
        lift(m)
        assertTrue(m.drainEvents().contains(MatchEvent.Shot(0, ReleaseKind.UNASSISTED)))
        assertNotNull(m.lastShotDistance)
    }

    // §6.4 — steal timing

    @Test fun aStealNeedsTheSettleWindowThenPoint18OfContact() {
        val m = drill(Drill.SLEEPY)
        val carrier = m.ball.carrier!!
        val thief = m.rosters[1][1]
        m.ball.wonAt = m.time
        var steps = 0
        while (m.ball.carrier == carrier && steps < 1000) {
            m.time += dt
            m.players[thief].pos = m.ball.pos
            m.checkSteal(carrier, dt)
            steps += 1
        }
        val settle = (Tuning.Ball.settleTime / dt).roundToInt()
        val contact = ceil(Tuning.Ball.stealTime / dt).toInt()
        assertTrue("stole after $steps steps", abs(steps - (settle + contact)) <= 1)
        assertEquals(thief, m.ball.carrier)
        assertEquals(Tuning.Ball.stealLoserCooldown, m.players[carrier].pickupCooldown, 0.0)
    }

    @Test fun contactIsLostTwiceAsFastOutOfReach() {
        val m = drill(Drill.SLEEPY)
        val carrier = m.ball.carrier!!
        val thief = m.rosters[1][1]
        m.ball.wonAt = m.time - 1
        m.players[thief].pos = m.ball.pos
        repeat(20) { m.checkSteal(carrier, dt) }
        m.players[thief].pos = Vec(m.ball.pos.x + 5, m.ball.pos.z)
        repeat(5) { m.checkSteal(carrier, dt) }
        assertEquals(10 * dt, m.players[thief].stealContact, 1e-12)
        repeat(6) { m.checkSteal(carrier, dt) }
        assertEquals(0.0, m.players[thief].stealContact, 0.0)
        assertEquals(carrier, m.ball.carrier)
    }

    // §10 — drill rules

    @Test fun theWrongNetInterruptsADrill() {
        val m = drill(Drill.SHOT)
        m.ball.carrier = null
        m.ball.lastTouch = 0
        m.ball.pos = Vec(0.0, -24.0)
        m.ball.vel = Vec(0.0, -25.0)
        repeat(30) { m.tick() }
        assertTrue(m.drainEvents().contains(MatchEvent.DrillInterrupted(DrillInterruption.WRONG_NET)))
        assertEquals(listOf(0, 0), m.scores)
        assertEquals(MatchState.LOST, m.state)
    }

    @Test fun theGiveAndGoCountsOnlyAssistedGoals() {
        val m = drill(Drill.PASS)
        m.players[0].pos = Vec(0.0, 14.0)
        m.ball.orbit = 0.0
        m.shoot(0, 1.0, 30.0)
        repeat(60) { m.tick() }
        assertTrue(m.drainEvents().contains(MatchEvent.DrillInterrupted(DrillInterruption.NO_ASSIST)))
        assertEquals(listOf(0, 0), m.scores)

        val n = drill(Drill.PASS)
        n.ball.carrier = null
        n.ball.lastTouch = 1
        n.takeBall(0, reorient = true)
        n.players[0].pos = Vec(0.0, 14.0)
        n.shoot(0, 1.0, 30.0)
        repeat(60) { n.tick() }
        assertTrue(n.drainEvents().contains(MatchEvent.Goal(0, 0, 1, false)))
        assertEquals(listOf(1, 0), n.scores)
    }

    @Test fun theDefenceTakingTheBallInterruptsWithTheReason() {
        val m = drill(Drill.SLEEPY)
        val d = m.players[m.rosters[1][1]]
        m.ball.carrier = null
        m.ball.pos = Vec(d.pos.x, d.pos.z - 1.2)
        m.ball.vel = Vec.ZERO
        m.tick()
        assertTrue(m.drainEvents().contains(MatchEvent.DrillInterrupted(DrillInterruption.STOLEN)))
    }

    @Test fun aDrillIsLostWhenTheClockRunsOut() {
        val m = Match(DrillSetup(Drill.SHOT, 1, Tactics.defaults, 2.0))
        while (m.state != MatchState.ENDED) m.tick()
        assertEquals(MatchResult.LOST, m.result)
        assertEquals(0.0, m.clock, 0.0)
        assertTrue(abs(m.ticks - ((Tuning.Training.ready + Drill.SHOT.seconds) * 120).toInt()) <= 1)
    }

    @Test fun aBallNobodyCollectsResetsADrill() {
        val m = drill(Drill.SHOT)
        m.ball.carrier = null
        m.ball.pos = Vec(0.0, -27.2)
        m.ball.vel = Vec.ZERO
        val seen = ArrayList<MatchEvent>()
        repeat(9 * 120) {
            m.tick()
            seen += m.drainEvents()
        }
        assertTrue(seen.contains(MatchEvent.DrillInterrupted(DrillInterruption.DEAD_BALL)))
    }

    // §8.6 — what presentation reads

    @Test fun aShotAboutToScoreIsReported() {
        val m = drill(Drill.SHOT)
        m.ball.carrier = null
        m.ball.pos = Vec(1.0, 20.0)
        m.ball.vel = Vec(0.0, 20.0)
        assertTrue(m.shotAboutToScore)
        m.ball.vel = Vec(0.0, 5.0)
        assertFalse(m.shotAboutToScore)
        m.ball.vel = Vec(20.0, 20.0)
        assertFalse(m.shotAboutToScore)
    }

    // Performance (§4)

    @Test fun aFullMatchRunsFarFasterThanRealTime() {
        val warm = Match(MatchSetup.demo(8, World.MAGICWOOD, SideSetup.club(Club.MOSSFOXES), SideSetup.club(Club.NEBULA), 120.0))
        while (warm.state != MatchState.ENDED) warm.tick()
        val m = Match(MatchSetup.demo(9, World.MAGICWOOD, SideSetup.club(Club.MOSSFOXES), SideSetup.club(Club.NEBULA), 120.0))
        val start = System.nanoTime()
        while (m.state != MatchState.ENDED) m.tick()
        val seconds = (System.nanoTime() - start) * 1e-9
        val simulated = m.ticks * Tuning.Time.tickSeconds
        println("full 3 × 120 s match: ${m.ticks} ticks ($simulated s) in $seconds s — ${(simulated / seconds).toInt()}× real time")
        assertTrue(simulated / seconds > 10)
    }
}
