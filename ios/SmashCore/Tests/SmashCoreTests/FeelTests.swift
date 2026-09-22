import Foundation
import Testing
@testable import SmashCore

/// Feel/ (spec §5.2, §8.8, §16.4): the arrow's length, what each event sets off, the countdown and
/// the aim window, the mix and the voices. Android's `FeelTest` checks the same list.
@Suite struct FeelTests {
    static let arrow = AimArrow.Params(maxLength: 16, minLength: 2.5, passShort: 1.6, shotShort: 1.2,
                                       boardMargin: 1.2, boardProbe: 0.6, probeStep: 0.5)

    static var params: MatchCues.Params {
        var p = MatchCues.Params()
        p.banner.versus = 2.2; p.banner.period = 1.5; p.banner.periodEnd = 2.4; p.banner.whistle = 1.8
        p.banner.ready = 0.9; p.banner.lost = 1.2; p.banner.goal = 2.4; p.banner.end = 1.5
        p.shakeGoal = 1.2; p.shakePost = 0.5
        p.hapticWindow = 0.35; p.hapticSharp = 0.9; p.hapticGoal = 1; p.goalPulses = [0, 0.5, 1]; p.hapticAgainst = 0.4
        p.hapticTick = 0.25; p.releaseLow = 0.35; p.releaseHigh = 1; p.releaseSlow = 12; p.releaseFast = 30
        p.shotSlow = 12; p.shotFast = 30; p.countdown = 5; p.stingDelay = 1.3
        return p
    }

    static func snapshot(state: MatchState = .play, clock: Double = 60, period: Int = 1, overtime: Bool = false,
                         ball: (x: Double, vx: Double) = (0, 0), carrier: Int? = nil, aim: MatchSnapshot.Aim? = nil,
                         playerCarrier: Bool = false) -> MatchSnapshot {
        let players: [MatchSnapshot.Player] = (0..<12).map { (i: Int) -> MatchSnapshot.Player in
            let team: Int = i < 6 ? 0 : 1
            let role: Role = i % 6 == 0 ? .goalie : .forward
            let x = Double(i)
            return MatchSnapshot.Player(team: team, role: role, radius: 1, x: x, z: -x, vx: 0, vz: 0, facing: 0)
        }
        let b = MatchSnapshot.Ball(x: ball.x, z: 0, vx: ball.vx, vz: 0, radius: 0.36, carrier: carrier, orbit: 0, orbitDirection: 1)
        return MatchSnapshot(state: state, players: players, ball: b, aim: aim, playerCarrier: playerCarrier, clock: clock,
                             score: [0, 0], period: period, overtime: overtime, time: 0, result: nil)
    }

    static func banners(_ cues: [Cue]) -> [Banner] {
        cues.compactMap { if case .banner(let b) = $0 { b } else { nil } }
    }

    // MARK: the arrow (§5.2)

    @Test func freeArrowStopsShortOfTheBoards() {
        // Up the middle from the centre: the march stops at 17.5 (its end), so 17.5 − 1.5 − 1.2 = 14.8.
        #expect(abs(AimArrow.length(.free, x: 0, z: 0, angle: 0, corner: 2, Self.arrow) - 14.8) < 1e-9)
        // Toward the side boards from x = 12: clear only to 2.0, so the minimum.
        #expect(AimArrow.length(.free, x: 12, z: 0, angle: .pi / 2, corner: 2, Self.arrow) == 2.5)
        #expect(AimArrow.boards(x: 12, z: 0, angle: .pi / 2, corner: 2, Self.arrow) == 2.0)
    }

    @Test func passAndShotArrowsReachTheirTarget() {
        #expect(abs(AimArrow.length(.pass(x: 0, z: 10), x: 0, z: 0, angle: 0, corner: 2, Self.arrow) - 6.9) < 1e-9)
        #expect(abs(AimArrow.length(.shot(goalZ: 26), x: 0, z: 14, angle: 0, corner: 2, Self.arrow) - 9.3) < 1e-9)
        // A pass across the whole pitch is still stopped by the boards: 17.5 − 2.7.
        #expect(abs(AimArrow.length(.pass(x: 0, z: 25), x: 0, z: -5, angle: 0, corner: 2, Self.arrow) - 14.8) < 1e-9)
    }

