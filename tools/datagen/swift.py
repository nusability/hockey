"""Emits the Swift side: ios/SmashCore/Sources/SmashCore/Generated/*.swift and the constant-bits
table for the SmashCore test target."""
from .common import HEADER, double_lit
from .model import ROLES, bits_of, camel, pascal

SRC = "ios/SmashCore/Sources/SmashCore/Generated/"
TEST = "ios/SmashCore/Tests/SmashCoreTests/Generated/"
KEYWORDS = {"final", "default", "case", "in", "is", "as", "for", "if", "else", "switch", "where", "self",
            "Self", "init", "class", "struct", "enum", "func", "let", "var", "return", "public", "static"}
ROLE_CASE = {k: v for k, v in ROLES.items()}


def ident(name):
    return f"`{name}`" if name in KEYWORDS else name


def head(doc):
    return f"// {HEADER}\n// {doc}\n\n"


def spot(s):
    return f"Spot(x: {double_lit(s[0])}, z: {double_lit(s[1])})"


def emit(model, bits):
    files = {}
    files[SRC + "Types.swift"] = types()
    files[SRC + "Tuning.swift"] = tuning(model, bits)
    files[SRC + "World.swift"] = worlds(model, bits)
    files[SRC + "Teams.swift"] = teams(model, bits)
    files[SRC + "Drills.swift"] = drills(model, bits)
    files[SRC + "MathConstants.swift"] = math_constants(model)
    files[SRC + "CopyKey.swift"] = copy_keys(model)
    return files


def bits_test(bits):
    rows = "\n".join(f'        ("{s}", {s}, 0x{b:016X}),' for s, b in bits.rows)
    return (head("Every double the generator declares, with its exact bit pattern (see ConstantBitsTests).")
            + "@testable import SmashCore\n\n"
            + "enum GeneratedConstantBits {\n"
            + "    static let all: [(name: String, value: Double, bits: UInt64)] = [\n"
            + rows + "\n    ]\n}\n")


def types():
    return head("The shapes the declarations in shared/data/ take.") + """\
/// A point on the pitch (x across, z along; spec §1).
public struct Spot: Sendable, Hashable {
    public let x: Double
    public let z: Double
    public init(x: Double, z: Double) { self.x = x; self.z = z }
}

/// A lineup role (spec §3): goalie, defender, forward, or a drill's dummy.
public enum Role: String, Sendable, CaseIterable {
    case goalie = "G", defender = "D", forward = "F", dummy = "O"
}

/// A formation's outfield player: role and home spot for a team attacking +Z (spec §3).
public struct LineupSpot: Sendable, Hashable {
    public let role: Role
    public let spot: Spot
}

/// A support slot relative to the ball (spec §7.4).
public struct SupportSlot: Sendable, Hashable {
    public let x: Double
    public let z: Double
    public let role: Role
    public let mirror: Bool
}

/// A team's tactics (spec §12); each in 0…1.
public struct Tactics: Sendable, Hashable {
    public var pressing: Double
    public var covering: Double
    public var pushUp: Double
    public var passing: Double
    public var shooting: Double
    public var discipline: Double
    public init(pressing: Double, covering: Double, pushUp: Double, passing: Double, shooting: Double, discipline: Double) {
        self.pressing = pressing; self.covering = covering; self.pushUp = pushUp
        self.passing = passing; self.shooting = shooting; self.discipline = discipline
    }
}

/// A patrolling dummy's second point, speed and phase (spec §10).
public struct Patrol: Sendable, Hashable {
    public let to: Spot
    public let speed: Double
    public let phase: Double
}

/// A drill's player (spec §10). `patrol` is nil for everyone but a patrolling dummy.
public struct DrillPlayer: Sendable, Hashable {
    public let role: Role
    public let spot: Spot
    public let speed: Double
    public let patrol: Patrol?
}

/// A drill's special rule (spec §10).
public enum DrillRule: String, Sendable, CaseIterable {
    case none, assist, freePlay = "free_play"
}

/// A pair of the created team's kit palette (spec §2.2). Colours are sRGB 0xRRGGBB; the names are
/// the swatches' accessibility labels.
public struct Kit: Sendable, Hashable {
    public let id: String
    public let primary: UInt32
    public let secondary: UInt32
    public let primaryName: CopyKey
    public let secondaryName: CopyKey
}

/// A step of the season's matchday plan (spec §11.1).
public enum MatchdayStep: Sendable, Hashable {
    case league(round: Int)
    case cup(CupRound)
}
"""


