package `in`.nann.smashhockey.game

import `in`.nann.smashhockey.core.feel.MatchCues
import `in`.nann.smashhockey.generated.Presentation

/** The presentation's numbers (presentation.toml) handed to the core's pure feel/ decisions (§8.8, §16.4). */
object Feel {
    val params: MatchCues.Params by lazy {
        val b = Presentation.Banner
        val h = Presentation.Haptics
        val s = Presentation.Sound
        MatchCues.Params(
            banner = MatchCues.Params.Seconds(b.versus, b.period, b.periodEnd, b.whistle, b.ready, b.lost, b.goal, b.end),
            shakeGoal = Presentation.Camera.Shake.goal,
            shakePost = Presentation.Camera.Shake.post,
            hapticWindow = h.window,
            releaseLow = h.releaseLow,
            releaseHigh = h.releaseHigh,
            releaseSlow = h.releaseSlow,
            releaseFast = h.releaseFast,
            hapticSharp = h.sharp,
            hapticGoal = h.goal,
            goalPulses = h.goalPulses,
            hapticAgainst = h.against,
            hapticTick = h.tick,
            shotSlow = s.shotSlow,
            shotFast = s.shotFast,
            countdown = s.countdown,
            stingDelay = s.stingDelay,
        )
    }
}
