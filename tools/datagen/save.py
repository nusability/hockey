"""The save records (shared/data/save.toml, spec §15): loads the declaration and emits the record
types with their canonical JSON encoding and strict decoding, for both platforms.

The JSON runtime both emitters call — the value tree, the parser, the canonical writer, the
per-type helpers and the typed decode error — is hand-written on each platform (Season/ in
SmashCore, core/season on Android); the hand-written rule checks a record opts into with
`_validate = true` live there too. Everything a record's shape decides is generated here, once.
"""
import re
import tomllib
from dataclasses import dataclass

from .common import HEADER
from .model import DataError, camel, fail

SWIFT = "ios/SmashCore/Sources/SmashCore/Generated/SaveRecords.swift"
KOTLIN = "android/core/src/main/kotlin/in/nann/smashhockey/core/generated/SaveRecords.kt"

# Base types: (Swift type, Kotlin type). Keyed types are enums written as their declared key.
BASE = {
    "int": ("Int", "Int"), "bool": ("Bool", "Boolean"), "string": ("String", "String"),
    "u64": ("UInt64", "Long"), "double": ("Double", "Double"), "rgb": ("UInt32", "Int"),
}
KEYED = {"club": "Club", "world": "World", "formation": "Formation", "drill": "Drill", "team": "TeamKey"}


@dataclass
class TypeRef:
    name: str          # a base type, a keyed type, or a record name
    is_list: bool
    optional: bool
    record: bool


@dataclass
class Record:
    name: str
    doc: str
    validate: bool
    fields: list       # [(snake name, TypeRef)]


@dataclass
class Save:
    version: int
    records: list


def load(root):
    path = root / "shared" / "data" / "save.toml"
    if not path.exists():
        raise DataError(f"{path} is missing")
    with open(path, "rb") as f:
        doc = tomllib.load(f)
    if set(doc) != {"format", "record"}:
        fail("save.toml", f"expected exactly [format] and [record.*], got {sorted(doc)}")
    fmt = doc["format"]
    if set(fmt) != {"version"} or isinstance(fmt["version"], bool) or not isinstance(fmt["version"], int) \
            or fmt["version"] < 1:
        fail("save.toml [format]", "expected version = a positive integer")
    names = list(doc["record"])
    records = []
    for name in names:
        w = f"save.toml [record.{name}]"
        if not re.fullmatch(r"[A-Z][A-Za-z0-9]*", name):
            fail(w, "a record name is UpperCamelCase")
        table = doc["record"][name]
        doc_text = table.get("_doc")
        if not isinstance(doc_text, str) or not doc_text:
            fail(w, "missing _doc")
        validate = table.get("_validate", False)
        if not isinstance(validate, bool):
            fail(w, "_validate must be true or false")
        extra = {k for k in table if k.startswith("_")} - {"_doc", "_validate"}
        if extra:
            fail(w, f"unknown metadata {sorted(extra)}")
        fields = []
        for key, text in table.items():
            if key.startswith("_"):
                continue
            fw = f"{w}.{key}"
            if not re.fullmatch(r"[a-z][a-z0-9]*(_[a-z0-9]+)*", key):
                fail(fw, "a field name is snake_case")
            fields.append((key, type_ref(text, fw, names)))
        if not fields:
            fail(w, "a record has at least one field")
        records.append(Record(name, doc_text, validate, fields))
    root_record = records[0]
    first = root_record.fields[0]
    if first[0] != "version" or first[1] != TypeRef("int", False, False, False):
        fail(f"save.toml [record.{root_record.name}]", "the root record's first field is version = \"int\"")
    return Save(fmt["version"], records)


def type_ref(text, where, records):
    if not isinstance(text, str):
        fail(where, f"a field's type is a string, got {text!r}")
    m = re.fullmatch(r"\[([A-Za-z0-9]+)\]|([A-Za-z0-9]+)(\?)?", text)
    if not m:
        fail(where, f"type {text!r} is not T, T? or [T]")
    name = m.group(1) or m.group(2)
    ref = TypeRef(name, m.group(1) is not None, m.group(3) is not None, name in records)
    if not ref.record and name not in BASE and name not in KEYED:
        fail(where, f"unknown type {name!r} — a record, or one of {sorted(BASE) + sorted(KEYED)}")
    return ref


