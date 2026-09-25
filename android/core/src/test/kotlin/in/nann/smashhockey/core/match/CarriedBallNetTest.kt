package `in`.nann.smashhockey.core.match

import `in`.nann.smashhockey.core.generated.Formation
import `in`.nann.smashhockey.core.generated.Sport
import `in`.nann.smashhockey.core.generated.Tactics
import `in`.nann.smashhockey.core.generated.Tuning
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import kotlin.math.abs

/**
 * §5.1: the ball on a carrier's orbit is kept out of both nets' cloth, by the nearest of the net's
 * three ways out, without the orbit angle or any aim moving. The twin of iOS's
 * `CarriedBallNetTests.swift`.
 */
class CarriedBallNetTest {
    private val gz = Pitch.ownGoalZ(1)                 // 26 — the goal team 0 attacks
    private val dir = Pitch.direction(1)               // −1: into this net is +z
    private val hw = Tuning.Pitch.goalMouthWidth / 2 + Tuning.Pitch.netFrameMargin
    private val deep = Tuning.Pitch.goalDepth + Tuning.Pitch.netFrameMargin
    private val ballRadius = Sport.FIELD.ballRadius

    /** How far inside the cloth a point is; 0 or less when it is clear of it. */
    private fun insideBy(p: Vec, r: Double): Double {
        val into = -dir * (p.z - gz)
        if (!(abs(p.x) < hw + r && into > -r && into < deep + r)) return 0.0
        return Pitch.lesser(Pitch.lesser(into + r, deep + r - into), hw + r - abs(p.x))
    }

    private fun match(): Match {
        val side = SideSetup(50, Tactics.defaults, Formation.entries[0])
        return Match(MatchSetup(1L, Sport.FIELD, side, side, 60.0, 2.0, false, Control.AUTOMATIC))
    }

    /**
     * The whole point: a carrier standing anywhere the rules allow, with the orbit swept right round,
     * never puts the ball in the cloth.
     */
    @Test fun noCarrierAnywhereCanPutTheBallInTheCloth() {
        val m = match()
        m.ball.carrier = 0
        var worst = 0.0
        var at = Vec(0.0, 0.0)
        for (xi in -60..60) {
            for (zi in -40..40) {
                val spot = Vec(xi * 0.25, gz - dir * (zi * 0.25))
                m.players[0].pos = spot
                m.constrainPlayers()
                // Only spots a player may actually stand in count.
                if (abs(m.players[0].pos.x - spot.x) >= 1e-12) continue
                if (abs(m.players[0].pos.z - spot.z) >= 1e-12) continue
                for (step in 0 until 72) {
                    m.ball.orbit = Pitch.wrap(step * Pitch.TWO_PI / 72)
                    val d = insideBy(m.orbitPoint(0), m.sport.ballRadius)
                    if (d > worst) { worst = d; at = m.orbitPoint(0) }
                }
            }
        }
        // The clamp puts the ball exactly on the cloth's plane, and a plane cannot be landed on
        // exactly in binary — an epsilon either side of it is the arithmetic, not a way through.
        assertTrue("ball reached $worst into the cloth at (${at.x}, ${at.z})", worst <= 1e-12)
    }

    @Test fun aBallBehindTheNetLeavesByTheBack() {
        val p = Vec(0.5, gz - dir * (deep - 0.1))
        val out = Pitch.pushOutOfNet(p, 1, ballRadius)
        assertEquals(p.x, out.x, 0.0)                              // straight out, no sideways shove
        assertEquals(gz - dir * (deep + ballRadius), out.z, 0.0)
    }

    @Test fun aBallBesideTheNetLeavesBySideNotByTheLongWayRound() {
        val p = Vec(hw - 0.05, gz - dir * (deep / 2))
        val out = Pitch.pushOutOfNet(p, 1, ballRadius)
        assertEquals(p.z, out.z, 0.0)
        assertEquals(hw + ballRadius, out.x, 0.0)
    }

    /**
     * The case that makes the mouth one of the three: a carrier a metre in front of the goal line has
     * its ball swing over the line, and shoving it out of the back instead would teleport it the
     * length of the net.
     */
    @Test fun aBallJustInsideTheMouthLeavesByTheMouth() {
        val p = Vec(0.0, gz - dir * 0.2)
        val out = Pitch.pushOutOfNet(p, 1, ballRadius)
        assertEquals(0.0, out.x, 0.0)
        assertEquals(gz + dir * ballRadius, out.z, 0.0)
        // And it really is the short way: the back would have been over a metre and a half.
        assertTrue(abs(out.z - p.z) < 1.0)
    }

    @Test fun aBallClearOfTheNetIsNotMovedAtAll() {
        val points = listOf(
            Vec(0.0, 0.0),
            Vec(0.0, gz - dir * -2.0),
            Vec(hw + ballRadius + 0.01, gz - dir * 0.5),
            Vec(0.0, gz - dir * (deep + ballRadius + 0.01)))
        for (p in points) {
            val out = Pitch.pushOutOfNet(p, 1, ballRadius)
            assertEquals("(${p.x}, ${p.z}) moved in x", p.x, out.x, 0.0)
            assertEquals("(${p.x}, ${p.z}) moved in z", p.z, out.z, 0.0)
        }
    }

    /**
     * A0: the clamp moves the ball, never the aim. `snap` reads the carrier's position and the orbit
     * angle, so a carrier whose ball is being held out of the net still aims where the arrow says.
     */
    @Test fun theAimIsUnchangedByTheClamp() {
        val m = match()
        m.ball.carrier = 0
        // Behind the net, where the clamp bites hardest.
        m.players[0].pos = Vec(0.0, gz - dir * (deep + m.players[0].radius + 0.01))
        m.constrainPlayers()
        for (step in 0 until 72) {
            val a = Pitch.wrap(step * Pitch.TWO_PI / 72)
            m.ball.orbit = a
            val clamped = m.orbitPoint(0)
            // The snap at this angle is a pure function of the carrier and the angle — the ball's
            // clamped position is not one of its inputs.
            val before = m.snap(0, a)
            m.ball.pos = clamped
            assertEquals(before, m.snap(0, a))
        }
    }
}
