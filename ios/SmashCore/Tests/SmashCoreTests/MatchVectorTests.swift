import Foundation
import Testing
@testable import SmashCore

/// Spec §4.7: the match golden vectors in shared/vectors/match/, replayed to the bit — every
/// sampled state and every event, line by line. Android's core module replays the same files; a
/// mismatch on either side is a red build. No tolerance.
@Suite struct MatchVectorTests {
    static let directory = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("shared/vectors/match")

    static let files = [
        "cup-overtime.txt", "demo-field.txt", "demo-ice.txt", "drill1-first-shot.txt", "drill2-give-and-go.txt",
        "drill5-moving-cones.txt", "drill8-scrimmage.txt", "match-player-tape.txt",
    ]

    static func load(_ name: String) throws -> (vector: MatchVector, recorded: [String]) {
        let url = directory.appendingPathComponent(name)
        guard let text = try? String(contentsOf: url, encoding: .utf8) else {
            throw VectorError("vector file \(url.path) is missing — record it with `swift run -c release RecordMatchVectors`")
        }
        return try MatchVector.parse(text)
    }

    @Test(arguments: files) func replays(_ name: String) throws {
        let (vector, recorded) = try Self.load(name)
        #expect(!recorded.isEmpty)
        let replayed = vector.run()
        let firstDifference = zip(recorded, replayed).enumerated().first { $0.element.0 != $0.element.1 }
        if let (i, (want, got)) = firstDifference {
            Issue.record("\(name): body line \(i + 1) differs\n  recorded: \(want.prefix(400))\n  replayed: \(got.prefix(400))")
        }
        #expect(recorded.count == replayed.count, "\(name): body length")
    }

    @Test func everyVectorFileIsReplayed() throws {
        let names = try FileManager.default.contentsOfDirectory(atPath: Self.directory.path).filter { $0.hasSuffix(".txt") }.sorted()
        #expect(names == Self.files)
    }

    /// The vectors say what they claim to: drill 1 is won, drill 2 scores only with assists, the
    /// cup match reaches sudden death, the player's tape passes through every branch of §5.3.
    @Test func theVectorsCoverWhatTheyClaim() throws {
        func events(_ name: String) throws -> [String] { try Self.load(name).recorded.filter { $0.hasPrefix("e ") } }
        #expect(try events("drill1-first-shot.txt").last == "e 1855 end won")
        let giveAndGo = try events("drill2-give-and-go.txt").filter { $0.contains(" goal ") }
        #expect(giveAndGo.count == 3 && giveAndGo.allSatisfy { !$0.hasSuffix(" - 0") })
        #expect(try events("drill5-moving-cones.txt").contains { $0.contains(" block ") })
        #expect(try Self.load("cup-overtime.txt").recorded.contains { $0.hasPrefix("s ") && $0.split(separator: " ")[4] == "1" })
        #expect(try events("drill8-scrimmage.txt").contains { $0.contains(" goal 1 ") })
        let tape = try Self.load("match-player-tape.txt").vector
        var match = tape.makeMatch()
        var seen: Set<String> = []
        var next = 0
        while match.state != .ended {
            while next < tape.inputs.count && tape.inputs[next].tick == match.ticks {
                if !tape.inputs[next].down { seen.insert("\(match.previewLift())") }
                match.hold(tape.inputs[next].down)
                next += 1
            }
            match.tick()
        }
        #expect(seen.isSuperset(of: ["snap", "lateGrace", "pending", "unassisted"]))
    }
}
