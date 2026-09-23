/// The save file's JSON (spec §15, shared/data/save.toml): a value tree, a strict parser and the
/// canonical writer. The record types and their per-field encoding are generated
/// (Generated/SaveRecords.swift); this is the runtime they call. The Android twin is
/// `core/season/SaveJson.kt`; both write the same bytes for the same state
/// (shared/vectors/season/save/).
///
/// The device record (spec §17, shared/data/telemetry.toml) is declared the same way and written by
/// the same runtime; everything here that says "save" holds for it too.
///
/// Written by hand rather than on Foundation's JSON: the bytes are a cross-platform contract, and
/// the decoder has to tell an integer from a boolean and a missing key from a null — neither of
/// which `JSONSerialization` promises.
public indirect enum JSONValue: Sendable, Equatable {
    case null
    case bool(Bool)
    case int(Int)
    /// A number that is not an integer the save could hold (a fraction, an exponent, or out of range).
    case otherNumber(String)
    case string(String)
    case array([JSONValue])
    case object([Member])

    public struct Member: Sendable, Equatable {
        public let key: String
        public let value: JSONValue
    }

    static func object(_ members: [(String, JSONValue)]) -> JSONValue {
        .object(members.map { Member(key: $0.0, value: $0.1) })
    }
}

/// Why a save file was refused. Decoding never substitutes an empty save for a broken one
/// (conventions.md, greenfield): the caller keeps the file and decides.
public enum SaveDecodeError: Error, Sendable, Equatable {
    /// Not JSON (or not UTF-8); `offset` is the byte where parsing failed.
    case malformedJSON(offset: Int)
    /// A save of another format version (save.toml [format]); nothing else was read.
    case unknownVersion(Int)
    case missingField(path: String)
    case unknownField(path: String)
    case duplicateField(path: String)
    /// A value of the wrong JSON type.
    case wrongType(path: String)
    /// A value of the right type that is not a value of its field: an undeclared key, a malformed hex.
    case badValue(path: String)
    /// A well-formed record that breaks a rule of the spec.
    case brokenRule(path: String, SaveRule)
}

/// The rules a decoded record is checked against (the records' `validate(at:)`) — the save's (§15)
/// and the device record's (§17), which share this runtime.
public enum SaveRule: String, Sendable, CaseIterable {
    case createdTeamInvalid                 // §2.2: name, short code or kit
    case negativeCount                      // trophies, goals
    case tacticOutOfRange                   // §12: 0–1
    case notABoardChoice                    // §12: period length, ball spin
    case drillWonTwice
    case seasonWithoutCareer
    case leagueIsNotTheCareers              // §11.1: the season's teams are the career's league
    case matchdayOutOfRange
    case fixtureNotInLeague
    case cupScoreLevel                      // §11.3: a cup match always has a winner
    case overtimeOutsideCup
    case seasonNumber                       // §15: a season's number is 1 or more
    case negativeInstant                    // §17: an instant is epoch milliseconds, never before 1970
    case answeredWithoutAsking              // §17: the dialog cannot have been answered before it was shown
}

// MARK: - The helpers the generated code calls

enum SaveJSON {
    static func fields(_ v: JSONValue, at path: String, _ keys: [String]) throws(SaveDecodeError) -> [JSONValue] {
        guard case .object(let members) = v else { throw .wrongType(path: path) }
        var found: [String: JSONValue] = [:]
        for m in members {
            guard keys.contains(m.key) else { throw .unknownField(path: path + "." + m.key) }
            guard found[m.key] == nil else { throw .duplicateField(path: path + "." + m.key) }
            found[m.key] = m.value
        }
        var out: [JSONValue] = []
        for k in keys {
            guard let value = found[k] else { throw .missingField(path: path + "." + k) }
            out.append(value)
        }
        return out
    }

    static func array(_ v: JSONValue, at path: String) throws(SaveDecodeError) -> [JSONValue] {
        guard case .array(let items) = v else { throw .wrongType(path: path) }
        return items
    }

    /// A save's integers are 32-bit on both platforms (Kotlin's `Int`): a larger one is refused.
    static func int(_ v: JSONValue, at path: String) throws(SaveDecodeError) -> Int {
        guard case .int(let n) = v else { throw .wrongType(path: path) }
        guard Int(Int32.min)...Int(Int32.max) ~= n else { throw .badValue(path: path) }
        return n
    }

