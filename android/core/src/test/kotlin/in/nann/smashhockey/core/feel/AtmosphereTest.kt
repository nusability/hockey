package `in`.nann.smashhockey.core.feel

import `in`.nann.smashhockey.core.generated.Role
import `in`.nann.smashhockey.core.generated.Tuning
import `in`.nann.smashhockey.core.match.MatchEvent
import `in`.nann.smashhockey.core.match.MatchSnapshot
import `in`.nann.smashhockey.core.match.MatchState
import kotlin.math.abs
import kotlin.math.max
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * The stadium and the drums (spec §8.8, shared/data/atmosphere.toml): the crowd follows the ball
 * toward one goal or the other, the events push it, the music lifts late, and everything falls away
 * when the match does. iOS's `AtmosphereTests` checks the same list.
 */
class AtmosphereTest {
    private val params = Atmosphere.Params(
        shape = 1.6, base = 0.06, rise = 0.95, hush = 0.3,
        lateSeconds = 30.0, lateRise = 0.35,
        attackDanger = 0.45, defendDanger = 0.55, panSpan = 0.5,
        surgeDecay = 0.55, attackRate = 3.2, releaseRate = 0.7,
        surge = Atmosphere.Params.Surge(
            kickoff = 0.45, goalFor = 1.0, goalAgainst = -0.75, save = 0.4,
            post = 0.35, steal = 0.12, whistle = -0.15, periodEnd = -0.35, ended = -0.6,
        ),
        music = Atmosphere.Params.Music(base = 0.0, rise = 0.8, lateRise = 1.0, attackRate = 1.2, releaseRate = 0.45),
        duckAttack = 0.04, duckHold = 0.5, duckRelease = 1.1,
        minRate = 0.42,
    )

    private fun snapshot(
        z: Double,
        clock: Double = 60.0,
        overtime: Boolean = false,
    ): MatchSnapshot {
        val players = (0 until 12).map { i ->
            MatchSnapshot.Player(if (i < 6) 0 else 1, if (i % 6 == 0) Role.GOALIE else Role.FORWARD, 1.0, 0.0, 0.0, 0.0, 0.0, 0.0)
        }
        val ball = MatchSnapshot.Ball(0.0, z, 0.0, 0.0, 0.36, null, 0.0, 1.0)
        return MatchSnapshot(
            MatchState.PLAY, players, ball, null, false, players.map { false },
            clock, listOf(0, 0), 1, overtime, 0.0, null,
        )
    }

    /** Runs [seconds] of frames at 1/60 and returns where the levels end up. */
    private fun settle(
        a: Atmosphere,
        s: MatchSnapshot?,
        seconds: Double,
        danger: Atmosphere.Danger? = null,
        timeScale: Double = 1.0,
    ): Atmosphere.Levels {
        repeat((seconds * 60).toInt()) { a.update(1.0 / 60, s, danger, timeScale) }
        return a.now.copy()
    }

    @Test
    fun `open play is quiet and even`() {
        val l = settle(Atmosphere(params), snapshot(0.0), 12.0)
        assertTrue(abs(l.home - l.away) < 0.01)
        assertTrue(l.home < 0.1)
        assertTrue(l.swell < 0.1)
        assertTrue(abs(l.swellPan) < 0.01)
    }

    @Test
    fun `our attack lifts our end and hushes theirs`() {
        val l = settle(Atmosphere(params), snapshot(Tuning.Pitch.goalLineZ), 12.0)
        assertTrue(l.home > 0.9)
        assertTrue(l.away < 0.05)
        assertTrue(l.swell > 0.9)
        // The swell leans toward the end being attacked: theirs, which is the away bed's side.
        assertTrue(l.swellPan < -0.4)
    }

    @Test
    fun `their attack is the mirror of ours`() {
        val a = settle(Atmosphere(params), snapshot(Tuning.Pitch.goalLineZ), 12.0)
        val b = settle(Atmosphere(params), snapshot(-Tuning.Pitch.goalLineZ), 12.0)
        assertEquals(a.home, b.away, 1e-9)
        assertEquals(a.away, b.home, 1e-9)
        assertEquals(a.swellPan, -b.swellPan, 1e-9)
    }

