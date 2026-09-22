import Foundation

// THROWAWAY (SMASH-5): the motion sketch's fake data — a click-dummy for judging the 3D UI's
// feel on a phone, not the season (§11). Kit colours are invented here; the spec gives each club
// a primary and a secondary kit colour but does not yet name them.

enum SketchScreenID: String { case title, hub, match, result, coach }

struct SketchClub {
    let code: String
    let primary: Int
    let secondary: Int
}

struct SketchStanding {
    let code: String
    var played: Int
    var goalDiff: Int
    var points: Int
}

enum SketchData {
    static let clubs: [String: SketchClub] = [
        "MOS": SketchClub(code: "MOS", primary: 0x4F8A3C, secondary: 0xF2E6C9),
        "GLO": SketchClub(code: "GLO", primary: 0x6C4AB6, secondary: 0xFFD84D),
        "NEB": SketchClub(code: "NEB", primary: 0x1F3B73, secondary: 0x7FD1F5),
        "ROC": SketchClub(code: "ROC", primary: 0xE4572E, secondary: 0x2B2D42),
        "DUN": SketchClub(code: "DUN", primary: 0xE8A33D, secondary: 0x5A2E0E),
        "MIR": SketchClub(code: "MIR", primary: 0xC1476B, secondary: 0xF6E7D8),
        "GLW": SketchClub(code: "GLW", primary: 0x9CC7E0, secondary: 0x1D3557),
        "COR": SketchClub(code: "COR", primary: 0xFF7F66, secondary: 0x0F6E7A),
    ]
    static let player = "DUN"
    static let opponent = "NEB"

    /// The table after matchday 4.
    static let before: [SketchStanding] = [
        .init(code: "ROC", played: 4, goalDiff: 6, points: 10),
        .init(code: "NEB", played: 4, goalDiff: 4, points: 9),
        .init(code: "GLO", played: 4, goalDiff: 2, points: 7),
        .init(code: "DUN", played: 4, goalDiff: 1, points: 6),
        .init(code: "MOS", played: 4, goalDiff: 0, points: 5),
        .init(code: "COR", played: 4, goalDiff: -2, points: 4),
        .init(code: "MIR", played: 4, goalDiff: -4, points: 3),
        .init(code: "GLW", played: 4, goalDiff: -7, points: 1),
    ]

    /// The table after matchday 5: DUN 3–1 NEB, ROC 1–1 GLO, MOS 2–1 COR, MIR 1–0 GLW.
    static let after: [SketchStanding] = ranked([
        .init(code: "ROC", played: 5, goalDiff: 6, points: 11),
        .init(code: "NEB", played: 5, goalDiff: 2, points: 9),
        .init(code: "GLO", played: 5, goalDiff: 2, points: 8),
        .init(code: "DUN", played: 5, goalDiff: 3, points: 9),
        .init(code: "MOS", played: 5, goalDiff: 1, points: 8),
        .init(code: "COR", played: 5, goalDiff: -3, points: 4),
        .init(code: "MIR", played: 5, goalDiff: -3, points: 6),
        .init(code: "GLW", played: 5, goalDiff: -8, points: 1),
    ])

    /// §11.4's order: points, goal difference, then code (goals for is not faked here).
    static func ranked(_ s: [SketchStanding]) -> [SketchStanding] {
        s.sorted { ($0.points, $0.goalDiff, $1.code) > ($1.points, $1.goalDiff, $0.code) }
    }

    /// The fake match: 30 s on the clock, goals at these clock seconds elapsed (true = ours).
    static let matchSeconds = 30.0
    static let goals: [(at: Double, home: Bool)] = [(5, true), (11, false), (17.5, true), (24, true)]
}

/// Localized copy for the sketch (keys in Localizable.xcstrings).
func L(_ key: String.LocalizationValue) -> String { String(localized: key) }
