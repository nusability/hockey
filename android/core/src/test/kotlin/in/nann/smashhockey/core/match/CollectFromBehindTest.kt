package `in`.nann.smashhockey.core.match

import `in`.nann.smashhockey.core.generated.Formation
import `in`.nann.smashhockey.core.generated.Sport
import `in`.nann.smashhockey.core.generated.Tactics
import `in`.nann.smashhockey.core.generated.Tuning
import `in`.nann.smashhockey.core.math.DetMath
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import kotlin.math.PI
import kotlin.math.abs

/**
 * §6.3.1: a ball arriving from behind an outfield player is not reliably collected — it is gathered
 * rarely, ricochets off them, or runs on past them. The twin of iOS's `CollectFromBehindTests.swift`.
 */
class CollectFromBehindTest {
    private val b = Tuning.Ball
    private val ballRadius = Sport.FIELD.ballRadius

    private enum class Outcome { COLLECTED, RICOCHETED, RAN_ON }

    /**
     * A match with every player parked out of the way, so [pickUp] can only ever choose the subject.
     * Positions are set straight onto the athletes: nothing here is a legal match state, and nothing
     * here constrains them back onto the pitch.
     */
    private fun match(seed: Long, control: Control = Control.AUTOMATIC): Match {
        val side = SideSetup(50, Tactics.defaults, Formation.entries[0])
        val m = Match(MatchSetup(seed, Sport.FIELD, side, side, 60.0, 2.0, false, control))
        for ((i, p) in m.players.withIndex()) p.pos = Vec(200.0 + i, 200.0)
        m.ball.carrier = null
        m.ball.lastTouch = null
        return m
    }

    /** An outfield player of [team] — roster index 0 is the goalie, whom §6.3.1 exempts. */
    private fun outfield(m: Match, team: Int = 0): Int = m.rosters[team].first { m.players[it].isOutfield }

    /**
     * Put [subject] at the origin facing [facing], with the ball 1.0 away and closing at [speed]
     * along [travel], then run §6.3's pickup. Returns what became of it.
     */
    private fun offer(
        m: Match,
        subject: Int,
        facing: Double,
        travel: Vec,
        speed: Double,
        playerVel: Vec = Vec.ZERO,
    ): Outcome {
        val p = m.players[subject]
        p.pos = Vec.ZERO
        p.vel = playerVel
        p.facing = facing
        p.pickupCooldown = 0.0
        m.ball.carrier = null
        m.ball.pos = Vec(0.0, -1.0)
        m.ball.vel = Vec(travel.x * speed, travel.z * speed)
        m.events.clear()
        val before = m.ball.vel
        m.pickUp(ballRadius)
        if (m.ball.carrier == subject) return Outcome.COLLECTED
        if (m.ball.vel == before) return Outcome.RAN_ON
        return Outcome.RICOCHETED
    }

    /** A ball travelling +z meets a player facing +z from directly behind: the worst case. */
    private fun fromBehind(m: Match, subject: Int = outfield(m), speed: Double = 15.0): Outcome =
        offer(m, subject, 0.0, Vec(0.0, 1.0), speed)

    // What is unaffected

    /**
     * A ball met head-on is collected, every time, and **takes nothing from §4.3's stream** — the one
     * property that keeps the rule from rewriting every ordinary pickup in the corpus.
     */
    @Test fun aBallMetHeadOnIsAlwaysCollectedAndCostsNoRandomness() {
        for (seed in 0L until 200L) {
            val m = match(seed)
            val state = m.streamState
            assertEquals(Outcome.COLLECTED, offer(m, outfield(m), 0.0, Vec(0.0, -1.0), 15.0))
            assertEquals(state, m.streamState)
            assertTrue(m.events.isNotEmpty())    // a pickup, not a fumble
        }
    }

    /** The free cone is 60° wide either side of facing: at 59° nothing applies and no draw is made. */
    @Test fun insideTheSixtyDegreeConeNothingApplies() {
        val inside = PI - 59.0 / 180.0 * PI      // arrives 59° off the player's facing
        for (seed in 0L until 200L) {
            val m = match(seed)
            val state = m.streamState
            val travel = Vec(DetMath.sin(inside), DetMath.cos(inside))
            assertEquals(Outcome.COLLECTED, offer(m, outfield(m), 0.0, travel, 15.0))
            assertEquals(state, m.streamState)
        }
    }

    /** Past it, it bites: at 61° a draw is made and the ball is sometimes lost. */
    @Test fun justOutsideTheConeTheRuleStartsToBite() {
        val outside = PI - 61.0 / 180.0 * PI
        var lost = 0
        for (seed in 0L until 400L) {
            val m = match(seed)
            val state = m.streamState
            val travel = Vec(DetMath.sin(outside), DetMath.cos(outside))
            val out = offer(m, outfield(m), 0.0, travel, 15.0)
            assertNotEquals(state, m.streamState)            // the draw happened
            if (out != Outcome.COLLECTED) lost++
        }
        assertTrue(lost > 0)
    }

    /**
     * **A slow roll stays collectable**, however far behind it comes from: under 4 relative, the
     * speed factor is zero and no draw is made.
     */
    @Test fun aSlowRollFromBehindIsAlwaysCollected() {
        for (seed in 0L until 200L) {
            val m = match(seed)
            val state = m.streamState
            assertEquals(Outcome.COLLECTED, fromBehind(m, speed = b.collectSlowSpeed - 0.5))
            assertEquals(state, m.streamState)
        }
    }