    /// An instant, as epoch milliseconds (telemetry.toml): a plain JSON integer, written as itself.
    static func i64(_ v: Int64) -> JSONValue { .int(Int(v)) }

    /// Anything beyond 2^53 is refused: a JSON number that large is not exact everywhere it will be
    /// read, and no instant we write is anywhere near it.
    static func i64(_ v: JSONValue, at path: String) throws(SaveDecodeError) -> Int64 {
        guard case .int(let n) = v else { throw .wrongType(path: path) }
        guard -exactInteger...exactInteger ~= n else { throw .badValue(path: path) }
        return Int64(n)
    }

    static let exactInteger = 1 << 53

    /// An install id (telemetry.toml): the canonical lowercase 8-4-4-4-12 form, and nothing else.
    /// Held as a `String` rather than a `UUID` so the core stays free of Foundation and so the bytes
    /// on the wire are the bytes in the vector.
    static func uuid(_ v: String) -> JSONValue { .string(v) }

    static func uuid(_ v: JSONValue, at path: String) throws(SaveDecodeError) -> String {
        let s = try string(v, at: path)
        let groups = s.split(separator: "-", omittingEmptySubsequences: false)
        guard groups.map(\.count) == [8, 4, 4, 4, 12],
              groups.allSatisfy({ $0.allSatisfy { $0.isHexDigit && !$0.isUppercase } }) else {
            throw .badValue(path: path)
        }
        return s
    }

    static func bool(_ v: JSONValue, at path: String) throws(SaveDecodeError) -> Bool {
        guard case .bool(let b) = v else { throw .wrongType(path: path) }
        return b
    }

    static func string(_ v: JSONValue, at path: String) throws(SaveDecodeError) -> String {
        guard case .string(let s) = v else { throw .wrongType(path: path) }
        return s
    }

    static func key<T: RawRepresentable>(_ v: JSONValue, at path: String) throws(SaveDecodeError) -> T
    where T.RawValue == String {
        guard let value = T(rawValue: try string(v, at: path)) else { throw .badValue(path: path) }
        return value
    }

    /// "0x" and 16 hex digits.
    static func u64(_ v: UInt64) -> JSONValue { .string("0x" + hex(v, digits: 16)) }

    static func u64(_ v: JSONValue, at path: String) throws(SaveDecodeError) -> UInt64 {
        let s = try string(v, at: path)
        guard s.utf8.count == 18, s.hasPrefix("0x"), let n = UInt64(s.dropFirst(2), radix: 16),
              s.dropFirst(2).allSatisfy(\.isHexDigit) else { throw .badValue(path: path) }
        return n
    }

    /// A double as its IEEE-754 bits — exact, with no decimal formatting to disagree about.
    static func double(_ v: Double) -> JSONValue { u64(v.bitPattern) }

    static func double(_ v: JSONValue, at path: String) throws(SaveDecodeError) -> Double {
        Double(bitPattern: try u64(v, at: path))
    }

    /// "#RRGGBB".
    static func rgb(_ v: UInt32) -> JSONValue { .string("#" + hex(UInt64(v), digits: 6)) }

    static func rgb(_ v: JSONValue, at path: String) throws(SaveDecodeError) -> UInt32 {
        let s = try string(v, at: path)
        guard s.utf8.count == 7, s.hasPrefix("#"), s.dropFirst().allSatisfy(\.isHexDigit),
              let n = UInt32(s.dropFirst(), radix: 16) else { throw .badValue(path: path) }
        return n
    }

    static func hex(_ v: UInt64, digits: Int) -> String {
        let s = String(v, radix: 16, uppercase: true)
        return String(repeating: "0", count: max(0, digits - s.count)) + s
    }
}

// MARK: - Writing

extension JSONValue {
    /// The canonical text (save.toml): two-space indentation, one value per line, a final newline.
    func canonicalText() -> String {
        var out = ""
        write(into: &out, indent: "")
        out += "\n"
        return out
    }

