"""Emits the sound bank (shared/data/sounds.toml, spec §8.8) → SmashCore and :core, next to the copy
keys: the ids of the events the game plays and, per event, its variant files (for both sports, or
per sport), gain, pitch spread, voices, priority and mixing bus. Every named file must exist in both
formats (`<name>.m4a` for iOS, `<name>.ogg` for Android) under shared/assets/sounds/ — the generator
refuses otherwise, and each app fails its launch loudly on a file its bundle lacks. An event with no
files is silent by declaration. The playback layers are each app's own; the pure choices about a
play (which variant, which voice, what pitch, rate and pan) live in the cores' Feel/ and are tested
there. Nothing here reaches a tick.
"""
import re
import tomllib

from .common import HEADER, double_lit
from .model import DataError, camel, fail, upper_snake

SWIFT = "ios/SmashCore/Sources/SmashCore/Generated/Sounds.swift"
KOTLIN = "android/core/src/main/kotlin/in/nann/smashhockey/core/generated/Sounds.kt"
BUSES = ("match", "ui", "ambience")
REQUIRED = {"category", "when", "gain_db", "pitch_semitones", "max_voices", "priority"}
OPTIONAL = {"files", "field", "ice", "todo"}
ID = re.compile(r"[a-z]+(\.[a-z]+)*")
NAME = re.compile(r"[a-z0-9_\-]+(/[a-z0-9_\-]+)*")


def load(root):
    path = root / "shared" / "data" / "sounds.toml"
    if not path.exists():
        raise DataError(f"{path} is missing — the sound bank's declaration (spec §8.8)")
    with open(path, "rb") as f:
        data = tomllib.load(f)
    if data.get("version") != 1:
        fail("sounds.toml", "version must be 1")
    if sorted(data.get("category", {})) != sorted(BUSES):
        fail("sounds.toml [category]", f"the buses are {BUSES}")
    events = data.get("event")
    if not isinstance(events, dict) or not events:
        fail("sounds.toml", "declares no [event.\"…\"]")
    sounds = root / "shared" / "assets" / "sounds"
    out = []
    for key, e in events.items():
        w = f"sounds.toml event.{key}"
        if not ID.fullmatch(key):
            fail(w, "an id is lower-case words joined by dots")
        missing, extra = REQUIRED - set(e), set(e) - REQUIRED - OPTIONAL
        if missing or extra:
            fail(w, f"missing {sorted(missing)} / undeclared {sorted(extra)}")
        if "files" in e and ("field" in e or "ice" in e):
            fail(w, "either `files`, or `field` and `ice`")
        if "files" not in e and not ("field" in e and "ice" in e):
            fail(w, "needs `files`, or both `field` and `ice`")
        field = e.get("files", e.get("field"))
        ice = e.get("files", e.get("ice"))
        for name in field + ice:
            if not isinstance(name, str) or not NAME.fullmatch(name):
                fail(w, f"{name!r}: a path under shared/assets/sounds/ without extension, lower-case")
            for ext in ("m4a", "ogg"):
                if not (sounds / f"{name}.{ext}").exists():
                    fail(w, f"shared/assets/sounds/{name}.{ext} does not exist")
        if e["category"] not in BUSES:
            fail(w, f"category: one of {BUSES}")
        if not isinstance(e["gain_db"], float) or not -40.0 <= e["gain_db"] <= 12.0:
            fail(w, "gain_db: a float in −40…12")
        if not isinstance(e["pitch_semitones"], float) or not 0.0 <= e["pitch_semitones"] <= 12.0:
            fail(w, "pitch_semitones: a float in 0…12")
        for k, lo, hi in (("max_voices", 1, 8), ("priority", 0, 100)):
            if not isinstance(e[k], int) or isinstance(e[k], bool) or not lo <= e[k] <= hi:
                fail(w, f"{k}: an integer {lo}…{hi}")
        out.append(dict(key=key, field=field, ice=ice, gain=e["gain_db"], pitch=e["pitch_semitones"],
                        voices=e["max_voices"], priority=e["priority"], bus=e["category"]))
    return out


def emit(root):
    events = load(root)
    return {SWIFT: swift(events), KOTLIN: kotlin(events)}


