// Measures automatic play over a sweep of seeded matches (spec §7). It writes nothing — it is the
// bench §7.9's alert window and §7.4's receiving slot were tuned on, and the way to re-measure.
//
//     cd ios/SmashCore && swift run -c release MeasureMatches            # the default sweep, 40 + 24 + 300 matches
//     cd ios/SmashCore && swift run -c release MeasureMatches 80 48 600  # a longer one
//
// Four benches, because one does not see what the other does:
//
//  * **league** — both sides automatic (§9's demo rules). Goals, shots, saves, turnovers and how far
//    out goals are scored from: the health of the match as a whole.
//  * **solo** — the player's side driven by a bot that never passes: it carries from wherever it
//    wins the ball and lifts at the first shot snap. This is the long solo goal the alert window
//    exists to punish, measured as conversion per distance band.
//  * **shape** — while the player's side carries inside the attacking third, how many team-mates
//    stand in a genuine receiving position (the §7.4 band, an unblocked lane, up the pitch).
//  * **sports** — the same league fixtures played out on ice and on the field, side by side: the
//    bench §8.9's offside was tuned on. Offside whistles, how often the rule takes possession away,
//    the share of zone entries that stray offside and the share of those the referee misses — and
//    goals per match on each sport, because the rule must not wreck the ice world's flow.
//  * **margins** — the bench §7.10's rubberband was tuned on: over a few hundred seeded league
//    matches, how the final margin is distributed, how often a match is decided by one goal, and
//    how often a side is ever five clear. This is the one that says whether a match feels close.
import Foundation
import SmashCore

let args = CommandLine.arguments.dropFirst().compactMap { Int($0) }
let leagueCount = args.first ?? 40
let soloCount = args.dropFirst().first ?? 24
let marginCount = args.dropFirst(2).first ?? 300
let clubs = Club.allCases
let goalZ = Tuning.Pitch.goalLineZ

func length(_ x: Double, _ z: Double) -> Double { (x * x + z * z).squareRoot() }

/// Distance from `p` to the segment a→b.
func segmentDistance(_ p: MatchSnapshot.Player, _ ax: Double, _ az: Double, _ bx: Double, _ bz: Double) -> Double {
    let dx = bx - ax, dz = bz - az
    let len2 = dx * dx + dz * dz
    var t = 0.0
    if len2 > 0 { t = max(0, min(1, ((p.x - ax) * dx + (p.z - az) * dz) / len2)) }
    return length(p.x - (ax + dx * t), p.z - (az + dz * t))
}

func setup(_ n: Int, control: Control) -> MatchSetup {
    let home = clubs[(n * 3) % clubs.count]
    var away = clubs[(n * 3 + 1 + n / clubs.count) % clubs.count]
    if away == home { away = clubs[(clubs.firstIndex(of: home)! + 1) % clubs.count] }
    return MatchSetup(seed: 0x5EED_0000 &+ UInt64(n), sport: n % 5 == 4 ? .ice : .field,
                      home: .club(home), away: .club(away), periodSeconds: 120,
                      orbitPeriod: control == .automatic ? Tuning.Orbit.demoPeriod : 2.0,
                      cup: false, control: control)
}

func share(_ part: Int, _ whole: Int) -> String {
    whole == 0 ? "   —" : String(format: "%3.0f %%", 100 * Double(part) / Double(whole))
}
func per(_ part: Int, _ whole: Int) -> String {
    whole == 0 ? "—" : String(format: "%.2f", Double(part) / Double(whole))
}

