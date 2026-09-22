package `in`.nann.smashhockey.core.feel

import `in`.nann.smashhockey.core.generated.CopyKey
import `in`.nann.smashhockey.core.generated.Role
import `in`.nann.smashhockey.core.generated.SoundCue
import `in`.nann.smashhockey.core.generated.Tuning
import `in`.nann.smashhockey.core.match.DrillInterruption
import `in`.nann.smashhockey.core.match.MatchEvent
import `in`.nann.smashhockey.core.match.MatchResult
import `in`.nann.smashhockey.core.match.MatchSnapshot
import `in`.nann.smashhockey.core.match.MatchState
import `in`.nann.smashhockey.core.match.Pitch
import kotlin.math.ceil

/** A banner the match raises (spec §16.4): its copy and arguments, its style and how long it stands. */
data class Banner(val key: CopyKey, val args: List<String> = emptyList(), val style: Style, val seconds: Double) {
    enum class Style {
        /** A goal of ours, a win: popped big in the sun colour. */
        GOOD,
        /** A goal against, a loss, a drill interrupted. */
        BAD,
        /** A dead-ball reset in a match. */
        WARN,
        /** The intro, periods, a drill's get ready. */
        INFO,
    }
}

/** A haptic the match plays (spec §8.8); intensities 0–1. */
sealed interface Haptic {
    /** Light: the aim entering a window, a countdown second. */
    data class Tick(val intensity: Double) : Haptic
    /** A body blow: a release, the goal horn. */
    data class Impact(val intensity: Double) : Haptic
    /** A sharp transient: a steal, a save, a post. */
    data class Sharp(val intensity: Double) : Haptic
}

/** Where a save, a steal or a block pops (§8.8). */
enum class PopKind { SAVE, STEAL, BLOCK }

/** One reaction to what the match did (spec §8.8, §16.4). `delay` is real seconds from now. */
sealed interface Cue {
    data class Show(val banner: Banner) : Cue
    /** A sound; one made on the pitch carries the ball's [x]: it pans there and follows §8.6's time scale. */
    data class Sound(val cue: SoundCue, val x: Double? = null, val delay: Double = 0.0) : Cue
    data class Feel(val haptic: Haptic, val delay: Double = 0.0) : Cue
    /** A camera shake of this many metres (the prototype's kick, §8.8). */
    data class Shake(val metres: Double) : Cue
    data class Pop(val kind: PopKind, val x: Double, val z: Double) : Cue

    /** A cue the demo keeps: what is seen, not heard or felt. */
    val isSeen: Boolean get() = this is Shake || this is Pop
}

/**
 * What the match's events and frames set off — the banners, sounds, haptics, shakes and pops (spec
 * §8.8, §16.4), decided once for both apps (the twin of iOS's MatchCues). It keeps the little memory
 * the prototype's messages needed (a face-off after a period's end names the period; a drill's
 * get-ready says why), and the countdown's and the aim's last state. The player's matches get
 * everything; the demo behind the menus (§9) only what is seen.
 *
 * [drill]: a drill is on the pitch (§10). [audible]: the player's own match, not the demo.
 */
class MatchCues(private val p: Params, private val drill: Boolean, private val audible: Boolean) {
    data class Params(
        val banner: Seconds,
        val shakeGoal: Double,
        val shakePost: Double,
        val hapticWindow: Double,
        val releaseLow: Double,
        val releaseHigh: Double,
        val releaseSlow: Double,
        val releaseFast: Double,
        val hapticSharp: Double,
        val hapticGoal: Double,
        val goalPulses: List<Double>,
        val hapticAgainst: Double,
        val hapticTick: Double,
        val shotSlow: Double,
        val shotFast: Double,
        val countdown: Int,
        val stingDelay: Double,
    ) {
        /** The banners' durations (presentation.toml [banner]). */
        data class Seconds(
            val versus: Double, val period: Double, val periodEnd: Double, val whistle: Double,
            val ready: Double, val lost: Double, val goal: Double, val end: Double,
        )
    }

    private var lastFlow: MatchEvent? = null
    private var lastTick: Int? = null
    private var aimWindow: MatchSnapshot.Aim? = null

    /** The intro banner of a player's match (not a drill): "Home vs Away". */
    fun intro(home: String, away: String): List<Cue> =
        if (!audible || drill) emptyList()
        else listOf(Cue.Show(Banner(CopyKey.EVENT_VERSUS, listOf(home, away), Banner.Style.INFO, p.banner.versus)))

