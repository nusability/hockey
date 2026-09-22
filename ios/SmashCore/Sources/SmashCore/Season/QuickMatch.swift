/// A quick match (spec §11.5): a friendly against a random club other than the player's, in a
/// random world, outside the season. Its two draws come from a stream of its own, seeded when the
/// quick match is chosen — never the season's, whose position a friendly must not move (§4.3).
public struct QuickMatch: Sendable, Hashable {
    public let opponent: Club
    public let world: World

    /// The opponent — `floor(u × n)` into the clubs as declared, less the player's club — then
    /// the world, `floor(u × 5)` into the worlds as declared, from a stream seeded with `seed`.
    public init(seed: UInt64, player: TeamKey) {
        var rng = SplitMix64(seed: seed)
        let clubs = Club.allCases.filter { $0 != player.club }
        opponent = clubs[Int((rng.uniform() * Double(clubs.count)).rounded(.down))]
        world = World.allCases[Int((rng.uniform() * Double(World.allCases.count)).rounded(.down))]
    }
}
