import Foundation
import SmashCore

/// The declared copy (spec §14, shared/data/copy.toml → Localizable.xcstrings): a key and its
/// placeholders, in the order the English names them. Every word on screen comes through here.
func L(_ key: CopyKey, _ args: CustomStringConvertible...) -> String {
    let format = Bundle.main.localizedString(forKey: key.rawValue, value: nil, table: nil)
    guard !args.isEmpty else { return format }
    return String(format: format, locale: .current, arguments: args.map { $0.description as NSString })
}

/// Names the screens show, from the career or the declarations.
enum Names {
    /// A team's name in capitals: a club's localized name, or the created team's own.
    static func team(_ key: TeamKey, _ career: CareerRecord?) -> String {
        if let club = key.club { return L(club.nameKey).uppercased() }
        return career?.created?.name.uppercased() ?? ""
    }

    static func short(_ key: TeamKey, _ career: CareerRecord?) -> String {
        key.club?.short ?? career?.created?.short ?? ""
    }

    static func world(_ w: World) -> String { L(w.nameKey).uppercased() }

    /// "1ST", "2ND", "3RD", "4TH"… (§16.3's place in the league).
    static func ordinal(_ n: Int) -> String {
        switch n {
        case 1: L(.ord1)
        case 2: L(.ord2)
        case 3: L(.ord3)
        default: L(.ordN, n)
        }
    }

    /// A matchday's label: league round or cup round (§11.1).
    static func matchday(_ step: MatchdayStep) -> String {
        switch step {
        case .league(let round): L(.hubLeague, round)
        case .cup(let round): L(.hubCup, cupRound(round))
        }
    }

    static func cupRound(_ r: CupRound) -> String {
        switch r {
        case .quarterFinal: L(.hubQuarterFinal)
        case .semiFinal: L(.hubSemiFinal)
        case .final: L(.hubFinal)
        }
    }

    /// m:ss, rounded up — the HUD's clock (§8.3).
    static func clock(_ seconds: Double) -> String {
        let s = max(0, Int(seconds.rounded(.up)))
        return String(format: "%d:%02d", s / 60, s % 60)
    }
}
