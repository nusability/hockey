package `in`.nann.smashhockey.core.telemetry

import `in`.nann.smashhockey.core.generated.DeviceRecord

/**
 * The love-dialog golden vector (spec §4.7, §17, shared/vectors/telemetry/love.txt): a script of steps
 * carrying the clock, replayed against the policy and the device record.
 *
 * iOS's `RecordTelemetryVectors` writes the file; `TelemetryVectorTest` here and `SmashCoreTests`
 * recompute every output line from the input lines and must reproduce them exactly. The iOS twin is
 * SmashCore's `Telemetry/LoveScript.swift`.
 *
 * This is the whole bet of ADR 0009: a time-dependent policy that can be pinned headlessly. A clock
 * moved backwards, a cooldown straddling a clock change, a record we lost, an answer already given —
 * each is one line here instead of three months on a phone.
 */
class LoveScript(val steps: List<Step>) {

    class Failure(message: String) : Exception(message)

    /** One input line. Everything else in the file is output. */
    sealed interface Step {
        /**
         * `launch <now> <fresh|lost> <install id>` — the record was read, or lost and replaced
         * (§17.1). The id is an input like the clock: the platform mints it and hands it in, so the
         * corpus pins a chosen one rather than a random one.
         */
        data class Launch(val now: Long, val lost: Boolean, val installId: String) : Step

        /** `match <now> <duration> <cup|league|-> <goal…>` — a finished player match. */
        data class Match(val now: Long, val match: LoveMatch) : Step

        /** `settle <now> <unread|on|off>` — a settled screen (§17.3), the kill switch in that state. */
        data class Settle(val now: Long, val remote: LoveSwitch) : Step

        /** `answer <now> <positive|negative|dismissed>` — the answer to the panel that is up. */
        data class Answer(val now: Long, val answer: LoveAnswer) : Step

        /** `bytes <file>` — the record's canonical JSON is that file, exactly. */
        data class Bytes(val file: String) : Step
    }

    companion object {
        /** Reads a vector's input lines; everything else in the file is output and is ignored here. */
        fun parse(text: String): LoveScript {
            val steps = mutableListOf<Step>()
            for (line in text.lines()) {
                if (line.isEmpty() || line.startsWith("#")) continue
                val w = line.split(" ")
                fun now(): Long = w.getOrNull(1)?.toLongOrNull() ?: throw Failure("bad instant: $line")
                when (w[0]) {
                    "launch" -> {
                        if (w.size != 4 || (w[2] != "fresh" && w[2] != "lost")) throw Failure("bad launch line: $line")
                        steps.add(Step.Launch(now(), w[2] == "lost", w[3]))
                    }
                    "match" -> {
                        val duration = w.getOrNull(2)?.toIntOrNull() ?: throw Failure("bad match line: $line")
                        if (w.size < 4) throw Failure("bad match line: $line")
                        val goals = w.drop(4).map { item ->
                            val parts = item.split("@")
                            if (parts.size != 2 || (parts[0] != "f" && parts[0] != "a")) throw Failure("bad goal $item: $line")
                            LoveMatch.Goal(parts[0] == "f", parts[1].toIntOrNull() ?: throw Failure("bad goal $item: $line"))
                        }
                        if (w[3] !in listOf("cup", "league", "-")) throw Failure("bad trophy ${w[3]}: $line")
                        steps.add(Step.Match(now(), LoveMatch(goals, duration, w[3] == "cup", w[3] == "league")))
                    }
                    "settle" -> {
                        val remote = LoveSwitch.entries.firstOrNull { it.key == w.getOrNull(2) }
                            ?: throw Failure("bad settle line: $line")
                        steps.add(Step.Settle(now(), remote))
                    }
                    "answer" -> {
                        val answer = LoveAnswer.entries.firstOrNull { it.key == w.getOrNull(2) }
                            ?: throw Failure("bad answer line: $line")
                        steps.add(Step.Answer(now(), answer))
                    }
                    "bytes" -> {
                        if (w.size != 2) throw Failure("bad bytes line: $line")
                        steps.add(Step.Bytes(w[1]))
                    }
                    else -> continue
                }
            }
            if (steps.isEmpty()) throw Failure("a vector needs at least one step")
            return LoveScript(steps)
        }
    }

