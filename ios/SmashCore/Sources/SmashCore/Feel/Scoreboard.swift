import Foundation

/// The scoreboard's numbers and its layout (spec §16.4) — the split-flap board over the pitch and
/// the result slab. Pure, so one test pins both apps. The Android twin is `core/feel/Scoreboard.kt`.
///
/// The board **always shows two cards a side**, the tens card blank below ten. Nothing is rebuilt
/// when a side reaches ten: the tens card simply flips from blank to `1`, like the rest of the
/// board, and every side's cards stand in the same place whatever the score.
public enum Scoreboard {
    /// Cards a side. Two is what the board is built for; a score beyond it is clamped.
    public static let cards = 2
    public static let maxScore = 99
    /// A card showing nothing — the tens card of a single-digit score.
    public static let blank: Character = " "

    /// `n` as the characters of one side's cards: right-aligned, blank-padded, clamped to what the
    /// board can show. Always `cards` characters long, so the board's layout never changes.
    public static func score(_ n: Int) -> String {
        let clamped = min(max(n, 0), maxScore)
        let digits = String(clamped)
        return String(repeating: String(blank), count: max(0, cards - digits.count)) + digits
    }

    /// Both sides on one board: `" 3: 0"`, `"12:11"`. Always `2 × cards + 1` characters.
    public static func score(_ home: Int, _ away: Int) -> String { "\(score(home)):\(score(away))" }

    /// A drill's "scored of target" (§10). The target sets the width, so a target of ten or more
    /// gets two cards a side and one below it gets one — and the scored half never outgrows it.
    public static func drill(scored: Int, target: Int) -> String {
        let width = String(min(max(target, 0), maxScore)).count
        let capped = min(max(scored, 0), min(max(target, 0), maxScore))
        let digits = String(capped)
        let pad = String(repeating: String(blank), count: max(0, width - digits.count))
        return "\(pad)\(digits)/\(min(max(target, 0), maxScore))"
    }

    /// Where the board's pieces stand, in the design frame's metres, measured out from the colon in
    /// the middle. Every measure is derived, so the two platforms cannot drift apart.
    public struct Metrics: Sendable, Hashable {
        /// Half the width of one side's cards together.
        public var halfCards: Double
        /// The centre of a side's cards; side 0 stands at `-scoreX`, side 1 at `+scoreX`.
        public var scoreX: Double
        /// The centre of a side's team chip.
        public var chipX: Double
        /// The slab the whole lot stands on.
        public var boardWidth: Double
    }

    /// `card` is one card's width, `gap` the space between cards, `colon` the width kept clear in
    /// the middle, `chip` a team chip's width, `margin` the board's edge beyond the chips.
    public static func metrics(card: Double, gap: Double, colon: Double, chip: Double, margin: Double) -> Metrics {
        let width = Double(cards) * card + Double(cards - 1) * gap
        let inner = colon / 2
        let scoreX = inner + width / 2
        let chipX = inner + width + gap + chip / 2
        return Metrics(halfCards: width / 2, scoreX: scoreX, chipX: chipX,
                       boardWidth: 2 * (chipX + chip / 2 + margin))
    }
}
