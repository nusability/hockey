"""Loads shared/data/ and validates it into one platform-neutral model.

Everything here fails loud: a missing or malformed value stops the generator with a message that
names the file and the key, never a default (conventions.md, Configuration).
"""
import json
import re
import struct
import tomllib
from dataclasses import dataclass, field
from pathlib import Path

ROLES = {"G": "goalie", "D": "defender", "F": "forward", "O": "dummy"}
LANGS = ("en", "de")


class DataError(Exception):
    pass


def fail(where, msg):
    raise DataError(f"{where}: {msg}")


def camel(snake):
    parts = re.split(r"[_.]", snake)
    return parts[0] + "".join(p[:1].upper() + p[1:] for p in parts[1:])


def pascal(snake):
    c = camel(snake)
    return c[:1].upper() + c[1:]


def upper_snake(name):
    """camelCase / dotted / snake → UPPER_SNAKE (Kotlin enum entries)."""
    s = re.sub(r"[.\-]", "_", name)
    s = re.sub(r"([a-z0-9])([A-Z])", r"\1_\2", s)
    return s.upper()


def bits_of(value):
    return struct.unpack(">Q", struct.pack(">d", float(value)))[0]


def double_of_hex(text, where):
    if not isinstance(text, str) or not re.fullmatch(r"0x[0-9A-Fa-f]{16}", text):
        fail(where, f"expected a 64-bit hex bit pattern like 0x3FF0000000000000, got {text!r}")
    return struct.unpack(">d", bytes.fromhex(text[2:]))[0]


# --- scalar trees -------------------------------------------------------------------------------
# A scalar tree is a nested table of plain values, emitted as nested namespaces of constants.
# Entry kinds: int, double, string, bool, doubles, spot, spots, slots.

@dataclass
class Entry:
    name: str          # snake_case, as declared
    kind: str
    value: object
    doc: str = ""


@dataclass
class Tree:
    name: str          # snake_case table name
    entries: list = field(default_factory=list)
    children: list = field(default_factory=list)


def spot(value, where):
    if not isinstance(value, dict) or set(value) != {"x", "z"}:
        fail(where, f"expected a spot {{ x = …, z = … }}, got {value!r}")
    return (need_float(value["x"], where + ".x"), need_float(value["z"], where + ".z"))


def need_float(value, where):
    if isinstance(value, bool) or not isinstance(value, float):
        fail(where, f"expected a float (write 3.0, not 3), got {value!r}")
    return value


def need_int(value, where):
    if isinstance(value, bool) or not isinstance(value, int):
        fail(where, f"expected an integer, got {value!r}")
    return value


def need_str(value, where):
    if not isinstance(value, str) or not value:
        fail(where, f"expected a non-empty string, got {value!r}")
    return value


def classify(name, value, where):
    if isinstance(value, bool):
        return Entry(name, "bool", value)
    if isinstance(value, int):
        return Entry(name, "int", value)
    if isinstance(value, float):
        return Entry(name, "double", value)
    if isinstance(value, str):
        return Entry(name, "string", value)
    if isinstance(value, dict) and set(value) == {"x", "z"}:
        return Entry(name, "spot", spot(value, where))
    if isinstance(value, list) and value:
        if all(isinstance(v, float) for v in value):
            return Entry(name, "doubles", list(value))
        if all(isinstance(v, dict) and set(v) == {"x", "z"} for v in value):
            return Entry(name, "spots", [spot(v, f"{where}[{i}]") for i, v in enumerate(value)])
        if all(isinstance(v, dict) and set(v) == {"x", "z", "role", "mirror"} for v in value):
            slots = []
            for i, v in enumerate(value):
                w = f"{where}[{i}]"
                if v["role"] not in ("D", "F"):
                    fail(w, f"a support slot's role is D or F, got {v['role']!r}")
                if not isinstance(v["mirror"], bool):
                    fail(w, "mirror must be true or false")
                slots.append((need_float(v["x"], w), need_float(v["z"], w), v["role"], v["mirror"]))
            return Entry(name, "slots", slots)
    fail(where, f"unsupported value {value!r} (use a number, string, bool, spot, or a list of floats/spots)")


def tree_of(name, table, where, skip=()):
    t = Tree(name)
    for key, value in table.items():
        if key in skip or key.startswith("_"):
            continue
        w = f"{where}.{key}"
        if isinstance(value, dict) and set(value) != {"x", "z"}:
            t.children.append(tree_of(key, value, w))
        else:
            t.entries.append(classify(key, value, w))
    return t


