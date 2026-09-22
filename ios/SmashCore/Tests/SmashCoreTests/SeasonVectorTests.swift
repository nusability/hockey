import Foundation
import Testing
@testable import SmashCore

/// Spec §4.7 for the season, the career and the save (§2.2, §11, §15): shared/vectors/season/,
/// recorded by RecordSeasonVectors and replayed here and by android/core, line for line and byte
/// for byte. No tolerance.
@Suite struct SeasonVectorTests {
    static let dir = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("shared/vectors/season")

    static func text(_ name: String) throws -> String {
        let url = dir.appendingPathComponent(name)
        guard let s = try? String(contentsOf: url, encoding: .utf8) else {
            throw VectorError("vector file \(url.path) is missing — record it with `swift run RecordSeasonVectors`")
        }
        return s
    }

    static func lines(_ name: String) throws -> [String] {
        try text(name).split(separator: "\n").filter { !$0.hasPrefix("#") }.map(String.init)
    }

    /// The first line where two transcripts part, or nil.
    static func firstDifference(_ a: [String], _ b: [String]) -> String? {
        for i in 0..<max(a.count, b.count) where i >= a.count || i >= b.count || a[i] != b[i] {
            return "line \(i + 1): expected \(i < a.count ? a[i] : "<end>"), got \(i < b.count ? b[i] : "<end>")"
        }
        return nil
    }

    @Test(arguments: ["season-club.txt", "season-created.txt"])
    func aWholeSeasonReplays(_ name: String) throws {
        let expected = try Self.lines(name)
        let got = try SeasonScript.parse(try Self.text(name)).run().lines
        #expect(Self.firstDifference(expected, got) == nil, "\(name): \(Self.firstDifference(expected, got) ?? "")")
    }

    /// A season written to the save and read back after any player match goes on with exactly the
    /// draws it would have made (§15: the stream position is kept).
    @Test(arguments: ["season-club.txt", "season-created.txt"])
    func aReloadedSeasonContinuesTheSameDraws(_ name: String) throws {
        let expected = try Self.lines(name)
        let script = try SeasonScript.parse(try Self.text(name))
        for k in 1...script.entries.count {
            let got = try script.run(reloadAfter: k).lines
            #expect(Self.firstDifference(expected, got) == nil, "reloaded after \(k): \(Self.firstDifference(expected, got) ?? "")")
        }
    }

    @Test func simulatedResultsReplay() throws {
        let lines = try Self.lines("simulated.txt")
        var rng = SplitMix64(seed: UInt64(lines[0].dropFirst("seed 0x".count), radix: 16)!)
        let sims = lines.dropFirst().dropLast()
        #expect(sims.count == 486)
        for line in sims {
            let w = line.split(separator: " ").map(String.init)
            let s = SeasonRecord.simulate(home: Int(w[1])!, away: Int(w[2])!, cup: w[3] == "cup", &rng)
            #expect("\(s.home) \(s.away) \(s.overtime ? "ot" : "-")" == w[4...6].joined(separator: " "), "\(line)")
        }
        #expect(lines.last == "stream 0x" + SaveJSON.hex(rng.state, digits: 16))
    }

    @Test func theCreatedTeamsRulesReplay() throws {
        var checked = 0
        for line in try Self.lines("career.txt") {
            let name = String(line[line.index(after: line.firstIndex(of: "\"")!)..<line.lastIndex(of: "\"")!])
            let w = line.split(separator: " ").map(String.init)
            switch w[0] {
            case "short":
                #expect(CreatedTeamRules.suggestedShortCode(for: name) == w[1], "\(line)")
            case "issues":
                let draft = TeamDraft(name: name, short: w[2] == "-" ? "" : w[2], primary: UInt32(w[3].dropFirst(), radix: 16)!,
                                      secondary: UInt32(w[4].dropFirst(), radix: 16)!, world: .magicwood)
                let got = CreatedTeamRules.issues(draft).map(\.rawValue).joined(separator: ",")
                #expect((got.isEmpty ? "-" : got) == w[1], "\(line)")
            default:
                Issue.record("unknown line \(line)")
            }
            checked += 1
        }
        #expect(checked == 34)
    }

    @Test func quickMatchesReplay() throws {
        let lines = try Self.lines("quickmatch.txt")
        #expect(lines.count == 48)
        for line in lines {
            let w = line.split(separator: " ").map(String.init)
            let q = QuickMatch(seed: UInt64(w[1].dropFirst(2), radix: 16)!, player: TeamKey(rawValue: w[2])!)
            #expect(q.opponent.rawValue == w[3] && q.world.rawValue == w[4], "\(line)")
        }
    }

    /// Both platforms build each state and must write the file byte for byte; reading it back
    /// yields the same state.
    @Test func saveFilesAreWrittenAndReadExactly() throws {
        let manifest = try Self.lines("save/manifest.txt")
        #expect(manifest.count == 3)
        for line in manifest {
            let c = try SaveVectorCase(line: line) { try Self.text($0) }
            let file = try Self.text("save/" + c.file)
            #expect(c.save.encoded() == file, "\(c.file): the encoding differs")
            let read = try SaveRecord.decode(file)
            #expect(read == c.save, "\(c.file): reading it back gave another state")
            #expect(read.encoded() == file)
        }
    }

    /// Every refused save is refused with exactly the recorded, typed error — never read.
    @Test func brokenSavesAreRefusedTyped() throws {
        let cases = try Self.lines("save/invalid.txt")
        #expect(cases.count == 21)
        for line in cases {
            let file = String(line.prefix { $0 != " " })
            let expected = String(line.dropFirst(file.count + 1))
            let bytes = [UInt8](try Data(contentsOf: Self.dir.appendingPathComponent("save/invalid/" + file)))
            do {
                _ = try SaveRecord.decode(bytes)
                Issue.record("\(file) was read; expected \(expected)")
            } catch {
                #expect(error.description == expected, "\(file)")
            }
        }
    }
}
