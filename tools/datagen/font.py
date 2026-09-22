"""Emits the shared font's metrics: shared/assets/fonts/LilitaOne-Regular.ttf → both cores.

The 3D UI's lettering is extruded from one font file on both platforms (ADR 0005), but each
platform meshes it with its own engine — RealityKit's `generateText` on iOS, our own outline
triangulation on Android — and each engine reports a *different* box around the result. Laying a
screen out from that box is what let the two platforms drift: a word's place on its slab came out
of the mesher rather than out of the font.

So the metrics the layout needs — how wide a string is, and where its line sits — are read here,
straight from the font's own tables, and generated into both cores as plain numbers. `TextLayout`
in each core turns them into the one layout computation both apps share.

Only the horizontal metrics are needed: the advance of every glyph the font maps, plus the
units-per-em, the cap height (what `height` means everywhere in the kit) and the ascent and
descent that fix the line box. TrueType only; stdlib only.
"""
import struct

from .common import HEADER
from .model import DataError

FONT = "shared/assets/fonts/LilitaOne-Regular.ttf"
# The subset the UI can ever show: the font's whole cmap is Latin-1 plus a few marks, so it is
# emitted whole rather than guessed at from the copy — a player types their team's name.


class Font:
    def __init__(self, units_per_em, cap_height, ascent, descent, notdef, advances):
        self.units_per_em = units_per_em
        self.cap_height = cap_height
        self.ascent = ascent
        self.descent = descent
        self.notdef = notdef
        #: codepoint -> advance in font units, sorted by codepoint
        self.advances = advances


def _tables(data):
    if len(data) < 12:
        raise DataError(f"{FONT} is not a font file")
    count = struct.unpack_from(">H", data, 4)[0]
    out = {}
    for i in range(count):
        tag, _, off, length = struct.unpack_from(">4sIII", data, 12 + 16 * i)
        out[tag.decode("latin1")] = (off, length)
    for needed in ("head", "hhea", "hmtx", "cmap", "maxp", "OS/2"):
        if needed not in out:
            raise DataError(f"{FONT} has no '{needed}' table")
    return out


def _cmap(data, offset):
    """The Unicode subtable as codepoint -> glyph id. Format 4 (what every Latin TTF uses)."""
    count = struct.unpack_from(">H", data, offset + 2)[0]
    best = None
    for i in range(count):
        pid, eid, off = struct.unpack_from(">HHI", data, offset + 4 + 8 * i)
        if (pid, eid) in ((3, 1), (3, 10), (0, 3), (0, 4), (0, 6)):
            best = offset + off
    if best is None:
        raise DataError(f"{FONT} has no Unicode cmap subtable")
    fmt = struct.unpack_from(">H", data, best)[0]
    if fmt != 4:
        raise DataError(f"{FONT}'s Unicode cmap is format {fmt}; only format 4 is read")
    seg2 = struct.unpack_from(">H", data, best + 6)[0]
    segments = seg2 // 2
    ends = best + 14
    starts = ends + seg2 + 2
    deltas = starts + seg2
    ranges = deltas + seg2
    out = {}
    for s in range(segments):
        end = struct.unpack_from(">H", data, ends + 2 * s)[0]
        start = struct.unpack_from(">H", data, starts + 2 * s)[0]
        delta = struct.unpack_from(">h", data, deltas + 2 * s)[0]
        range_off = struct.unpack_from(">H", data, ranges + 2 * s)[0]
        if start > end:
            continue
        for cp in range(start, min(end, 0xFFFF) + 1):
            if range_off == 0:
                glyph = (cp + delta) & 0xFFFF
            else:
                at = ranges + 2 * s + range_off + 2 * (cp - start)
                if at + 1 >= len(data):
                    continue
                glyph = struct.unpack_from(">H", data, at)[0]
                if glyph:
                    glyph = (glyph + delta) & 0xFFFF
            if glyph and cp != 0xFFFF:
                out[cp] = glyph
    return out