/// Shots and the goals they produced, by the distance they were taken from.
struct Bands {
    static let edges = [0.0, 6, 10, 14, 18, 22, 26, 60]
    var shots = [Int](repeating: 0, count: edges.count - 1)
    var goals = [Int](repeating: 0, count: edges.count - 1)
    static func index(_ d: Double) -> Int {
        for k in 0..<(edges.count - 1) where d >= edges[k] && d < edges[k + 1] { return k }
        return edges.count - 2
    }
    mutating func shot(_ d: Double) { shots[Bands.index(d)] += 1 }
    mutating func goal(_ d: Double) { goals[Bands.index(d)] += 1 }
    func table() -> String {
        var out = "    band      shots   goals   scored\n"
        for k in 0..<(Bands.edges.count - 1) where shots[k] + goals[k] > 0 {
            out += String(format: "  %4.0f–%-4.0f %7d %7d   %@\n",
                          Bands.edges[k], Bands.edges[k + 1], shots[k], goals[k], share(goals[k], shots[k]))
        }
        return out
    }
}

// MARK: The league bench — both sides automatic

var league = (matches: 0, goals: 0, assisted: 0, own: 0, long: 0, longSolo: 0, shots: 0, saves: 0, turnovers: 0)
var leagueBands = Bands()

for n in 0..<leagueCount {
    var match = Match(setup(n, control: .automatic))
    let teams = match.snapshot.players.map(\.team)
    var holder: Int?
    league.matches += 1
    while match.state != .ended && match.ticks < 120_000 {
        match.tick()
        for event in match.drainEvents() {
            switch event {
            case .pickup(let p), .steal(by: let p, from: _):
                if let h = holder, teams[h] != teams[p] { league.turnovers += 1 }
                holder = p
            case .shot(_, let kind):
                if kind == .shot { league.shots += 1; leagueBands.shot(match.lastShotDistance ?? 0) }
            case .save:
                league.saves += 1
            case .goal(_, _, let assist, let own):
                league.goals += 1
                let d = match.lastShotDistance ?? 0
                leagueBands.goal(d)
                if own { league.own += 1 }
                if assist != nil { league.assisted += 1 }
                if d >= 18 { league.long += 1; if assist == nil { league.longSolo += 1 } }
            default: break
            }
        }
    }
}

// MARK: The solo bench — a bot that never passes, and the shape it leaves behind

struct Solo {
    var matches = 0
    var goals = 0
    var conceded = 0
    var bands = Bands()
    var alertBands = Bands()
    /// Ticks sampled with the bot's side carrying inside the attacking third.
    var thirdTicks = 0
    /// Of those, ticks with at least one team-mate in a genuine receiving position.
    var withReceiver = 0
    var receiverSum = 0
    /// Ticks with a team-mate up there at all: in the pass band and within 18 of the goal.
    var withMateUpThere = 0
    /// How far the nearest team-mate is from the §7.4 offer spot, summed over sampled ticks.
    var offerGapSum = 0.0
    /// Nearest team-mate's distance to the carrier, summed over sampled ticks.
    var nearestSum = 0.0
    var alertTicks = 0
    var playTicks = 0
    /// Ticks the bot's side carried in its own half, and past the line.
    var ownHalfCarry = 0
    var farHalfCarry = 0
}

var solo = Solo()
/// The bot carries until this near the goal, then lifts at the first shot snap.
let soloRange = 24.0

