package `in`.nann.smashhockey.core.season

import java.nio.ByteBuffer
import java.nio.charset.CharacterCodingException
import java.nio.charset.CodingErrorAction
import java.nio.charset.StandardCharsets

/**
 * The save file's JSON (spec §15, shared/data/save.toml): a value tree, a strict parser and the
 * canonical writer. The record types and their per-field encoding are generated
 * (generated/SaveRecords.kt); this is the runtime they call. The iOS twin is SmashCore's
 * `Season/SaveJSON.swift`; both write the same bytes for the same state
 * (shared/vectors/season/save/).
 *
 * The device record (spec §17, shared/data/telemetry.toml) is declared the same way and written by
 * the same runtime; everything here that says "save" holds for it too.
 *
 * Hand-written rather than on a JSON library: the bytes are a cross-platform contract, and :core
 * stays a dependency-free JVM module.
 */
sealed interface JsonValue {
    data object Null : JsonValue
    data class Bool(val value: Boolean) : JsonValue
    /** An integer that fits a Long. */
    data class Num(val value: Long) : JsonValue
    /** A number that is not an integer the save could hold (a fraction, an exponent, or out of range). */
    data class OtherNumber(val raw: String) : JsonValue
    data class Str(val value: String) : JsonValue
    data class Arr(val items: List<JsonValue>) : JsonValue
    data class Obj(val members: List<Pair<String, JsonValue>>) : JsonValue

    /** The canonical text (save.toml): two-space indentation, one value per line, a final newline. */
    fun canonicalText(): String = StringBuilder().also { write(it, ""); it.append('\n') }.toString()

    private fun write(out: StringBuilder, indent: String) {
        when (this) {
            Null -> out.append("null")
            is Bool -> out.append(if (value) "true" else "false")
            is Num -> out.append(value)
            is OtherNumber -> out.append(raw)
            is Str -> writeString(value, out)
            is Arr -> if (items.isEmpty()) out.append("[]") else {
                out.append("[\n")
                items.forEachIndexed { i, item ->
                    out.append(indent).append("  ")
                    item.write(out, "$indent  ")
                    out.append(if (i + 1 < items.size) ",\n" else "\n")
                }
                out.append(indent).append(']')
            }
            is Obj -> if (members.isEmpty()) out.append("{}") else {
                out.append("{\n")
                members.forEachIndexed { i, (key, value) ->
                    out.append(indent).append("  ")
                    writeString(key, out)
                    out.append(": ")
                    value.write(out, "$indent  ")
                    out.append(if (i + 1 < members.size) ",\n" else "\n")
                }
                out.append(indent).append('}')
            }
        }
    }

    companion object {
        private fun writeString(s: String, out: StringBuilder) {
            out.append('"')
            for (c in s) {
                when {
                    c == '"' -> out.append("\\\"")
                    c == '\\' -> out.append("\\\\")
                    c == '\b' -> out.append("\\b")
                    c == '\t' -> out.append("\\t")
                    c == '\n' -> out.append("\\n")
                    c == '\u000C' -> out.append("\\f")
                    c == '\r' -> out.append("\\r")
                    c.code < 0x20 -> out.append("\\u00").append(c.code.toString(16).padStart(2, '0'))
                    else -> out.append(c)
                }
            }
            out.append('"')
        }

        /** Parses one JSON document (RFC 8259) from UTF-8 bytes; anything else is [SaveDecodeError.MalformedJson]. */
        fun parse(bytes: ByteArray): JsonValue {
            val p = Parser(bytes)
            p.skipSpace()
            val value = p.value(0)
            p.skipSpace()
            if (p.i != bytes.size) throw p.fail()
            return value
        }
    }
}

/**
 * Why a save file was refused. Decoding never substitutes an empty save for a broken one
 * (conventions.md, greenfield): the caller keeps the file and decides. [toString] is one line
 * naming the kind and where — identical to iOS's `SaveDecodeError.description`, which
 * shared/vectors/season/save/invalid.txt records.
 */
