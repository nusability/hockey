import RealityKit

/// The order the match's see-through parts are drawn in (spec §8.8) — the twin of Android's
/// renderable priorities (`Materials.flatOwned`, `Geometry.priority`).
///
/// Everything here is blended and writes no depth: the discs under the players and the ball, the
/// ring the ball circles on, the pops, the nets' film, the ball's trail and every part of the aim
/// arrow. Without a group RealityKit sorts blended parts back to front **by the centre of each
/// part's bounds** — and the parts these compete with are all centred on the pitch's origin: the
/// aim meshes carry one fixed box round the whole pitch, and every world effect is given a box a
/// kilometre wide so its shader can move it (`WorldEffects`). A decal under a player is therefore
/// "nearer than the pitch centre" in our own half and "further" beyond the halfway line — the
/// camera stands behind the player's own goal (§8.6) — so it changed places with them at the
/// halfway line and was painted over in the opponent's half (SMASH-33's sibling: same symptom,
/// order rather than culling). One group with one stated order cannot flip.
@MainActor
enum DrawOrder {
    /// Every see-through part of the match is in this one group, so the order below is the order.
    static let pitch = ModelSortGroup(depthPass: nil)

    /// Lowest first. The ground marks lie under everything; the arrow is drawn over them, its glows
    /// under their own solid parts, exactly as before.
    static let disc: Int32 = 0          // the discs under the players and the ball
    static let offside: Int32 = 1       // the ring under a player the whistle would name (§8.9)
    static let net: Int32 = 2           // the nets' film (their cords are solid)
    static let pop: Int32 = 3           // a save, a steal or a block
    static let orbit: Int32 = 4         // the ring the ball circles on
    static let trail: Int32 = 5         // the loose ball's ribbon
    static let lock: Int32 = 6          // the lock-on: the receiver's ring, the dots, the goal glow
    static let arrowGlow: Int32 = 7
    static let arrow: Int32 = 8         // the chevron ribbon
    static let headGlow: Int32 = 9
    static let head: Int32 = 10

    /// Puts `entity` in the group at `order`.
    static func set(_ entity: Entity, _ order: Int32) {
        entity.components.set(ModelSortGroupComponent(group: pitch, order: order))
    }
}
