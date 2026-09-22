package `in`.nann.smashhockey.core.feel

import `in`.nann.smashhockey.core.generated.FontMetrics
import kotlin.math.abs
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * The 3D UI's layout maths (spec §16): text width → slab width → where an element sits, measured
 * from the shared font's real glyph metrics. iOS's `TextLayoutTests` checks the same list with the
 * same numbers — that is the point of the file: the two platforms mesh the lettering with
 * different engines, so the measuring has to come from here or they drift.
 */
class TextLayoutTest {
    private fun near(expected: Double, actual: Double, tolerance: Double = 1e-9) =
        assertTrue("expected $expected, was $actual", abs(expected - actual) < tolerance)

    /** Lilita One, as its own tables state it. */
    @Test fun theFontIsTheSharedOne() {
        assertEquals(1000, FontMetrics.UNITS_PER_EM)
        assertEquals(704, FontMetrics.CAP_HEIGHT)
        assertEquals(923, FontMetrics.ASCENT)
        assertEquals(-220, FontMetrics.DESCENT)
    }

    /** `height` is the cap height, so an em is a little taller than the height asked for. */
    @Test fun anEmIsTheCapHeightScaledUp() {
        near(1.0, TextLayout.em(0.704), 1e-12)
        near(0.1 * 1000 / 704, TextLayout.em(0.1), 1e-12)
    }

    /**
     * The strings the owner saw sitting wrong — English and German, the German ones with an
     * umlaut and a middle dot, which is exactly what an ink-measured layout got wrong.
     */
    @Test fun theStringsThatBreakMeasureTheirAdvance() {
        near(0.13 * 3718 / 704, TextLayout.width("ANPFIFF", 0.13))
        near(0.13 * 5732 / 704, TextLayout.width("PLAY MATCH", 0.13))
        near(0.1 * 6820 / 704, TextLayout.width("ZURÜCKSETZEN", 0.1))
        near(0.1 * 9717 / 704, TextLayout.width("SAISON 1 · SPIELTAG 5", 0.1))
        near(0.1 * 2609 / 704, TextLayout.width("RESET", 0.1))
        assertEquals(0.0, TextLayout.width("", 0.1), 0.0)
    }

    /**
     * Width is linear in the height and additive over the string: a slab may be sized from a
     * caption and a caption shrunk to a slab without either measurement disagreeing.
     */
    @Test fun widthIsLinearAndAdditive() {
        val a = TextLayout.width("ANPFIFF", 0.1)
        near(2 * a, TextLayout.width("ANPFIFF", 0.2))
        val parts = TextLayout.width("PLAY", 0.1) + TextLayout.width(" ", 0.1) + TextLayout.width("MATCH", 0.1)
        near(parts, TextLayout.width("PLAY MATCH", 0.1))
    }

    /** A character the font does not map is laid out as its .notdef box, never as nothing. */
    @Test fun anUnmappedCharacterStillTakesRoom() {
        assertEquals(FontMetrics.NOTDEF_ADVANCE, FontMetrics.advance(0xE000))
        assertTrue(TextLayout.width("\uE000", 0.1) > 0)
    }

    /**
     * The line box is the font's, so it does not move with the string: "ZURÜCKSETZEN" sits on the
     * same line as "ANPFIFF" even though its umlaut reaches higher than any cap. Measuring the
     * ink instead is what dropped a German caption off its slab.
     */
    @Test fun theLineDoesNotMoveWithTheString() {
        near(0.1 * 923 / 704, TextLayout.lineTop(0.1))
        near(-0.1 * 220 / 704, TextLayout.lineBottom(0.1))
        near(0.1 * 351.5 / 704, TextLayout.centreY(0.1))
        near(2 * TextLayout.centreY(0.1), TextLayout.centreY(0.2))
    }

    /** A caption keeps a margin either side of its slab, and a long word shrinks into what is left. */
    @Test fun aCaptionFitsItsSlab() {
        near(0.66, TextLayout.room(0.78, 0.1), 1e-12)
        assertEquals(0.0, TextLayout.room(0.1, 0.5), 0.0)
        // The coach board's Reset button: "RESET" fits as it is, "ZURÜCKSETZEN" has to shrink.
        val room = TextLayout.room(0.78, 0.1)
        assertEquals(1.0, TextLayout.fit(TextLayout.width("RESET", 0.1), room), 0.0)
        val german = TextLayout.fit(TextLayout.width("ZURÜCKSETZEN", 0.1), room)
        near(0.6813, german, 1e-4)
        // Shrunk, it is exactly the room it was given — the caption ends on the slab's margin.
        near(room, german * TextLayout.width("ZURÜCKSETZEN", 0.1), 1e-12)
        // Nothing ever grows, and no limit means no change.
        assertEquals(1.0, TextLayout.fit(0.2, null), 0.0)
        assertEquals(1.0, TextLayout.fit(0.2, 0.9), 0.0)
    }

    /**
     * Where lettering sits against the point it is aligned to — a cup tie's team code hangs off
     * the left of its card, its goals off the right.
     */
    @Test fun alignmentIsMeasuredFromTheSameWidth() {
        assertEquals(0.0, TextLayout.alignX(TextLayout.Align.CENTRE, 0.4), 0.0)
        assertEquals(0.2, TextLayout.alignX(TextLayout.Align.LEADING, 0.4), 1e-12)
        assertEquals(-0.2, TextLayout.alignX(TextLayout.Align.TRAILING, 0.4), 1e-12)
    }

    /** Running text breaks in the same places on both phones, spaces measured by the font. */
    @Test fun paragraphsWrapTheSameWay() {
        val lines = TextLayout.wrap("HOLD TO AIM AND RELEASE TO PASS", 0.075, 0.5)
        assertEquals("HOLD TO AIM AND RELEASE TO PASS", lines.joinToString(" "))
        for (line in lines) assertTrue(TextLayout.width(line, 0.075) <= 0.5)
        // A single word wider than the line still gets its own line rather than vanishing.
        assertEquals(listOf("ZURÜCKSETZEN"), TextLayout.wrap("ZURÜCKSETZEN", 0.1, 0.1))
        assertTrue(TextLayout.wrap("", 0.1, 1.0).isEmpty())
    }
}
