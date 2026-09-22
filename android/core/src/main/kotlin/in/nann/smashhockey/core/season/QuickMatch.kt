package `in`.nann.smashhockey.core.season

import `in`.nann.smashhockey.core.generated.Club
import `in`.nann.smashhockey.core.generated.TeamKey
import `in`.nann.smashhockey.core.generated.World
import `in`.nann.smashhockey.core.math.SplitMix64
import kotlin.math.floor

/**
 * A quick match (spec §11.5): a friendly against a random club other than the player's, in a
 * random world, outside the season. Its two draws come from a stream of its own, seeded when the
 * quick match is chosen — never the season's, whose position a friendly must not move (§4.3).
 */
data class QuickMatch(val opponent: Club, val world: World) {
    companion object {
        /**
         * The opponent — `floor(u × n)` into the clubs as declared, less the player's club — then
         * the world, `floor(u × 5)` into the worlds as declared, from a stream seeded with [seed].
         */
        fun draw(seed: Long, player: TeamKey): QuickMatch {
            val rng = SplitMix64.seeded(seed)
            val clubs = Club.entries.filter { it != player.club }
            val opponent = clubs[floor(rng.uniform() * clubs.size.toDouble()).toInt()]
            val world = World.entries[floor(rng.uniform() * World.entries.size.toDouble()).toInt()]
            return QuickMatch(opponent, world)
        }
    }
}
