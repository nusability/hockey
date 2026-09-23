"""The save records (shared/data/save.toml, spec §15) — one of the two record families declared
over the engine in records.py: everything the game keeps of a player's career, season, training and
board, with its canonical JSON encoding and strict decoding, on both platforms.

The JSON runtime the generated code calls, and the `validate` rule checks the records opt into,
are hand-written in Season/ (SmashCore) and core/season (Android).
"""
from . import records

DECL = records.Declaration(
    toml="save.toml",
    format="SaveFormat",
    format_doc="The save format",
    swift_path="ios/SmashCore/Sources/SmashCore/Generated/SaveRecords.swift",
    kotlin_path="android/core/src/main/kotlin/in/nann/smashhockey/core/generated/SaveRecords.kt",
    swift_doc="The save records (save.toml, spec §15): the types, their canonical JSON and its strict decoding.\n"
              "// The JSON runtime, the decode error and the `validate(at:)` rule checks are hand-written in Season/.",
    kotlin_doc="The save records (save.toml, spec §15): the types, their canonical JSON and its strict decoding.\n"
               "// The JSON runtime, the decode error and the `validate(path)` rule checks are hand-written in core/season.",
    kotlin_imports=["core.season.JsonValue", "core.season.SaveJson", "core.season.validate"],
)

# Kept for the tests and tools that name these paths directly.
SWIFT = DECL.swift_path
KOTLIN = DECL.kotlin_path


def emit(root):
    return records.emit(root, DECL)
