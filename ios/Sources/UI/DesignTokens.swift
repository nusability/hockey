/// The 3D UI's design tokens — colours and sizes — in one place. Plain names and plain values on
/// purpose: this file is the draft of `shared/data/design.json`, which the SMASH-6 generator will
/// write into both apps (conventions: "Design tokens, not raw values"). No component or screen
/// spells a colour or a size of its own.
///
/// Sizes are metres in a screen's *design frame*: a plane `frameDepth` in front of the camera,
/// `frameWidth` wide, scaled as a whole to the phone's visible width (see `ScreenFrame`).
enum DesignTokens {
    enum Colour {
        static let ink = 0x1E1B4B           // lettering on light blocks
        static let cream = 0xFFF4D6         // slabs, light lettering
        static let sun = 0xFFC83D           // the primary action
        static let sunShade = 0xC98A12      // the base a sun button sits in
        static let coral = 0xFF6B6B         // badges, danger
        static let coralShade = 0xB8434B
        static let teal = 0x2EC4B6          // secondary action
        static let tealShade = 0x1B7F76
        static let creamShade = 0xC9B892
        static let disabled = 0xB8B2A7
        static let disabledShade = 0x7E786E
        static let disabledInk = 0x6E6860
        static let board = 0x23213A         // scoreboard housing
        static let card = 0x33304F          // a flip card
        static let cardInk = 0xFFE8A3       // flip-card digits
        static let chalk = 0x2F5D50         // the coach's board
        static let rail = 0x1A3F35
        static let rowLight = 0xFFF4D6
        static let rowDark = 0xF3E3BE
        static let rowHighlight = 0xFFC83D
    }

    enum Size {
        static let frameDepth: Float = 4.0
        static let frameWidth: Float = 1.8
        static let corner: Float = 0.06
        static let buttonWidth: Float = 1.3
        static let buttonHeight: Float = 0.32
        static let buttonDepth: Float = 0.16
        static let buttonBaseInset: Float = -0.035   // the base is this much larger on each side
        static let textDepthRatio: Float = 0.32      // extrusion as a share of cap height
        static let textTitle: Float = 0.30
        static let textHeading: Float = 0.13
        static let textButton: Float = 0.12
        static let textBody: Float = 0.075
        static let textSmall: Float = 0.055
        static let slabDepth: Float = 0.10
        static let rowHeight: Float = 0.105
        static let rowGap: Float = 0.018
        static let railHeight: Float = 0.045
        static let knobRadius: Float = 0.085
        static let knobDepth: Float = 0.07
    }
}
