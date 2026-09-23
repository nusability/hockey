import Foundation
import Testing
@testable import SmashCore

/// The stadium and the drums (spec §8.8, shared/data/atmosphere.toml): the crowd follows the ball
/// toward one goal or the other, the events push it, the music lifts late, and everything falls away
/// when the match does. Android's `AtmosphereTest` checks the same list.
@Suite struct AtmosphereTests {
    static var params: Atmosphere.Params {
        var p = Atmosphere.Params()
        p.shape = 1.6; p.base = 0.06; p.rise = 0.95; p.hush = 0.3
        p.lateSeconds = 30; p.lateRise = 0.35
        p.attackDanger = 0.45; p.defendDanger = 0.55; p.panSpan = 0.5
        p.surgeDecay = 0.55; p.attackRate = 3.2; p.releaseRate = 0.7
        p.surge.kickoff = 0.45; p.surge.goalFor = 1; p.surge.goalAgainst = -0.75; p.surge.save = 0.4
        p.surge.post = 0.35; p.surge.steal = 0.12; p.surge.whistle = -0.15
        p.surge.periodEnd = -0.35; p.surge.ended = -0.6
        p.music.base = 0; p.music.rise = 0.8; p.music.lateRise = 1; p.music.attackRate = 1.2; p.music.releaseRate = 0.45
        p.duckAttack = 0.04; p.duckHold = 0.5; p.duckRelease = 1.1
        p.minRate = 0.42
        return p
    }

    static func snapshot(z: Double, clock: Double = 60, state: MatchState = .play,
                         overtime: Bool = false) -> MatchSnapshot {
        let players: [MatchSnapshot.Player] = (0..<12).map {
            MatchSnapshot.Player(team: $0 < 6 ? 0 : 1, role: $0 % 6 == 0 ? .goalie : .forward,
                                 radius: 1, x: 0, z: 0, vx: 0, vz: 0, facing: 0)
        }
        let ball = MatchSnapshot.Ball(x: 0, z: z, vx: 0, vz: 0, radius: 0.36, carrier: nil, orbit: 0, orbitDirection: 1)
        return MatchSnapshot(state: state, players: players, ball: ball, aim: nil, playerCarrier: false,
                             clock: clock, score: [0, 0], period: 1, overtime: overtime, time: 0, result: nil)
    }

    /// Runs `seconds` of frames at 1/60 and returns where the levels end up.
    @discardableResult
    static func settle(_ a: inout Atmosphere, _ s: MatchSnapshot?, seconds: Double,
                       danger: Atmosphere.Danger? = nil, timeScale: Double = 1) -> Atmosphere.Levels {
        var out = a.now
        for _ in 0..<Int(seconds * 60) { out = a.update(1.0 / 60, s, danger: danger, timeScale: timeScale) }
        return out
    }

    @Test func openPlayIsQuietAndEven() {
        var a = Atmosphere(Self.params)
        let l = Self.settle(&a, Self.snapshot(z: 0), seconds: 12)
        #expect(abs(l.home - l.away) < 0.01)
        #expect(l.home < 0.1)
        #expect(l.swell < 0.1)
        #expect(abs(l.swellPan) < 0.01)
    }

    @Test func ourAttackLiftsOurEndAndHushesTheirs() {
        var a = Atmosphere(Self.params)
        let l = Self.settle(&a, Self.snapshot(z: Tuning.Pitch.goalLineZ), seconds: 12)
        #expect(l.home > 0.9)
        #expect(l.away < 0.05)
        #expect(l.swell > 0.9)
        // The swell leans toward the end being attacked: theirs, which is the away bed's side.
        #expect(l.swellPan < -0.4)
    }

    @Test func theirAttackIsTheMirrorOfOurs() {
        var ours = Atmosphere(Self.params), theirs = Atmosphere(Self.params)
        let a = Self.settle(&ours, Self.snapshot(z: Tuning.Pitch.goalLineZ), seconds: 12)
        let b = Self.settle(&theirs, Self.snapshot(z: -Tuning.Pitch.goalLineZ), seconds: 12)
        #expect(abs(a.home - b.away) < 1e-9)
        #expect(abs(a.away - b.home) < 1e-9)
        #expect(abs(a.swellPan + b.swellPan) < 1e-9)
    }

