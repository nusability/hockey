/// The simulation's math (spec §4.4): the same result, to the bit, as Android's
/// `in.nann.smashhockey.core.math.DetMath`.
///
/// Only operations IEEE-754 defines exactly are used — `+ − × ÷`, `squareRoot()`, and the exact
/// integral rounding `rounded(.down)` — each in the order written here and in the Kotlin twin.
/// Swift never contracts `a * b + c` into a fused multiply-add: it emits no `contract` fast-math
/// flag, so LLVM keeps `fmul` and `fadd` separate at every optimization level (checked on the
/// arm64 assembly of this file; see shared/README.md). Nothing here is `@inlinable`, so callers
/// always run this module's code.
///
/// The constants come from shared/data/math.toml (MathConstants, generated). Accuracy — absolute
/// error ≤ 1e-9 on the simulation's ranges — is asserted by DetMathAccuracyTests; bit-exactness
/// across platforms by the golden vectors in shared/vectors/math/.
public enum DetMath {
    private typealias T = MathConstants.Trig
    private typealias A = MathConstants.Atan
    private typealias E = MathConstants.Exp

    // MARK: Length

    /// `sqrt(x² + z²)`, never `hypot` (spec §4.4).
    public static func length(_ x: Double, _ z: Double) -> Double {
        let xx = x * x
        let zz = z * z
        return (xx + zz).squareRoot()
    }

    // MARK: Sine and cosine

    /// sin x for |x| ≤ 1e6. Beyond that, or for a non-finite x, it fails loud.
    public static func sin(_ x: Double) -> Double {
        let (quadrant, r) = reduce(x)
        switch quadrant {
        case 0: return sinKernel(r)
        case 1: return cosKernel(r)
        case 2: return -sinKernel(r)
        default: return -cosKernel(r)
        }
    }

    /// cos x for |x| ≤ 1e6. Beyond that, or for a non-finite x, it fails loud.
    public static func cos(_ x: Double) -> Double {
        let (quadrant, r) = reduce(x)
        switch quadrant {
        case 0: return cosKernel(r)
        case 1: return -sinKernel(r)
        case 2: return -cosKernel(r)
        default: return sinKernel(r)
        }
    }

    /// x = k·π/2 + r with |r| ≲ π/4; returns (k mod 4, r). Cody–Waite with a three-part π/2:
    /// k·p1 and k·p2 are exact because p1 and p2 carry 33 bits and |k| < 2^20.
    private static func reduce(_ x: Double) -> (Int, Double) {
        precondition(x.isFinite && x.magnitude <= T.maxInput,
                     "DetMath: sin/cos argument \(x) is outside ±1e6 (spec §4.4); wrap angles first")
        let scaled = x * T.invPio2
        let k = (scaled + 0.5).rounded(.down)
        let r1 = x - k * T.pio21
        let r2 = r1 - k * T.pio22
        let r = r2 - k * T.pio23
        return (Int(k) & 3, r)
    }

    /// sin r ≈ r + (r·z)·(s1 + z·(s2 + z·(s3 + z·(s4 + z·(s5 + z·s6))))), z = r².
    private static func sinKernel(_ r: Double) -> Double {
        let z = r * r
        var p = T.sin6
        p = T.sin5 + z * p
        p = T.sin4 + z * p
        p = T.sin3 + z * p
        p = T.sin2 + z * p
        p = T.sin1 + z * p
        let rz = r * z
        return r + rz * p
    }

    /// cos r ≈ (1 − 0.5·z) + (z·z)·(c1 + z·(c2 + z·(c3 + z·(c4 + z·(c5 + z·c6))))), z = r².
    private static func cosKernel(_ r: Double) -> Double {
        let z = r * r
        var p = T.cos6
        p = T.cos5 + z * p
        p = T.cos4 + z * p
        p = T.cos3 + z * p
        p = T.cos2 + z * p
        p = T.cos1 + z * p
        let head = 1.0 - 0.5 * z
        let zz = z * z
        return head + zz * p
    }

    // MARK: Arctangent

    /// The angle of (x, y) in [−π, π], for finite x and y (a non-finite one fails loud).
    /// atan2(0, 0) is 0; the sign of a zero is not consulted, so atan2(−0, −1) is +π.
    public static func atan2(_ y: Double, _ x: Double) -> Double {
        precondition(x.isFinite && y.isFinite, "DetMath: atan2(\(y), \(x)) needs finite arguments (spec §4.4)")
        let ax = x.magnitude
        let ay = y.magnitude
        if ax == 0 && ay == 0 { return 0 }
        var a: Double
        if ay <= ax {
            a = atanUnit(ay / ax)
        } else {
            let inner = atanUnit(ax / ay)
            a = (A.pio2Hi - inner) + A.pio2Lo
        }
        if x < 0 {
            a = (A.piHi - a) + A.piLo
        }
        return y < 0 ? -a : a
    }

    /// atan t for t in [0, 1], reduced to |u| < 7/16 around 0, ½ or 1 (fdlibm's split).
    private static func atanUnit(_ t: Double) -> Double {
        if t < A.splitLow {
            return t - t * atanSeries(t)
        }
        if t < A.splitHigh {
            let num = 2.0 * t - 1.0
            let u = num / (2.0 + t)
            return A.halfHi - ((u * atanSeries(u) - A.halfLo) - u)
        }
        let u = (t - 1.0) / (t + 1.0)
        return A.oneHi - ((u * atanSeries(u) - A.oneLo) - u)
    }

    /// s1 + s2 with z = u², w = z²: s1 = z·(a0 + w·(a2 + … + w·a10)), s2 = w·(a1 + w·(a3 + … + w·a9)).
    private static func atanSeries(_ u: Double) -> Double {
        let z = u * u
        let w = z * z
        var odd = A.a10
        odd = A.a8 + w * odd
        odd = A.a6 + w * odd
        odd = A.a4 + w * odd
        odd = A.a2 + w * odd
        odd = A.a0 + w * odd
        var even = A.a9
        even = A.a7 + w * even
        even = A.a5 + w * even
        even = A.a3 + w * even
        even = A.a1 + w * even
        let s1 = z * odd
        let s2 = w * even
        return s1 + s2
    }

    // MARK: Exponential

    /// e^x for any non-NaN x: +∞ above 709.78, 0 below −745.13 (a NaN fails loud).
    public static func exp(_ x: Double) -> Double {
        precondition(!x.isNaN, "DetMath: exp(NaN) (spec §4.4)")
        if x > E.overflow { return .infinity }
        if x < E.underflow { return 0 }
        let scaled = x * E.invLn2
        let k = (scaled + 0.5).rounded(.down)
        let hi = x - k * E.ln2Hi
        let lo = k * E.ln2Lo
        let r = hi - lo
        let z = r * r
        var p = E.p5
        p = E.p4 + z * p
        p = E.p3 + z * p
        p = E.p2 + z * p
        p = E.p1 + z * p
        let c = r - z * p
        let rc = r * c
        let q = rc / (2.0 - c)
        let y = 1.0 - ((lo - q) - hi)
        return scale(y, Int(k))
    }

    /// y · 2^k, exact except where the result is subnormal.
    private static func scale(_ y: Double, _ k: Int) -> Double {
        if k > 1023 { return (y * 2.0) * twoTo(k - 1) }
        if k < -1022 { return (y * twoTo(k + 1000)) * twoTo(-1000) }
        return y * twoTo(k)
    }

    /// 2^n for −1022 ≤ n ≤ 1023, built from its bits.
    private static func twoTo(_ n: Int) -> Double {
        Double(bitPattern: UInt64(1023 + n) << 52)
    }
}
