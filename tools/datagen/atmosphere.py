"""Emits the looping layers (shared/data/atmosphere.toml, spec §8.8) → the iOS app target and
Android's :app module, beside the rest of the presentation.

The crowd beds and the drum music: which file each layer plays, where it sits, the gains its
envelope runs between, and the mapping from the match to that envelope. The mapping's arithmetic is
the cores' `Atmosphere` (Feel/), tested there; this is only its numbers. Like the rest of
presentation, nothing declared here can change what a tick does (spec §4.2).
"""
import re
import tomllib

from .common import HEADER, double_lit
from .model import DataError, camel, fail, upper_snake

SWIFT = "ios/Sources/Scene/Generated/"
KOTLIN = "android/app/src/main/kotlin/in/nann/smashhockey/generated/"
NAME = re.compile(r"[a-z0-9_\-]+(/[a-z0-9_\-]+)*")
FOLLOWS = ("home", "away", "swell")
MAPPING = ("shape", "base", "rise", "hush", "late_seconds", "late_rise", "attack_danger", "defend_danger",
           "pan_span", "surge_decay", "attack_rate", "release_rate")
SURGE = ("kickoff", "goal_for", "goal_against", "save", "post", "steal", "whistle", "period_end", "ended")
MUSIC_MAPPING = ("base", "rise", "late_rise", "attack_rate", "release_rate")
DUCK = ("depth_db", "attack", "hold", "release")
SETTING = ("music_default", "crowd_default", "steps")


def load(root):
    path = root / "shared" / "data" / "atmosphere.toml"
    if not path.exists():
        raise DataError(f"{path} is missing — the looping layers' declaration (spec §8.8)")
    with open(path, "rb") as f:
        data = tomllib.load(f)
    if data.get("version") != 1:
        fail("atmosphere.toml", "version must be 1")
    sounds = root / "shared" / "assets" / "sounds"

    def file_of(where, layer):
        name = layer.get("file")
        if not isinstance(name, str) or not NAME.fullmatch(name):
            fail(where, "file: a path under shared/assets/sounds/ without extension, lower-case")
        for ext in ("m4a", "ogg"):
            if not (sounds / f"{name}.{ext}").exists():
                fail(where, f"shared/assets/sounds/{name}.{ext} does not exist — run tools/prepare-sounds.py")
        return name

    def db(where, layer, key):
        v = layer.get(key)
        if not isinstance(v, float) or not -60.0 <= v <= 6.0:
            fail(where, f"{key}: a float in −60…6")
        return v

    beds = []
    for lid, layer in (data.get("bed") or {}).items():
        w = f"atmosphere.toml bed.{lid}"
        if layer.get("follows") not in FOLLOWS:
            fail(w, f"follows: one of {FOLLOWS}")
        for key, lo, hi in (("pan", -1.0, 1.0), ("rate", 0.5, 2.0)):
            if not isinstance(layer.get(key), float) or not lo <= layer[key] <= hi:
                fail(w, f"{key}: a float in {lo}…{hi}")
        beds.append(dict(id=lid, file=file_of(w, layer), follows=layer["follows"], pan=layer["pan"],
                         rate=layer["rate"], quiet=db(w, layer, "quiet_db"), loud=db(w, layer, "loud_db")))
    if [b["follows"] for b in beds] != ["home", "away", "swell"]:
        fail("atmosphere.toml [bed]", "declare exactly one bed per envelope, in the order home, away, swell")

    tracks = {}
    for tid in ("match", "menu"):
        layer = (data.get("music") or {}).get(tid)
        w = f"atmosphere.toml music.{tid}"
        if not isinstance(layer, dict):
            fail("atmosphere.toml [music]", "declare both music.match and music.menu")
        if not isinstance(layer.get("follows_time_scale"), bool):
            fail(w, "follows_time_scale: true or false")
        tracks[tid] = dict(file=file_of(w, layer), quiet=db(w, layer, "quiet_db"), loud=db(w, layer, "loud_db"),
                           slows=layer["follows_time_scale"])

    def numbers(table, keys, where):
        t = data.get(table)
        if not isinstance(t, dict) or sorted(t) != sorted(keys):
            fail(f"atmosphere.toml [{where}]", f"declares exactly {sorted(keys)}")
        for k in keys:
            if not isinstance(t[k], float):
                fail(f"atmosphere.toml [{where}].{k}", "a float")
        return t

    mapping = numbers("mapping", MAPPING, "mapping")
    surge = numbers("surge", SURGE, "surge")
    music_mapping = numbers("music_mapping", MUSIC_MAPPING, "music_mapping")
    setting = numbers("setting", SETTING, "setting")
    duck = data.get("duck") or {}
    if sorted(duck) != sorted(DUCK + ("cues",)):
        fail("atmosphere.toml [duck]", f"declares exactly {sorted(DUCK + ('cues',))}")
    for k in DUCK:
        if not isinstance(duck[k], float):
            fail(f"atmosphere.toml [duck].{k}", "a float")
    cues = duck["cues"]
    if not isinstance(cues, list) or not cues or not all(isinstance(c, str) for c in cues):
        fail("atmosphere.toml [duck].cues", "the sound-bank ids the music steps back under")
    time_scale = data.get("time_scale") or {}
    if sorted(time_scale) != ["min_rate"] or not isinstance(time_scale["min_rate"], float):
        fail("atmosphere.toml [time_scale]", "declares min_rate, a float")
    return dict(beds=beds, tracks=tracks, mapping=mapping, surge=surge, music_mapping=music_mapping,
                duck=duck, cues=cues, min_rate=time_scale["min_rate"], setting=setting)