    @Test func aDangerousShotGripsBothEnds() {
        var a = Atmosphere(Self.params)
        let calm = Self.settle(&a, Self.snapshot(z: 10), seconds: 8)
        var b = Atmosphere(Self.params)
        let gripped = Self.settle(&b, Self.snapshot(z: 10), seconds: 8, danger: .theirs)
        #expect(gripped.home > calm.home)
        #expect(gripped.away > calm.away)
    }

    @Test func aGoalOfOursLiftsUsAndSinksThem() {
        var a = Atmosphere(Self.params)
        let s = Self.snapshot(z: 0)
        Self.settle(&a, s, seconds: 6)
        let before = a.now
        a.hear(.goal(team: 0, scorer: 1, assist: nil, ownGoal: false), s)
        let after = Self.settle(&a, s, seconds: 0.5)
        #expect(after.home > before.home)
        #expect(after.away < before.away)
    }

    @Test func aGoalAgainstIsTheMirror() {
        var a = Atmosphere(Self.params)
        let s = Self.snapshot(z: 0)
        Self.settle(&a, s, seconds: 6)
        a.hear(.goal(team: 1, scorer: 7, assist: nil, ownGoal: false), s)
        let after = Self.settle(&a, s, seconds: 0.5)
        #expect(after.away > after.home)
    }

    @Test func aSaveLiftsOnlyTheKeepersOwnEnd() {
        var a = Atmosphere(Self.params)
        let s = Self.snapshot(z: 0)
        Self.settle(&a, s, seconds: 6)
        let before = a.now
        a.hear(.save(by: 0), s)                    // player 0 is the player's own goalie
        let after = Self.settle(&a, s, seconds: 0.3)
        #expect(after.home > before.home)
        #expect(after.away <= before.away + 1e-9)
    }

    @Test func theCrowdComesUpFasterThanItSettles() {
        var a = Atmosphere(Self.params)
        let loud = Self.snapshot(z: Tuning.Pitch.goalLineZ)
        let rising = Self.settle(&a, loud, seconds: 0.5).home
        var b = Atmosphere(Self.params)
        Self.settle(&b, loud, seconds: 12)
        let top = b.now.home
        let falling = Self.settle(&b, Self.snapshot(z: 0), seconds: 0.5).home
        #expect(rising / max(top, 1e-9) > (top - falling) / max(top, 1e-9))
    }

    @Test func theMusicLiftsInTheLastSeconds() {
        var early = Atmosphere(Self.params), late = Atmosphere(Self.params)
        let a = Self.settle(&early, Self.snapshot(z: 0, clock: 90), seconds: 10)
        let b = Self.settle(&late, Self.snapshot(z: 0, clock: 2), seconds: 10)
        #expect(b.music > a.music + 0.2)
    }

    @Test func overtimeIsAllTheWayLate() {
        var a = Atmosphere(Self.params)
        let l = Self.settle(&a, Self.snapshot(z: 0, clock: 0, overtime: true), seconds: 10)
        #expect(l.music > 0.9)
    }

    @Test func aDuckingCuePushesTheMusicBackAndItComesBack() {
        var a = Atmosphere(Self.params)
        let s = Self.snapshot(z: 0)
        Self.settle(&a, s, seconds: 2)
        a.duck(seconds: 0.2)
        let ducked = Self.settle(&a, s, seconds: 0.3)
        #expect(ducked.duck > 0.9)
        let back = Self.settle(&a, s, seconds: 6)
        #expect(back.duck < 0.05)
    }

    @Test func theLayersFollowTheTimeScaleAndHoldWhenPaused() {
        var a = Atmosphere(Self.params)
        let s = Self.snapshot(z: 0)
        #expect(a.update(1.0 / 60, s, danger: nil, timeScale: 0.45).rate == 0.45)
        #expect(a.update(1.0 / 60, s, danger: nil, timeScale: 0.18).rate == Self.params.minRate)
        #expect(a.update(1.0 / 60, s, danger: nil, timeScale: 0).rate == 0)
        #expect(a.update(1.0 / 60, s, danger: nil, timeScale: 1).rate == 1)
    }

    @Test func leavingTheMatchTakesEverythingWithIt() {
        var a = Atmosphere(Self.params)
        Self.settle(&a, Self.snapshot(z: Tuning.Pitch.goalLineZ), seconds: 12)
        let gone = Self.settle(&a, nil, seconds: 20)
        #expect(gone.home < 0.01)
        #expect(gone.away < 0.01)
        #expect(gone.swell < 0.01)
        #expect(gone.music < 0.01)
    }
}
