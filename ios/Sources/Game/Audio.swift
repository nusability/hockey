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
/// and pitch `SoundMix`. The looping layers — the two crowd beds, the swell over them and the drum
/// music (`shared/data/atmosphere.toml`) — get nodes of their own that start once and never restart:
/// only their gain, pan and rate move, from the core's `Atmosphere`. The session is `.ambient`: the silent switch silences it and other apps' audio
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
        /// A looping layer that has been started: only those take a gain from `apply`.
        var looping = false
    }

    typealias S = Presentation.Sound
    /// The world's sport, whose variants play (§1).
    var sport = Sport.field
    private let engine = AVAudioEngine()
    private let format = AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 2)!
    private var voices: [Voice] = []
    /// The looping layers: the three crowd beds in `AtmosphereData.beds`' order, then the match
    /// music and the menu music. Each is a voice whose buffer loops for as long as the app lives.
    private let beds = AtmosphereData.beds.map { _ in Voice() }
    private let matchTrack = Voice()
    private let menuTrack = Voice()
    private var looping: [Voice] { beds + [matchTrack, menuTrack] }
    private var bedsOn = false
    private var menuOn = false
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
        for name in AtmosphereData.beds.map(\.file) + [AtmosphereData.matchMusic.file, AtmosphereData.menuMusic.file]
        where buffers[name] == nil {
            guard let url = bundle.resourceURL?.appendingPathComponent("sounds/\(name).m4a"),
                  FileManager.default.fileExists(atPath: url.path) else {
                throw AssetError.missing("looping layer \(name).m4a (shared/data/atmosphere.toml) is not in the app's "
                                         + "sounds/ — shared/assets/sounds/ is bundled by ios/project.yml")
            }
            buffers[name] = try Self.decode(url, to: format)
        }
        guard !buffers.isEmpty else { return }
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.ambient)
        try session.setActive(true)
        for _ in 0..<S.voices { voices.append(Voice()) }
        for v in voices + looping {
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

    /// The stadium under a player's match (§8.8): the two crowd beds and the swell, looping while
    /// `on`, and the match's drums with them. Starting is the only thing that ever happens to a loop
    /// — from here on `apply` only moves its gain.
    func stadium(_ on: Bool) {
        guard bedsOn != on else { return }
        bedsOn = on
        for (v, bed) in zip(beds, AtmosphereData.beds) { loop(v, bed.file, on) }
        loop(matchTrack, AtmosphereData.matchMusic.file, on)
    }

    /// The menus' drums (§8.8), looping while `on` — never at the same time as the match's.
    func menuMusic(_ on: Bool) {
        guard menuOn != on else { return }
        menuOn = on
        loop(menuTrack, AtmosphereData.menuMusic.file, on)
    }

    private func loop(_ v: Voice, _ name: String, _ on: Bool) {
        v.player.stop()
        v.mixer.outputVolume = 0
        v.looping = false
        guard on, let buffer = buffers[name], running else { return }
        v.looping = true
        v.speed.rate = 1
        v.player.scheduleBuffer(buffer, at: nil, options: [.loops], completionHandler: nil)
        v.player.play()
    }

    /// One frame of the looping layers: the crowd's three envelopes, the music's and its duck, each
    /// read across that layer's `quietDb`…`loudDb` and scaled by the player's two volumes (§12).
    /// A layer at a time scale of 0 (the match paused) holds where it is.
    func apply(_ l: SmashCore.Atmosphere.Levels, crowd: Double, music: Double) {
        typealias A = AtmosphereData
        for (v, bed) in zip(beds, A.beds) {
            let level = switch bed.follows {
            case .home: l.home
            case .away: l.away
            case .swell: l.swell
            }
            let pan = bed.follows == .swell ? bed.pan + l.swellPan : bed.pan
            set(v, db: bed.quietDb + (bed.loudDb - bed.quietDb) * level, volume: crowd,
                pan: pan, rate: bed.rate * l.rate, hold: l.rate == 0)
        }
        let m = A.matchMusic
        set(matchTrack, db: m.quietDb + (m.loudDb - m.quietDb) * l.music + A.duckDepthDb * l.duck, volume: music,
            pan: 0, rate: m.followsTimeScale ? l.rate : 1, hold: m.followsTimeScale && l.rate == 0)
        let n = A.menuMusic
        set(menuTrack, db: n.quietDb + (n.loudDb - n.quietDb) * l.music + A.duckDepthDb * l.duck, volume: music,
            pan: 0, rate: 1, hold: false)
    }

    private func set(_ v: Voice, db: Double, volume: Double, pan: Double, rate: Double, hold: Bool) {
        guard v.looping else { return }
        v.mixer.outputVolume = Float(min(SoundMix.amplitude(db) * max(volume, 0), 1))
        v.mixer.pan = Float(min(max(pan, -1), 1))
        if hold {
            if v.player.isPlaying { v.player.pause() }
        } else {
            v.speed.rate = Float(min(max(rate, 0.25), 4))
            if !v.player.isPlaying, v.player.engine != nil, running { v.player.play() }
        }
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