sealed interface SaveDecodeError {
    /** Not JSON (or not UTF-8); [offset] is the byte where parsing failed. */
    data class MalformedJson(val offset: Int) : SaveDecodeError { override fun toString() = "malformedJSON $offset" }
    /** A save of another format version (save.toml [format]); nothing else was read. */
    data class UnknownVersion(val version: Long) : SaveDecodeError { override fun toString() = "unknownVersion $version" }
    data class MissingField(val path: String) : SaveDecodeError { override fun toString() = "missingField $path" }
    data class UnknownField(val path: String) : SaveDecodeError { override fun toString() = "unknownField $path" }
    data class DuplicateField(val path: String) : SaveDecodeError { override fun toString() = "duplicateField $path" }
    /** A value of the wrong JSON type. */
    data class WrongType(val path: String) : SaveDecodeError { override fun toString() = "wrongType $path" }
    /** A value of the right type that is not a value of its field: an undeclared key, a malformed hex. */
    data class BadValue(val path: String) : SaveDecodeError { override fun toString() = "badValue $path" }
    /** A well-formed record that breaks a rule of the spec. */
    data class BrokenRule(val path: String, val rule: SaveRule) : SaveDecodeError {
        override fun toString() = "brokenRule $path ${rule.key}"
    }
}

/** Thrown by decoding with the typed [error]; never caught into an empty save. */
class SaveDecodeException(val error: SaveDecodeError) : Exception(error.toString())

/**
 * The rules a decoded record is checked against (the records' `validate`) — the save's (§15) and the
 * device record's (§17), which share this runtime. Keys match iOS.
 */
enum class SaveRule(val key: String) {
    CREATED_TEAM_INVALID("createdTeamInvalid"),
    NEGATIVE_COUNT("negativeCount"),
    TACTIC_OUT_OF_RANGE("tacticOutOfRange"),
    NOT_A_BOARD_CHOICE("notABoardChoice"),
    DRILL_WON_TWICE("drillWonTwice"),
    SEASON_WITHOUT_CAREER("seasonWithoutCareer"),
    LEAGUE_IS_NOT_THE_CAREERS("leagueIsNotTheCareers"),
    MATCHDAY_OUT_OF_RANGE("matchdayOutOfRange"),
    FIXTURE_NOT_IN_LEAGUE("fixtureNotInLeague"),
    CUP_SCORE_LEVEL("cupScoreLevel"),
    OVERTIME_OUTSIDE_CUP("overtimeOutsideCup"),
    SEASON_NUMBER("seasonNumber"),
    NEGATIVE_INSTANT("negativeInstant"),
    ANSWERED_WITHOUT_ASKING("answeredWithoutAsking"),
}

internal fun refuse(error: SaveDecodeError): Nothing = throw SaveDecodeException(error)

/** The helpers the generated code calls. */
object SaveJson {
    fun fields(v: JsonValue, path: String, keys: List<String>): List<JsonValue> {
        if (v !is JsonValue.Obj) refuse(SaveDecodeError.WrongType(path))
        val found = HashMap<String, JsonValue>()
        for ((key, value) in v.members) {
            if (key !in keys) refuse(SaveDecodeError.UnknownField("$path.$key"))
            if (found.put(key, value) != null) refuse(SaveDecodeError.DuplicateField("$path.$key"))
        }
        return keys.map { found[it] ?: refuse(SaveDecodeError.MissingField("$path.$it")) }
    }

    fun array(v: JsonValue, path: String): List<JsonValue> =
        (v as? JsonValue.Arr)?.items ?: refuse(SaveDecodeError.WrongType(path))

    /** A save's integers are 32-bit on both platforms: a larger one is refused. */
    fun int(v: JsonValue, path: String): Int {
        val n = (v as? JsonValue.Num)?.value ?: refuse(SaveDecodeError.WrongType(path))
        if (n < Int.MIN_VALUE || n > Int.MAX_VALUE) refuse(SaveDecodeError.BadValue(path))
        return n.toInt()
    }

    /** An instant, as epoch milliseconds (telemetry.toml): a plain JSON integer, written as itself. */
    fun i64(v: Long): JsonValue = JsonValue.Num(v)