# --- structured data ----------------------------------------------------------------------------

@dataclass
class CopyEntry:
    key: str
    en: str
    de: str
    comment: str = ""
    args: list = field(default_factory=list)


PLACEHOLDER = re.compile(r"\{([A-Za-z][A-Za-z0-9]*)\}")


def copy_entry(key, table, where):
    if not re.fullmatch(r"[a-z][A-Za-z0-9]*(\.[A-Za-z0-9]+)+", key):
        fail(where, f"copy key {key!r} must be dotted lowerCamel segments, e.g. menu.newSeason")
    if not isinstance(table, dict):
        fail(where, "expected { en = …, de = … }")
    extra = set(table) - {"en", "de", "comment"}
    if extra:
        fail(where, f"unknown fields {sorted(extra)}")
    texts = {}
    for lang in LANGS:
        if lang not in table:
            fail(where, f"missing the {lang!r} text — every string exists in English and German (§14)")
        text = need_str(table[lang], f"{where}.{lang}")
        if "%" in text or "<" in text:
            fail(where, f"{lang!r} text contains % or < — plain text only, placeholders as {{name}}")
        texts[lang] = text
    args = []
    for m in PLACEHOLDER.finditer(texts["en"]):
        if m.group(1) not in args:
            args.append(m.group(1))
    de_args = {m.group(1) for m in PLACEHOLDER.finditer(texts["de"])}
    if de_args != set(args):
        fail(where, f"placeholders differ between en {sorted(args)} and de {sorted(de_args)}")
    return CopyEntry(key, texts["en"], texts["de"], table.get("comment", ""), args)


def localized(entity, kind, ident, field_name, where, copy):
    key = f"{kind}.{ident}.{field_name}"
    copy.append(copy_entry(key, entity.get(field_name), f"{where}.{field_name}"))
    return key


def kit_name(kit, ident, which, where, copy):
    """A palette colour's accessibility label: copy key kit.<id>.<primary|secondary>."""
    key = f"kit.{ident}.{which}"
    copy.append(copy_entry(key, kit.get(f"{which}_name"), f"{where}.{which}_name"))
    return key


@dataclass
class Model:
    trees: list            # scalar trees → Tuning
    sports: list
    worlds: list
    formation_goalie: tuple
    formations: list
    default_tactics: dict
    clubs: list
    career: dict
    kits: list             # the created team's palette (§2.2)
    drills: list
    matchdays: list        # ("league", round) | ("cup", stage)
    cup_rounds: list
    math: dict
    copy: list


TACTICS = ("pressing", "covering", "push_up", "passing", "shooting", "discipline")


