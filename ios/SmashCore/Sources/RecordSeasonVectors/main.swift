// Records the season golden vectors (spec §2.2, §11, §15, §4.7) into shared/vectors/season/:
//
//     cd ios/SmashCore && swift run RecordSeasonVectors            # writes missing files; refuses to change one
//     cd ios/SmashCore && swift run RecordSeasonVectors --rerecord # overwrites — only with a spec change
//
// The inputs (seeds, careers, the player's scripted scores, the names and drafts, the save states)
// are declared here and written into the files; the replaying suites read them from the files and
// never from this program.
import Foundation
import SmashCore

let root = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    .deletingLastPathComponent().deletingLastPathComponent()
let outDir = root.appendingPathComponent("shared/vectors/season")
let rerecord = CommandLine.arguments.contains("--rerecord")
let provenance = "Recorded by ios/SmashCore RecordSeasonVectors (macOS, arm64). Replayed exactly by SmashCoreTests and android/core."
var failures = 0

@MainActor func write(_ name: String, _ body: String) {
    let url = outDir.appendingPathComponent(name)
    if let existing = try? String(contentsOf: url, encoding: .utf8) {
        if existing == body { print("unchanged \(name)"); return }
        if !rerecord {
            print("REFUSED \(name): it differs from what this build computes. Re-recording a vector needs a spec "
                  + "change in the same commit (spec §4.7); pass --rerecord if that is what this is.")
            failures += 1
            return
        }
    }
    try! FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    try! body.write(to: url, atomically: true, encoding: .utf8)
    print("wrote \(name)")
}

func text(_ header: [String], _ lines: [String]) -> String {
    header.map { "# " + $0 }.joined(separator: "\n") + "\n" + lines.joined(separator: "\n") + "\n"
}

func entries(_ spec: String) -> [SeasonScript.Entry] {
    spec.split(separator: ",").map { item in
        let w = item.split(separator: " ")
        return SeasonScript.Entry(goalsFor: Int(w[0])!, goalsAgainst: Int(w[1])!, mode: SeasonScript.Mode(rawValue: String(w[2]))!)
    }
}

func hex(_ v: UInt32) -> String {
    let s = String(v, radix: 16, uppercase: true)
    return "#" + String(repeating: "0", count: 6 - s.count) + s
}

// MARK: - Two whole seasons

// Every career is the player's own team in Glacier Wolves' place (spec §2.2), so both seasons are
// played by a created team; their short codes are derived from their names (MOS is Moss Foxes').
let jet = Career.kitPalette[0], navy = Career.kitPalette[9], coral = Career.kitPalette[4]

// (a) A forfeit in the league, the quarter-final and the final won in overtime, the cup won.
let runName = "Rocket Rangers"
let runCareer = "created \(CreatedTeamRules.suggestedShortCode(for: runName)) \(hex(coral.primary)) "
    + "\(hex(navy.secondary)) magicwood \(runName)"
let runScript = SeasonScript(seed: 0x5EA5_0200_2026_0922, career: runCareer, entries: entries(
    "2 1 -,0 0 -,1 3 -,3 0 -,3 2 ot,0 3 forfeit,4 2 -,1 1 -,2 0 -,0 1 -,2 1 -,3 3 -,1 0 -,2 2 -,5 1 -,0 2 -,1 0 ot"))

// (b) The quarter-final forfeited, so the semi-finals and the final are simulated straight through.
let exitName = "Moss Giants"
let exitCareer = "created \(CreatedTeamRules.suggestedShortCode(for: exitName)) \(hex(navy.primary)) "
    + "\(hex(jet.secondary)) himalaya \(exitName)"
let exitScript = SeasonScript(seed: 0x0000_0000_0000_002A, career: exitCareer, entries: entries(
    "1 0 -,2 2 -,0 1 -,3 1 -,0 3 forfeit,2 0 -,1 1 -,0 2 -,4 0 -,1 0 -,2 3 -,3 0 -,0 0 -,2 1 -,1 2 -"))

for (name, script, about) in [("season-cup-run.txt", runScript, "the player to the cup final"),
                              ("season-cup-exit.txt", exitScript, "the player out of the cup")] {
    let lines = try script.run().lines
    write(name, text([
        "Season golden vector (spec §11, §2.2): a whole season from a fixed seed through the save's API — \(about).",
        "Inputs: seed, career, and one script line per player match (goals for, against, - | ot | forfeit).",
        "Outputs: league (canonical order), every drawn fixture (matchday, label, home, away), the stream after",
        "the start and after every player match, and per closed matchday its results (home away hg ag ot|- player|sim),",
        "the next cup draw, and the table (pos short P W D L GF GA Pts); then champion, cup winner and trophies.",
        provenance,
    ], lines))
}

// MARK: - Simulated results, densely

