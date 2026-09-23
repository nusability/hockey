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
        return MatchSnapshot(state: state, players: players, ball: b, aim: aim, playerCarrier: playerCarrier,
                             offside: players.map { _ in false }, clock: clock,
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

    /// `[aim]`'s drawing numbers: the ribbon starts at the orbit radius plus 0.35, spreads at most
    /// 1.1 × 0.62 / 2 across (the arrowhead's wings, 0.95 × 1.1, are wider), its head reaches
    /// 1.3 × 1.1 past the ribbon's end, and the lock-on never draws more than a lead point away.
    static let drawing = AimArrow.Drawing(start: Tuning.Orbit.radius + 0.35, across: 0.95 * 1.1,
                                          head: 1.3 * 1.1, lock: 9.5)

    /// The box a written mesh is bounded by has to hold what is written into it: a box that misses
    /// the drawn extent is culled away and the arrow stops being drawn (SMASH-24's follow-up — the
    /// arrow drew only while the carrier was in one half). Every carrier the pitch allows, aiming
    /// in every direction, against both kinds of clamp the length can take.
    @Test func theArrowsBoundsHoldEveryVertexItEverWrites() {
        let box = AimArrow.extent(Self.arrow, Self.drawing)
        #expect(box.x > Tuning.Pitch.halfWidth && box.z > Tuning.Pitch.halfLength)
        let r = Tuning.Player.outfieldRadius
        var checked = 0
        for corner in [2.0, 8.5] {
            for x in stride(from: -(Tuning.Pitch.halfWidth - r), through: Tuning.Pitch.halfWidth - r, by: 1.4) {
                for z in stride(from: -(Tuning.Pitch.halfLength - r), through: Tuning.Pitch.halfLength - r, by: 1.4) {
                    for step in 0..<72 {
                        let angle = Double(step) / 72 * 2 * .pi
                        for kind in [AimArrow.Kind.free, .shot(goalZ: 26), .shot(goalZ: -26),
                                     .pass(x: Tuning.Pitch.halfWidth - r, z: Tuning.Pitch.halfLength - r)] {
                            let len = AimArrow.length(kind, x: x, z: z, angle: angle, corner: corner, Self.arrow)
                            for p in AimArrow.outline(x: x, z: z, angle: angle, length: len, Self.drawing) {
                                #expect(abs(p.x) <= box.x, "x \(p.x) outside \(box.x) at (\(x), \(z)) ∠\(angle)")
                                #expect(abs(p.z) <= box.z, "z \(p.z) outside \(box.z) at (\(x), \(z)) ∠\(angle)")
                                checked += 1
                            }
                        }
                    }
                }
            }
        }
        #expect(checked > 100_000)
    }

    /// The lock-on is drawn around a team-mate, who stands on the pitch: their ring and the lead
    /// point the dotted line runs to are inside the same box.
    @Test func theLockOnsMarksAreInsideTheArrowsBounds() {
        let box = AimArrow.extent(Self.arrow, Self.drawing)
        let r = Tuning.Player.outfieldRadius
        #expect(Tuning.Pitch.halfWidth - r + Self.drawing.lock <= box.x)
        #expect(Tuning.Pitch.halfLength - r + Self.drawing.lock <= box.z)
    }

    // MARK: the flat marks — the trail and the pops (§8.8)

    /// The trail and the pops are written in place too, so their boxes have to hold everywhere the
    /// ball and the players can take them. A whole match is walked against the reach they are built
    /// from: a mark outside it would be culled and stop being drawn (SMASH-33).
    @Test func everyMarkAMatchDrawsStaysInsideItsBounds() {
        let reach = SceneMarks.reach
        var m = Match(MatchSetup.demo(seed: 5, world: .magicwood, home: .club(.mossfoxes),
                                      away: .club(.nebula), periodSeconds: 30))
        var ticks = 0
        while m.state != .ended {
            m.tick()
            let s = m.snapshot
            #expect(abs(s.ball.x) <= reach.x, "the ball at x \(s.ball.x)")
            #expect(abs(s.ball.z) <= reach.z, "the ball at z \(s.ball.z)")
            for p in s.players {
                #expect(abs(p.x) <= reach.x && abs(p.z) <= reach.z, "a player at (\(p.x), \(p.z))")
            }
            ticks += 1
        }
        #expect(ticks > 1000)
        // Both marks are drawn round a point inside that reach, so both boxes are wider than it.
        let trail = SceneMarks.trailExtent(width: 0.5)      // `[trail] width`
        let pop = SceneMarks.popExtent(radius: 2.0)         // `[pop] radius_to`
        #expect(trail.x > reach.x && trail.z > reach.z)
        #expect(pop.x >= reach.x + 2 && pop.z >= reach.z + 2)
    }

    // MARK: the nets (§8.8)

    /// `presentation.toml [net]` and `[net.sway]` as the apps hand them in.
    static let net = GoalNet.Params(height: 1.9, columns: 12, rows: 5, depth: 4, cord: 0.05, cordLift: 0.012,
                                    sway: 0.18, swaySeconds: 3.6, wave: 1.1, calm: 0.4, ripple: 0.55,
                                    decay: 3.2, frequency: 18.0, k: 4.0, reach: 2.5, seconds: 1.6,
                                    hitSpeed: 22.0, hitLeast: 2.0)

    /// The net is four sheets a goal, and every one of them is laced all the way round: the ground,
    /// the posts, the crossbar and the sheet next door. A node on an edge never moves, so the four
    /// sheets stay one skin however hard the cloth breathes.
    @Test func everyNetSheetIsLacedAlongEveryEdge() {
        for sign in [Double(-1), 1] {
            let sheets = GoalNet.sheets(sign, Self.net)
            #expect(sheets.count == 4)
            for s in sheets {
                for i in 0...s.columns {
                    #expect(s.bell(i, 0) == 0 && s.bell(i, s.rows) == 0)
                }
                for j in 0...s.rows {
                    #expect(s.bell(0, j) == 0 && s.bell(s.columns, j) == 0)
                }
                #expect(s.bell(s.columns / 2, s.rows / 2) > 0.5)
            }
            // The back sheet stands a goal's depth behind the line; the roof sits at the net's height.
            #expect(abs(sheets[0].point(0, 0).z - sign * (Tuning.Pitch.goalLineZ + Tuning.Pitch.goalDepth)) < 1e-9)
            #expect(abs(sheets[1].point(0, 0).y - Self.net.height) < 1e-9)
        }
    }

    /// The nets' bounds have to hold what the apps write into them: the films, the cords either side
    /// of every grid line and lifted off the film, at every moment of the cloth's sway and of a
    /// goal's ripple, at both goals, with and without Reduce Motion. A box that misses a vertex is
    /// culled away and the nets stop being drawn (SMASH-33, the aim arrow's old fault).
    @Test func theNetsBoundsHoldEveryVertexItEverWrites() {
        let p = Self.net
        let box = GoalNet.extent(p)
        let lift = p.cordLift, half = p.cord / 2
        var checked = 0
        for sign in [Double(-1), 1] {
            let strike = GoalNet.Point(2.4, 0.11, sign * (Tuning.Pitch.goalLineZ + Tuning.Pitch.goalDepth))
            for sheet in GoalNet.sheets(sign, p) {
                let (a, u, n) = (sheet.acrossUnit, sheet.upUnit, sheet.normal)
                for i in 0...sheet.columns {
                    for j in 0...sheet.rows {
                        let node = sheet.point(i, j)
                        let bell = sheet.bell(i, j)
                        for step in 0...120 {                       // two seconds of frames, and a goal
                            let t = Double(step) / 60
                            for calm in [false, true] {
                                for age in [-1.0, t, t - 0.4] {
                                    let d = GoalNet.offset(x: node.x, y: node.y, z: node.z, bell: bell, t: t,
                                                           reduceMotion: calm, strikeX: strike.x,
                                                           strikeY: strike.y, strikeZ: strike.z, age: age,
                                                           strength: 1, p)
                                    // The film's vertex, and the four a cord's two ribbons put here.
                                    for (shift, off) in [(GoalNet.Point(0, 0, 0), 0.0),
                                                         (u * half, lift), (u * -half, lift),
                                                         (a * half, lift), (a * -half, lift)] {
                                        let v = node + shift + n * (d + off)
                                        #expect(abs(v.x) <= box.x, "x \(v.x) outside \(box.x)")
                                        #expect(v.y >= box.yLow && v.y <= box.yHigh, "y \(v.y) outside the box")
                                        #expect(abs(v.z) <= box.z, "z \(v.z) outside \(box.z)")
                                        checked += 1
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
        #expect(checked > 100_000)
        // And the box is no bigger than it has to be: the goal, grown by everything that moves.
        #expect(box.z < Tuning.Pitch.goalLineZ + Tuning.Pitch.goalDepth + 1)
    }

    /// The cloth never stands still — with or without a ball, and under Reduce Motion, which calms
    /// it once and never freezes it. A contact's ripple rides on top, bigger than the sway, deeper
    /// the harder the ball came in, and is gone by `seconds`.
    @Test func theNetBreathesAlwaysAndRipplesOnlyForAWhile() {
        let p = Self.net
        let sheet = GoalNet.sheets(1, p)[0]
        let node = sheet.point(p.columns / 2, p.rows / 2)
        let bell = sheet.bell(p.columns / 2, p.rows / 2)
        func offset(_ t: Double, calm: Bool = false, age: Double = -1, strength: Double = 1) -> Double {
            GoalNet.offset(x: node.x, y: node.y, z: node.z, bell: bell, t: t, reduceMotion: calm,
                           strikeX: node.x, strikeY: node.y, strikeZ: node.z, age: age,
                           strength: strength, p)
        }
        // Over one period the middle of the back sheet swings the full amplitude, both ways.
        var lo = 0.0, hi = 0.0
        for step in 0...360 {
            let d = offset(Double(step) / 100)
            lo = min(lo, d)
            hi = max(hi, d)
        }
        #expect(hi > 0.9 * p.sway * bell && lo < -0.9 * p.sway * bell)
        // Reduce Motion keeps `calm` of it — once, and never nothing.
        for step in 0...360 {
            let t = Double(step) / 100
            #expect(abs(offset(t, calm: true) - offset(t) * p.calm) < 1e-12)
        }
        #expect((0...360).contains { abs(offset(Double($0) / 100, calm: true)) > 0.2 * p.sway })
        // A contact is felt at once, is deeper than the breath, and is forgotten on time.
        func dent(_ strength: Double) -> Double {
            (0...40).map { abs(offset(Double($0) / 200, age: Double($0) / 200, strength: strength) - offset(Double($0) / 200)) }.max()!
        }
        #expect(dent(1) > 0.7 * p.ripple * bell)
        #expect(dent(1) > 2 * p.sway)
        // A dribbled ball nudges it; a hard shot punches it, in proportion.
        #expect(abs(dent(0.25) - dent(1) / 4) < 1e-9)
        #expect(dent(0) == 0)
        #expect(offset(0.5, age: p.seconds) == offset(0.5))
        // Reduce Motion calms a dent by the same share as the breath, and never flattens it.
        #expect(abs(offset(0.1, calm: true, age: 0.1) - offset(0.1, age: 0.1) * p.calm) < 1e-12)
    }

    // MARK: what the ball does to the cloth (§8.8)

    /// A ball meeting a sheet, from wherever: the ripple starts where it struck, on the sheet it
    /// struck, as deep as it was fast into that sheet — and nothing happens when it misses, when it
    /// is only leaning on the net, or on a second frame against the same sheet.
    @Test func theBallDentsWhateverSheetItMeetsWhereItMeetsIt() {
        let p = Self.net
        let r = 0.36                                        // the ball's radius, both sports
        let frame = 1.0 / 60
        let line = Tuning.Pitch.goalLineZ, back = line + Tuning.Pitch.goalDepth
        let hw = Tuning.Pitch.goalMouthWidth / 2
        func touch(_ x: Double, _ z: Double, _ vx: Double, _ vz: Double) -> GoalNet.Touch? {
            GoalNet.touch(x: x, z: z, vx: vx, vz: vz, seconds: frame, ballY: 0, radius: r, p)
        }

        // A shot into the back of the net, from inside it after it crossed the line: sheet 0, at
        // the ball's x across the mouth, on the back's own plane.
        let goal = touch(1.2, back - 0.5, 0, 20)
        #expect(goal?.sheet == 0 && goal?.goal == 1)
        #expect(abs((goal?.point.x ?? 0) - 1.2) < 1e-9)
        #expect(abs((goal?.point.z ?? 0) - back) < 1e-9)
        #expect(abs((goal?.speed ?? 0) - 20) < 1e-9)
        #expect(abs((goal?.strength ?? 0) - 20 / p.hitSpeed) < 1e-9)

        // A shot into the side netting from behind the goal: sheet 3 (the +x side), at its depth.
        let side = touch(hw + 0.6, line + 0.8, -12, 0)
        #expect(side?.sheet == 3)
        #expect(abs((side?.point.x ?? 0) - hw) < 1e-9)
        #expect(abs((side?.point.z ?? 0) - (line + 0.8)) < 1e-9)
        #expect(abs((side?.speed ?? 0) - 12) < 1e-9)

        // The same, at the other goal and the other side: sheet 2, goal 0.
        let far = touch(-hw - 0.6, -line - 0.8, 9, 0)
        #expect(far?.goal == 0 && far?.sheet == 2)
        #expect(abs((far?.speed ?? 0) - 9) < 1e-9)

        // At an angle into the back, the contact lands where the path crosses it, not where the
        // ball started: 20 across and 20 along carries it 0.14 sideways over the 0.14 it has left.
        let angled = touch(0, back - r - 0.14, 20, 20)
        #expect(angled?.sheet == 0)
        #expect(abs((angled?.point.x ?? 0) - 0.14) < 1e-3)
        #expect(abs((angled?.speed ?? 0) - 20) < 1e-9)

        // A hard shot dents it fully; anything faster still only fully.
        #expect(touch(0, back - 0.5, 0, 30)?.strength == 1)
        // A slow one in proportion.
        #expect(abs((touch(0, back - r - 0.05, 0, 5.5)?.strength ?? 0) - 0.25) < 1e-9)

        // A miss: the ball goes by the goal's side, well clear of the netting.
        #expect(touch(hw + 2.5, line + 0.8, -12, 0) == nil)
        // A miss: in front of the goal line, nowhere near the cloth.
        #expect(touch(0, line - 6, 0, 20) == nil)
        // A miss: across the mouth, parallel to the back and never reaching it.
        #expect(touch(-2, back - 1.2, 14, 0) == nil)
        // Leaning on the net, slower than `hitLeast`: the cloth does not answer.
        #expect(touch(0, back - r - 0.01, 0, 1) == nil)
        // A second frame against the same sheet is the same contact, not a new one: the ball is
        // already standing on it.
        #expect(touch(0, back - r, 0, 20) == nil)
        // Off the back onto a side is a new contact, on the new sheet.
        #expect(touch(-hw + r + 0.01, back - r, -14, -3)?.sheet == 2)

        // The contact point never leaves its sheet, however wide of the mouth the ball comes in.
        for x in stride(from: -hw - 1.0, through: hw + 1.0, by: 0.05) {
            guard let t = touch(x, back - 0.5, 0, 20) else { continue }
            #expect(abs(t.point.x) <= hw + 1e-9)
            #expect(t.point.y >= 0 && t.point.y <= p.height)
            #expect(abs(t.point.z) <= back + 1e-9)
        }
    }

    /// And the same maths, driven the way an app drives it — two ticks a frame at 60 fps, off the
    /// ball as the frame found it — finds the cloth in a match actually played. Every goal is
    /// followed by a contact in the net it went into — on its back, or on a side sheet it grazes on
    /// the way in — and the cloth is struck far more often than it is scored past.
    @Test func aPlayedMatchStrikesTheCloth() {
        let p = Self.net
        var m = Match(MatchSetup.demo(seed: 4, world: .himalaya, home: .club(.mossfoxes),
                                      away: .club(.nebula), periodSeconds: 120))
        let frame = 2 * Tuning.Time.tickSeconds          // one frame at 60 Hz; the tick is 1/120 s
        var touches = 0, goals = 0, answered = 0, onTheBack = 0
        var owed: Int?                                   // the goal still waiting for its back sheet
        while m.state != .ended {
            let was = m.snapshot.ball
            m.tick(); m.tick()
            for e in m.drainEvents() {
                if case .goal(let team, _, _, _) = e {
                    goals += 1
                    owed = team == 0 ? 1 : 0             // team 0 attacks +z, so it scores into goal 1
                }
            }
            if let t = GoalNet.touch(x: was.x, z: was.z, vx: was.vx, vz: was.vz, seconds: frame,
                                     ballY: 0, radius: was.radius, p) {
                touches += 1
                #expect(t.strength > 0 && t.strength <= 1)
                if t.goal == owed {
                    answered += 1
                    if t.sheet == 0 { onTheBack += 1 }
                    owed = nil
                }
            }
        }
        #expect(goals > 0)
        #expect(answered == goals, "\(answered) of \(goals) goals reached the cloth")
        #expect(onTheBack > 0, "no goal reached the back sheet")      // the rest graze a side first
        #expect(touches > goals, "\(touches) contacts for \(goals) goals — the net is only hit when scored past")
    }

    // MARK: the scoreboard, 0:0 to 99:99 (§16.4)

    static let board = Scoreboard.metrics(card: 0.14, gap: 0.0112, colon: 0.084, chip: 0.30, margin: 0.03)

    @Test func everyScoreTheBoardCanShowKeepsItsLayout() {
        let want = 2 * Scoreboard.cards + 1
        for home in 0...99 {
            for away in [0, 1, 9, 10, 11, 99] {
                let text = Scoreboard.score(home, away)
                #expect(text.count == want, "\(home):\(away) is '\(text)'")
                #expect(text.filter { $0 == ":" }.count == 1)
            }
        }
        #expect(Scoreboard.score(0) == " 0")
        #expect(Scoreboard.score(9) == " 9")
        #expect(Scoreboard.score(10) == "10")
        #expect(Scoreboard.score(99) == "99")
        #expect(Scoreboard.score(120) == "99")       // clamped, never wider than the board
        #expect(Scoreboard.score(-1) == " 0")
        // The card that changes when the tenth goal goes in is the tens card, so it flips.
        let nine = Array(Scoreboard.score(9)), ten = Array(Scoreboard.score(10))
        #expect(nine[0] == Scoreboard.blank && ten[0] == "1")
    }

    @Test func theTwoSidesAndTheirChipsNeverRunIntoEachOther() {
        let m = Self.board
        // The sides' cards clear the colon in the middle and each other.
        #expect(m.scoreX - m.halfCards > 0)
        // A chip clears its own side's cards.
        #expect(m.chipX - 0.30 / 2 >= m.scoreX + m.halfCards)
        // And the board holds the lot.
        #expect(m.boardWidth / 2 >= m.chipX + 0.30 / 2)
        // Nothing here depends on the score: the layout is the same at 0:0 and 99:99.
        #expect(m.halfCards > 0.14)                  // two cards wide, not one
    }

    @Test func aDrillsTargetSetsItsWidth() {
        #expect(Scoreboard.drill(scored: 0, target: 3) == "0/3")
        #expect(Scoreboard.drill(scored: 3, target: 3) == "3/3")
        #expect(Scoreboard.drill(scored: 9, target: 3) == "3/3")     // never past the target
        #expect(Scoreboard.drill(scored: 0, target: 12) == " 0/12")
        #expect(Scoreboard.drill(scored: 10, target: 12) == "10/12")
        for target in 1...99 {
            let width = Scoreboard.drill(scored: 0, target: target).count
            for scored in 0...target { #expect(Scoreboard.drill(scored: scored, target: target).count == width) }
        }
    }

    // MARK: the UI's arrivals and departures (conventions: UI)

    /// motion.json's `pop` in, `soft` out, `fade.seconds`.
    static func presence() -> UIPresence {
        UIPresence(enter: SpringToken(stiffness: 260, damping: 13), exit: SpringToken(stiffness: 160, damping: 18))
    }
    static let fadeSeconds = 0.18

    /// Runs `seconds` of 60 Hz frames.
    static func run(_ p: inout UIPresence, _ seconds: Double, reduceMotion: Bool = false) {
        for _ in 0..<Int(seconds * 60) { p.advance(1.0 / 60, reduceMotion: reduceMotion, fadeSeconds: fadeSeconds) }
    }

    @Test func anArrivalEndsOnItsExactPose() {
        var p = Self.presence()
        p.show()
        Self.run(&p, 0.1)
        #expect(p.phase == .shown && p.arrival < 1)          // still on its way
        Self.run(&p, 2)
        #expect(p.isSettledIn)
        #expect(p.arrival == 1)                              // exactly, not a hair short for ever
    }

    @Test func aLeaveAlwaysEndsHidden() {
        for reduce in [false, true] {
            var p = Self.presence()
            p.show()
            Self.run(&p, 2, reduceMotion: reduce)
            p.hide()
            Self.run(&p, 0.05, reduceMotion: reduce)
            #expect(p.phase == .leaving, "\(reduce)")
            Self.run(&p, 3, reduceMotion: reduce)
            #expect(p.phase == .hidden, "\(reduce)")
            #expect(!p.isVisible, "\(reduce)")
        }
    }

    /// The bug that left a piece of UI hanging in the air: Reduce Motion is read every frame on
    /// Android (the system animator scale, battery saver), so it can turn on or off in the middle of
    /// a transition. Neither way of playing a leave may strand the other's.
    @Test func reduceMotionTurningOnOrOffMidLeaveStillFinishes() {
        for (before, after) in [(false, true), (true, false)] {
            var p = Self.presence()
            p.show()
            Self.run(&p, 2, reduceMotion: before)
            p.hide()
            Self.run(&p, 0.1, reduceMotion: before)          // the leave is in flight…
            #expect(p.phase == .leaving, "\(before) then \(after)")
            Self.run(&p, 5, reduceMotion: after)             // …and the setting flips under it
            #expect(p.phase == .hidden, "\(before) then \(after)")
        }
    }

    @Test func aLeaveInterruptedByAShowComesBackAndCanLeaveAgain() {
        var p = Self.presence()
        p.show()
        Self.run(&p, 2)
        p.hide()
        Self.run(&p, 0.1)
        p.show()                                             // caught mid-flight
        Self.run(&p, 2)
        #expect(p.isSettledIn && p.arrival == 1)
        p.hide()
        Self.run(&p, 3)
        #expect(p.phase == .hidden)
    }

    /// Reduce Motion is read every frame on Android, so it can flip in the middle of an **arrival**
    /// too — not only a leave. Either way of drawing it, the arrival still ends on its exact pose,
    /// fully opaque: an element that stops short of its mark is one whose caption lands without it.
    @Test func reduceMotionTurningOnOrOffMidArrivalStillLands() {
        for (before, after) in [(false, true), (true, false)] {
            var p = Self.presence()
            p.show()
            Self.run(&p, 0.08, reduceMotion: before)             // the arrival is in flight…
            #expect(p.phase == .shown && p.arrival < 1, "\(before) then \(after)")
            Self.run(&p, 3, reduceMotion: after)                 // …and the setting flips under it
            #expect(p.isSettledIn, "\(before) then \(after)")
            #expect(p.arrival == 1, "\(before) then \(after)")
            #expect(p.opacity == 1, "\(before) then \(after)")
        }
    }

    /// A screen entered twice in quick succession: the staggered arrivals of the second entry are
    /// asked for while the first is still in the air. Every element still ends on its exact pose —
    /// none is left part-way, and none is taken for arrived while it still has a delay to serve.
    @Test func aScreenEnteredTwiceInQuickSuccessionStillLandsEverything() {
        for stagger in [0.0, 0.05, 0.12] {
            var p = Self.presence()
            p.show(after: stagger)
            Self.run(&p, 0.06)
            p.show(after: stagger)                               // entered again, mid-flight
            #expect(!p.isSettledIn, "\(stagger)")               // a pending arrival is not arrived
            Self.run(&p, 3)
            #expect(p.isSettledIn && p.arrival == 1, "\(stagger)")
        }
    }

    @Test func hidingBeforeAnArrivalBeginsCancelsIt() {
        var p = Self.presence()
        p.show(after: 0.5)
        p.hide()
        Self.run(&p, 2)
        #expect(p.phase == .hidden && !p.isVisible)
    }

    // MARK: what the arrow shows, transition by transition (§5.2)

    /// One frame of the arrow, 1/60 s after the last.
    private struct Rig {
        var showing = AimArrow.Showing()
        var clock = 0.0
        static let fadeIn = 0.08

        mutating func frame(_ state: MatchState = .play, playerCarrier: Bool = true, carrier: Int? = 1,
                            aim: MatchSnapshot.Aim? = .unassisted, step: Double = 1.0 / 60) -> AimArrow.Look {
            clock += step
            return showing.frame(state: state, playerCarrier: playerCarrier, carrier: carrier, aim: aim,
                                 clock: clock, fadeIn: Self.fadeIn)
        }
    }

    @Test func theArrowShowsOnlyForThePlayersOwnCarrierInPlay() {
        var r = Rig()
        for state in MatchState.allCases {
            let shown = r.frame(state).arrow
            #expect(shown == (state == .play || state == .ready), "\(state)")
        }
        #expect(!r.frame(.play, playerCarrier: false).arrow)
        #expect(!r.frame(.play, carrier: nil).arrow)
        #expect(!r.frame(.play, aim: nil).arrow)
        // …and it comes back the very next frame the match is back in play.
        #expect(r.frame(.play).arrow)
    }

    @Test func theArrowsColourSaysWhatAReleaseWouldDo() {
        var r = Rig()
        #expect(r.frame(aim: .unassisted).colour == 0)
        #expect(r.frame(aim: .pass(to: 3)).colour == 1)
        #expect(r.frame(aim: .shot).colour == 2)
        #expect(!r.frame(aim: .unassisted).snapped)
        #expect(r.frame(aim: .shot).snapped)
    }

    /// The whole reason the arrow has a state machine: a snap's fade must start at every beginning
    /// and at no other time, and it must never run on for ever.
    @Test func theLockOnFadesInAtEverySnapBeginning() {
        var r = Rig()
        // A free arrow has no lock-on.
        #expect(r.frame(aim: .unassisted).lock == .none)
        // A snap begins: the fade runs from nothing to one over fade_in, then stops.
        #expect(r.frame(aim: .shot).fade < 0.3)
        for _ in 0..<4 { _ = r.frame(aim: .shot) }
        #expect(r.frame(aim: .shot).fade == 1)
        for _ in 0..<600 { _ = r.frame(aim: .shot) }
        #expect(r.frame(aim: .shot).fade == 1)
        // A new snap begins, even to the same receiver, when the ball changes hands.
        _ = r.frame(aim: .pass(to: 3))
        for _ in 0..<20 { _ = r.frame(aim: .pass(to: 3)) }
        #expect(r.frame(aim: .pass(to: 3)).fade == 1)
        #expect(r.frame(carrier: 2, aim: .pass(to: 3)).fade < 1)
        // And after a whistle it fades in again rather than coming back fully lit.
        for _ in 0..<20 { _ = r.frame(carrier: 2, aim: .pass(to: 3)) }
        #expect(r.frame(carrier: 2, aim: .pass(to: 3)).fade == 1)
        _ = r.frame(.whistle, aim: .pass(to: 3))
        #expect(r.frame(.play, carrier: 2, aim: .pass(to: 3)).fade < 1)
    }

    @Test func aRestartedSceneClockDoesNotStickTheLockOn() {
        var r = Rig()
        for _ in 0..<20 { _ = r.frame(aim: .shot) }
        #expect(r.frame(aim: .shot).fade == 1)
        // A new match's scene starts its clock again; the arrow must not read a negative age.
        r.clock = 0
        let look = r.frame(aim: .shot)
        #expect(look.fade >= 0 && look.fade <= 1)
    }

    /// Twenty minutes of frames at 120 Hz, the match state, the carrier and the aim shuffled by a
    /// seeded generator: the arrow is shown on **exactly** the frames §5.2 says it must be, whatever
    /// sequence led there. SMASH-24 was "the arrow stops appearing after a few minutes" — this is
    /// the half of that which the core owns, and it must stay ruled out by a test, not by reading.
    @Test func theArrowNeverGetsStuckOverALongMatch() {
        var showing = AimArrow.Showing()
        var rng = SplitMix64(seed: 0x5EED_A1_ACE)
        let states = MatchState.allCases
        var clock = 0.0
        var state = MatchState.play
        var carrier: Int? = 1
        var aim: MatchSnapshot.Aim? = .unassisted
        var mine = true
        // The snap on screen, tracked here independently of the thing under test.
        var since = 0.0
        var was: (carrier: Int, aim: MatchSnapshot.Aim)?
        var shown = 0
        for _ in 0..<(120 * 60 * 20) {
            clock += 1.0 / 120
            // Roughly a change a second in each of the four inputs, independently.
            if rng.uniform() < 1.0 / 120 { state = states[Int(rng.uniform() * Double(states.count))] }
            if rng.uniform() < 1.0 / 120 { carrier = rng.uniform() < 0.1 ? nil : Int(rng.uniform() * 12) }
            if rng.uniform() < 1.0 / 120 { mine = rng.uniform() < 0.7 }
            if rng.uniform() < 1.0 / 120 {
                let r = rng.uniform()
                aim = r < 0.1 ? nil : r < 0.4 ? .unassisted : r < 0.7 ? .pass(to: Int(rng.uniform() * 12)) : .shot
            }
            let look = showing.frame(state: state, playerCarrier: mine, carrier: carrier, aim: aim,
                                     clock: clock, fadeIn: Rig.fadeIn)
            let want = mine && carrier != nil && aim != nil && (state == .play || state == .ready)
            #expect(look.arrow == want, "clock \(clock) state \(state) mine \(mine)")
            guard want, let aim, let carrier else {
                was = nil
                continue
            }
            shown += 1
            // The colour is the aim's, always.
            let colour = switch aim { case .unassisted: 0; case .pass: 1; case .shot: 2 }
            #expect(look.colour == colour)
            // A snap begins when what it aims at changes, and when the ball changes hands.
            if was == nil || was!.carrier != carrier || was!.aim != aim {
                was = (carrier, aim)
                since = clock
            }
            // A free arrow has no lock-on to fade in; a snap's fades over `fadeIn` and then stands.
            let fade = colour == 0 ? 0 : min(1, (clock - since) / Rig.fadeIn)
            #expect(abs(look.fade - fade) < 1e-9)
            let lock: AimArrow.Lock = switch aim {
            case .unassisted: .none
            case .pass(let to): .pass(to)
            case .shot: .shot
            }
            #expect(look.lock == lock)
        }
        #expect(shown > 120 * 60)           // the run really did spend minutes with the arrow up
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

    /// The only audible count of time is the countdown (§8.5): the clock's split-flap cards
    /// change every second and must not clack, or the match ticks from the first whistle.
    @Test func onlyTheScoreClacks() {
        #expect(Scoreboard.Face.score.clacks)
        #expect(!Scoreboard.Face.clock.clacks)
    }

    @Test func theLastFiveSecondsTick() {
        var c = MatchCues(Self.params, drill: false, audible: true)
        #expect(c.frame(Self.snapshot(clock: 5.5)).isEmpty)
        #expect(c.frame(Self.snapshot(clock: 4.99)).count == 2)
        #expect(c.frame(Self.snapshot(clock: 4.2)).isEmpty)
        #expect(c.frame(Self.snapshot(clock: 3.99)).count == 2)
        #expect(c.frame(Self.snapshot(clock: 2.5)).count == 2)
        #expect(c.frame(Self.snapshot(clock: 1.5)).count == 2)
        #expect(c.frame(Self.snapshot(clock: 0.5)).count == 2)
        #expect(c.frame(Self.snapshot(clock: 0)).isEmpty)              // nothing on zero itself
        // Overtime is sudden death: it is never counted down, at any clock (§8.5).
        for clock in [5.5, 4.5, 3.5, 2.5, 1.5, 0.5] {
            #expect(c.frame(Self.snapshot(clock: clock, overtime: true)).isEmpty)
        }
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

    // MARK: where the camera stands (§8.6)

    /// `presentation.toml [camera]` and §8.6's shot window, as the apps hand them over.
    static let camera = MatchCamera.Params(
        height: 36, back: 20, look: -4, follow: 0.85, minZ: -7, maxZ: 14, rate: 2.2,
        halfWidth: 16.5, fitNear: 8, minFov: 45, maxFov: 78,
        buildupHeight: 8, buildupBack: 20, buildupFov: 44, buildupWeight: 0.4, buildupRate: 5,
        goalRadius: 13, goalHeight: 4.5, goalRise: 1.1, goalStartAngle: 1.8, goalSweep: 0.14,
        goalSweepSeconds: 4.5, goalLookHeight: 0.4, goalFov: 46, goalWeight: 1, goalRateIn: 4, goalRateOut: 1.6,
        reduceGoalWeight: 0.35, reduceBuildupWeight: 0.15,
        goalLineZ: Tuning.Pitch.goalLineZ, postX: Tuning.Pitch.postX,
        postMargin: Tuning.SlowMotion.shotPostMargin, shotHorizon: Tuning.SlowMotion.shotHorizon)

    /// A lap of the whole pitch and well past both goal lines, through the corners and up the
    /// middle. The camera is asked about every metre of it.
    static let walk: [SIMD2<Double>] = [
        [0, 0], [14, 0], [14, 24], [14, 31], [0, 33], [-14, 31], [-14, 24], [-14, 0],
        [-14, -24], [-14, -31], [0, -33], [14, -31], [14, -24], [14, 0], [0, 0],
        [0, 33], [0, -33], [0, 0], [-14, 30], [14, -30], [0, 0],
    ]

    /// The bug the owner saw: behind the goal line the camera shook between two poses at frame
    /// rate. A ball there is **not** a shot about to score — whichever way its z velocity happens to
    /// point this frame — so nothing may frame it as one.
    @Test func aBallBehindAGoalLineIsNeverFramedAsAShot() {
        let p = Self.camera
        for z in [p.goalLineZ + 0.1, p.goalLineZ + 4, 30.0] {
            for vz in [-25.0, -8, 8, 25] {
                for side in [-1.0, 1.0] {
                    let ball = MatchCamera.Ball(x: 0, z: side * z, vx: 0, vz: vz)
                    #expect(MatchCamera.buildupGoalZ(ball, p) == nil, "z \(side * z) vz \(vz)")
                }
            }
        }
        // In front of the line and running at the mouth, it still is one — and it is the goal the
        // ball is heading into, never the one its velocity's sign happens to name.
        let coming = MatchCamera.Ball(x: 0, z: 20, vx: 0, vz: 20)
        #expect(MatchCamera.buildupGoalZ(coming, p) == p.goalLineZ)
        let going = MatchCamera.Ball(x: 0, z: -20, vx: 0, vz: -20)
        #expect(MatchCamera.buildupGoalZ(going, p) == -p.goalLineZ)
    }

    /// Walked over the whole pitch — corners, both goal mouths and well behind both nets — the
    /// camera stays stable. Jitter has a shape: the eye stepping one way and straight back the
    /// next frame, over and over. A blend that turns around once, when a shot stops being a shot,
    /// does not: it turns *once* and it turns by a hair.
    ///
    /// The stated thresholds: no single frame reverses the eye or the look-at by more than
    /// **0.15 m**, and two reversals worth noticing (over a centimetre) never fall within
    /// **10 frames** of each other. The bug threw the eye tens of metres, end to end, every frame.
    @Test func theCameraNeverJittersWhereverTheBallIs() {
        for reduce in [false, true] {
            var camera = MatchCamera(Self.camera, aspect: 0.46)
            var last: (eye: SIMD3<Double>, at: SIMD3<Double>)?
            var lastStep: (eye: SIMD3<Double>, at: SIMD3<Double>)?
            var worstStep = 0.0, worstReversal = 0.0
            var frame = 0, lastReversalFrame = -100, closestReversals = Int.max
            for (a, b) in zip(Self.walk, Self.walk.dropFirst()) {
                let span = b - a
                let frames = max(1, Int((span.x * span.x + span.y * span.y).squareRoot() / 12 * 60))
                let v = SIMD2(span.x / Double(frames) * 60, span.y / Double(frames) * 60)
                for i in 0..<frames {
                    frame += 1
                    let at = a + span * (Double(i) / Double(frames))
                    let ball = MatchCamera.Ball(x: at.x, z: at.y, vx: v.x, vz: v.y)
                    let mode: MatchCamera.Mode = MatchCamera.buildupGoalZ(ball, Self.camera) == nil ? .play : .buildup
                    let pose = camera.advance(1.0 / 60, mode: mode, ball: ball, aspect: 0.46, reduceMotion: reduce)
                    let eye = SIMD3(pose.eyeX, pose.eyeY, pose.eyeZ), target = SIMD3(pose.atX, pose.atY, pose.atZ)
                    defer { last = (eye, target) }
                    guard let l = last else { continue }
                    let step = (eye: eye - l.eye, at: target - l.at)
                    worstStep = max(worstStep, Self.length(step.eye), Self.length(step.at))
                    if let previous = lastStep {
                        var reversal = 0.0
                        for pair in [(step.eye, previous.eye), (step.at, previous.at)] where Self.dot(pair.0, pair.1) < 0 {
                            reversal = max(reversal, min(Self.length(pair.0), Self.length(pair.1)))
                        }
                        worstReversal = max(worstReversal, reversal)
                        if reversal > 0.01 {
                            closestReversals = min(closestReversals, frame - lastReversalFrame)
                            lastReversalFrame = frame
                        }
                    }
                    lastStep = step
                }
            }
            let why = "reduce motion: \(reduce)"
            #expect(worstStep < 1.6, "worst step \(worstStep), \(why)")
            #expect(worstReversal < 0.15, "worst reversal \(worstReversal), \(why)")
            #expect(closestReversals > 10, "reversals \(closestReversals) frames apart, \(why)")
        }
    }

    private static func length(_ v: SIMD3<Double>) -> Double { (v.x * v.x + v.y * v.y + v.z * v.z).squareRoot() }
    private static func dot(_ a: SIMD3<Double>, _ b: SIMD3<Double>) -> Double { a.x * b.x + a.y * b.y + a.z * b.z }
}