def swift_type(ref):
    base = ref.name if ref.record else (BASE[ref.name][0] if ref.name in BASE else KEYED[ref.name])
    return f"[{base}]" if ref.is_list else (base + "?" if ref.optional else base)


def kotlin_type(ref):
    base = ref.name if ref.record else (BASE[ref.name][1] if ref.name in BASE else KEYED[ref.name])
    return f"List<{base}>" if ref.is_list else (base + "?" if ref.optional else base)


# --- Swift --------------------------------------------------------------------------------------

def swift_encode_one(ref, expr):
    if ref.record:
        return f"{expr}.json()"
    if ref.name in KEYED:
        return f".string({expr}.rawValue)"
    return {"int": f".int({expr})", "bool": f".bool({expr})", "string": f".string({expr})",
            "u64": f"SaveJSON.u64({expr})", "double": f"SaveJSON.double({expr})", "rgb": f"SaveJSON.rgb({expr})"}[ref.name]


def swift_decode_one(ref, value, path):
    if ref.record:
        return f"try {ref.name}(json: {value}, at: {path})"
    if ref.name in KEYED:
        return f"try SaveJSON.key({value}, at: {path}) as {KEYED[ref.name]}"
    return f"try SaveJSON.{ref.name}({value}, at: {path})"


def swift(save):
    out = [f"// {HEADER}\n// The save records (save.toml, spec §15): the types, their canonical JSON and its strict decoding.\n"
           "// The JSON runtime, the decode error and the `validate(at:)` rule checks are hand-written in Season/.\n\n"]
    out.append("/// The save format (save.toml [format]). A record of any other version is refused, never read.\n")
    out.append(f"public enum SaveFormat {{\n    public static let version: Int = {save.version}\n}}\n")
    for r in save.records:
        out.append(f"\n/// {r.doc}\npublic struct {r.name}: Sendable, Hashable {{\n")
        for key, ref in r.fields:
            out.append(f"    public var {camel(key)}: {swift_type(ref)}\n")
        params = ", ".join(f"{camel(k)}: {swift_type(t)}" for k, t in r.fields)
        out.append(f"\n    public init({params}) {{\n")
        out.extend(f"        self.{camel(k)} = {camel(k)}\n" for k, _ in r.fields)
        out.append("    }\n}\n\nextension " + r.name + " {\n")
        out.append("    /// This record as its canonical JSON value.\n    func json() -> JSONValue {\n        .object([\n")
        for key, ref in r.fields:
            n = camel(key)
            if ref.is_list:
                enc = f".array({n}.map {{ {swift_encode_one(ref, '$0')} }})"
            elif ref.optional:
                enc = f"{n}.map {{ {swift_encode_one(ref, '$0')} }} ?? .null"
            else:
                enc = swift_encode_one(ref, n)
            out.append(f"            (\"{key}\", {enc}),\n")
        out.append("        ])\n    }\n\n")
        out.append("    /// Decodes the record at `path` (\"$\" for the file's root), failing on anything but its exact shape.\n")
        out.append("    init(json: JSONValue, at path: String) throws(SaveDecodeError) {\n")
        keys = ", ".join(f'"{k}"' for k, _ in r.fields)
        out.append(f"        let o = try SaveJSON.fields(json, at: path, [{keys}])\n")
        for i, (key, ref) in enumerate(r.fields):
            n, p = camel(key), f'path + ".{key}"'
            if ref.is_list:
                out.append(f"        var {n}: {swift_type(ref)} = []\n")
                item_path = p + ' + "[\\(i)]"'
                out.append(f"        for (i, v) in try SaveJSON.array(o[{i}], at: {p}).enumerated() {{\n")
                out.append(f"            {n}.append({swift_decode_one(ref, 'v', item_path)})\n        }}\n")
                out.append(f"        self.{n} = {n}\n")
            elif ref.optional:
                out.append(f"        if case .null = o[{i}] {{ self.{n} = nil }} else {{ self.{n} = {swift_decode_one(ref, f'o[{i}]', p)} }}\n")
            else:
                out.append(f"        self.{n} = {swift_decode_one(ref, f'o[{i}]', p)}\n")
        if r.validate:
            out.append("        try validate(at: path)\n")
        out.append("    }\n}\n")
    return "".join(out)