    @Test func iceCornersStopTheArrowSooner() {
        let field = AimArrow.boards(x: 10, z: 20, angle: .pi / 4, corner: 2, Self.arrow)
        let ice = AimArrow.boards(x: 10, z: 20, angle: .pi / 4, corner: 8.5, Self.arrow)
        #expect(ice < field)
    }

    // MARK: banners (§16.4)

    @Test func theDrillsGetReadySaysWhy() {
        var c = MatchCues(Self.params, drill: true, audible: true)
        let s = Self.snapshot(state: .ready)
        #expect(Self.banners(c.hear(.ready, s)).map(\.key) == [.eventGetReady])
        _ = c.hear(.goal(team: 0, scorer: 1, assist: nil, ownGoal: false), Self.snapshot(state: .goal))
        #expect(Self.banners(c.hear(.ready, s)).map(\.key) == [.eventNiceAgain])
        let lost = Self.banners(c.hear(.drillInterrupted(.saved), Self.snapshot(state: .lost)))
        #expect(lost == [Banner(.eventSaved, style: .bad, seconds: 1.2)])
        #expect(Self.banners(c.hear(.ready, s)).map(\.key) == [.eventAgain])
        #expect(Self.banners(c.hear(.drillInterrupted(.deadBall), Self.snapshot(state: .lost))).map(\.key) == [.eventReset])
    }

