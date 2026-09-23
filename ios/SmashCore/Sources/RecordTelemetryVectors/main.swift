// Records the love-dialog golden vector (spec §17, §4.7) into shared/vectors/telemetry/:
//
//     cd ios/SmashCore && swift run RecordTelemetryVectors            # writes missing files; refuses to change one
//     cd ios/SmashCore && swift run RecordTelemetryVectors --rerecord # overwrites — only with a spec change
//
// The input lines (the clock, the matches, the settled screens, the answers) are declared here and
// written into the file; the replaying suites read them from the file and never from this program.
import Foundation
import SmashCore

let root = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    .deletingLastPathComponent().deletingLastPathComponent()
let outDir = root.appendingPathComponent("shared/vectors/telemetry")
let rerecord = CommandLine.arguments.contains("--rerecord")
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

// MARK: - The clock

// A fixed instant to reason from: 2026-03-01 12:00:00 UTC. Real epoch milliseconds, because the
// numbers in the file should be recognisable as instants rather than as small integers.
let start: Int64 = 1_772_366_400_000
let day: Int64 = 86_400_000
let cooldown = LovePolicy.cooldownMillis

// A match is 4 × 120 s by default (§12): 480 000 ms. The last third begins at 320 000.
let matchMillis = 480_000
let late = 400_000, early = 100_000

func goals(_ items: String) -> [LoveMatch.Goal] {
    items.isEmpty ? [] : items.split(separator: ",").map {
        let p = $0.split(separator: "@")
        return LoveMatch.Goal(mine: p[0] == "f", atMillis: Int(p[1])!)
    }
}

// MARK: - The script
//
// Every rule of §17.2–§17.4 appears here at least once, and the ones with a number appear at their
// boundary: the cooldown to the millisecond either side, the twentieth match, the last third's first
// millisecond, a clock that runs backwards, a record we lost, a yes that ends the asking.
//
// Each instant is named after the thing that fixed it, because every boundary below is relative to a
// presentation and not to the start.

var steps: [LoveScript.Step] = []
let minute: Int64 = 60_000

/// A one-goal win whose winning goal falls at `winner`: hard-fought, if the count allows it.
func oneGoalWin(_ winner: Int) -> LoveMatch {
    LoveMatch(goals: goals("a@\(early),f@200000,f@\(winner)"), durationMillis: matchMillis)
}

// 1. A brand-new device. A three-goal stroll is not a story, and a settled screen stays quiet.
let installed = start
steps.append(.launch(now: installed, lost: false))
steps.append(.match(now: installed + minute, match: LoveMatch(goals: goals("f@\(early),f@200000,f@300000"),
                                                             durationMillis: matchMillis)))
steps.append(.settle(now: installed + 2 * minute, remote: .on))

// 2. A one-goal win with the winning goal late — the second match ever, so the hard-fought branch is
//    not open and nothing is armed.
steps.append(.match(now: installed + 10 * minute, match: oneGoalWin(late)))
steps.append(.settle(now: installed + 11 * minute, remote: .on))

// 3. The cup, won on the third match ever: a trophy arms at any count.
steps.append(.match(now: installed + 20 * minute, match: LoveMatch(goals: goals("a@\(early),f@200000,f@\(late)"),
                                                                  durationMillis: matchMillis, wonCup: true)))
// 4. The kill switch: unread stays silent rather than racing the flag, off stays silent, on asks.
steps.append(.settle(now: installed + 21 * minute, remote: .unread))
steps.append(.settle(now: installed + 22 * minute, remote: .off))
let asked1 = installed + 23 * minute
steps.append(.settle(now: asked1, remote: .on))
steps.append(.bytes(file: "asked.json"))
// The scrim is the third answer, and it is the "ask me later": nothing durable changes.
steps.append(.answer(now: asked1 + minute, answer: .dismissed))

// 5. The league, won the next day — armed, and then held for the whole cooldown, to the millisecond.
steps.append(.match(now: asked1 + day, match: LoveMatch(goals: goals("f@\(late)"), durationMillis: matchMillis,
                                                        wonLeague: true)))
steps.append(.settle(now: asked1 + cooldown - 1, remote: .on))
let asked2 = asked1 + cooldown
steps.append(.settle(now: asked2, remote: .on))

// 6. A no is not a never: it is the cooldown that rations, so the record keeps only the showing.
steps.append(.answer(now: asked2 + 1000, answer: .negative))
steps.append(.bytes(file: "refused.json"))

