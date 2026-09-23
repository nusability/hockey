package `in`.nann.smashhockey.core.feel

import kotlin.math.abs
import kotlin.math.max
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * A card's own layout (spec §16.3a, §16.6): the owner found the team detail's buttons sitting on
 * its last line of content and sticking out past its edges. These are the two things that must
 * never happen again, on either phone and in either language — iOS's `CardLayoutTests` checks the
 * same list.
 */
class CardLayoutTest {
    private val cardWidth = 1.66

    private fun near(expected: Double, actual: Double, tolerance: Double = 1e-12) =
        assertTrue("expected $expected, was $actual", abs(expected - actual) < tolerance)

    private fun detailButtons(back: String, edit: String?): List<CardLayout.Button> {
        val b = mutableListOf(CardLayout.Button(back, 0.08, 0.5, 0.28))
        if (edit != null) b += CardLayout.Button(edit, 0.1, 0.7, 0.3)
        return b
    }

    private val englishBlocks = listOf("NEBULA NARWHALS", "3RD · 21 PTS", "13 PLAYED", "GOALS 31:18 · GD +13",
        "LAST MATCHES", "A MIRAGE FALCONS · CUP", "NEXT", "A NEBULA NARWHALS · LEAGUE · ROUND 13")
    private val germanBlocks = listOf("GLETSCHERWÖLFE", "3. · 21 PKT", "13 GESPIELT", "TORE 31:18 · TD +13",
        "LETZTE SPIELE", "A WÜSTENFALKEN · POKAL", "NÄCHSTES", "A GLETSCHERWÖLFE · LIGA · 13. SPIELTAG")

    private fun card(texts: List<String>, buttons: List<CardLayout.Button>, height: Double = 0.055): CardLayout {
        val room = CardLayout(cardWidth, emptyList(), emptyList()).innerWidth
        return CardLayout(cardWidth, texts.map { CardLayout.blockHeight(it, height, room) }, buttons)
    }

    /** The defect itself: the buttons sat over the last line and hung off both sides. */
    @Test fun theButtonsStayInsideTheCardAndBelowEveryLine() {
        for ((back, edit, texts) in listOf(Triple("BACK", "EDIT TEAM", englishBlocks),
                Triple("ZURÜCK", "TEAM ÄNDERN", germanBlocks))) {
            // Both cards: every team's (Back alone) and the player's own (Back and Edit team).
            for (buttons in listOf(detailButtons(back, edit), detailButtons(back, null))) {
                val c = card(texts, buttons)
                val lowest = c.blocks.minOf { it.bottom }
                for (key in c.buttons) {
                    assertTrue("$key left of the card", key.left >= c.left)
                    assertTrue("$key right of the card", key.right <= c.right)
                    assertTrue("$key over the content", key.top <= lowest)
                    assertTrue("$key below the card", key.bottom >= -c.height / 2)
                }
            }
        }
    }

    /** Nothing overlaps anything: blocks come down the card in order, the buttons last. */
    @Test fun theBlocksComeDownTheCardInOrder() {
        val c = card(germanBlocks, detailButtons("ZURÜCK", "TEAM ÄNDERN"))
        assertTrue(c.blocks.size == germanBlocks.size)
        near(c.height / 2 - CardLayout.MARGIN, c.blocks[0].top)
        for (i in 0 until c.blocks.size - 1) near(CardLayout.BLOCK_GAP, c.blocks[i].bottom - c.blocks[i + 1].top)
    }

    /**
     * The height follows the content: a club name that wraps to two lines makes the card taller,
     * it does not push the buttons over the line above.
     */
    @Test fun theCardGrowsWithItsContent() {
        val buttons = detailButtons("ZURÜCK", "TEAM ÄNDERN")
        // The header's lettering: a long German club name has nowhere to sit on one line.
        val tall = 0.085
        val short = card(listOf("NEXT", "A LYNX"), buttons, tall)
        val long = card(listOf("NEXT", "A GLETSCHERWÖLFE · LIGA · 13. SPIELTAG"), buttons, tall)
        assertTrue(long.height > short.height)
        val room = short.innerWidth
        val wrapped = CardLayout.blockHeight("A GLETSCHERWÖLFE · LIGA · 13. SPIELTAG", tall, room)
        val plain = CardLayout.blockHeight("A LYNX", tall, room)
        assertTrue(wrapped > plain)
        near(wrapped - plain, long.height - short.height)
        val bare = CardLayout(cardWidth, listOf(0.2, 0.3), emptyList())
        near(2 * CardLayout.MARGIN + 0.5 + CardLayout.BLOCK_GAP, bare.height)
    }

    /**
     * A caption longer than the card has room for squeezes the row rather than hanging off it —
     * and the key that then has to wrap grows taller, so the words still sit on it.
     */
    @Test fun anOverlongRowIsSqueezedToFit() {
        val absurd = CardLayout.Button("MANNSCHAFTSEINSTELLUNGEN BEARBEITEN", 0.1, 0.7, 0.3)
        val back = CardLayout.Button("ZURÜCK", 0.08, 0.5, 0.28)
        val c = CardLayout(cardWidth, listOf(0.2), listOf(back, absurd))
        assertTrue(c.buttons[0].left >= c.left)
        assertTrue(c.buttons[1].right <= c.right)
        near(c.innerWidth, c.buttons[1].right - c.buttons[0].left, 1e-9)
        assertTrue(c.buttons[1].height > absurd.minHeight)
        near(c.buttons[0].centreY, c.buttons[1].centreY)
    }

    /** A key wide enough for its caption, never narrower than the screen asked for. */
    @Test fun aKeyIsAsWideAsItsCaption() {
        val c = CardLayout(3.0, listOf(0.2), listOf(CardLayout.Button("BACK", 0.08, 0.5, 0.28)))
        val caption = TextLayout.width("BACK", 0.08) + 2 * 0.08 * TextLayout.MARGIN_PER_HEIGHT
        near(max(0.5, caption), c.buttons[0].width)
        val wide = CardLayout(3.0, listOf(0.2), listOf(CardLayout.Button("LOS", 0.08, 1.2, 0.28)))
        near(1.2, wide.buttons[0].width)
    }
}
