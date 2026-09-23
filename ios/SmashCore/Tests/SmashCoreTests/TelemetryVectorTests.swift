import Foundation
import Testing
@testable import SmashCore

/// Spec §4.7 for the love dialog and the device record (§17): `shared/vectors/telemetry/`, recorded
/// by RecordTelemetryVectors and replayed here and by android/core, line for line and byte for byte.
/// No tolerance — the policy's clock arithmetic is integer milliseconds precisely so that there is
/// none to grant.
@Suite struct TelemetryVectorTests {
    static let dir = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("shared/vectors/telemetry")

    static func text(_ name: String) throws -> String {
        let url = dir.appendingPathComponent(name)
        guard let s = try? String(contentsOf: url, encoding: .utf8) else {
            throw VectorError("vector file \(url.path) is missing — record it with `swift run RecordTelemetryVectors`")
        }
        return s
    }

    static func lines(_ name: String) throws -> [String] {
        try text(name).split(separator: "\n").filter { !$0.hasPrefix("#") }.map(String.init)
    }

    /// Every step of the script, recomputed from its input lines: the trigger a match armed, the
    /// verdict on a settled screen, and the record after each one.
    @Test func theWholeLoveScriptReplays() throws {
        let expected = try Self.lines("love.txt")
        var pinned = 0
        let got = try LoveScript.parse(try Self.text("love.txt")).run { file, record in
            pinned += 1
            let bytes = try Self.text(file)
            #expect(record.encoded() == bytes, "\(file): the record's canonical JSON differs")
            // The pinned bytes must read back as the very record that wrote them.
            #expect(try DeviceRecord.decode(bytes) == record, "\(file): reading it back gave another record")
        }
        #expect(pinned == 4)
        for i in 0..<max(expected.count, got.count) where i >= expected.count || i >= got.count || expected[i] != got[i] {
            let want = i < expected.count ? expected[i] : "<end>"
            let have = i < got.count ? got[i] : "<end>"
            Issue.record("line \(i + 1): expected \(want), got \(have)")
            break
        }
        #expect(expected.count == got.count)
    }

    /// The thresholds are the declared ones (`rules.toml [love]`), not a second copy of them, and the
    /// cooldown is ninety days of absolute time rather than ninety calendar days. Android asserts the
    /// same two numbers, so a table edit that reached one platform and not the other turns one red.
    @Test func theThresholdsAreTheDeclaredOnes() {
        #expect(LovePolicy.cooldownMillis == 90 * 86_400_000)
        #expect(LovePolicy.hardFoughtMatches == 20)
    }

    /// Every refused record is refused with exactly the recorded, typed error — never read.
    @Test func brokenDeviceRecordsAreRefusedTyped() throws {
        let cases = try Self.lines("invalid.txt")
        #expect(cases.count == 15)
        for line in cases {
            let file = String(line.prefix { $0 != " " })
            let expected = String(line.dropFirst(file.count + 1))
            let bytes = [UInt8](try Data(contentsOf: Self.dir.appendingPathComponent("invalid/" + file)))
            do {
                _ = try DeviceRecord.decode(bytes)
                Issue.record("\(file) was read; expected \(expected)")
            } catch {
                #expect(error.description == expected, "\(file)")
            }
        }
    }
}
