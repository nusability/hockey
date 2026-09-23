import Foundation

/// How a card lays out what it carries (spec §16.3a, §16.6) — the one computation both apps build
/// the team detail and the drill's intro card with. Pure, so one test pins both. The Android twin
/// is `core/feel/CardLayout.kt`.
///
/// A card is a column of content blocks under a top margin, and then its buttons, in a row of
/// their own below the last of them. The card is **as tall as that comes to**: a long club name
/// that wraps pushes the card's own bottom edge down, never its buttons onto a line of content.
/// And a button is never wider than the room the card has, because the row is squeezed to fit
/// before it is placed — a German caption cannot stick out past the card's edge.
///
/// Everything is in the design frame's metres, measured from the card's own centre, and `height`
/// always means the cap height of the lettering — the same thing the kit's `textHeight` tokens
/// mean (`TextLayout`).
public struct CardLayout: Sendable, Equatable {
    /// A button the card carries: its caption says how wide it wants to be, and `minWidth` /
    /// `minHeight` are the smallest key the screen will accept.
    public struct Button: Sendable, Equatable {
        public let text: String
        public let textHeight: Double
        public let minWidth: Double
        public let minHeight: Double

        public init(text: String, textHeight: Double, minWidth: Double, minHeight: Double) {
            self.text = text
            self.textHeight = textHeight
            self.minWidth = minWidth
            self.minHeight = minHeight
        }
    }

    /// Where something the card carries ended up, from the card's centre.
    public struct Box: Sendable, Equatable {
        public let centreX: Double
        public let centreY: Double
        public let width: Double
        public let height: Double

        public var left: Double { centreX - width / 2 }
        public var right: Double { centreX + width / 2 }
        public var top: Double { centreY + height / 2 }
        public var bottom: Double { centreY - height / 2 }
    }

    /// The margin the card keeps inside its own edges, on all four sides.
    public static let margin = 0.09
    /// Between two content blocks.
    public static let blockGap = 0.035
    /// Between two buttons of the row.
    public static let buttonGap = 0.08
    /// Between the last content block and the row of buttons — wide enough that the two never
    /// read as one thing.
    public static let buttonRowGap = 0.1

    public let width: Double
    /// What the card's slab has to be built at: the content, the buttons and the margins.
    public let height: Double
    /// Each content block's box, in the order it was given, top down.
    public let blocks: [Box]
    /// Each button's box, left to right, all on one baseline below the content.
    public let buttons: [Box]

    /// The width content may take: the card's width less its two side margins.
    public var innerWidth: Double { max(0, width - 2 * Self.margin) }
    /// The x a leading-aligned line starts at, and the x a trailing-aligned one ends at.
    public var left: Double { -innerWidth / 2 }
    public var right: Double { innerWidth / 2 }

    public init(width: Double, blocks blockHeights: [Double], buttons specs: [Button]) {
        self.width = width
        let inner = max(0, width - 2 * Self.margin)

        // Each key as wide as its own caption wants; the whole row squeezed when it overruns the
        // card, so no button can ever protrude past an edge.
        var widths = specs.map { spec in
            max(spec.minWidth,
                TextLayout.width(spec.text, height: spec.textHeight)
                    + 2 * spec.textHeight * TextLayout.marginPerHeight)
        }
        let gaps = Double(max(specs.count - 1, 0)) * Self.buttonGap
        let wanted = widths.reduce(0, +)
        if wanted > 0, wanted + gaps > inner {
            let k = max(0, inner - gaps) / wanted
            widths = widths.map { $0 * k }
        }
        // A caption that has to wrap on the squeezed key makes the key taller — the kit's own rule
        // for a block button, computed here so the card knows its height before it is built.
        var heights: [Double] = []
        for (i, spec) in specs.enumerated() {
            let room = TextLayout.room(slabWidth: widths[i], textHeight: spec.textHeight)
            let lines = TextLayout.caption(spec.text, height: spec.textHeight, width: room)
            heights.append(max(spec.minHeight,
                               TextLayout.stackHeight(lines.count, height: spec.textHeight)
                                   + 2 * spec.textHeight * TextLayout.marginPerHeight))
        }
        let rowHeight = heights.max() ?? 0

        let content = blockHeights.reduce(0, +) + Double(max(blockHeights.count - 1, 0)) * Self.blockGap
        let h = 2 * Self.margin + content + (specs.isEmpty ? 0 : Self.buttonRowGap + rowHeight)
        height = h

        var y = h / 2 - Self.margin
        var laid: [Box] = []
        for bh in blockHeights {
            laid.append(Box(centreX: 0, centreY: y - bh / 2, width: inner, height: bh))
            y -= bh + Self.blockGap
        }
        blocks = laid

        let rowWidth = widths.reduce(0, +) + gaps
        let rowY = -h / 2 + Self.margin + rowHeight / 2
        var x = -rowWidth / 2
        var keys: [Box] = []
        for i in specs.indices {
            keys.append(Box(centreX: x + widths[i] / 2, centreY: rowY, width: widths[i], height: heights[i]))
            x += widths[i] + Self.buttonGap
        }
        buttons = keys
    }

    /// The width content may take on a card `width` wide — before the card is built.
    public static func inner(width: Double) -> Double { max(0, width - 2 * margin) }

    /// How tall a run of lettering is in `room` of width — one line, or the two it wraps to (§16).
    public static func blockHeight(_ text: String, height: Double, room: Double) -> Double {
        TextLayout.stackHeight(TextLayout.caption(text, height: height, width: room).count, height: height)
    }
}