// 7. A clock that has run backwards — a restored backup, a corrected device clock — reads as no time
//    passed at all, never as a long time, so the prompt is held instead of burnt.
steps.append(.match(now: asked2 + 2000, match: LoveMatch(goals: goals("f@\(late)"),
                                                         durationMillis: matchMillis, wonCup: true)))
steps.append(.settle(now: installed, remote: .on))

// 8. Nineteen more one-goal late wins. Each is hard-fought and each arms nothing until the twentieth
//    match played, which is where the branch opens.
for i in 0..<19 {
    steps.append(.match(now: asked2 + 3000 + Int64(i) * minute, match: oneGoalWin(late)))
}

// 9. The last third, both sides of its first millisecond — with the player ahead the whole way, so the
//    clock is the only thing that can arm it and the comeback branch cannot mask the answer. Then the
//    same boundary on a match that also came from behind, where the comeback arms it either way.
//    (`armed` already holds from step 8 — a prompt earned is not un-earned by a later match.)
let third = 2 * matchMillis / 3

/// A one-goal win the player led throughout, the winning goal at `winner`.
func neverBehind(_ winner: Int) -> LoveMatch {
    LoveMatch(goals: goals("f@\(early),a@200000,f@\(winner)"), durationMillis: matchMillis)
}
steps.append(.match(now: asked2 + 28 * minute, match: neverBehind(third - 1)))
steps.append(.match(now: asked2 + 29 * minute, match: neverBehind(third)))
steps.append(.match(now: asked2 + 30 * minute, match: oneGoalWin(third - 1)))
steps.append(.match(now: asked2 + 31 * minute, match: oneGoalWin(third)))

// 10. A comeback won by three goals: coming back arms it whether the last goal was late or not. Then
//     a defeat and a draw, which arm nothing at any count.
steps.append(.match(now: asked2 + 32 * minute,
                    match: LoveMatch(goals: goals("a@\(early),a@120000,f@200000,f@300000,f@400000,f@460000,f@470000"),
                                     durationMillis: matchMillis)))
steps.append(.match(now: asked2 + 33 * minute, match: LoveMatch(goals: goals("a@200000,a@300000,f@\(late)"),
                                                                durationMillis: matchMillis)))
steps.append(.match(now: asked2 + 34 * minute, match: LoveMatch(goals: goals("a@200000,f@\(late)"),
                                                                durationMillis: matchMillis)))

// 11. The yes, once the second cooldown is served — and then never again, not on the next cup.
let asked3 = asked2 + cooldown
steps.append(.settle(now: asked3, remote: .on))
steps.append(.answer(now: asked3 + 1000, answer: .positive))
steps.append(.bytes(file: "loved.json"))
steps.append(.match(now: asked3 + cooldown, match: LoveMatch(goals: goals("f@\(late)"),
                                                             durationMillis: matchMillis, wonCup: true)))
steps.append(.settle(now: asked3 + 2 * cooldown, remote: .on))

// 12. A record we could not read is replaced as if the prompt had just been shown. The yes is gone
//     with the bytes — nothing can bring it back — so what matters is that the replacement serves a
//     full cooldown before the game says a word.
let lost = asked3 + 3 * cooldown
steps.append(.launch(now: lost, lost: true))
steps.append(.bytes(file: "lost.json"))
steps.append(.match(now: lost + 1000, match: LoveMatch(goals: goals("f@\(late)"), durationMillis: matchMillis,
                                                       wonCup: true)))
steps.append(.settle(now: lost + 2000, remote: .on))
steps.append(.settle(now: lost + cooldown, remote: .on))

// MARK: - Writing it out

let header = """
# Love-dialog golden vector (spec §17, §4.7): the arming rule and the rationing, step by step, with
# the clock as an input. Both platforms recompute every output line from the input lines.
# Input lines:
#   launch <now> <fresh|lost>                        — the record was read, or lost and replaced (§17.1)
#   match <now> <duration> <cup|league|-> <goal…>    — a finished match; a goal is f@<ms> or a@<ms>, in order
#   settle <now> <unread|on|off>                     — a settled screen (§17.3), the kill switch in that state
#   answer <now> <positive|negative|dismissed>       — the answer to the panel that is up
#   bytes <file>                                     — the record's canonical JSON is that file, byte for byte
# Output lines:
#   result <for>-<against> <won|drew|lost> <trailed|-> <winning goal ms|-> <late|-> <hard|->
#   trigger <cup|league|hardFought|->                — what the match armed
#   verdict <ask|saidYes|switchOff|switchUnread|notArmed|cooldown>
#   state <matches> <installed at> <last asked at|-> <yes|no> <armed|->
# Recorded by ios/SmashCore RecordTelemetryVectors (macOS, arm64). Replayed exactly by SmashCoreTests and android/core.
"""