    private func write(into out: inout String, indent: String) {
        switch self {
        case .null: out += "null"
        case .bool(let b): out += b ? "true" : "false"
        case .int(let n): out += String(n)
        case .otherNumber(let raw): out += raw
        case .string(let s): JSONValue.writeString(s, into: &out)
        case .array(let items):
            if items.isEmpty { out += "[]"; return }
            out += "[\n"
            for (i, item) in items.enumerated() {
                out += indent + "  "
                item.write(into: &out, indent: indent + "  ")
                out += i + 1 < items.count ? ",\n" : "\n"
            }
            out += indent + "]"
        case .object(let members):
            if members.isEmpty { out += "{}"; return }
            out += "{\n"
            for (i, m) in members.enumerated() {
                out += indent + "  "
                JSONValue.writeString(m.key, into: &out)
                out += ": "
                m.value.write(into: &out, indent: indent + "  ")
                out += i + 1 < members.count ? ",\n" : "\n"
            }
            out += indent + "}"
        }
    }

    private static func writeString(_ s: String, into out: inout String) {
        out += "\""
        for scalar in s.unicodeScalars {
            switch scalar {
            case "\"": out += "\\\""
            case "\\": out += "\\\\"
            case "\u{08}": out += "\\b"
            case "\t": out += "\\t"
            case "\n": out += "\\n"
            case "\u{0C}": out += "\\f"
            case "\r": out += "\\r"
            case _ where scalar.value < 0x20: out += "\\u00" + SaveJSON.hex(UInt64(scalar.value), digits: 2).lowercased()
            default: out.unicodeScalars.append(scalar)
            }
        }
        out += "\""
    }
}

// MARK: - Parsing

extension JSONValue {
    /// Parses one JSON document (RFC 8259) from UTF-8 bytes; anything else is `malformedJSON`.
    static func parse(_ bytes: [UInt8]) throws(SaveDecodeError) -> JSONValue {
        var p = JSONParser(bytes: bytes)
        p.skipSpace()
        let value = try p.value(depth: 0)
        p.skipSpace()
        guard p.i == bytes.count else { throw .malformedJSON(offset: p.i) }
        return value
    }
}

private struct JSONParser {
    let bytes: [UInt8]
    var i = 0

    init(bytes: [UInt8]) { self.bytes = bytes }

    var fail: SaveDecodeError { .malformedJSON(offset: i) }

    mutating func skipSpace() {
        while i < bytes.count, [0x20, 0x09, 0x0A, 0x0D].contains(bytes[i]) { i += 1 }
    }

    mutating func expect(_ literal: String) throws(SaveDecodeError) {
        for b in literal.utf8 {
            guard i < bytes.count, bytes[i] == b else { throw fail }
            i += 1
        }
    }

    mutating func value(depth: Int) throws(SaveDecodeError) -> JSONValue {
        guard i < bytes.count, depth < 64 else { throw fail }
        switch bytes[i] {
        case UInt8(ascii: "{"): return try object(depth: depth)
        case UInt8(ascii: "["): return try array(depth: depth)
        case UInt8(ascii: "\""): return .string(try string())
        case UInt8(ascii: "t"): try expect("true"); return .bool(true)
        case UInt8(ascii: "f"): try expect("false"); return .bool(false)
        case UInt8(ascii: "n"): try expect("null"); return .null
        case UInt8(ascii: "-"), UInt8(ascii: "0")...UInt8(ascii: "9"): return try number()
        default: throw fail
        }
    }

    mutating func object(depth: Int) throws(SaveDecodeError) -> JSONValue {
        i += 1
        var members: [JSONValue.Member] = []
        skipSpace()
        if i < bytes.count, bytes[i] == UInt8(ascii: "}") { i += 1; return .object(members) }
        while true {
            skipSpace()
            guard i < bytes.count, bytes[i] == UInt8(ascii: "\"") else { throw fail }
            let key = try string()
            skipSpace()
            try expect(":")
            skipSpace()
            members.append(JSONValue.Member(key: key, value: try value(depth: depth + 1)))
            skipSpace()
            guard i < bytes.count else { throw fail }
            if bytes[i] == UInt8(ascii: ",") { i += 1; continue }
            if bytes[i] == UInt8(ascii: "}") { i += 1; return .object(members) }
            throw fail
        }
    }

