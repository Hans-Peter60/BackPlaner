#!/usr/bin/env python3
"""Builds the string catalog of CookPlanner's Android app from its sources.

Every `String(localized: "…", bundle: .module)` in
Android/CookPlannerAndroid/Sources/CookPlanner/*.swift becomes an entry,
interpolations written as %lld (the Android app interpolates mostly whole
numbers) or, with a `/*%@*/` comment inside the interpolation's
parentheses — `\(name /*%@*/)` — as %@ for a String. (Inside the
parentheses Swift reads the marker as a comment; after them it would be
part of the text.)
The English and French come from the iPhone's catalog
(CookPlanner/CookPlanner/Localizable.xcstrings); a text the iPhone does not
have keeps what the Android catalog already says, so new texts are
translated once, by hand, in the Android catalog. All entries are
"manual" (Xcode does not find texts in Skip-built code), sorted the way
Xcode sorts, and the file ends without a newline, as BakePlanner's
Android catalog.

    python3 scripts/cookplanner/android-catalog.py           # write
    python3 scripts/cookplanner/android-catalog.py --check   # check-repo
"""

import json
import re
import sys
import unicodedata
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
SOURCES = ROOT / "Android/CookPlannerAndroid/Sources/CookPlanner"
CATALOG = SOURCES / "Resources/Localizable.xcstrings"
IOS_CATALOG = ROOT / "CookPlanner/CookPlanner/Localizable.xcstrings"
LANGUAGES = ("en", "fr")

LITERAL = re.compile(r'String\(localized: "((?:[^"\\]|\\.)*)"')
INTERPOLATION = re.compile(r'\\\(((?:[^()]|\([^()]*\))*)\)')


def keys_in_sources() -> set[str]:
    keys = set()
    for path in sorted(SOURCES.glob("*.swift")):
        for match in LITERAL.finditer(path.read_text(encoding="utf-8")):
            literal = match.group(1)
            key = INTERPOLATION.sub(lambda m: "%@" if "/*%@*/" in m.group(1) else "%lld", literal)
            keys.add(key.replace('\\"', '"').replace("\\n", "\n"))
    return keys


def xcode_order(key: str) -> str:
    plain = unicodedata.normalize("NFKD", key)
    return "".join(c for c in plain if not unicodedata.combining(c)).casefold()


def build() -> tuple[str, list[str]]:
    ios = json.loads(IOS_CATALOG.read_text(encoding="utf-8"))["strings"]
    current = {}
    if CATALOG.exists():
        current = json.loads(CATALOG.read_text(encoding="utf-8")).get("strings", {})
    missing = []
    strings = {}
    for key in sorted(keys_in_sources(), key=xcode_order):
        localizations = {}
        for language in LANGUAGES:
            unit = (ios.get(key, {}).get("localizations", {}).get(language)
                    or current.get(key, {}).get("localizations", {}).get(language))
            if unit:
                localizations[language] = unit
            else:
                missing.append(f"{language}: {key}")
        strings[key] = {"extractionState": "manual", "localizations": localizations}
    text = json.dumps({"sourceLanguage": "de", "strings": strings, "version": "1.1"},
                      ensure_ascii=False, indent=2, separators=(",", " : "))
    return text, missing


def main() -> int:
    text, missing = build()
    if "--check" in sys.argv:
        problems = [f"no translation ({entry})" for entry in missing]
        if not CATALOG.exists() or CATALOG.read_text(encoding="utf-8") != text:
            problems.append("out of date — run python3 scripts/cookplanner/android-catalog.py")
        for problem in problems:
            print(f"{CATALOG.relative_to(ROOT)}: {problem}")
        return 1 if problems else 0
    CATALOG.write_text(text, encoding="utf-8")
    for entry in missing:
        print(f"missing {entry} — add it in {CATALOG.relative_to(ROOT)}")
    return 1 if missing else 0


if __name__ == "__main__":
    sys.exit(main())