    /** What event [e] sets off; [s] is the match as it stands after the tick that emitted it. */
    fun hear(e: MatchEvent, s: MatchSnapshot): List<Cue> {
        val out = ArrayList<Cue>()
        val b = p.banner
        fun banner(key: CopyKey, args: List<String>, style: Banner.Style, seconds: Double) { out += Cue.Show(Banner(key, args, style, seconds)) }
        /** A sound; one made on the pitch (the ball's) is at the ball's x — it pans and follows §8.6. */
        fun sound(cue: SoundCue, onPitch: Boolean = false, delay: Double = 0.0) { out += Cue.Sound(cue, if (onPitch) s.ball.x else null, delay) }
        fun haptic(h: Haptic, delay: Double = 0.0) { out += Cue.Feel(h, delay) }
        fun mine(i: Int) = s.players[i].team == 0 && s.players[i].role != Role.GOALIE
        val none = emptyList<String>()

        when (e) {
            is MatchEvent.Goal -> {
                out += Cue.Shake(p.shakeGoal)
                sound(SoundCue.MATCH_WHISTLE_SHORT)
                sound(SoundCue.UI_CONFETTI_POP)
                if (e.team == 0) {
                    banner(CopyKey.EVENT_GOAL, none, Banner.Style.GOOD, b.goal)
                    sound(SoundCue.MATCH_GOAL_HORN)
                    sound(SoundCue.MATCH_GOAL_CHEER)
                    for (t in p.goalPulses) haptic(Haptic.Impact(p.hapticGoal), t)
                } else {
                    banner(CopyKey.EVENT_GOAL_AGAINST, none, Banner.Style.BAD, b.goal)
                    sound(SoundCue.MATCH_GOAL_AGAINST)
                    haptic(Haptic.Impact(p.hapticAgainst))
                }
            }
            MatchEvent.Post -> {
                out += Cue.Shake(p.shakePost)
                sound(SoundCue.MATCH_POST, onPitch = true)
                haptic(Haptic.Sharp(p.hapticSharp))
            }
            is MatchEvent.Board -> sound(SoundCue.MATCH_BOARD, onPitch = true)
            is MatchEvent.Block -> {
                sound(SoundCue.MATCH_BLOCK, onPitch = true)
                out += Cue.Pop(PopKind.BLOCK, s.players[e.by].x, s.players[e.by].z)
            }
            is MatchEvent.Save -> {
                sound(SoundCue.MATCH_SAVE, onPitch = true)
                haptic(Haptic.Sharp(p.hapticSharp))
                out += Cue.Pop(PopKind.SAVE, s.players[e.by].x, s.players[e.by].z)
            }
            is MatchEvent.Steal -> {
                sound(SoundCue.MATCH_STEAL, onPitch = true)
                haptic(Haptic.Sharp(p.hapticSharp))
                out += Cue.Pop(PopKind.STEAL, s.players[e.by].x, s.players[e.by].z)
            }
            is MatchEvent.Pickup -> if (s.players[e.player].team == 0) sound(SoundCue.MATCH_RECEIVE, onPitch = true)
            is MatchEvent.Shot -> {
                val speed = Pitch.length(s.ball.vx, s.ball.vz)
                sound(shot(speed), onPitch = true)
                if (mine(e.by)) haptic(Haptic.Impact(release(speed)))
            }
            is MatchEvent.Pass -> {
                sound(SoundCue.MATCH_PASS, onPitch = true)
                if (mine(e.from)) haptic(Haptic.Impact(release(Pitch.length(s.ball.vx, s.ball.vz))))
            }
            MatchEvent.Play -> sound(SoundCue.MATCH_FACEOFF_DROP, onPitch = true)
            MatchEvent.Whistle -> {
                banner(CopyKey.EVENT_RESET, none, Banner.Style.WARN, b.whistle)
                sound(SoundCue.MATCH_WHISTLE_SHORT)
            }
            is MatchEvent.DrillInterrupted -> {
                val key = when (e.reason) {
                    DrillInterruption.SAVED -> CopyKey.EVENT_SAVED
                    DrillInterruption.STOLEN -> CopyKey.EVENT_STOLEN
                    DrillInterruption.WRONG_NET -> CopyKey.EVENT_WRONG_NET
                    DrillInterruption.NO_ASSIST -> CopyKey.EVENT_PASS_FIRST
                    DrillInterruption.DEAD_BALL -> CopyKey.EVENT_RESET
                }
                banner(key, none, Banner.Style.BAD, b.lost)
                sound(SoundCue.MATCH_WHISTLE_SHORT)
            }
            MatchEvent.Ready -> {
                val key = when (lastFlow) {
                    is MatchEvent.Goal -> CopyKey.EVENT_NICE_AGAIN
                    is MatchEvent.DrillInterrupted -> CopyKey.EVENT_AGAIN
                    else -> CopyKey.EVENT_GET_READY
                }
                banner(key, none, Banner.Style.INFO, b.ready)
            }
            is MatchEvent.PeriodEnd -> {
                // The third period's end either leads to overtime or is the end itself (its banner).
                if (s.state == MatchState.PERIOD_END) {
                    if (e.period < Tuning.Match.periods) banner(CopyKey.EVENT_PERIOD_END, listOf("${e.period}"), Banner.Style.INFO, b.periodEnd)
                    else banner(CopyKey.EVENT_OVERTIME, none, Banner.Style.INFO, b.periodEnd)
                    sound(SoundCue.MATCH_WHISTLE_END)
                }
            }
            is MatchEvent.FaceOff -> if (lastFlow is MatchEvent.PeriodEnd) {
                if (s.overtime) banner(CopyKey.EVENT_SUDDEN_DEATH, none, Banner.Style.INFO, b.period)
                else banner(CopyKey.EVENT_PERIOD, listOf("${s.period}"), Banner.Style.INFO, b.period)
            }
            is MatchEvent.End -> {
                val key = if (drill) (if (e.result == MatchResult.WON) CopyKey.RESULT_DRILL_WON else CopyKey.RESULT_TIME_UP) else CopyKey.EVENT_FINAL
                banner(key, none, if (e.result == MatchResult.LOST) Banner.Style.BAD else Banner.Style.GOOD, b.end)
                sound(SoundCue.MATCH_WHISTLE_END)
                sound(if (e.result == MatchResult.LOST) SoundCue.MATCH_RESULT_LOSE else SoundCue.MATCH_RESULT_WIN, delay = p.stingDelay)
            }
        }
        when (e) {
            is MatchEvent.Goal, is MatchEvent.DrillInterrupted, is MatchEvent.PeriodEnd, is MatchEvent.FaceOff,
            MatchEvent.Whistle, MatchEvent.Ready, is MatchEvent.End -> lastFlow = e
            else -> Unit
        }
        return if (audible) out else out.filter { it.isSeen }
    }

