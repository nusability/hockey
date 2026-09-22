import SmashCore
import UIKit

/// What the match sets off beyond the picture (spec §8.8): the sounds (`Audio`) and the haptics, on
/// the game's one clock — a cue with a delay waits for it in real seconds. The core's `MatchCues`
/// decides what; this plays it. Android's twins: game/Feel.kt, audio/Sfx.kt, audio/Haptics.kt.
@MainActor
final class Feedback {
    let audio: Audio
    private let haptics = Haptics()
    private var later: [(due: Double, cue: Cue)] = []
    private var clock = 0.0

    init(audio: Audio) { self.audio = audio }

    /// MatchCues' tunables, from presentation.toml.
    static var params: MatchCues.Params {
        typealias B = Presentation.Banner
        typealias H = Presentation.Haptics
        typealias S = Presentation.Sound
        var p = MatchCues.Params()
        p.banner.versus = B.versus; p.banner.period = B.period; p.banner.periodEnd = B.periodEnd
        p.banner.whistle = B.whistle; p.banner.ready = B.ready; p.banner.lost = B.lost
        p.banner.goal = B.goal; p.banner.end = B.end
        p.shakeGoal = Presentation.Camera.Shake.goal
        p.shakePost = Presentation.Camera.Shake.post
        p.hapticWindow = H.window; p.releaseLow = H.releaseLow; p.releaseHigh = H.releaseHigh
        p.releaseSlow = H.releaseSlow; p.releaseFast = H.releaseFast; p.hapticSharp = H.sharp
        p.hapticGoal = H.goal; p.goalPulses = H.goalPulses; p.hapticAgainst = H.against; p.hapticTick = H.tick
        p.shotSlow = S.shotSlow; p.shotFast = S.shotFast
        p.countdown = S.countdown; p.stingDelay = S.stingDelay
        return p
    }

    /// Plays a sound or haptic cue now, or once its delay has passed.
    func perform(_ c: Cue) {
        switch c {
        case .sound(_, _, let delay) where delay > 0, .haptic(_, let delay) where delay > 0:
            later.append((clock + delay, c))
        case .sound(let cue, let x, _):
            audio.play(cue, x: x)
        case .haptic(let h, _):
            haptics.play(h)
        case .banner, .shake, .pop:
            break
        }
    }

    /// A sound of the 3D UI kit (§8.8): a press, a flip, a pop, a whoosh, a nope, a slider's step.
    func ui(_ cue: SoundCue) { audio.play(cue, x: nil) }

    /// One frame of real time; `timeScale` is §8.6's, which the sounds made on the pitch follow.
    func update(_ dt: Double, timeScale: Double) {
        clock += dt
        let due = later.filter { $0.due <= clock }
        later.removeAll { $0.due <= clock }
        for d in due {
            switch d.cue {
            case .sound(let cue, let x, _): audio.play(cue, x: x)
            case .haptic(let h, _): haptics.play(h)
            default: break
            }
        }
        audio.update(timeScale: timeScale)
    }

    /// Leaving a match drops what it still had coming but the result sting — the result's own.
    func cancelMatchCues() {
        later.removeAll {
            if case .sound(let cue, _, _) = $0.cue { cue != .matchResultWin && cue != .matchResultLose } else { true }
        }
    }
}

/// The haptics (§8.8) on UIKit's feedback generators — which follow the system's haptics setting:
/// a light tick, a heavy impact and a rigid, sharp transient, each at its intensity.
@MainActor
final class Haptics {
    private let light = UIImpactFeedbackGenerator(style: .light)
    private let heavy = UIImpactFeedbackGenerator(style: .heavy)
    private let rigid = UIImpactFeedbackGenerator(style: .rigid)

    init() {
        for g in [light, heavy, rigid] { g.prepare() }
    }

    func play(_ h: Haptic) {
        switch h {
        case .tick(let i): light.impactOccurred(intensity: CGFloat(i)); light.prepare()
        case .impact(let i): heavy.impactOccurred(intensity: CGFloat(i)); heavy.prepare()
        case .sharp(let i): rigid.impactOccurred(intensity: CGFloat(i)); rigid.prepare()
        }
    }
}
