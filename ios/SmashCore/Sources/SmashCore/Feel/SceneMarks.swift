import Foundation

/// The flat marks a match draws on the pitch (spec §8.8) — the ball's trail and the ring a save, a
/// steal or a block pops — and the boxes an app must bound their meshes by.
///
/// A mesh whose vertices are written in place carries its own bounds and the renderer culls the
/// entity against them (SMASH-33). Every such mesh here is written in the **pitch's** frame on an
/// entity that never moves, so one fixed box round the whole pitch can never go stale. The numbers
/// are shared so both platforms bound the same drawing the same way; the Android twin is
/// `core/feel/SceneMarks.kt`.
public enum SceneMarks {
    /// How far from the centre anything in a match can ever stand: the pitch (§1) and a player's
    /// radius of room past its boards, which holds a ball rebounding off them and a player pressed
    /// against them alike — a test walks whole matches against it.
    public static var reach: (x: Double, z: Double) {
        let room = Tuning.Player.outfieldRadius
        return (Tuning.Pitch.halfWidth + room, Tuning.Pitch.halfLength + room)
    }

    /// The ball's trail: a ribbon `width` wide through where the ball has been.
    public static func trailExtent(width: Double) -> (x: Double, z: Double) {
        (reach.x + width / 2, reach.z + width / 2)
    }

    /// The pops: a ring of at most `radius` round the spot where it happened.
    public static func popExtent(radius: Double) -> (x: Double, z: Double) {
        (reach.x + radius, reach.z + radius)
    }
}