// Recording is a replay whose pinned records are written out rather than compared.
var pinned: [(String, String)] = []
let lines = try LoveScript(steps: steps).run { file, record in
    pinned.append((file, record.encoded()))
}

for (file, body) in pinned { write(file, body) }
write("love.txt", header + "\n" + lines.joined(separator: "\n") + "\n")

// MARK: - Refused records
//
// A device record we cannot read is replaced rather than shown (§17.1), but *which* refusal it is
// still has to be the same on both platforms — a record one side reads and the other rejects would
// silently give the two phones different rationing.

let asked = pinned.first { $0.0 == "asked.json" }!.1

func edit(_ s: String, _ from: String, _ to: String) -> String {
    precondition(s.contains(from), "the edit's anchor \(from) is not in the record")
    return s.replacingOccurrences(of: from, with: to)
}

let invalid: [(String, [UInt8])] = [
    ("empty.json", []),
    ("array-root.json", Array("[]\n".utf8)),
    ("no-version.json", Array(edit(asked, "  \"version\": 1,\n", "").utf8)),
    ("version-2.json", Array(edit(asked, "\"version\": 1,", "\"version\": 2,").utf8)),
    ("missing-field.json", Array(edit(asked, "  \"last_asked_at\": 1772367780000,\n", "").utf8)),
    ("unknown-field.json", Array(edit(asked, "  \"answered_positively\"", "  \"install_id\": \"x\",\n  \"answered_positively\"").utf8)),
    ("duplicate-field.json", Array(edit(asked, "  \"matches_played\": 3,\n", "  \"matches_played\": 3,\n  \"matches_played\": 3,\n").utf8)),
    ("instant-string.json", Array(edit(asked, "\"installed_at\": 1772366400000", "\"installed_at\": \"1772366400000\"").utf8)),
    ("instant-fraction.json", Array(edit(asked, "\"installed_at\": 1772366400000", "\"installed_at\": 1772366400000.5").utf8)),
    ("instant-too-large.json", Array(edit(asked, "\"installed_at\": 1772366400000", "\"installed_at\": 9007199254740993").utf8)),
    ("negative-instant.json", Array(edit(asked, "\"installed_at\": 1772366400000", "\"installed_at\": -1").utf8)),
    ("negative-count.json", Array(edit(asked, "\"matches_played\": 3", "\"matches_played\": -1").utf8)),
    ("answered-without-asking.json", Array(edit(asked, "\"last_asked_at\": 1772367780000,\n  \"answered_positively\": false",
                                                "\"last_asked_at\": null,\n  \"answered_positively\": true").utf8)),
]
var invalidLines: [String] = []
for (name, bytes) in invalid {
    do {
        _ = try DeviceRecord.decode(bytes)
        print("NOT REFUSED invalid/\(name): the edit left a valid record")
        failures += 1
    } catch {
        invalidLines.append("\(name) \(error)")
    }
    let url = outDir.appendingPathComponent("invalid/" + name)
    if let existing = try? Data(contentsOf: url), existing == Data(bytes) { continue }
    if FileManager.default.fileExists(atPath: url.path), !rerecord {
        print("REFUSED invalid/\(name): it differs; pass --rerecord with a spec change.")
        failures += 1
        continue
    }
    try! FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    try! Data(bytes).write(to: url)
    print("wrote invalid/\(name)")
}
write("invalid.txt", """
# Refused device records (spec §17.1): <file in invalid/> <the typed refusal: kind, then offset | version | path [rule]>.
# Decoding must fail with exactly this error on both platforms — the record is then replaced, never read, and never a screen.
# Recorded by ios/SmashCore RecordTelemetryVectors (macOS, arm64). Replayed exactly by SmashCoreTests and android/core.

""".replacingOccurrences(of: "\n\n", with: "\n") + invalidLines.joined(separator: "\n") + "\n")

exit(failures == 0 ? 0 : 1)