def load(root: Path) -> Model:
    data = root / "shared" / "data"

    def read(name):
        path = data / name
        if not path.exists():
            raise DataError(f"{path} is missing")
        with open(path, "rb") as f:
            return tomllib.load(f)

    rules, teams, drills_toml, math, copy_toml = (read(n) for n in
                                                 ("rules.toml", "teams.toml", "drills.toml", "math.toml", "copy.toml"))
    with open(data / "motion.json", encoding="utf-8") as f:
        motion = json.load(f)

    copy = [copy_entry(k, v, f"copy.toml [copy] {k!r}") for k, v in need_table(copy_toml, "copy", "copy.toml").items()]

    # Sports and worlds.
    sports = []
    for i, s in enumerate(need_list(rules, "sport", "rules.toml")):
        w = f"rules.toml [[sport]] #{i + 1}"
        expect_keys(s, {"id", "corner_radius", "ball_friction", "ball_drag", "wall_restitution", "ball_radius", "ball_kind"}, w)
        sports.append({"id": need_str(s["id"], w), "ball_kind": need_str(s["ball_kind"], w),
                       **{k: need_float(s[k], f"{w}.{k}") for k in s if k not in ("id", "ball_kind")}})
    sport_ids = [s["id"] for s in sports]
    worlds = []
    for i, wd in enumerate(need_list(teams, "world", "teams.toml")):
        w = f"teams.toml [[world]] #{i + 1}"
        expect_keys(wd, {"id", "sport", "name", "look"}, w)
        ident = need_str(wd["id"], w)
        if wd["sport"] not in sport_ids:
            fail(w, f"sport {wd['sport']!r} is not one of {sport_ids}")
        worlds.append({"id": ident, "sport": wd["sport"], "name": localized(wd, "world", ident, "name", w, copy),
                       "look": world_look(wd["look"], f"{w}.look")})
    world_ids = [x["id"] for x in worlds]

    # Formations.
    goalie = spot(need_table(teams, "formation_goalie", "teams.toml"), "teams.toml [formation_goalie]")
    formations = []
    for i, fm in enumerate(need_list(teams, "formation", "teams.toml")):
        w = f"teams.toml [[formation]] #{i + 1}"
        expect_keys(fm, {"id", "name", "blurb", "players"}, w)
        ident = need_str(fm["id"], w)
        players = [lineup(p, f"{w}.players[{j}]", ("D", "F")) for j, p in enumerate(fm["players"])]
        if len(players) != need_int(rules["pitch"]["players_per_side"], "rules.toml pitch.players_per_side") - 1:
            fail(w, "a formation lists the five outfield players (the goalie is formation_goalie)")
        formations.append({"id": ident, "players": players,
                           "name": localized(fm, "formation", ident, "name", w, copy),
                           "blurb": localized(fm, "formation", ident, "blurb", w, copy)})

    # Tactics and clubs.
    dt = need_table(teams, "default_tactics", "teams.toml")
    expect_keys(dt, set(TACTICS), "teams.toml [default_tactics]")
    default_tactics = {k: need_float(dt[k], f"teams.toml default_tactics.{k}") for k in TACTICS}
    clubs = []
    for i, c in enumerate(need_list(teams, "club", "teams.toml")):
        w = f"teams.toml [[club]] #{i + 1}"
        expect_keys(c, {"id", "short", "world", "rating", "primary", "secondary", "tactics", "name"}, w)
        ident = need_str(c["id"], w)
        if not re.fullmatch(r"[A-Z]{3}", c["short"]):
            fail(w, f"short code {c['short']!r} must be three capital letters")
        if c["world"] not in world_ids:
            fail(w, f"world {c['world']!r} is not one of {world_ids}")
        unknown = set(c["tactics"]) - set(TACTICS)
        if unknown:
            fail(w, f"unknown tactics {sorted(unknown)}")
        tactics = dict(default_tactics)
        tactics.update({k: need_float(v, f"{w}.tactics.{k}") for k, v in c["tactics"].items()})
        clubs.append({"id": ident, "short": c["short"], "world": c["world"], "rating": need_int(c["rating"], w),
                      "primary": colour(c["primary"], w), "secondary": colour(c["secondary"], w),
                      "tactics": tactics, "name": localized(c, "club", ident, "name", w, copy)})
    shorts = [c["short"] for c in clubs]
    if len(set(shorts)) != len(shorts):
        fail("teams.toml [[club]]", "short codes must be unique")
    club_ids = [c["id"] for c in clubs]

    career = need_table(teams, "career", "teams.toml")
    expect_keys(career, {"demo_club", "created_rating", "created_replaces", "created_id", "name_min_length",
                         "name_max_length", "short_code_length", "short_code_pad"}, "teams.toml [career]")
    for k in ("demo_club", "created_replaces"):
        if career[k] not in club_ids:
            fail(f"teams.toml career.{k}", f"{career[k]!r} is not a club")
    if not re.fullmatch(r"[a-z]+", need_str(career["created_id"], "teams.toml career.created_id")) or career["created_id"] in club_ids:
        fail("teams.toml career.created_id", f"{career['created_id']!r} must be a lowercase key no club has")
    if not re.fullmatch(r"[A-Z]", need_str(career["short_code_pad"], "teams.toml career.short_code_pad")) \
            or any(career["short_code_pad"] in s for s in shorts):
        fail("teams.toml career.short_code_pad", "must be one capital letter that no club's short code contains (§2.2)")
    if career["short_code_length"] != 3:
        fail("teams.toml career.short_code_length", "the spec's short code is 3 letters (§2.2)")

    # §2.2 — the created team's kit palette.
    kits = []
    for i, k in enumerate(need_list(teams, "kit", "teams.toml")):
        w = f"teams.toml [[kit]] #{i + 1}"
        expect_keys(k, {"id", "primary", "secondary", "primary_name", "secondary_name"}, w)
        ident = need_str(k["id"], w)
        kits.append({"id": ident, "primary": colour(k["primary"], w), "secondary": colour(k["secondary"], w),
                     "primary_name": kit_name(k, ident, "primary", w, copy),
                     "secondary_name": kit_name(k, ident, "secondary", w, copy)})
    if len(kits) != 12:
        fail("teams.toml [[kit]]", f"the palette is twelve pairs, got {len(kits)}")
    club_primaries = {c["primary"] for c in clubs}
    for k in kits:
        if k["primary"] in club_primaries:
            fail(f"teams.toml [[kit]] {k['id']!r}", "its primary equals a club's primary (§2.2)")
    colours = [k["primary"] for k in kits] + [k["secondary"] for k in kits]
    if len(set(colours)) != len(colours):
        fail("teams.toml [[kit]]", "every palette colour must be unique")
    if len({k["id"] for k in kits}) != len(kits):
        fail("teams.toml [[kit]]", "kit ids must be unique")
    mean = sum(c["rating"] for c in clubs) / len(clubs)
    if career["created_rating"] != int(mean + 0.5):
        fail("teams.toml career.created_rating", f"must be the clubs' mean rating rounded ({mean} → {int(mean + 0.5)}, §2.2)")
    weakest = min(clubs, key=lambda c: c["rating"])["id"]
    if career["created_replaces"] != weakest:
        fail("teams.toml career.created_replaces", f"must be the weakest club, {weakest!r} (§2.2)")

    # Drills.
    drills = []
    for i, d in enumerate(need_list(drills_toml, "drill", "drills.toml")):
        w = f"drills.toml [[drill]] #{i + 1}"
        expect_keys(d, {"id", "world", "goals", "seconds", "rule", "ball_to", "home", "away", "name", "hint"}, w)
        ident = need_str(d["id"], w)
        if d["world"] not in world_ids:
            fail(w, f"world {d['world']!r} is not one of {world_ids}")
        if d["rule"] not in ("none", "assist", "free_play"):
            fail(w, f"rule {d['rule']!r} is not none, assist or free_play")
        home = [drill_player(p, f"{w}.home[{j}]") for j, p in enumerate(d["home"])]
        away = [drill_player(p, f"{w}.away[{j}]") for j, p in enumerate(d["away"])]
        if not 0 <= need_int(d["ball_to"], w) < len(home):
            fail(w, f"ball_to {d['ball_to']} is not an index into home")
        drills.append({"id": ident, "world": d["world"], "goals": need_int(d["goals"], w),
                       "seconds": need_float(d["seconds"], w), "rule": d["rule"], "ball_to": d["ball_to"],
                       "home": home, "away": away,
                       "name": localized(d, "drill", ident, "name", w, copy),
                       "hint": localized(d, "drill", ident, "hint", w, copy)})

    # The matchday plan.
    matchdays, cup_rounds = [], []
    for i, b in enumerate(need_list(rules, "matchday_block", "rules.toml")):
        w = f"rules.toml [[matchday_block]] #{i + 1}"
        if set(b) == {"league"}:
            first, last = b["league"]
            matchdays += [("league", r) for r in range(need_int(first, w), need_int(last, w) + 1)]
        elif set(b) == {"cup"}:
            matchdays.append(("cup", need_str(b["cup"], w)))
            cup_rounds.append(b["cup"])
        else:
            fail(w, "a block is either league = [first, last] or cup = \"round\"")
    league = [r for kind, r in matchdays if kind == "league"]
    if league != list(range(1, rules["season"]["league_rounds"] + 1)):
        fail("rules.toml [[matchday_block]]", "the league blocks must cover every round once, in order")

    # Scalar trees → Tuning.
    trees = [tree_of(k, v, f"rules.toml [{k}]") for k, v in rules.items() if isinstance(v, dict)]
    trees.append(tree_of("board", need_table(teams, "board", "teams.toml"), "teams.toml [board]"))
    board = trees[-1]
    for e in board.entries:
        if e.name.endswith("_default"):
            choices = next(x for x in board.entries if x.name == e.name[: -len("_default")])
            if e.value not in choices.value:
                fail(f"teams.toml board.{e.name}", f"{e.value} is not one of the choices")
    trees.append(tree_of("motion", motion, "motion.json"))
    time = next(t for t in trees if t.name == "time")
    sps = next(e.value for e in time.entries if e.name == "steps_per_second")
    spt = next(e.value for e in time.entries if e.name == "steps_per_tick")
    time.entries.append(Entry("step_seconds", "double", 1.0 / sps, "1 / steps_per_second"))
    time.entries.append(Entry("tick_seconds", "double", spt / sps, "steps_per_tick / steps_per_second"))

    return Model(trees, sports, worlds, goalie, formations, default_tactics, clubs,
                 {k: career[k] for k in career}, kits, drills, matchdays, cup_rounds,
                 load_math(math), copy_unique(copy))


