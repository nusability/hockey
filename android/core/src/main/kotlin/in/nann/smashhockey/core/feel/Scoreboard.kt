package `in`.nann.smashhockey.core.feel

/**
 * The scoreboard's numbers and its layout (spec §16.4) — the split-flap board over the pitch and the
 * result slab. Pure, so one test pins both apps. The iOS twin is `SmashCore/Feel/Scoreboard.swift`.
 *
 * The board **always shows two cards a side**, the tens card blank below ten. Nothing is rebuilt when
 * a side reaches ten: the tens card simply flips from blank to `1`, like the rest of the board, and
 * every side's cards stand in the same place whatever the score.
 */
object Scoreboard {
    /** Cards a side. Two is what the board is built for; a score beyond it is clamped. */
    const val CARDS = 2
    const val MAX_SCORE = 99

    /** A card showing nothing — the tens card of a single-digit score. */
    const val BLANK = ' '

    /**
     * [n] as the characters of one side's cards: right-aligned, blank-padded, clamped to what the
     * board can show. Always [CARDS] characters long, so the board's layout never changes.
     */
    fun score(n: Int): String {
        val digits = n.coerceIn(0, MAX_SCORE).toString()
        return BLANK.toString().repeat(maxOf(0, CARDS - digits.length)) + digits
    }

    /** Both sides on one board: `" 3: 0"`, `"12:11"`. Always `2 × CARDS + 1` characters. */
    fun score(home: Int, away: Int): String = "${score(home)}:${score(away)}"

    /**
     * A drill's "scored of target" (§10). The target sets the width, so a target of ten or more gets
     * two cards a side and one below it gets one — and the scored half never outgrows it.
     */
    fun drill(scored: Int, target: Int): String {
        val capped = target.coerceIn(0, MAX_SCORE)
        val width = capped.toString().length
        val digits = scored.coerceIn(0, capped).toString()
        return BLANK.toString().repeat(maxOf(0, width - digits.length)) + digits + "/" + capped
    }

    /**
     * Where the board's pieces stand, in the design frame's metres, measured out from the colon in the
     * middle. Every measure is derived, so the two platforms cannot drift apart.
     */
    data class Metrics(
        /** Half the width of one side's cards together. */
        val halfCards: Double,
        /** The centre of a side's cards; side 0 stands at `-scoreX`, side 1 at `+scoreX`. */
        val scoreX: Double,
        /** The centre of a side's team chip. */
        val chipX: Double,
        /** The slab the whole lot stands on. */
        val boardWidth: Double,
    )

    /**
     * [card] is one card's width, [gap] the space between cards, [colon] the width kept clear in the
     * middle, [chip] a team chip's width, [margin] the board's edge beyond the chips.
     */
    fun metrics(card: Double, gap: Double, colon: Double, chip: Double, margin: Double): Metrics {
        val width = CARDS * card + (CARDS - 1) * gap
        val inner = colon / 2
        val scoreX = inner + width / 2
        val chipX = inner + width + gap + chip / 2
        return Metrics(width / 2, scoreX, chipX, 2 * (chipX + chip / 2 + margin))
    }
}
