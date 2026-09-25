package `in`.nann.smashhockey.core.match

import `in`.nann.smashhockey.core.generated.Formation
import `in`.nann.smashhockey.core.generated.Sport
import `in`.nann.smashhockey.core.generated.Tactics
import `in`.nann.smashhockey.core.generated.Tuning
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import kotlin.math.abs

/**
 * §7.8: a goalie reads a **shot** — a loose ball that will cross its line within the horizon — and
 * nothing else. The twin of iOS's `GoalieReadTests.swift`.
 */
class GoalieReadTest {
    private val team = 1                                  // the goal team 0 attacks
    private val gz = Pitch.ownGoalZ(team)
    private val dir = Pitch.direction(team)               // −1: toward this goal is +z

    /** A match in play with everyone parked out of the way, so only the ball moves the keeper. */
    private fun inPlay(): Pair<Match, Int> {
        val side = SideSetup(75, Tactics.defaults, Formation.entries[0])
        val m = Match(MatchSetup(3L, Sport.FIELD, side, side, 120.0, 2.0, false, Control.AUTOMATIC))
        while (m.state != MatchState.PLAY) m.tick()
        m.drainEvents()
        val g = m.players.indices.first { m.players[it].team == team && m.players[it].isGoalie }
        for (i in m.players.indices) {
            if (i == g) continue
            m.players[i].pos = Vec(13.0, i * 0.9 - 28.0)
            m.players[i].vel = Vec(0.0, 0.0)
        }
        m.ball.carrier = null
        m.ball.lastReleaseTime = null                     // no reaction delay in the way
        return m to g
    }

    /** Where §7.8's positioning line alone would put the keeper — the shading it does at range. */
    private fun lineOnly(m: Match): Double {
        val gl = Tuning.AI.Goalie
        val toBall = Pitch.unit(m.ball.pos.x, m.ball.pos.z - gz)
        val out = gl.outBase + gl.outPerSkill * m.skill[team]
        val limit = Tuning.Pitch.postX + gl.xLimitExtra
        return Pitch.clamp(toBall.x * out * gl.xScale, -limit, limit)
    }

    private fun keeperTargetX(m: Match, g: Int): Double {
        m.thinkGoalie(g, Tuning.Time.stepSeconds)
        return m.players[g].target!!.x
    }

    /**
     * The bug this rule was rewritten for: a player carrying the ball at the goal is not a shot,
     * however fast they skate. The keeper shades toward them and no more.
     */
    @Test fun aCarriedBallIsNeverReadAsAShot() {
        val (m, g) = inPlay()
        val carrier = m.players.indices.first { m.players[it].team == 0 && m.players[it].isOutfield }
        m.players[carrier].pos = Vec(5.0, gz - dir * -25.0)
        m.players[carrier].vel = Vec(0.0, -dir * 7.0)
        m.ball.carrier = carrier
        m.ball.pos = m.orbitPoint(carrier)
        m.ball.vel = m.players[carrier].vel
        val x = keeperTargetX(m, g)
        assertEquals("a carried ball moved the keeper off its line", lineOnly(m), x, 0.0)
        // And the shading really is gentle: nowhere near the post it used to be dragged to.
        assertTrue("the keeper shaded $x — that is a commitment, not a shade", abs(x) < 1.5)
    }

    /**
     * The other half: a loose ball that will not arrive is not a shot either. This is the branch
     * that used to fall back to the ball's *current* x.
     */
    @Test fun aLooseBallThatWillNotArriveIsNotReadEither() {
        val (m, g) = inPlay()
        // 30 out, drifting goalward at 5 m/s: six seconds away, well past the 2.5 s horizon.
        m.ball.pos = Vec(6.0, gz - dir * -30.0)
        m.ball.vel = Vec(0.0, -dir * 5.0)
        assertEquals("a ball six seconds away moved the keeper off its line",
            lineOnly(m), keeperTargetX(m, g), 0.0)
    }

    /** And the rule still does its job: a real shot is read and the keeper goes across. */
    @Test fun aRealShotIsReadAndTheKeeperGoesAcross() {
        val (m, g) = inPlay()
        // 15 out, travelling at 30 toward the line and across: half a second away.
        m.ball.pos = Vec(0.0, gz - dir * -15.0)
        m.ball.vel = Vec(4.0, -dir * 30.0)
        val x = keeperTargetX(m, g)
        assertNotEquals("a real shot was not read", lineOnly(m), x, 1e-12)
        assertTrue("the keeper did not move toward the side the shot is going ($x)", x > 0.5)
    }

    /**
     * A shot is only read once the keeper has had time to react to it (§7.8's delay), which is what
     * stops a keeper being perfect the instant the ball leaves a stick.
     */
    @Test fun aShotIsNotReadBeforeTheKeeperHasReacted() {
        val (m, g) = inPlay()
        m.ball.pos = Vec(0.0, gz - dir * -15.0)
        m.ball.vel = Vec(4.0, -dir * 30.0)
        m.ball.lastReleaseTime = m.time                   // released this very step
        assertEquals("the keeper read a shot with no delay", lineOnly(m), keeperTargetX(m, g), 0.0)
    }

    /** A ball travelling *away* from the goal is never read, whatever its speed. */
    @Test fun aBallGoingTheOtherWayIsNotRead() {
        val (m, g) = inPlay()
        m.ball.pos = Vec(3.0, gz - dir * -10.0)
        m.ball.vel = Vec(0.0, dir * 30.0)                 // straight back up the pitch
        assertEquals(lineOnly(m), keeperTargetX(m, g), 0.0)
    }
}
