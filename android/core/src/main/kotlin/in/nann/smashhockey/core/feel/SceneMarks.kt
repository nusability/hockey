package `in`.nann.smashhockey.core.feel

import `in`.nann.smashhockey.core.generated.Tuning

/**
 * The flat marks a match draws on the pitch (spec §8.8) — the ball's trail and the ring a save, a
 * steal or a block pops — and the boxes an app must bound their meshes by.
 *
 * A mesh whose vertices are written in place carries its own bounds and the renderer culls against
 * them (SMASH-33). Every such mesh here is written in the **pitch's** frame on a node that never
 * moves, so one fixed box round the whole pitch can never go stale. The numbers are shared so both
 * platforms bound the same drawing the same way; the iOS twin is `SmashCore/Feel/SceneMarks.swift`.
 */
object SceneMarks {
    /** Across the pitch, and along it: how far anything in a match can ever stand from the centre. */
    data class Reach(val x: Double, val z: Double)

    /**
     * The pitch (§1) and a player's radius of room past its boards, which holds a ball rebounding off
     * them and a player pressed against them alike — a test walks whole matches against it.
     */
    val reach: Reach
        get() {
            val room = Tuning.Player.outfieldRadius
            return Reach(Tuning.Pitch.halfWidth + room, Tuning.Pitch.halfLength + room)
        }

    /** The ball's trail: a ribbon [width] wide through where the ball has been. */
    fun trailExtent(width: Double) = Reach(reach.x + width / 2, reach.z + width / 2)

    /** The pops: a ring of at most [radius] round the spot where it happened. */
    fun popExtent(radius: Double) = Reach(reach.x + radius, reach.z + radius)
}
