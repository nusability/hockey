"""Emits the Kotlin side: android/core/src/main/kotlin/in/nann/smashhockey/core/generated/*.kt and
the constant-bits table for the core module's tests."""
from .common import HEADER, double_lit
from .model import ROLES, bits_of, camel, pascal, upper_snake

PKG_DIR = "in/nann/smashhockey/core/generated/"
SRC = "android/core/src/main/kotlin/" + PKG_DIR
TEST = "android/core/src/test/kotlin/" + PKG_DIR
PACKAGE = "package `in`.nann.smashhockey.core.generated\n\n"


def head(doc):
    return f"// {HEADER}\n// {doc}\n{PACKAGE}"


def spot(s):
    return f"Spot({double_lit(s[0])}, {double_lit(s[1])})"


def role(code):
    return "Role." + ROLES[code].upper()


def signed(u64):
    return u64 - (1 << 64) if u64 >= 1 << 63 else u64


def long_lit(u64):
    v = signed(u64)
    return f"{v}L" if v != -(1 << 63) else "Long.MIN_VALUE"


def emit(model, bits):
    return {
        SRC + "Types.kt": types(),
        SRC + "Tuning.kt": tuning(model, bits),
        SRC + "World.kt": worlds(model, bits),
        SRC + "Teams.kt": teams(model, bits),
        SRC + "Drills.kt": drills(model, bits),
        SRC + "MathConstants.kt": math_constants(model),
        SRC + "CopyKey.kt": copy_keys(model),
    }


def bits_test(bits):
    rows = "\n".join(f'        Triple("{k}", {k}, {long_lit(b)}), // 0x{b:016X}' for k, b in bits.rows)
    return (head("Every double the generator declares, with its exact bit pattern (see ConstantBitsTest).")
            + "internal object GeneratedConstantBits {\n"
            + "    val all: List<Triple<String, Double, Long>> = listOf(\n" + rows + "\n    )\n}\n")


def lookup(type_name, source):
    return (f"    companion object {{\n"
            f"        /** The entry declared as [key]; throws for a key {source} does not declare. */\n"
            f"        fun of(key: String): {type_name} = entries.firstOrNull {{ it.key == key }}\n"
            f"            ?: throw IllegalArgumentException(\"unknown {type_name} '$key' — not declared in {source}\")\n"
            f"    }}\n")


def types():
    return head("The shapes the declarations in shared/data/ take.") + """\
/** A point on the pitch (x across, z along; spec §1). */
data class Spot(val x: Double, val z: Double)

/** A lineup role (spec §3): goalie, defender, forward, or a drill's dummy. */
enum class Role(val key: String) {
    GOALIE("G"), DEFENDER("D"), FORWARD("F"), DUMMY("O");

""" + lookup("Role", "shared/data") + """}

/** A formation's outfield player: role and home spot for a team attacking +Z (spec §3). */
data class LineupSpot(val role: Role, val spot: Spot)

/** A support slot relative to the ball (spec §7.4). */
data class SupportSlot(val x: Double, val z: Double, val role: Role, val mirror: Boolean)

/** A patrolling dummy's second point, speed and phase (spec §10). */
data class Patrol(val to: Spot, val speed: Double, val phase: Double)

/** A drill's player (spec §10). [patrol] is null for everyone but a patrolling dummy. */
data class DrillPlayer(val role: Role, val spot: Spot, val speed: Double, val patrol: Patrol?)

/** A drill's special rule (spec §10). */
enum class DrillRule(val key: String) {
    NONE("none"), ASSIST("assist"), FREE_PLAY("free_play");

""" + lookup("DrillRule", "drills.toml") + """}

/**
 * A pair of the created team's kit palette (spec §2.2). Colours are sRGB 0xRRGGBB; the names are
 * the swatches' accessibility labels.
 */
data class Kit(val id: String, val primary: Int, val secondary: Int, val primaryName: CopyKey, val secondaryName: CopyKey)

/** A step of the season's matchday plan (spec §11.1). */
sealed interface MatchdayStep {
    data class League(val round: Int) : MatchdayStep
    data class Cup(val round: CupRound) : MatchdayStep
}
"""


