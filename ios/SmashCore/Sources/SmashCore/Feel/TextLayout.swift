import Foundation

/// Where the 3D UI's lettering sits (spec §16) — the one computation both apps lay a screen out
/// with. Pure, so one test pins both. The Android twin is `core/feel/TextLayout.kt`.
///
/// The kit's lettering is extruded from one font file on both platforms, but each platform meshes
/// it with a different engine (ADR 0005), and the box an engine reports around the result is its
/// own: RealityKit's `generateText` bounds and Android's triangulated outline bounds are not the
/// same rectangle. A layout measured off that box therefore came out differently on the two
/// phones — a long German word sat off its slab, a lone digit was centred on its ink rather than
/// on its advance. So the measuring is done here instead, from the font's own metrics
/// (`FontMetrics`): the mesher draws the glyphs, this decides where they go.
///
/// Everything is in the design frame's metres, and `height` always means the **cap height** of the
/// lettering — the same thing the kit's `textHeight` tokens mean.
public enum TextLayout {
    /// One em, in metres, for lettering of cap height `height`.
    public static func em(_ height: Double) -> Double {
        height * Double(FontMetrics.unitsPerEm) / Double(FontMetrics.capHeight)
    }

    /// How wide `text` is as lettering of cap height `height`: the sum of its glyphs' advances.
    /// This is the width a slab has to hold and the width an alignment is measured from.
    public static func width(_ text: String, height: Double) -> Double {
        var units = 0
        for scalar in text.unicodeScalars { units += FontMetrics.advance(scalar) }
        return Double(units) * em(height) / Double(FontMetrics.unitsPerEm)
    }

    /// The line's top and bottom above the baseline, in metres — the box the lettering is placed
    /// by. It depends on the font and the height, never on which characters the string has, so a
    /// word with an umlaut sits on the same line as one without.
    public static func lineTop(_ height: Double) -> Double {
        Double(FontMetrics.ascent) * em(height) / Double(FontMetrics.unitsPerEm)
    }

    public static func lineBottom(_ height: Double) -> Double {
        Double(FontMetrics.descent) * em(height) / Double(FontMetrics.unitsPerEm)
    }

    /// How far above the baseline a piece of lettering is anchored: the middle of the line box.
    /// A label placed at y sits with this point on y.
    public static func centreY(_ height: Double) -> Double { (lineTop(height) + lineBottom(height)) / 2 }

    /// The scale a piece of lettering is shrunk by to fit `maxWidth` — 1 when it already fits, and
    /// 1 when there is no limit. A long word in a short slot shrinks; nothing ever grows.
    public static func fit(_ natural: Double, _ maxWidth: Double?) -> Double {
        guard let maxWidth, maxWidth > 0, natural > maxWidth else { return 1 }
        return maxWidth / natural
    }

    /// How a piece of lettering is placed against the point it is aligned to.
    public enum Align: Sendable, Hashable { case centre, leading, trailing }

    /// The x offset from the alignment point to the lettering's centre, for lettering `width` wide
    /// (already shrunk by `fit`).
    public static func alignX(_ align: Align, width: Double) -> Double {
        switch align {
        case .centre: 0
        case .leading: width / 2
        case .trailing: -width / 2
        }
    }

    /// The width a caption may take on a slab `slabWidth` wide: a margin of six tenths of the
    /// lettering's height is kept either side, so a button's word never runs into its rounding.
    public static func room(slabWidth: Double, textHeight: Double) -> Double {
        max(0, slabWidth - 2 * textHeight * marginPerHeight)
    }

    /// The side margin a caption keeps, as a share of its own cap height.
    public static let marginPerHeight = 0.6

    /// Running text wrapped greedily into lines no wider than `width` — as many words on a line
    /// as fit, never breaking one. Measured with the font's own spaces, so both apps break a
    /// help card in the same places.
    public static func wrap(_ text: String, height: Double, width: Double) -> [String] {
        let space = TextLayout.width(" ", height: height)
        var lines: [String] = []
        var line = ""
        var lineWidth = 0.0
        for word in text.split(separator: " ").map(String.init) where !word.isEmpty {
            let w = TextLayout.width(word, height: height)
            if line.isEmpty {
                line = word
                lineWidth = w
            } else if lineWidth + space + w <= width {
                line += " " + word
                lineWidth += space + w
            } else {
                lines.append(line)
                line = word
                lineWidth = w
            }
        }
        if !line.isEmpty { lines.append(line) }
        return lines
    }

    // MARK: captions that do not fit on one line (spec §16.4)

    /// How many lines a caption may take before it starts shrinking instead.
    public static let maxCaptionLines = 2

    /// Baseline to baseline for stacked lines: the font's own line box, so two lines of a banner sit
    /// as far apart on both phones.
    public static func lineStep(_ height: Double) -> Double { lineTop(height) - lineBottom(height) }

    /// Where line `index` of `count` sits above the block's centre — the top line highest. A single
    /// line sits on the anchor, exactly where it used to.
    public static func stackY(_ index: Int, of count: Int, height: Double) -> Double {
        (Double(count - 1) / 2 - Double(index)) * lineStep(height)
    }

    /// How tall a block of `count` lines is — what a slab has to grow to hold them.
    public static func stackHeight(_ count: Int, height: Double) -> Double {
        Double(max(count, 1) - 1) * lineStep(height) + (lineTop(height) - lineBottom(height))
    }

    /// The widest of `lines`.
    public static func widest(_ lines: [String], height: Double) -> Double {
        lines.reduce(0) { max($0, width($1, height: height)) }
    }

    /// The lines a caption takes in `width` of room: one, while it fits; otherwise the **most even**
    /// split into at most `maxCaptionLines` that never breaks a word. A caption that still does not
    /// fit — one long word, or more words than two lines can hold — comes back as it is, for the
    /// caller to shrink with `fit`. Both apps therefore break "END OF PERIOD 1" and
    /// "ENDE 1. DRITTEL" in the same place.
    public static func caption(_ text: String, height: Double, width room: Double) -> [String] {
        let words = text.split(separator: " ").map(String.init).filter { !$0.isEmpty }
        guard words.count > 1, room > 0, width(text, height: height) > room else {
            return [text]
        }
        var best: [String]?
        var bestWidest = Double.infinity
        for cut in 1..<words.count {
            let candidate = [words[..<cut].joined(separator: " "), words[cut...].joined(separator: " ")]
            let w = widest(candidate, height: height)
            if w < bestWidest { bestWidest = w; best = candidate }
        }
        return best ?? [text]
    }
}
