package `in`.nann.smashhockey.core.match

import `in`.nann.smashhockey.core.generated.Formation
import `in`.nann.smashhockey.core.generated.Sport
import `in`.nann.smashhockey.core.generated.Tactics
import `in`.nann.smashhockey.core.generated.Tuning
import `in`.nann.smashhockey.core.math.DetMath
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import kotlin.math.abs
import kotlin.math.sign

/**
 * §5.4: the player's own shot goes where the arrow was pointing; an AI carrier's still goes to the
 * far side of the keeper. The twin of iOS's `ShotAimTests.swift`.
 */
class ShotAimTest {
    private val gz = Pitch.attackGoalZ(0)                    // 26 — the goal team 0 attacks
    private val half = Tuning.Pitch.postX - Tuning.Release.shotPostInset   // 2.15

    private fun match(control: Control = Control.PLAYER): Match {
        val side = SideSetup(75, Tactics.defaults, Formation.entries[0])
        return Match(MatchSetup(7L, Sport.FIELD, side, side, 60.0, 2.0, false, control))
    }

    /**
     * A carrier of the player's team [distance] out from the goal, the keeper parked at [keeperX],
     * the orbit set so the arrow points at [aimAt] on the goal line.
     */
    private fun rig(m: Match, distance: Double, keeperX: Double, aimAt: Double): Int {
        val c = m.outfield(0).first()
        m.state = MatchState.PLAY
        m.players[c].pos = Vec(0.0, gz - distance)
        m.players[c].vel = Vec.ZERO
        val g = m.goalieOf(1)
        if (g != null) {
            m.players[g].pos = Vec(keeperX, gz - 1.2)
            m.players[g].vel = Vec.ZERO
        }
        m.ball.carrier = c
        m.ball.orbitDirection = 1.0
        m.ball.orbit = Pitch.heading(aimAt - m.players[c].pos.x, gz - m.players[c].pos.z)
        m.ball.pos = m.orbitPoint(c)
        return c
    }

    /** Where the ball, having just left, crosses the goal line. */
    private fun crossing(m: Match): Double? {
        if (m.ball.carrier != null || m.ball.vel.z == 0.0) return null
        val t = (gz - m.ball.pos.z) / m.ball.vel.z
        if (t <= 0) return null
        return m.ball.pos.x + m.ball.vel.x * t
    }

    /**
     * The point the shot was *aimed* at, read back off its direction — which §5.4 measures from the
     * carrier, not from the orbit point the ball leaves from. With a standing carrier this is the
     * aim point exactly, so it is what to assert the clamp on.
     */
    private fun aimedAt(m: Match, c: Int): Double? {
        if (m.ball.carrier != null || m.ball.vel.z == 0.0) return null
        val run = gz - m.players[c].pos.z
        if (m.ball.vel.z * run <= 0) return null
        return m.players[c].pos.x + m.ball.vel.x * (run / m.ball.vel.z)
    }

    /**
     * The owner's case, and the whole of the change: the arrow past the keeper, on the keeper's own
     * side. The old rule sent every one of these to the other side.
     */
    @Test fun thePlayersShotGoesToTheSideTheArrowChose() {
        var wrongSide = 0
        var samples = 0
        var worstMiss = 0.0
        for (keeperX in listOf(-1.8, -0.9, 0.9, 1.8)) {
            for (distance in listOf(7.0, 12.0, 18.0)) {
                for (k in -7..7) {
                    val aimAt = k * 0.35
                    if (abs(aimAt - keeperX) < 0.5) continue     // "at the keeper" has no side
                    repeat(40) {
                        val m = match()
                        rig(m, distance, keeperX, aimAt)
                        m.playerLift()
                        val x = crossing(m) ?: return@repeat
                        samples++
                        if (sign(x - keeperX) != sign(aimAt - keeperX)) wrongSide++
                        worstMiss = Pitch.greater(worstMiss, abs(x - aimAt))
                    }
                }
            }
        }
        assertTrue(samples > 2000)
        assertEquals("shots that went to the other side of the keeper (of $samples)", 0, wrongSide)
        // Only the noise of an accuracy-1 release (±0.3) and the orbit point's offset stand between
        // the spot aimed at and the spot hit.
        assertTrue("worst miss $worstMiss m from the spot aimed at", worstMiss < 0.8)
    }

