/// The device record (spec §17.1, shared/data/telemetry.toml): what this install remembers about
/// itself, as a value with pure transitions. The Android twin is `core/telemetry/Device.kt`.
///
/// Every transition **returns a new record** rather than mutating a store: the writing is the
/// platform layer's job (a `DeviceStore` twinned on `SaveStore`), and the deciding is the core's. A
/// value is also the only shape a golden vector can pin byte for byte.
extension DeviceRecord {
    /// A device seen for the first time: never asked, nothing played.
    public static func fresh(at now: Int64) -> DeviceRecord {
        DeviceRecord(version: TelemetryFormat.version, installedAt: now, matchesPlayed: 0,
                     lastAskedAt: nil, answeredPositively: false)
    }

    /// What replaces a record we could not read (§17.1).
    ///
    /// **Stamped as if the prompt had just been shown**, which is the one thing that matters here: a
    /// lost record must read as brand new and serving a full cooldown, never as
    /// long-ago-and-eligible. Otherwise a single corrupt byte re-arms the prompt for someone who has
    /// already answered it — the exact outcome the rationing exists to prevent. A refused device
    /// record is never a screen: telemetry may not block the game.
    public static func replacement(at now: Int64) -> DeviceRecord {
        var record = fresh(at: now)
        record.lastAskedAt = now
        return record
    }

    // MARK: - The file

    /// The canonical JSON (shared/data/telemetry.toml) — byte for byte what Android writes.
    public func encoded() -> String { json().canonicalText() }

    /// Reads a device record. Fails, typed, on anything but a well-formed record of this version —
    /// the caller replaces it with `replacement(at:)` and carries on.
    public static func decode(_ bytes: [UInt8]) throws(SaveDecodeError) -> DeviceRecord {
        let json = try JSONValue.parse(bytes)
        guard case .object(let members) = json else { throw .wrongType(path: "$") }
        guard let version = members.first(where: { $0.key == "version" })?.value else {
            throw .missingField(path: "$.version")
        }
        guard case .int(let v) = version else { throw .wrongType(path: "$.version") }
        guard v == TelemetryFormat.version else { throw .unknownVersion(v) }
        return try DeviceRecord(json: json, at: "$")
    }

    public static func decode(_ text: String) throws(SaveDecodeError) -> DeviceRecord {
        try decode(Array(text.utf8))
    }

    // MARK: - The transitions (spec §17.1)

    /// A match the player finished, however it ended. The count is lifetime and lives here rather
    /// than in the save precisely so that starting over does not un-earn it (§17.1).
    public func recordingPlayedMatch() -> DeviceRecord {
        var next = self
        next.matchesPlayed += 1
        return next
    }

    /// The panel went up. **The cooldown starts at the presentation, not at the answer** (§17.2): a
    /// player who is shown the panel and walks away has been asked, and an ignored prompt that
    /// re-appeared tomorrow would be the rudest version of this feature.
    public func recordingPresentation(at now: Int64) -> DeviceRecord {
        var next = self
        next.lastAskedAt = now
        return next
    }

    /// The player answered. Only a positive answer changes anything durable — a no and a dismissal
    /// are already paid for by the cooldown the presentation started, and there is no "never ask
    /// again" button because a yes *is* the never and a dismissal *is* the later (§17.2).
    public func recording(_ answer: LoveAnswer) -> DeviceRecord {
        guard answer == .positive else { return self }
        var next = self
        next.answeredPositively = true
        return next
    }

    /// The facts the policy decides from, for a moment that armed `trigger` and a switch read from
    /// config. This record deliberately knows nothing about either.
    public func loveFacts(armed trigger: LoveTrigger?, remote: LoveSwitch) -> LoveFacts {
        LoveFacts(armed: trigger, lastAskedAt: lastAskedAt, answeredPositively: answeredPositively,
                  remote: remote)
    }
}

/// How the player answered the panel (spec §17.2). Tapping the scrim is `dismissed` — a third
/// answer, never a no-op.
public enum LoveAnswer: String, Sendable, Hashable, CaseIterable {
    case positive, negative, dismissed
}

// MARK: - The rules a decoded record is checked against

extension DeviceRecord {
    func validate(at path: String) throws(SaveDecodeError) {
        guard matchesPlayed >= 0 else { throw .brokenRule(path: path + ".matches_played", .negativeCount) }
        guard installedAt >= 0 else { throw .brokenRule(path: path + ".installed_at", .negativeInstant) }
        if let lastAskedAt {
            guard lastAskedAt >= 0 else { throw .brokenRule(path: path + ".last_asked_at", .negativeInstant) }
        } else if answeredPositively {
            // The presentation stamps the instant and the answer follows it, so a yes without one is
            // a record that cannot have arisen. A clock that ran backwards, by contrast, makes
            // last_asked_at < installed_at — legitimate, and deliberately not a rule.
            throw .brokenRule(path: path + ".answered_positively", .answeredWithoutAsking)
        }
    }
}