    @Test
    fun `a dangerous shot grips both ends`() {
        val calm = settle(Atmosphere(params), snapshot(10.0), 8.0)
        val gripped = settle(Atmosphere(params), snapshot(10.0), 8.0, Atmosphere.Danger.THEIRS)
        assertTrue(gripped.home > calm.home)
        assertTrue(gripped.away > calm.away)
    }

    @Test
    fun `a goal of ours lifts us and sinks them`() {
        val a = Atmosphere(params)
        val s = snapshot(0.0)
        val before = settle(a, s, 6.0)
        a.hear(MatchEvent.Goal(0, 1, null, false), s)
        val after = settle(a, s, 0.5)
        assertTrue(after.home > before.home)
        assertTrue(after.away < before.away)
    }

    @Test
    fun `a goal against is the mirror`() {
        val a = Atmosphere(params)
        val s = snapshot(0.0)
        settle(a, s, 6.0)
        a.hear(MatchEvent.Goal(1, 7, null, false), s)
        val after = settle(a, s, 0.5)
        assertTrue(after.away > after.home)
    }

    @Test
    fun `a save lifts only the keeper's own end`() {
        val a = Atmosphere(params)
        val s = snapshot(0.0)
        val before = settle(a, s, 6.0)
        a.hear(MatchEvent.Save(0), s)               // player 0 is the player's own goalie
        val after = settle(a, s, 0.3)
        assertTrue(after.home > before.home)
        assertTrue(after.away <= before.away + 1e-9)
    }

    @Test
    fun `the crowd comes up faster than it settles`() {
        val loud = snapshot(Tuning.Pitch.goalLineZ)
        val rising = settle(Atmosphere(params), loud, 0.5).home
        val b = Atmosphere(params)
        val top = settle(b, loud, 12.0).home
        val falling = settle(b, snapshot(0.0), 0.5).home
        assertTrue(rising / max(top, 1e-9) > (top - falling) / max(top, 1e-9))
    }

    @Test
    fun `the music lifts in the last seconds`() {
        val early = settle(Atmosphere(params), snapshot(0.0, clock = 90.0), 10.0)
        val late = settle(Atmosphere(params), snapshot(0.0, clock = 2.0), 10.0)
        assertTrue(late.music > early.music + 0.2)
    }

    @Test
    fun `overtime is all the way late`() {
        val l = settle(Atmosphere(params), snapshot(0.0, clock = 0.0, overtime = true), 10.0)
        assertTrue(l.music > 0.9)
    }

    @Test
    fun `a ducking cue pushes the music back and it comes back`() {
        val a = Atmosphere(params)
        val s = snapshot(0.0)
        settle(a, s, 2.0)
        a.duck(0.2)
        assertTrue(settle(a, s, 0.3).duck > 0.9)
        assertTrue(settle(a, s, 6.0).duck < 0.05)
    }

    @Test
    fun `the layers follow the time scale and hold when paused`() {
        val a = Atmosphere(params)
        val s = snapshot(0.0)
        assertEquals(0.45, a.update(1.0 / 60, s, null, 0.45).rate, 0.0)
        assertEquals(params.minRate, a.update(1.0 / 60, s, null, 0.18).rate, 0.0)
        assertEquals(0.0, a.update(1.0 / 60, s, null, 0.0).rate, 0.0)
        assertEquals(1.0, a.update(1.0 / 60, s, null, 1.0).rate, 0.0)
    }

    @Test
    fun `leaving the match takes everything with it`() {
        val a = Atmosphere(params)
        settle(a, snapshot(Tuning.Pitch.goalLineZ), 12.0)
        val gone = settle(a, null, 20.0)
        assertTrue(gone.home < 0.01)
        assertTrue(gone.away < 0.01)
        assertTrue(gone.swell < 0.01)
        assertTrue(gone.music < 0.01)
    }
}
