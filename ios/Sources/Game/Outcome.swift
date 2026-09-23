import SmashCore

/// How a match or drill ended, for the result screen (§16.5).
struct Outcome: Equatable {
    let plan: MatchPlan
    let score: [Int]
    let overtime: Bool
    let result: MatchResult
    let codes: [String]?
    /// The two sides' full names, home first — shown under the codes (§16.5); nil in a drill.
    let names: [String]?
    let colours: [TeamColours]
    let drillGoals: Int?
}
