package `in`.nann.smashhockey.core.match

import `in`.nann.smashhockey.core.generated.Formation
import `in`.nann.smashhockey.core.generated.Sport
import `in`.nann.smashhockey.core.generated.Tactics
import `in`.nann.smashhockey.core.generated.Tuning
import org.junit.Assert.assertEquals
import org.junit.Test
import kotlin.math.abs

/**
 * §5.4: every release leaves **from the orbit point** — the one §5.1 has already kept out of both
 * nets — and from nowhere else. The twin of iOS's `ReleasePointTests.swift`.
 */
class ReleasePointTest {
    private fun match(): Match {
        val side = SideSetup(50, Tactics.defaults, Formation.entries[0])
        return Match(MatchSetup(1L, Sport.FIELD, side, side, 60.0, 2.0, false, Control.AUTOMATIC))
    }

    /** Puts the ball back on the orbit of carrier 0 after a release has taken it off. */
    private fun rearm(m: Match) {
        m.ball.carrier = 0
        m.ball.pending = null
        m.players[0].pickupCooldown = 0.0
    }

    /**
     * The bug this test exists for: a carrier standing behind a net released the ball **through the
     * cloth**, in front of the goal line, because §5.4 used to pull a release point with |z| > 25.7
     * back to within 25.5. Nothing may move the ball at the moment it leaves.
     */
    @Test fun aReleaseFromBehindANetDoesNotJumpThroughIt() {
        val m = match()
        rearm(m)
        val gz = Pitch.ownGoalZ(0)                              // −26, the net team 0 defends
        val dir = Pitch.direction(0)                            // into this net is −z
        val deep = Tuning.Pitch.goalDepth + Tuning.Pitch.netFrameMargin
        var jumped = 0
        for (xi in -14..14) {
            for (zi in 0..8) {
                val spot = Vec(xi * 0.25, gz - dir * (deep + m.players[0].radius + 0.05 + zi * 0.25))
                m.players[0].pos = spot
                m.constrainPlayers()
                if (abs(m.players[0].pos.x - spot.x) >= 1e-12) continue
                if (abs(m.players[0].pos.z - spot.z) >= 1e-12) continue
                for (step in 0 until 72) {
                    rearm(m)
                    m.ball.orbit = Pitch.wrap(step * Pitch.TWO_PI / 72)
                    m.ball.pos = m.orbitPoint(0)
                    m.releaseUnassisted(0, ReleaseKind.UNASSISTED)
                    // Behind the line is where the ball was; in front of it is through the net.
                    if (-dir * (m.ball.pos.z - gz) <= 0) jumped++
                }
            }
        }
        assertEquals("releases from behind the net that put the ball in front of it", 0, jumped)
    }

    /**
     * The general contract, both nets, every standable spot near them: the ball leaves from exactly
     * where it stands. §5.1 is the only thing that ever moves it, and it has already run.
     */
    @Test fun aReleaseLeavesFromWhereTheBallStands() {
        val m = match()
        for (team in 0 until 2) {
            val gz = Pitch.ownGoalZ(team)
            val dir = Pitch.direction(team)
            for (xi in -24..24) {
                for (zi in -8..16) {
                    val spot = Vec(xi * 0.25, gz - dir * (zi * 0.25))
                    m.players[0].pos = spot
                    m.constrainPlayers()
                    if (abs(m.players[0].pos.x - spot.x) >= 1e-12) continue
                    if (abs(m.players[0].pos.z - spot.z) >= 1e-12) continue
                    for (step in 0 until 24) {
                        rearm(m)
                        m.ball.orbit = Pitch.wrap(step * Pitch.TWO_PI / 24)
                        val from = m.orbitPoint(0)
                        m.ball.pos = from
                        m.releaseUnassisted(0, ReleaseKind.UNASSISTED)
                        assertEquals("release x", from.x, m.ball.pos.x, 0.0)
                        assertEquals("release z", from.z, m.ball.pos.z, 0.0)
                    }
                }
            }
        }
    }
}
