"""The device record (shared/data/telemetry.toml, spec §17) — the second record family declared
over the engine in records.py: what the device remembers about itself rather than about the
player's career, which is why it is a file of its own beside the save (ADR 0009).

The JSON runtime the generated code calls is the save's (core/season on either platform); the
`validate` rule check is hand-written in Telemetry/ (SmashCore) and core/telemetry (Android).
"""
from . import records

DECL = records.Declaration(
    toml="telemetry.toml",
    format="TelemetryFormat",
    format_doc="The device record's format",
    swift_path="ios/SmashCore/Sources/SmashCore/Generated/TelemetryRecords.swift",
    kotlin_path="android/core/src/main/kotlin/in/nann/smashhockey/core/generated/TelemetryRecords.kt",
    swift_doc="The device record (telemetry.toml, spec §17): the types, their canonical JSON and its strict decoding.\n"
              "// The JSON runtime is the save's (Season/); the `validate(at:)` rule check is hand-written in Telemetry/.",
    kotlin_doc="The device record (telemetry.toml, spec §17): the types, their canonical JSON and its strict decoding.\n"
               "// The JSON runtime is the save's (core/season); the `validate(path)` rule check is hand-written in core/telemetry.",
    kotlin_imports=["core.season.JsonValue", "core.season.SaveJson", "core.telemetry.validate"],
)


def emit(root):
    return records.emit(root, DECL)