def load_math(math):
    out = {}
    for section, table in math.items():
        entries = []
        for key, value in table.items():
            w = f"math.toml [{section}].{key}"
            if section == "splitmix" and key in ("gamma", "mix1", "mix2"):
                entries.append((key, "u64", int(value, 16)))
            elif isinstance(value, int):
                entries.append((key, "int", value))
            elif isinstance(value, list):
                base = 0 if section == "atan" else 1
                for j, v in enumerate(value):
                    entries.append((f"{key}{j + base}", "double", double_of_hex(v, f"{w}[{j}]")))
            else:
                entries.append((key, "double", double_of_hex(value, w)))
        out[section] = entries
    return out


def copy_unique(copy):
    seen = set()
    for c in copy:
        if c.key in seen:
            fail("copy", f"key {c.key!r} is declared twice")
        seen.add(c.key)
    return copy


def need_table(doc, key, where):
    v = doc.get(key)
    if not isinstance(v, dict):
        fail(where, f"missing table [{key}]")
    return v


def need_list(doc, key, where):
    v = doc.get(key)
    if not isinstance(v, list) or not v:
        fail(where, f"missing [[{key}]] entries")
    return v


def expect_keys(table, keys, where):
    missing, extra = keys - set(table), set(table) - keys
    if missing:
        fail(where, f"missing {sorted(missing)}")
    if extra:
        fail(where, f"unknown {sorted(extra)}")


