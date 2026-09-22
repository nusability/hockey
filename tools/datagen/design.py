"""Emits the 3D UI's design tokens: shared/data/design.json → the iOS app target and Android's
:app module (conventions: UI — "Design tokens, not raw values").

Colours are Ints on both platforms (what the kit's block and lettering calls take), sizes are Floats
(metres in a screen's design frame), and the UI's own light is a `WorldLook` — the menus' light, not
the light of the world behind them, so a slab reads the same in every world.
"""
import json

from .common import HEADER
from .model import DataError, camel, fail, upper_snake
from .presentation import COLOUR, LOOK_FIELDS, look_value, rgb

SWIFT = "ios/Sources/UI/Generated/"
KOTLIN = "android/app/src/main/kotlin/in/nann/smashhockey/ui/generated/"


def load(root):
    path = root / "shared" / "data" / "design.json"
    if not path.exists():
        raise DataError(f"{path} is missing")
    with open(path, "rb") as f:
        doc = json.load(f)
    for section in ("colour", "size", "look", "contrast"):
        if section not in doc:
            raise DataError(f"design.json has no '{section}'")
    colours = {}
    for key, value in doc["colour"].items():
        if not (isinstance(value, str) and COLOUR.fullmatch(value)):
            fail(f"design.json.colour.{key}", f"not a #rrggbb colour: {value!r}")
        colours[key] = rgb(value)
    sizes = {}
    for key, value in doc["size"].items():
        if isinstance(value, bool) or not isinstance(value, (int, float)):
            fail(f"design.json.size.{key}", f"not a number: {value!r}")
        sizes[key] = float(value)
    check_contrast(doc["contrast"], colours)
    look = {}
    for key, kind in LOOK_FIELDS:
        if key not in doc["look"]:
            raise DataError(f"design.json.look has no '{key}'")
        value = doc["look"][key]
        look[key] = rgb(value) if kind == "colour" else value
    return colours, sizes, look


#: Spec §16: anything text-like clears this against what it sits on.
MIN_CONTRAST = 4.5


def relative_luminance(value):
    """WCAG 2 relative luminance of an sRGB 0xRRGGBB colour."""
    def channel(c):
        v = (value >> c & 0xFF) / 255
        return v / 12.92 if v <= 0.04045 else ((v + 0.055) / 1.055) ** 2.4
    return 0.2126 * channel(16) + 0.7152 * channel(8) + 0.0722 * channel(0)


def contrast(a, b):
    """The WCAG contrast ratio of two sRGB colours, 1…21."""
    la, lb = relative_luminance(a), relative_luminance(b)
    return (max(la, lb) + 0.05) / (min(la, lb) + 0.05)


def check_contrast(pairs, colours):
    """Every declared lettering-on-ground pair clears spec §16's 4.5:1, or nothing is written."""
    if not isinstance(pairs, list) or not pairs:
        raise DataError("design.json.contrast is the list of lettering-on-ground pairs to check")
    for pair in pairs:
        if not (isinstance(pair, list) and len(pair) == 2):
            fail("design.json.contrast", f"expected [ink, ground] pairs: {pair!r}")
        ink, ground = pair
        for key in pair:
            if key not in colours:
                fail("design.json.contrast", f"{key!r} is not a declared colour")
        ratio = contrast(colours[ink], colours[ground])
        if ratio < MIN_CONTRAST:
            fail(f"design.json.contrast.{ink}-on-{ground}",
                 f"{ratio:.2f}:1 — spec \u00a716 wants at least {MIN_CONTRAST}:1; "
                 f"darken {ink} (#{colours[ink]:06x}) or lighten {ground} (#{colours[ground]:06x})")


def float_lit(v):
    text = repr(float(v))
    return text + "f" if text.endswith((".0",)) or "." in text else text + ".0f"


def emit(root):
    colours, sizes, look = load(root)
    return {SWIFT + "DesignTokens.swift": swift(colours, sizes, look),
            KOTLIN + "DesignTokens.kt": kotlin(colours, sizes, look)}


def swift(colours, sizes, look):
    out = [f"// {HEADER}\n// The 3D UI's design tokens (design.json): the palette, the sizes of the design frame, and\n"
           "// the light the menus are lit by — never the light of the world behind them.\n\n"]
    out.append("enum DesignTokens {\n    enum Colour {\n")
    for key, value in colours.items():
        out.append(f"        static let {camel(key)} = 0x{value:06X}\n")
    out.append("    }\n\n    enum Size {\n")
    for key, value in sizes.items():
        out.append(f"        static let {camel(key)}: Float = {float_lit(value)[:-1]}\n")
    out.append("    }\n\n")
    out.append("    /// The UI's own light (ADR 0006's formula), so a menu looks the same in every world.\n")
    args = ", ".join(f"{camel(key)}: " + look_value(look[key], kind, True) for key, kind in LOOK_FIELDS)
    out.append(f"    static let look = WorldLook({args})\n}}\n")
    return "".join(out)


def kotlin(colours, sizes, look):
    out = [f"// {HEADER}\n// The 3D UI's design tokens (design.json): the palette, the sizes of the design frame, and\n"
           "// the light the menus are lit by — never the light of the world behind them.\n"
           "package `in`.nann.smashhockey.ui.generated\n\n"
           "import `in`.nann.smashhockey.generated.WorldLook\n\n"]
    out.append("object DesignTokens {\n    object Colour {\n")
    for key, value in colours.items():
        out.append(f"        const val {upper_snake(key)} = 0x{value:06X}\n")
    out.append("    }\n\n    object Size {\n")
    for key, value in sizes.items():
        out.append(f"        const val {upper_snake(key)}: Float = {float_lit(value)}\n")
    out.append("    }\n\n")
    out.append("    /** The UI's own light (ADR 0006's formula), so a menu looks the same in every world. */\n")
    args = ", ".join(look_value(look[key], kind, False) for key, kind in LOOK_FIELDS)
    out.append(f"    val LOOK = WorldLook({args})\n}}\n")
    return "".join(out)
