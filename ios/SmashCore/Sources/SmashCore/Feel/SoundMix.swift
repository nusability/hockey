import Foundation

/// How a play of an event is mixed (spec §8.8, shared/data/sounds.toml) — the same arithmetic on both
/// platforms' playback layers. A sound made *somewhere on the pitch* (it carries an x) follows §8.6's
/// time scale and pans with where it happened; every other sound plays at real speed, centred.
public enum SoundMix {
    /// dB → linear amplitude.
    public static func amplitude(_ db: Double) -> Double { pow(10, db / 20) }

    /// A play's pitch factor for a uniform draw `u` in [0, 1): ± `semitones`, uniformly in semitones.
    public static func pitch(semitones: Double, u: Double) -> Double { pow(2, (2 * u - 1) * semitones / 12) }

    /// A play's rate: its pitch, times the time scale when it happened on the pitch, clamped to the
    /// playback layer's range.
    public static func rate(pitch: Double, timeScale: Double, onPitch: Bool, min lo: Double, max hi: Double) -> Double {
        Swift.min(Swift.max(onPitch ? pitch * timeScale : pitch, lo), hi)
    }

    /// Where a sound at `x` across the pitch (half-width 15) sits: −1 left … 1 right, `width` at the
    /// boards; centred when it has no place.
    public static func pan(x: Double?, width: Double) -> Double {
        guard let x else { return 0 }
        return Swift.min(Swift.max(x / Tuning.Pitch.halfWidth * width, -1), 1)
    }

    /// Left and right gains for `pan` under a constant-power law (pan 0: both 1/√2).
    public static func stereo(_ pan: Double) -> (left: Double, right: Double) {
        let a = (pan + 1) * Double.pi / 4
        return (cos(a), sin(a))
    }

    /// Which of `count` variants a play takes for a uniform draw `u` in [0, 1): at random, never the
    /// one played last (`last`) when there are two or more.
    public static func variant(count: Int, last: Int?, u: Double) -> Int {
        guard count > 1 else { return 0 }
        guard let last, last >= 0, last < count else { return Swift.min(Int(u * Double(count)), count - 1) }
        let pick = Swift.min(Int(u * Double(count - 1)), count - 2)
        return pick >= last ? pick + 1 : pick
    }
}

/// The voices a playback layer has (spec §8.8): which one a new play takes. An event already at its
/// `maxVoices` steals its own oldest; otherwise a free voice; otherwise the oldest voice of the lowest
/// priority below the event's; otherwise the play is dropped.
public struct VoicePool: Sendable {
    public struct Voice: Sendable, Hashable {
        public let cue: SoundCue
        public let priority: Int
        public let started: Double
        public let ends: Double
    }

    public private(set) var voices: [Voice?]

    public init(count: Int) { voices = Array(repeating: nil, count: count) }

    /// The voice a play of `cue` starting at `now` and lasting `seconds` takes, or nil to drop it.
    /// The voice is recorded as taken.
    public mutating func claim(_ cue: SoundCue, now: Double, seconds: Double) -> Int? {
        let spec = cue.spec
        func live(_ i: Int) -> Voice? { voices[i].flatMap { $0.ends > now ? $0 : nil } }
        let chosen: Int?
        let mine = voices.indices.filter { live($0)?.cue == cue }
        if mine.count >= spec.maxVoices {
            chosen = mine.min { voices[$0]!.started < voices[$1]!.started }
        } else if let free = voices.indices.first(where: { live($0) == nil }) {
            chosen = free
        } else {
            chosen = voices.indices
                .filter { voices[$0]!.priority < spec.priority }
                .min { a, b in
                    let va = voices[a]!, vb = voices[b]!
                    return va.priority != vb.priority ? va.priority < vb.priority : va.started < vb.started
                }
        }
        guard let i = chosen else { return nil }
        voices[i] = Voice(cue: cue, priority: spec.priority, started: now, ends: now + seconds)
        return i
    }
}