def tuning(model, bits):
    out = [head("The simulation's numbers (rules.toml), the coach's board (teams.toml [board]) and the motion tokens (motion.json)."),
           "public enum Tuning {\n"]

    def walk(tree, depth, path):
        pad = "    " * depth
        name = pascal(tree.name) if tree.name != "ai" else "AI"
        out.append(f"{pad}public enum {name} {{\n")
        spath = f"{path}.{name}"
        for e in tree.entries:
            p, n = pad + "    ", camel(e.name)
            if e.doc:
                out.append(f"{p}/// {e.doc}\n")
            full = f"{spath}.{n}"
            if e.kind == "int":
                out.append(f"{p}public static let {n}: Int = {e.value}\n")
            elif e.kind == "double":
                out.append(f"{p}public static let {n}: Double = {double_lit(e.value)}\n")
                bits.add(full, e.value)
            elif e.kind == "bool":
                out.append(f"{p}public static let {n}: Bool = {'true' if e.value else 'false'}\n")
            elif e.kind == "string":
                out.append(f'{p}public static let {n}: String = "{e.value}"\n')
            elif e.kind == "doubles":
                out.append(f"{p}public static let {n}: [Double] = [{', '.join(double_lit(v) for v in e.value)}]\n")
                for i, v in enumerate(e.value):
                    bits.add(f"{full}[{i}]", v)
            elif e.kind == "spot":
                out.append(f"{p}public static let {n}: Spot = {spot(e.value)}\n")
            elif e.kind == "spots":
                out.append(f"{p}public static let {n}: [Spot] = [\n")
                out.extend([f"{p}    {spot(s)},\n" for s in e.value])
                out.append(f"{p}]\n")
            elif e.kind == "slots":
                out.append(f"{p}public static let {n}: [SupportSlot] = [\n")
                for x, z, role, mirror in e.value:
                    out.append(f"{p}    SupportSlot(x: {double_lit(x)}, z: {double_lit(z)}, role: .{ROLE_CASE[role]}, "
                               f"mirror: {'true' if mirror else 'false'}),\n")
                out.append(f"{p}]\n")
        for child in tree.children:
            walk(child, depth + 1, spath)
        out.append(f"{pad}}}\n")

    for t in model.trees:
        walk(t, 1, "Tuning")
    out.append("}\n")
    return "".join(out)


def switch(prop, typ, cases, doc=None):
    lines = [f"    /// {doc}\n"] if doc else []
    lines.append(f"    public var {prop}: {typ} {{\n        switch self {{\n")
    lines += [f"        case .{ident(c)}: {v}\n" for c, v in cases]
    lines.append("        }\n    }\n")
    return "".join(lines)


