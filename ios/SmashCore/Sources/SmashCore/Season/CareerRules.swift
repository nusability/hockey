import Foundation

/// A team the player is creating (spec §2.2): what the create screen edits before confirming.
public struct TeamDraft: Sendable, Hashable {
    public var name: String
    public var short: String
    public var primary: UInt32
    public var secondary: UInt32
    public var world: World

    public init(name: String, short: String, primary: UInt32, secondary: UInt32, world: World) {
        self.name = name
        self.short = short
        self.primary = primary
        self.secondary = secondary
        self.world = world
    }
}

/// Why a draft cannot be confirmed (spec §2.2). Listed in this order by `CreatedTeamRules.issues`.
public enum TeamIssue: String, Sendable, CaseIterable, Hashable {
    case nameTooShort
    case nameTooLong
    case shortCodeNotThreeLetters
    case shortCodeIsAClubs
    case primaryNotInPalette
    case secondaryNotInPalette
}

/// What the game refuses to do (spec §2.2, §11, §8.7). Every refusal is typed; none is a string.
public enum GameError: Error, Sendable, Equatable {
    /// A career exists: there is no switching (§2.2) — only starting over.
    case careerExists
    case noCareer
    case invalidTeam([TeamIssue])
    /// A new season starts only when there is none or the last one is over (§11.4).
    case seasonInProgress
    case noSeason
    case seasonFinished
    /// The current matchday has no fixture for the player (they are never left on one: §11.2).
    case noPlayerFixture
    case negativeGoals
    /// A cup match always has a winner (§8.4).
    case cupScoreLevel
    case overtimeOutsideCup
    /// Sudden death ends on the next goal (§8.4).
    case overtimeNotByOneGoal
    /// A coach's board value outside §12's ranges and steps.
    case notABoardValue
}

/// The created team's rules (spec §2.2).
public enum CreatedTeamRules {
    /// The name as it is kept: leading and trailing spaces (U+0020) dropped.
    public static func trimmedName(_ name: String) -> String {
        let s = Array(name.unicodeScalars)
        var lo = 0, hi = s.count
        while lo < hi, s[lo] == " " { lo += 1 }
        while hi > lo, s[hi - 1] == " " { hi -= 1 }
        var view = String.UnicodeScalarView()
        view.append(contentsOf: s[lo..<hi])
        return String(view)
    }

    /// The short code derived from a name: its letters A–Z (accents dropped, uppercased) — the
    /// first, the second and the first later one that makes a code no club has; failing that, the
    /// first two letters (as many as there are) padded with `Career.shortCodePad`.
    public static func suggestedShortCode(for name: String) -> String {
        let letters = name.decomposedStringWithCanonicalMapping.unicodeScalars.compactMap { s -> Character? in
            switch s.value {
            case 0x41...0x5A: Character(s)
            case 0x61...0x7A: Character(Unicode.Scalar(s.value - 0x20)!)
            default: nil
            }
        }
        let clubCodes = Set(Club.allCases.map(\.short))
        if letters.count >= Career.shortCodeLength {
            for k in 2..<letters.count {
                let code = String([letters[0], letters[1], letters[k]])
                if !clubCodes.contains(code) { return code }
            }
        }
        var code = String(letters.prefix(2))
        while code.count < Career.shortCodeLength { code += Career.shortCodePad }
        return code
    }

    /// Every rule the draft breaks, in `TeamIssue` order; empty when it can be confirmed.
    public static func issues(_ draft: TeamDraft) -> [TeamIssue] {
        var out: [TeamIssue] = []
        let length = trimmedName(draft.name).unicodeScalars.count
        if length < Career.nameMinLength { out.append(.nameTooShort) }
        if length > Career.nameMaxLength { out.append(.nameTooLong) }
        let short = draft.short.unicodeScalars
        if short.count != Career.shortCodeLength || !short.allSatisfy({ (0x41...0x5A).contains($0.value) }) {
            out.append(.shortCodeNotThreeLetters)
        } else if Club.allCases.contains(where: { $0.short == draft.short }) {
            out.append(.shortCodeIsAClubs)
        }
        if !Career.kitPalette.contains(where: { $0.primary == draft.primary }) { out.append(.primaryNotInPalette) }
        if !Career.kitPalette.contains(where: { $0.secondary == draft.secondary }) { out.append(.secondaryNotInPalette) }
        return out
    }
}

extension CareerRecord {
    /// The player's team: always the one they created (§2.2) — there is no picking a club.
    public var team: TeamKey { .created }

    /// The league's eight teams in their canonical order (§11.1): the clubs as declared, the
    /// player's team in the place of the club it replaces.
    public var league: [TeamKey] {
        Club.allCases.map { club in club == Career.createdReplaces ? .created : TeamKey(club) }
    }

    /// A team's short code — the player's team's own, or a club's.
    public func short(of key: TeamKey) -> String {
        key.club?.short ?? created.short
    }

    /// A team's rating (§2.1); the player's team's is fixed (§2.2).
    public func rating(of key: TeamKey) -> Int {
        key.club?.rating ?? Career.createdRating
    }
}

extension BoardRecord {
    /// The board's defaults (§12).
    public static let defaults = BoardRecord(
        pressing: Tactics.defaults.pressing, covering: Tactics.defaults.covering, pushUp: Tactics.defaults.pushUp,
        discipline: Tactics.defaults.discipline, formation: Formation.allCases[0],
        periodSeconds: Tuning.Board.periodSecondsDefault, ballSpinSeconds: Tuning.Board.ballSpinSecondsDefault)

    /// Sets the board's tactics — creating a team starts the board from its tactics (§2.2)
    /// and keeps the formation, period length and ball spin the player set.
    public mutating func adoptTactics(_ t: Tactics) {
        pressing = t.pressing
        covering = t.covering
        pushUp = t.pushUp
        discipline = t.discipline
    }
}
