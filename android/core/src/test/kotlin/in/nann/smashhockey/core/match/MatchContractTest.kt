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

    // §7.10 — the rubberband

    /** The temperament is drawn once, in range, and is the seed's — and a drill has none. */
    @Test fun aMatchDrawsOneTemperamentAndADrillDrawsNone() {
        val m = Match(match)
        val drawn = m.temperament
        assertTrue(drawn >= 0 && drawn <= Tuning.AI.Balance.temperamentMax)
        assertEquals(drawn, Match(match).temperament, 0.0)
        repeat(600) { m.tick() }
        assertEquals(drawn, m.temperament, 0.0)
        assertEquals(0.0, drill(Drill.SHOT).temperament, 0.0)
    }

    /** Level, or one goal in it, and the board's numbers reach §7 untouched — to the bit. */
    @Test fun aCloseScoreLeavesEveryTacticExactlyAsTheBoardSetIt() {
        val m = Match(match)
        for (lead in listOf(0, 1, -1)) {
            m.score[0] = if (lead > 0) lead else 0
            m.score[1] = if (lead < 0) -lead else 0
            m.period = 3
            m.clock = 0.0
            m.updateBalance()
            for (team in 0 until 2) {
                assertEquals(0.0, m.chase(team), 0.0)
                assertEquals(0.0, m.hold(team), 0.0)
                assertEquals(m.tactics[team], m.effectiveTactics(team))
            }
        }
    }

    /** It helps whoever is behind, whichever side that is, by the same amount. */
    @Test fun theTiltIsSymmetricBetweenTheTwoSides() {
        val m = Match(match)
        m.temperament = 1.0
        m.period = 2
        m.score[0] = 5
        m.score[1] = 1
        m.updateBalance()
        val chasing = m.chase(1)
        val holding = m.hold(0)
        assertTrue(chasing > 0)
        assertEquals(chasing, holding, 0.0)
        m.score[0] = 1
        m.score[1] = 5
        m.updateBalance()
        assertEquals(chasing, m.chase(0), 0.0)
        assertEquals(holding, m.hold(1), 0.0)
    }

    /** It grows with the lead and with the clock, and never past 1. */
    @Test fun theTiltGrowsWithTheLeadAndTheClock() {
        val m = Match(match)
        m.temperament = 1.0
        fun tilt(home: Int, away: Int, period: Int, clock: Double): Double {
            m.score[0] = home
            m.score[1] = away
            m.period = period
            m.clock = clock
            m.updateBalance()
            return m.chase(1)
        }
        val early2 = tilt(2, 0, 1, 60.0)
        val late2 = tilt(2, 0, 3, 0.0)
        val late4 = tilt(4, 0, 3, 0.0)
        assertTrue(early2 > 0 && early2 < late2 && late2 <= late4)
        assertTrue(late4 <= Tuning.AI.Balance.tiltMax)
        m.temperament = Tuning.AI.Balance.temperamentMax
        assertEquals(Tuning.AI.Balance.tiltMax, tilt(9, 0, 3, 0.0), 0.0)
    }

    /**
     * Only ever sharper, never softer (A0): the side ahead keeps its keeper and its marking, and
     * loses only appetite — pressing, push up, shooting.
     */
    @Test fun theSideAheadIsNeverMadeWorseAtDefending() {
        val m = Match(match)
        m.temperament = Tuning.AI.Balance.temperamentMax
        m.score[0] = 6
        m.score[1] = 0
        m.period = 3
        m.clock = 0.0
        m.updateBalance()
        val ahead = m.effectiveTactics(0)
        val behind = m.effectiveTactics(1)
        assertEquals(m.tactics[0].covering, ahead.covering, 0.0)   // never dulled
        assertTrue(ahead.pressing < m.tactics[0].pressing)
        assertTrue(ahead.pushUp < m.tactics[0].pushUp)
        assertTrue(ahead.shooting < m.tactics[0].shooting)
        assertTrue(ahead.discipline > m.tactics[0].discipline)
        assertTrue(behind.covering > m.tactics[1].covering)
        assertTrue(behind.pressing > m.tactics[1].pressing)
        assertTrue(behind.pushUp > m.tactics[1].pushUp)
        assertEquals(m.tactics[1].shooting, behind.shooting, 0.0)
    }

    /** A drill never tilts, whatever its score (§10). */
    @Test fun aDrillNeverTilts() {
        val m = drill(Drill.SHOT)
        m.score[0] = 5
        m.updateBalance()
        assertEquals(0.0, m.chase(0), 0.0)
        assertEquals(0.0, m.chase(1), 0.0)
        assertEquals(0.0, m.hold(0), 0.0)
        assertEquals(0.0, m.hold(1), 0.0)
    }

    // §8.9 — offside, the ice sport only

    private fun iceMatch(seed: Long = 42, sport: Sport = Sport.ICE) = MatchSetup(
        seed, sport, SideSetup.club(Club.WOLVES), SideSetup.club(Club.NEBULA), 60.0, 2.0,
        cup = false, control = Control.PLAYER,
    )

    /**
     * An ice match in play, the puck loose just outside the zone team 0 attacks, last touched by
     * team 0, with [deep] moved past the blue line by [beyond].
     */
    private fun aboutToEnter(deep: Int, beyond: Double, setup: MatchSetup = iceMatch()): Match {
        val m = Match(setup)
        while (m.state != MatchState.PLAY) m.tick()
        m.drainEvents()
        m.ball.carrier = null
        m.ball.pos = Vec(0.0, Tuning.Pitch.blueLineZ - 1)
        m.ball.vel = Vec.ZERO
        m.ball.lastTouch = m.outfield(0).first()
        m.inZone[0] = false
        m.inZone[1] = false
        m.players[deep].pos = Vec(4.0, Tuning.Pitch.blueLineZ + beyond)
        return m
    }

    /** Moves the puck into the zone and runs the rule once. Returns the events it emitted. */
    private fun enterZone(m: Match): List<MatchEvent> {
        m.ball.pos = Vec(m.ball.pos.x, Tuning.Pitch.blueLineZ + 0.5)
        m.checkOffside()
        return m.drainEvents()
    }

    @Test fun aPlayerInTheZoneBeforeThePuckIsWhistledOffside() {
        var whistled = 0
        var missed = 0
        for (seed in 0L until 40L) {
            val m = aboutToEnter(3, Tuning.Offside.playerMargin + 0.5, iceMatch(seed))
            val events = enterZone(m)
            assertEquals(1, m.offsideStrays)
            val call = events.filterIsInstance<MatchEvent.Offside>().firstOrNull()
            if (call != null) {
                whistled += 1
                assertEquals(0, call.team)
                assertEquals(3, call.player)
                assertEquals(MatchState.WHISTLE, m.state)
                assertEquals(0, m.offsideMissed)
                assertTrue(Tuning.Pitch.faceoffNeutral.any { it.x == m.restartSpot.x && it.z == m.restartSpot.z })
                assertEquals(Tuning.Offside.faceoffReferenceZ, m.restartSpot.z, 0.0)
            } else {
                missed += 1
                assertEquals(MatchState.PLAY, m.state)
                assertEquals(1, m.offsideMissed)
            }
        }
        assertEquals(40, whistled + missed)
        assertTrue("the miss must be rare: $missed of 40", whistled > 30)
        assertTrue("and it must happen", missed > 0)
    }

    @Test fun aPlayerOnTheLineIsOnside() {
        val m = aboutToEnter(3, Tuning.Offside.playerMargin - 0.1)
        assertTrue(enterZone(m).isEmpty())
        assertEquals(MatchState.PLAY, m.state)
    }

    @Test fun theCarrierAndTheLastTouchAreNeverOffside() {
        for (deep in listOf(3, 4)) {
            val m = aboutToEnter(deep, 3.0)
            if (deep == 3) {
                m.ball.lastTouch = 3
            } else {
                m.ball.carrier = 4
                m.ball.lastTouch = 4
            }
            assertTrue(enterZone(m).isEmpty())
        }
    }

    @Test fun aFieldMatchAndADrillAreNeverWhistledOffside() {
        val field = aboutToEnter(3, 3.0, iceMatch(sport = Sport.FIELD))
        assertTrue(enterZone(field).isEmpty())
        val d = drill(Drill.MOVING)                 // drill 5 — the ice world (§10)
        assertFalse(d.offsideApplies)
        assertTrue(d.offsidePlayers.none { it })
    }

    /**
     * The zone, once entered, is not clear again until the puck is 4.0 back out (§8.9): a puck
     * rattling on the line is one entry, not twenty.
     */
    @Test fun aPuckRattlingOnTheLineIsOneEntry() {
        val m = aboutToEnter(3, 3.0)
        enterZone(m)
        val after = m.offsideEntries
        for (z in listOf(Tuning.Pitch.blueLineZ - 1, Tuning.Pitch.blueLineZ + 1, Tuning.Pitch.blueLineZ - 2)) {
            m.state = MatchState.PLAY
            m.ball.pos = Vec(0.0, z)
            m.checkOffside()
        }
        assertEquals(after, m.offsideEntries)
        m.state = MatchState.PLAY
        m.ball.pos = Vec(0.0, Tuning.Pitch.blueLineZ - Tuning.Offside.clearDepth - 0.1)
        m.checkOffside()
        m.ball.pos = Vec(0.0, Tuning.Pitch.blueLineZ + 0.5)
        m.checkOffside()
        assertEquals(after + 1, m.offsideEntries)
    }

    /**
     * §5.2: the aim never snaps to a team-mate the whistle would punish, and the AI's pass score
     * reads the same predicate (§7.6).
     */
    @Test fun theAimNeverSnapsToAnOffsideTeamMate() {
        val m = aboutToEnter(1, 3.0)
        m.ball.carrier = 3
        m.players[3].pos = Vec(0.0, 0.0)
        m.players[1].pos = Vec(0.0, Tuning.Pitch.blueLineZ + 3)
        m.players[1].vel = Vec.ZERO
        m.ball.pos = Vec(0.0, 0.0)
        assertTrue(m.isOffsideReceiver(1))
        assertFalse(m.snap(3, 0.0) is Snap.Pass)    // the orbit pointing along +Z, at team-mate 1
        m.ball.pos = Vec(0.0, Tuning.Pitch.blueLineZ + 1)
        assertFalse(m.isOffsideReceiver(1))
    }

    /** §7.4: a supporter's target is held short of the line while the puck is short of it. */
    @Test fun theAttackHoldsTheBlueLineWhileThePuckIsShortOfIt() {
        val m = aboutToEnter(3, 3.0)
        m.ball.pos = Vec(0.0, 0.0)
        val wanted = Vec(2.0, Tuning.Pitch.blueLineZ + 5)
        assertEquals(Tuning.Pitch.blueLineZ - Tuning.Offside.holdBack, m.heldAtLine(3, wanted).z, 0.0)
        m.ball.pos = Vec(0.0, Tuning.Pitch.blueLineZ + 1)
        assertEquals(wanted.z, m.heldAtLine(3, wanted).z, 0.0)
        m.ball.pos = Vec(0.0, 0.0)
        m.ball.carrier = 3
        assertEquals(wanted.z, m.heldAtLine(3, wanted).z, 0.0)
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