for n in 0..<soloCount {
    var match = Match(setup(n, control: .player))
    solo.matches += 1
    var down = false
    var wasAlerted = false
    while match.state != .ended && match.ticks < 120_000 {
        let snap = match.snapshot
        var lift = false
        if snap.state == .play, snap.playerCarrier, let c = snap.ball.carrier {
            let d = length(snap.players[c].x, goalZ - snap.players[c].z)
            // It carries until it is in range — the owner's run: win it deep, cross, shoot from afar.
            lift = down && snap.aim == .shot && d < soloRange
            // Sample the shape while the carrier is inside the attacking third.
            if d < 20 {
                solo.thirdTicks += 1
                var receivers = 0
                var upThere = 0
                var nearest = Double.infinity
                for m in snap.players.indices
                where m != c && snap.players[m].team == 0 && snap.players[m].role != .goalie {
                    let p = snap.players[m]
                    let dm = length(p.x - snap.players[c].x, p.z - snap.players[c].z)
                    nearest = min(nearest, dm)
                    guard dm >= 7 && dm <= 17 else { continue }                 // a real pass, still a shot after it
                    if length(p.x, goalZ - p.z) <= 18 { upThere += 1 }          // a shooting position
                    guard length(p.x, goalZ - p.z) <= 22 else { continue }      // up the pitch, not an outlet
                    let blocked = snap.players.indices.contains { o in
                        snap.players[o].team == 1
                            && segmentDistance(snap.players[o], snap.players[c].x, snap.players[c].z, p.x, p.z) < 1.4
                    }
                    if !blocked { receivers += 1 }
                }
                if receivers > 0 { solo.withReceiver += 1 }
                if upThere > 0 { solo.withMateUpThere += 1 }
                // Where §7.4 says the offer is, and how near the nearest team-mate got to it.
                let cx = snap.players[c].x, cz = snap.players[c].z
                var takerX = 0.0, takerD = Double.infinity
                for m in snap.players.indices
                where m != c && snap.players[m].team == 0 && snap.players[m].role == .forward {
                    let d = length(snap.players[m].x, goalZ - snap.players[m].z)
                    if d < takerD { takerD = d; takerX = snap.players[m].x }
                }
                typealias S = Tuning.AI.Support
                var ox = S.offerX * (takerX >= 0 ? 1 : -1), oz = goalZ - S.offerGoalInset
                let od = length(ox - cx, oz - cz)
                let want = max(S.offerMin, min(S.offerMax, od))
                if want != od { ox = cx + (ox - cx) / od * want; oz = cz + (oz - cz) / od * want }
                ox = max(-(Tuning.Pitch.halfWidth - S.sidelineInset), min(Tuning.Pitch.halfWidth - S.sidelineInset, ox))
                var gap = Double.infinity
                for m in snap.players.indices
                where m != c && snap.players[m].team == 0 && snap.players[m].role != .goalie {
                    gap = min(gap, length(snap.players[m].x - ox, snap.players[m].z - oz))
                }
                solo.offerGapSum += gap.isFinite ? gap : 0
                solo.receiverSum += receivers
                solo.nearestSum += nearest.isFinite ? nearest : 0
            }
        }
        if lift { match.hold(false); down = false } else if !down { match.hold(true); down = true }
        if snap.state == .play {
            solo.playTicks += 1
            if match.alerted[1] { solo.alertTicks += 1 }
            if let c = snap.ball.carrier, snap.players[c].team == 0, snap.players[c].role != .goalie {
                if snap.players[c].z < 0 { solo.ownHalfCarry += 1 } else { solo.farHalfCarry += 1 }
            }
        }
        let alertedBefore = match.alerted[1]
        match.tick()
        for event in match.drainEvents() {
            switch event {
            case .shot(let by, let kind):
                if kind == .shot && match.snapshot.players[by].team == 0 {
                    wasAlerted = alertedBefore || match.alerted[1]
                    if wasAlerted { solo.alertBands.shot(match.lastShotDistance ?? 0) }
                    else { solo.bands.shot(match.lastShotDistance ?? 0) }
                }
            case .goal(let team, _, _, _):
                if team == 0 {
                    solo.goals += 1
                    if wasAlerted { solo.alertBands.goal(match.lastShotDistance ?? 0) }
                    else { solo.bands.goal(match.lastShotDistance ?? 0) }
                } else { solo.conceded += 1 }
            default: break
            }
        }
    }
}

// MARK: The sports bench — ice against field, and the offside rule (§8.9)

struct SportBench {
    var matches = 0
    var goals = 0
    var whistles = 0
    var entries = 0
    var strays = 0
    var missed = 0
    /// Offside whistles that took the puck off an attack that was carrying it.
    var tookPossession = 0
    /// Offside restarts whose first touch went to the side that had been defending.
    var turnedOver = 0
    var restarts = 0
}