// Every pair of ratings the season can hold (the clubs' and the created team's), league and cup,
// three times over, from one stream: pins the Poisson draws and the cup's overtime rule far beyond
// what two seasons happen to exercise.
let ratings = Array(Set(Club.allCases.map(\.rating) + [Career.createdRating])).sorted()
var simStream = SplitMix64(seed: 0x0011_0003_5EA5_0000)
var sims: [String] = ["seed 0x001100035EA50000"]
for _ in 0..<3 {
    for cup in [false, true] {
        for h in ratings {
            for a in ratings {
                let s = SeasonRecord.simulate(home: h, away: a, cup: cup, &simStream)
                sims.append("sim \(h) \(a) \(cup ? "cup" : "league") \(s.home) \(s.away) \(s.overtime ? "ot" : "-")")
            }
        }
    }
}
sims.append("stream 0x" + String(format: "%016llX", simStream.state))
write("simulated.txt", text([
    "Simulated results (spec §11.3): one stream seeded as given; each line draws, in order, home rating, away rating,",
    "league | cup, and the score it gives (home away, ot when a level cup match went to overtime); the stream's end.",
    provenance,
], sims))

// MARK: - The created team's rules

let names = ["Moss Giants", "Rocket Rangers", "Glowworms", "Ümläut Élan", "Jo", "7", "A", "Coral", "Mos", "Neb",
             "Straße Kings", "  Dune Riders  ", "Nebula Knights", "Mirage", "GLW", "x-ray 9", "Łódź Lions", "🦊 Foxy"]
var careerLines = names.map { "short \(CreatedTeamRules.suggestedShortCode(for: $0)) \"\($0)\"" }
let fox = "🦊🦊"
let drafts: [(String, String, UInt32, UInt32)] = [
    ("Moss Giants", "MOG", jet.primary, jet.secondary),
    ("A", "AXX", jet.primary, jet.secondary),
    ("  A  ", "AXX", jet.primary, jet.secondary),
    ("  Bo  ", "BOX", jet.primary, jet.secondary),
    ("Sixteen Letters!", "SIX", jet.primary, jet.secondary),
    ("Seventeen Letters", "SEV", jet.primary, jet.secondary),
    (fox, "FOX", jet.primary, jet.secondary),
    ("Moss Giants", "MO", jet.primary, jet.secondary),
    ("Moss Giants", "mog", jet.primary, jet.secondary),
    ("Moss Giants", "MÖG", jet.primary, jet.secondary),
    ("Moss Giants", "ROC", jet.primary, jet.secondary),
    ("Moss Giants", "GLW", jet.primary, jet.secondary),
    ("Moss Giants", "MOG", Club.mossfoxes.primary, jet.secondary),
    ("Moss Giants", "MOG", jet.primary, jet.primary),
    ("Moss Giants", "MOG", navy.primary, jet.secondary),
    ("", "", Club.rocketlynx.primary, Club.rocketlynx.secondary),
]
careerLines += drafts.map { name, short, p, s in
    let d = TeamDraft(name: name, short: short, primary: p, secondary: s, world: .magicwood)
    let issues = CreatedTeamRules.issues(d).map(\.rawValue).joined(separator: ",")
    return "issues \(issues.isEmpty ? "-" : issues) \(short.isEmpty ? "-" : short) \(hex(p)) \(hex(s)) \"\(name)\""
}
write("career.txt", text([
    "The created team's rules (spec §2.2).",
    "short <derived short code> \"<name>\" — the code derived from the name.",
    "issues <TeamIssue,…|-> <short|- for empty> <#primary> <#secondary> \"<name>\" — the draft's issues, in order.",
    provenance,
], careerLines))

// MARK: - Quick match

var quick: [String] = []
for player in [TeamKey.mossfoxes, .created] {
    for seed in UInt64(0)..<16 {
        let q = QuickMatch(seed: seed &* 0x9E37_79B9 &+ 7, player: player)
        quick.append("quick 0x\(String(format: "%016llX", seed &* 0x9E37_79B9 &+ 7)) \(player.rawValue) \(q.opponent.rawValue) \(q.world.rawValue)")
    }
}
write("quickmatch.txt", text([
    "Quick match (spec §11.5): seed, the player's team, the drawn opponent and world — from the quick match's own stream.",
    provenance,
], quick))

// MARK: - The save file

let manifest = [
    "fresh.json - - - -",
    "midseason.json season-cup-run.txt 6 shot,pass 0.7 0.35 0.6 0.25 diamond 150.0 2.4",
    "finished.json season-cup-exit.txt end shot,pass,goalie,cones,moving,sleepy,press,scrimmage -",
]
var saves: [String: String] = [:]
for line in manifest {
    let c = try SaveVectorCase(line: line) { name in
        try String(contentsOf: outDir.appendingPathComponent(name), encoding: .utf8)
    }
    saves[c.file] = c.save.encoded()
    write("save/" + c.file, saves[c.file]!)
}
write("save/manifest.txt", text([
    "Save records (spec §15, shared/data/save.toml): <file> <season vector|-> <player matches|end|-> <drills won|-> <board|->,",
    "the board as pressing covering push_up discipline formation period_seconds ball_spin_seconds.",
    "Each platform builds the state and must write the file byte for byte, and read it back to the same state.",
    provenance,
], manifest))