def tuning(model, bits):
    out = [head("The simulation's numbers (rules.toml), the coach's board (teams.toml [board]) and the motion tokens (motion.json)."),
           "object Tuning {\n"]

    def walk(tree, depth, path):
        pad = "    " * depth
        name = pascal(tree.name) if tree.name != "ai" else "AI"
        out.append(f"{pad}object {name} {{\n")
        kpath = f"{path}.{name}"
        for e in tree.entries:
            p, n = pad + "    ", camel(e.name)
            if e.doc:
                out.append(f"{p}/** {e.doc} */\n")
            full = f"{kpath}.{n}"
            if e.kind == "int":
                out.append(f"{p}const val {n}: Int = {e.value}\n")
            elif e.kind == "double":
                out.append(f"{p}const val {n}: Double = {double_lit(e.value)}\n")
                bits.add(full, e.value)
            elif e.kind == "bool":
                out.append(f"{p}const val {n}: Boolean = {'true' if e.value else 'false'}\n")
            elif e.kind == "string":
                out.append(f'{p}const val {n}: String = "{e.value}"\n')
            elif e.kind == "doubles":
                out.append(f"{p}val {n}: List<Double> = listOf({', '.join(double_lit(v) for v in e.value)})\n")
                for i, v in enumerate(e.value):
                    bits.add(f"{full}[{i}]", v)
            elif e.kind == "spot":
                out.append(f"{p}val {n}: Spot = {spot(e.value)}\n")
            elif e.kind == "spots":
                out.append(f"{p}val {n}: List<Spot> = listOf(\n")
                out.extend([f"{p}    {spot(s)},\n" for s in e.value])
                out.append(f"{p})\n")
            elif e.kind == "slots":
                out.append(f"{p}val {n}: List<SupportSlot> = listOf(\n")
                for x, z, r, mirror in e.value:
                    out.append(f"{p}    SupportSlot({double_lit(x)}, {double_lit(z)}, {role(r)}, {'true' if mirror else 'false'}),\n")
                out.append(f"{p})\n")
        for child in tree.children:
            walk(child, depth + 1, kpath)
        out.append(f"{pad}}}\n")

    for t in model.trees:
        walk(t, 1, "Tuning")
    out.append("}\n")
    return "".join(out)


def worlds(model, bits):
    s = [head("The sports (rules.toml [[sport]], spec §1) and the worlds (teams.toml [[world]], spec §13).")]
    s.append("/** The two sports one engine plays (spec §1). [FIELD] is the default. */\n")
    s.append("enum class Sport(\n    val key: String,\n    val cornerRadius: Double,\n    val ballFriction: Double,\n"
             "    val ballDrag: Double,\n    val wallRestitution: Double,\n    val ballRadius: Double,\n"
             "    /** \"ball\" or \"puck\": what the world draws. */\n    val ballKind: String,\n"
             "    /** Whether an attacker may not enter the zone before the ball (spec \u00a78.9). */\n"
             "    val offside: Boolean,\n) {\n")
    keys = ("corner_radius", "ball_friction", "ball_drag", "wall_restitution", "ball_radius")
    rows = []
    for x in model.sports:
        rows.append(f"    {x['id'].upper()}(\"{x['id']}\", " + ", ".join(double_lit(x[k]) for k in keys)
                    + f", \"{x['ball_kind']}\", {str(x['offside']).lower()})")
        for k in keys:
            bits.add(f"Sport.{x['id'].upper()}.{camel(k)}", x[k])
    s.append(",\n".join(rows) + ";\n\n" + lookup("Sport", "rules.toml") + "}\n\n")
    s.append("/** The five worlds, in the demo match's order (spec §9, §13). */\n")
    s.append("enum class World(val key: String, val sport: Sport, val nameKey: CopyKey) {\n")
    s.append(",\n".join(f"    {w['id'].upper()}(\"{w['id']}\", Sport.{w['sport'].upper()}, CopyKey.{upper_snake(w['name'])})"
                        for w in model.worlds) + ";\n\n" + lookup("World", "teams.toml") + "}\n")
    return "".join(s)


def tactics_lit(t):
    return ("Tactics(" + ", ".join(f"{camel(k)} = {double_lit(t[k])}" for k in
                                   ("pressing", "covering", "push_up", "passing", "shooting", "discipline")) + ")")


