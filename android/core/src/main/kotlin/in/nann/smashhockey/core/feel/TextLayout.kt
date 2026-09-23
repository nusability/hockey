package `in`.nann.smashhockey.core.feel

import `in`.nann.smashhockey.core.generated.FontMetrics

/**
 * Where the 3D UI's lettering sits (spec §16) — the one computation both apps lay a screen out
 * with, the twin of iOS's `SmashCore/Feel/TextLayout.swift`.
 *
 * The kit's lettering is extruded from one font file on both platforms, but each platform meshes
 * it with a different engine (ADR 0005), and the box an engine reports around the result is its
 * own: RealityKit's `generateText` bounds and Android's triangulated outline bounds are not the
 * same rectangle. A layout measured off that box therefore came out differently on the two
 * phones — a long German word sat off its slab, a lone digit was centred on its ink rather than
 * on its advance. So the measuring is done here instead, from the font's own metrics
 * ([FontMetrics]): the mesher draws the glyphs, this decides where they go.
 *
 * Everything is in the design frame's metres, and `height` always means the **cap height** of the
 * lettering — the same thing the kit's `textHeight` tokens mean.
 */
object TextLayout {
    /** How a piece of lettering is placed against the point it is aligned to. */
    enum class Align { CENTRE, LEADING, TRAILING }

    /** The side margin a caption keeps on a slab, as a share of its own cap height. */
    const val MARGIN_PER_HEIGHT = 0.6

    /** One em, in metres, for lettering of cap height [height]. */
    fun em(height: Double): Double = height * FontMetrics.UNITS_PER_EM / FontMetrics.CAP_HEIGHT

    /**
     * How wide [text] is as lettering of cap height [height]: the sum of its glyphs' advances.
     * This is the width a slab has to hold and the width an alignment is measured from.
     */
    fun width(text: String, height: Double): Double {
        var units = 0
        var i = 0
        while (i < text.length) {
            val cp = text.codePointAt(i)
            units += FontMetrics.advance(cp)
            i += Character.charCount(cp)
        }
        return units * em(height) / FontMetrics.UNITS_PER_EM
    }

    /**
     * The line's top and bottom above the baseline, in metres — the box the lettering is placed
     * by. It depends on the font and the height, never on which characters the string has, so a
     * word with an umlaut sits on the same line as one without.
     */
    fun lineTop(height: Double): Double = FontMetrics.ASCENT * em(height) / FontMetrics.UNITS_PER_EM

    fun lineBottom(height: Double): Double = FontMetrics.DESCENT * em(height) / FontMetrics.UNITS_PER_EM

    /**
     * How far above the baseline a piece of lettering is anchored: the middle of the line box.
     * A label placed at y sits with this point on y.
     */
    fun centreY(height: Double): Double = (lineTop(height) + lineBottom(height)) / 2

    /**
     * The scale a piece of lettering is shrunk by to fit [maxWidth] — 1 when it already fits, and
     * 1 when there is no limit. A long word in a short slot shrinks; nothing ever grows.
     */
    fun fit(natural: Double, maxWidth: Double?): Double {
        if (maxWidth == null || maxWidth <= 0.0 || natural <= maxWidth) return 1.0
        return maxWidth / natural
    }

    /**
     * The x offset from the alignment point to the lettering's centre, for lettering [width] wide
     * (already shrunk by [fit]).
     */
    fun alignX(align: Align, width: Double): Double = when (align) {
        Align.CENTRE -> 0.0
        Align.LEADING -> width / 2
        Align.TRAILING -> -width / 2
    }

    /**
     * The width a caption may take on a slab [slabWidth] wide: a margin of six tenths of the
     * lettering's height is kept either side, so a button's word never runs into its rounding.
     */
    fun room(slabWidth: Double, textHeight: Double): Double =
        maxOf(0.0, slabWidth - 2 * textHeight * MARGIN_PER_HEIGHT)

    /**
     * Running text wrapped greedily into lines no wider than [maxWidth] — as many words on a line
     * as fit, never breaking one. Measured with the font's own spaces, so both apps break a
     * help card in the same places.
     */
    fun wrap(text: String, height: Double, maxWidth: Double): List<String> {
        val space = width(" ", height)
        val lines = ArrayList<String>()
        var line = ""
        var lineWidth = 0.0
        for (word in text.split(' ')) {
            if (word.isEmpty()) continue
            val w = width(word, height)
            when {
                line.isEmpty() -> { line = word; lineWidth = w }
                lineWidth + space + w <= maxWidth -> { line += " " + word; lineWidth += space + w }
                else -> { lines += line; line = word; lineWidth = w }
            }
        }
        if (line.isNotEmpty()) lines += line
        return lines
    }

    // ---- captions that do not fit on one line (spec §16.4)

    /** How many lines a caption may take before it starts shrinking instead. */
    const val MAX_CAPTION_LINES = 2

    /**
     * Baseline to baseline for stacked lines: the font's own line box, so two lines of a banner sit
     * as far apart on both phones.
     */
    fun lineStep(height: Double): Double = lineTop(height) - lineBottom(height)

    /**
     * Where line [index] of [count] sits above the block's centre — the top line highest. A single
     * line sits on the anchor, exactly where it used to.
     */
    fun stackY(index: Int, count: Int, height: Double): Double =
        ((count - 1) / 2.0 - index) * lineStep(height)

    /** How tall a block of [count] lines is — what a slab has to grow to hold them. */
    fun stackHeight(count: Int, height: Double): Double =
        (maxOf(count, 1) - 1) * lineStep(height) + (lineTop(height) - lineBottom(height))

    /** The widest of [lines]. */
    fun widest(lines: List<String>, height: Double): Double =
        lines.fold(0.0) { w, line -> maxOf(w, width(line, height)) }

    /**
     * The lines a caption takes in [room] of room: one, while it fits; otherwise the **most even**
     * split into at most [MAX_CAPTION_LINES] that never breaks a word. A caption that still does not
     * fit — one long word, or more words than two lines can hold — comes back as it is, for the
     * caller to shrink with [fit]. Both apps therefore break "END OF PERIOD 1" and
     * "ENDE 1. DRITTEL" in the same place.
     */
    fun caption(text: String, height: Double, room: Double): List<String> {
        val words = text.split(' ').filter { it.isNotEmpty() }
        if (words.size < 2 || room <= 0.0 || width(text, height) <= room) return listOf(text)
        var best: List<String>? = null
        var bestWidest = Double.POSITIVE_INFINITY
        for (cut in 1 until words.size) {
            val candidate = listOf(words.subList(0, cut).joinToString(" "), words.subList(cut, words.size).joinToString(" "))
            val w = widest(candidate, height)
            if (w < bestWidest) { bestWidest = w; best = candidate }
        }
        return best ?: listOf(text)
    }
}
