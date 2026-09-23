package `in`.nann.smashhockey.core.feel

import kotlin.math.max

/**
 * How a card lays out what it carries (spec §16.3a, §16.6) — the one computation both apps build
 * the team detail and the drill's intro card with. Pure, so one test pins both. The iOS twin is
 * `SmashCore/Feel/CardLayout.swift`.
 *
 * A card is a column of content blocks under a top margin, and then its buttons, in a row of
 * their own below the last of them. The card is **as tall as that comes to**: a long club name
 * that wraps pushes the card's own bottom edge down, never its buttons onto a line of content.
 * And a button is never wider than the room the card has, because the row is squeezed to fit
 * before it is placed — a German caption cannot stick out past the card's edge.
 *
 * Everything is in the design frame's metres, measured from the card's own centre, and `height`
 * always means the cap height of the lettering — the same thing the kit's `textHeight` tokens
 * mean ([TextLayout]).
 */
class CardLayout(
    val width: Double,
    blockHeights: List<Double>,
    specs: List<Button>,
) {
    /**
     * A button the card carries: its caption says how wide it wants to be, and [minWidth] /
     * [minHeight] are the smallest key the screen will accept.
     */
    data class Button(
        val text: String,
        val textHeight: Double,
        val minWidth: Double,
        val minHeight: Double,
    )

    /** Where something the card carries ended up, from the card's centre. */
    data class Box(val centreX: Double, val centreY: Double, val width: Double, val height: Double) {
        val left get() = centreX - width / 2
        val right get() = centreX + width / 2
        val top get() = centreY + height / 2
        val bottom get() = centreY - height / 2
    }

    /** What the card's slab has to be built at: the content, the buttons and the margins. */
    val height: Double
    /** Each content block's box, in the order it was given, top down. */
    val blocks: List<Box>
    /** Each button's box, left to right, all on one baseline below the content. */
    val buttons: List<Box>

    /** The width content may take: the card's width less its two side margins. */
    val innerWidth: Double get() = max(0.0, width - 2 * MARGIN)
    /** The x a leading-aligned line starts at, and the x a trailing-aligned one ends at. */
    val left get() = -innerWidth / 2
    val right get() = innerWidth / 2

    init {
        val inner = max(0.0, width - 2 * MARGIN)

        // Each key as wide as its own caption wants; the whole row squeezed when it overruns the
        // card, so no button can ever protrude past an edge.
        var widths = specs.map { spec ->
            max(spec.minWidth, TextLayout.width(spec.text, spec.textHeight) + 2 * spec.textHeight * TextLayout.MARGIN_PER_HEIGHT)
        }
        val gaps = max(specs.size - 1, 0) * BUTTON_GAP
        val wanted = widths.sum()
        if (wanted > 0 && wanted + gaps > inner) {
            val k = max(0.0, inner - gaps) / wanted
            widths = widths.map { it * k }
        }
        // A caption that has to wrap on the squeezed key makes the key taller — the kit's own rule
        // for a block button, computed here so the card knows its height before it is built.
        val heights = specs.mapIndexed { i, spec ->
            val room = TextLayout.room(widths[i], spec.textHeight)
            val lines = TextLayout.caption(spec.text, spec.textHeight, room)
            max(spec.minHeight, TextLayout.stackHeight(lines.size, spec.textHeight) + 2 * spec.textHeight * TextLayout.MARGIN_PER_HEIGHT)
        }
        val rowHeight = heights.maxOrNull() ?: 0.0

        val content = blockHeights.sum() + max(blockHeights.size - 1, 0) * BLOCK_GAP
        val h = 2 * MARGIN + content + (if (specs.isEmpty()) 0.0 else BUTTON_ROW_GAP + rowHeight)
        height = h

        var y = h / 2 - MARGIN
        blocks = blockHeights.map { bh ->
            val box = Box(0.0, y - bh / 2, inner, bh)
            y -= bh + BLOCK_GAP
            box
        }

        val rowWidth = widths.sum() + gaps
        val rowY = -h / 2 + MARGIN + rowHeight / 2
        var x = -rowWidth / 2
        buttons = specs.indices.map { i ->
            val box = Box(x + widths[i] / 2, rowY, widths[i], heights[i])
            x += widths[i] + BUTTON_GAP
            box
        }
    }

    companion object {
        /** The margin the card keeps inside its own edges, on all four sides. */
        const val MARGIN = 0.09
        /** Between two content blocks. */
        const val BLOCK_GAP = 0.035
        /** Between two buttons of the row. */
        const val BUTTON_GAP = 0.08
        /**
         * Between the last content block and the row of buttons — wide enough that the two never
         * read as one thing.
         */
        const val BUTTON_ROW_GAP = 0.1

        /** The width content may take on a card [width] wide — before the card is built. */
        fun inner(width: Double): Double = max(0.0, width - 2 * MARGIN)

        /** How tall a run of lettering is in [room] of width — one line, or the two it wraps to (§16). */
        fun blockHeight(text: String, height: Double, room: Double): Double =
            TextLayout.stackHeight(TextLayout.caption(text, height, room).size, height)
    }
}