def emit(root, sounds_keys):
    a = load(root)
    for c in a["cues"]:
        if c not in sounds_keys:
            fail("atmosphere.toml [duck].cues", f"{c!r} is not an event of shared/data/sounds.toml")
    return {SWIFT + "Atmosphere.swift": swift(a), KOTLIN + "Atmosphere.kt": kotlin(a)}


DOC = ("The looping layers under the game (shared/data/atmosphere.toml, spec §8.8): the crowd beds,\n"
       "the drum music, and the numbers the cores' `Atmosphere` turns the match into. Gains are dB,\n"
       "pans −1 (left) … 1 (right); a bed's envelope runs its gain from `quietDb` to `loudDb`.")


def swift(a):
    o = [f"// {HEADER}\n" + "".join(f"// {line}\n" for line in DOC.splitlines()) + "\nimport SmashCore\n\n",
         "public enum AtmosphereData {\n",
         "    /// Which of the crowd's envelopes a bed follows.\n",
         "    public enum Follows: String, Sendable, Hashable, CaseIterable { case home, away, swell }\n\n",
         "    /// One crowd bed: a loop that starts once and only ever changes its gain.\n",
         "    public struct Bed: Sendable, Hashable {\n"
         "        public let file: String\n        public let follows: Follows\n        public let pan: Double\n"
         "        public let rate: Double\n        public let quietDb: Double\n        public let loudDb: Double\n    }\n\n",
         "    /// One music loop. `followsTimeScale`: it slurs with §8.6's slow motion (the match's does).\n",
         "    public struct Track: Sendable, Hashable {\n"
         "        public let file: String\n        public let quietDb: Double\n        public let loudDb: Double\n"
         "        public let followsTimeScale: Bool\n    }\n\n",
         "    public static let beds: [Bed] = [\n"]
    for b in a["beds"]:
        o.append(f"        Bed(file: \"{b['file']}\", follows: .{b['follows']}, pan: {double_lit(b['pan'])}, "
                 f"rate: {double_lit(b['rate'])}, quietDb: {double_lit(b['quiet'])}, loudDb: {double_lit(b['loud'])}),\n")
    o.append("    ]\n\n")
    for tid in ("match", "menu"):
        t = a["tracks"][tid]
        o.append(f"    public static let {tid}Music = Track(file: \"{t['file']}\", quietDb: {double_lit(t['quiet'])}, "
                 f"loudDb: {double_lit(t['loud'])}, followsTimeScale: {'true' if t['slows'] else 'false'})\n")
    o.append("\n    /// How far the music steps back under a ducking cue, dB.\n"
             f"    public static let duckDepthDb = {double_lit(a['duck']['depth_db'])}\n\n"
             "    /// The one-shots the music steps back under.\n    public static let duckCues: [SoundCue] = [")
    o.append(", ".join(f".{camel(c)}" for c in a["cues"]))
    o.append("]\n\n    /// The coach's board's two volumes (§12), 0 (off) … 1.\n")
    for k in SETTING:
        o.append(f"    public static let {camel(k)} = {double_lit(a['setting'][k])}\n")
    o.append("\n    /// The mapping, handed to the core (`SmashCore.Atmosphere.Params`).\n"
             "    public static var params: SmashCore.Atmosphere.Params {\n"
             "        var p = SmashCore.Atmosphere.Params()\n")
    for k in MAPPING:
        o.append(f"        p.{camel(k)} = {double_lit(a['mapping'][k])}\n")
    for k in SURGE:
        o.append(f"        p.surge.{camel(k)} = {double_lit(a['surge'][k])}\n")
    for k in MUSIC_MAPPING:
        o.append(f"        p.music.{camel(k)} = {double_lit(a['music_mapping'][k])}\n")
    for k in ("attack", "hold", "release"):
        o.append(f"        p.duck{k.capitalize()} = {double_lit(a['duck'][k])}\n")
    o.append(f"        p.minRate = {double_lit(a['min_rate'])}\n        return p\n    }}\n}}\n")
    return "".join(o)


