import Testing
@testable import SmashCore

/// A card's own layout (spec §16.3a, §16.6): the owner found the team detail's buttons sitting on
/// its last line of content and sticking out past its edges. These are the two things that must
/// never happen again, on either phone and in either language — Android's `CardLayoutTest` checks
/// the same list.
@Suite struct CardLayoutTests {
    /// The detail's own width, and the two keys it carries for the player's own team.
    private static let cardWidth = 1.66

    private static func detailButtons(_ back: String, _ edit: String?) -> [CardLayout.Button] {
        var b = [CardLayout.Button(text: back, textHeight: 0.08, minWidth: 0.5, minHeight: 0.28)]
        if let edit { b.append(CardLayout.Button(text: edit, textHeight: 0.1, minWidth: 0.7, minHeight: 0.3)) }
        return b
    }

    /// The detail as the owner's screenshot had it, in both languages: the longest club name in
    /// the form strip and in "next", and the two keys under them.
    private static let englishBlocks = ["NEBULA NARWHALS", "3RD · 21 PTS", "13 PLAYED", "GOALS 31:18 · GD +13",
                                        "LAST MATCHES", "A MIRAGE FALCONS · CUP", "NEXT",
                                        "A NEBULA NARWHALS · LEAGUE · ROUND 13"]
    private static let germanBlocks = ["GLETSCHERWÖLFE", "3. · 21 PKT", "13 GESPIELT", "TORE 31:18 · TD +13",
                                       "LETZTE SPIELE", "A WÜSTENFALKEN · POKAL", "NÄCHSTES",
                                       "A GLETSCHERWÖLFE · LIGA · 13. SPIELTAG"]

    private static func card(_ texts: [String], _ buttons: [CardLayout.Button], height: Double = 0.055) -> CardLayout {
        let room = CardLayout(width: cardWidth, blocks: [], buttons: []).innerWidth
        let blocks = texts.map { CardLayout.blockHeight($0, height: height, room: room) }
        return CardLayout(width: cardWidth, blocks: blocks, buttons: buttons)
    }

    /// The defect itself: the buttons sat over the last line and hung off both sides.
    @Test func theButtonsStayInsideTheCardAndBelowEveryLine() {
        for (back, edit, texts) in [("BACK", "EDIT TEAM", Self.englishBlocks),
                                    ("ZURÜCK", "TEAM ÄNDERN", Self.germanBlocks)] {
            // Both cards: every team's (Back alone) and the player's own (Back and Edit team).
            for buttons in [Self.detailButtons(back, edit), Self.detailButtons(back, nil)] {
                let card = Self.card(texts, buttons)
                let lowest = card.blocks.map(\.bottom).min()!
                for key in card.buttons {
                    #expect(key.left >= card.left)
                    #expect(key.right <= card.right)
                    #expect(key.top <= lowest)
                    #expect(key.bottom >= -card.height / 2)
                }
            }
        }
    }

    /// Nothing overlaps anything: blocks come down the card in order, the buttons last.
    @Test func theBlocksComeDownTheCardInOrder() {
        let card = Self.card(Self.germanBlocks, Self.detailButtons("ZURÜCK", "TEAM ÄNDERN"))
        #expect(card.blocks.count == Self.germanBlocks.count)
        #expect(abs(card.blocks[0].top - (card.height / 2 - CardLayout.margin)) < 1e-12)
        for (a, b) in zip(card.blocks, card.blocks.dropFirst()) {
            #expect(abs(a.bottom - b.top - CardLayout.blockGap) < 1e-12)
        }
    }

    /// The height follows the content: a club name that wraps to two lines makes the card taller,
    /// it does not push the buttons over the line above.
    @Test func theCardGrowsWithItsContent() {
        let buttons = Self.detailButtons("ZURÜCK", "TEAM ÄNDERN")
        // The header's lettering: a long German club name has nowhere to sit on one line.
        let tall = 0.085
        let short = Self.card(["NEXT", "A LYNX"], buttons, height: tall)
        let long = Self.card(["NEXT", "A GLETSCHERWÖLFE · LIGA · 13. SPIELTAG"], buttons, height: tall)
        // And the extra height is exactly the extra line, not a guess.
        let room = short.innerWidth
        let wrapped = CardLayout.blockHeight("A GLETSCHERWÖLFE · LIGA · 13. SPIELTAG", height: tall, room: room)
        let plain = CardLayout.blockHeight("A LYNX", height: tall, room: room)
        #expect(wrapped > plain)
        #expect(long.height > short.height)
        #expect(abs(long.height - short.height - (wrapped - plain)) < 1e-12)
        // A card with no buttons is only its content and its margins.
        let bare = CardLayout(width: Self.cardWidth, blocks: [0.2, 0.3], buttons: [])
        #expect(abs(bare.height - (2 * CardLayout.margin + 0.5 + CardLayout.blockGap)) < 1e-12)
    }

    /// A caption longer than the card has room for squeezes the row rather than hanging off it —
    /// and the key that then has to wrap grows taller, so the words still sit on it.
    @Test func anOverlongRowIsSqueezedToFit() {
        let absurd = CardLayout.Button(text: "MANNSCHAFTSEINSTELLUNGEN BEARBEITEN", textHeight: 0.1,
                                       minWidth: 0.7, minHeight: 0.3)
        let back = CardLayout.Button(text: "ZURÜCK", textHeight: 0.08, minWidth: 0.5, minHeight: 0.28)
        let card = CardLayout(width: Self.cardWidth, blocks: [0.2], buttons: [back, absurd])
        #expect(card.buttons[0].left >= card.left)
        #expect(card.buttons[1].right <= card.right)
        let row = card.buttons[1].right - card.buttons[0].left
        #expect(abs(row - card.innerWidth) < 1e-9)          // squeezed to exactly the room there is
        #expect(card.buttons[1].height > absurd.minHeight)  // it wrapped, so the key grew
        #expect(abs(card.buttons[0].centreY - card.buttons[1].centreY) < 1e-12)
    }

    /// A key wide enough for its caption, never narrower than the screen asked for.
    @Test func aKeyIsAsWideAsItsCaption() {
        let card = CardLayout(width: 3, blocks: [0.2],
                              buttons: [CardLayout.Button(text: "BACK", textHeight: 0.08, minWidth: 0.5, minHeight: 0.28)])
        let caption = TextLayout.width("BACK", height: 0.08) + 2 * 0.08 * TextLayout.marginPerHeight
        #expect(abs(card.buttons[0].width - max(0.5, caption)) < 1e-12)
        let wide = CardLayout(width: 3, blocks: [0.2],
                              buttons: [CardLayout.Button(text: "LOS", textHeight: 0.08, minWidth: 1.2, minHeight: 0.28)])
        #expect(abs(wide.buttons[0].width - 1.2) < 1e-12)
    }
}
