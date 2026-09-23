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
    /// The stadium and the drums (§8.8): the core decides the levels, `Audio` plays them.
    private var atmosphere = SmashCore.Atmosphere(AtmosphereData.params)
    /// The player's two volumes (§12); until the coach's board offers them, their declared defaults.
    var crowdVolume = AtmosphereData.crowdDefault
    var musicVolume = AtmosphereData.musicDefault

    init(audio: Audio) { self.audio = audio }

    /// The stadium under a player's match: its beds and its drums start, or fall silent.
    func stadium(_ on: Bool) { audio.stadium(on) }

    /// The menus' drums, whenever no match of the player's is on.
    func menuMusic(_ on: Bool) { audio.menuMusic(on) }

    /// What an event does to the crowd (§8.8) — a goal, a save, a stoppage.
    func hear(_ e: MatchEvent, _ s: MatchSnapshot) { atmosphere.hear(e, s) }

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
            play(cue, x: x)
        case .haptic(let h, _):
            haptics.play(h)
        case .banner, .shake, .pop:
            break
        }
    }

    /// A one-shot, and the duck it puts on the music when it is one of the declared cues.
    private func play(_ cue: SoundCue, x: Double?) {
        audio.play(cue, x: x)
        if AtmosphereData.duckCues.contains(cue) { atmosphere.duck(seconds: 0) }
    }

    /// A sound of the 3D UI kit (§8.8): a press, a flip, a pop, a whoosh, a nope, a slider's step.
    func ui(_ cue: SoundCue) { audio.play(cue, x: nil) }

    /// One frame of real time; `timeScale` is §8.6's, which the sounds made on the pitch follow, and
    /// `match` is what the stadium reads (nil outside a match of the player's: it falls away).
    func update(_ dt: Double, timeScale: Double,
                match: (snapshot: MatchSnapshot, danger: SmashCore.Atmosphere.Danger?)? = nil) {
        clock += dt
        let due = later.filter { $0.due <= clock }
        later.removeAll { $0.due <= clock }
        for d in due {
            switch d.cue {
            case .sound(let cue, let x, _): play(cue, x: x)
            case .haptic(let h, _): haptics.play(h)
            default: break
            }
        }
        audio.update(timeScale: timeScale)
        let levels = atmosphere.update(dt, match?.snapshot, danger: match?.danger, timeScale: timeScale)
        audio.apply(levels, crowd: crowdVolume, music: musicVolume)
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