def teams(model, bits):
    s = [head("Formations, tactics, clubs and the career (teams.toml, spec §2, §3, §12).")]
    s.append("/** A team's tactics (spec §12); each in 0…1. */\n")
    s.append("data class Tactics(\n    val pressing: Double,\n    val covering: Double,\n    val pushUp: Double,\n"
             "    val passing: Double,\n    val shooting: Double,\n    val discipline: Double,\n) {\n"
             f"    companion object {{\n        /** The default tactics (spec §12). */\n"
             f"        val defaults: Tactics = {tactics_lit(model.default_tactics)}\n    }}\n}}\n\n")

    s.append("/** The coach's formations (spec §3), for a team attacking +Z. [BALANCED] is the default. */\n")
    s.append("enum class Formation(\n    val key: String,\n    /** The five outfield players in roster order (after the goalie). */\n"
             "    val players: List<LineupSpot>,\n    val nameKey: CopyKey,\n    val blurbKey: CopyKey,\n) {\n")
    rows = []
    for f in model.formations:
        ps = ",\n".join(f"            LineupSpot({role(r)}, {spot((x, z))})" for r, x, z in f["players"])
        rows.append(f"    {f['id'].upper()}(\n        \"{f['id']}\",\n        listOf(\n{ps},\n        ),\n"
                    f"        CopyKey.{upper_snake(f['name'])},\n        CopyKey.{upper_snake(f['blurb'])},\n    )")
        for i, (_, x, z) in enumerate(f["players"]):
            bits.add(f"Formation.{f['id'].upper()}.players[{i}].spot.x", x)
            bits.add(f"Formation.{f['id'].upper()}.players[{i}].spot.z", z)
    s.append(",\n".join(rows) + ";\n\n")
    s.append(f"    companion object {{\n        /** The goalie's spot in every formation. */\n"
             f"        val goalie: Spot = {spot(model.formation_goalie)}\n\n"
             f"        /** The formation declared as [key]; throws for a key teams.toml does not declare. */\n"
             f"        fun of(key: String): Formation = entries.firstOrNull {{ it.key == key }}\n"
             f"            ?: throw IllegalArgumentException(\"unknown Formation '$key' — not declared in teams.toml\")\n"
             f"    }}\n}}\n\n")

    s.append("/** The eight clubs (spec §2.1). Kit colours are sRGB 0xRRGGBB; [world] is the home world. */\n")
    s.append("enum class Club(\n    val key: String,\n    val short: String,\n    val world: World,\n    val rating: Int,\n"
             "    val primary: Int,\n    val secondary: Int,\n    val tactics: Tactics,\n    val nameKey: CopyKey,\n) {\n")
    rows = []
    for c in model.clubs:
        rows.append(f"    {c['id'].upper()}(\"{c['id']}\", \"{c['short']}\", World.{c['world'].upper()}, {c['rating']}, "
                    f"0x{c['primary']:06X}, 0x{c['secondary']:06X},\n        {tactics_lit(c['tactics'])},\n"
                    f"        CopyKey.{upper_snake(c['name'])})")
        for k, v in c["tactics"].items():
            bits.add(f"Club.{c['id'].upper()}.tactics.{camel(k)}", v)
    s.append(",\n".join(rows) + ";\n\n" + lookup("Club", "teams.toml") + "}\n\n")

    k = model.career
    s.append("/** The career's constants (spec §2.2, §9). */\nobject Career {\n")
    s.append(f"    /** The demo's team before a career exists (§9). */\n    val demoClub: Club = Club.{k['demo_club'].upper()}\n")
    s.append(f"    /** A created team's fixed rating: the clubs' mean, rounded. */\n    const val createdRating: Int = {k['created_rating']}\n")
    s.append(f"    /** The club a created team replaces in the league and cup. */\n    val createdReplaces: Club = Club.{k['created_replaces'].upper()}\n")
    s.append(f"    const val nameMinLength: Int = {k['name_min_length']}\n")
    s.append(f"    const val nameMaxLength: Int = {k['name_max_length']}\n")
    s.append(f"    const val shortCodeLength: Int = {k['short_code_length']}\n")
    s.append(f"    /** Pads a derived short code short of letters; no club's code contains it. */\n"
             f"    const val shortCodePad: String = \"{k['short_code_pad']}\"\n")
    s.append("    /** The created team's kit palette: twelve pairs (§2.2). No primary equals a club's primary. */\n")
    s.append("    val kitPalette: List<Kit> = listOf(\n")
    for kit in model.kits:
        s.append(f"        Kit(\"{kit['id']}\", 0x{kit['primary']:06X}, 0x{kit['secondary']:06X}, "
                 f"CopyKey.{upper_snake(kit['primary_name'])}, CopyKey.{upper_snake(kit['secondary_name'])}),\n")
    s.append("    )\n}\n\n")

    created = k["created_id"]
    s.append("/** A team in a season (spec §11): one of the clubs, or the created team (§2.2); [club] is null for it. */\n")
    s.append("enum class TeamKey(val key: String, val club: Club?) {\n")
    rows = [f"    {c['id'].upper()}(\"{c['id']}\", Club.{c['id'].upper()})" for c in model.clubs]
    rows.append(f"    {created.upper()}(\"{created}\", null)")
    s.append(",\n".join(rows) + ";\n\n")
    s.append("    companion object {\n"
             "        /** The entry declared as [key]; throws for a key that is neither a club's nor the created team's. */\n"
             "        fun of(key: String): TeamKey = entries.firstOrNull { it.key == key }\n"
             "            ?: throw IllegalArgumentException(\"unknown TeamKey '$key' — not declared in teams.toml\")\n\n"
             "        /** The key of [club]. */\n"
             "        fun of(club: Club): TeamKey = entries.first { it.club == club }\n"
             "    }\n}\n\n")

    s.append("/** The cup's rounds (spec §11.1). */\nenum class CupRound(val key: String) {\n")
    s.append(",\n".join(f"    {upper_snake(r)}(\"{r}\")" for r in model.cup_rounds) + ";\n\n"
             + lookup("CupRound", "rules.toml") + "}\n\n")
    s.append("/** The season's matchday plan, in order (spec §11.1). */\nobject Season {\n")
    s.append("    val plan: List<MatchdayStep> = listOf(\n")
    for kind, v in model.matchdays:
        s.append(f"        MatchdayStep.League({v}),\n" if kind == "league" else f"        MatchdayStep.Cup(CupRound.{upper_snake(v)}),\n")
    s.append("    )\n}\n")
    return "".join(s)


