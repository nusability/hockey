import Testing
@testable import SmashCore

/// The 3D UI's layout maths (spec §16): text width → slab width → where an element sits, measured
/// from the shared font's real glyph metrics. Android's `TextLayoutTest` checks the same list with
/// the same numbers — that is the point of the file: the two platforms mesh the lettering with
/// different engines, so the measuring has to come from here or they drift.
@Suite struct TextLayoutTests {
    /// Lilita One, as its own tables state it.
    @Test func theFontIsTheSharedOne() {
        #expect(FontMetrics.unitsPerEm == 1000)
        #expect(FontMetrics.capHeight == 704)
        #expect(FontMetrics.ascent == 923)
        #expect(FontMetrics.descent == -220)
    }

    /// `height` is the cap height, so an em is a little taller than the height asked for.
    @Test func anEmIsTheCapHeightScaledUp() {
        #expect(abs(TextLayout.em(0.704) - 1) < 1e-12)
        #expect(abs(TextLayout.em(0.1) - 0.1 * 1000 / 704) < 1e-12)
    }

    /// The strings the owner saw sitting wrong — English and German, the German ones with an
    /// umlaut and a middle dot, which is exactly what an ink-measured layout got wrong.
    @Test func theStringsThatBreakMeasureTheirAdvance() {
        #expect(abs(TextLayout.width("ANPFIFF", height: 0.13) - 0.13 * 3718 / 704) < 1e-9)
        #expect(abs(TextLayout.width("PLAY MATCH", height: 0.13) - 0.13 * 5732 / 704) < 1e-9)
        #expect(abs(TextLayout.width("ZURÜCKSETZEN", height: 0.1) - 0.1 * 6820 / 704) < 1e-9)
        #expect(abs(TextLayout.width("SAISON 1 · SPIELTAG 5", height: 0.1) - 0.1 * 9717 / 704) < 1e-9)
        #expect(abs(TextLayout.width("RESET", height: 0.1) - 0.1 * 2609 / 704) < 1e-9)
        #expect(TextLayout.width("", height: 0.1) == 0)
    }

    /// Width is linear in the height and additive over the string: a slab may be sized from a
    /// caption and a caption shrunk to a slab without either measurement disagreeing.
    @Test func widthIsLinearAndAdditive() {
        let a = TextLayout.width("ANPFIFF", height: 0.1)
        #expect(abs(TextLayout.width("ANPFIFF", height: 0.2) - 2 * a) < 1e-9)
        let parts = TextLayout.width("PLAY", height: 0.1) + TextLayout.width(" ", height: 0.1)
            + TextLayout.width("MATCH", height: 0.1)
        #expect(abs(TextLayout.width("PLAY MATCH", height: 0.1) - parts) < 1e-9)
    }

    /// A character the font does not map is laid out as its .notdef box, never as nothing.
    @Test func anUnmappedCharacterStillTakesRoom() {
        #expect(FontMetrics.advance(Unicode.Scalar(0xE000)!) == FontMetrics.notdefAdvance)
        #expect(TextLayout.width("\u{E000}", height: 0.1) > 0)
    }

    /// The line box is the font's, so it does not move with the string: "ZURÜCKSETZEN" sits on the
    /// same line as "ANPFIFF" even though its umlaut reaches higher than any cap. Measuring the
    /// ink instead is what dropped a German caption off its slab.
    @Test func theLineDoesNotMoveWithTheString() {
        #expect(abs(TextLayout.lineTop(0.1) - 0.1 * 923 / 704) < 1e-9)
        #expect(abs(TextLayout.lineBottom(0.1) + 0.1 * 220 / 704) < 1e-9)
        #expect(abs(TextLayout.centreY(0.1) - 0.1 * 351.5 / 704) < 1e-9)
        // Twice the height, twice the anchor: nothing else enters the sum.
        #expect(abs(TextLayout.centreY(0.2) - 2 * TextLayout.centreY(0.1)) < 1e-9)
    }

    /// A caption keeps a margin either side of its slab, and a long word shrinks into what is left.
    @Test func aCaptionFitsItsSlab() {
        #expect(abs(TextLayout.room(slabWidth: 0.78, textHeight: 0.1) - 0.66) < 1e-12)
        #expect(TextLayout.room(slabWidth: 0.1, textHeight: 0.5) == 0)
        // The coach board's Reset button: "RESET" fits as it is, "ZURÜCKSETZEN" has to shrink.
        let room = TextLayout.room(slabWidth: 0.78, textHeight: 0.1)
        #expect(TextLayout.fit(TextLayout.width("RESET", height: 0.1), room) == 1)
        let german = TextLayout.fit(TextLayout.width("ZURÜCKSETZEN", height: 0.1), room)
        #expect(abs(german - 0.6813) < 1e-4)
        // Shrunk, it is exactly the room it was given — the caption ends on the slab's margin.
        #expect(abs(german * TextLayout.width("ZURÜCKSETZEN", height: 0.1) - room) < 1e-12)
        // Nothing ever grows, and no limit means no change.
        #expect(TextLayout.fit(0.2, nil) == 1)
        #expect(TextLayout.fit(0.2, 0.9) == 1)
    }

    /// Where lettering sits against the point it is aligned to — a cup tie's team code hangs off
    /// the left of its card, its goals off the right.
    @Test func alignmentIsMeasuredFromTheSameWidth() {
        #expect(TextLayout.alignX(.centre, width: 0.4) == 0)
        #expect(TextLayout.alignX(.leading, width: 0.4) == 0.2)
        #expect(TextLayout.alignX(.trailing, width: 0.4) == -0.2)
    }

    /// Running text breaks in the same places on both phones, spaces measured by the font.
    @Test func paragraphsWrapTheSameWay() {
        let lines = TextLayout.wrap("HOLD TO AIM AND RELEASE TO PASS", height: 0.075, width: 0.5)
        #expect(lines.joined(separator: " ") == "HOLD TO AIM AND RELEASE TO PASS")
        for line in lines { #expect(TextLayout.width(line, height: 0.075) <= 0.5) }
        // A single word wider than the line still gets its own line rather than vanishing.
        #expect(TextLayout.wrap("ZURÜCKSETZEN", height: 0.1, width: 0.1) == ["ZURÜCKSETZEN"])
        #expect(TextLayout.wrap("", height: 0.1, width: 1).isEmpty)
    }
}
