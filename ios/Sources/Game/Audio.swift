import AVFoundation
import QuartzCore
import SmashCore
import os

/// The sound bank on AVAudioEngine (spec §8.8, shared/data/sounds.toml): every event's files — both
/// sports' — decoded once at launch into PCM buffers from the bundle's `sounds/<name>.m4a`; a
/// file the bank names but the bundle lacks fails the launch, loudly, and an event with no files is
/// silent by declaration. A fixed set of voices, each a player node through a varispeed (the rate:
/// the drawn pitch, times §8.6's time scale for a sound made on the pitch) into a small mixer (pan
/// and level) into the main mixer; which voice a play takes is the core's `VoicePool`, which variant
/// and pitch `SoundMix`. The crowd bed, when the bank has one, loops on a voice of its own under the
/// player's match. The session is `.ambient`: the silent switch silences it and other apps' audio
/// plays on. Low latency: buffers are resident and a play is scheduled at once. The twin of Android's
/// audio/Sfx.kt (SoundPool).
@MainActor
final class Audio {
    private final class Voice {
        let player = AVAudioPlayerNode()
        let speed = AVAudioUnitVarispeed()
        let mixer = AVAudioMixerNode()
        var pitch = 1.0
        var onPitch = false
    }

    typealias S = Presentation.Sound
    /// The world's sport, whose variants play (§1).
    var sport = Sport.field
    private let engine = AVAudioEngine()
    private let format = AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 2)!
    private var voices: [Voice] = []
    private let bed = Voice()
    private var pool = VoicePool(count: Presentation.Sound.voices)
    private var buffers: [String: AVAudioPCMBuffer] = [:]
    private var last: [SoundCue: Int] = [:]
    private var timeScale = 1.0
    private let log = Logger(subsystem: "in.nann.smashhockey", category: "audio")

    /// Loads the bank; throws naming the first file of the bank the bundle lacks or cannot decode.
    init(bundle: Bundle = .main) throws {
        for cue in SoundCue.allCases {
            for name in cue.spec.field + cue.spec.ice where buffers[name] == nil {
                guard let url = bundle.resourceURL?.appendingPathComponent("sounds/\(name).m4a"),
                      FileManager.default.fileExists(atPath: url.path) else {
                    throw AssetError.missing("sound \(name).m4a of \(cue.rawValue) (shared/data/sounds.toml) is not in the app's "
                                             + "sounds/ — shared/assets/sounds/ is bundled by ios/project.yml")
                }
                buffers[name] = try Self.decode(url, to: format)
            }
        }
        guard !buffers.isEmpty else { return }
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.ambient)
        try session.setActive(true)
        for _ in 0..<S.voices { voices.append(Voice()) }
        for v in voices + [bed] {
            engine.attach(v.player)
            engine.attach(v.speed)
            engine.attach(v.mixer)
            engine.connect(v.player, to: v.speed, format: format)
            engine.connect(v.speed, to: v.mixer, format: format)
            engine.connect(v.mixer, to: engine.mainMixerNode, format: nil)
        }
        engine.prepare()
        try engine.start()
    }

    private var running: Bool {
        if engine.isRunning { return true }
        do { try engine.start() } catch { log.error("audio engine: \(error, privacy: .public)"); return false }
        return true
    }

    /// Plays `cue` now: a variant (never the last one twice), at a pitch drawn in its spread; one
    /// made on the pitch at `x` across it pans there and follows the time scale.
    func play(_ cue: SoundCue, x: Double?) {
        let spec = cue.spec
        let names = spec.files(sport)
        guard !names.isEmpty, !voices.isEmpty, running else { return }
        let k = SoundMix.variant(count: names.count, last: last[cue], u: Double.random(in: 0..<1))
        last[cue] = k
        guard let buffer = buffers[names[k]] else { return }
        let pitch = SoundMix.pitch(semitones: spec.pitchSemitones, u: Double.random(in: 0..<1))
        let onPitch = x != nil
        let rate = SoundMix.rate(pitch: pitch, timeScale: timeScale, onPitch: onPitch, min: S.minRate, max: S.maxRate)
        let seconds = Double(buffer.frameLength) / format.sampleRate / rate
        guard let i = pool.claim(cue, now: CACurrentMediaTime(), seconds: seconds) else { return }
        let v = voices[i]
        v.player.stop()
        v.pitch = pitch
        v.onPitch = onPitch
        v.speed.rate = Float(rate)
        v.mixer.pan = Float(SoundMix.pan(x: x, width: S.pan))
        v.player.volume = Float(min(SoundMix.amplitude(spec.gainDb), 1))
        v.player.scheduleBuffer(buffer, at: nil, options: [], completionHandler: nil)
        v.player.play()
    }

    /// The crowd bed under a player's match (§8.8), looped while `on` — silent while the bank has none.
    func crowd(_ on: Bool) {
        bed.player.stop()
        let names = SoundCue.ambienceCrowd.spec.files(sport)
        guard on, let name = names.first, let buffer = buffers[name], running else { return }
        bed.player.volume = Float(min(SoundMix.amplitude(SoundCue.ambienceCrowd.spec.gainDb), 1))
        bed.player.scheduleBuffer(buffer, at: nil, options: [.loops], completionHandler: nil)
        bed.player.play()
    }

    /// One frame: the sounds made on the pitch follow §8.6's time scale, and hold while the match is
    /// paused (a scale of 0).
    func update(timeScale scale: Double) {
        guard scale != timeScale else { return }
        let was = timeScale
        timeScale = scale
        for v in voices where v.onPitch {
            if scale == 0 {
                if v.player.isPlaying { v.player.pause() }
            } else {
                v.speed.rate = Float(SoundMix.rate(pitch: v.pitch, timeScale: scale, onPitch: true, min: S.minRate, max: S.maxRate))
                if was == 0 { v.player.play() }
            }
        }
    }

    /// A file decoded into `format` (stereo, 44.1 kHz, float; a mono file in both channels).
    private static func decode(_ url: URL, to format: AVAudioFormat) throws -> AVAudioPCMBuffer {
        let file = try AVAudioFile(forReading: url)
        guard let raw = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: AVAudioFrameCount(file.length)) else {
            throw AssetError.missing("a buffer for \(url.lastPathComponent)")
        }
        try file.read(into: raw)
        if file.processingFormat == format { return raw }
        guard let converter = AVAudioConverter(from: file.processingFormat, to: format) else {
            throw AssetError.missing("a converter for \(url.lastPathComponent)")
        }
        let ratio = format.sampleRate / file.processingFormat.sampleRate
        let capacity = AVAudioFrameCount(Double(raw.frameLength) * ratio) + 1024
        guard let out = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: capacity) else {
            throw AssetError.missing("a buffer for \(url.lastPathComponent)")
        }
        var fed = false
        var failure: NSError?
        converter.convert(to: out, error: &failure) { _, status in
            if fed { status.pointee = .endOfStream; return nil }
            fed = true
            status.pointee = .haveData
            return raw
        }
        if let failure { throw failure }
        return out
    }
}
