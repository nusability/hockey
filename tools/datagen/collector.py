"""The collector's half of shared/data/telemetry.toml (spec §18): the DDL and the column contract.

Both are **generated from the same declaration as the apps' record types**, which is the whole
mechanism of ADR 0009 and is not a theoretical nicety. ../flashybird's collector kept its column
list by hand, and its own schema header records what that cost: `platform` and `language` were
being sent and not inserted for months, together with the five columns its difficulty question
grouped on, because "a column missing from this list is not an error at any layer; it is a default
quietly standing in for a measurement."

So: one table per `_table` record, the envelope's columns first, and `columns.json` — the only
artifact that crosses to the server — listing each table's columns in order, with the types and the
declared value sets. The collector reads it at boot and builds its INSERTs from it. Nothing on
either side spells a column name.

The DDL is idempotent (`IF NOT EXISTS` throughout) and carries no migrations: until the first store
submission a declaration change drops and rebuilds the table (conventions.md, greenfield). From the
first shipped build that changes, and an added column needs an explicit default written by hand —
which is a deliberate decision each time, not something a generator should guess.
"""
import json

from . import records

SQL_TYPE = {
    "int": "INT", "bool": "BOOLEAN", "string": "TEXT", "i64": "BIGINT",
    "uuid": "UUID", "double": "DOUBLE PRECISION", "u64": "TEXT", "rgb": "INT",
}
# Instants are stored as epoch milliseconds rather than TIMESTAMPTZ, on purpose: it is what the
# client already holds (no conversion to disagree about), it is what a golden vector pins, and it is
# what Grafana's time axis reads natively. `received_at` is the server's own clock and is the one
# timestamp here, because it is the one value the client has no say in.
SERVER_COLUMNS = """    id          BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    received_at TIMESTAMPTZ NOT NULL DEFAULT now(),
"""


def sql_type(ref):
    if ref.enum or ref.name in records.KEYED:
        return "TEXT"
    if ref.is_list:
        return SQL_TYPE[ref.name] + "[]"
    return SQL_TYPE[ref.name]


def column(name, ref, enums):
    """One column: its type, its nullability, and a CHECK for a declared value set."""
    quoted = f'"{name}"'
    out = f"    {quoted:<18} {sql_type(ref)}"
    out += "" if ref.optional else " NOT NULL"
    if ref.enum and not ref.is_list:
        allowed = ", ".join(f"'{v}'" for v in enums[ref.name])
        out += f"\n        CHECK ({quoted} IN ({allowed}))"
    return out


def schema(family):
    """The DDL. Deterministic: the same declaration always writes the same bytes."""
    enums = {e.name: e.values for e in family.enums}
    out = ["""-- Smash Hockey telemetry — the schema (spec §18, ADR 0009).
--
-- GENERATED from shared/data/telemetry.toml by tools/generate-data.py. Do not edit: run the
-- generator. A hand edit here is caught by `python3 tools/generate-data.py --check`, which is the
-- guard that makes this file trustworthy — and the reason it is generated at all is written at the
-- top of tools/datagen/collector.py.
--
-- Idempotent: every statement is IF NOT EXISTS, so running it twice is running it once.
--
-- There are deliberately **no ALTER statements**. Nothing has been submitted to either store, so
-- conventions.md's greenfield section is still awake and a declaration change simply drops and
-- rebuilds the table. From the first shipped build that stops being true — rows written by installs
-- we can no longer update have to stay readable — and a change then adds a column with an explicit
-- default, never renames or removes one. Generating an ALTER per column before then was worse than
-- useless: it emitted `UUID NOT NULL DEFAULT \'\'` and would have failed on the table it claimed to
-- catch up.
"""]
    for r in family.tables:
        out.append(f"\n-- {r.doc}\nCREATE TABLE IF NOT EXISTS {r.table} (\n")
        out.append(SERVER_COLUMNS)
        out.append(",\n".join(column(n, t, enums) for n, t in r.fields))
        out.append("\n);\n")
        # Every query starts from "real rows, this platform, this window", so that leads the index.
        out.append(f'CREATE INDEX IF NOT EXISTS {r.table}_env     ON {r.table} ("env", "synthetic", "at" DESC);\n')
        out.append(f'CREATE INDEX IF NOT EXISTS {r.table}_install ON {r.table} ("install_id", "at");\n')
    return "".join(out)


def contract(family):
    """`columns.json` — the only artifact that crosses to the server.

    The collector reads this at boot and builds one INSERT per table from it, so a column it does
    not know about cannot exist and a column it knows about cannot be missing from the statement.
    """
    enums = {e.name: e.values for e in family.enums}
    tables = {}
    for r in family.tables:
        tables[r.table] = {
            "doc": r.doc,
            "columns": [
                {
                    "name": n,
                    # The wire type, not the SQL type: this is what the collector validates against.
                    "type": "enum" if t.enum else ("key" if t.name in records.KEYED else t.name),
                    "sql": sql_type(t),
                    "required": not t.optional,
                    **({"values": enums[t.name]} if t.enum else {}),
                }
                for n, t in r.fields
            ],
        }
    return json.dumps({
        "_generated": "tools/generate-data.py from shared/data/telemetry.toml — do not edit",
        # The tables' own version (telemetry.toml [wire]), never the device record's file format:
        # one moving because the other changed is what this split exists to prevent (spec §18.6).
        "wire": family.wire_version,
        "tables": tables,
    }, indent=2, sort_keys=False) + "\n"


def emit(root, decl):
    family = records.load(root, decl)
    if not family.tables:
        return {}
    return {decl.sql_path: schema(family), decl.contract_path: contract(family)}
