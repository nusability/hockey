package `in`.nann.smashhockey.core.match

import `in`.nann.smashhockey.core.generated.Formation
import `in`.nann.smashhockey.core.generated.Sport
import `in`.nann.smashhockey.core.generated.Tactics
import `in`.nann.smashhockey.core.generated.Tuning
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * §7.2: one challenger goes for the ball and the rest cover, and the role does not churn. The twin
 * of iOS's `ChallengeTests.swift`.
 */
class ChallengeTest {
    private val ch = Tuning.AI.Challenge

    /** A match in play with team 1 carrying, so team 0 is the defending side. */
    private fun theirBall(): Pair<Match, Int> {
        val side = SideSetup(75, Tactics.defaults, Formation.entries[0])
        val m = Match(MatchSetup(11L, Sport.FIELD, side, side, 120.0, 2.0, false, Control.AUTOMATIC))
        while (m.state != MatchState.PLAY) m.tick()
        m.drainEvents()
        val carrier = m.players.indices.first { m.players[it].team == 1 && m.players[it].isOutfield }
        // Park everyone else in a corner: only the defenders a test places are candidates.
        for (i in m.players.indices) {
            if (i == carrier) continue
            m.players[i].pos = Vec(13.0, i * 0.9 - 28.0)
            m.players[i].vel = Vec(0.0, 0.0)
        }
        m.players[carrier].pos = Vec(0.0, 0.0)
        m.players[carrier].vel = Vec(0.0, 0.0)
        m.ball.carrier = carrier
        // Pin the orbit, so "nearest to the ball" is a property of where the defenders stand and not
        // of where the ball happens to be swinging.
        m.ball.orbit = 0.0
        m.ball.pos = m.orbitPoint(carrier)
        return m to carrier
    }

    private fun mine(m: Match) =
        m.players.indices.filter { m.players[it].team == 0 && m.players[it].isOutfield }

    @Test fun onlyTheFirstChallengerGoesForTheBall() {
        val (m, carrier) = theirBall()
        val mine = mine(m)
        m.players[mine[0]].pos = Vec(-3.0, -4.0)
        m.players[mine[1]].pos = Vec(3.0, -4.0)
        val chosen = m.pickChallengers(0, carrier)
        assertTrue("the case needs two challengers (${chosen.size})", chosen.size >= 2)

        val ball = m.challengePoint()
        val cover = m.coverPoint(chosen[1], chosen[0])
        assertTrue(Pitch.distance(ball, m.ball.pos) < 2.5)
        assertTrue(Pitch.distance(cover, m.ball.pos) > ch.coverAhead - 1)
        // The cover point is goal-side of the carrier — between it and the goal it attacks.
        val gz = Pitch.ownGoalZ(0)
        val dir = Pitch.direction(0)
        assertTrue("the cover point is not goal-side of the carrier",
            -dir * (cover.z - m.players[carrier].pos.z) > 0)
        assertTrue("the cover point is no nearer the goal than the carrier",
            Pitch.length(cover.x, gz - cover.z) <
                Pitch.length(m.players[carrier].pos.x, gz - m.players[carrier].pos.z))
    }

    /** The bug that mattered most: the two defenders must not keep swapping jobs. */
    @Test fun theRoleDoesNotChurnWhileTheCommitmentLasts() {
        val (m, carrier) = theirBall()
        val mine = mine(m)
        // Both goal-side, so the sort's last tiebreak is distance to the ball.
        m.players[mine[0]].pos = Vec(-1.0, -4.0)
        m.players[mine[1]].pos = Vec(6.0, -4.0)
        val first = m.pickChallengers(0, carrier)[0]
        assertEquals("the near one should have taken the ball", mine[0], first)

        var handovers = 0
        var previous = first
        var sawTheOrderCross = false
        for (step in 1..40) {
            m.players[mine[0]].pos = Vec(-1.0 - step * 0.2, -4.0)
            m.players[mine[1]].pos = Vec(6.0 - step * 0.2, -4.0)
            if (Pitch.distance(m.players[mine[1]].pos, m.ball.pos) <
                Pitch.distance(m.players[mine[0]].pos, m.ball.pos)) sawTheOrderCross = true
            val now = m.pickChallengers(0, carrier)[0]
            if (now != previous) { handovers++; previous = now }
        }
        assertTrue("the case never actually crossed the ordering over", sawTheOrderCross)
        assertEquals("the job changed hands inside one commitment", 0, handovers)
        assertEquals(first, previous)
    }

    /** …but it is not sticky forever: once the commitment lapses, someone else can take it. */
    @Test fun onceTheCommitmentLapsesTheJobCanPassOn() {
        val (m, carrier) = theirBall()
        val mine = mine(m)
        m.players[mine[0]].pos = Vec(-2.0, -4.0)
        m.players[mine[1]].pos = Vec(8.0, -9.0)
        val first = m.pickChallengers(0, carrier)[0]
        m.time += ch.commitTime + 0.01
        m.players[first].pos = Vec(12.0, -12.0)
        val other = mine.first { it != first }
        m.players[other].pos = Vec(0.5, -2.0)
        assertEquals("the job never passed on after the commitment lapsed",
            other, m.pickChallengers(0, carrier)[0])
    }

    /** §4.6: a restart clears the role along with the commitment. */
    @Test fun aRestartClearsTheRole() {
        val (m, carrier) = theirBall()
        val mine = mine(m)
        m.players[mine[0]].pos = Vec(-3.0, -4.0)
        m.players[mine[1]].pos = Vec(3.0, -4.0)
        m.pickChallengers(0, carrier)
        assertTrue(m.players.any { it.onTheBall })
        m.clearForRestart()
        assertFalse("a restart left someone still on the ball", m.players.any { it.onTheBall })
        assertFalse(m.players.any { it.challengeUntil > 0 })
    }

    /** The cover point keeps its distance from the player going in, whichever side they are on. */
    @Test fun theCoverPointStaysClearOfThePlayerGoingIn() {
        val (m, carrier) = theirBall()
        val mine = mine(m)
        for (primarySide in listOf(-1.0, 1.0)) {
            m.players[mine[0]].pos = Vec(primarySide * 2, -3.0)
            m.players[mine[1]].pos = Vec(-primarySide * 2, -5.0)
            val chosen = m.pickChallengers(0, carrier)
            if (chosen.size < 2) continue
            val cover = m.coverPoint(chosen[1], chosen[0])
            val gap = Pitch.distance(cover, m.players[chosen[0]].pos)
            assertTrue("the cover point sat $gap from the player going in", gap >= ch.coverMinGap - 1e-9)
        }
    }
}
