// Records the simulation's golden vectors (spec §4.7) into shared/vectors/match/:
//
//     cd ios/SmashCore && swift run -c release RecordMatchVectors            # writes missing files; refuses to change one
//     cd ios/SmashCore && swift run -c release RecordMatchVectors --rerecord # overwrites — only with a spec change
//     cd ios/SmashCore && swift run -c release RecordMatchVectors --survey   # prints outcomes, writes nothing
//
// A vector is a setup plus the player's finger as (tick, down|up) events. Where the player plays, a
// small bot plays the tape once — lifting on a snap, through the late grace, early into a pending
// release, or unassisted — and the tape it played is what the file stores: the replaying suites
// never run the bot, they replay the tape.
import Foundation
import SmashCore

let root = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    .deletingLastPathComponent().deletingLastPathComponent()
let outDir = root.appendingPathComponent("shared/vectors/match")
let rerecord = CommandLine.arguments.contains("--rerecord")
let survey = CommandLine.arguments.contains("--survey")
let provenance = "Recorded by ios/SmashCore RecordMatchVectors (macOS, arm64). Replayed bit-exactly by SmashCoreTests and android/core."

// MARK: The bot

/// How the bot decides when to lift.
enum Policy {
    /// Lift the moment a release would snap (§5.3 rule 1).
    case snap
    /// Give-and-go: lift on a pass first, then on a shot once a pass has been made (§10 drill 2).
    case giveAndGo
    /// Lift on a shot; pass only to a team-mate further up the pitch (§10 drills 4–5).
    case shootFirst
    /// Rotate per possession through a snap, the late grace, a pending release and an unassisted
    /// release, so the tape exercises every branch of §5.3.
    case mixed
}

/// A shot snap, or a pass snap to a team-mate at least 3 further up the pitch.
func shootsOrPassesForward(_ snap: MatchSnapshot, _ carrier: Int) -> Bool {
    if snap.aim == .shot { return true }
    if case .pass(let m)? = snap.aim { return snap.players[m].z > snap.players[carrier].z + 3 }
    return false
}

nonisolated(unsafe) var liftCounts: [Match.LiftOutcome: Int] = [:]

/// Plays `vector` with `policy` driving the finger; returns the tape it played.
func playTape(_ vector: MatchVector, _ policy: Policy) -> [(tick: Int, down: Bool)] {
    var match = vector.makeMatch()
    var tape: [(tick: Int, down: Bool)] = []
    var down = false
    var passed = false
    var possession: Int?
    var heldSince = 0
    var mode = 0
    var lastLift = -1000
    var carrierAtLift: Int?
    let modes: [Match.LiftOutcome] = [.snap, .lateGrace, .pending, .unassisted]
    while match.ticks < vector.maxTicks && match.state != .ended {
        let snap = match.snapshot
        let carrier = snap.playerCarrier ? snap.ball.carrier : nil
        if carrier != possession {
            possession = carrier
            heldSince = match.ticks
            if carrier != nil { mode = (mode + 1) % modes.count }
        }
        var lift = false
        // One lift per possession spell: a pending release (§5.3) is left to fire, not re-armed.
        if down, snap.state == .play, carrier != nil, match.ticks - lastLift >= 45 || carrier != carrierAtLift {
            let outcome = match.previewLift()
            switch policy {
            case .snap:
                lift = outcome == .snap
            case .shootFirst:
                lift = shootsOrPassesForward(snap, carrier!)
            case .giveAndGo:
                if case .pass? = snap.aim, !passed { lift = true }
                if snap.aim == .shot && passed { lift = true }
            case .mixed:
                let waited = match.ticks - heldSince
                switch modes[mode] {
                case .unassisted: lift = waited >= 90 && outcome == .unassisted
                case .snap: lift = shootsOrPassesForward(snap, carrier!)
                default: lift = outcome == modes[mode]
                }
                if waited >= 480 { lift = true }
            }
        }
        if lift { liftCounts[match.previewLift(), default: 0] += 1; lastLift = match.ticks; carrierAtLift = carrier }
        if lift {
            tape.append((match.ticks, false)); match.hold(false); down = false
        } else if !down {
            tape.append((match.ticks, true)); match.hold(true); down = true
        }
        match.tick()
        for event in match.drainEvents() {
            switch event {
            case .pass(let from, _) where snap.players[from].team == 0: passed = true
            case .ready: passed = false
            default: break
            }
        }
    }
    return tape
}

// MARK: The vectors

let player = Tactics.defaults

func matchSetup(seed: UInt64, sport: Sport, home: Club, away: Club, period: Double, cup: Bool, control: Control,
                homeFormation: Formation = .balanced) -> MatchSetup {
    var h = SideSetup.club(home)
    h.formation = homeFormation
    return MatchSetup(seed: seed, sport: sport, home: h, away: .club(away), periodSeconds: period,
                      orbitPeriod: control == .automatic ? Tuning.Orbit.demoPeriod : 2.0, cup: cup, control: control)
}

func drill(_ d: Drill, seed: UInt64) -> MatchVector {
    MatchVector(setup: .drill(DrillSetup(drill: d, seed: seed, tactics: player, orbitPeriod: 2.0)),
                every: 30, maxTicks: Int(d.seconds * 120) + 20 * 120, inputs: [])
}

