package `in`.nann.smashhockey.core.telemetry

import `in`.nann.smashhockey.core.generated.Envelope
import `in`.nann.smashhockey.core.generated.FeedbackRow
import `in`.nann.smashhockey.core.generated.LoveRow
import `in`.nann.smashhockey.core.generated.MatchRow
import `in`.nann.smashhockey.core.generated.SeasonRow
import `in`.nann.smashhockey.core.generated.Tuning

/**
 * What leaves the device (spec §18), as values: one row waiting for its send, and the bounded backlog
 * it waits in. The iOS twin is SmashCore's `Telemetry/Outbox.swift`.
 *
 * **Nothing here can send anything, and that is the design** (§18.8, A0). The types on the enqueue
 * path name no network, no file, no thread and no clock, so "appending a row cannot cost a frame" is
 * a property of what this code *is* — readable in one screen and checked by `TelemetrySourceTest` —
 * rather than a claim measured after the fact. The platform layer owns the sending: the HTTP client,
 * the background executor and the two moments a flush is allowed. All it may do on the main thread is
 * [Outbox.append].
 */
sealed interface TelemetryRow {
    data class Match(val body: MatchRow.Body) : TelemetryRow
    data class Season(val body: SeasonRow.Body) : TelemetryRow
    data class Love(val body: LoveRow.Body) : TelemetryRow

    /**
     * A player's own words (§18.5). `FeedbackRow.Body` is the only body with a text field at all,
     * which is what makes "free text never rides an analytics row" a compile error rather than a rule
     * to remember: there is nowhere in `MatchRow.Body`, `SeasonRow.Body` or `LoveRow.Body` to put a
     * message, so a call site holding one can only build this case.
     */
    data class Feedback(val body: FeedbackRow.Body) : TelemetryRow

    /**
     * The collector's table for this row, and so the route it is posted to (§18.6). Taken from the
     * generated record, never spelled here: nothing outside telemetry.toml names a table.
     */
    val table: String
        get() = when (this) {
            is Match -> MatchRow.table
            is Season -> SeasonRow.table
            is Love -> LoveRow.table
            is Feedback -> FeedbackRow.table
        }

    /**
     * The row's canonical JSON, stamped with the envelope of the send that carries it (§18.1). Called
     * on the sending path and never on the enqueue path — building it is work, and work near the
     * frame is what §18.8 exists to forbid.
     */
    fun encoded(envelope: Envelope): String = when (this) {
        is Match -> MatchRow(envelope, body).encoded()
        is Season -> SeasonRow(envelope, body).encoded()
        is Love -> LoveRow(envelope, body).encoded()
        is Feedback -> FeedbackRow(envelope, body).encoded()
    }
}

/**
 * The rows waiting to go (spec §18.8): an ordinary list with one rule, held by the platform layer and
 * **never written to disk**. A lost row changes no decision we will make; a second persisted shape
 * near the frame would cost more than the rows are worth.
 */
class Outbox {
    private val queued = ArrayList<TelemetryRow>()

    val rows: List<TelemetryRow> get() = queued
    val isEmpty: Boolean get() = queued.isEmpty()
    val count: Int get() = queued.size

    /**
     * Takes a row. Past the bound the **oldest** goes: what just happened is the thing worth keeping,
     * and a row that has already waited through a whole backlog is the one whose loss costs least.
     * Dropping the newest instead would make a long offline stretch invisible exactly where it
     * matters.
     */
    fun append(row: TelemetryRow) {
        queued.add(row)
        while (queued.size > BOUND) queued.removeAt(0)
    }

    /**
     * Everything waiting, and the outbox emptied. The send takes the rows with it, so a failure loses
     * them (§18.8) rather than queueing them behind the next one — a retry is a stall waiting to
     * happen, and nothing may stand between a result and the next face-off (A2).
     */
    fun drain(): List<TelemetryRow> {
        val batch = ArrayList(queued)
        queued.clear()
        return batch
    }

    companion object {
        /** The most rows kept at once (shared/data/rules.toml [telemetry]). */
        const val BOUND: Int = Tuning.Telemetry.backlog
    }
}
