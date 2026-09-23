package `in`.nann.smashhockey.core.feel

import `in`.nann.smashhockey.core.generated.Tuning
import `in`.nann.smashhockey.core.match.MatchEvent
import `in`.nann.smashhockey.core.match.MatchSnapshot
import `in`.nann.smashhockey.core.match.MatchState
import kotlin.math.exp
import kotlin.math.max
import kotlin.math.min
import kotlin.math.pow

/**
 * The stadium and the drums (spec §8.8, `shared/data/atmosphere.toml`) — what the looping layers
 * under a match should be doing right now, decided once for both apps. The twin of iOS's
 * `Feel/Atmosphere.swift`.
 *
 * It owns no audio and knows no file: it turns the match into five numbers between 0 and 1 — the
 * home crowd, the away crowd, the swell over both, the music, and how far the music is ducked —
 * plus where the swell sits across the stereo field and the rate the match layers play at. The
 * playback layers turn those into gains with each layer's own `quiet_db`/`loud_db`.
 *
 * Nothing here restarts a loop: a bed comes up and goes down, it never begins again.
 */
class Atmosphere(private val p: Params) {

    /** The declared mapping (atmosphere.toml `[mapping]`, `[surge]`, `[music_mapping]`, `[duck]`, `[time_scale]`). */
    data class Params(
        val shape: Double = 1.6,
        val base: Double = 0.0,
        val rise: Double = 1.0,
        val hush: Double = 0.0,
        val lateSeconds: Double = 30.0,
        val lateRise: Double = 0.0,
        val attackDanger: Double = 0.0,
        val defendDanger: Double = 0.0,
        val panSpan: Double = 0.0,
        val surgeDecay: Double = 1.0,
        val attackRate: Double = 3.0,
        val releaseRate: Double = 1.0,
        val surge: Surge = Surge(),
        val music: Music = Music(),
        /** `[duck]` — the times only; the depth is the playback layer's, in dB. */
        val duckAttack: Double = 0.05,
        val duckHold: Double = 0.5,
        val duckRelease: Double = 1.0,
        val minRate: Double = 0.42,
    ) {
        data class Surge(
            val kickoff: Double = 0.0,
            val goalFor: Double = 0.0,
            val goalAgainst: Double = 0.0,
            val save: Double = 0.0,
            val post: Double = 0.0,
            val steal: Double = 0.0,
            val whistle: Double = 0.0,
            val periodEnd: Double = 0.0,
            val ended: Double = 0.0,
        )

        data class Music(
            val base: Double = 0.0,
            val rise: Double = 0.0,
            val lateRise: Double = 0.0,
            val attackRate: Double = 1.0,
            val releaseRate: Double = 1.0,
        )
    }

    /**
     * What the layers should be doing this frame. Every level is 0…1 — the playback layer reads each
     * layer's `quiet_db`…`loud_db` across it.
     */
    data class Levels(
        /** The crowd behind the player's own goal, the crowd behind the other, and the swell over both. */
        var home: Double = 0.0,
        var away: Double = 0.0,
        var swell: Double = 0.0,
        /** Where the swell sits: −1 left … 1 right, leaning toward the end being attacked. */
        var swellPan: Double = 0.0,
        var music: Double = 0.0,
        /** How far the music is ducked, 0 (not at all) … 1 (the declared depth). */
        var duck: Double = 0.0,
        /** The rate the match layers play at, following §8.6's time scale; 0 while the match is paused. */
        var rate: Double = 1.0,
    )

    /** Which goal a shot about to score (§8.6) is heading for. */
    enum class Danger { OURS, THEIRS }

    private var homeSurge = 0.0
    private var awaySurge = 0.0
    private var duckFor = 0.0

    /** The levels as they stand, without advancing anything. */
    val now = Levels()

    /**
     * What an event pushes into the crowd. A goal is the big one: the side that scored goes to the
     * top, the side that conceded below its own floor.
     */
    fun hear(e: MatchEvent, s: MatchSnapshot) {
        val g = p.surge
        when (e) {
            is MatchEvent.Goal -> push(if (e.team == 0) g.goalFor else g.goalAgainst, if (e.team == 0) g.goalAgainst else g.goalFor)
            is MatchEvent.Save -> side(s.players[e.by].team, g.save)
            is MatchEvent.Steal -> side(s.players[e.by].team, g.steal)
            MatchEvent.Post -> push(g.post, g.post)
            MatchEvent.Play -> push(g.kickoff, g.kickoff)
            MatchEvent.Whistle, is MatchEvent.DrillInterrupted -> push(g.whistle, g.whistle)
            is MatchEvent.PeriodEnd -> push(g.periodEnd, g.periodEnd)
            is MatchEvent.End -> push(g.ended, g.ended)
            else -> Unit
        }
    }