    /**
     * Once per tick, after its events: the countdown of a period's (or a drill's) last seconds, and
     * the aim of the player's carrier entering a pass or shot window.
     */
    fun frame(s: MatchSnapshot): List<Cue> {
        if (!audible) return emptyList()
        val out = ArrayList<Cue>()
        if (s.state == MatchState.PLAY && !s.overtime) {
            val secs = ceil(s.clock).toInt()
            if (secs > p.countdown) {
                lastTick = null
            } else if (secs >= 1 && secs != lastTick) {
                lastTick = secs
                out += Cue.Sound(SoundCue.MATCH_COUNTDOWN_TICK)
                out += Cue.Feel(Haptic.Tick(p.hapticTick))
            }
        }
        val window = if (s.playerCarrier && s.state == MatchState.PLAY) s.aim?.takeIf { it != MatchSnapshot.Aim.Unassisted } else null
        if (window != null && window != aimWindow) out += Cue.Feel(Haptic.Tick(p.hapticWindow))
        aimWindow = window
        return out
    }

    /** A shot's sound by its speed: the slowest third of shotSlow…shotFast soft, the middle medium, the fastest hard. */
    internal fun shot(speed: Double): SoundCue {
        val third = (p.shotFast - p.shotSlow) / 3
        return when {
            speed < p.shotSlow + third -> SoundCue.MATCH_SHOT_SOFT
            speed < p.shotSlow + 2 * third -> SoundCue.MATCH_SHOT_MEDIUM
            else -> SoundCue.MATCH_SHOT_HARD
        }
    }

    /** A release's impact: from releaseLow at releaseSlow m/s to releaseHigh at releaseFast. */
    internal fun release(speed: Double) = ramp(speed, p.releaseSlow, p.releaseFast, p.releaseLow, p.releaseHigh)

    internal fun ramp(v: Double, v0: Double, v1: Double, out0: Double, out1: Double): Double {
        if (v1 <= v0) return out1
        val t = ((v - v0) / (v1 - v0)).coerceIn(0.0, 1.0)
        return out0 + (out1 - out0) * t
    }
}