    mutating func array(depth: Int) throws(SaveDecodeError) -> JSONValue {
        i += 1
        var items: [JSONValue] = []
        skipSpace()
        if i < bytes.count, bytes[i] == UInt8(ascii: "]") { i += 1; return .array(items) }
        while true {
            skipSpace()
            items.append(try value(depth: depth + 1))
            skipSpace()
            guard i < bytes.count else { throw fail }
            if bytes[i] == UInt8(ascii: ",") { i += 1; continue }
            if bytes[i] == UInt8(ascii: "]") { i += 1; return .array(items) }
            throw fail
        }
    }

    mutating func number() throws(SaveDecodeError) -> JSONValue {
        let start = i
        if bytes[i] == UInt8(ascii: "-") { i += 1 }
        guard i < bytes.count, isDigit(bytes[i]) else { throw fail }
        if bytes[i] == UInt8(ascii: "0") { i += 1 } else { while i < bytes.count, isDigit(bytes[i]) { i += 1 } }
        var integral = true
        if i < bytes.count, bytes[i] == UInt8(ascii: ".") {
            integral = false
            i += 1
            guard i < bytes.count, isDigit(bytes[i]) else { throw fail }
            while i < bytes.count, isDigit(bytes[i]) { i += 1 }
        }
        if i < bytes.count, bytes[i] == UInt8(ascii: "e") || bytes[i] == UInt8(ascii: "E") {
            integral = false
            i += 1
            if i < bytes.count, bytes[i] == UInt8(ascii: "+") || bytes[i] == UInt8(ascii: "-") { i += 1 }
            guard i < bytes.count, isDigit(bytes[i]) else { throw fail }
            while i < bytes.count, isDigit(bytes[i]) { i += 1 }
        }
        let raw = String(decoding: bytes[start..<i], as: UTF8.self)
        if integral, let n = Int64(raw) { return .int(Int(n)) }
        return .otherNumber(raw)
    }

    func isDigit(_ b: UInt8) -> Bool { b >= UInt8(ascii: "0") && b <= UInt8(ascii: "9") }

    mutating func string() throws(SaveDecodeError) -> String {
        i += 1
        var scalars = String.UnicodeScalarView()
        var run: [UInt8] = []   // raw UTF-8 since the last escape, validated when flushed
        func flush(_ run: inout [UInt8], at offset: Int) throws(SaveDecodeError) {
            guard !run.isEmpty else { return }
            guard let s = String(validating: run, as: UTF8.self) else { throw .malformedJSON(offset: offset) }
            scalars.append(contentsOf: s.unicodeScalars)
            run.removeAll()
        }
        while true {
            guard i < bytes.count else { throw fail }
            let b = bytes[i]
            if b == UInt8(ascii: "\"") {
                try flush(&run, at: i)
                i += 1
                return String(scalars)
            }
            guard b >= 0x20 else { throw fail }
            if b != UInt8(ascii: "\\") { run.append(b); i += 1; continue }
            try flush(&run, at: i)
            i += 1
            guard i < bytes.count else { throw fail }
            let e = bytes[i]
            i += 1
            switch e {
            case UInt8(ascii: "\""): scalars.append("\"")
            case UInt8(ascii: "\\"): scalars.append("\\")
            case UInt8(ascii: "/"): scalars.append("/")
            case UInt8(ascii: "b"): scalars.append("\u{08}")
            case UInt8(ascii: "f"): scalars.append("\u{0C}")
            case UInt8(ascii: "n"): scalars.append("\n")
            case UInt8(ascii: "r"): scalars.append("\r")
            case UInt8(ascii: "t"): scalars.append("\t")
            case UInt8(ascii: "u"):
                var unit = try hex4()
                if (0xD800..<0xDC00).contains(unit) {
                    try expect("\\u")
                    let low = try hex4()
                    guard (0xDC00..<0xE000).contains(low) else { throw fail }
                    unit = 0x10000 + ((unit - 0xD800) << 10) + (low - 0xDC00)
                }
                guard let scalar = Unicode.Scalar(unit) else { throw fail }
                scalars.append(scalar)
            default: throw fail
            }
        }
    }

    mutating func hex4() throws(SaveDecodeError) -> UInt32 {
        guard i + 4 <= bytes.count,
              let n = UInt32(String(decoding: bytes[i..<(i + 4)], as: UTF8.self), radix: 16),
              bytes[i..<(i + 4)].allSatisfy({ Character(Unicode.Scalar($0)).isHexDigit }) else { throw fail }
        i += 4
        return n
    }
}
