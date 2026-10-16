// Trains the team policy by self-play (spec §7, SMASH-72). It writes checkpoints and nothing else
// — it is not on the path to production, and the policy it produces only reaches an app through
// `shared/assets/policy/` and a spec change.
//
//     cd ios/SmashCore && swift run -c release TrainTeamAI                     # the default run
//     cd ios/SmashCore && swift run -c release TrainTeamAI --iterations 400    # a longer one
//
// ## Why evolution strategies and not PPO
//
// The thing being optimised is small (a few thousand parameters) and the thing being measured is
// cheap (a 2-minute match costs 0.8 s, so ~75k simulated ticks a second a core). ES wants exactly
// that trade: no backward pass, no value function, no per-step credit assignment, no autograd
// dependency — just "perturb, play, move toward what won", which parallelises over cores with
// nothing but `concurrentPerform`. It needs only a score per match, which `MeasureMatches` already
// taught us how to compute. If it plateaus, PPO is the next rung and it will cost a Python stack;
// we pay for that when there is evidence we need it, not before.
//
// ## What the score rewards, and why each term is there
//
// The owner picked **off-ball shape**, **legible roles** and **variety** — explicitly *not* raw
// strength. But a side that is indifferent to winning learns nothing, so goals are the drive and
// the rest is shaping:
//
//   * `possession` — a dense signal from the first iteration. With random weights a side never
//     scores, so goal difference alone is a flat landscape with nothing to climb. Possession is the
//     gradient that gets a policy from "wanders off" to "goes for the ball".
//   * `receivers` — the deficit, measured: §7.4's greedy six-slot assignment offers 0.53 receivers
//     on average while carrying in the attacking third. This is the realism term.
//   * `spread` — the anti-swarm term, against the failure §7.2 names in writing: "two players
//     steering to one point is one player's job done twice, and it reads from the stands as a pack
//     of children following the ball."
//   * `goals` — the drive. Deliberately the smallest weight that still points downhill.
import Foundation
import SmashCore

// MARK: - Run configuration

struct Config {
    var iterations = 60
    var population = 32          // halved into antithetic pairs
    var matches = 4              // seeded matches per candidate
    var periodSeconds = 40.0     // three of these per match (§8)
    var hidden = 32
    var sigma = 0.05
    var learningRate = 0.002
    var decay = 0.001
    var seed: UInt64 = 0xA11CE
    /// `--reward victory` trains on goal difference alone. The shaping terms are still *measured*
    /// and reported, so the two arms can be compared on the same numbers — the question a
    /// victory-only run answers is not whether it wins, but whether a policy that only ever cared
    /// about winning also ends up spread out, patient and legible. If it does, the shaping below is
    /// me telling the search things it would have found on its own, and it should go.
    var victoryOnly = false
    /// `--replay <checkpoint>` writes one match as an HTML replay and exits, training nothing.
    var replay: String?
    /// `--evaluate <checkpoint>` reports a checkpoint's full metrics and exits.
    var evaluateOnly: String?
    /// Which seeded match `--replay` records.
    var replaySeed = 0
    /// Write a replay beside the checkpoints every this many iterations (0 to write none). The
    /// metrics say whether it is improving; only watching says whether it looks like hockey.
    var replayEvery = 25
    /// Metrics are sampled every this many ticks rather than every tick. A snapshot allocates, and
    /// the spacing term is O(n²) in the roster, so measuring at the tick rate costs more than the
    /// simulation it measures. 12 ticks is 10 Hz, far finer than anything being averaged.
    var sampleStride = 12
    /// `--bootstrap` fits the net to §7's rules by regression and writes `bootstrap.txt`, then exits.
    var bootstrap = false
    /// Matches of §7-vs-§7 to harvest teaching samples from. Both teams teach, so this is doubled.
    var teachMatches = 10
    var bootstrapEpochs = 30
    /// Rounds of DAgger after the first fit: roll the policy out, label the states *it* reached
    /// with §7's advice, add those to the pile and refit. 0 is plain behavioural cloning.
    var daggerRounds = 4
    /// Matches harvested per DAgger round.
    var daggerMatches = 6
    /// `--diagnose` measures whether §7's target is a *function* of the observation at all, then
    /// exits. See the mode below for what it answers and why it matters.
    var diagnose = false
    /// How often the policy's memory inputs are hidden during the fit. See `Backprop.step`.
    var memoryDropout = 0.5
    /// The step size never anneals below this. See the pull-back below.
    var sigmaFloor = 0.01
    /// `--analyse <checkpoint>` measures the stated objectives — shape, legible roles, no
    /// ball-chasing — for the policy and for §7 side by side, then exits. None of them are trained
    /// on, which is the point: a measure you optimise stops being a measure.
    var analyse: String?
    /// Seed offset for `--evaluate` and `--analyse`. The search selects its best on seeds 0..<
    /// `centreMatches`, so a number measured there is a number the search was allowed to fit. An
    /// offset moves the measurement onto seeds it has never been scored against — which is the
    /// only kind of number worth quoting, as two retracted claims tonight attest.
    var evalOffset = 0
    var bootstrapBatch = 256
    /// `--init <checkpoint>` starts the search from an existing checkpoint instead of random weights.
    var initFrom: String?
    /// The share of a candidate's matches played against the **current centre** rather than §7's
    /// rules. Self-play is what stops the policy overfitting to one opponent's habits, and it is
    /// what produces the `strength` ladder — but on its own it is zero-sum and says nothing about
    /// absolute progress, so some matches always stay against §7 as a fixed yardstick.
    var selfPlay = 0.25
    /// Iterations the centre may fail to beat its own best before the search is pulled back to
    /// that best and the step size cut. Evolution strategies estimate a gradient in 4,354
    /// dimensions from a few dozen samples; that estimate is noisy enough that the update is part
    /// signal and part random walk, and from a *good* starting point — an imitation bootstrap —
    /// the walk can undo in an hour what the bootstrap bought in a minute. Measured: possession
    /// against §7 fell 0.334 → 0.176 over 100 iterations while the reported best never improved.
    var patience = 40
    /// Seeded matches used to score the **centre**, as opposed to a candidate.
    ///
    /// Larger than `matches`, and that matters more than it looks. The best-so-far is the maximum
    /// of this estimate over thousands of iterations, so if the estimate is noisy the best is
    /// partly luck — and then nothing can beat it, the pull-back fires forever, and sigma anneals
    /// to nothing chasing a number that was never real. Measured: a centre scored 6.92 on 6 seeds
    /// and lost to §7 on 40.
    var centreMatches = 24
    var out = "../../.claude/worktrees-out/policy"
}