def drill_player(p):
    r, x, z, speed, patrol = p
    pt = "null" if patrol is None else f"Patrol({spot(patrol[:2])}, {double_lit(patrol[2])}, {double_lit(patrol[3])})"
    return f"DrillPlayer({role(r)}, {spot((x, z))}, {double_lit(speed)}, {pt})"


def drills(model, bits):
    s = [head("The training drills (drills.toml, spec §10), in unlock order.")]
    s.append("enum class Drill(\n    val key: String,\n    /** 1-based, as the player sees it. */\n    val number: Int,\n"
             "    val world: World,\n    /** Goals to reach before the clock runs out. */\n    val goals: Int,\n"
             "    val seconds: Double,\n    val rule: DrillRule,\n"
             "    /** Index in [home] of the player who starts with the ball. */\n    val ballTo: Int,\n"
             "    /** The player's side. */\n    val home: List<DrillPlayer>,\n    /** The opponents. */\n"
             "    val away: List<DrillPlayer>,\n    val nameKey: CopyKey,\n    val hintKey: CopyKey,\n) {\n")
    rows = []
    for i, d in enumerate(model.drills):
        sides = []
        for side in ("home", "away"):
            ps = d[side]
            sides.append("emptyList()" if not ps else
                         "listOf(\n" + "".join(f"            {drill_player(p)},\n" for p in ps) + "        )")
            for j, p in enumerate(ps):
                base = f"Drill.{d['id'].upper()}.{side}[{j}]"
                bits.add(base + ".spot.x", p[1])
                bits.add(base + ".spot.z", p[2])
                bits.add(base + ".speed", p[3])
                if p[4]:
                    for n, f in enumerate(("to.x", "to.z", "speed", "phase")):
                        bits.add(f"{base}.patrol!!.{f}", p[4][n])
        rows.append(f"    {d['id'].upper()}(\n        \"{d['id']}\", {i + 1}, World.{d['world'].upper()}, {d['goals']}, "
                    f"{double_lit(d['seconds'])}, DrillRule.{d['rule'].upper()}, {d['ball_to']},\n"
                    f"        {sides[0]},\n        {sides[1]},\n"
                    f"        CopyKey.{upper_snake(d['name'])},\n        CopyKey.{upper_snake(d['hint'])},\n    )")
        bits.add(f"Drill.{d['id'].upper()}.seconds", d["seconds"])
    s.append(",\n".join(rows) + ";\n\n" + lookup("Drill", "drills.toml") + "}\n")
    return "".join(s)


def math_constants(model):
    s = [head("The deterministic math's constants (math.toml, spec §4.3–§4.4), as exact bit patterns.")]
    s.append("internal object MathConstants {\n")
    for section, entries in model.math.items():
        s.append(f"    object {pascal(section)} {{\n")
        for name, kind, value in entries:
            n = camel(name)
            if kind == "u64":
                s.append(f"        const val {n}: Long = {long_lit(value)} // 0x{value:016X}\n")
            elif kind == "int":
                s.append(f"        const val {n}: Int = {value}\n")
            else:
                b = bits_of(value)
                s.append(f"        @JvmField val {n}: Double = Double.fromBits({long_lit(b)}) // 0x{b:016X} = {value!r}\n")
        s.append("    }\n")
    s.append("}\n")
    return "".join(s)


def copy_keys(model):
    s = [head("Every copy key (copy.toml and the names in teams.toml / drills.toml, spec §14). The text is in\n"
              "// android/app/src/main/res/values*/strings.xml under [resourceName]; placeholders are positional\n"
              "// string arguments in [arguments] order.")]
    s.append("enum class CopyKey(val key: String, val resourceName: String, val arguments: List<String>) {\n")
    rows = []
    for c in model.copy:
        args = "emptyList()" if not c.args else "listOf(" + ", ".join(f'"{a}"' for a in c.args) + ")"
        rows.append(f"    {upper_snake(c.key)}(\"{c.key}\", \"{c.key.replace('.', '_')}\", {args})")
    s.append(",\n".join(rows) + ";\n\n" + lookup("CopyKey", "shared/data") + "}\n")
    return "".join(s)
