import Testing
@testable import SmashCore

/// Spec §4.3, checked against the published SplitMix64 reference (Steele, Lea & Flood 2014;
/// Vigna's splitmix64.c) rather than against our own recording.
@Suite struct SplitMix64Tests {
    @Test func matchesTheReferenceSequenceForSeedZero() {
        var g = SplitMix64(seed: 0)
        #expect(g.next() == 0xE220_A839_7B1D_CDAF)
        #expect(g.next() == 0x6E78_9E6A_A1B9_65F4)
        #expect(g.next() == 0x06C4_5D18_8009_454F)
    }

    @Test func uniformIsTheTop53BitsScaled() {
        var a = SplitMix64(seed: 123)
        var b = SplitMix64(seed: 123)
        for _ in 0..<1000 {
            let u = a.uniform()
            #expect(u == Double(b.next() >> 11) / 9_007_199_254_740_992.0)
            #expect(u >= 0 && u < 1)
        }
    }

    @Test func noiseSumsThreeDrawsLeftToRight() {
        var a = SplitMix64(seed: 9)
        var b = SplitMix64(seed: 9)
        let n = a.noise(1.6)
        let u1 = b.uniform(), u2 = b.uniform(), u3 = b.uniform()
        #expect(n == (u1 + u2 + u3 - 1.5) * 1.6)
    }

    @Test func aStoredStateResumesTheStream() {
        var a = SplitMix64(seed: 77)
        _ = a.next(); _ = a.next()
        var b = SplitMix64(state: a.state)
        #expect(a.next() == b.next())
    }
}