/// The first seed from `from` whose cup match reaches sudden-death overtime.
func overtimeSeed(from: UInt64) -> UInt64 {
    var seed = from
    while true {
        let v = MatchVector(setup: .match(matchSetup(seed: seed, sport: .field, home: .glowowls, away: .falcons,
                                                     period: 60, cup: true, control: .automatic)),
                            every: 120, maxTicks: 60_000, inputs: [])
        var m = v.makeMatch()
        while m.state != .ended && m.ticks < v.maxTicks && !m.overtime { m.tick() }
        if m.overtime { return seed }
        seed += 1
    }
}

struct Entry {
    let file: String
    let about: String
    var vector: MatchVector
    let policy: Policy?
}

var entries = [
    Entry(file: "drill1-first-shot.txt", about: "Drill 1 (§10): the player lifts whenever the release snaps.",
          vector: drill(.shot, seed: 0x5EED_0001), policy: .snap),
    Entry(file: "drill2-give-and-go.txt", about: "Drill 2 (§10): pass first, then shoot — goals count only after a pass.",
          vector: drill(.pass, seed: 0x5EED_0002), policy: .giveAndGo),
    Entry(file: "drill5-moving-cones.txt", about: "Drill 5 (§10): patrolling dummies block; the player shoots on a shot snap and passes only forward.",
          vector: drill(.moving, seed: 0x5EED_0005), policy: .shootFirst),
    Entry(file: "drill8-scrimmage.txt", about: "Drill 8 (§10): free play — both sides may score, every goal resets; the player shoots on a shot snap and passes only forward.",
          vector: drill(.scrimmage, seed: 0x5EED_0008), policy: .shootFirst),
    Entry(file: "demo-field.txt", about: "A demo match (§9): Moss Foxes v Rocket Lynx, field hockey, 2-minute periods, both sides automatic.",
          vector: MatchVector(setup: .match(matchSetup(seed: 0xD3_0001, sport: .field, home: .mossfoxes, away: .rocketlynx,
                                                      period: 120, cup: false, control: .automatic)),
                              every: 120, maxTicks: 60_000, inputs: []), policy: nil),
    Entry(file: "demo-ice.txt", about: "A demo match (§9) on ice (Himalaya): Glacier Wolves v Nebula Narwhals, 2-minute periods, both sides automatic.",
          vector: MatchVector(setup: .match(matchSetup(seed: 0xD3_0002, sport: .ice, home: .wolves, away: .nebula,
                                                      period: 120, cup: false, control: .automatic)),
                              every: 120, maxTicks: 60_000, inputs: []), policy: nil),
    Entry(file: "match-player-tape.txt", about: "A full match (§8) the player plays: snaps, late-grace lifts, pending releases and unassisted releases, in rotation.",
          vector: MatchVector(setup: .match(matchSetup(seed: 0xF00D_0003, sport: .field, home: .mossfoxes, away: .scorpions,
                                                      period: 120, cup: false, control: .player, homeFormation: .diamond)),
                              every: 120, maxTicks: 60_000, inputs: []), policy: .mixed),
]

let otSeed = overtimeSeed(from: 0xC0_0001)
entries.append(Entry(file: "cup-overtime.txt",
                     about: "A cup match (§8.4), Glow Owls v Mirage Falcons, 1-minute periods, both automatic, level after three periods: sudden-death overtime. Seed = the first from 0xC00001 that reaches overtime.",
                     vector: MatchVector(setup: .match(matchSetup(seed: otSeed, sport: .field, home: .glowowls, away: .falcons,
                                                                 period: 60, cup: true, control: .automatic)),
                                         every: 120, maxTicks: 60_000, inputs: []), policy: nil))

// MARK: Writing

var failures = 0
try FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)
for var entry in entries {
    if let policy = entry.policy { entry.vector.inputs = playTape(entry.vector, policy) }
    if entry.policy != nil { print("  lifts:", liftCounts); liftCounts = [:] }
    let start = Date()
    let body = entry.vector.run()
    let seconds = Date().timeIntervalSince(start)
    let events = body.filter { $0.hasPrefix("e ") }
    let goals = events.filter { $0.split(separator: " ")[2] == "goal" }.count
    let interrupted = events.filter { $0.split(separator: " ")[2] == "interrupted" }.count
    let lastSample = body.last { $0.hasPrefix("s ") }!.split(separator: " ")
    print("\(entry.file): \(lastSample[1]) ticks, \(entry.vector.inputs.count) inputs, \(goals) goals, "
          + "\(interrupted) interruptions, final \(lastSample[2]) \(lastSample[6])–\(lastSample[7]), "
          + String(format: "%.2f s", seconds))
    if survey { continue }
    let text = (["# Smash Hockey 3D — match golden vector (spec §4.7). " + entry.about, "# " + provenance]
                + entry.vector.headerLines() + body).joined(separator: "\n") + "\n"
    let url = outDir.appendingPathComponent(entry.file)
    if let existing = try? String(contentsOf: url, encoding: .utf8) {
        if existing == text { print("  unchanged"); continue }
        if !rerecord {
            print("  REFUSED: it differs from what this build computes. Re-recording a vector needs a spec change in the same commit (spec §4.7); pass --rerecord if that is what this is.")
            failures += 1
            continue
        }
    }
    try text.write(to: url, atomically: true, encoding: .utf8)
    print("  wrote \(body.count) lines")
}
exit(failures == 0 ? 0 : 1)
