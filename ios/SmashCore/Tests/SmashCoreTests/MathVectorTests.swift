import Foundation
import Testing
@testable import SmashCore

/// Spec §4.7: the math golden vectors in shared/vectors/math/, replayed to the bit. Android's
/// core module replays the same files; a mismatch on either side is a red build. No tolerance.
@Suite struct MathVectorTests {
    /// shared/vectors/math/<name>, as rows of whitespace-separated tokens (comments dropped).
    static func rows(_ name: String, arity: Int) throws -> [[String]] {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
        let url = root.appendingPathComponent("shared/vectors/math/\(name)")
        guard let text = try? String(contentsOf: url, encoding: .utf8) else {
            throw VectorError("vector file \(url.path) is missing — record it with `swift run RecordVectors`")
        }
        let rows = text.split(separator: "\n").filter { !$0.hasPrefix("#") && !$0.isEmpty }
            .map { $0.split(separator: " ").map(String.init) }
        for row in rows where row.count != arity {
            throw VectorError("\(name): row \(row) has \(row.count) fields, expected \(arity)")
        }
        guard !rows.isEmpty else { throw VectorError("\(name) has no rows") }
        return rows
    }

    static func bits(_ token: String) -> UInt64 { UInt64(token, radix: 16)! }
    static func double(_ token: String) -> Double { Double(bitPattern: bits(token)) }

    /// Replays `rows`, returning the rows whose recomputed last field differs from the recorded one.
    static func mismatches(_ rows: [[String]], _ compute: ([String]) -> UInt64) -> [String] {
        rows.compactMap { row in
            let got = compute(row)
            return got == bits(row.last!) ? nil
                : "\(row.dropLast().joined(separator: " ")): expected \(row.last!), got \(String(got, radix: 16, uppercase: true))"
        }
    }

    @Test func splitMix64() throws {
        let rows = try Self.rows("splitmix64.txt", arity: 3)
        var streams: [UInt64: SplitMix64] = [:]
        let bad = Self.mismatches(rows) { row in
            let seed = Self.bits(row[0])
            var g = streams[seed] ?? SplitMix64(seed: seed)
            let out = g.next()
            streams[seed] = g
            return out
        }
        #expect(rows.count == 3000)
        #expect(bad.isEmpty, "\(bad.count) mismatches, first: \(bad.prefix(3))")
    }

    @Test func uniform() throws {
        let rows = try Self.rows("uniform.txt", arity: 3)
        var g = SplitMix64(seed: Self.bits(rows[0][0]))
        let bad = Self.mismatches(rows) { _ in g.uniform().bitPattern }
        #expect(bad.isEmpty, "\(bad.count) mismatches, first: \(bad.prefix(3))")
    }

    @Test func noise() throws {
        let rows = try Self.rows("noise.txt", arity: 4)
        var streams: [UInt64: SplitMix64] = [:]
        let bad = Self.mismatches(rows) { row in
            let s = Self.bits(row[1])
            var g = streams[s] ?? SplitMix64(seed: Self.bits(row[0]))
            let out = g.noise(Double(bitPattern: s))
            streams[s] = g
            return out.bitPattern
        }
        #expect(bad.isEmpty, "\(bad.count) mismatches, first: \(bad.prefix(3))")
    }

    @Test func sine() throws {
        let bad = Self.mismatches(try Self.rows("sin.txt", arity: 2)) { DetMath.sin(Self.double($0[0])).bitPattern }
        #expect(bad.isEmpty, "\(bad.count) mismatches, first: \(bad.prefix(3))")
    }

    @Test func cosine() throws {
        let bad = Self.mismatches(try Self.rows("cos.txt", arity: 2)) { DetMath.cos(Self.double($0[0])).bitPattern }
        #expect(bad.isEmpty, "\(bad.count) mismatches, first: \(bad.prefix(3))")
    }

    @Test func arctangent() throws {
        let bad = Self.mismatches(try Self.rows("atan2.txt", arity: 3)) {
            DetMath.atan2(Self.double($0[0]), Self.double($0[1])).bitPattern
        }
        #expect(bad.isEmpty, "\(bad.count) mismatches, first: \(bad.prefix(3))")
    }

    @Test func exponential() throws {
        let bad = Self.mismatches(try Self.rows("exp.txt", arity: 2)) { DetMath.exp(Self.double($0[0])).bitPattern }
        #expect(bad.isEmpty, "\(bad.count) mismatches, first: \(bad.prefix(3))")
    }

    @Test func length() throws {
        let bad = Self.mismatches(try Self.rows("length.txt", arity: 3)) {
            DetMath.length(Self.double($0[0]), Self.double($0[1])).bitPattern
        }
        #expect(bad.isEmpty, "\(bad.count) mismatches, first: \(bad.prefix(3))")
    }
}

struct VectorError: Error, CustomStringConvertible {
    let description: String
    init(_ description: String) { self.description = description }
}