    /**
     * Anything beyond 2^53 is refused: a JSON number that large is not exact everywhere it will be
     * read, and no instant we write is anywhere near it.
     */
    fun i64(v: JsonValue, path: String): Long {
        val n = (v as? JsonValue.Num)?.value ?: refuse(SaveDecodeError.WrongType(path))
        if (n < -EXACT_INTEGER || n > EXACT_INTEGER) refuse(SaveDecodeError.BadValue(path))
        return n
    }

    const val EXACT_INTEGER: Long = 1L shl 53

    /**
     * An install id (telemetry.toml): the canonical lowercase 8-4-4-4-12 form, and nothing else. Held
     * as a [String] rather than a java.util.UUID so the bytes on the wire are the bytes in the vector.
     */
    fun uuid(v: String): JsonValue = JsonValue.Str(v)

    fun uuid(v: JsonValue, path: String): String {
        val s = string(v, path)
        val groups = s.split("-")
        if (groups.map { it.length } != listOf(8, 4, 4, 4, 12) ||
            !groups.all { g -> g.all { it in '0'..'9' || it in 'a'..'f' } }
        ) {
            refuse(SaveDecodeError.BadValue(path))
        }
        return s
    }

    fun bool(v: JsonValue, path: String): Boolean = (v as? JsonValue.Bool)?.value ?: refuse(SaveDecodeError.WrongType(path))

    fun string(v: JsonValue, path: String): String = (v as? JsonValue.Str)?.value ?: refuse(SaveDecodeError.WrongType(path))

    fun <T> key(v: JsonValue, path: String, entries: List<T>, keyOf: (T) -> String): T {
        val s = string(v, path)
        return entries.firstOrNull { keyOf(it) == s } ?: refuse(SaveDecodeError.BadValue(path))
    }

    /** "0x" and 16 hex digits. */
    fun u64(v: Long): JsonValue = JsonValue.Str("0x" + hex(v, 16))

    fun u64(v: JsonValue, path: String): Long {
        val s = string(v, path)
        if (s.length != 18 || !s.startsWith("0x") || !s.substring(2).all(::isHex)) refuse(SaveDecodeError.BadValue(path))
        return java.lang.Long.parseUnsignedLong(s.substring(2), 16)
    }

    /** A double as its IEEE-754 bits — exact, with no decimal formatting to disagree about. */
    fun double(v: Double): JsonValue = u64(v.toRawBits())

    fun double(v: JsonValue, path: String): Double = Double.fromBits(u64(v, path))

    /** "#RRGGBB". */
    fun rgb(v: Int): JsonValue = JsonValue.Str("#" + hex(v.toLong(), 6))

    fun rgb(v: JsonValue, path: String): Int {
        val s = string(v, path)
        if (s.length != 7 || s[0] != '#' || !s.substring(1).all(::isHex)) refuse(SaveDecodeError.BadValue(path))
        return s.substring(1).toInt(16)
    }

    fun hex(v: Long, digits: Int): String = java.lang.Long.toHexString(v).uppercase().padStart(digits, '0')

    private fun isHex(c: Char) = c in '0'..'9' || c in 'a'..'f' || c in 'A'..'F'
}

private class Parser(val bytes: ByteArray) {
    var i = 0

    fun fail() = SaveDecodeException(SaveDecodeError.MalformedJson(i))

    private fun at(c: Char) = i < bytes.size && bytes[i].toInt() == c.code

    fun skipSpace() {
        while (i < bytes.size && bytes[i].toInt().let { it == 0x20 || it == 0x09 || it == 0x0A || it == 0x0D }) i++
    }

    private fun expect(literal: String) {
        for (c in literal) {
            if (!at(c)) throw fail()
            i++
        }
    }

    fun value(depth: Int): JsonValue {
        if (i >= bytes.size || depth >= 64) throw fail()
        return when (bytes[i].toInt().toChar()) {
            '{' -> obj(depth)
            '[' -> arr(depth)
            '"' -> JsonValue.Str(string())
            't' -> { expect("true"); JsonValue.Bool(true) }
            'f' -> { expect("false"); JsonValue.Bool(false) }
            'n' -> { expect("null"); JsonValue.Null }
            '-', in '0'..'9' -> number()
            else -> throw fail()
        }
    }

