// Records shared/vectors/policy/ (spec §4.7, ADR 0010). Not linked by the app.
//
//     cd ios/SmashCore && swift run -c release RecordPolicyVectors
//     cd ios/SmashCore && swift run -c release RecordPolicyVectors --rerecord
//
// The policy's forward pass is simulation-path arithmetic and lives under §4.4 like everything
// else: `+ − × ÷` only, in the order written, never fused. This corpus is what proves iOS and
// Android agree about it, before any trained weights are relied on — because a divergence found
// here costs a day, and the same divergence found after the §7 rewrite costs the corpus.
//
// Each row pins three things, not one: the **observation**, a fold of **every hidden activation**,
// and the **outputs**. The outputs alone would catch almost every divergence, but "almost" is the
// wrong word for a bit-exactness contract, and a fold localises the fault to a layer instead of
// leaving it somewhere in four thousand multiply-accumulates.
//
// The observations are real: harvested from a played match rather than drawn at random, so the
// corpus exercises the value ranges the policy will actually meet — flags that are exactly 0 or 1,
// positions near the boundary clamps, the zeroed padding of an absent roster slot.
import Foundation
import SmashCore

let rerecord = CommandLine.arguments.contains("--rerecord")

let here = URL(fileURLWithPath: #filePath)
let root = here.deletingLastPathComponent().deletingLastPathComponent()
    .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
let dir = root.appendingPathComponent("shared/vectors/policy")
let file = dir.appendingPathComponent("kernel.txt")

try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
if FileManager.default.fileExists(atPath: file.path) && !rerecord {
    print("shared/vectors/policy/kernel.txt exists — pass --rerecord to replace it (spec §4.7)")
    exit(0)
}

func hex(_ v: Double) -> String { String(format: "%016llX", v.bitPattern) }
func hex(_ v: UInt64) -> String { String(format: "%016llX", v) }

/// The recorder's own SplitMix64, for the weights only. The weights are written into the file, so
/// nothing about how they were drawn has to be reproduced on the other platform.
struct Rand {
    var s: UInt64
    mutating func next() -> UInt64 {
        s = s &+ 0x9E37_79B9_7F4A_7C15
        var z = s
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
    mutating func symmetric(_ scale: Double) -> Double {
        (Double(next() >> 11) * 0x1p-53 * 2.0 - 1.0) * scale
    }
}

let nIn = PolicyInputs.count
let nHidden = 32
let nOut = PolicyInputs.outputCount
let dim = PolicyNet.parameterCount(nIn: nIn, nHidden: nHidden, nOut: nOut)

var rand = Rand(s: 0x5A5A_1234_FEED_0001)
// Deliberately wider than a trained net's weights: a divergence that only shows up once an
// activation is large should be caught here rather than after ten thousand iterations of training.
let theta = (0..<dim).map { _ in rand.symmetric(0.35) }
let net = PolicyNet(nIn: nIn, nHidden: nHidden, nOut: nOut, parameters: theta)

// Real observations, from a played match.
var m = Match(MatchSetup(seed: 0x5EED_0000, sport: .field,
                         home: .club(Club.allCases[0]), away: .club(Club.allCases[1]),
                         periodSeconds: 60, orbitPeriod: Tuning.Orbit.demoPeriod,
                         cup: false, control: .automatic))
m.teach()
while m.result == nil && m.ticks < 100_000 { m.tick() }
let tape = m.teaching
guard tape.count >= 256 else { fatalError("RecordPolicyVectors: only \(tape.count) observations harvested") }
// Spread across the match rather than the first few seconds of the first period.
let step = tape.count / 256
let rows = (0..<256).map { tape[$0 * step] }

var out = """
# Smash Hockey 3D — policy kernel golden vector (spec §4.7, ADR 0010).
# The learned policy's forward pass (§7), pinned to the bit across iOS and Android.
# Recorded by ios/SmashCore RecordPolicyVectors (macOS, arm64). Replayed by SmashCoreTests and
# android/core. No tolerance: a single differing bit is a red build.
#
# shape <inputs> <hidden> <outputs>
# p <hex>                          — one parameter, in PolicyNet.parameters order: w0 b0 w1 b1 w2 b2
# r <inputs × hex> <fold> <out × hex>
#     the observation, then the XOR of every hidden activation's bit pattern (both layers, first
#     layer then second, in index order), then the outputs. Every double is the hex of its bits.
shape \(nIn) \(nHidden) \(nOut)

"""
for v in theta { out += "p \(hex(v))\n" }
out += "\n"

for sample in rows {
    let t = net.trace(sample.observation)
    var fold: UInt64 = 0
    for v in t.h0 { fold ^= v.bitPattern }
    for v in t.h1 { fold ^= v.bitPattern }
    out += "r " + sample.observation.map(hex).joined(separator: " ")
        + " " + hex(fold)
        + " " + t.out.map(hex).joined(separator: " ") + "\n"
}

try out.write(to: file, atomically: true, encoding: .utf8)
print("wrote shared/vectors/policy/kernel.txt — \(rows.count) rows, \(dim) parameters, shape \(nIn)→\(nHidden)→\(nHidden)→\(nOut)")