// Refused saves: each a small edit of a valid one, and the refusal expected.
let fresh = saves["fresh.json"]!, mid = saves["midseason.json"]!
func edit(_ s: String, _ from: String, _ to: String) -> String {
    precondition(s.contains(from), "the edit's anchor \(from) is not in the save")
    return s.replacingOccurrences(of: from, with: to)
}

/// The whole `career` member of a save, as written — the anchor for taking the career away.
func careerBlock(_ s: String) -> String {
    let start = s.range(of: "  \"career\": {")!.lowerBound
    let end = s.range(of: "\n  },", range: start..<s.endIndex)!.upperBound
    return String(s[start..<end])
}
let invalid: [(String, [UInt8])] = [
    ("empty.json", []),
    ("truncated.json", Array(fresh.prefix(40).utf8)),
    ("trailing-comma.json", Array(edit(fresh, "\"ball_spin_seconds\": \"0x4000000000000000\"\n", "\"ball_spin_seconds\": \"0x4000000000000000\",\n").utf8)),
    ("not-utf8.json", Array(edit(mid, "\"short\": \"ROK\"", "\"short\": \"R\u{FFFF}OK\"").utf8).map { $0 == 0xEF ? 0xFF : $0 }),
    ("array-root.json", Array("[]\n".utf8)),
    ("no-version.json", Array(edit(fresh, "  \"version\": 1,\n", "").utf8)),
    ("version-2.json", Array(edit(fresh, "\"version\": 1,", "\"version\": 2,").utf8)),
    ("version-0.json", Array(edit(mid, "\"version\": 1,", "\"version\": 0,").utf8)),
    ("version-string.json", Array(edit(fresh, "\"version\": 1,", "\"version\": \"1\",").utf8)),
    ("missing-field.json", Array(edit(fresh, "  \"season\": null,\n", "").utf8)),
    ("unknown-field.json", Array(edit(fresh, "\"discipline\":", "\"coins\": 5,\n    \"discipline\":").utf8)),
    ("duplicate-field.json", Array(edit(fresh, "  \"season\": null,\n", "  \"season\": null,\n  \"season\": null,\n").utf8)),
    ("wrong-type.json", Array(edit(mid, "\"cups\": 0", "\"cups\": \"0\"").utf8)),
    ("fraction.json", Array(edit(mid, "\"cups\": 0", "\"cups\": 0.5").utf8)),
    ("unknown-team.json", Array(edit(mid, "\"teams\": [\n      \"mossfoxes\",", "\"teams\": [\n      \"unicorns\",").utf8)),
    ("bad-seed.json", Array(edit(mid, "\"seed\": \"0x5EA5020020260922\"", "\"seed\": \"0x5EA5\"").utf8)),
    ("tactic-out-of-range.json", Array(edit(mid, "\"pressing\": \"0x3FE6666666666666\"", "\"pressing\": \"0x3FF8000000000000\"").utf8)),
    ("period-not-a-choice.json", Array(edit(mid, "\"period_seconds\": \"0x4062C00000000000\"", "\"period_seconds\": \"0x4062A00000000000\"").utf8)),
    ("season-without-career.json", Array(edit(mid, careerBlock(mid), "  \"career\": null,").utf8)),
    ("created-team-invalid.json", Array(edit(mid, "\"short\": \"ROK\"", "\"short\": \"MOS\"").utf8)),
    ("drill-won-twice.json", Array(edit(mid, "\"shot\",\n      \"pass\"", "\"shot\",\n      \"shot\"").utf8)),
    ("season-zero.json", Array(edit(mid, "\"number\": 1,", "\"number\": 0,").utf8)),
]
var invalidLines: [String] = []
for (name, bytes) in invalid {
    do {
        _ = try SaveRecord.decode(bytes)
        print("NOT REFUSED save/invalid/\(name): the edit left a valid save")
        failures += 1
    } catch {
        invalidLines.append("\(name) \(error)")
    }
    let url = outDir.appendingPathComponent("save/invalid/" + name)
    if let existing = try? Data(contentsOf: url), existing == Data(bytes) { continue }
    if FileManager.default.fileExists(atPath: url.path), !rerecord {
        print("REFUSED save/invalid/\(name): it differs; pass --rerecord with a spec change.")
        failures += 1
        continue
    }
    try! FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    try! Data(bytes).write(to: url)
    print("wrote save/invalid/\(name)")
}
write("save/invalid.txt", text([
    "Refused saves (spec §15): <file in invalid/> <the typed refusal: kind, then offset | version | path [rule]>.",
    "Decoding must fail with exactly this error on both platforms — never yield a save.",
    provenance,
], invalidLines))

exit(failures == 0 ? 0 : 1)
