package `in`.nann.smashhockey.core.telemetry

import `in`.nann.smashhockey.core.generated.DeviceRecord
import `in`.nann.smashhockey.core.season.SaveDecodeException
import java.io.File
import java.io.FileOutputStream
import java.io.IOException
import java.nio.file.Files
import java.nio.file.StandardCopyOption

/**
 * The device record on the device (spec §17.1): one file, `device.json`, in the same directory as the
 * save (Android: `filesDir`). Written whole and atomically, exactly as `SaveStore` writes `save.json`
 * — the canonical JSON goes to a temporary file beside it, which is then renamed over the old one.
 * The iOS twin is SmashCore's `Telemetry/DeviceStore.swift`.
 *
 * It is a **second file and not a branch of the save**, and the three reasons are the whole design
 * (ADR 0009):
 *
 * 1. **A refused save cannot reach it.** `SaveStore.replaceRefused()` and starting over name
 *    `save.json` and nothing else, so a player who has said yes is never asked again whatever becomes
 *    of their career.
 * 2. **A refused device record is never a screen.** Telemetry may not stand between the player and
 *    the game, so [replaceRefused] moves the unreadable file aside and writes a
 *    [DeviceRecord.Companion.replacement] — stamped as if the question had just been put. Never a
 *    [DeviceRecord.Companion.fresh]: a record we lost must serve a full cooldown, never read as
 *    long-ago-and-eligible.
 * 3. **It is excluded from device backup** — by name, in `app/src/main/res/xml/backup_rules.xml` and
 *    `data_extraction_rules.xml`, so an install id can never be restored onto a second phone and
 *    counted twice. `save.json` stays backed up — player data is sacred.
 */
class DeviceStore(val directory: File) {
    /**
     * What was on the device — the same three answers `SaveStore.Loaded` gives, and the same meanings;
     * only what the app does with the third one differs.
     */
    sealed interface Loaded {
        /** No record yet: this install has just been seen for the first time. */
        data class New(val record: DeviceRecord) : Loaded
        data class Found(val record: DeviceRecord) : Loaded
        /** A record exists and was refused (§17.1) — why, as a line for the log. Never a screen. */
        data class Refused(val why: String) : Loaded
    }

    val file = File(directory, FILE_NAME)
    private val temporary = File(directory, "$FILE_NAME.tmp")

    /**
     * Reads the record. A missing file is a new install; anything else that is not a well-formed
     * record of this version — unreadable bytes included — is refused.
     *
     * [now] and [installId] are only what a *new* install would be stamped with: the platform mints
     * the id and reads the clock, the core does neither.
     */
    fun load(now: Long, installId: String): Loaded {
        if (!file.exists()) return Loaded.New(DeviceRecord.fresh(now, installId))
        val bytes = try {
            file.readBytes()
        } catch (e: IOException) {
            return Loaded.Refused("unreadable ${e.message}")
        }
        return try {
            Loaded.Found(DeviceRecord.decode(bytes))
        } catch (e: SaveDecodeException) {
            Loaded.Refused(e.error.toString())
        }
    }

    /**
     * Writes [record] atomically: the whole file to `device.json.tmp`, then renamed over
     * `device.json`. Backup exclusion is declared in the manifest's rules, not set here — Android has
     * no per-file flag.
     */
    fun write(record: DeviceRecord) {
        directory.mkdirs()
        FileOutputStream(temporary).use { out ->
            out.write(record.encoded().toByteArray(Charsets.UTF_8))
            out.fd.sync()
        }
        Files.move(temporary.toPath(), file.toPath(), StandardCopyOption.ATOMIC_MOVE, StandardCopyOption.REPLACE_EXISTING)
    }

    /**
     * Where a refused record is kept: a directory of its own, excluded from backup as a whole.
     *
     * Not beside the record as the save's refused copies are, and the reason is the id. An exclusion
     * list names exact paths, so `device.refused-1.json` sitting next to `device.json` would be
     * **backed up** — carrying the very install id §18.1 says never rides a record that syncs. A
     * directory is excluded once and covers every copy there will ever be.
     */
    val refusedDirectory = File(directory, REFUSED_DIRECTORY_NAME)

    /**
     * After a refusal (§17.1): the refused file is moved aside, untouched, into
     * `device-refused/device-N.json` (the first N free), and a **replacement** is written in its place.
     *
     * The replacement — never a [DeviceRecord.Companion.fresh] — is stamped as if the question had
     * just been put, so the record we lost reads as brand new and serving a full cooldown. One corrupt
     * byte must not re-ask a player who has already answered.
     */
    fun replaceRefused(now: Long, installId: String): Pair<DeviceRecord, File?> {
        var kept: File? = null
        if (file.exists()) {
            refusedDirectory.mkdirs()
            var n = 1
            while (File(refusedDirectory, "device-$n.json").exists()) n++
            val aside = File(refusedDirectory, "device-$n.json")
            Files.move(file.toPath(), aside.toPath())
            kept = aside
        }
        val replacement = DeviceRecord.replacement(now, installId)
        write(replacement)
        return replacement to kept
    }

    /**
     * The whole of launch, in one call: the record that is on the device, written if it was not there
     * or could not be read. The second value is the line to log when it could not — and nothing more,
     * because a refused device record is never a screen.
     */
    fun loadOrCreate(now: Long, installId: String): Pair<DeviceRecord, String?> =
        when (val loaded = load(now, installId)) {
            is Loaded.Found -> loaded.record to null
            is Loaded.New -> loaded.record.also { write(it) } to null
            is Loaded.Refused -> replaceRefused(now, installId).first to loaded.why
        }

    companion object {
        const val FILE_NAME = "device.json"
        const val REFUSED_DIRECTORY_NAME = "device-refused"
    }
}