    /** A one-shot that the music steps back under (atmosphere.toml `[duck].cues`), lasting [seconds]. */
    fun duck(seconds: Double) {
        duckFor = max(duckFor, max(seconds, 0.0) + p.duckHold)
    }

    /**
     * One frame of real time [dt]. [s] is the match as it stands (null outside a match: everything
     * falls away); [danger] is §8.6's shot about to score and which goal it is heading for;
     * [timeScale] is §8.6's, which the match layers follow.
     */
    fun update(dt: Double, s: MatchSnapshot?, danger: Danger?, timeScale: Double): Levels {
        val step = max(dt, 0.0)
        homeSurge *= exp(-p.surgeDecay * step)
        awaySurge *= exp(-p.surgeDecay * step)

        var attack = 0.0
        var defend = 0.0
        var late = 0.0
        if (s != null) {
            val threat = clamp(s.ball.z / Tuning.Pitch.goalLineZ, -1.0, 1.0)
            attack = max(0.0, threat).pow(p.shape)
            defend = max(0.0, -threat).pow(p.shape)
            late = when {
                s.overtime -> 1.0
                s.state == MatchState.PLAY && p.lateSeconds > 0 -> clamp((p.lateSeconds - s.clock) / p.lateSeconds, 0.0, 1.0)
                else -> 0.0
            }
        }
        var homeDanger = 0.0
        var awayDanger = 0.0
        when (danger) {
            Danger.THEIRS -> { homeDanger = p.attackDanger; awayDanger = p.defendDanger }
            Danger.OURS -> { homeDanger = p.defendDanger; awayDanger = p.attackDanger }
            null -> Unit
        }
        val live = s != null
        val homeTarget = if (live) clamp(p.base + attack * p.rise - defend * p.hush + late * p.lateRise + homeDanger + homeSurge, 0.0, 1.0) else 0.0
        val awayTarget = if (live) clamp(p.base + defend * p.rise - attack * p.hush + late * p.lateRise + awayDanger + awaySurge, 0.0, 1.0) else 0.0
        now.home = ease(now.home, homeTarget, step)
        now.away = ease(now.away, awayTarget, step)
        now.swell = ease(now.swell, max(homeTarget, awayTarget), step)
        now.swellPan = clamp(p.panSpan * (defend - attack), -1.0, 1.0)

        val m = p.music
        val musicTarget = if (live) clamp(m.base + max(attack, defend) * m.rise + late * m.lateRise, 0.0, 1.0) else 0.0
        val mRate = if (musicTarget > now.music) m.attackRate else m.releaseRate
        now.music += (musicTarget - now.music) * (1 - exp(-mRate * step))

        duckFor = max(duckFor - step, 0.0)
        val duckTarget = if (duckFor > 0) 1.0 else 0.0
        val dRate = if (duckTarget > now.duck) 1 / max(p.duckAttack, 1e-3) else 1 / max(p.duckRelease, 1e-3)
        now.duck += (duckTarget - now.duck) * (1 - exp(-dRate * step))

        now.rate = if (timeScale <= 0) 0.0 else max(min(timeScale, 1.0), p.minRate)
        return now
    }

    private fun side(team: Int, amount: Double) = push(if (team == 0) amount else 0.0, if (team == 0) 0.0 else amount)

    private fun push(home: Double, away: Double) {
        homeSurge += home
        awaySurge += away
    }

    /**
     * A level eases toward its target — faster coming up than going down: a crowd rises quicker than
     * it settles.
     */
    private fun ease(v: Double, target: Double, dt: Double): Double {
        val rate = if (target > v) p.attackRate else p.releaseRate
        return v + (target - v) * (1 - exp(-rate * dt))
    }

    private fun clamp(v: Double, lo: Double, hi: Double) = min(max(v, lo), hi)
}