func runSport(_ sport: Sport, _ count: Int) -> SportBench {
    var b = SportBench()
    for n in 0..<count {
        var s = setup(n, control: .automatic)
        s.sport = sport
        // A stream of its own, so this bench does not measure the league bench's matches.
        s.seed = 0x0FF5_0000 &+ UInt64(n)
        var match = Match(s)
        b.matches += 1
        var offendingTeam: Int?
        while match.state != .ended && match.ticks < 120_000 {
            let carried = match.snapshot.ball.carrier != nil
            match.tick()
            for event in match.drainEvents() {
                switch event {
                case .goal: b.goals += 1
                case .offside(let team, _):
                    b.whistles += 1
                    if carried { b.tookPossession += 1 }
                    offendingTeam = team
                case .pickup(let p), .steal(by: let p, from: _):
                    if let t = offendingTeam {
                        b.restarts += 1
                        if match.snapshot.players[p].team != t { b.turnedOver += 1 }
                        offendingTeam = nil
                    }
                default: break
                }
            }
        }
        b.entries += match.offsideEntries
        b.strays += match.offsideStrays
        b.missed += match.offsideMissed
    }
    return b
}

let sportCount = args.dropFirst(3).first ?? 120
let sportBenches = [(name: "field", bench: runSport(.field, sportCount)),
                    (name: "ice  ", bench: runSport(.ice, sportCount))]
let sportsTable: String = {
    var out = "    sport   matches   goals   offside   took puck   turned over   entries   strayed   missed\n"
    for (name, b) in sportBenches {
        out += "    \(name) \(String(format: "%9d", b.matches))    \(per(b.goals, b.matches))"
        out += "      \(per(b.whistles, b.matches))       \(share(b.tookPossession, b.whistles))"
        out += "          \(share(b.turnedOver, b.restarts))    \(per(b.entries, b.matches))"
        out += "      \(share(b.strays, b.entries))     \(share(b.missed, b.strays))\n"
    }
    return out
}()

// MARK: The margins bench — how close a match ends up (§7.10)

struct Margins {
    var matches = 0
    var goals = 0
    /// Final margins, bucketed 0, 1, … 6, then 7+.
    var histogram = [Int](repeating: 0, count: 8)
    var everFiveClear = 0
    var draws = 0
    var marginSum = 0
    /// Matches whose biggest lead at any point was this many goals or more.
    var everLead = [Int](repeating: 0, count: 8)

    mutating func record(final: Int, peak: Int, goals: Int) {
        matches += 1
        self.goals += goals
        histogram[min(final, 7)] += 1
        marginSum += final
        if final == 0 { draws += 1 }
        if peak >= 5 { everFiveClear += 1 }
        for k in 0...min(peak, 7) { everLead[k] += 1 }
    }

    func table() -> String {
        var out = "   margin    matches   share\n"
        for k in histogram.indices {
            let label = k == 7 ? "  7+ " : String(format: "%4d", k)
            out += String(format: "   %@ %10d   %@\n", label, histogram[k], share(histogram[k], matches))
        }
        return out
    }
}

var margins = Margins()
/// The same, split by how strongly the match's temperament rubberbands it (§7.10): the calm third,
/// the middle third and the fierce third. A blowout should live almost entirely in the calm third.
var byTemperament = [Margins(), Margins(), Margins()]
var temperaments: [Double] = []
/// The thirds the report splits on, half a temperament either side of §7.10's base.
let calmBelow = Tuning.AI.Balance.temperamentBase - 0.5
let fierceFrom = Tuning.AI.Balance.temperamentBase + 0.5
for n in 0..<marginCount {
    // A stream of its own, disjoint from the league bench's, so the two do not measure the same matches.
    var setup = setup(n, control: .automatic)
    setup.seed = 0x8A1A_0000 &+ UInt64(n)
    var match = Match(setup)
    var peak = 0
    var goals = 0
    while match.state != .ended && match.ticks < 120_000 {
        match.tick()
        for event in match.drainEvents() {
            if case .goal = event {
                goals += 1
                peak = max(peak, abs(match.score[0] - match.score[1]))
            }
        }
    }
    let final = abs(match.score[0] - match.score[1])
    margins.record(final: final, peak: peak, goals: goals)
    let t = match.temperament
    temperaments.append(t)
    byTemperament[t < calmBelow ? 0 : (t < fierceFrom ? 1 : 2)].record(final: final, peak: peak, goals: goals)
}