    /**
     * A ball keeping pace with its receiver is at rest relative to them, so it is theirs however fast
     * the two are moving down the pitch — the "trailing pass that barely catches you" case.
     */
    @Test fun aBallKeepingPaceWithItsReceiverIsCollected() {
        for (seed in 0L until 100L) {
            val m = match(seed)
            val out = offer(m, outfield(m), 0.0, Vec(0.0, 1.0), 14.0, Vec(0.0, 13.0))
            assertEquals(Outcome.COLLECTED, out)
        }
    }

    /**
     * **Goalies are exempt** — §3 pins their facing down the pitch, so an angle from it means
     * nothing. Their own low limit (9) is what guards them.
     */
    @Test fun goaliesAreExempt() {
        for (seed in 0L until 100L) {
            val m = match(seed)
            val keeper = m.players.indices.first { m.players[it].isGoalie }
            val state = m.streamState
            // 8 is under the goalie's limit of 9, and arrives from straight behind their pinned facing.
            assertEquals(Outcome.COLLECTED, fromBehind(m, keeper, 8.0))
            assertEquals(state, m.streamState)
        }
    }

    // The three outcomes

    /**
     * Straight from behind and at pace: collected 8 % of the time, and of the rest, 40 % ricochet and
     * 60 % run on. The shares are the spec's, measured over a few thousand draws.
     */
    @Test fun straightFromBehindSplitsThreeWays() {
        val counts = Outcome.entries.associateWith { 0 }.toMutableMap()
        val trials = 4000
        for (seed in 0L until trials.toLong()) {
            val out = fromBehind(match(seed))
            counts[out] = counts.getValue(out) + 1
        }
        val collected = counts.getValue(Outcome.COLLECTED).toDouble() / trials
        val ricochet = counts.getValue(Outcome.RICOCHETED).toDouble() / trials
        val ranOn = counts.getValue(Outcome.RAN_ON).toDouble() / trials
        assertTrue(abs(collected - (1 - b.collectPressureWeight)) < 0.02)
        assertTrue(abs(ricochet - b.collectPressureWeight * b.collectRicochetShare) < 0.03)
        assertTrue(abs(ranOn - b.collectPressureWeight * (1 - b.collectRicochetShare)) < 0.03)
        // All three really happen — the point of the rule is that it is not a binary.
        assertTrue(counts.values.all { it > 0 })
    }

    /**
     * A fumble is a touch, it is emitted, and the fumbler cannot have the ball back — nor steal it —
     * for 0.35 s. That cooldown is what makes this one event and not a coin flipped every step.
     */
    @Test fun aFumbleIsATouchAndCostsTheFumblerTheNextMoment() {
        var seen = 0
        for (seed in 0L until 400L) {
            if (seen >= 20) break
            val m = match(seed)
            val subject = outfield(m)
            if (fromBehind(m) == Outcome.COLLECTED) continue
            seen++
            assertEquals(subject, m.ball.lastTouch)
            assertEquals(b.collectFumbleCooldown, m.players[subject].pickupCooldown, 0.0)
            assertTrue(m.events.any { it is MatchEvent.Fumble && it.player == subject })
            // Offered again on the very next step, still in reach, they cannot take it.
            m.ball.pos = Vec(0.0, -1.0)
            m.pickUp(ballRadius)
            assertEquals(null, m.ball.carrier)
        }
        assertEquals(20, seen)
    }

    /**
     * A ricochet keeps 55 % of the approach speed, in the player's frame, and goes somewhere within
     * ±2.0 rad of where the ball was already headed.
     */
    @Test fun aRicochetKeepsItsShareOfTheSpeedAndStaysInItsCone() {
        val travel = Pitch.heading(0.0, 1.0)
        var seen = 0
        for (seed in 0L until 2000L) {
            if (seen >= 50) break
            val m = match(seed)
            if (fromBehind(m) != Outcome.RICOCHETED) continue
            seen++
            val off = Pitch.length(m.ball.vel.x, m.ball.vel.z)   // the player is at rest here
            assertEquals(15.0 * b.collectRicochetKeep, off, 1e-9)
            val turned = Pitch.heading(m.ball.vel.x, m.ball.vel.z)
            assertTrue(abs(Pitch.angleDiff(turned, travel)) <= b.collectRicochetSpread + 1e-9)
        }
        assertEquals(50, seen)
    }

    // Fair both ways

    /**
     * **It is the player's rule too.** `PLAYER` is the control scheme where team 0's carriers wait for
     * the finger (§5), and under it the rule is unchanged — the core never branches on who is
     * steering, because nobody steers a facing: §3 takes it from movement. The test that would catch
     * an exemption smuggled in later.
     */
    @Test fun theRuleIsTheSameUnderThePlayersControl() {
        for (seed in 0L until 300L) {
            val auto = match(seed, Control.AUTOMATIC)
            val finger = match(seed, Control.PLAYER)
            assertEquals(fromBehind(auto), fromBehind(finger))
        }
    }

    /**
     * **The rule is symmetric.** A team 1 player, who attacks the other way, is judged exactly as a
     * team 0 player is: same facing, same arrival, same outcome, draw for draw.
     */
    @Test fun theRuleIsTheSameForBothTeams() {
        for (seed in 0L until 300L) {
            val one = match(seed)
            val two = match(seed)
            assertEquals(fromBehind(one, outfield(one, 0)), fromBehind(two, outfield(two, 1)))
        }
    }
}