    /**
     * Replays the script. Every step's input line is re-emitted followed by its outputs, so the
     * returned lines are the whole file below its header. A `bytes` step calls [pinning] with the
     * file's name and the record as it stands.
     *
     * The runner is the platform layer's part of the dance, reduced to nothing: a record, and the
     * trigger a moment armed, held until a settled screen shows it. Deliberately **not** durable —
     * arming is a session fact, so a prompt earned and not reached is simply earned again.
     */
    fun run(pinning: (String, DeviceRecord) -> Unit): List<String> {
        // A script starts with a launch, so the record the replay begins from is the one that line
        // describes — there is no record before the app has read one, and nothing to invent an install
        // id for. The loop then re-derives it as its first step.
        val first = steps.firstOrNull() as? Step.Launch ?: throw Failure("a script starts with a launch line")
        var record = if (first.lost) DeviceRecord.replacement(first.now, first.installId)
        else DeviceRecord.fresh(first.now, first.installId)
        var armed: LoveTrigger? = null
        var up = false
        val lines = mutableListOf<String>()

        fun state() = "  state ${record.matchesPlayed} ${record.installedAt} ${record.lastAskedAt ?: "-"} " +
            "${if (record.answeredPositively) "yes" else "no"} ${armed?.key ?: "-"}"

        for (step in steps) {
            when (step) {
                is Step.Launch -> {
                    lines.add("launch ${step.now} ${if (step.lost) "lost" else "fresh"} ${step.installId}")
                    record = if (step.lost) DeviceRecord.replacement(step.now, step.installId)
                    else DeviceRecord.fresh(step.now, step.installId)
                    armed = null
                    up = false
                    lines.add(state())
                }
                is Step.Match -> {
                    val m = step.match
                    val goals = m.goals.map { "${if (it.mine) "f" else "a"}@${it.atMillis}" }
                    val trophy = if (m.wonCup) "cup" else if (m.wonLeague) "league" else "-"
                    lines.add((listOf("match", "${step.now}", "${m.durationMillis}", trophy) + goals).joinToString(" "))
                    record = record.recordingPlayedMatch()
                    val trigger = LovePolicy.trigger(m, record.matchesPlayed)
                    // A moment that arms nothing leaves a moment that already did alone: the prompt is
                    // earned once and waits for a settled screen (§17.3).
                    if (trigger != null) armed = trigger
                    lines.add(
                        "  result ${m.goalsFor}-${m.goalsAgainst}" +
                            " ${if (m.won) "won" else if (m.goalsFor == m.goalsAgainst) "drew" else "lost"}" +
                            " ${if (m.trailed) "trailed" else "-"}" +
                            " ${m.winningGoalMillis ?: "-"}" +
                            " ${if (m.winningGoalWasLate) "late" else "-"}" +
                            " ${if (m.wasHardFought) "hard" else "-"}",
                    )
                    lines.add("  trigger ${trigger?.key ?: "-"}")
                    lines.add(state())
                }
                is Step.Settle -> {
                    lines.add("settle ${step.now} ${step.remote.key}")
                    val verdict = LovePolicy.decide(record.loveFacts(armed, step.remote), step.now)
                    if (verdict == LoveVerdict.ASK) {
                        record = record.recordingPresentation(step.now)
                        armed = null
                        up = true
                    }
                    lines.add("  verdict ${verdict.key}")
                    lines.add(state())
                }
                is Step.Answer -> {
                    lines.add("answer ${step.now} ${step.answer.key}")
                    if (!up) throw Failure("answered at ${step.now} with no panel up")
                    record = record.recording(step.answer)
                    up = false
                    lines.add(state())
                }
                is Step.Bytes -> {
                    lines.add("bytes ${step.file}")
                    pinning(step.file, record)
                }
            }
        }
        return lines
    }
}