# --- Kotlin -------------------------------------------------------------------------------------

def kotlin_encode_one(ref, expr):
    if ref.record:
        return f"{expr}.toJson()"
    if ref.name in KEYED:
        return f"JsonValue.Str({expr}.key)"
    return {"int": f"JsonValue.Num({expr}.toLong())", "bool": f"JsonValue.Bool({expr})", "string": f"JsonValue.Str({expr})",
            "u64": f"SaveJson.u64({expr})", "double": f"SaveJson.double({expr})", "rgb": f"SaveJson.rgb({expr})"}[ref.name]


def kotlin_decode_one(ref, value, path):
    if ref.record:
        return f"{ref.name}.fromJson({value}, {path})"
    if ref.name in KEYED:
        t = KEYED[ref.name]
        return f"SaveJson.key({value}, {path}, {t}.entries) {{ it.key }}"
    return f"SaveJson.{ref.name}({value}, {path})"


def kotlin(save):
    out = [f"// {HEADER}\n// The save records (save.toml, spec §15): the types, their canonical JSON and its strict decoding.\n"
           "// The JSON runtime, the decode error and the `validate(path)` rule checks are hand-written in core/season.\n"
           "package `in`.nann.smashhockey.core.generated\n\n"
           "import `in`.nann.smashhockey.core.season.JsonValue\n"
           "import `in`.nann.smashhockey.core.season.SaveJson\n"
           "import `in`.nann.smashhockey.core.season.validate\n\n"]
    out.append("/** The save format (save.toml [format]). A record of any other version is refused, never read. */\n")
    out.append(f"object SaveFormat {{\n    const val version: Int = {save.version}\n}}\n")
    for r in save.records:
        out.append(f"\n/** {r.doc} */\ndata class {r.name}(\n")
        out.extend(f"    val {camel(k)}: {kotlin_type(t)},\n" for k, t in r.fields)
        out.append(") {\n    /** This record as its canonical JSON value. */\n")
        out.append("    fun toJson(): JsonValue = JsonValue.Obj(\n        listOf(\n")
        for key, ref in r.fields:
            n = camel(key)
            if ref.is_list:
                enc = f"JsonValue.Arr({n}.map {{ {kotlin_encode_one(ref, 'it')} }})"
            elif ref.optional:
                enc = f"({n}?.let {{ {kotlin_encode_one(ref, 'it')} }} ?: JsonValue.Null)"
            else:
                enc = kotlin_encode_one(ref, n)
            out.append(f"            \"{key}\" to {enc},\n")
        out.append("        ),\n    )\n\n    companion object {\n")
        out.append("        /** Decodes the record at [path] (\"$\" for the file's root), failing on anything but its exact shape. */\n")
        out.append(f"        fun fromJson(json: JsonValue, path: String): {r.name} {{\n")
        keys = ", ".join(f'"{k}"' for k, _ in r.fields)
        out.append(f"            val o = SaveJson.fields(json, path, listOf({keys}))\n")
        out.append(f"            val record = {r.name}(\n")
        for i, (key, ref) in enumerate(r.fields):
            n, p = camel(key), f'"$path.{key}"'
            if ref.is_list:
                item = kotlin_decode_one(ref, "v", f'"$path.{key}[$i]"')
                dec = f"SaveJson.array(o[{i}], {p}).mapIndexed {{ i, v -> {item} }}"
            elif ref.optional:
                dec = f"o[{i}].let {{ if (it is JsonValue.Null) null else {kotlin_decode_one(ref, 'it', p)} }}"
            else:
                dec = kotlin_decode_one(ref, f"o[{i}]", p)
            out.append(f"                {n} = {dec},\n")
        out.append("            )\n")
        if r.validate:
            out.append("            record.validate(path)\n")
        out.append("            return record\n        }\n    }\n}\n")
    return "".join(out)


def emit(save):
    return {SWIFT: swift(save), KOTLIN: kotlin(save)}
