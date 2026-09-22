import Foundation
import Testing
@testable import SmashCore

/// Spec §4.4: our sin, cos, atan2 and exp stay within 1e-9 (absolute) of the true value on the
/// simulation's input ranges. The platform's libm (≤ 1 ulp) stands in for the true value; its own
/// error is ~1e-16, far below the bound. This is the tolerance test; bit-exactness across the
/// platforms is MathVectorTests' job.
@Suite struct DetMathAccuracyTests {
    static let bound = 1e-9

    /// Max |ours − libm| over n evenly spaced points in [lo, hi] plus n pseudo-random ones.
    static func maxError(_ lo: Double, _ hi: Double, _ n: Int,
                         _ ours: (Double) -> Double, _ ref: (Double) -> Double) -> (Double, Double) {
        var worst = 0.0, at = lo
        var g = SplitMix64(seed: 99)
        for i in 0...n {
            for x in [lo + (hi - lo) * Double(i) / Double(n), lo + (hi - lo) * g.uniform()] {
                let e = abs(ours(x) - ref(x))
                if e > worst { worst = e; at = x }
            }
        }
        return (worst, at)
    }

    @Test func sineAndCosineOnTheSimulationsAngles() {
        for (lo, hi) in [(-4 * Double.pi, 4 * Double.pi), (-300.0, 300.0), (-1e6, 1e6)] {
            let (s, sAt) = Self.maxError(lo, hi, 200_000, DetMath.sin, Foundation.sin)
            let (c, cAt) = Self.maxError(lo, hi, 200_000, DetMath.cos, Foundation.cos)
            print("DetMath.sin max error on [\(lo), \(hi)]: \(s) at \(sAt); cos: \(c) at \(cAt)")
            #expect(s <= Self.bound, "sin error \(s) at \(sAt)")
            #expect(c <= Self.bound, "cos error \(c) at \(cAt)")
        }
    }

    @Test func arctangentOverAllFiniteInputs() {
        var worst = 0.0, at = (0.0, 0.0)
        var g = SplitMix64(seed: 5)
        for i in 0..<400_000 {
            // Magnitudes from 2^-80 to 2^80 on both axes, every sign, plus a dense ring.
            let scaleY = Double(sign: .plus, exponent: Int(g.uniform() * 160) - 80, significand: 1)
            let scaleX = Double(sign: .plus, exponent: Int(g.uniform() * 160) - 80, significand: 1)
            var y = (g.uniform() * 2 - 1) * scaleY
            var x = (g.uniform() * 2 - 1) * scaleX
            if i % 2 == 0 {
                let a = Double(i) / 400_000 * 2 * Double.pi - Double.pi
                y = Foundation.sin(a); x = Foundation.cos(a)
            }
            let e = abs(DetMath.atan2(y, x) - Foundation.atan2(y, x))
            if e > worst { worst = e; at = (y, x) }
        }
        print("DetMath.atan2 max error: \(worst) at \(at)")
        #expect(worst <= Self.bound, "atan2 error \(worst) at \(at)")
    }

    @Test func exponentialOnTheSimulationsRange() {
        let (e, at) = Self.maxError(-50, 5, 400_000, DetMath.exp, Foundation.exp)
        print("DetMath.exp max error on [-50, 5]: \(e) at \(at)")
        #expect(e <= Self.bound, "exp error \(e) at \(at)")
        // Beyond the simulation's range the relative error stays at the ulp level.
        var worstRel = 0.0
        var g = SplitMix64(seed: 11)
        for _ in 0..<100_000 {
            let x = -745 + 1454 * g.uniform()
            let ref = Foundation.exp(x)
            if ref > 1e-300 { worstRel = max(worstRel, abs(DetMath.exp(x) - ref) / ref) }
        }
        print("DetMath.exp max relative error on [-745, 709]: \(worstRel)")
        #expect(worstRel <= 1e-15)
    }

    @Test func edgeCases() {
        #expect(DetMath.sin(0) == 0)
        #expect(DetMath.cos(0) == 1)
        #expect(DetMath.exp(0) == 1)
        #expect(DetMath.exp(710) == .infinity)
        #expect(DetMath.exp(-746) == 0)
        #expect(DetMath.atan2(0, 0) == 0)
        #expect(DetMath.atan2(0, -1) == Double.pi)
        #expect(DetMath.atan2(1, 0) == Double.pi / 2)
        #expect(DetMath.atan2(-1, 0) == -Double.pi / 2)
        #expect(DetMath.length(3, 4) == 5)
    }
}