def colour(text, where):
    if not isinstance(text, str) or not re.fullmatch(r"#[0-9a-fA-F]{6}", text):
        fail(where, f"colour {text!r} must be #rrggbb")
    return int(text[1:], 16)


LOOK_COLOURS = ("hemi_sky", "hemi_ground", "sun")
LOOK_NUMBERS = ("hemi_strength", "sun_strength", "shade")


def world_look(look, where):
    """A world's light (§13, ADR 0006): the hemisphere's sky and ground colours and its strength, the
    sun's colour, strength and direction, and `shade` — how much of the sun a face turned away from
    it keeps, the toon band's dark side. Presentation only, generated into the apps."""
    if not isinstance(look, dict):
        fail(where, "expected a [world.look] table")
    expect_keys(look, set(LOOK_COLOURS + LOOK_NUMBERS + ("sun_direction",)), where)
    out = {k: colour(look[k], f"{where}.{k}") for k in LOOK_COLOURS}
    out.update({k: need_float(look[k], f"{where}.{k}") for k in LOOK_NUMBERS})
    for k in LOOK_NUMBERS:
        if out[k] < 0.0:
            fail(f"{where}.{k}", "a light's strength is not negative")
    # The toon band's dark side is a share of the sun, so it lives in 0…1 (ADR 0006).
    if out["shade"] > 1.0:
        fail(f"{where}.shade", "the shaded side keeps at most all of the sun (0…1)")
    d = look["sun_direction"]
    if not isinstance(d, list) or len(d) != 3:
        fail(f"{where}.sun_direction", "expected [x, y, z] toward the sun")
    d = [need_float(v, f"{where}.sun_direction") for v in d]
    if d[1] <= 0.0:
        fail(f"{where}.sun_direction", "the sun is above the horizon (y > 0)")
    out["sun_direction"] = d
    return out


def lineup(p, where, roles):
    expect_keys(p, {"role", "x", "z"}, where)
    if p["role"] not in roles:
        fail(where, f"role {p['role']!r} is not one of {roles}")
    return (p["role"], need_float(p["x"], where), need_float(p["z"], where))


def drill_player(p, where):
    allowed = {"role", "x", "z", "speed", "patrol"}
    if set(p) - allowed or not {"role", "x", "z"} <= set(p):
        fail(where, f"a drill player has role, x, z and optionally speed, patrol — got {sorted(p)}")
    if p["role"] not in ROLES:
        fail(where, f"role {p['role']!r} is not one of {sorted(ROLES)}")
    patrol = None
    if "patrol" in p:
        if p["role"] != "O":
            fail(where, "only a dummy (O) patrols")
        pt = p["patrol"]
        expect_keys(pt, {"x", "z", "speed", "phase"}, where + ".patrol")
        patrol = tuple(need_float(pt[k], f"{where}.patrol.{k}") for k in ("x", "z", "speed", "phase"))
    # "Speed multiplies top speed" (§10): a player the drill gives no speed runs at 1.0.
    speed = need_float(p["speed"], where + ".speed") if "speed" in p else 1.0
    return (p["role"], need_float(p["x"], where), need_float(p["z"], where), speed, patrol)