    private fun obj(depth: Int): JsonValue {
        i++
        val members = ArrayList<Pair<String, JsonValue>>()
        skipSpace()
        if (at('}')) { i++; return JsonValue.Obj(members) }
        while (true) {
            skipSpace()
            if (!at('"')) throw fail()
            val key = string()
            skipSpace()
            expect(":")
            skipSpace()
            members.add(key to value(depth + 1))
            skipSpace()
            if (i >= bytes.size) throw fail()
            if (at(',')) { i++; continue }
            if (at('}')) { i++; return JsonValue.Obj(members) }
            throw fail()
        }
    }

    private fun arr(depth: Int): JsonValue {
        i++
        val items = ArrayList<JsonValue>()
        skipSpace()
        if (at(']')) { i++; return JsonValue.Arr(items) }
        while (true) {
            skipSpace()
            items.add(value(depth + 1))
            skipSpace()
            if (i >= bytes.size) throw fail()
            if (at(',')) { i++; continue }
            if (at(']')) { i++; return JsonValue.Arr(items) }
            throw fail()
        }
    }

    private fun digit() = i < bytes.size && bytes[i] >= '0'.code.toByte() && bytes[i] <= '9'.code.toByte()

    private fun number(): JsonValue {
        val start = i
        if (at('-')) i++
        if (!digit()) throw fail()
        if (at('0')) i++ else while (digit()) i++
        var integral = true
        if (at('.')) {
            integral = false
            i++
            if (!digit()) throw fail()
            while (digit()) i++
        }
        if (at('e') || at('E')) {
            integral = false
            i++
            if (at('+') || at('-')) i++
            if (!digit()) throw fail()
            while (digit()) i++
        }
        val raw = String(bytes, start, i - start, StandardCharsets.US_ASCII)
        val n = if (integral) raw.toLongOrNull() else null
        return if (n != null) JsonValue.Num(n) else JsonValue.OtherNumber(raw)
    }

    private fun string(): String {
        i++
        val out = StringBuilder()
        var runStart = i   // raw UTF-8 since the last escape, validated when flushed
        fun flush() {
            if (i == runStart) return
            val decoder = StandardCharsets.UTF_8.newDecoder()
                .onMalformedInput(CodingErrorAction.REPORT).onUnmappableCharacter(CodingErrorAction.REPORT)
            try {
                out.append(decoder.decode(ByteBuffer.wrap(bytes, runStart, i - runStart)))
            } catch (e: CharacterCodingException) {
                throw fail()
            }
        }
        while (true) {
            if (i >= bytes.size) throw fail()
            val b = bytes[i].toInt() and 0xFF
            if (b == '"'.code) {
                flush()
                i++
                return out.toString()
            }
            if (b < 0x20) throw fail()
            if (b != '\\'.code) { i++; continue }
            flush()
            i++
            if (i >= bytes.size) throw fail()
            val e = bytes[i].toInt().toChar()
            i++
            when (e) {
                '"' -> out.append('"')
                '\\' -> out.append('\\')
                '/' -> out.append('/')
                'b' -> out.append('\b')
                'f' -> out.append('\u000C')
                'n' -> out.append('\n')
                'r' -> out.append('\r')
                't' -> out.append('\t')
                'u' -> {
                    var unit = hex4()
                    if (unit in 0xD800 until 0xDC00) {
                        expect("\\u")
                        val low = hex4()
                        if (low !in 0xDC00 until 0xE000) throw fail()
                        unit = 0x10000 + ((unit - 0xD800) shl 10) + (low - 0xDC00)
                    } else if (unit in 0xDC00 until 0xE000) {
                        throw fail()
                    }
                    out.appendCodePoint(unit)
                }
                else -> throw fail()
            }
            runStart = i
        }
    }

    private fun hex4(): Int {
        if (i + 4 > bytes.size) throw fail()
        var n = 0
        for (k in 0 until 4) {
            val c = bytes[i + k].toInt().toChar()
            val d = Character.digit(c, 16)
            if (d < 0 || c.code > 0x7F) throw fail()
            n = n * 16 + d
        }
        i += 4
        return n
    }
}
