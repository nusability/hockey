"""Emits the apps' presentation constants: shared/data/presentation.toml and each world's look
(teams.toml [world.look], ADR 0006) → the iOS app target and Android's :app module.

Presentation never reaches the simulation core (SmashCore, :core): nothing declared here can change
what a tick does (spec §4.2), so these doubles are not in the bit-exactness table either.
"""
import re
import tomllib

from .common import HEADER, double_lit
from .model import DataError, camel, fail, pascal, upper_snake

SWIFT = "ios/Sources/Scene/Generated/"
KOTLIN = "android/app/src/main/kotlin/in/nann/smashhockey/generated/"
COLOUR = re.compile(r"#[0-9a-fA-F]{6}")
SWIFT_KEYWORDS = {"default", "case", "in", "is", "as", "for", "if", "else", "switch", "where", "self", "init",
                  "class", "struct", "enum", "func", "let", "var", "return", "public", "static", "repeat"}
KOTLIN_KEYWORDS = {"in", "is", "as", "for", "if", "else", "when", "object", "class", "fun", "val", "var",
                   "return", "object", "package", "interface", "null", "true", "false", "typealias"}


def load(root):
    path = root / "shared" / "data" / "presentation.toml"
    if not path.exists():
        raise DataError(f"{path} is missing")
    with open(path, "rb") as f:
        return tree("presentation", tomllib.load(f), "presentation.toml")


def tree(name, table, where):
    entries, children = [], []
    for key, value in table.items():
        w = f"{where}.{key}"
        if isinstance(value, dict):
            children.append(tree(key, value, w))
        else:
            entries.append((key, kind(value, w), value))
    return (name, entries, children)


def kind(value, where):
    if isinstance(value, bool):
        fail(where, "presentation has no switches — declare a number")
    if isinstance(value, int):
        return "int"
    if isinstance(value, float):
        return "double"
    if isinstance(value, str) and COLOUR.fullmatch(value):
        return "colour"
    if isinstance(value, list) and value and all(isinstance(v, float) for v in value):
        return "doubles"
    if isinstance(value, list) and value and all(isinstance(v, str) and COLOUR.fullmatch(v) for v in value):
        return "colours"
    fail(where, f"unsupported value {value!r} (a float, an integer, a #rrggbb colour, or a list of either)")


def rgb(text):
    return int(text[1:], 16)


def emit(root, model):
    t = load(root)
    return {SWIFT + "Presentation.swift": swift(t, model.worlds),
            KOTLIN + "Presentation.kt": kotlin(t, model.worlds)}


LOOK_FIELDS = (("hemi_sky", "colour"), ("hemi_ground", "colour"), ("hemi_strength", "double"),
               ("sun", "colour"), ("sun_strength", "double"), ("sun_direction", "vector"))
LOOK_DOCS = {
    "hemi_sky": "The hemisphere light (ADR 0006): its colour from above and from below, sRGB 0xRRGGBB, and its strength.",
    "sun": "The sun: its colour, sRGB 0xRRGGBB, its strength, and the direction toward it (not normalized).",
}


def look_value(value, k, swift):
    if k == "colour":
        return f"0x{value:06X}"
    if k == "double":
        return double_lit(value)
    return ("[" if swift else "listOf(") + ", ".join(double_lit(v) for v in value) + ("]" if swift else ")")


# --- Swift ---------------------------------------------------------------------------------------