/// The margin table split by temperament (§7.10): a blowout should live in the calm third.
let temperamentTable: String = {
    var out = String(format: "  by temperament (\u{00A7}7.10): calm < %.2f, middling, fierce \u{2265} %.2f\n", calmBelow, fierceFrom)
    out += "    band       matches   goals   margin   within 3    5+   ever 5 clear\n"
    for (k, name) in ["calm    ", "middling", "fierce  "].enumerated() {
        let m = byTemperament[k]
        let within3 = m.histogram[0] + m.histogram[1] + m.histogram[2] + m.histogram[3]
        let five = m.histogram[5] + m.histogram[6] + m.histogram[7]
        out += "    \(name) \(String(format: "%8d", m.matches))   \(per(m.goals, m.matches))"
        out += "    \(per(m.marginSum, m.matches))     \(share(within3, m.matches))  \(share(five, m.matches))"
        out += "          \(share(m.everFiveClear, m.matches))\n"
    }
    return out
}()

// MARK: The report

print("""

LEAGUE — \(league.matches) matches, both sides automatic
  goals per match       \(per(league.goals, league.matches))   (\(league.goals), \(league.own) own)
  shots per match       \(per(league.shots, league.matches))
  saves per match       \(per(league.saves, league.matches))
  turnovers per match   \(per(league.turnovers, league.matches))
  assisted goals        \(share(league.assisted, league.goals))
  goals from ≥ 18       \(share(league.long, league.goals))  (\(league.long))
  … and unassisted      \(share(league.longSolo, league.goals))  (\(league.longSolo))
\(leagueBands.table())
SOLO — \(solo.matches) matches, the player's side a bot that never passes
  goals for / against   \(solo.goals) / \(solo.conceded)   (\(per(solo.goals, solo.matches)) per match)
  shots against an ALERTED defence (§7.9)
\(solo.alertBands.table())  shots against a settled defence
\(solo.bands.table())
SHAPE — sampled while the bot carries inside 20 of the goal it attacks
  play ticks            \(solo.playTicks)  (alerted \(share(solo.alertTicks, solo.playTicks)))
  team 0 carries        own half \(solo.ownHalfCarry), far half \(solo.farHalfCarry)
  ticks sampled         \(solo.thirdTicks)
  a mate in a shooting position \(share(solo.withMateUpThere, solo.thirdTicks))
  a receiver is offered \(share(solo.withReceiver, solo.thirdTicks))
  receivers on average  \(per(solo.receiverSum, solo.thirdTicks))
  nearest team-mate     \(per(Int(solo.nearestSum.rounded()), solo.thirdTicks)) m
  nearest to the offer  \(per(Int(solo.offerGapSum.rounded()), solo.thirdTicks)) m

SPORTS — \(sportCount) matches each, the same fixtures on both sports, both sides automatic (§8.9)
  "entries" is the zone entries an attack made per match, "strayed" the share of those that were
  offside, "missed" the share of those the referee let go; "turned over" is the share of offside
  restarts whose first touch went to the side that had been defending.
\(sportsTable)
MARGINS — \(margins.matches) matches, both sides automatic (§7.10)
  goals per match       \(per(margins.goals, margins.matches))
  mean final margin     \(per(margins.marginSum, margins.matches))
  decided by one goal   \(share(margins.histogram[1], margins.matches))
  drawn                 \(share(margins.draws, margins.matches))
  within 3              \(share(margins.histogram[0] + margins.histogram[1] + margins.histogram[2] + margins.histogram[3], margins.matches))
  5 or more             \(share(margins.histogram[5] + margins.histogram[6] + margins.histogram[7], margins.matches))
  7 or more             \(share(margins.histogram[7], margins.matches))
  ever 5 clear          \(share(margins.everFiveClear, margins.matches))
\(margins.table())
\(temperamentTable)
""")