// A redirected stdout is block-buffered, so a long run's progress sits in a 4 KB buffer instead of
// reaching the log. Line-buffer it: this is a run you watch.
setvbuf(stdout, nil, _IOLBF, 0)

var cfg = Config()
var it = CommandLine.arguments.dropFirst().makeIterator()
while let a = it.next() {
    func num() -> Double { Double(it.next() ?? "") ?? 0 }
    switch a {
    case "--iterations": cfg.iterations = Int(num())
    case "--population": cfg.population = Int(num())
    case "--matches": cfg.matches = Int(num())
    case "--period": cfg.periodSeconds = num()
    case "--hidden": cfg.hidden = Int(num())
    case "--sigma": cfg.sigma = num()
    case "--lr": cfg.learningRate = num()
    case "--out": cfg.out = it.next() ?? cfg.out
    case "--reward": cfg.victoryOnly = (it.next() ?? "shaped") == "victory"
    case "--replay": cfg.replay = it.next()
    case "--evaluate": cfg.evaluateOnly = it.next()
    case "--replay-seed": cfg.replaySeed = Int(num())
    case "--replay-every": cfg.replayEvery = Int(num())
    case "--stride": cfg.sampleStride = Int(num())
    case "--bootstrap": cfg.bootstrap = true
    case "--teach-matches": cfg.teachMatches = Int(num())
    case "--epochs": cfg.bootstrapEpochs = Int(num())
    case "--dagger": cfg.daggerRounds = Int(num())
    case "--dagger-matches": cfg.daggerMatches = Int(num())
    case "--diagnose": cfg.diagnose = true
    case "--memory-dropout": cfg.memoryDropout = num()
    case "--sigma-floor": cfg.sigmaFloor = num()
    case "--analyse": cfg.analyse = it.next()
    case "--eval-offset": cfg.evalOffset = Int(num())
    case "--init": cfg.initFrom = it.next()
    case "--self-play": cfg.selfPlay = num()
    case "--patience": cfg.patience = Int(num())
    case "--centre-matches": cfg.centreMatches = Int(num())
    default: FileHandle.standardError.write("TrainTeamAI: unknown argument \(a)\n".data(using: .utf8)!)
    }
}
if cfg.population % 2 != 0 { cfg.population += 1 }

// MARK: - Scoring one match

/// What one match says about a policy. Every term is per match, so the weights below are readable.
struct Score {
    var goalsFor = 0.0
    var goalsAgainst = 0.0
    var possession = 0.0      // share of play ticks this side carried
    var receivers = 0.0       // mean genuine receiving options on ANY carry — the trained term
    var receiversFinal = 0.0  // the same, but only in the final third: comparable to the shape bench
    var spread = 0.0          // mean distance to the nearest team-mate, metres
    var pressure = 0.0        // mean distance from the ball to this side's nearest outfielder
    var territory = 0.0       // mean carry position up the pitch, −1 (own goal) to 1 (theirs)
    var attacking = 0.0       // share of play ticks spent carrying inside the attacking third
    var width = 0.0           // standard deviation of outfield x: does the side use the pitch

    /// Set from the run's configuration; it selects which reward `fitness(_:reference:)` returns.
    var victoryOnly = false

    static func mean(_ xs: [Score]) -> Score {
        guard !xs.isEmpty else { return Score() }
        let n = Double(xs.count)
        var m = Score()
        m.victoryOnly = xs[0].victoryOnly
        m.goalsFor = xs.reduce(0) { $0 + $1.goalsFor } / n
        m.goalsAgainst = xs.reduce(0) { $0 + $1.goalsAgainst } / n
        m.possession = xs.reduce(0) { $0 + $1.possession } / n
        m.receivers = xs.reduce(0) { $0 + $1.receivers } / n
        m.receiversFinal = xs.reduce(0) { $0 + $1.receiversFinal } / n
        m.spread = xs.reduce(0) { $0 + $1.spread } / n
        m.pressure = xs.reduce(0) { $0 + $1.pressure } / n
        m.territory = xs.reduce(0) { $0 + $1.territory } / n
        m.attacking = xs.reduce(0) { $0 + $1.attacking } / n
        m.width = xs.reduce(0) { $0 + $1.width } / n
        return m
    }
}


