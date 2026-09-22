package `in`.nann.smashhockey.core.season

import `in`.nann.smashhockey.core.generated.SaveRecord
import java.io.File
import java.io.FileOutputStream
import java.io.IOException
import java.nio.file.Files
import java.nio.file.StandardCopyOption

/**
 * The save on the device (spec §15): one file, `save.json`, in a directory the app owns (Android:
 * `filesDir`). Written whole and atomically — the canonical JSON goes to a temporary file beside
 * it, which is then renamed over the old one, so a crash mid-write leaves the last good record,
 * never half a new one. A record that cannot be read is never replaced silently: [load] says so,
 * and only [replaceRefused] moves it aside — untouched, under a name of its own — and writes a new
 * one. The iOS twin is SmashCore's `Season/SaveStore.swift`.
 */
class SaveStore(val directory: File) {
    /** What was on the device. */
    sealed interface Loaded {
        /** No save yet: a new player. */
        data class New(val record: SaveRecord) : Loaded
        data class Found(val record: SaveRecord) : Loaded
        /** A save exists and was refused (§15) — why, as a line for the log and the refusal screen. */
        data class Refused(val why: String) : Loaded
    }

    val file = File(directory, FILE_NAME)
    private val temporary = File(directory, "$FILE_NAME.tmp")

    /**
     * Reads the save. A missing file is a new player; anything else that is not a well-formed record
     * of this version — unreadable bytes included — is refused.
     */
    fun load(): Loaded {
        if (!file.exists()) return Loaded.New(SaveRecord.fresh())
        val bytes = try {
            file.readBytes()
        } catch (e: IOException) {
            return Loaded.Refused("unreadable ${e.message}")
        }
        return try {
            Loaded.Found(SaveRecord.decode(bytes))
        } catch (e: SaveDecodeException) {
            Loaded.Refused(e.error.toString())
        }
    }

    /** Writes [record] atomically: the whole file to `save.json.tmp`, then renamed over `save.json`. */
    fun write(record: SaveRecord) {
        directory.mkdirs()
        FileOutputStream(temporary).use { out ->
            out.write(record.encoded().toByteArray(Charsets.UTF_8))
            out.fd.sync()
        }
        Files.move(temporary.toPath(), file.toPath(), StandardCopyOption.ATOMIC_MOVE, StandardCopyOption.REPLACE_EXISTING)
    }

    /**
     * After a refusal (§15): the refused file is moved aside, untouched, as `save.refused-N.json`
     * (the first N free), and a fresh record is written in its place. Returns the fresh record and
     * where the refused one now lives.
     */
    fun replaceRefused(): Pair<SaveRecord, File?> {
        var kept: File? = null
        if (file.exists()) {
            var n = 1
            while (File(directory, "save.refused-$n.json").exists()) n++
            val aside = File(directory, "save.refused-$n.json")
            Files.move(file.toPath(), aside.toPath())
            kept = aside
        }
        val fresh = SaveRecord.fresh()
        write(fresh)
        return fresh to kept
    }

    companion object { const val FILE_NAME = "save.json" }
}