def _list(names, swift):
    body = ", ".join(f'"{n}"' for n in names)
    return f"[{body}]" if swift else f"listOf({body})"


def swift(events):
    o = [f"// {HEADER}\n// The sound bank (shared/data/sounds.toml, spec §8.8): the events the game plays and how each plays.\n\n"
         "/// The mixing bus an event plays on (sounds.toml `category`).\npublic enum SoundBus: String, Sendable, Hashable, CaseIterable {\n"
         "    case match, ui, ambience\n}\n\n"
         "/// How an event plays (sounds.toml).\npublic struct SoundSpec: Sendable, Hashable {\n"
         "    /// The variants on a field-hockey pitch and on ice: paths under shared/assets/sounds/ without\n"
         "    /// extension (iOS plays `.m4a`, Android `.ogg`). Empty: silent by declaration.\n"
         "    public let field: [String]\n    public let ice: [String]\n"
         "    /// Playback gain on top of the file's level, dB.\n    public let gainDb: Double\n"
         "    /// Each play's pitch is drawn uniformly in ± this many semitones.\n    public let pitchSemitones: Double\n"
         "    /// How many of this event may sound at once; one more steals the oldest.\n    public let maxVoices: Int\n"
         "    /// 0–100: with every voice taken, a play steals only from a lower priority.\n    public let priority: Int\n"
         "    public let bus: SoundBus\n\n"
         "    public func files(_ sport: Sport) -> [String] { sport == .ice ? ice : field }\n}\n\n"
         "/// An event the game plays (sounds.toml `[event.\"…\"]`).\npublic enum SoundCue: String, Sendable, Hashable, CaseIterable {\n"]
    for e in events:
        o.append(f"    case {camel(e['key'])} = \"{e['key']}\"\n")
    o.append("\n    public var spec: SoundSpec {\n        switch self {\n")
    for e in events:
        o.append(f"        case .{camel(e['key'])}: SoundSpec(field: {_list(e['field'], True)}, ice: {_list(e['ice'], True)}, "
                 f"gainDb: {double_lit(e['gain'])}, pitchSemitones: {double_lit(e['pitch'])}, maxVoices: {e['voices']}, "
                 f"priority: {e['priority']}, bus: .{e['bus']})\n")
    o.append("        }\n    }\n}\n")
    return "".join(o)


def kotlin(events):
    o = [f"// {HEADER}\n// The sound bank (shared/data/sounds.toml, spec §8.8): the events the game plays and how each plays.\n"
         "package `in`.nann.smashhockey.core.generated\n\n"
         "/** The mixing bus an event plays on (sounds.toml `category`). */\nenum class SoundBus { MATCH, UI, AMBIENCE }\n\n"
         "/**\n * How an event plays (sounds.toml): its variants on a field-hockey pitch and on ice (paths under\n"
         " * shared/assets/sounds/ without extension — Android plays `.ogg`, iOS `.m4a`; empty: silent by\n"
         " * declaration), its gain (dB over the file's level), its pitch spread (± semitones), how many may\n"
         " * sound at once (one more steals the oldest), its priority (0–100: with every voice taken, a play\n"
         " * steals only from a lower one) and its bus.\n */\n"
         "data class SoundSpec(\n    val field: List<String>,\n    val ice: List<String>,\n    val gainDb: Double,\n"
         "    val pitchSemitones: Double,\n    val maxVoices: Int,\n    val priority: Int,\n    val bus: SoundBus,\n) {\n"
         "    fun files(sport: Sport): List<String> = if (sport == Sport.ICE) ice else field\n}\n\n"
         "/** An event the game plays (sounds.toml `[event.\"…\"]`). */\nenum class SoundCue(val key: String, val spec: SoundSpec) {\n"]
    for e in events:
        o.append(f"    {upper_snake(e['key'])}(\"{e['key']}\", SoundSpec({_list(e['field'], False)}, {_list(e['ice'], False)}, "
                 f"{double_lit(e['gain'])}, {double_lit(e['pitch'])}, {e['voices']}, {e['priority']}, "
                 f"SoundBus.{e['bus'].upper()})),\n")
    o.append("}\n")
    return "".join(o)