/// What the search climbs: **beat §7 on goals, resemble §7 in shape.**
///
/// Every shape term in the earlier rewards was monotone — more width better, more spacing better —
/// and that is the wrong shape of objective for the thing being bought. Realism is a *range*, not
/// an extreme: a side whose players stand as far apart as possible is no more a hockey team than
/// one filing down the middle, and maximising a proxy walks straight out of the range that made it
/// a good proxy. Measured consequence: the policy that maximised these terms ended up narrower
/// (4.2 m against §7's 6.5), deeper and more packed than the rules it replaced, while winning.
///
/// So the shape terms now penalise *deviation from §7* rather than rewarding extremes. §7 is the
/// reference because it was hand-tuned until it looked right and nothing better has shipped. Goals
/// stay a one-sided drive: resemble §7's shape, and beat it at the result.
///
/// `receivers` is left one-sided on purpose — offering a carrier more passing options is not a
/// thing to do in moderation, and §7's own §7.4 is the part of the spec the shape bench was written
/// to measure as *deficient*.
func fitness(_ s: Score, reference r: Score) -> Double {
    if s.victoryOnly { return s.goalsFor - s.goalsAgainst }

    /// Squared deviation in units of a tolerance, capped so one wayward term cannot drown the rest.
    func off(_ x: Double, _ target: Double, _ tolerance: Double) -> Double {
        let d = (x - target) / tolerance
        return Swift.min(d * d, 9.0)
    }

    let shape = off(s.possession, r.possession, 0.05)
        + off(s.spread, r.spread, 1.0)
        + off(s.width, r.width, 1.0)
        + off(s.pressure, r.pressure, 0.5)
        + off(s.attacking, r.attacking, 0.03)

    return 4.0 * (s.goalsFor - s.goalsAgainst)
        + 0.6 * Swift.max(s.receivers - r.receivers, 0)
        - 0.15 * shape
}

let clubs = Club.allCases

func setup(_ n: Int, periodSeconds: Double) -> MatchSetup {
    let home = clubs[(n * 3) % clubs.count]
    var away = clubs[(n * 3 + 1 + n / clubs.count) % clubs.count]
    if away == home { away = clubs[(clubs.firstIndex(of: home)! + 1) % clubs.count] }
    return MatchSetup(seed: 0x5EED_0000 &+ UInt64(n), sport: .field,
                      home: .club(home), away: .club(away), periodSeconds: periodSeconds,
                      orbitPeriod: Tuning.Orbit.demoPeriod, cup: false, control: .automatic)
}

func length(_ x: Double, _ z: Double) -> Double { (x * x + z * z).squareRoot() }

/// Plays one match with `net` driving team 0 (or nothing driving it, for the baseline) and §7's
/// written rules driving team 1, and scores team 0.
func play(_ net: PolicyNet?, seed n: Int, cfg: Config, opponent: PolicyNet? = nil) -> Score {
    var m = Match(setup(n, periodSeconds: cfg.periodSeconds))
    m.installPolicies([net, opponent])

    var s = Score()
    s.victoryOnly = cfg.victoryOnly
    var playTicks = 0, ownTicks = 0
    var carryTicks = 0, finalTicks = 0
    var receiverTotal = 0.0
    var receiverFinalTotal = 0.0
    var territoryTotal = 0.0
    var spreadTotal = 0.0
    var spreadSamples = 0
    var pressureTotal = 0.0
    var widthTotal = 0.0

    let goalZ = Tuning.Pitch.goalLineZ
    // A match of three periods runs ~18.6k ticks at a 40 s period. A policy that cannot get the
    // ball out of a dead state stretches that toward the safety cap instead — and a 200k cap means
    // the *worst* candidates cost ten times the most promising ones, which is a sink precisely when
    // the search is at its weakest. Three times the expected length is generous; anything reaching
    // it is pathological and scores badly on its own merits.
    let maxTicks = Int(cfg.periodSeconds * 120.0 * 9.0)
    let stride = cfg.sampleStride > 0 ? cfg.sampleStride : 1
    var sinceSample = 0
    while m.result == nil && m.ticks < maxTicks {
        m.tick()
        sinceSample += 1
        guard sinceSample >= stride else { continue }
        sinceSample = 0
        let snap = m.snapshot
        guard snap.state == .play else { continue }
        playTicks += 1

        // Mean distance to the nearest team-mate: the spread term, sampled every tick.
        let mine = snap.players.indices.filter { snap.players[$0].team == 0 && snap.players[$0].role != .goalie }
        for i in mine {
            var nearest = Double.greatestFiniteMagnitude
            for j in mine where j != i {
                let d = length(snap.players[i].x - snap.players[j].x, snap.players[i].z - snap.players[j].z)
                if d < nearest { nearest = d }
            }
            if nearest < .greatestFiniteMagnitude {
                spreadTotal += nearest > 12 ? 12 : nearest   // capped: standing apart is not a tactic
                spreadSamples += 1
            }
        }

        // Width: the standard deviation of outfield x.
        //
        // Added because the objectives were finally measured directly rather than by proxy, and the
        // policy was using half the pitch: 3.3 m of x-spread against §7's 6.5 m, a side filing down
        // the middle. Nothing in the reward had ever mentioned the width — `spread` is the distance
        // to the nearest team-mate, which a single file satisfies perfectly. The lesson is the one
        // the whole night taught: a proxy only constrains what it actually names.
        //
        // The other measures from `Analyse` are deliberately NOT trained on, so they stay honest
        // checks: swarm, role churn and whether the deepest defender is goal-side.
        if !mine.isEmpty {
            let meanX = mine.reduce(0.0) { $0 + snap.players[$1].x } / Double(mine.count)
            var variance = 0.0
            for i in mine {
                let d = snap.players[i].x - meanX
                variance += d * d
            }
            widthTotal += (variance / Double(mine.count)).squareRoot()
        }

        // How far the ball is from this side's nearest outfielder: the dense term.
        var toBall = 20.0
        for i in mine {
            let d = length(snap.players[i].x - snap.ball.x, snap.players[i].z - snap.ball.z)
            if d < toBall { toBall = d }
        }
        pressureTotal += toBall

        guard let c = snap.ball.carrier else { continue }
        guard snap.players[c].team == 0 else { continue }
        ownTicks += 1

        carryTicks += 1
        territoryTotal += snap.players[c].z / goalZ
        // Inside 20 of the goal being attacked is the window `MeasureMatches`' shape bench samples;
        // it is reported, not trained on.
        let inFinalThird = length(snap.players[c].x, snap.players[c].z - goalZ) < 20
        if inFinalThird { finalTicks += 1 }
        var offered = 0
        for i in mine where i != c {
            let p = snap.players[i]
            let d = length(p.x - snap.players[c].x, p.z - snap.players[c].z)
            guard d > 3, d < 26 else { continue }
            guard p.z > snap.players[c].z - 2 else { continue }   // up the pitch, roughly
            // An unblocked lane: nobody on the other side within 1.4 of the segment.
            var blocked = false
            for j in snap.players.indices where snap.players[j].team == 1 {
                let o = snap.players[j]
                let abx = p.x - snap.players[c].x, abz = p.z - snap.players[c].z
                let l2 = abx * abx + abz * abz
                var t = 0.0
                if l2 > 0 {
                    t = ((o.x - snap.players[c].x) * abx + (o.z - snap.players[c].z) * abz) / l2
                    t = t < 0 ? 0 : (t > 1 ? 1 : t)
                }
                if length(o.x - (snap.players[c].x + abx * t), o.z - (snap.players[c].z + abz * t)) < 1.4 {
                    blocked = true
                    break
                }
            }
            if !blocked { offered += 1 }
        }
        receiverTotal += Double(offered)
        if inFinalThird { receiverFinalTotal += Double(offered) }
    }

    s.goalsFor = Double(m.score[0])
    s.goalsAgainst = Double(m.score[1])
    s.possession = playTicks > 0 ? Double(ownTicks) / Double(playTicks) : 0
    s.receivers = carryTicks > 0 ? receiverTotal / Double(carryTicks) : 0
    s.receiversFinal = finalTicks > 0 ? receiverFinalTotal / Double(finalTicks) : 0
    s.territory = carryTicks > 0 ? territoryTotal / Double(carryTicks) : 0
    s.attacking = playTicks > 0 ? Double(finalTicks) / Double(playTicks) : 0
    s.spread = spreadSamples > 0 ? spreadTotal / Double(spreadSamples) : 0
    s.pressure = playTicks > 0 ? pressureTotal / Double(playTicks) : 0
    s.width = playTicks > 0 ? widthTotal / Double(playTicks) : 0
    return s
}

