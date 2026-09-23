package `in`.nann.smashhockey.core.match

import `in`.nann.smashhockey.core.generated.Drill
import `in`.nann.smashhockey.core.generated.Formation
import `in`.nann.smashhockey.core.generated.Sport
import `in`.nann.smashhockey.core.generated.Tactics

/**
 * A golden vector of the simulation (spec §4.7): a setup, the player's input as (tick, finger)
 * events, and the match it produces — sampled state every [every] ticks and every event — as text
 * with every double written as the hex of its bits. iOS's `MatchVector` reads and writes the same
 * format (its doc comment spells the lines out); both replay shared/vectors/match/ line by line,
 * never with a tolerance.
 */
class MatchVector(val setup: Setup, val every: Int, val maxTicks: Int, val inputs: List<Input>) {
    sealed interface Setup {
        data class OfMatch(val setup: MatchSetup) : Setup
        data class OfDrill(val setup: DrillSetup) : Setup
    }

    /** The finger going [down] (or up) at the boundary once [tick] ticks have run. */
    data class Input(val tick: Int, val down: Boolean)

    fun makeMatch(): Match = when (setup) {
        is Setup.OfMatch -> Match(setup.setup)
        is Setup.OfDrill -> Match(setup.setup)
    }

    /** The body lines this vector produces: events and samples, in order. */
    fun run(): List<String> {
        val match = makeMatch()
        val lines = ArrayList<String>()
        for (e in match.drainEvents()) lines.add("e 0 " + format(e))
        lines.add(sample(match))
        var next = 0
        while (match.ticks < maxTicks && match.state != MatchState.ENDED) {
            while (next < inputs.size && inputs[next].tick == match.ticks) {
                match.hold(inputs[next].down)
                next += 1
            }
            match.tick()
            for (e in match.drainEvents()) lines.add("e ${match.ticks} " + format(e))
            if (match.ticks % every == 0 || match.state == MatchState.ENDED) lines.add(sample(match))
        }
        return lines
    }

    companion object {
        fun sample(m: Match): String {
            val b = m.ball
            val t = arrayListOf(
                "s", m.ticks.toString(), m.state.key, m.period.toString(), if (m.overtime) "1" else "0", hex(m.clock),
                m.score[0].toString(), m.score[1].toString(), hex(m.streamState),
                hex(b.pos.x), hex(b.pos.z), hex(b.vel.x), hex(b.vel.z), (b.carrier ?: -1).toString(),
                hex(b.orbit), hex(b.orbitDirection),
            )
            for (p in m.players) {
                t += listOf(hex(p.pos.x), hex(p.pos.z), hex(p.vel.x), hex(p.vel.z), hex(p.facing))
            }
            return t.joinToString(" ")
        }

        fun format(e: MatchEvent): String {
            fun who(i: Int?) = i?.toString() ?: "-"
            return when (e) {
                is MatchEvent.FaceOff -> "faceoff ${hex(e.spot.x)} ${hex(e.spot.z)}"
                MatchEvent.Play -> "play"
                MatchEvent.Ready -> "ready"
                is MatchEvent.Pickup -> "pickup ${e.player}"
                is MatchEvent.Pass -> "pass ${e.from} ${e.to}"
                is MatchEvent.Shot -> "shot ${e.by} ${e.kind.key}"
                is MatchEvent.Steal -> "steal ${e.by} ${e.from}"
                is MatchEvent.Save -> "save ${e.by}"
                is MatchEvent.Block -> "block ${e.by}"
                MatchEvent.Post -> "post"
                is MatchEvent.Board -> "board ${hex(e.speed)}"
                is MatchEvent.Goal -> "goal ${e.team} ${who(e.scorer)} ${who(e.assist)} ${if (e.ownGoal) 1 else 0}"
                MatchEvent.Whistle -> "whistle"
                is MatchEvent.Offside -> "offside ${e.team} ${e.player}"
                is MatchEvent.PeriodEnd -> "periodEnd ${e.period}"
                is MatchEvent.DrillInterrupted -> "interrupted ${e.reason.key}"
                is MatchEvent.End -> "end ${e.result.key}"
            }
        }

        fun hex(bits: Long): String = java.lang.Long.toHexString(bits).uppercase().padStart(16, '0')

        fun hex(d: Double): String = hex(d.toRawBits())

        /** Parses a vector file into the vector and the body lines it recorded. */
        fun parse(text: String): Pair<MatchVector, List<String>> {
            var setup: Setup? = null
            var every: Int? = null
            var maxTicks: Int? = null
            val inputs = ArrayList<Input>()
            val body = ArrayList<String>()
            for (line in text.split("\n")) {
                if (line.isEmpty() || line.startsWith("#")) continue
                val t = Tokens(line.split(" "))
                when (val kind = t.word()) {
                    "setup" -> setup = parseSetup(t)
                    "every" -> every = t.int()
                    "ticks" -> maxTicks = t.int()
                    "input" -> {
                        val tick = t.int()
                        val edge = t.word()
                        require(edge == "down" || edge == "up") { "input edge $edge is not down|up" }
                        inputs.add(Input(tick, edge == "down"))
                    }
                    "s", "e" -> body.add(line)
                    else -> throw IllegalArgumentException("unknown line kind $kind")
                }
            }
            requireNotNull(setup) { "a vector needs a setup line" }
            requireNotNull(every) { "a vector needs an every line" }
            requireNotNull(maxTicks) { "a vector needs a ticks line" }
            return Pair(MatchVector(setup, every, maxTicks, inputs), body)
        }

        private fun parseSetup(t: Tokens): Setup = when (val kind = t.word()) {
            "match" -> {
                t.expect("seed"); val seed = t.bits()
                t.expect("sport"); val sport = Sport.of(t.word())
                t.expect("period"); val period = t.double()
                t.expect("orbit"); val orbit = t.double()
                t.expect("cup"); val cup = t.int() == 1
                t.expect("control"); val control = Control.of(t.word())
                t.expect("home"); val home = parseSide(t)
                t.expect("away"); val away = parseSide(t)
                Setup.OfMatch(MatchSetup(seed, sport, home, away, period, orbit, cup, control))
            }
            "drill" -> {
                val id = t.word()
                val drill = Drill.entries.firstOrNull { it.key == id } ?: throw IllegalArgumentException("unknown drill $id")
                t.expect("seed"); val seed = t.bits()
                t.expect("orbit"); val orbit = t.double()
                t.expect("tactics"); val tactics = parseTactics(t)
                Setup.OfDrill(DrillSetup(drill, seed, tactics, orbit))
            }
            else -> throw IllegalArgumentException("unknown setup kind $kind")
        }

        private fun parseSide(t: Tokens): SideSetup {
            val rating = t.int()
            val formation = Formation.of(t.word())
            return SideSetup(rating, parseTactics(t), formation)
        }

        private fun parseTactics(t: Tokens) = Tactics(
            pressing = t.double(), covering = t.double(), pushUp = t.double(),
            passing = t.double(), shooting = t.double(), discipline = t.double(),
        )
    }

    private class Tokens(val items: List<String>) {
        var at = 0

        fun word(): String {
            require(at < items.size) { "line ends early: ${items.joinToString(" ")}" }
            return items[at++]
        }

        fun expect(w: String) {
            val got = word()
            require(got == w) { "expected $w, got $got" }
        }

        fun int(): Int = word().toInt()

        fun bits(): Long {
            val w = word()
            require(w.length == 16) { "$w is not 16 hex digits" }
            return java.lang.Long.parseUnsignedLong(w, 16)
        }

        fun double(): Double = Double.fromBits(bits())
    }
}