    @Test func periodsAreAnnounced() {
        var c = MatchCues(Self.params, drill: false, audible: true)
        #expect(Self.banners(c.hear(.faceOff(spot: Spot(x: 0, z: 0)), Self.snapshot(state: .faceOff))).isEmpty)
        #expect(Self.banners(c.hear(.periodEnd(period: 1), Self.snapshot(state: .periodEnd)))
                == [Banner(.eventPeriodEnd, ["1"], style: .info, seconds: 2.4)])
        #expect(Self.banners(c.hear(.faceOff(spot: Spot(x: 0, z: 0)), Self.snapshot(state: .faceOff, period: 2)))
                == [Banner(.eventPeriod, ["2"], style: .info, seconds: 1.5)])
        // The third period's end into overtime, then sudden death.
        #expect(Self.banners(c.hear(.periodEnd(period: 3), Self.snapshot(state: .periodEnd, period: 3))).map(\.key) == [.eventOvertime])
        #expect(Self.banners(c.hear(.faceOff(spot: Spot(x: 0, z: 0)), Self.snapshot(state: .faceOff, period: 3, overtime: true)))
                .map(\.key) == [.eventSuddenDeath])
        // A face-off after a goal says nothing.
        _ = c.hear(.goal(team: 1, scorer: 7, assist: nil, ownGoal: false), Self.snapshot(state: .goal))
        #expect(Self.banners(c.hear(.faceOff(spot: Spot(x: 0, z: 0)), Self.snapshot(state: .faceOff))).isEmpty)
    }

    @Test func theLastPeriodsEndIsTheEndsBanner() {
        var c = MatchCues(Self.params, drill: false, audible: true)
        #expect(Self.banners(c.hear(.periodEnd(period: 3), Self.snapshot(state: .ended, period: 3))).isEmpty)
        let end = c.hear(.end(result: .lost), Self.snapshot(state: .ended, period: 3))
        #expect(Self.banners(end) == [Banner(.eventFinal, style: .bad, seconds: 1.5)])
        #expect(end.contains(.sound(.matchResultLose, x: nil, delay: 1.3)))
        #expect(end.contains(.sound(.matchWhistleEnd, x: nil, delay: 0)))
        var d = MatchCues(Self.params, drill: true, audible: true)
        let won = d.hear(.end(result: .won), Self.snapshot(state: .ended))
        #expect(Self.banners(won) == [Banner(.resultDrillWon, style: .good, seconds: 1.5)])
        #expect(won.contains(.sound(.matchResultWin, x: nil, delay: 1.3)))
    }

    @Test func goalsShakeAndCelebrate() {
        var c = MatchCues(Self.params, drill: false, audible: true)
        let ours = c.hear(.goal(team: 0, scorer: 3, assist: nil, ownGoal: false), Self.snapshot(state: .goal))
        #expect(ours.contains(.shake(1.2)))
        #expect(Self.banners(ours) == [Banner(.eventGoal, style: .good, seconds: 2.4)])
        #expect(ours.filter { if case .haptic(.impact(1), _) = $0 { true } else { false } }.count == 3)
        #expect(ours.contains(.haptic(.impact(1), delay: 0.5)))
        let theirs = c.hear(.goal(team: 1, scorer: 8, assist: nil, ownGoal: false), Self.snapshot(state: .goal))
        #expect(Self.banners(theirs).map(\.style) == [.bad])
        #expect(theirs.contains(.sound(.matchGoalAgainst, x: nil, delay: 0)))
        #expect(ours.contains(.sound(.matchGoalHorn, x: nil, delay: 0)) && ours.contains(.sound(.matchGoalCheer, x: nil, delay: 0)))
        #expect(c.intro(home: "MOSS FOXES", away: "GLOW OWLS") == [.banner(Banner(.eventVersus, ["MOSS FOXES", "GLOW OWLS"], style: .info, seconds: 2.2))])
    }

    @Test func theDemoIsOnlySeen() {
        var c = MatchCues(Self.params, drill: false, audible: false)
        #expect(c.hear(.goal(team: 0, scorer: 3, assist: nil, ownGoal: false), Self.snapshot(state: .goal)) == [.shake(1.2)])
        #expect(c.hear(.save(by: 6), Self.snapshot()) == [.pop(.save, x: 6, z: -6)])
        #expect(c.intro(home: "A", away: "B").isEmpty)
        #expect(c.frame(Self.snapshot(clock: 3)).isEmpty)
    }

    @Test func thePostShakesTheBoardsDoNot() {
        var c = MatchCues(Self.params, drill: false, audible: true)
        #expect(c.hear(.post, Self.snapshot(ball: (x: 3, vx: 0))) == [.shake(0.5), .sound(.matchPost, x: 3, delay: 0), .haptic(.sharp(0.9), delay: 0)])
        #expect(c.hear(.board(speed: 20), Self.snapshot(ball: (x: -15, vx: 0))) == [.sound(.matchBoard, x: -15, delay: 0)])
    }

    @Test func releasesScaleWithSpeedAndOnlyThePlayersBuzz() {
        var c = MatchCues(Self.params, drill: false, audible: true)
        let slow = c.hear(.shot(by: 2, kind: .shot), Self.snapshot(ball: (x: 0, vx: 12)))
        #expect(slow == [.sound(.matchShotSoft, x: 0, delay: 0), .haptic(.impact(0.35), delay: 0)])
        #expect(c.hear(.shot(by: 2, kind: .shot), Self.snapshot(ball: (x: 0, vx: 21)))[0] == .sound(.matchShotMedium, x: 0, delay: 0))
        let fast = c.hear(.shot(by: 2, kind: .shot), Self.snapshot(ball: (x: 0, vx: 30)))
        #expect(fast == [.sound(.matchShotHard, x: 0, delay: 0), .haptic(.impact(1), delay: 0)])
        // The player's goalie and the opponents release by themselves: no haptic.
        #expect(c.hear(.shot(by: 0, kind: .shot), Self.snapshot(ball: (x: 0, vx: 20))).count == 1)
        #expect(c.hear(.pass(from: 8, to: 9), Self.snapshot(ball: (x: 0, vx: 20))).count == 1)
    }

    @Test func theLastFiveSecondsTick() {
        var c = MatchCues(Self.params, drill: false, audible: true)
        #expect(c.frame(Self.snapshot(clock: 5.5)).isEmpty)
        #expect(c.frame(Self.snapshot(clock: 4.99)).count == 2)
        #expect(c.frame(Self.snapshot(clock: 4.2)).isEmpty)
        #expect(c.frame(Self.snapshot(clock: 3.99)).count == 2)
        #expect(c.frame(Self.snapshot(clock: 0.5, overtime: true)).isEmpty)
        #expect(c.frame(Self.snapshot(state: .periodEnd, clock: 0)).isEmpty)
    }

    @Test func enteringAWindowTicks() {
        var c = MatchCues(Self.params, drill: false, audible: true)
        let tick = [Cue.haptic(.tick(0.35), delay: 0)]
        #expect(c.frame(Self.snapshot(carrier: 1, aim: .unassisted, playerCarrier: true)).isEmpty)
        #expect(c.frame(Self.snapshot(carrier: 1, aim: .pass(to: 2), playerCarrier: true)) == tick)
        #expect(c.frame(Self.snapshot(carrier: 1, aim: .pass(to: 2), playerCarrier: true)).isEmpty)
        #expect(c.frame(Self.snapshot(carrier: 1, aim: .shot, playerCarrier: true)) == tick)
        // An opponent's aim is not the player's.
        #expect(c.frame(Self.snapshot(carrier: 7, aim: .pass(to: 8), playerCarrier: false)).isEmpty)
    }

    // MARK: the mix (§8.8)

    @Test func theMix() {
        #expect(abs(SoundMix.amplitude(-6) - 0.501187) < 1e-6)
        #expect(SoundMix.rate(pitch: 1.05, timeScale: 0.18, onPitch: true, min: 0.5, max: 2) == 0.5)
        #expect(SoundMix.rate(pitch: 1.05, timeScale: 0.18, onPitch: false, min: 0.5, max: 2) == 1.05)
        #expect(abs(SoundMix.rate(pitch: 1.2, timeScale: 0.45, onPitch: true, min: 0.5, max: 2) - 0.54) < 1e-12)
        #expect(SoundMix.pan(x: 15, width: 0.6) == 0.6)
        #expect(SoundMix.pan(x: -7.5, width: 0.6) == -0.3)
        #expect(SoundMix.pan(x: nil, width: 0.6) == 0)
        let (l, r) = SoundMix.stereo(0)
        #expect(abs(l - r) < 1e-12 && abs(l * l + r * r - 1) < 1e-12)
        // ± semitones, uniformly: the ends and the middle of the draw.
        #expect(abs(SoundMix.pitch(semitones: 1, u: 0) - pow(2, -1.0 / 12)) < 1e-12)
        #expect(SoundMix.pitch(semitones: 1, u: 0.5) == 1)
        #expect(SoundMix.pitch(semitones: 0, u: 0.9) == 1)
    }

    @Test func aVariantIsNeverTheSameTwiceInARow() {
        #expect(SoundMix.variant(count: 1, last: 0, u: 0.7) == 0)
        #expect(SoundMix.variant(count: 3, last: nil, u: 0.99) == 2)
        for last in 0..<4 {
            for k in 0..<100 {
                let v = SoundMix.variant(count: 4, last: last, u: Double(k) / 100)
                #expect(v != last && (0..<4).contains(v))
            }
        }
        // Every other variant is reachable.
        #expect(Set((0..<100).map { SoundMix.variant(count: 3, last: 1, u: Double($0) / 100) }) == [0, 2])
    }

    @Test func voicesAreSharedByPriority() {
        var pool = VoicePool(count: 3)
        // The face-off drop has one voice: a second play steals the first.
        #expect(pool.claim(.matchFaceoffDrop, now: 0, seconds: 1) == 0)
        #expect(pool.claim(.matchFaceoffDrop, now: 0.1, seconds: 1) == 0)
        #expect(pool.claim(.uiDigitFlip, now: 0.2, seconds: 1) == 1)      // priority 40
        #expect(pool.claim(.uiSliderTick, now: 0.3, seconds: 1) == 2)     // priority 30
        // Full: a higher priority steals the lowest; nothing lower, the play is dropped.
        #expect(pool.claim(.matchGoalHorn, now: 0.4, seconds: 1) == 2)
        #expect(pool.claim(.uiDigitFlip, now: 0.5, seconds: 1) == nil)
        // A finished voice is free again.
        #expect(pool.claim(.uiDigitFlip, now: 1.15, seconds: 1) == 0)
    }

    /// Every event the match or the kit plays is declared in the bank (shared/data/sounds.toml).
    @Test func theBankHasEveryEventThePlayUses() {
        let used: [SoundCue] = [.matchShotSoft, .matchShotMedium, .matchShotHard, .matchPass, .matchReceive, .matchBoard,
                                .matchBlock, .matchPost, .matchSave, .matchSteal, .matchWhistleShort, .matchWhistleEnd,
                                .matchFaceoffDrop, .matchGoalHorn, .matchGoalCheer, .matchGoalAgainst, .matchCountdownTick,
                                .matchResultWin, .matchResultLose, .uiButtonPress, .uiDigitFlip, .uiPanelPop,
                                .uiCameraWhooshLong, .uiCameraWhooshShort, .uiError, .uiSliderTick, .uiConfettiPop]
        for cue in used { #expect(!cue.spec.field.isEmpty && !cue.spec.ice.isEmpty, "\(cue.rawValue) has no files") }
    }
}
