package `in`.nann.smashhockey.core.season

import `in`.nann.smashhockey.core.generated.BoardRecord
import `in`.nann.smashhockey.core.generated.Club
import `in`.nann.smashhockey.core.generated.CupRound
import `in`.nann.smashhockey.core.generated.Drill
import `in`.nann.smashhockey.core.generated.Formation
import `in`.nann.smashhockey.core.generated.MatchdayStep
import `in`.nann.smashhockey.core.generated.SaveRecord
import `in`.nann.smashhockey.core.generated.Season
import `in`.nann.smashhockey.core.generated.World

/**
 * Plays a season golden vector (shared/vectors/season/season-*.txt, recorded by iOS's
 * RecordSeasonVectors) through the save's API and writes its transcript — the same lines, in the
 * same format, as SmashCore's `SeasonScript`. The format is the vector's; the code is Android's own.
 */
class SeasonScript(val seed: Long, val career: String, val entries: List<Entry>) {
    data class Entry(val goalsFor: Int, val goalsAgainst: Int, val mode: String)

    fun startingSave(): SaveRecord {
        val w = career.split(" ", limit = 6)
        val save = when (w[0]) {
            "club" -> SaveRecord.fresh().chooseClub(Club.of(w[1]))
            "created" -> SaveRecord.fresh().createTeam(
                TeamDraft(w[5], w[1], w[2].substring(1).toInt(16), w[3].substring(1).toInt(16), World.of(w[4])),
            )
            else -> error("bad career: $career")
        }
        return save.startSeason(seed)
    }

    /** The transcript and the last save; see SmashCore's `SeasonScript.run` for [reloadAfter] and [stopAfter]. */
    fun run(reloadAfter: Int? = null, stopAfter: Int? = null): Pair<List<String>, SaveRecord> {
        var save = startingSave()
        val career = save.career!!
        val lines = mutableListOf("seed 0x" + SaveJson.hex(seed, 16), "career ${this.career}")
        entries.forEach { lines.add("script ${it.goalsFor} ${it.goalsAgainst} ${it.mode}") }
        val first = save.season!!
        lines.add("league " + first.teams.joinToString(" ") { career.short(it) })
        first.fixtures.forEach { lines.add("fixture ${it.matchday} ${label(it.matchday)} ${career.short(it.home)} ${career.short(it.away)}") }
        lines.add("stream 0x" + SaveJson.hex(first.stream, 16))
        var printed = 0
        printed = days(save, printed, lines)
        var played = 0
        while (!save.season!!.isFinished) {
            check(played < entries.size) { "the script ran out at matchday ${save.season!!.matchday}" }
            val entry = entries[played++]
            val f = save.playerFixture!!
            lines.add("play ${f.matchday} ${label(f.matchday)} ${career.short(f.home)} ${career.short(f.away)}")
            save = when (entry.mode) {
                "forfeit" -> save.forfeit().first
                "-", "ot" -> save.recordPlayed(entry.goalsFor, entry.goalsAgainst, entry.mode == "ot").first
                else -> error("bad mode ${entry.mode}")
            }
            if (played == reloadAfter) save = SaveRecord.decode(save.encoded())
            printed = days(save, printed, lines)
            lines.add("stream 0x" + SaveJson.hex(save.season!!.stream, 16))
            if (played == stopAfter) return lines to save
        }
        check(played == entries.size) { "the script has ${entries.size - played} lines too many" }
        val end = save.season!!
        val c = save.career!!
        lines.add("champion " + c.short(end.table(c)[0].team))
        lines.add("cupwinner " + c.short(end.cupWinner!!))
        lines.add("trophies ${c.leagueTitles} ${c.cups}")
        return lines to save
    }

    private fun days(save: SaveRecord, from: Int, lines: MutableList<String>): Int {
        val season = save.season!!
        val career = save.career!!
        var md = from
        while (md < season.matchday) {
            lines.add("day $md ${label(md)}")
            for (f in season.fixturesOn(md)) {
                val s = f.score!!
                val who = if (f.home == career.team || f.away == career.team) "player" else "sim"
                lines.add("result ${career.short(f.home)} ${career.short(f.away)} ${s.home} ${s.away} ${if (s.overtime) "ot" else "-"} $who")
            }
            val step = Season.plan[md]
            if (step is MatchdayStep.Cup && step.round != CupRound.entries.last()) {
                val next = CupRound.entries[CupRound.entries.indexOf(step.round) + 1]
                season.cupTies(next).forEach {
                    lines.add("cupdraw ${it.matchday} ${label(it.matchday)} ${career.short(it.home)} ${career.short(it.away)}")
                }
            }
            season.table(career, md).forEachIndexed { i, r ->
                lines.add("table ${i + 1} ${career.short(r.team)} ${r.played} ${r.won} ${r.drawn} ${r.lost} ${r.goalsFor} ${r.goalsAgainst} ${r.points}")
            }
            md++
        }
        return md
    }

    companion object {
        fun parse(text: String): SeasonScript {
            var seed: Long? = null
            var career: String? = null
            val entries = mutableListOf<Entry>()
            for (line in text.lines().filter { it.isNotEmpty() && !it.startsWith("#") }) {
                val w = line.split(" ")
                when (w[0]) {
                    "seed" -> seed = java.lang.Long.parseUnsignedLong(w[1].substring(2), 16)
                    "career" -> career = line.removePrefix("career ")
                    "script" -> entries.add(Entry(w[1].toInt(), w[2].toInt(), w[3]))
                }
            }
            return SeasonScript(seed ?: error("no seed line"), career ?: error("no career line"), entries)
        }

        fun label(md: Int): String = when (val step = Season.plan[md]) {
            is MatchdayStep.League -> "L${step.round}"
            is MatchdayStep.Cup -> step.round.key
        }

        /** A line of save/manifest.txt: the file and the state it holds (see SmashCore's `SaveVectorCase`). */
        fun saveCase(line: String, vector: (String) -> String): Pair<String, SaveRecord> {
            val w = line.split(" ")
            check(w.size == 5 || w.size == 11) { "bad manifest line: $line" }
            var save = SaveRecord.fresh()
            if (w[1] != "-") save = parse(vector(w[1])).run(stopAfter = if (w[2] == "end") null else w[2].toInt()).second
            if (w[3] != "-") w[3].split(",").forEach { save = save.won(Drill.of(it)) }
            if (w.size == 11) {
                save = save.copy(
                    board = BoardRecord(
                        w[4].toDouble(), w[5].toDouble(), w[6].toDouble(), w[7].toDouble(), Formation.of(w[8]),
                        w[9].toDouble(), w[10].toDouble(),
                    ),
                )
            }
            return w[0] to save
        }
    }
}