def worlds(model, bits):
    s = [head("The sports (rules.toml [[sport]], spec §1) and the worlds (teams.toml [[world]], spec §13).")]
    s.append("/// The two sports one engine plays (spec §1). `field` is the default.\n")
    s.append("public enum Sport: String, Sendable, CaseIterable {\n")
    s.append("".join(f"    case {ident(x['id'])}\n" for x in model.sports))
    for key, typ in (("corner_radius", "Double"), ("ball_friction", "Double"), ("ball_drag", "Double"),
                     ("wall_restitution", "Double"), ("ball_radius", "Double")):
        s.append(switch(camel(key), typ, [(x["id"], double_lit(x[key])) for x in model.sports]))
        for x in model.sports:
            bits.add(f"Sport.{x['id']}.{camel(key)}", x[key])
    s.append(switch("ballKind", "String", [(x["id"], f'"{x["ball_kind"]}"') for x in model.sports],
                    "\"ball\" or \"puck\": what the world draws."))
    s.append("}\n\n/// The five worlds, in the demo match's order (spec §9, §13).\n")
    s.append("public enum World: String, Sendable, CaseIterable {\n")
    s.append("".join(f"    case {ident(w['id'])}\n" for w in model.worlds))
    s.append(switch("sport", "Sport", [(w["id"], f".{w['sport']}") for w in model.worlds]))
    s.append(switch("nameKey", "CopyKey", [(w["id"], f".{camel(w['name'])}") for w in model.worlds]))
    s.append("}\n")
    return "".join(s)


def tactics_lit(t):
    return ("Tactics(" + ", ".join(f"{camel(k)}: {double_lit(t[k])}" for k in
                                   ("pressing", "covering", "push_up", "passing", "shooting", "discipline")) + ")")


