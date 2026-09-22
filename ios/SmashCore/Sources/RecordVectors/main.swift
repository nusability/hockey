// Records the math golden vectors (spec §4.7) into shared/vectors/math/ from SmashCore:
//
//     cd ios/SmashCore && swift run RecordVectors            # writes missing files; refuses to change one
//     cd ios/SmashCore && swift run RecordVectors --rerecord # overwrites — only with a spec change
//
// Every number is written as the hex of its IEEE-754 bits, so the replay is bit-exact. The
// inputs come from a SplitMix64 stream plus hand-picked edge cases, and are stored in the files:
// the replaying suites never regenerate them.
import Foundation
import SmashCore

let root = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    .deletingLastPathComponent().deletingLastPathComponent()
let outDir = root.appendingPathComponent("shared/vectors/math")
let rerecord = CommandLine.arguments.contains("--rerecord")

func hex(_ v: UInt64) -> String {
    let s = String(v, radix: 16, uppercase: true)
    return String(repeating: "0", count: 16 - s.count) + s
}

func hex(_ d: Double) -> String { hex(d.bitPattern) }

var failures = 0

@MainActor func write(_ name: String, _ header: [String], _ rows: [[String]]) {
    let body = header.map { "# " + $0 }.joined(separator: "\n") + "\n"
        + rows.map { $0.joined(separator: " ") }.joined(separator: "\n") + "\n"
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
    try! FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)
    try! body.write(to: url, atomically: true, encoding: .utf8)
    print("wrote \(name) (\(rows.count) rows)")
}

let provenance = "Recorded by ios/SmashCore RecordVectors (macOS, arm64). Replayed bit-exactly by SmashCoreTests and android/core."

// SplitMix64: the first 1,000 outputs of three seeds.
var rows: [[String]] = []
for seed: UInt64 in [0, 42, 0xDEAD_BEEF_CAFE_F00D] {
    var g = SplitMix64(seed: seed)
    for i in 0..<1000 { rows.append([hex(seed), String(i), hex(g.next())]) }
}
write("splitmix64.txt", ["SplitMix64 (spec §4.3): seed, index, output — the first 1,000 outputs of each seed.", provenance], rows)

rows = []
var u = SplitMix64(seed: 42)
for i in 0..<1000 { rows.append([hex(UInt64(42)), String(i), hex(u.uniform())]) }
write("uniform.txt", ["uniform() (spec §4.3): seed, index, the double's bits.", provenance], rows)

rows = []
for s in [1.6, 0.8, 0.5] {
    var g = SplitMix64(seed: 7)
    for i in 0..<200 { rows.append([hex(UInt64(7)), hex(s), String(i), hex(g.noise(s))]) }
}
write("noise.txt", ["noise(s) (spec §4.3): seed, s, index, result — a fresh stream per s.", provenance], rows)

// Inputs.
var src = SplitMix64(seed: 2026)
@MainActor func uniform(_ lo: Double, _ hi: Double) -> Double { lo + (hi - lo) * src.uniform() }
let pi = Double.pi

var angles: [Double] = [0, -0.0, 1e-300, -1e-300, 1e-10, 0.5, -0.5, 1, -1]
for k in -16...16 { angles.append(Double(k) * pi / 4) }
for k in -8...8 {   // either side of every reduction boundary (k + ½)·π/2
    let b = (Double(k) + 0.5) * (pi / 2)
    angles += [b.nextDown, b, b.nextUp]
}
for _ in 0..<2000 { angles.append(uniform(-4 * pi, 4 * pi)) }
for _ in 0..<500 { angles.append(uniform(-300, 300)) }
for _ in 0..<100 { angles.append(uniform(-1e6, 1e6)) }
write("sin.txt", ["DetMath.sin (spec §4.4): x, sin x.", provenance], angles.map { [hex($0), hex(DetMath.sin($0))] })
write("cos.txt", ["DetMath.cos (spec §4.4): x, cos x.", provenance], angles.map { [hex($0), hex(DetMath.cos($0))] })

var pairs: [(Double, Double)] = [(0, 0), (-0.0, 0), (0, -0.0), (-0.0, -0.0), (0, 1), (0, -1), (1, 0), (-1, 0),
                                 (1, 1), (-1, -1), (1, -1), (-1, 1), (7, 16), (11, 16), (-7, -16), (11, -16),
                                 (1e-300, 1), (1, 1e-300), (1e300, -1e-300), (-5e-324, 1), (3, 4)]
for _ in 0..<2000 { pairs.append((uniform(-50, 50), uniform(-50, 50))) }
for _ in 0..<1000 {
    let y = uniform(-1, 1) * Double(sign: .plus, exponent: Int(uniform(-60, 60)), significand: 1)
    let x = uniform(-1, 1) * Double(sign: .plus, exponent: Int(uniform(-60, 60)), significand: 1)
    pairs.append((y, x))
}
write("atan2.txt", ["DetMath.atan2 (spec §4.4): y, x, atan2(y, x).", provenance],
      pairs.map { [hex($0.0), hex($0.1), hex(DetMath.atan2($0.0, $0.1))] })

var exps: [Double] = [0, -0.0, 1, -1, 5, -50, 0.5 * .ulpOfOne, -1e-300, 709.78, 709.79, -745.1, -745.2, -708.5, 700]
for k in -72...7 { exps.append(Double(k) * 0.6931471805599453) }
for _ in 0..<2000 { exps.append(uniform(-50, 5)) }
for _ in 0..<200 { exps.append(uniform(-745, 709)) }
write("exp.txt", ["DetMath.exp (spec §4.4): x, e^x.", provenance], exps.map { [hex($0), hex(DetMath.exp($0))] })

var lens: [(Double, Double)] = [(0, 0), (3, 4), (-3, -4), (1e-200, 1e-200), (1e150, 1e150)]
for _ in 0..<500 { lens.append((uniform(-60, 60), uniform(-60, 60))) }
write("length.txt", ["DetMath.length (spec §4.4): x, z, sqrt(x·x + z·z).", provenance],
      lens.map { [hex($0.0), hex($0.1), hex(DetMath.length($0.0, $0.1))] })

exit(failures == 0 ? 0 : 1)
