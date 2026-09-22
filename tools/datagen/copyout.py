"""Emits the copy: ios/Sources/Localizable.xcstrings and android/app/src/main/res/values*/strings.xml."""
import json

from .common import HEADER
from .model import PLACEHOLDER

XCSTRINGS = "ios/Sources/Localizable.xcstrings"
ANDROID = {"en": "android/app/src/main/res/values/strings.xml",
           "de": "android/app/src/main/res/values-de/strings.xml"}


def positional(text, args, spec):
    return PLACEHOLDER.sub(lambda m: f"%{args.index(m.group(1)) + 1}${spec}", text)


def xcstrings(model):
    strings = {}
    for c in model.copy:
        entry = {}
        if c.comment:
            entry["comment"] = c.comment
        entry["extractionState"] = "manual"
        entry["localizations"] = {
            lang: {"stringUnit": {"state": "translated", "value": positional(getattr(c, lang), c.args, "@")}}
            for lang in ("de", "en")
        }
        strings[c.key] = entry
    doc = {"sourceLanguage": "en", "strings": strings, "version": "1.0"}
    # Xcode's own layout (2-space indent, " : ", sorted keys, no final newline), so opening the
    # catalog in Xcode does not rewrite it.
    return json.dumps(doc, indent=2, separators=(",", " : "), sort_keys=True, ensure_ascii=False)


def android_escape(text):
    out = (text.replace("\\", "\\\\").replace("&", "&amp;").replace("<", "&lt;")
           .replace("'", "\\'").replace('"', '\\"'))
    if out[:1] in ("@", "?"):
        out = "\\" + out
    return out


def strings_xml(model, lang):
    lines = ['<?xml version="1.0" encoding="utf-8"?>',
             f"<!-- {HEADER} Source: shared/data/copy.toml and the names in teams.toml / drills.toml. -->",
             "<resources>"]
    for c in model.copy:
        if c.comment:
            lines.append(f"    <!-- {c.comment} -->")
        value = android_escape(positional(getattr(c, lang), c.args, "s"))
        lines.append(f'    <string name="{c.key.replace(".", "_")}">{value}</string>')
    lines.append("</resources>")
    return "\n".join(lines) + "\n"


def emit(model):
    files = {XCSTRINGS: xcstrings(model)}
    for lang, path in ANDROID.items():
        files[path] = strings_xml(model, lang)
    return files