def swift(t, worlds):
    out = [f"// {HEADER}\n// The match's presentation (presentation.toml) and each world's look (teams.toml [world.look]):\n"
           "// how the scene looks, never what a tick does (spec §4.2, §5.2, §8.6, §13).\n\nimport SmashCore\n\n"]

    def sid(n):
        c = camel(n)
        return f"`{c}`" if c in SWIFT_KEYWORDS else c

    def walk(node, depth):
        name, entries, children = node
        pad = "    " * depth
        out.append(f"{pad}enum {pascal(name)} {{\n")
        p = pad + "    "
        for key, k, v in entries:
            n = sid(key)
            if k == "int":
                out.append(f"{p}static let {n}: Int = {v}\n")
            elif k == "double":
                out.append(f"{p}static let {n}: Double = {double_lit(v)}\n")
            elif k == "colour":
                out.append(f"{p}static let {n}: UInt32 = 0x{rgb(v):06X}\n")
            elif k == "doubles":
                out.append(f"{p}static let {n}: [Double] = [{', '.join(double_lit(x) for x in v)}]\n")
            else:
                out.append(f"{p}static let {n}: [UInt32] = [{', '.join(f'0x{rgb(x):06X}' for x in v)}]\n")
        for c in children:
            walk(c, depth + 1)
        out.append(f"{pad}}}\n")

    walk(t, 0)
    out.append("\n/// A world's light (spec §13, ADR 0006). Colours are sRGB 0xRRGGBB.\nstruct WorldLook: Sendable, Hashable {\n")
    for key, k in LOOK_FIELDS:
        if key in LOOK_DOCS:
            out.append(f"    /// {LOOK_DOCS[key]}\n")
        out.append(f"    let {camel(key)}: {dict(colour='UInt32', double='Double', vector='[Double]')[k]}\n")
    out.append("}\n\nextension World {\n    var look: WorldLook {\n        switch self {\n")
    for w in worlds:
        args = ", ".join(f"{camel(key)}: " + look_value(w["look"][key], k, True) for key, k in LOOK_FIELDS)
        out.append(f"        case .{w['id']}: WorldLook({args})\n")
    out.append("        }\n    }\n}\n")
    return "".join(out)


# --- Kotlin --------------------------------------------------------------------------------------

def kotlin(t, worlds):
    out = [f"// {HEADER}\n// The match's presentation (presentation.toml) and each world's look (teams.toml [world.look]):\n"
           "// how the scene looks, never what a tick does (spec §4.2, §5.2, §8.6, §13).\n"
           "package `in`.nann.smashhockey.generated\n\nimport `in`.nann.smashhockey.core.generated.World\n\n"]

    def kid(n):
        c = camel(n)
        return f"`{c}`" if c in KOTLIN_KEYWORDS else c

    def walk(node, depth):
        name, entries, children = node
        pad = "    " * depth
        out.append(f"{pad}object {pascal(name)} {{\n")
        p = pad + "    "
        for key, k, v in entries:
            n = kid(key)
            if k == "int":
                out.append(f"{p}const val {n}: Int = {v}\n")
            elif k == "double":
                out.append(f"{p}const val {n}: Double = {double_lit(v)}\n")
            elif k == "colour":
                out.append(f"{p}const val {n}: Int = 0x{rgb(v):06X}\n")
            elif k == "doubles":
                out.append(f"{p}val {n}: List<Double> = listOf({', '.join(double_lit(x) for x in v)})\n")
            else:
                out.append(f"{p}val {n}: List<Int> = listOf({', '.join(f'0x{rgb(x):06X}' for x in v)})\n")
        for c in children:
            walk(c, depth + 1)
        out.append(f"{pad}}}\n")

    walk(t, 0)
    out.append("\n/** A world's light (spec §13, ADR 0006). Colours are sRGB 0xRRGGBB. */\ndata class WorldLook(\n")
    for key, k in LOOK_FIELDS:
        if key in LOOK_DOCS:
            out.append(f"    /** {LOOK_DOCS[key]} */\n")
        out.append(f"    val {camel(key)}: {dict(colour='Int', double='Double', vector='List<Double>')[k]},\n")
    out.append(")\n\nval World.look: WorldLook\n    get() = when (this) {\n")
    for w in worlds:
        args = ", ".join(look_value(w["look"][key], k, False) for key, k in LOOK_FIELDS)
        out.append(f"        World.{upper_snake(w['id'])} -> WorldLook({args})\n")
    out.append("    }\n")
    return "".join(out)