def load(root):
    path = root / FONT
    if not path.exists():
        raise DataError(f"{FONT} is missing — the shared font is what both apps letter with")
    data = path.read_bytes()
    tabs = _tables(data)
    head = tabs["head"][0]
    units_per_em = struct.unpack_from(">H", data, head + 18)[0]
    hhea = tabs["hhea"][0]
    ascent, descent, _gap = struct.unpack_from(">hhh", data, hhea + 4)
    long_metrics = struct.unpack_from(">H", data, hhea + 34)[0]
    os2 = tabs["OS/2"][0]
    version = struct.unpack_from(">H", data, os2)[0]
    if version < 2:
        raise DataError(f"{FONT}'s OS/2 table is version {version}; sCapHeight needs version 2")
    cap_height = struct.unpack_from(">h", data, os2 + 88)[0]
    if not (0 < cap_height <= units_per_em and units_per_em > 0 and ascent > 0 > descent):
        raise DataError(f"{FONT} has implausible vertical metrics: "
                        f"upem {units_per_em}, cap {cap_height}, ascent {ascent}, descent {descent}")
    hmtx = tabs["hmtx"][0]

    def advance(glyph):
        i = min(glyph, long_metrics - 1)
        return struct.unpack_from(">H", data, hmtx + 4 * i)[0]

    cmap = _cmap(data, tabs["cmap"][0])
    advances = sorted((cp, advance(g)) for cp, g in cmap.items())
    if not advances:
        raise DataError(f"{FONT} maps no characters")
    return Font(units_per_em, cap_height, ascent, descent, advance(0), advances)


DOC = ("The shared font's own metrics (LilitaOne-Regular.ttf), so both platforms measure a string "
       "the same way\n// instead of asking their mesher — see SmashCore's TextLayout / core's "
       "TextLayout.")


def _rows(font, per_line=8):
    """The advance table as source lines: codepoint, advance pairs, sorted."""
    flat = [f"{cp}, {adv}," for cp, adv in font.advances]
    return ["        " + " ".join(flat[i:i + per_line]) for i in range(0, len(flat), per_line)]


def emit(root):
    from . import kotlin, swift
    font = load(root)
    return {swift.SRC + "FontMetrics.swift": _swift(font),
            kotlin.SRC + "FontMetrics.kt": _kotlin(font)}


def _swift(font):
    rows = "\n".join(_rows(font))
    return (f"// {HEADER}\n// {DOC}\n\n"
            "/// The UI font's horizontal metrics in font units, straight from its own tables.\n"
            "public enum FontMetrics {\n"
            f"    public static let unitsPerEm = {font.units_per_em}\n"
            "    /// Cap height — what `height` means for every piece of lettering in the kit.\n"
            f"    public static let capHeight = {font.cap_height}\n"
            f"    public static let ascent = {font.ascent}\n"
            f"    public static let descent = {font.descent}\n"
            "    /// What an unmapped character is laid out as (the font's .notdef box).\n"
            f"    public static let notdefAdvance = {font.notdef}\n\n"
            "    /// The advance of `scalar`, in font units.\n"
            "    public static func advance(_ scalar: Unicode.Scalar) -> Int {\n"
            "        let cp = Int(scalar.value)\n"
            "        var lo = 0, hi = table.count / 2 - 1\n"
            "        while lo <= hi {\n"
            "            let mid = (lo + hi) / 2\n"
            "            let key = table[mid * 2]\n"
            "            if key == cp { return table[mid * 2 + 1] }\n"
            "            if key < cp { lo = mid + 1 } else { hi = mid - 1 }\n"
            "        }\n"
            "        return notdefAdvance\n"
            "    }\n\n"
            "    /// Codepoint, advance pairs, sorted by codepoint.\n"
            "    static let table: [Int] = [\n"
            f"{rows}\n"
            "    ]\n}\n")


def _kotlin(font):
    rows = "\n".join(_rows(font))
    return (f"// {HEADER}\n// {DOC}\n"
            "package `in`.nann.smashhockey.core.generated\n\n"
            "/** The UI font's horizontal metrics in font units, straight from its own tables. */\n"
            "object FontMetrics {\n"
            f"    const val UNITS_PER_EM = {font.units_per_em}\n"
            "    /** Cap height — what `height` means for every piece of lettering in the kit. */\n"
            f"    const val CAP_HEIGHT = {font.cap_height}\n"
            f"    const val ASCENT = {font.ascent}\n"
            f"    const val DESCENT = {font.descent}\n"
            "    /** What an unmapped character is laid out as (the font's .notdef box). */\n"
            f"    const val NOTDEF_ADVANCE = {font.notdef}\n\n"
            "    /** The advance of the character at [codePoint], in font units. */\n"
            "    fun advance(codePoint: Int): Int {\n"
            "        var lo = 0\n"
            "        var hi = TABLE.size / 2 - 1\n"
            "        while (lo <= hi) {\n"
            "            val mid = (lo + hi) / 2\n"
            "            val key = TABLE[mid * 2]\n"
            "            if (key == codePoint) return TABLE[mid * 2 + 1]\n"
            "            if (key < codePoint) lo = mid + 1 else hi = mid - 1\n"
            "        }\n"
            "        return NOTDEF_ADVANCE\n"
            "    }\n\n"
            "    /** Codepoint, advance pairs, sorted by codepoint. */\n"
            "    internal val TABLE = intArrayOf(\n"
            f"{rows}\n"
            "    )\n}\n")