/// Scores a candidate over `cfg.matches` seeded matches against a pool of opponents.
///
/// The pool, not just the current centre. Self-play against one's immediate self is how a policy
/// forgets: both sides drift together, the matches get easier in step, and competence that nothing
/// is currently testing quietly rots. Mixing in §7's rules and *older* checkpoints keeps a side
/// honest about the things it used to be able to do — the small-scale version of AlphaStar's
/// league, and the reason a share of matches always stays against the fixed rules.
func evaluate(_ net: PolicyNet?, cfg: Config, offset: Int = 0, pool: [PolicyNet] = []) -> Score {
    let selfPlayCount = pool.isEmpty ? 0 : Int((Double(cfg.matches) * cfg.selfPlay).rounded())
    return Score.mean((0..<cfg.matches).map { k in
        play(net, seed: offset + k, cfg: cfg,
             opponent: k < selfPlayCount ? pool[k % pool.count] : nil)
    })
}

// MARK: - Noise

/// Gaussian draws from a seeded SplitMix64, so a run is repeatable on this machine. This is a tool,
/// not the simulation — §4.4's arithmetic contract binds `DetPolicy`, not the search that finds it.
struct Gauss {
    var state: UInt64
    init(seed: UInt64) { state = seed }

    mutating func next() -> UInt64 {
        state = state &+ 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
    mutating func uniform() -> Double { Double(next() >> 11) * 0x1p-53 }

    /// Box–Muller.
    mutating func normal() -> Double {
        let u1 = Swift.max(uniform(), 1e-12)
        let u2 = uniform()
        return (-2.0 * Foundation.log(u1)).squareRoot() * Foundation.cos(2.0 * Double.pi * u2)
    }

    mutating func vector(_ n: Int) -> [Double] { (0..<n).map { _ in normal() } }
}

/// Centred ranks in [−0.5, 0.5]: ES cares about the order of the population, not the spread of its
/// scores, which keeps one freak match from dominating an update.
func centredRanks(_ xs: [Double]) -> [Double] {
    let order = xs.indices.sorted { xs[$0] < xs[$1] }
    var r = [Double](repeating: 0, count: xs.count)
    for (rank, i) in order.enumerated() {
        r[i] = Double(rank) / Double(xs.count - 1) - 0.5
    }
    return r
}

// MARK: - Parallel map

/// `concurrentPerform` writing disjoint slots. Unchecked because the compiler cannot see that the
/// indices never overlap; they are `0..<n`, one per iteration.
final class Slots: @unchecked Sendable {
    var values: [Score]
    init(_ n: Int) { values = [Score](repeating: Score(), count: n) }
}

func parallelScores(_ n: Int, _ body: @escaping @Sendable (Int) -> Score) -> [Score] {
    let slots = Slots(n)
    DispatchQueue.concurrentPerform(iterations: n) { k in
        let v = body(k)
        slots.values[k] = v
    }
    return slots.values
}

// MARK: - The run

// An immutable copy, so the functions and closures below are not reaching into a main-actor
// isolated global (Swift 6). Nothing mutates the configuration after the arguments are parsed.
nonisolated(unsafe) let C: Config = cfg

let nIn = PolicyInputs.count
let nOut = PolicyInputs.outputCount
let dim = PolicyNet.parameterCount(nIn: nIn, nHidden: C.hidden, nOut: nOut)

func net(_ theta: [Double]) -> PolicyNet {
    PolicyNet(nIn: nIn, nHidden: C.hidden, nOut: nOut, parameters: theta)
}

var gauss = Gauss(seed: cfg.seed)
// Small random start: the output layer near zero so the first targets sit near the pitch centre
// rather than pinned to a corner.
var theta: [Double]
if let path = C.initFrom {
    theta = readCheckpoint(path)
    precondition(theta.count == dim, "--init: \(path) holds \(theta.count) parameters, this shape wants \(dim)")
    print("starting from \(path)")
} else {
    theta = (0..<dim).map { _ in gauss.normal() * 0.1 }
    for k in (dim - nOut * cfg.hidden - nOut)..<dim { theta[k] *= 0.01 }
}

print("reward: " + (C.victoryOnly ? "victory alone (goal difference)" : "shaped"))
print("""
TrainTeamAI — \(dim) parameters (\(nIn) → \(cfg.hidden) → \(cfg.hidden) → \(nOut)), \
population \(cfg.population), \(cfg.matches) matches each, 3 × \(Int(cfg.periodSeconds)) s
""")

let outDir = C.out
do {
    try FileManager.default.createDirectory(atPath: outDir, withIntermediateDirectories: true)
} catch {
    FileHandle.standardError.write("TrainTeamAI: cannot create \(outDir): \(error)\n".data(using: .utf8)!)
    exit(1)
}

/// Writes or dies. A `try?` here cost a bootstrap run: every checkpoint failed because the output
/// directory did not exist, and the run still printed "wrote …" and exited 0.
func write(_ text: String, to path: String) {
    do {
        try text.write(toFile: path, atomically: true, encoding: .utf8)
    } catch {
        FileHandle.standardError.write("TrainTeamAI: cannot write \(path): \(error)\n".data(using: .utf8)!)
        exit(1)
    }
}

func writeCheckpoint(_ theta: [Double], _ name: String) {
    var s = "# TrainTeamAI checkpoint — \(nIn) \(C.hidden) \(C.hidden) \(nOut), \(theta.count) parameters\n"
    s += "# Every parameter as the hex of its IEEE-754 bits, in PolicyNet.parameters order.\n"
    for v in theta { s += String(format: "%016llX\n", v.bitPattern) }
    write(s, to: "\(outDir)/\(name).txt")
}

/// Reads a checkpoint written by `writeCheckpoint`: comment lines, then one hex double per line.
func readCheckpoint(_ path: String) -> [Double] {
    guard let text = try? String(contentsOfFile: path, encoding: .utf8) else {
        FileHandle.standardError.write("TrainTeamAI: cannot read \(path)\n".data(using: .utf8)!)
        exit(1)
    }
    return text.split(separator: "\n").compactMap { line -> Double? in
        let t = line.trimmingCharacters(in: .whitespaces)
        guard !t.hasPrefix("#"), let bits = UInt64(t, radix: 16) else { return nil }
        return Double(bitPattern: bits)
    }
}

/// Writes one seeded match twice — once with `theta` on team 0, once with §7's rules on both
/// sides — as a single scrubable page. Same seed, so the two pitches start identically and every
/// difference after that is the policy rather than the draw.
func writeReplay(_ theta: [Double], to file: String, seed: Int) {
    let loaded = PolicyNet(nIn: nIn, nHidden: C.hidden, nOut: nOut, parameters: theta)
    let s = setup(seed, periodSeconds: C.periodSeconds)
    let tapes = [Replay.record([loaded, nil], setup: s, label: "learned v §7"),
                 Replay.record([nil, nil], setup: s, label: "§7 v §7")]
    let name = (file as NSString).lastPathComponent
    write(Replay.html(title: name, tapes: tapes,
                      halfWidth: Tuning.Pitch.halfWidth, halfLength: Tuning.Pitch.halfLength),
          to: file)
}

if let path = C.evaluateOnly ?? C.replay {
    let theta = readCheckpoint(path)
    guard theta.count == dim else {
        FileHandle.standardError.write("TrainTeamAI: \(path) holds \(theta.count) parameters, this shape wants \(dim)\n".data(using: .utf8)!)
        exit(1)
    }
    if C.replay != nil {
        let file = path + String(format: "-seed%d.html", C.replaySeed)
        writeReplay(theta, to: file, seed: C.replaySeed)
        print("replay written: \(file)")
    } else {
        let learned = evaluate(PolicyNet(nIn: nIn, nHidden: C.hidden, nOut: nOut, parameters: theta),
                               cfg: C, offset: C.evalOffset)
        let rules = evaluate(nil, cfg: C, offset: C.evalOffset)
        print("seeds \(C.evalOffset)..<\(C.evalOffset + C.matches)"
              + (C.evalOffset == 0 ? "  (WARNING: the search selects on these)" : "  (unseen by the search)"))
        print("                goals      poss   recv  final  spread  press   terr    att")
        for (label, m) in [("learned", learned), ("§7 rules", rules)] {
            let a = String(format: "%.2f-%.2f", m.goalsFor, m.goalsAgainst)
            let b = String(format: "%.3f  %.2f  %.2f   %5.1f  %5.1f  %+.2f  %.3f",
                           m.possession, m.receivers, m.receiversFinal, m.spread,
                           m.pressure, m.territory, m.attacking)
            print(label.padding(toLength: 10, withPad: " ", startingAt: 0) + "  " + a + "   " + b)
        }
    }
    exit(0)
}

if let path = C.analyse {
    let theta = readCheckpoint(path)
    guard theta.count == dim else {
        FileHandle.standardError.write("TrainTeamAI: \(path) holds \(theta.count) parameters, this shape wants \(dim)\n".data(using: .utf8)!)
        exit(1)
    }
    let learned = PolicyNet(nIn: nIn, nHidden: C.hidden, nOut: nOut, parameters: theta)
    print("analysing \(C.matches) seeded matches each way...")
    print("")
    let a = Analyse.Report.mean((0..<C.matches).map {
        Analyse.match([learned, nil], setup: setup(C.evalOffset + $0, periodSeconds: C.periodSeconds))
    })
    let b = Analyse.Report.mean((0..<C.matches).map {
        Analyse.match([nil, nil], setup: setup(C.evalOffset + $0, periodSeconds: C.periodSeconds))
    })
    print(Analyse.table([("learned", a), ("\u{00A7}7 rules", b)]))
    print("  swarm      mean distance from the ball to EVERY outfielder. Higher is less of a pack.")
    print("  churn/min  how often the nearest pair to the ball changes. Lower is more legible.")
    print("  depth      how far the deepest defender sits behind the ball. Positive is goal-side.")
    print("  goal-side  share of play with that defender actually goal-side of the ball.")
    print("  width      standard deviation of outfield x. Higher uses the pitch.")
    print("  spacing    distance to the nearest team-mate.")
    exit(0)
}

if C.diagnose {
    // **Is §7's target a function of the observation?**
    //
    // Squared-error regression can only ever return one answer per input, and the answer it
    // returns is the *mean* of the answers it saw. That is fine when similar states call for
    // similar targets. It is a disaster when they do not: if half the time a state means "chase
    // the ball" and half the time it means "hold your slot", the fitted net steers to the midpoint
    // of the two, which is neither, and no amount of capacity or data fixes it.
    //
    // So: take probe samples, find each one's nearest neighbours *in observation space*, and
    // measure how far apart their targets are. Compare that local spread against the spread of
    // targets across the whole corpus. If the local spread is a small fraction of the global one,
    // the mapping is well-behaved and regression is the right tool. If it approaches the global
    // spread, the targets are multimodal and the architecture is wrong, not the training.
    //
    // Reported in metres, by converting the pre-squash labels back through the action decode.
    print("harvesting §7's decisions from \(C.teachMatches) matches…")
    var samples: [TeachingSample] = []
    for k in 0..<C.teachMatches {
        var m = Match(setup(k, periodSeconds: C.periodSeconds))
        m.teach()
        let maxTicks = Int(C.periodSeconds * 120.0 * 9.0)
        while m.result == nil && m.ticks < maxTicks { m.tick() }
        samples += m.teaching
    }
    print("  \(samples.count) samples")

    /// A label as a point on the pitch, in metres, in the attacking frame.
    func point(_ label: [Double]) -> (Double, Double) {
        (DetPolicy.squash(label[0]) * PolicyInputs.actionXScale,
         DetPolicy.squash(label[1]) * PolicyInputs.actionZScale)
    }
    func gap(_ a: [Double], _ b: [Double]) -> Double {
        let (ax, az) = point(a), (bx, bz) = point(b)
        return ((ax - bx) * (ax - bx) + (az - bz) * (az - bz)).squareRoot()
    }

    var g = Gauss(seed: 99)
    let probes = 150
    let neighbours = 12

    // Global spread: the mean distance between two targets picked at random.
    var globalTotal = 0.0
    for _ in 0..<5000 {
        let a = samples[Int(g.uniform() * Double(samples.count))]
        let b = samples[Int(g.uniform() * Double(samples.count))]
        globalTotal += gap(a.label, b.label)
    }
    let global = globalTotal / 5000.0

    var localTotal = 0.0
    var obsTotal = 0.0
    for _ in 0..<probes {
        let probe = samples[Int(g.uniform() * Double(samples.count))]
        // The `neighbours` closest observations, by Euclidean distance over the whole vector.
        var best: [(d: Double, k: Int)] = []
        for (k, other) in samples.enumerated() {
            var d = 0.0
            for i in 0..<nIn {
                let e = probe.observation[i] - other.observation[i]
                d += e * e
            }
            if d <= 0 { continue }
            if best.count < neighbours {
                best.append((d, k))
                best.sort { $0.d < $1.d }
            } else if d < best[neighbours - 1].d {
                best[neighbours - 1] = (d, k)
                best.sort { $0.d < $1.d }
            }
        }
        obsTotal += best.map { $0.d.squareRoot() }.reduce(0, +) / Double(best.count)
        // How far apart are the targets of these near-identical states?
        var pairs = 0.0, total = 0.0
        for a in 0..<best.count {
            for b in (a + 1)..<best.count {
                total += gap(samples[best[a].k].label, samples[best[b].k].label)
                pairs += 1
            }
        }
        if pairs > 0 { localTotal += total / pairs }
    }
    let local = localTotal / Double(probes)

    print("")
    print(String(format: "  mean observation distance to the %d nearest neighbours : %.4f", neighbours, obsTotal / Double(probes)))
    print(String(format: "  mean distance between two targets, picked at random    : %6.2f m", global))
    print(String(format: "  mean distance between targets of NEAR-IDENTICAL states : %6.2f m", local))
    print(String(format: "  local spread as a share of global                      : %5.1f %%", 100 * local / global))
    print("")
    if local > 0.5 * global {
        print("  → Multimodal. Near-identical states call for targets almost as far apart as")
        print("    random pairs, so there is no single right answer to regress toward and the mean")
        print("    of the answers is not one of them. A bigger net cannot fix this; a different")
        print("    action head can — classify over candidate targets instead of regressing a point.")
    } else {
        print("  → Well-behaved. Similar states call for similar targets, so regression is the right")
        print("    tool and the gap to §7 is a matter of fit or of training, not of architecture.")
    }
    exit(0)
}

if C.bootstrap {
    // Harvest. Both teams are driven by §7's rules and both teach: the observation is written in
    // the thinking player's own attacking frame, so a sample from team 1 is as good as one from
    // team 0 and costs nothing extra.
    print("harvesting §7's decisions from \(C.teachMatches) matches…")
    var samples: [TeachingSample] = []
    for k in 0..<C.teachMatches {
        var m = Match(setup(k, periodSeconds: C.periodSeconds))
        m.teach()
        let maxTicks = Int(C.periodSeconds * 120.0 * 9.0)
        while m.result == nil && m.ticks < maxTicks { m.tick() }
        samples += m.teaching
    }
    // Memory discipline: this machine has 16 GB and is shared. 100 doubles a sample is 800 bytes,
    // so a cap of 200k samples is ~160 MB and no more.
    let cap = 200_000
    if samples.count > cap {
        var g = Gauss(seed: 7)
        for i in stride(from: samples.count - 1, to: 0, by: -1) {
            let j = Int(g.uniform() * Double(i + 1))
            samples.swapAt(i, j)
        }
        samples = Array(samples.prefix(cap))
    }
    var lo = 0.0, hi = 0.0, mag = 0.0
    for s in samples { for l in s.label { lo = Swift.min(lo, l); hi = Swift.max(hi, l); mag += l.magnitude } }
    print(String(format: "  %d samples · label range %.2f…%.2f, mean |label| %.3f",
                 samples.count, lo, hi, mag / Double(Swift.max(samples.count * nOut, 1))))

    var bp = Backprop(nIn: nIn, nH: C.hidden, nOut: nOut, seed: C.seed)
    var g = Gauss(seed: C.seed &+ 1)

    func fit(_ epochs: Int, label: String) {
        for epoch in 1...epochs {
            for i in stride(from: samples.count - 1, to: 0, by: -1) {
                let j = Int(g.uniform() * Double(i + 1))
                samples.swapAt(i, j)
            }
            var total = 0.0, batches = 0
            var start = 0
            while start < samples.count {
                let end = Swift.min(start + C.bootstrapBatch, samples.count)
                total += bp.step(samples[start..<end],
                             dropTail: PolicyInputs.memoryCount,
                             dropProbability: C.memoryDropout,
                             rng: &g)
                batches += 1
                start = end
            }
            if epoch == epochs {
                let fitted = PolicyNet(nIn: nIn, nHidden: C.hidden, nOut: nOut, parameters: bp.parameters)
                let m = evaluate(fitted, cfg: C)
                let a = String(format: "%.2f-%.2f", m.goalsFor, m.goalsAgainst)
                print(String(format: "  %@  %6d samples  loss %.4f   goals %@  poss %.3f  recv %.2f  spread %4.1f  press %4.1f",
                             label.padding(toLength: 9, withPad: " ", startingAt: 0),
                             samples.count, total / Double(batches), a,
                             m.possession, m.receivers, m.spread, m.pressure))
            }
            writeCheckpoint(bp.parameters, "bootstrap")
        }
    }

    fit(C.bootstrapEpochs, label: "clone")

    // DAgger. Each round plays matches with the *policy* in charge and records what §7 would have
    // advised at the states the policy actually reached, which is where a plain clone is blind.
    for round in 1...Swift.max(C.daggerRounds, 0) where C.daggerRounds > 0 {
        let current = PolicyNet(nIn: nIn, nHidden: C.hidden, nOut: nOut, parameters: bp.parameters)
        var fresh: [TeachingSample] = []
        for k in 0..<C.daggerMatches {
            var m = Match(setup(1000 * round + k, periodSeconds: C.periodSeconds))
            m.installPolicies([current, nil])
            m.teach()
            let maxTicks = Int(C.periodSeconds * 120.0 * 9.0)
            while m.result == nil && m.ticks < maxTicks { m.tick() }
            fresh += m.teaching
        }
        samples += fresh
        if samples.count > cap {
            for i in stride(from: samples.count - 1, to: 0, by: -1) {
                let j = Int(g.uniform() * Double(i + 1))
                samples.swapAt(i, j)
            }
            samples = Array(samples.prefix(cap))
        }
        fit(Swift.max(C.bootstrapEpochs / 2, 1), label: "dagger \(round)")
    }
    let rules = evaluate(nil, cfg: C)
    let a = String(format: "%.2f-%.2f", rules.goalsFor, rules.goalsAgainst)
    print(String(format: "  §7 rules  (target)        goals %@  poss %.3f  recv %.2f  spread %4.1f  press %4.1f",
                 a, rules.possession, rules.receivers, rules.spread, rules.pressure))
    writeReplay(bp.parameters, to: outDir + "/bootstrap.html", seed: C.replaySeed)
    print("wrote \(outDir)/bootstrap.txt and bootstrap.html")
    exit(0)
}

var baselineCfg = cfg
baselineCfg.matches = cfg.centreMatches
let baseline = evaluate(nil, cfg: baselineCfg)
let baseGoals: String = String(format: "%.2f–%.2f", baseline.goalsFor, baseline.goalsAgainst)
let baseRest: String = String(format: "poss %.2f  recv %.2f (final %.2f)  spread %.1f m  press %.1f m  terr %+.2f  att %.3f  fitness %.3f",
                              baseline.possession, baseline.receivers, baseline.receiversFinal,
                              baseline.spread, baseline.pressure, baseline.territory,
                              baseline.attacking, fitness(baseline, reference: baseline))
print("baseline  §7's written rules vs itself   goals " + baseGoals + "  " + baseRest)
print("")
print(" iter    goals     poss   recv  final  spread  press   terr    att    fitness    best      secs")



var best = -Double.greatestFiniteMagnitude
var bestTheta = theta
var stale = 0
var sigma = C.sigma
/// Past selves the candidates also have to beat. Capped: a handful of rungs is enough to stop the
/// forgetting, and every extra one costs matches.
var opponentPool: [PolicyNet] = []
let poolLimit = 4
let pairs = cfg.population / 2

for iteration in 1...cfg.iterations {
    let started = Date()
    let epsilons = (0..<pairs).map { _ in gauss.vector(dim) }

    // Antithetic: every perturbation is played in both directions, which cancels the noise that
    // would otherwise look like signal.
    let candidates: [[Double]] = epsilons.flatMap { eps -> [[Double]] in
        [zip(theta, eps).map { $0 + sigma * $1 },
         zip(theta, eps).map { $0 - sigma * $1 }]
    }

    let localCfg = cfg
    let frozenPool = opponentPool
    let scores = parallelScores(candidates.count) { k in
        evaluate(net(candidates[k]), cfg: localCfg, offset: iteration * 97, pool: frozenPool)
    }
    let fitnesses = scores.map { fitness($0, reference: baseline) }
    let ranks = centredRanks(fitnesses)

    // θ ← θ + α · (1 / (n σ)) · Σ rank_k · ε_k, antithetic pairs differenced.
    var gradient = [Double](repeating: 0, count: dim)
    for p in 0..<pairs {
        let weight = ranks[2 * p] - ranks[2 * p + 1]
        let eps = epsilons[p]
        for d in 0..<dim { gradient[d] += weight * eps[d] }
    }
    // Normalise the gradient to unit RMS before stepping, so `learningRate` *is* the per-weight
    // step and means the same thing at any population or sigma. The textbook α/(nσ) scaling does
    // not: at population 48 and σ 0.02 it worked out to ~18 % of a weight's magnitude per
    // iteration, which is a stride, not a step — one update took the centre's fitness from 3.56 to
    // 1.80. Weights here are O(0.15), so a learning rate of 0.002 moves about 1 % at a time.
    var rms = 0.0
    for d in 0..<dim { rms += gradient[d] * gradient[d] }
    rms = (rms / Double(dim)).squareRoot()
    let scale = rms > 1e-12 ? cfg.learningRate / rms : 0.0
    for d in 0..<dim {
        theta[d] = theta[d] + scale * gradient[d] - cfg.learningRate * cfg.decay * theta[d]
    }

    let mean = Score.mean(scores)
    // The centre is always scored against §7's rules on fixed seeds, never against the pool, so
    // this column means the same thing at iteration 10 and iteration 10,000. A self-play score is
    // not comparable over time — the opponent moved.
    var centreCfg = cfg
    centreCfg.matches = cfg.centreMatches
    let centre = evaluate(net(theta), cfg: centreCfg)
    if fitness(centre, reference: baseline) > best {
        best = fitness(centre, reference: baseline)
        bestTheta = theta
        stale = 0
        writeCheckpoint(theta, "best")
        if opponentPool.count >= poolLimit { opponentPool.removeFirst() }
        opponentPool.append(net(theta))
    } else {
        stale += 1
        if stale >= C.patience {
            // Drifting. Go back to what demonstrably worked and search more finely around it —
            // but never below a floor. Annealing without one is how the safety net becomes the
            // cage: three pull-backs took sigma from 0.02 to 0.0069 and the search spent two
            // hundred iterations exploring a ball a third of its original size, unable to beat a
            // checkpoint it could no longer reach away from.
            theta = bestTheta
            sigma = Swift.max(sigma * 0.7, C.sigmaFloor)
            stale = 0
            print(String(format: "  ↩ pulled back to best (%.3f); sigma now %.4f", best, sigma))
        }
    }
    writeCheckpoint(theta, String(format: "iter-%04d", iteration))
    if C.replayEvery > 0 && iteration % C.replayEvery == 0 {
        writeReplay(theta, to: String(format: "%@/replay-%04d.html", outDir, iteration), seed: C.replaySeed)
    }

    let secs: Double = Date().timeIntervalSince(started)
    let goals: String = String(format: "%.2f–%.2f", centre.goalsFor, centre.goalsAgainst)
    let rest: String = String(format: "%.3f  %.2f  %.2f   %5.1f  %5.1f  %+.2f  %.3f   %7.3f  %7.3f   %5.1f",
                              centre.possession, centre.receivers, centre.receiversFinal,
                              centre.spread, centre.pressure, centre.territory, centre.attacking,
                              fitness(centre, reference: baseline), best, secs)
    print(String(format: "%5d  ", iteration) + goals + "   " + rest)
    _ = mean
}

print("")
print(String(format: "done — best fitness %.3f, baseline %.3f. Checkpoints in %@",
             best, fitness(baseline, reference: baseline), outDir))
