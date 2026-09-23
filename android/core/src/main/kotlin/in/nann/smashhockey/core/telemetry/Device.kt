package `in`.nann.smashhockey.core.telemetry

import `in`.nann.smashhockey.core.generated.DeviceRecord
import `in`.nann.smashhockey.core.generated.TelemetryFormat
import `in`.nann.smashhockey.core.season.JsonValue
import `in`.nann.smashhockey.core.season.SaveDecodeError
import `in`.nann.smashhockey.core.season.SaveDecodeException
import `in`.nann.smashhockey.core.season.SaveRule
import `in`.nann.smashhockey.core.season.refuse

/*
 * The device record (spec §17.1, shared/data/telemetry.toml): what this install remembers about
 * itself, as a value with pure transitions. The iOS twin is SmashCore's `Telemetry/Device.swift`.
 *
 * Every transition **returns a new record** rather than mutating a store: the writing is the platform
 * layer's job (a `DeviceStore` twinned on `SaveStore`), and the deciding is the core's. A value is
 * also the only shape a golden vector can pin byte for byte.
 */

/** A device seen for the first time: never asked, nothing played. */
fun DeviceRecord.Companion.fresh(now: Long): DeviceRecord =
    DeviceRecord(TelemetryFormat.version, now, 0, null, false)

/**
 * What replaces a record we could not read (§17.1).
 *
 * **Stamped as if the prompt had just been shown**, which is the one thing that matters here: a lost
 * record must read as brand new and serving a full cooldown, never as long-ago-and-eligible.
 * Otherwise a single corrupt byte re-arms the prompt for someone who has already answered it — the
 * exact outcome the rationing exists to prevent. A refused device record is never a screen: telemetry
 * may not block the game.
 */
fun DeviceRecord.Companion.replacement(now: Long): DeviceRecord = fresh(now).copy(lastAskedAt = now)

// --- The file ------------------------------------------------------------------------------------

/** The canonical JSON (shared/data/telemetry.toml) — byte for byte what iOS writes. */
fun DeviceRecord.encoded(): String = toJson().canonicalText()

/**
 * Reads a device record. Throws [SaveDecodeException], typed, on anything but a well-formed record of
 * this version — the caller replaces it with [DeviceRecord.Companion.replacement] and carries on.
 */
fun DeviceRecord.Companion.decode(bytes: ByteArray): DeviceRecord {
    val json = JsonValue.parse(bytes)
    if (json !is JsonValue.Obj) refuse(SaveDecodeError.WrongType("$"))
    val version = json.members.firstOrNull { it.first == "version" }?.second
        ?: refuse(SaveDecodeError.MissingField("$.version"))
    if (version !is JsonValue.Num) refuse(SaveDecodeError.WrongType("$.version"))
    if (version.value != TelemetryFormat.version.toLong()) refuse(SaveDecodeError.UnknownVersion(version.value))
    return fromJson(json, "$")
}

fun DeviceRecord.Companion.decode(text: String): DeviceRecord = decode(text.toByteArray(Charsets.UTF_8))

// --- The transitions (spec §17.1) ----------------------------------------------------------------

/**
 * A match the player finished, however it ended. The count is lifetime and lives here rather than in
 * the save precisely so that starting over does not un-earn it (§17.1).
 */
fun DeviceRecord.recordingPlayedMatch(): DeviceRecord = copy(matchesPlayed = matchesPlayed + 1)

/**
 * The panel went up. **The cooldown starts at the presentation, not at the answer** (§17.2): a player
 * who is shown the panel and walks away has been asked, and an ignored prompt that re-appeared
 * tomorrow would be the rudest version of this feature.
 */
fun DeviceRecord.recordingPresentation(now: Long): DeviceRecord = copy(lastAskedAt = now)

/**
 * The player answered. Only a positive answer changes anything durable — a no and a dismissal are
 * already paid for by the cooldown the presentation started, and there is no "never ask again" button
 * because a yes *is* the never and a dismissal *is* the later (§17.2).
 */
fun DeviceRecord.recording(answer: LoveAnswer): DeviceRecord =
    if (answer == LoveAnswer.POSITIVE) copy(answeredPositively = true) else this

/**
 * The facts the policy decides from, for a moment that armed [trigger] and a switch read from config.
 * This record deliberately knows nothing about either.
 */
fun DeviceRecord.loveFacts(trigger: LoveTrigger?, remote: LoveSwitch): LoveFacts =
    LoveFacts(trigger, lastAskedAt, answeredPositively, remote)

/**
 * How the player answered the panel (spec §17.2). Tapping the scrim is [DISMISSED] — a third answer,
 * never a no-op.
 */
enum class LoveAnswer(val key: String) {
    POSITIVE("positive"),
    NEGATIVE("negative"),
    DISMISSED("dismissed"),
}

// --- The rules a decoded record is checked against -----------------------------------------------

internal fun DeviceRecord.validate(path: String) {
    if (matchesPlayed < 0) refuse(SaveDecodeError.BrokenRule("$path.matches_played", SaveRule.NEGATIVE_COUNT))
    if (installedAt < 0) refuse(SaveDecodeError.BrokenRule("$path.installed_at", SaveRule.NEGATIVE_INSTANT))
    if (lastAskedAt != null) {
        if (lastAskedAt < 0) refuse(SaveDecodeError.BrokenRule("$path.last_asked_at", SaveRule.NEGATIVE_INSTANT))
    } else if (answeredPositively) {
        // The presentation stamps the instant and the answer follows it, so a yes without one is a
        // record that cannot have arisen. A clock that ran backwards, by contrast, makes
        // last_asked_at < installed_at — legitimate, and deliberately not a rule.
        refuse(SaveDecodeError.BrokenRule("$path.answered_positively", SaveRule.ANSWERED_WITHOUT_ASKING))
    }
}
