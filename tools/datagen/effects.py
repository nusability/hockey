"""Loads shared/data/effects.toml (what is alive in each world, spec §13, ADR 0007) and emits it into
both app targets — iOS ios/Sources/Effects/Generated/Effects.swift, Android …/effects/generated/Effects.kt.

`load` is also what the world builds read (tools/worldkit.py, inside Blender): one parser, one set of
rules, so an effect the apps drive is exactly an effect the asset carries. Every effect comes out with
every field filled — a field its shading or motion does not use is its neutral value, never a guess:
the declaration must give each field it does use (conventions: fail loud).
"""
import tomllib

from .common import HEADER, double_lit
from .model import DataError, fail, upper_snake

SWIFT = "ios/Sources/Effects/Generated/"
KOTLIN = "android/app/src/main/kotlin/in/nann/smashhockey/effects/generated/"

SHADINGS = ("lit", "glow", "soft", "particles")
BLENDS = ("add", "alpha")
MOTIONS = ("none", "sway", "orbit")
MESH_FIELDS = {"sway": ("sway", "sway_rate"), "orbit": ("spin", "pivot", "ellipse", "sway", "sway_rate")}
PARTICLE_FIELDS = ("size", "size_spread", "opacity", "travel", "wrap", "wobble", "wobble_rate")
KNOWN = {"world", "id", "shading", "blend", "motion", "sway", "sway_rate", "spin", "pivot", "ellipse", "pulse",
         "opacity", "size", "size_spread", "travel", "wrap", "wobble", "wobble_rate", "over_pitch"}
NEUTRAL = dict(blend="opaque", motion="none", sway=[0.0, 0.0, 0.0], sway_rate=0.0, spin=0.0, pivot=[0.0, 0.0, 0.0],
               ellipse=1.0, pulse=[1.0, 0.0, 0.0, 0.0, 0.0], opacity=1.0, size=0.0, size_spread=0.0,
               travel=[0.0, 0.0, 0.0], wrap=0.0, wobble=[0.0, 0.0, 0.0], wobble_rate=0.0, over_pitch=False)
WORLDS = ("magicwood", "space", "oasis", "himalaya", "ocean")


def _num(v, where):
    if isinstance(v, bool) or not isinstance(v, (int, float)):
        fail(where, f"expected a number, got {v!r}")
    return float(v)


def _vec(v, n, where):
    if not isinstance(v, list) or len(v) != n:
        fail(where, f"expected a list of {n} numbers, got {v!r}")
    return [_num(x, f"{where}[{i}]") for i, x in enumerate(v)]


