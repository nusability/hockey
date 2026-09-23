/// What leaves the device (spec §18), as values: one row waiting for its send, and the bounded
/// backlog it waits in. The Android twin is `core/telemetry/Outbox.kt`.
///
/// **Nothing here can send anything, and that is the design** (§18.8, A0). The types on the enqueue
/// path name no network, no file, no thread and no clock, so "appending a row cannot cost a frame"
/// is a property of what this code *is* — readable in one screen and checked by
/// `TelemetrySourceTests` — rather than a claim measured after the fact. The platform layer owns the
/// sending: the HTTP client, the background queue and the two moments a flush is allowed. All it may
/// do on the main actor is `append`.
public enum TelemetryRow: Sendable, Hashable {
    case match(MatchRow.Body)
    case season(SeasonRow.Body)
    case love(LoveRow.Body)
    /// A player's own words (§18.5). `FeedbackRow.Body` is the only body with a text field at all,
    /// which is what makes "free text never rides an analytics row" a compile error rather than a
    /// rule to remember: there is nowhere in `MatchRow.Body`, `SeasonRow.Body` or `LoveRow.Body` to
    /// put a message, so a call site holding one can only build this case.
    case feedback(FeedbackRow.Body)

    /// The collector's table for this row, and so the route it is posted to (§18.6). Taken from the
    /// generated record, never spelled here: nothing outside `telemetry.toml` names a table.
    public var table: String {
        switch self {
        case .match: MatchRow.table
        case .season: SeasonRow.table
        case .love: LoveRow.table
        case .feedback: FeedbackRow.table
        }
    }

    /// The row's canonical JSON, stamped with the envelope of the send that carries it (§18.1).
    /// Called on the sending path and never on the enqueue path — building it is work, and work
    /// near the frame is what §18.8 exists to forbid.
    public func encoded(_ envelope: Envelope) -> String {
        switch self {
        case .match(let body): MatchRow(envelope, body).encoded()
        case .season(let body): SeasonRow(envelope, body).encoded()
        case .love(let body): LoveRow(envelope, body).encoded()
        case .feedback(let body): FeedbackRow(envelope, body).encoded()
        }
    }
}

/// The rows waiting to go (spec §18.8): an ordinary array with one rule, held by the platform layer
/// and **never written to disk**. A lost row changes no decision we will make; a second persisted
/// shape near the frame would cost more than the rows are worth.
public struct Outbox: Sendable, Hashable {
    /// The most rows kept at once (`shared/data/rules.toml [telemetry]`).
    public static let bound = Tuning.Telemetry.backlog

    public private(set) var rows: [TelemetryRow] = []

    public init() {}

    public var isEmpty: Bool { rows.isEmpty }
    public var count: Int { rows.count }

    /// Takes a row. Past the bound the **oldest** goes: what just happened is the thing worth
    /// keeping, and a row that has already waited through a whole backlog is the one whose loss
    /// costs least. Dropping the newest instead would make a long offline stretch invisible exactly
    /// where it matters.
    public mutating func append(_ row: TelemetryRow) {
        rows.append(row)
        if rows.count > Self.bound { rows.removeFirst(rows.count - Self.bound) }
    }

    /// Everything waiting, and the outbox emptied. The send takes the rows with it, so a failure
    /// loses them (§18.8) rather than queueing them behind the next one — a retry is a stall waiting
    /// to happen, and nothing may stand between a result and the next face-off (A2).
    public mutating func drain() -> [TelemetryRow] {
        defer { rows = [] }
        return rows
    }
}
