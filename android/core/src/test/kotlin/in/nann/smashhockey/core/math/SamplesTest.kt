package `in`.nann.smashhockey.core.math

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import kotlin.math.abs

/**
 * The soak meters' running summary (A0): constant memory, constant time, and quantiles that agree
 * with the sorted array it replaced to within one bucket. The twin of iOS's `SamplesTests.swift`.
 */
class SamplesTest {
    @Test fun nothingMeasuredIsNotAnError() {
        val s = Samples()
        assertEquals(0, s.count)
        assertEquals(0.0, s.mean, 0.0)
        assertEquals(0.0, s.rate, 0.0)
        assertEquals(0.0, s.peak, 0.0)
        assertEquals(0.0, s.quantile(0.0), 0.0)
        assertEquals(0.0, s.quantile(0.5), 0.0)
        assertEquals(0.0, s.quantile(1.0), 0.0)
        assertEquals("n=0", s.summary())
    }

    @Test fun countMeanAndPeakAreExact() {
        val s = Samples()
        for (ms in listOf(16.0, 17.0, 100.0, 4.0)) s.add(ms)
        assertEquals(4, s.count)
        assertEquals(137.0, s.sum, 0.0)
        assertEquals(137.0 / 4, s.mean, 0.0)
        assertEquals(100.0, s.peak, 0.0)
        assertEquals(1000.0 / (137.0 / 4), s.rate, 0.0)
    }

    /** The contract that matters: the same rank a sorted array would pick, within one bucket. */
    @Test fun quantilesAgreeWithTheSortedArrayTheyReplaced() {
        val s = Samples()
        val sorted = ArrayList<Double>()
        var x = 7.0
        repeat(5000) {
            // A spread with a long tail, the shape a frame-time stream actually has.
            x = (x * 48271) % 2147483647
            val ms = 8 + (x / 2147483647) * 40
            s.add(ms)
            sorted += ms
        }
        sorted.sort()
        for (q in listOf(0.0, 0.5, 0.95, 0.99, 1.0)) {
            val expected = sorted[((sorted.size - 1) * q).toInt()]
            assertTrue("q=$q: ${s.quantile(q)} vs $expected",
                abs(s.quantile(q) - expected) <= Samples.STEP)
        }
        assertEquals(sorted.last(), s.peak, 0.0)
    }

    @Test fun theRankIsTheSameOneASortedArrayPicks() {
        val s = Samples()
        // Ten samples, one per bucket, so the bucket the rank lands in is unambiguous.
        for (i in 1..10) s.add(i * Samples.STEP)
        // floor((10 - 1) * 0.5) = 4 ⇒ the fifth smallest ⇒ bucket 5, reported by its middle.
        assertEquals(5.5 * Samples.STEP, s.quantile(0.5), 0.0)
        assertEquals(1.5 * Samples.STEP, s.quantile(0.0), 0.0)
        // The top bucket's middle is above the sample in it, so the cap at `peak` bites.
        assertEquals(s.peak, s.quantile(1.0), 0.0)
    }

    @Test fun aSampleBeyondTheBucketsStillReportsItsPeak() {
        val s = Samples()
        s.add(16.0)
        s.add(9999.0)           // far past 256 ms: the overflow bucket
        assertEquals(9999.0, s.peak, 0.0)
        assertEquals(9999.0, s.quantile(1.0), 0.0)
        assertEquals(64.5 * Samples.STEP, s.quantile(0.0), 0.0)   // 16 ms ⇒ bucket 64
        assertEquals(2, s.count)
        assertEquals(10015.0, s.sum, 0.0)
    }

    @Test fun aClockThatRanBackwardsDoesNotPoisonTheSummary() {
        val s = Samples()
        s.add(Double.NaN)               // ignored outright
        s.add(Double.POSITIVE_INFINITY) // ignored outright
        assertEquals(0, s.count)
        s.add(-5.0)                     // the first bucket, where a backwards clock belongs
        s.add(16.0)
        assertEquals(2, s.count)
        assertEquals(11.0, s.sum, 0.0)
        assertEquals(16.0, s.peak, 0.0)
        assertTrue(s.mean.isFinite())
    }

    @Test fun aWindowStartsOverWithoutForgettingHowBigItIs() {
        val s = Samples()
        repeat(1000) { s.add(16.7) }
        s.reset()
        assertEquals(0, s.count)
        assertEquals(0.0, s.sum, 0.0)
        assertEquals(0.0, s.peak, 0.0)
        assertEquals(0.0, s.quantile(0.5), 0.0)
        s.add(33.4)
        assertEquals(1, s.count)
        assertEquals(33.4, s.peak, 0.0)
    }

    /**
     * The bug this type exists to kill (SMASH-58): a million samples cost what a thousand cost.
     *
     * The wall-clock bound is the regression guard. It is absurdly generous — the histogram does
     * this in well under a second — but the array-and-sort this replaced would need hours for a
     * million, so putting that back fails here instead of merely being slow in the player's hands.
     */
    @Test fun aMillionSamplesCostWhatAThousandCost() {
        val thousand = Samples()
        val million = Samples()
        repeat(1_000) { thousand.add(16.7) }
        val started = System.nanoTime()
        repeat(1_000_000) { million.add(16.7) }
        val tookMs = (System.nanoTime() - started) / 1e6
        assertTrue("a million samples took $tookMs ms", tookMs < 10_000)
        assertEquals(thousand.quantile(0.95), million.quantile(0.95), 0.0)
        assertEquals(thousand.peak, million.peak, 0.0)
        assertEquals(1_000_000, million.count)
    }
}