def teams(model, bits):
    s = [head("Formations, tactics, clubs and the career (teams.toml, spec §2, §3, §12).")]
    s.append("/// The coach's formations (spec §3), for a team attacking +Z. `balanced` is the default.\n")
    s.append("public enum Formation: String, Sendable, CaseIterable {\n")
    s.append("".join(f"    case {ident(f['id'])}\n" for f in model.formations))
    s.append(f"\n    /// The goalie's spot in every formation.\n    public static let goalie: Spot = {spot(model.formation_goalie)}\n")
    s.append(switch("players", "[LineupSpot]", [(f["id"], f"FormationStorage.{ident(f['id'])}") for f in model.formations],
                    "The five outfield players in roster order (after the goalie)."))
    s.append(switch("nameKey", "CopyKey", [(f["id"], f".{camel(f['name'])}") for f in model.formations]))
    s.append(switch("blurbKey", "CopyKey", [(f["id"], f".{camel(f['blurb'])}") for f in model.formations]))
    s.append("}\n\nprivate enum FormationStorage {\n")
    for f in model.formations:
        s.append(f"    static let {ident(f['id'])}: [LineupSpot] = [\n")
        for i, (role, x, z) in enumerate(f["players"]):
            s.append(f"        LineupSpot(role: .{ROLES[role]}, spot: {spot((x, z))}),\n")
            bits.add(f"Formation.{f['id']}.players[{i}].spot.x", x)
            bits.add(f"Formation.{f['id']}.players[{i}].spot.z", z)
        s.append("    ]\n")
    s.append("}\n\nextension Tactics {\n    /// The default tactics (spec §12).\n")
    s.append(f"    public static let defaults = {tactics_lit(model.default_tactics)}\n}}\n\n")

    s.append("/// The eight clubs (spec §2.1).\npublic enum Club: String, Sendable, CaseIterable {\n")
    s.append("".join(f"    case {ident(c['id'])}\n" for c in model.clubs))
    s.append(switch("short", "String", [(c["id"], f'"{c["short"]}"') for c in model.clubs]))
    s.append(switch("world", "World", [(c["id"], f".{c['world']}") for c in model.clubs], "The home world."))
    s.append(switch("rating", "Int", [(c["id"], str(c["rating"])) for c in model.clubs]))
    s.append(switch("primary", "UInt32", [(c["id"], f"0x{c['primary']:06X}") for c in model.clubs], "Kit colour, sRGB 0xRRGGBB."))
    s.append(switch("secondary", "UInt32", [(c["id"], f"0x{c['secondary']:06X}") for c in model.clubs]))
    s.append(switch("tactics", "Tactics", [(c["id"], tactics_lit(c["tactics"])) for c in model.clubs]))
    s.append(switch("nameKey", "CopyKey", [(c["id"], f".{camel(c['name'])}") for c in model.clubs]))
    s.append("}\n\n")
    for c in model.clubs:
        for k, v in c["tactics"].items():
            bits.add(f"Club.{c['id']}.tactics.{camel(k)}", v)

    k = model.career
    s.append("/// The career's constants (spec §2.2, §9).\npublic enum Career {\n")
    s.append(f"    /// The demo's team before a career exists (§9).\n    public static let demoClub: Club = .{k['demo_club']}\n")
    s.append(f"    /// A created team's fixed rating: the clubs' mean, rounded.\n    public static let createdRating: Int = {k['created_rating']}\n")
    s.append(f"    /// The club a created team replaces in the league and cup.\n    public static let createdReplaces: Club = .{k['created_replaces']}\n")
    s.append(f"    public static let nameMinLength: Int = {k['name_min_length']}\n")
    s.append(f"    public static let nameMaxLength: Int = {k['name_max_length']}\n")
    s.append(f"    public static let shortCodeLength: Int = {k['short_code_length']}\n")
    s.append(f"    /// Pads a derived short code short of letters; no club's code contains it.\n"
             f"    public static let shortCodePad: String = \"{k['short_code_pad']}\"\n")
    s.append("    /// The created team's kit palette: twelve pairs (§2.2). No primary equals a club's primary.\n")
    s.append("    public static let kitPalette: [Kit] = [\n")
    for kit in model.kits:
        s.append(f"        Kit(id: \"{kit['id']}\", primary: 0x{kit['primary']:06X}, secondary: 0x{kit['secondary']:06X}, "
                 f"primaryName: .{camel(kit['primary_name'])}, secondaryName: .{camel(kit['secondary_name'])}),\n")
    s.append("    ]\n}\n\n")

    s.append("/// A team in a season (spec §11): one of the clubs, or the created team (§2.2).\n")
    s.append("public enum TeamKey: String, Sendable, CaseIterable {\n")
    s.append("".join(f"    case {ident(c['id'])}\n" for c in model.clubs))
    s.append(f"    case {ident(k['created_id'])}\n\n    /// The club, or nil for the created team.\n")
    s.append("    public var club: Club? {\n        switch self {\n")
    s.append("".join(f"        case .{ident(c['id'])}: .{ident(c['id'])}\n" for c in model.clubs))
    s.append(f"        case .{ident(k['created_id'])}: nil\n        }}\n    }}\n\n")
    s.append("    public init(_ club: Club) {\n        switch club {\n")
    s.append("".join(f"        case .{ident(c['id'])}: self = .{ident(c['id'])}\n" for c in model.clubs))
    s.append("        }\n    }\n}\n\n")

    s.append("/// The cup's rounds (spec §11.1).\npublic enum CupRound: String, Sendable, CaseIterable {\n")
    s.append("".join(f"    case {ident(r)}\n" for r in model.cup_rounds))
    s.append("}\n\n/// The season's matchday plan, in order (spec §11.1).\npublic enum Season {\n")
    s.append("    public static let plan: [MatchdayStep] = [\n")
    for kind, v in model.matchdays:
        s.append(f"        .league(round: {v}),\n" if kind == "league" else f"        .cup(.{ident(v)}),\n")
    s.append("    ]\n}\n")
    return "".join(s)


def drill_player(p):
    role, x, z, speed, patrol = p
    pt = "nil" if patrol is None else (f"Patrol(to: {spot(patrol[:2])}, speed: {double_lit(patrol[2])}, "
                                       f"phase: {double_lit(patrol[3])})")
    return f"DrillPlayer(role: .{ROLES[role]}, spot: {spot((x, z))}, speed: {double_lit(speed)}, patrol: {pt})"