def load(path):
    """The declarations, validated: {'calm': {...}, 'effects': [{...}, ...]} in file order."""
    if not path.exists():
        raise DataError(f"{path} is missing")
    with open(path, "rb") as f:
        doc = tomllib.load(f)
    where = "effects.toml"
    calm = doc.get("calm")
    if not isinstance(calm, dict) or set(calm) != {"amplitude", "speed"}:
        fail(f"{where}.calm", "declare exactly amplitude and speed (Reduce Motion)")
    calm = {k: _num(v, f"{where}.calm.{k}") for k, v in calm.items()}
    out, seen = [], set()
    for i, e in enumerate(doc.get("effect", [])):
        w = f"{where}.effect[{i}]"
        extra = set(e) - KNOWN
        if extra:
            fail(w, f"unknown fields {sorted(extra)}")
        for k in ("world", "id", "shading"):
            if k not in e:
                fail(w, f"missing {k}")
        if e["world"] not in WORLDS:
            fail(w, f"unknown world {e['world']!r}")
        ident = e["id"]
        if not isinstance(ident, str) or not ident.replace("_", "").isalnum() or not ident[:1].isalpha():
            fail(w, f"id {ident!r} must be a lower-case identifier")
        if (e["world"], ident) in seen:
            fail(w, f"{e['world']}/{ident} is declared twice")
        seen.add((e["world"], ident))
        w = f"{where}.{e['world']}.{ident}"
        shading = e["shading"]
        if shading not in SHADINGS:
            fail(w, f"shading must be one of {SHADINGS}")
        fx = dict(NEUTRAL, world=e["world"], id=ident, shading=shading)
        blended = shading in ("soft", "particles")
        if blended != ("blend" in e):
            fail(w, "soft and particles declare a blend (add | alpha); lit and glow do not")
        if blended:
            if e["blend"] not in BLENDS:
                fail(w, f"blend must be one of {BLENDS}")
            fx["blend"] = e["blend"]
        if shading == "particles":
            if "motion" in e:
                fail(w, "particles move by travel and wobble, not by a motion")
            need = PARTICLE_FIELDS
        else:
            if e.get("motion") not in MOTIONS:
                fail(w, f"motion must be one of {MOTIONS}")
            fx["motion"] = e["motion"]
            need = MESH_FIELDS.get(e["motion"], ()) + (("opacity",) if shading == "soft" else ())
            if "over_pitch" in e:
                fail(w, "only particles may cross the pitch")
        allowed = set(need) | {"world", "id", "shading", "blend", "motion", "pulse", "over_pitch"}
        stray = set(e) - allowed
        if stray:
            fail(w, f"fields {sorted(stray)} do nothing for a {shading} effect with motion {fx['motion']}")
        for k in need:
            if k not in e:
                fail(w, f"missing {k}")
            fx[k] = _vec(e[k], 3, f"{w}.{k}") if isinstance(NEUTRAL[k], list) else _num(e[k], f"{w}.{k}")
        if "pulse" in e:
            fx["pulse"] = _vec(e["pulse"], 5, f"{w}.pulse")
        if "over_pitch" in e:
            if not isinstance(e["over_pitch"], bool):
                fail(w, "over_pitch is true or false")
            fx["over_pitch"] = e["over_pitch"]
        if fx["ellipse"] <= 0:
            fail(w, "ellipse must be positive")
        if shading == "particles" and fx["size"] <= 0:
            fail(w, "size must be positive")
        out.append(fx)
    return {"calm": calm, "effects": out}


def for_world(decl, world):
    return [e for e in decl["effects"] if e["world"] == world]


def emit(root):
    decl = load(root / "shared" / "data" / "effects.toml")
    return {SWIFT + "Effects.swift": swift(decl), KOTLIN + "Effects.kt": kotlin(decl)}


def _lits(values, swift_):
    body = ", ".join(double_lit(v) for v in values)
    return f"[{body}]" if swift_ else f"listOf({body})"


# --- Swift ---------------------------------------------------------------------------------------

def swift(decl):
    out = [f"// {HEADER}\n// What is alive in each world (effects.toml, spec §13, ADR 0007): presentation only, driven\n"
           "// on the renderer's clock by the effect shaders (FxMaterials).\n\nimport SmashCore\n\n"
           "enum FxShading: Sendable { case lit, glow, soft, particles }\n"
           "enum FxBlend: Sendable { case opaque, add, alpha }\n"
           "enum FxMotion: Sendable { case none, sway, orbit }\n\n"
           "/// One declared effect: the mesh `fx_<id>` in its world's asset and the numbers that move it.\n"
           "struct FxSpec: Sendable {\n    let id: String\n    let shading: FxShading\n    let blend: FxBlend\n"
           "    let motion: FxMotion\n    let sway: [Double]\n    let swayRate: Double\n    let spin: Double\n"
           "    let pivot: [Double]\n    let ellipse: Double\n    /// base, a1, ω1, a2, ω2\n    let pulse: [Double]\n"
           "    let opacity: Double\n    let size: Double\n    let sizeSpread: Double\n    let travel: [Double]\n"
           "    let wrap: Double\n    let wobble: [Double]\n    let wobbleRate: Double\n}\n\n"
           "/// Reduce Motion: every amplitude and rate is multiplied by these.\n"
           f"enum FxCalm {{\n    static let amplitude: Double = {double_lit(decl['calm']['amplitude'])}\n"
           f"    static let speed: Double = {double_lit(decl['calm']['speed'])}\n}}\n\n"
           "extension World {\n    var effects: [FxSpec] {\n        switch self {\n"]
    for world in WORLDS:
        fxs = for_world(decl, world)
        if not fxs:
            out.append(f"        case .{world}: []\n")
            continue
        out.append(f"        case .{world}: [\n")
        for e in fxs:
            out.append(
                f"            FxSpec(id: \"{e['id']}\", shading: .{e['shading']}, blend: .{e['blend']}, motion: .{e['motion']}, "
                f"sway: {_lits(e['sway'], True)}, swayRate: {double_lit(e['sway_rate'])}, spin: {double_lit(e['spin'])}, "
                f"pivot: {_lits(e['pivot'], True)}, ellipse: {double_lit(e['ellipse'])}, pulse: {_lits(e['pulse'], True)}, "
                f"opacity: {double_lit(e['opacity'])}, size: {double_lit(e['size'])}, sizeSpread: {double_lit(e['size_spread'])}, "
                f"travel: {_lits(e['travel'], True)}, wrap: {double_lit(e['wrap'])}, wobble: {_lits(e['wobble'], True)}, "
                f"wobbleRate: {double_lit(e['wobble_rate'])}),\n")
        out.append("        ]\n")
    out.append("        }\n    }\n}\n")
    return "".join(out)