    /**
     * The assistance that stays: a release aimed outside the mouth still snaps to a shot (§5.2's
     * window is a little wider than the goal), and it is kept off the post rather than sent wide.
     */
    @Test fun anArrowOutsideTheMouthIsKeptOffThePost() {
        var tested = 0
        for (aimAt in listOf(-4.0, -3.2, 3.2, 4.0)) {
            val m = match()
            val c = rig(m, 12.0, 0.0, aimAt)
            if (m.snap(c, m.ball.orbit) != Snap.Shot) continue
            m.playerLift()
            val x = aimedAt(m, c) ?: continue
            tested++
            // The clamp, plus the ±0.3 noise of an accuracy-1 release.
            assertTrue("aimed $aimAt, shot aimed at $x", abs(x) <= half + 0.31)
            assertEquals(sign(aimAt), sign(x), 0.0)
        }
        assertTrue("no release outside the mouth snapped to a shot — the case is untested", tested > 0)
    }

    /** An AI carrier has no arrow (§7.6), so the keeper still decides: the far side, every time. */
    @Test fun anAiCarriersShotStillTakesTheFarSideOfTheKeeper() {
        for (keeperX in listOf(-1.8, 1.8)) {
            var sameSideAsKeeper = 0
            repeat(200) {
                val m = match(Control.AUTOMATIC)
                // Aimed straight at the keeper — under the old rule and this one alike, an AI shot
                // ignores that and goes the other way.
                val c = rig(m, 12.0, keeperX, keeperX)
                m.shoot(c, 1.0, Tuning.Release.shotSpeed, null)
                val x = crossing(m) ?: return@repeat
                if (sign(x) == sign(keeperX)) sameSideAsKeeper++
            }
            // The 25 % pull to 30 % of the corner can cross the middle once noise is added; the far
            // side is still where the great majority go.
            assertTrue("$sameSideAsKeeper/200 AI shots went to the keeper's side", sameSideAsKeeper < 40)
        }
    }

    /**
     * §5.3 rule 2 winds the orbit back to find a snap. That wound-back angle is the one the player
     * released on, so it is the one that aims — not the angle the orbit has moved on to.
     */
    @Test fun theLateGraceAimsFromTheAngleThatSnapped() {
        val m = match()
        val c = rig(m, 12.0, 1.8, 0.0)
        val toGoal = Pitch.heading(0.0 - m.players[c].pos.x, gz - m.players[c].pos.z)
        val window = Pitch.clamp(
            DetMath.atan2(Tuning.Pitch.goalMouthWidth / 2 * Tuning.Orbit.goalAimGenerosity, 12.0),
            Tuning.Orbit.goalWindowMin, Tuning.Orbit.goalWindowMax,
        )
        m.ball.orbit = Pitch.wrap(toGoal + window + 0.02)
        m.ball.pos = m.orbitPoint(c)
        assertNull(m.snap(c, m.ball.orbit))
        val aimedFrom = m.lateSnap(c)!!
        assertEquals(Snap.Shot, aimedFrom.first)
        val aimed = m.goalLineCrossing(c, aimedFrom.second, gz)!!
        val now = m.goalLineCrossing(c, m.ball.orbit, gz)!!
        // The two angles really do point at different parts of the goal, or this proves nothing.
        assertTrue(abs(aimed - now) > 0.5)
        m.playerLift()
        val x = crossing(m)!!
        assertTrue(
            "shot crossed $x; the angle that snapped aimed at $aimed, the one now at $now",
            abs(x - Pitch.clamp(aimed, -half, half)) < 0.8,
        )
    }

    /** The geometry itself: measured from the carrier, and null when the release leads away. */
    @Test fun theCrossingIsMeasuredFromTheCarrier() {
        val m = match()
        val c = rig(m, 10.0, 0.0, 0.0)
        m.players[c].pos = Vec(1.0, gz - 10)
        // Straight up the pitch from (1, 16): crosses the line at x = 1, whatever the ball is doing.
        assertEquals(1.0, m.goalLineCrossing(c, 0.0, gz)!!, 1e-9)
        // Pointing back up the pitch, away from that line: no crossing at all.
        assertNull(m.goalLineCrossing(c, Pitch.wrap(Pitch.TWO_PI / 2), gz))
        // Along the line is not a special case: the crossing runs away to a huge x, and the clamp in
        // `shoot` takes it to the post on that side. Nothing here divides by zero or goes NaN.
        val alongTheLine = m.goalLineCrossing(c, Pitch.TWO_PI / 4, gz)!!
        assertTrue(alongTheLine.isFinite() && abs(alongTheLine) > 1e6)
        assertEquals(half, Pitch.clamp(alongTheLine, -half, half), 0.0)
    }
}
