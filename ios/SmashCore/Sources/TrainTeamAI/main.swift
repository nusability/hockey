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
    /// `--versus <checkpoint>` puts another policy on team 1 instead of §7, for a head-to-head.
    var versus: String?
    /// How dearly shape deviation is charged, against goals at weight 4.0. Each of the six shape
    /// terms is capped at 9, so this times 54 is the most the shape can ever cost — at 0.15 that
    /// ceiling is 8.1, under which a single goal (4.0) buys a lot of deviation. A high-capacity net
    /// finds more ways to trade shape for goals than a small one, and at 0.15 the 128-unit run gave
    /// away the clone's spread (7.3 → 5.5 m) inside forty iterations.
    var shapeWeight = 0.15
    // MARK: PPO (`--ppo`)
    //
    // A trainer that assigns credit through time, where everything above scores a whole match and
    // keeps what won. The defaults are the field's usual ones rather than anything tuned here;
    // nothing in this project has run them yet.
    var ppo = false
    var ppoMatches = 16          // matches collected per iteration, played in parallel
    var ppoEpochs = 4            // passes over the collected batch
    var ppoBatch = 512
    var ppoClip = 0.2            // how far the policy may move in one update
    var ppoGamma = 0.995         // a match is ~18k ticks, so credit has to reach a long way back
    var ppoLambda = 0.95
    var ppoLearningRate = 3e-4
    var ppoSigma = 0.3           // how widely it explores around its own output, in output units
    var ppoSigmaDecay = 0.999
    var ppoSigmaFloor = 0.05
    /// A goal is the objective. A steal is the only nudge, and small: the owner's point was that
    /// chasing must never outrank winning, and 0.05 against 1.0 is that in the raw reward rather
    /// than in a per-match aggregate.
    var ppoGoalReward = 1.0
    var ppoStealReward = 0.05
    /// `--gradcheck` checks the backward pass against finite differences and exits. The one piece
    /// of a policy-gradient trainer that fails silently, so it is checked before anything is run.
    var gradCheck = false
    /// `--pure` is self-play and nothing else: no §7, no scripted sparring, only the league of
    /// past selves. What the owner asked for - learn the game by playing itself.
    ///
    /// The thing it has to survive is the cosy equilibrium, which this trainer has already produced
    /// twice: both sides stop contesting, the ball sits loose nine-tenths of the match, and neither
    /// is punished because the opponent is equally idle. The published answer is a *league* - play a
    /// population of past selves rather than your immediate self - so `--pool` matters more here
    /// than anywhere else.
    var pureSelfPlay = false
    /// How many past selves the league keeps. Four is barely a league; AlphaStar's point was that
    /// naive self-play collapses and a population does not.
    var poolLimit = 4
    /// `--turnover-weight` is the **most** the turnover term can ever contribute, reached when the
    /// side wins the ball as often as `turnoverTarget`. Against a win's 3.0 this is what keeps
    /// chasing below winning by construction. 0 restores the reward as it was before 2026-10-18.
    var turnoverWeight = 0.9
    /// `--turnover-target`: steals a match at which the term saturates. §7's measured rate on 24
    /// unseen seeds, which is a reference and not a law - see the term in `fitness`.
    var turnoverTarget = 2.2
    /// Start with both nets open, and close them once the policy can finish. See `Match.openNets`.
    var openNets = false
    /// `--ease-collect` forgives §6.3.1 while the policy learns to gather a ball at all, then
    /// tightens the rule a notch at a time until it is the shipped rule. See `Match.collectEase`.
    ///
    /// The rule took away the free possession a search starting from noise used to bootstrap on,
    /// and without it goal difference is flat: measured, 91.6 % of a self-play match with the ball
    /// loose and a best fitness that did not move in 56 iterations. The last notch is **0**, so
    /// nothing is ever believed about a policy that has not been judged under the real rule.
    var easeCollect = false
    /// The notches, in order. Only ever climbed — a curriculum that loosens again teaches the
    /// policy to straddle both worlds, which is why the nets stay shut once shut.
    var easeLadder: [Double] = [1.0, 0.8, 0.6, 0.4, 0.2, 0.0]
    var easeStep = 0
    /// Running costs something. See `Match.stamina`.
    var stamina = false
    /// Goals a match, measured on the centre, at which the keepers come back. Once closed they
    /// stay closed — a curriculum that oscillates teaches the policy to straddle both worlds.
    var closeNetsAt = 1.5
    /// How far from the goal play restarts, rung by rung, before the real game takes over.
    ///
    /// Six metres is a tap-in; the last link of the chain and the only one learnable on its own.
    /// Each rung is climbed when the side scores `closeNetsAt` a match, so it joins the chain
    /// backwards. The final rung is the real thing: ordinary face-offs, keepers on.
    /// Finish, then build, then win it back. The first four rungs hand over the ball and back
    /// away; the last three take it away again, because a ladder made only of `ours` teaches
    /// finishing and nothing else.
    var spawnLadder: [TrainingStart] = [
        .ours(6), .ours(14), .ours(24),
        .loose(18), .loose(30),
        .theirs(24),
    ]
    /// The goals a match each rung asks for before the next one.
    ///
    /// One bar for every rung is wrong: 2.5 a match from a ball handed to you six metres out is
    /// trivial, and from the opponent's possession it may be unreachable. The bar falls as the
    /// situation gets harder, so the ladder keeps moving instead of stalling on rung four.
    var rungBar: [Double] = [3.0, 2.5, 2.0, 1.5, 1.0, 0.8]
    /// Iterations on one rung before it is climbed regardless. A rung nobody can clear should not
    /// swallow a whole night — a forced promotion is logged, so a policy stranded above its ability
    /// is visible rather than silent.
    var rungPatience = 400
    var rung = 0
    /// Consecutive iterations above the threshold before a rung is climbed. One good iteration is
    /// luck — a random net scores 2.6 a match from six metres — and promoting on it strands the
    /// policy a rung above what it can actually do.
    var holdFor = 4
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
    case "--versus": cfg.versus = it.next()
    case "--shape-weight": cfg.shapeWeight = num()
    case "--ppo": cfg.ppo = true
    case "--ppo-matches": cfg.ppoMatches = Int(num())
    case "--ppo-epochs": cfg.ppoEpochs = Int(num())
    case "--ppo-batch": cfg.ppoBatch = Int(num())
    case "--ppo-clip": cfg.ppoClip = num()
    case "--ppo-gamma": cfg.ppoGamma = num()
    case "--ppo-lr": cfg.ppoLearningRate = num()
    case "--ppo-sigma": cfg.ppoSigma = num()
    case "--ppo-goal": cfg.ppoGoalReward = num()
    case "--ppo-steal": cfg.ppoStealReward = num()
    case "--gradcheck": cfg.gradCheck = true
    case "--pure": cfg.pureSelfPlay = true; cfg.selfPlay = 1.0
    case "--pool": cfg.poolLimit = Int(num())
    case "--turnover-weight": cfg.turnoverWeight = num()
    case "--turnover-target": cfg.turnoverTarget = num()
    case "--open-nets": cfg.openNets = true
    case "--ease-collect": cfg.easeCollect = true
    case "--stamina": cfg.stamina = true
    case "--seed": cfg.seed = UInt64(Swift.max(num(), 0))
    case "--close-nets-at": cfg.closeNetsAt = num()
    case "--no-ladder": cfg.spawnLadder = []
    case "--hold-for": cfg.holdFor = Int(num())
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
    var wins = 0.0            // 1 for a win, 0 otherwise — a league's currency, not goal difference
    var draws = 0.0
    var depth = 0.0           // how far the deepest defender sits behind the ball, in metres
    /// Steals won off an opponent carrier, per match (§6.4). **The chase, counted.**
    ///
    /// A steal is the engine's own name for taking the ball off a carrier - hold contact within
    /// reach of it for 0.18 s - so it is the act itself and not a proxy for it. Possession share
    /// was the obvious alternative and is the wrong one: holding the ball and never releasing it
    /// maximises possession, which is the policy this fitness already had to be rewritten to stop
    /// (see the draw being worth nothing, below). A steal cannot be earned by keep-ball.
    ///
    /// Loose-ball recoveries are deliberately *not* counted. The observation shows a player who
    /// has the ball and which opponent that is, but for a loose ball it shows only "loose" and
    /// never whose touch was last - so a reward for recovering *their* spilled ball pays for
    /// something the policy cannot see to aim at.
    var turnovers = 0.0
    /// Steals conceded, per match. Measured and reported, not trained on: a side that holds the
    /// ball more is stolen from more, so charging for it would quietly charge for possession.
    var turnoversLost = 0.0

    /// Set from the run's configuration; it selects which reward `fitness(_:reference:)` returns.
    var victoryOnly = false
    /// Steals a match at which the turnover term saturates, from the run's configuration.
    var turnoverTarget = 0.0

    static func mean(_ xs: [Score]) -> Score {
        guard !xs.isEmpty else { return Score() }
        let n = Double(xs.count)
        var m = Score()
        m.victoryOnly = xs[0].victoryOnly
        m.turnoverTarget = xs[0].turnoverTarget
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
        m.wins = xs.reduce(0) { $0 + $1.wins } / n
        m.draws = xs.reduce(0) { $0 + $1.draws } / n
        m.depth = xs.reduce(0) { $0 + $1.depth } / n
        m.turnovers = xs.reduce(0) { $0 + $1.turnovers } / n
        m.turnoversLost = xs.reduce(0) { $0 + $1.turnoversLost } / n
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
func fitness(_ s: Score, reference r: Score, shapeWeight: Double = 0.15,
             turnoverWeight: Double = 0.9) -> Double {
    /// Ball-winning, saturating at `turnoverTarget` - see the long note in the victory-only branch.
    /// Both rewards get it: it is the one thing neither of them otherwise asks for. The shaped
    /// reward's six terms all *match §7* (possession, spacing, width, press, attacking third,
    /// depth), and matching §7's press asks a player to stand near the ball without ever asking
    /// anyone to take it - which is precisely the 0.4-against-2.2 gap the measurement found.
    let steals = s.turnoverTarget > 0 ? Swift.min(s.turnovers / s.turnoverTarget, 1.0) : 0.0
    if s.victoryOnly {
        // **League points, not goal difference** — plus one reflex the search cannot discover.
        //
        // Points, because a league pays 3 for a win and 1 for a draw, and that is most of why no
        // real side parks the bus for ninety minutes: a draw is nearly worthless. Goal difference
        // pays the opposite way. Conceding 0.17 while scoring 0.60 is an excellent return, and the
        // search found exactly that — a side that defends its own goal with everybody, which is
        // effective and miserable to play against. Goal difference stays as a small tiebreak,
        // because three coarse outcomes per match leave the search little to climb between.
        //
        // The reflex is the distance from the ball to this side's **nearest** player. Nearest, not
        // average: paying every player to approach the ball buys the huddle §7.2 warns about, while
        // paying only for the nearest asks exactly one player to go. Where the other nine stand is
        // left entirely open, which is the part meant to emerge. It is here because victory alone
        // never found it — 1,000 iterations of self-play produced a side whose nearest player sat
        // 13.5 m from the ball against §7's 3.7, because when neither side of a self-play pair
        // contests, neither is punished.
        // A draw is worth **nothing**, where a league pays 1. Deliberate: holding the ball and
        // never releasing it banks a guaranteed 0–0, and at 1 point a draw that is the safest
        // policy on the board — do nothing, risk nothing, collect. The net duly learned exactly
        // that and never discovered how to shoot. With draws worthless the only way to score
        // points is to win, which needs a goal, which needs letting the ball go.
        // **Steals won, paid up to a target and not a penny beyond.** The press term above asks
        // the nearest player to stand near the ball; it never asks anyone to take it, and measured
        // on 24 unseen seeds the policy obliged exactly that distinction - 0.4 steals a match
        // against §7's 2.2, while standing 6.0 m from the ball against §7's 4.2. No term that was
        // in here before could tell a side that waits for the ball from one that wins it.
        //
        // A steal, not possession share: a share is maximised by holding the ball and never
        // releasing it, which is the policy this function already had to be rewritten to kill (see
        // the draw being worth nothing). A steal cannot be earned by keep-ball, and it is an act
        // the policy can aim at - the observation carries which opponent is carrying and whether
        // this player is the nearest of its team-mates to the ball.
        //
        // **Saturating, because a monotone term is the wrong shape of objective** - the lesson the
        // experiment README already records: maximising a proxy walks out of the range that made it
        // a good proxy. So the term is `weight × min(steals / target, 1)` and its contribution lies
        // in `[0, weight]`. Two things follow that a per-steal price could not give:
        //
        //   * **The weight is the ceiling.** At 0.9 against a win's 3.0, chasing can never be worth
        //     more than winning *by construction*, not by my arithmetic coming out right.
        //   * **No reason to over-hunt.** Past the target the term is flat, so a side is never paid
        //     to send more bodies at the ball - the huddle §7.2 warns about. It is not *penalised*
        //     for exceeding it either: a side that genuinely wins the ball more than §7 is a better
        //     side, not an unrealistic one, which is why this is one-sided and not `off()`'s
        //     squared deviation.
        //
        // The target defaults to §7's measured 2.2 because that is the only ball-winning rate this
        // game has ever been observed at - a reference, not a law, and `--turnover-target` moves it.
        // §7 may well under-chase compared with a human; nobody has measured the human yet.
        //
        // Steals *conceded* are measured and reported but not charged: a side that holds the ball
        // more is stolen from more, so charging for it would charge for possession by the back door.
        return (s.wins * 3.0)
            + 0.15 * (s.goalsFor - s.goalsAgainst)
            - 0.12 * s.pressure
            + turnoverWeight * steals
    }

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
        + off(s.depth, r.depth, 1.0)

    return 4.0 * (s.goalsFor - s.goalsAgainst)
        + 0.6 * Swift.max(s.receivers - r.receivers, 0)
        - shapeWeight * shape
        + turnoverWeight * steals
}

let clubs = Club.allCases

/// A seeded match. The clubs vary, and so does each side's **formation**.
///
/// Every AI side plays `balanced` in the shipped game (§3), so without this the policy would only
/// ever see one opening shape and one set of home spots — and it would see it again after every
/// goal, since a face-off resets to it. Drawing one of §3's five formations a side is the cheap
/// version of varied starting states: different structures, different home spots, no surgery on
/// the state machine. It also exercises the reason the policy is per-player rather than one net
/// for the team — it has to work for whatever roster shape it is handed.
func setup(_ n: Int, periodSeconds: Double) -> MatchSetup {
    let home = clubs[(n * 3) % clubs.count]
    var away = clubs[(n * 3 + 1 + n / clubs.count) % clubs.count]
    if away == home { away = clubs[(clubs.firstIndex(of: home)! + 1) % clubs.count] }

    let shapes = Formation.allCases
    var h = SideSetup.club(home)
    var a = SideSetup.club(away)
    h.formation = shapes[(n * 7) % shapes.count]
    a.formation = shapes[(n * 11 + 2) % shapes.count]

    return MatchSetup(seed: 0x5EED_0000 &+ UInt64(n), sport: .field,
                      home: h, away: a, periodSeconds: periodSeconds,
                      orbitPeriod: Tuning.Orbit.demoPeriod, cup: false, control: .automatic)
}

func length(_ x: Double, _ z: Double) -> Double { (x * x + z * z).squareRoot() }

/// Plays one match with `net` driving team 0 (or nothing driving it, for the baseline) and §7's
/// written rules driving team 1, and scores team 0.
/// Who a candidate is made to play. Past selves keep it honest about its own lineage, §7 is the
/// absolute yardstick, and the two scripted sides punish the laziness a self-play pair will
/// happily agree on.
enum Rival {
    case rules
    case policy(PolicyNet)
    case scripted(Sparring)
}

func play(_ net: PolicyNet?, seed n: Int, cfg: Config, rival: Rival = .rules) -> Score {
    var m = Match(setup(n, periodSeconds: cfg.periodSeconds))
    switch rival {
    case .rules:
        m.installPolicies([net, nil])
    case .policy(let other):
        m.installPolicies([net, other])
    case .scripted(let style):
        m.installPolicies([net, nil])
        m.sparring = [nil, style]
    }
    m.openNets = cfg.openNets
    m.stamina = cfg.stamina
    if cfg.easeCollect && cfg.easeStep < cfg.easeLadder.count {
        m.collectEase = cfg.easeLadder[cfg.easeStep]
    }
    if cfg.rung < cfg.spawnLadder.count {
        m.trainingSpawn = cfg.spawnLadder[cfg.rung]
        m.spawnRNG = SplitMix64(seed: UInt64(bitPattern: Int64(n &* 7919 &+ 13)))
    }

    var s = Score()
    s.victoryOnly = cfg.victoryOnly
    s.turnoverTarget = cfg.turnoverTarget
    var playTicks = 0, ownTicks = 0
    var carryTicks = 0, finalTicks = 0
    var receiverTotal = 0.0
    var receiverFinalTotal = 0.0
    var territoryTotal = 0.0
    var spreadTotal = 0.0
    var spreadSamples = 0
    var pressureTotal = 0.0
    var widthTotal = 0.0
    var depthTotal = 0.0
    var stealsWon = 0, stealsLost = 0
    // Which team each roster index belongs to, read once: membership cannot change inside a match,
    // and `Match.players` is not public, so the alternative is a snapshot per steal.
    let teamOf = m.snapshot.players.map(\.team)

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
        // Every tick, not on the sampling stride: a steal is an instant, and the stride is 12 ticks
        // wide. Nothing else consumes the trainer's events, and draining keeps the match's event
        // array from growing for the whole run.
        for e in m.drainEvents() {
            guard case .steal(let by, _) = e else { continue }
            if by < teamOf.count, teamOf[by] == 0 { stealsWon += 1 } else { stealsLost += 1 }
        }
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

        // Depth: how far the deepest defender sits behind the ball. Added to the *trained* reward
        // rather than left as an honest check, because "leave the defenders back" is one of the
        // stated objectives and an untrained property drifts — the 128-unit clone that matched §7's
        // width exactly sat at +2.13 m of depth against §7's +5.45. Swarm and role churn stay
        // untrained, so something is still watching from outside.
        let defenders = mine.filter { snap.players[$0].role == .defender }
        if let deepest = defenders.min(by: { snap.players[$0].z < snap.players[$1].z }) {
            depthTotal += snap.ball.z - snap.players[deepest].z
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
    s.wins = m.score[0] > m.score[1] ? 1 : 0
    s.draws = m.score[0] == m.score[1] ? 1 : 0
    s.possession = playTicks > 0 ? Double(ownTicks) / Double(playTicks) : 0
    s.receivers = carryTicks > 0 ? receiverTotal / Double(carryTicks) : 0
    s.receiversFinal = finalTicks > 0 ? receiverFinalTotal / Double(finalTicks) : 0
    s.territory = carryTicks > 0 ? territoryTotal / Double(carryTicks) : 0
    s.attacking = playTicks > 0 ? Double(finalTicks) / Double(playTicks) : 0
    s.spread = spreadSamples > 0 ? spreadTotal / Double(spreadSamples) : 0
    s.pressure = playTicks > 0 ? pressureTotal / Double(playTicks) : 0
    s.width = playTicks > 0 ? widthTotal / Double(playTicks) : 0
    s.depth = playTicks > 0 ? depthTotal / Double(playTicks) : 0
    s.turnovers = Double(stealsWon)
    s.turnoversLost = Double(stealsLost)
    return s
}

/// Scores a candidate over `cfg.matches` seeded matches against a pool of opponents.
///
/// The pool, not just the current centre. Self-play against one's immediate self is how a policy
/// forgets: both sides drift together, the matches get easier in step, and competence that nothing
/// is currently testing quietly rots. Mixing in §7's rules and *older* checkpoints keeps a side
/// honest about the things it used to be able to do — the small-scale version of AlphaStar's
/// league, and the reason a share of matches always stays against the fixed rules.
func evaluate(_ net: PolicyNet?, cfg: Config, offset: Int = 0, pool: [PolicyNet] = [],
              league: Bool = true) -> Score {
    // **While the nets are open, play only itself.** §7 takes the ball back inside half a second,
    // and a side that never holds the ball cannot practise the one thing it is missing — when to
    // let it go. An equal opponent keeps the ball in play long enough for both to learn to finish.
    // Real opponents arrive with the keepers, which is the same promotion, so difficulty steps up
    // once rather than twice.
    if cfg.openNets && !pool.isEmpty {
        return Score.mean((0..<cfg.matches).map { k in
            play(net, seed: offset + k, cfg: cfg, rival: .policy(pool[k % pool.count]))
        })
    }
    // The rota, in order, so every candidate in an iteration meets the same opponents on the same
    // seeds — a paired comparison, which is most of the variance reduction ES gets for free.
    var rivals: [Rival] = []
    if league {
        let scripted = Swift.max(Int(Double(cfg.matches) * 0.15), 1)
        for k in 0..<scripted { rivals.append(.scripted(k % 2 == 0 ? .chaser : .blocker)) }
    }
    let selfPlay = pool.isEmpty ? 0 : Int((Double(cfg.matches) * cfg.selfPlay).rounded())
    for k in 0..<selfPlay { rivals.append(.policy(pool[k % pool.count])) }
    while rivals.count < cfg.matches { rivals.append(.rules) }

    return Score.mean((0..<cfg.matches).map { k in
        play(net, seed: offset + k, cfg: cfg, rival: rivals[k % rivals.count])
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
    // From scratch. He-scaled, so activations neither vanish nor explode through two layers, with
    // the output layer small so the first targets sit near the formation spot rather than pinned
    // to a corner.
    var k = 0
    theta = [Double](repeating: 0, count: dim)
    func fill(_ n: Int, _ scale: Double) {
        for _ in 0..<n { theta[k] = gauss.normal() * scale; k += 1 }
    }
    fill(cfg.hidden * nIn, (2.0 / Double(nIn)).squareRoot())
    fill(cfg.hidden, 0)
    fill(cfg.hidden * cfg.hidden, (2.0 / Double(cfg.hidden)).squareRoot())
    fill(cfg.hidden, 0)
    fill(nOut * cfg.hidden, 0.01)
    fill(nOut, 0)
    print("starting from scratch — \(dim) random parameters, nothing of §7 in them")
}

if C.gradCheck {
    let e = PPO.gradientCheck()
    print(String(format: "gradient check (relative error vs central differences)"))
    print(String(format: "  squared error  %.2e   |grad| %.4f", e.mse, e.mseNorm))
    print(String(format: "  PPO surrogate  %.2e   |grad| %.4f", e.surrogate, e.surrogateNorm))
    // A gradient of nothing agrees with a finite difference of nothing, which proves nothing - so
    // the magnitudes have to be real before the agreement means anything.
    let agree = e.mse < 1e-5 && e.surrogate < 1e-5
    let real = e.mseNorm > 1e-3 && e.surrogateNorm > 1e-3
    print(agree && real ? "both agree, and both gradients are substantial - the backward pass is right"
          : !real ? "VACUOUS - a gradient is ~0, so the agreement means nothing"
          : "MISMATCH - do not train on this")
    exit(agree && real ? 0 : 1)
}
print("reward: " + (C.victoryOnly ? "victory alone (goal difference)" : "shaped"))
if C.easeCollect {
    print("§6.3.1: eased in over \(C.easeLadder.map { String(format: "%.1f", $0) }.joined(separator: " → "))"
          + ", a notch per spawn rung climbed")
}
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

/// Writes one seeded match three times — `theta` against §7, **`theta` against itself**, and §7
/// against §7 — as a single scrubable page. Same seed, so all three pitches start identically and
/// every difference after that is the policy rather than the draw.
///
/// **The self-play pitch is the one worth watching for shape.** Against §7 you are watching a
/// policy exploit a known opponent, which tells you little about whether it plays hockey; against
/// itself there is nobody to exploit, so what is left is what it actually believes a team should
/// look like. `--versus B.txt` replaces that middle pitch with `theta` against B.
func writeReplay(_ theta: [Double], to file: String, seed: Int, versus: [Double]? = nil) {
    let loaded = PolicyNet(nIn: nIn, nHidden: C.hidden, nOut: nOut, parameters: theta)
    let other = versus.map { PolicyNet(nIn: nIn, nHidden: C.hidden, nOut: nOut, parameters: $0) }
    let s = setup(seed, periodSeconds: C.periodSeconds)
    let tapes = [Replay.record([loaded, nil], setup: s, label: "learned v §7"),
                 Replay.record([loaded, other ?? loaded], setup: s,
                               label: other == nil ? "learned v itself" : "learned v versus"),
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
        writeReplay(theta, to: file, seed: C.replaySeed, versus: C.versus.map(readCheckpoint))
        print("replay written: \(file)")
    } else {
        let me = PolicyNet(nIn: nIn, nHidden: C.hidden, nOut: nOut, parameters: theta)
        let other = C.versus.map { (path: String) -> PolicyNet in
            PolicyNet(nIn: nIn, nHidden: C.hidden, nOut: nOut, parameters: readCheckpoint(path))
        }
        let learned = other.map { (o: PolicyNet) -> Score in
            Score.mean((0..<C.matches).map { k in
                play(me, seed: C.evalOffset + k, cfg: C, rival: .policy(o))
            })
        } ?? evaluate(me, cfg: C, offset: C.evalOffset, league: false)
        let rules = other.map { (o: PolicyNet) -> Score in
            Score.mean((0..<C.matches).map { k in
                play(o, seed: C.evalOffset + k, cfg: C, rival: .policy(me))
            })
        } ?? evaluate(nil, cfg: C, offset: C.evalOffset, league: false)
        print("seeds \(C.evalOffset)..<\(C.evalOffset + C.matches)"
              + (C.evalOffset == 0 ? "  (WARNING: the search selects on these)" : "  (unseen by the search)"))
        print("                goals      poss   recv  final  spread  press   terr    att   steals")
        for (label, m) in [("learned", learned), ("§7 rules", rules)] {
            let a = String(format: "%.2f-%.2f", m.goalsFor, m.goalsAgainst)
            let b = String(format: "%.3f  %.2f  %.2f   %5.1f  %5.1f  %+.2f  %.3f  %4.1f-%.1f",
                           m.possession, m.receivers, m.receiversFinal, m.spread,
                           m.pressure, m.territory, m.attacking, m.turnovers, m.turnoversLost)
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
let baseline = evaluate(nil, cfg: baselineCfg, league: false)
let baseGoals: String = String(format: "%.2f–%.2f", baseline.goalsFor, baseline.goalsAgainst)
let baseRest: String = String(format: "poss %.2f  recv %.2f (final %.2f)  spread %.1f m  press %.1f m  terr %+.2f  att %.3f  steals %.1f-%.1f  fitness %.3f",
                              baseline.possession, baseline.receivers, baseline.receiversFinal,
                              baseline.spread, baseline.pressure, baseline.territory,
                              baseline.attacking, baseline.turnovers, baseline.turnoversLost,
                              fitness(baseline, reference: baseline, shapeWeight: C.shapeWeight, turnoverWeight: C.turnoverWeight))
print("baseline  §7's written rules vs itself   goals " + baseGoals + "  " + baseRest)
print("")
print("  (goals/poss/etc are measured against the frozen earlier self, not against §7)")
// PPO runs here rather than at the banner: `writeCheckpoint` reads `outDir`, and a top-level
// global referenced before its own statement has run is empty — the first smoke run duly wrote
// its checkpoints to "/" and died on a read-only file system.
if C.ppo {
    PPOTrain.run(C, outDir: outDir)
    exit(0)
}
print(" iter    goals     poss   recv  final  spread  press   terr    att    fitness    best      secs")



var best = -Double.greatestFiniteMagnitude
var bestTheta = theta
var stale = 0
var atThreshold = 0
var onRung = 0
var sigma = C.sigma
/// Past selves the candidates also have to beat. Capped: a handful of rungs is enough to stop the
/// forgetting, and every extra one costs matches.
/// Seeded with the starting weights so there is always an equal opponent, even at iteration one
/// before anything has been judged good enough to keep.
var opponentPool: [PolicyNet] = []
/// A frozen earlier self, and what the centre is scored against.
///
/// Not §7. Scoring the centre against a much stronger fixed opponent selects for *not conceding*,
/// because against a side you cannot beat, standing still is the best goal difference available —
/// and with the training gradient coming from self-play, selection and gradient then pull opposite
/// ways. Measured: possession against §7 fell to 0.10 while the search was nominally improving.
/// "Can I beat who I was" is stationary, aligned with what is being trained, and the standard way
/// to read progress in self-play.
var benchmark: PolicyNet?
let poolLimit = C.poolLimit
let pairs = cfg.population / 2
opponentPool.append(net(theta))   // an equal to play from the first iteration

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
        evaluate(net(candidates[k]), cfg: localCfg, offset: iteration * 97, pool: frozenPool,
                 league: !localCfg.pureSelfPlay)
    }
    let fitnesses = scores.map { fitness($0, reference: baseline, shapeWeight: localCfg.shapeWeight, turnoverWeight: localCfg.turnoverWeight) }
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
    centreCfg.selfPlay = 1.0
    // Against the frozen earlier self when there is one; against §7 until then.
    let centre = benchmark.map { evaluate(net(theta), cfg: centreCfg, pool: [$0], league: false) }
        ?? evaluate(net(theta), cfg: centreCfg, league: false)

    // Keepers come back once the policy can finish. Once closed they stay closed: a curriculum
    // that oscillates teaches a policy to straddle both worlds and master neither. The best-so-far
    // is reset with them, because scores earned against an open net are not comparable.
    // One ladder, climbed in order: tap-in, then further out, then the real game. Scores earned on
    // an easier rung are not comparable, so the best-so-far resets with each promotion.
    let bar = cfg.rung < cfg.rungBar.count ? cfg.rungBar[cfg.rung] : cfg.closeNetsAt
    atThreshold = centre.goalsFor >= bar ? atThreshold + 1 : 0
    onRung += 1
    if onRung >= cfg.rungPatience && cfg.rung < cfg.spawnLadder.count {
        print(String(format: "  = %d iterations on this rung without clearing %.1f - moving on anyway",
                     onRung, bar))
        atThreshold = cfg.holdFor
    }
    if atThreshold >= cfg.holdFor {
        onRung = 0
        atThreshold = 0
        if cfg.rung < cfg.spawnLadder.count {
            func describe(_ r: TrainingStart) -> String {
                switch r {
                case .ours(let d): return String(format: "our ball, %.0f m out", d)
                case .loose(let d): return String(format: "a loose ball, %.0f m out", d)
                case .theirs(let d): return String(format: "their ball, %.0f m from our goal", d)
                }
            }
            print("  = scoring " + String(format: "%.2f", centre.goalsFor) + " a match on "
                  + describe(cfg.spawnLadder[cfg.rung]) + " - moving to "
                  + (cfg.rung + 1 < cfg.spawnLadder.count
                     ? describe(cfg.spawnLadder[cfg.rung + 1]) : "the real game"))
            cfg.rung += 1
            // One notch of §6.3.1 per rung, so the policy meets a stricter rule each time it
            // meets a harder situation, and meets the real rule by the time it meets the real
            // game. Goals are what move in a run that is working - possession sits at 0.03-0.07
            // through every early rung even in the run that climbed them all - so clearing a rung
            // is the only competence signal there is to gate on.
            if cfg.easeCollect && cfg.easeStep < cfg.easeLadder.count - 1 {
                cfg.easeStep += 1
                print(String(format: "    §6.3.1 tightened to ease %.1f", cfg.easeLadder[cfg.easeStep]))
            }
            best = -Double.greatestFiniteMagnitude
            bestTheta = theta
            stale = 0
            if cfg.rung >= cfg.spawnLadder.count {
                cfg.openNets = false
                benchmark = net(theta)
            }
        } else if cfg.openNets {
            cfg.openNets = false
            benchmark = net(theta)
            best = -Double.greatestFiniteMagnitude
            bestTheta = theta
            stale = 0
            print("  = keepers back on from here")
        }
    }
    if fitness(centre, reference: baseline, shapeWeight: C.shapeWeight, turnoverWeight: C.turnoverWeight) > best {
        best = fitness(centre, reference: baseline, shapeWeight: C.shapeWeight, turnoverWeight: C.turnoverWeight)
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
                              fitness(centre, reference: baseline, shapeWeight: C.shapeWeight, turnoverWeight: C.turnoverWeight), best, secs)
    print(String(format: "%5d  ", iteration) + goals + "   " + rest)
    _ = mean
}

print("")
print(String(format: "done — best fitness %.3f, baseline %.3f. Checkpoints in %@",
             best, fitness(baseline, reference: baseline, shapeWeight: C.shapeWeight, turnoverWeight: C.turnoverWeight), outDir))