# --- Kotlin --------------------------------------------------------------------------------------

def kotlin(decl):
    out = [f"// {HEADER}\n// What is alive in each world (effects.toml, spec §13, ADR 0007): presentation only, driven\n"
           "// on the renderer's clock by the effect materials (fx_*.mat).\n"
           "package `in`.nann.smashhockey.effects.generated\n\nimport `in`.nann.smashhockey.core.generated.World\n\n"
           "enum class FxShading { LIT, GLOW, SOFT, PARTICLES }\n"
           "enum class FxBlend { OPAQUE, ADD, ALPHA }\n"
           "enum class FxMotion { NONE, SWAY, ORBIT }\n\n"
           "/** One declared effect: the mesh `fx_<id>` in its world's asset and the numbers that move it. */\n"
           "data class FxSpec(\n    val id: String,\n    val shading: FxShading,\n    val blend: FxBlend,\n"
           "    val motion: FxMotion,\n    val sway: List<Double>,\n    val swayRate: Double,\n    val spin: Double,\n"
           "    val pivot: List<Double>,\n    val ellipse: Double,\n    /** base, a1, ω1, a2, ω2 */\n    val pulse: List<Double>,\n"
           "    val opacity: Double,\n    val size: Double,\n    val sizeSpread: Double,\n    val travel: List<Double>,\n"
           "    val wrap: Double,\n    val wobble: List<Double>,\n    val wobbleRate: Double,\n)\n\n"
           "/** Reduce Motion: every amplitude and rate is multiplied by these. */\n"
           f"object FxCalm {{\n    const val amplitude: Double = {double_lit(decl['calm']['amplitude'])}\n"
           f"    const val speed: Double = {double_lit(decl['calm']['speed'])}\n}}\n\n"
           "val World.effects: List<FxSpec>\n    get() = when (this) {\n"]
    for world in WORLDS:
        fxs = for_world(decl, world)
        out.append(f"        World.{upper_snake(world)} -> listOf(\n")
        for e in fxs:
            out.append(
                f"            FxSpec(\"{e['id']}\", FxShading.{e['shading'].upper()}, FxBlend.{e['blend'].upper()}, "
                f"FxMotion.{e['motion'].upper()}, {_lits(e['sway'], False)}, {double_lit(e['sway_rate'])}, "
                f"{double_lit(e['spin'])}, {_lits(e['pivot'], False)}, {double_lit(e['ellipse'])}, {_lits(e['pulse'], False)}, "
                f"{double_lit(e['opacity'])}, {double_lit(e['size'])}, {double_lit(e['size_spread'])}, "
                f"{_lits(e['travel'], False)}, {double_lit(e['wrap'])}, {_lits(e['wobble'], False)}, "
                f"{double_lit(e['wobble_rate'])}),\n")
        out.append("        )\n")
    out.append("    }\n")
    return "".join(out)
