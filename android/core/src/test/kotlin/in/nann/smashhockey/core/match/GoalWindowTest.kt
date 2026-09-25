package `in`.nann.smashhockey.core.match

import `in`.nann.smashhockey.core.generated.Formation
import `in`.nann.smashhockey.core.generated.Sport
import `in`.nann.smashhockey.core.generated.Tactics
import `in`.nann.smashhockey.core.generated.Tuning
import `in`.nann.smashhockey.core.math.DetMath
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import kotlin.math.PI

/**
 * §5.2: the goal is as wide a target as it actually looks. The twin of iOS's `GoalWindowTests.swift`.
 */
class GoalWindowTest {
    private val o = Tuning.Orbit

    /**
     * A match with the carrier and one team-mate placed by hand and everyone else parked, so only
     * those two are candidates for a snap.
     */
    private fun twoPlayers(me: Vec, mate: Vec): Triple<Match, Int, Int> {
        val side = SideSetup(75, Tactics.defaults, Formation.entries[0])
        val m = Match(MatchSetup(5L, Sport.FIELD, side, side, 120.0, 2.0, false, Control.PLAYER))
        while (m.state != MatchState.PLAY) m.tick()
        m.drainEvents()
        val mine = m.players.indices.filter { m.players[it].team == 0 && m.players[it].isOutfield }
        val c = mine[0]
        val mateIdx = mine[1]
        for (i in m.players.indices) {
            if (i == c || i == mateIdx) continue
            m.players[i].pos = Vec(13.0, i * 0.9 - 28.0)
            m.players[i].vel = Vec(0.0, 0.0)
        }
        m.players[c].pos = me
        m.players[c].vel = Vec(0.0, 0.0)
        m.players[mateIdx].pos = mate
        m.players[mateIdx].vel = Vec(0.0, 0.0)
        m.ball.carrier = c
        return Triple(m, c, mateIdx)
    }

    private fun radians(degrees: Double) = degrees * PI / 180

    /** The window at a distance, as §5.2 states it. */
    private fun window(d: Double) = Pitch.clamp(
        DetMath.atan2(Tuning.Pitch.goalMouthWidth / 2 * o.goalAimGenerosity, d),
        o.goalWindowMin, o.goalWindowMax)

    @Test fun theWindowIsTheGoalsOwnAngularHalfSize() {
        // It shrinks with distance — the property the old flat window did not have.
        var previous = Double.MAX_VALUE
        for (d in listOf(3.0, 5.0, 9.0, 14.0, 20.0, 26.0, 35.0, 45.0)) {
            val w = window(d)
            assertTrue("the window did not shrink from $previous at $d away", w < previous)
            previous = w
        }
        // And it is the arctangent, not something near it.
        assertEquals(DetMath.atan2(3.0 * 1.25, 20.0), window(20.0), 0.0)
        // Clamped at both ends.
        assertEquals(o.goalWindowMax, window(0.5), 0.0)
        assertEquals(o.goalWindowMin, window(1000.0), 0.0)
    }

    /**
     * The owner's case: deep in your own half, a short pass to a team-mate 20° off the line to the
     * far goal, and the release lands a little early. It must stay a pass.
     */
    @Test fun aReleaseMeantForATeamMateIsNotTakenByAGoalFortyMetresAway() {
        val me = Vec(0.0, -20.0)
        val mateAngle = radians(20.0)
        val mate = Vec(12 * DetMath.sin(mateAngle), -20 + 12 * DetMath.cos(mateAngle))
        val (m, c, _) = twoPlayers(me, mate)
        val dGoal = Pitch.length(0 - me.x, Pitch.attackGoalZ(0) - me.z)
        assertTrue("the case is meant to be a long way out ($dGoal)", dGoal > 40)

        for (off in listOf(0.0, 5.0, 8.0, 11.0, 14.0, 17.0)) {
            m.ball.orbit = radians(20 - off)
            assertTrue("released $off° off the mate and the goal took it",
                m.snap(c, m.ball.orbit) != Snap.Shot)
        }
        // And aimed straight down the line at the goal it is STILL not a shot: from your own half
        // the goal is not offered at all. The release is free — the ball goes where the arrow
        // points, it is simply not an assisted shot on goal.
        m.ball.orbit = 0.0
        assertTrue("the goal was offered from the carrier's own half", m.snap(c, 0.0) != Snap.Shot)
    }

    /** The other side of that: one step inside the attacking half, the goal is a target again. */
    @Test fun justInsideTheAttackingHalfTheGoalIsOfferedAgain() {
        val gz = Pitch.attackGoalZ(0)
        for ((distance, wanted) in listOf(o.goalSnapRange - 0.5 to true, o.goalSnapRange + 0.5 to false)) {
            val (m, c, _) = twoPlayers(Vec(0.0, gz - distance), Vec(9.0, gz - distance - 6))
            m.ball.orbit = 0.0
            assertEquals("at $distance from goal", wanted, m.snap(c, 0.0) == Snap.Shot)
        }
    }

    /** Close in, nothing should have got harder: the mouth really is that big from there. */
    @Test fun closeInTheGoalIsAtLeastAsEasyToAimAtAsItWas() {
        for (d in listOf(2.0, 3.0, 4.0, 5.0)) {
            // What the old rule gave: 0.40 widened by up to 0.30 closing from 14.
            val old = 0.40 + 0.30 * Pitch.clamp((14 - d) / 14, 0.0, 1.0)
            assertTrue("the window narrowed at $d away", window(d) >= old)
        }
    }

    /** And the far half of the same statement: from range it is much tighter than it was. */
    @Test fun fromRangeTheWindowIsAFractionOfWhatItWas() {
        for (d in listOf(20.0, 26.0, 35.0, 45.0)) {
            assertTrue("the window is still wide at $d away", window(d) < 0.40 * 0.5)
        }
    }

    /**
     * A0: the arrow cannot disagree with the release, because both read this one function. A release
     * at an angle that snaps to a shot must actually leave as one.
     */
    @Test fun whatSnapsToAShotLeavesAsAShot() {
        // Inside the attacking half, where a shot is a shot.
        val (m, c, _) = twoPlayers(Vec(0.0, 8.0), Vec(9.0, 14.0))
        m.ball.orbit = 0.0
        assertEquals(Snap.Shot, m.snap(c, 0.0))
        m.hold(true)
        m.tick()
        m.hold(false)
        repeat(12) { m.tick() }
        assertTrue("the snap said shot and no shot was emitted",
            m.drainEvents().any { it is MatchEvent.Shot })
    }
}
