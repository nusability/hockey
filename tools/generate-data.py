#!/usr/bin/env python3
"""Generates both apps' config and copy from shared/data/ (ADR 0001, conventions: one table).

    python3 tools/generate-data.py          write every generated file
    python3 tools/generate-data.py --check  exit 1 if any generated file differs from what it
                                            would write (a hand-edit, or a forgotten regenerate)

Python 3.11+, standard library only. The output is deterministic: the same declarations always
write the same bytes. Writes:

  ios/SmashCore/Sources/SmashCore/Generated/*.swift            ios/SmashCore/Tests/…/Generated/
  android/core/src/main/kotlin/in/nann/smashhockey/core/generated/*.kt    …/src/test/…/generated/
  ios/Sources/Localizable.xcstrings    android/app/src/main/res/values{,-de}/strings.xml

including the save records (shared/data/save.toml → SaveRecords.swift / SaveRecords.kt), and the
apps' presentation (shared/data/presentation.toml and each world's look → ios/Sources/Scene/Generated/
Presentation.swift, android/app/…/smashhockey/generated/Presentation.kt — app targets, never the core),
and what is alive in each world (shared/data/effects.toml → ios/Sources/Effects/Generated/Effects.swift,
android/app/…/smashhockey/effects/generated/Effects.kt), and the sound bank (shared/data/sounds.toml → Sounds.swift /
 Sounds.kt in SmashCore and :core, next to the copy keys).
"""
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

from datagen import copyout, design, effects, kotlin, presentation, save, sounds, swift  # noqa: E402
from datagen.common import Bits  # noqa: E402
from datagen.model import DataError, camel, load, upper_snake  # noqa: E402

ROOT = Path(__file__).resolve().parent.parent


def render():
    model = load(ROOT)
    for name, fn in (("Swift", camel), ("Kotlin", upper_snake)):
        idents = [fn(c.key) for c in model.copy]
        if len(set(idents)) != len(idents):
            dupes = sorted({i for i in idents if idents.count(i) > 1})
            raise DataError(f"copy keys collide as {name} identifiers: {dupes}")
    files = {}
    sbits, kbits = Bits(), Bits()
    files.update(swift.emit(model, sbits))
    files.update(kotlin.emit(model, kbits))
    files[swift.TEST + "GeneratedConstantBits.swift"] = swift.bits_test(sbits)
    files[kotlin.TEST + "GeneratedConstantBits.kt"] = kotlin.bits_test(kbits)
    files.update(save.emit(save.load(ROOT)))
    files.update(copyout.emit(model))
    files.update(presentation.emit(ROOT, model))
    files.update(design.emit(ROOT))
    files.update(effects.emit(ROOT))
    files.update(sounds.emit(ROOT))
    return files


def generated_dirs():
    return [ROOT / swift.SRC, ROOT / swift.TEST, ROOT / kotlin.SRC, ROOT / kotlin.TEST,
            ROOT / presentation.SWIFT, ROOT / presentation.KOTLIN, ROOT / effects.SWIFT, ROOT / effects.KOTLIN,
            ROOT / design.SWIFT, ROOT / design.KOTLIN]


def main(argv):
    check = "--check" in argv[1:]
    try:
        files = render()
    except DataError as e:
        print(f"generate-data: {e}", file=sys.stderr)
        return 2
    # Anything in a generated directory the generator no longer writes is stale.
    stale = [p for d in generated_dirs() if d.exists() for p in sorted(d.iterdir())
             if p.is_file() and str(p.relative_to(ROOT)) not in files]
    differ = []
    for rel, content in sorted(files.items()):
        path = ROOT / rel
        if not path.exists() or path.read_text(encoding="utf-8") != content:
            differ.append(rel)
            if not check:
                path.parent.mkdir(parents=True, exist_ok=True)
                path.write_text(content, encoding="utf-8")
    if check:
        for rel in differ:
            print(f"generate-data --check: {rel} differs from shared/data/ — run python3 tools/generate-data.py",
                  file=sys.stderr)
        for p in stale:
            print(f"generate-data --check: {p.relative_to(ROOT)} is stale — not written by the generator",
                  file=sys.stderr)
        if differ or stale:
            return 1
        print(f"generate-data --check: {len(files)} files up to date")
        return 0
    for p in stale:
        p.unlink()
        print(f"removed stale {p.relative_to(ROOT)}")
    print(f"generate-data: {len(files)} files, {len(differ)} written")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
