import Foundation
import Testing
@testable import SmashCore

/// Spec §4.7 and ADR 0010: the policy kernel golden vector in `shared/vectors/policy/`, replayed.
/// No tolerance — a single differing bit is a red build, here and on Android.
///
/// iOS records this corpus, so a green run here means "the recorder and the kernel still agree",
/// which catches a change to `DetPolicy` that was never re-recorded. Android replaying the same
/// file is what makes it a *cross-platform* guarantee.
struct PolicyVectorTests {

    static func vectorFile() throws -> String {
        let path = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("shared/vectors/policy/kernel.txt").path
        #expect(FileManager.default.fileExists(atPath: path),
                "shared/vectors/policy/kernel.txt is missing — record it with `swift run -c release RecordPolicyVectors`")
        return try String(contentsOfFile: path, encoding: .utf8)
    }

    static func bits(_ token: Substring) -> UInt64 { UInt64(token, radix: 16)! }
    static func double(_ token: Substring) -> Double { Double(bitPattern: bits(token)) }
    static func hex(_ v: UInt64) -> String { String(format: "%016llX", v) }

    @Test func theKernelReproducesTheRecordedVector() throws {
        let text = try PolicyVectorTests.vectorFile()
        let lines = text.split(separator: "\n").filter { !$0.isEmpty && !$0.hasPrefix("#") }

        let shape = lines.first { $0.hasPrefix("shape ") }!.split(separator: " ")
        let nIn = Int(shape[1])!, nHidden = Int(shape[2])!, nOut = Int(shape[3])!

        let parameters = lines.filter { $0.hasPrefix("p ") }
            .map { PolicyVectorTests.double($0.split(separator: " ")[1]) }
        #expect(parameters.count == PolicyNet.parameterCount(nIn: nIn, nHidden: nHidden, nOut: nOut))
        let net = PolicyNet(nIn: nIn, nHidden: nHidden, nOut: nOut, parameters: parameters)

        let rows = lines.filter { $0.hasPrefix("r ") }
        #expect(!rows.isEmpty)

        var bad: [String] = []
        for (index, line) in rows.enumerated() {
            let f = line.split(separator: " ")
            #expect(f.count == 1 + nIn + 1 + nOut, "row \(index) has \(f.count) fields")
            let observation = (0..<nIn).map { PolicyVectorTests.double(f[1 + $0]) }
            let t = net.trace(observation)

            var fold: UInt64 = 0
            for v in t.h0 { fold ^= v.bitPattern }
            for v in t.h1 { fold ^= v.bitPattern }
            if fold != PolicyVectorTests.bits(f[1 + nIn]) {
                bad.append("row \(index): hidden fold expected \(f[1 + nIn]), got \(PolicyVectorTests.hex(fold))")
                continue
            }
            for o in 0..<nOut where t.out[o].bitPattern != PolicyVectorTests.bits(f[1 + nIn + 1 + o]) {
                bad.append("row \(index) output \(o): expected \(f[1 + nIn + 1 + o]), got \(PolicyVectorTests.hex(t.out[o].bitPattern))")
            }
        }
        #expect(bad.isEmpty, "\(bad.count) of \(rows.count) rows differ, first: \(bad.prefix(3))")
    }

    /// The accumulation order is the contract, so three ways of writing the same dot product must
    /// agree. These are the forms an optimiser is most tempted to fuse or reassociate; if `swiftc`
    /// ever starts doing either, this is the cheapest place to find out.
    @Test func threeWaysOfWritingTheLoopAgree() {
        let n = 2000
        var rand = SplitMix64(seed: 0x1234_5678_9ABC_DEF0)
        let w = (0..<n).map { _ in rand.uniform() * 2.0 - 1.0 }
        let x = (0..<n).map { _ in rand.uniform() * 2.0 - 1.0 }

        var plain = 0.0
        for i in 0..<n { plain = plain + w[i] * x[i] }

        var compound = 0.0
        for i in 0..<n { compound += w[i] * x[i] }

        var unrolled = 0.0
        var i = 0
        while i + 4 <= n {
            unrolled = unrolled + w[i] * x[i]
            unrolled = unrolled + w[i + 1] * x[i + 1]
            unrolled = unrolled + w[i + 2] * x[i + 2]
            unrolled = unrolled + w[i + 3] * x[i + 3]
            i += 4
        }
        while i < n { unrolled = unrolled + w[i] * x[i]; i += 1 }

        #expect(plain.bitPattern == compound.bitPattern, "`+=` must not differ from `s = s + …`")
        #expect(plain.bitPattern == unrolled.bitPattern, "unrolling must not reassociate")
    }
}
