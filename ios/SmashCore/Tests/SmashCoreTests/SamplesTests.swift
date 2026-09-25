import Testing
@testable import SmashCore

/// The soak meters' running summary (A0): constant memory, constant time, and quantiles that agree
/// with the sorted array it replaced to within one bucket.
@Suite struct SamplesTests {
    @Test func nothingMeasuredIsNotAnError() {
        let s = Samples()
        #expect(s.count == 0 && s.mean == 0 && s.rate == 0 && s.peak == 0)
        #expect(s.quantile(0) == 0 && s.quantile(0.5) == 0 && s.quantile(1) == 0)
        #expect(s.summary() == "n=0")
    }

    @Test func countMeanAndPeakAreExact() {
        var s = Samples()
        for ms in [16.0, 17.0, 100.0, 4.0] { s.add(ms) }
        #expect(s.count == 4)
        #expect(s.sum == 137)
        #expect(s.mean == 137.0 / 4)
        #expect(s.peak == 100)
        #expect(s.rate == 1000 / (137.0 / 4))
    }

    /// The contract that matters: the same rank a sorted array would pick, within one bucket.
    @Test func quantilesAgreeWithTheSortedArrayTheyReplaced() {
        var s = Samples()
        var sorted: [Double] = []
        var x = 7.0
        for _ in 0..<5000 {
            // A spread with a long tail, the shape a frame-time stream actually has.
            x = (x * 48271).truncatingRemainder(dividingBy: 2147483647)
            let ms = 8 + (x / 2147483647) * 40
            s.add(ms)
            sorted.append(ms)
        }
        sorted.sort()
        for q in [0.0, 0.5, 0.95, 0.99, 1.0] {
            let expected = sorted[Int(Double(sorted.count - 1) * q)]
            #expect(abs(s.quantile(q) - expected) <= Samples.step,
                    "q=\(q): \(s.quantile(q)) vs \(expected)")
        }
        #expect(s.peak == sorted.last!)
    }

    @Test func theRankIsTheSameOneASortedArrayPicks() {
        var s = Samples()
        // Ten samples, one per bucket, so the bucket the rank lands in is unambiguous.
        for i in 1...10 { s.add(Double(i) * Samples.step) }
        // floor((10 − 1) × 0.5) = 4 ⇒ the fifth smallest ⇒ bucket 5, reported by its middle.
        #expect(s.quantile(0.5) == 5.5 * Samples.step)
        #expect(s.quantile(0) == 1.5 * Samples.step)
        // The top bucket's middle is above the sample in it, so the cap at `peak` bites.
        #expect(s.quantile(1) == s.peak)
    }

    @Test func aSampleBeyondTheBucketsStillReportsItsPeak() {
        var s = Samples()
        s.add(16)
        s.add(9_999)            // far past 256 ms: the overflow bucket
        #expect(s.peak == 9_999)
        #expect(s.quantile(1) == 9_999)
        #expect(s.quantile(0) == 64.5 * Samples.step)   // 16 ms ⇒ bucket 64
        #expect(s.count == 2 && s.sum == 10_015)
    }

    @Test func aClockThatRanBackwardsDoesNotPoisonTheSummary() {
        var s = Samples()
        s.add(.nan)             // ignored outright
        s.add(.infinity)        // ignored outright
        #expect(s.count == 0)
        s.add(-5)               // the first bucket, where a backwards clock belongs
        s.add(16)
        #expect(s.count == 2 && s.sum == 11 && s.peak == 16)
        #expect(s.mean.isFinite)
    }

    @Test func aWindowStartsOverWithoutForgettingHowBigItIs() {
        var s = Samples()
        for _ in 0..<1000 { s.add(16.7) }
        s.reset()
        #expect(s.count == 0 && s.sum == 0 && s.peak == 0 && s.quantile(0.5) == 0)
        s.add(33.4)
        #expect(s.count == 1 && s.peak == 33.4)
    }

    /// The bug this type exists to kill (SMASH-58): a million samples cost what a thousand cost.
    ///
    /// The wall-clock bound is the regression guard. It is absurdly generous — the histogram does
    /// this in about 0.15 s — but the array-and-sort this replaced would need hours for a million,
    /// so putting that back fails here instead of merely being slow in the player's hands.
    @Test func aMillionSamplesCostWhatAThousandCost() {
        var thousand = Samples()
        var million = Samples()
        for _ in 0..<1_000 { thousand.add(16.7) }
        let started = ContinuousClock.now
        for _ in 0..<1_000_000 { million.add(16.7) }
        let took = ContinuousClock.now - started
        #expect(took < .seconds(10), "a million samples took \(took)")
        #expect(thousand.quantile(0.95) == million.quantile(0.95))
        #expect(thousand.peak == million.peak)
        #expect(million.count == 1_000_000)
    }
}
