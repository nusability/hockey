package `in`.nann.smashhockey.ui

/**
 * The 3D UI's design tokens — colours and sizes — the twin of iOS's DesignTokens.swift, value for
 * value. Both are the draft of `shared/data/design.json`, which the SMASH-6 generator will write
 * into both apps (conventions: "Design tokens, not raw values"). No component or screen spells a
 * colour or a size of its own.
 *
 * Sizes are metres in a screen's *design frame*: a plane [Size.FRAME_DEPTH] in front of the
 * camera, [Size.FRAME_WIDTH] wide, scaled as a whole to the phone's visible width ([ScreenFrame]).
 */
object DesignTokens {
    object Colour {
        const val INK = 0x1E1B4B            // lettering on light blocks
        const val CREAM = 0xFFF4D6          // slabs, light lettering
        const val SUN = 0xFFC83D            // the primary action
        const val SUN_SHADE = 0xC98A12      // the base a sun button sits in
        const val CORAL = 0xFF6B6B          // badges, danger
        const val CORAL_SHADE = 0xB8434B
        const val TEAL = 0x2EC4B6           // secondary action
        const val TEAL_SHADE = 0x1B7F76
        const val CREAM_SHADE = 0xC9B892
        const val DISABLED = 0xB8B2A7
        const val DISABLED_SHADE = 0x7E786E
        const val DISABLED_INK = 0x6E6860
        const val BOARD = 0x23213A          // scoreboard housing
        const val CARD = 0x33304F           // a flip card
        const val CARD_INK = 0xFFE8A3       // flip-card digits
        const val CHALK = 0x2F5D50          // the coach's board
        const val RAIL = 0x1A3F35
        const val ROW_LIGHT = 0xFFF4D6
        const val ROW_DARK = 0xF3E3BE
        const val ROW_HIGHLIGHT = 0xFFC83D
    }

    object Size {
        const val FRAME_DEPTH = 4.0f
        const val FRAME_WIDTH = 1.8f
        const val CORNER = 0.06f
        const val BUTTON_WIDTH = 1.3f
        const val BUTTON_HEIGHT = 0.32f
        const val BUTTON_DEPTH = 0.16f
        const val BUTTON_BASE_INSET = -0.035f   // the base is this much larger on each side
        const val TEXT_DEPTH_RATIO = 0.32f      // extrusion as a share of cap height
        const val TEXT_TITLE = 0.30f
        const val TEXT_HEADING = 0.13f
        const val TEXT_BUTTON = 0.12f
        const val TEXT_BODY = 0.075f
        const val TEXT_SMALL = 0.055f
        const val SLAB_DEPTH = 0.10f
        const val ROW_HEIGHT = 0.105f
        const val ROW_GAP = 0.018f
        const val RAIL_HEIGHT = 0.045f
        const val KNOB_RADIUS = 0.085f
        const val KNOB_DEPTH = 0.07f
    }
}