def drills(model, bits):
    s = [head("The training drills (drills.toml, spec §10), in unlock order.")]
    s.append("public enum Drill: String, Sendable, CaseIterable {\n")
    s.append("".join(f"    case {ident(d['id'])}\n" for d in model.drills))
    ds = model.drills
    s.append(switch("number", "Int", [(d["id"], str(i + 1)) for i, d in enumerate(ds)], "1-based, as the player sees it."))
    s.append(switch("world", "World", [(d["id"], f".{d['world']}") for d in ds]))
    s.append(switch("goals", "Int", [(d["id"], str(d["goals"])) for d in ds], "Goals to reach before the clock runs out."))
    s.append(switch("seconds", "Double", [(d["id"], double_lit(d["seconds"])) for d in ds]))
    s.append(switch("rule", "DrillRule", [(d["id"], f".{camel(d['rule'])}") for d in ds]))
    s.append(switch("ballTo", "Int", [(d["id"], str(d["ball_to"])) for d in ds], "Index in `home` of the player who starts with the ball."))
    s.append(switch("home", "[DrillPlayer]", [(d["id"], f"DrillStorage.{ident(d['id'])}Home") for d in ds], "The player's side."))
    s.append(switch("away", "[DrillPlayer]", [(d["id"], f"DrillStorage.{ident(d['id'])}Away") for d in ds], "The opponents."))
    s.append(switch("nameKey", "CopyKey", [(d["id"], f".{camel(d['name'])}") for d in ds]))
    s.append(switch("hintKey", "CopyKey", [(d["id"], f".{camel(d['hint'])}") for d in ds]))
    s.append("}\n\nprivate enum DrillStorage {\n")
    for d in ds:
        for side in ("home", "away"):
            players = d[side]
            s.append(f"    static let {d['id']}{side.capitalize()}: [DrillPlayer] = [\n" if players
                     else f"    static let {d['id']}{side.capitalize()}: [DrillPlayer] = []\n")
            for i, p in enumerate(players):
                s.append(f"        {drill_player(p)},\n")
                base = f"Drill.{ident(d['id'])}.{side}[{i}]"
                bits.add(base + ".spot.x", p[1])
                bits.add(base + ".spot.z", p[2])
                bits.add(base + ".speed", p[3])
                if p[4]:
                    for j, f in enumerate(("to.x", "to.z", "speed", "phase")):
                        bits.add(f"{base}.patrol!.{f}", p[4][j])
            if players:
                s.append("    ]\n")
    s.append("}\n")
    for d in ds:
        bits.add(f"Drill.{ident(d['id'])}.seconds", d["seconds"])
    return "".join(s)


def math_constants(model):
    s = [head("The deterministic math's constants (math.toml, spec §4.3–§4.4), as exact bit patterns.")]
    s.append("enum MathConstants {\n")
    for section, entries in model.math.items():
        s.append(f"    enum {pascal(section)} {{\n")
        for name, kind, value in entries:
            n = camel(name)
            if kind == "u64":
                s.append(f"        static let {n}: UInt64 = 0x{value:016X}\n")
            elif kind == "int":
                s.append(f"        static let {n}: Int = {value}\n")
            else:
                s.append(f"        static let {n}: Double = Double(bitPattern: 0x{bits_of(value):016X})  // {value!r}\n")
        s.append("    }\n")
    s.append("}\n")
    return "".join(s)


def copy_keys(model):
    s = [head("Every copy key (copy.toml and the names in teams.toml / drills.toml, spec §14). The text is in "
              "ios/Sources/Localizable.xcstrings;\n// placeholders are positional string arguments in `arguments` order.")]
    s.append("public enum CopyKey: String, Sendable, CaseIterable {\n")
    s.append("".join(f'    case {ident(camel(c.key))} = "{c.key}"\n' for c in model.copy))
    s.append("\n    /// The placeholder names, in argument order.\n    public var arguments: [String] {\n        switch self {\n")
    with_args = [c for c in model.copy if c.args]
    for c in with_args:
        s.append(f"        case .{ident(camel(c.key))}: [{', '.join(f'\"{a}\"' for a in c.args)}]\n")
    s.append("        default: []\n        }\n    }\n}\n")
    return "".join(s)