def kotlin(a):
    o = [f"// {HEADER}\n" + "".join(f"// {line}\n" for line in DOC.splitlines()),
         "package `in`.nann.smashhockey.generated\n\n",
         "import `in`.nann.smashhockey.core.feel.Atmosphere as Core\n",
         "import `in`.nann.smashhockey.core.generated.SoundCue\n\n",
         "object AtmosphereData {\n",
         "    /** Which of the crowd's envelopes a bed follows. */\n",
         "    enum class Follows { HOME, AWAY, SWELL }\n\n",
         "    /** One crowd bed: a loop that starts once and only ever changes its gain. */\n",
         "    data class Bed(\n        val file: String,\n        val follows: Follows,\n        val pan: Double,\n"
         "        val rate: Double,\n        val quietDb: Double,\n        val loudDb: Double,\n    )\n\n",
         "    /** One music loop. [followsTimeScale]: it slurs with §8.6's slow motion (the match's does). */\n",
         "    data class Track(\n        val file: String,\n        val quietDb: Double,\n        val loudDb: Double,\n"
         "        val followsTimeScale: Boolean,\n    )\n\n",
         "    val beds: List<Bed> = listOf(\n"]
    for b in a["beds"]:
        o.append(f"        Bed(\"{b['file']}\", Follows.{b['follows'].upper()}, {double_lit(b['pan'])}, "
                 f"{double_lit(b['rate'])}, {double_lit(b['quiet'])}, {double_lit(b['loud'])}),\n")
    o.append("    )\n\n")
    for tid in ("match", "menu"):
        t = a["tracks"][tid]
        o.append(f"    val {tid}Music = Track(\"{t['file']}\", {double_lit(t['quiet'])}, {double_lit(t['loud'])}, "
                 f"{'true' if t['slows'] else 'false'})\n")
    o.append("\n    /** How far the music steps back under a ducking cue, dB. */\n"
             f"    const val duckDepthDb: Double = {double_lit(a['duck']['depth_db'])}\n\n"
             "    /** The one-shots the music steps back under. */\n    val duckCues: List<SoundCue> = listOf(")
    o.append(", ".join(f"SoundCue.{upper_snake(c)}" for c in a["cues"]))
    o.append(")\n\n    /** The coach's board's two volumes (§12), 0 (off) … 1. */\n")
    for k in SETTING:
        o.append(f"    const val {camel(k)}: Double = {double_lit(a['setting'][k])}\n")
    o.append("\n    /** The mapping, handed to the core. */\n    val params: Core.Params = Core.Params(\n")
    for k in MAPPING:
        o.append(f"        {camel(k)} = {double_lit(a['mapping'][k])},\n")
    o.append("        surge = Core.Params.Surge(\n")
    for k in SURGE:
        o.append(f"            {camel(k)} = {double_lit(a['surge'][k])},\n")
    o.append("        ),\n        music = Core.Params.Music(\n")
    for k in MUSIC_MAPPING:
        o.append(f"            {camel(k)} = {double_lit(a['music_mapping'][k])},\n")
    o.append("        ),\n")
    for k in ("attack", "hold", "release"):
        o.append(f"        duck{k.capitalize()} = {double_lit(a['duck'][k])},\n")
    o.append(f"        minRate = {double_lit(a['min_rate'])},\n    )\n}}\n")
    return "".join(o)
