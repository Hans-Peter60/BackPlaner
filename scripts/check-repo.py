#!/usr/bin/env python3
"""Checks the repository for the mistakes a build on the Mac would not catch.

Run by the GitHub Action on every pull request, and locally with

    pip install openstep-parser   # once
    python3 scripts/check-repo.py

- String catalogs: every string the app shows has an English and a French
  entry, so nothing ships in German by accident.
- Package strings: every text the shared package (BakePlannerCore) shows
  is in the app's catalog, which translates it at run time, and has an
  English and a French entry there.
- Package data: the translations and units generated into the package for
  Android (scripts/generate-package-data.py) match the catalog and
  UnitSets.json.
- Xcode project: project.pbxproj parses, every object it refers to exists,
  and every source file it lists is where it says.
- User manual: the website pages match the Markdown, i.e. build-manual-html.py
  was run after the last change to a manual.

Exits with 1 and a list of findings when anything is off.
"""

from __future__ import annotations

import json
import os
import re
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
CATALOGS = [
    "BackPlaner/Localizable.xcstrings",
    "BackPlaner/InfoPlist.xcstrings",
    "BackPlanerShare/Localizable.xcstrings",
    "BakePlannerAndroid/Sources/BakePlanner/Resources/Localizable.xcstrings",
]
LANGUAGES = ("en", "fr")


def check_catalogs() -> list[str]:
    findings = []
    for relative in CATALOGS:
        path = ROOT / relative
        try:
            strings = json.loads(path.read_text(encoding="utf-8"))["strings"]
        except (OSError, ValueError, KeyError) as error:
            findings.append(f"{relative}: cannot be read ({error})")
            continue
        for key, entry in strings.items():
            if not key or entry.get("shouldTranslate") is False:
                continue
            if entry.get("extractionState") == "stale":
                continue
            localizations = entry.get("localizations", {})
            missing = [language for language in LANGUAGES if language not in localizations]
            if missing:
                shown = key if len(key) <= 70 else key[:67] + "…"
                findings.append(f"{relative}: no {'/'.join(missing)} for “{shown}”")
    return findings


PACKAGE_SOURCES = "BakePlannerCore/Sources"
PACKAGE_CATALOG = "BackPlaner/Localizable.xcstrings"
LOCALIZED_LITERAL = re.compile(r'String\(\s*localized:\s*"((?:[^"\\]|\\.)*)"')
FORMAT_SPECIFIER = r"%(?:\d+\$)?(?:@|lld|ld|d|lf|f)"


def catalog_key_pattern(literal: str) -> re.Pattern:
    """The catalog key a Swift literal becomes: each interpolation
    \\(…) turns into a format specifier whose kind depends on the value's
    type, so any of them is accepted."""
    parts, plain, i = [], "", 0
    while i < len(literal):
        if literal.startswith("\\(", i):
            parts.append(re.escape(json.loads(f'"{plain}"')))
            plain, depth, i = "", 1, i + 2
            while i < len(literal) and depth:
                depth += {"(": 1, ")": -1}.get(literal[i], 0)
                i += 1
            parts.append(FORMAT_SPECIFIER)
        else:
            plain += literal[i]
            i += 1
    parts.append(re.escape(json.loads(f'"{plain}"')))
    return re.compile("".join(parts) + r"\Z")


def check_package_strings() -> list[str]:
    """The package looks its texts up in the app's bundle
    (AppSettings.localizationBundle), so each one must stay in the app's
    catalog. Xcode no longer finds them in the app's code; they are kept
    there as manual entries, which the catalog check above skips only when
    stale."""
    try:
        strings = json.loads((ROOT / PACKAGE_CATALOG).read_text(encoding="utf-8"))["strings"]
    except (OSError, ValueError, KeyError) as error:
        return [f"{PACKAGE_CATALOG}: cannot be read ({error})"]

    findings = []
    for path in sorted((ROOT / PACKAGE_SOURCES).rglob("*.swift")):
        relative = path.relative_to(ROOT)
        for match in LOCALIZED_LITERAL.finditer(path.read_text(encoding="utf-8")):
            pattern = catalog_key_pattern(match.group(1))
            keys = [key for key in strings if pattern.match(key)]
            shown = match.group(1) if len(match.group(1)) <= 70 else match.group(1)[:67] + "…"
            if not keys:
                findings.append(f"{relative}: “{shown}” is not in {PACKAGE_CATALOG}")
                continue
            entry = strings[keys[0]]
            if entry.get("extractionState") == "stale":
                findings.append(f"{relative}: “{shown}” is stale in {PACKAGE_CATALOG}; mark it manual")
            else:
                missing = [language for language in LANGUAGES if language not in entry.get("localizations", {})]
                if missing:
                    findings.append(f"{relative}: no {'/'.join(missing)} for “{shown}” in {PACKAGE_CATALOG}")
    return findings


def check_package_data() -> list[str]:
    result = subprocess.run([sys.executable, str(ROOT / "scripts/generate-package-data.py"), "--check"],
                            cwd=ROOT, capture_output=True, text=True)
    if result.returncode != 0:
        return [line for line in (result.stdout + result.stderr).splitlines() if line.strip()]
    return []


def check_project() -> list[str]:
    try:
        import openstep_parser
    except ImportError:
        return ["openstep-parser is not installed (pip install openstep-parser)"]

    relative = "BackPlaner.xcodeproj/project.pbxproj"
    with open(ROOT / relative, encoding="utf-8") as file:
        try:
            objects = openstep_parser.OpenStepDecoder.ParseFromFile(file)["objects"]
        except Exception as error:  # the parser raises plain exceptions
            return [f"{relative}: does not parse ({error})"]

    findings = []
    identifier = re.compile(r"[0-9A-F]{24}")

    def references(value):
        if isinstance(value, dict):
            for item in value.values():
                yield from references(item)
        elif isinstance(value, list):
            for item in value:
                yield from references(item)
        elif isinstance(value, str) and identifier.fullmatch(value):
            yield value

    dangling = {ref for obj in objects.values() for ref in references(obj) if ref not in objects}
    findings += [f"{relative}: refers to missing object {ref}" for ref in sorted(dangling)]

    parent = {}
    for key, obj in objects.items():
        for child in obj.get("children", []):
            if child in parent:
                findings.append(f"{relative}: {child} sits in two groups")
            parent[child] = key

    def path_of(key: str) -> str:
        parts, obj = [], objects[key]
        while True:
            if obj.get("path"):
                parts.append(obj["path"])
            if obj.get("sourceTree") != "<group>" or key not in parent:
                break
            key = parent[key]
            obj = objects[key]
        return os.path.join(*reversed(parts)) if parts else ""

    for key, obj in objects.items():
        if obj.get("isa") not in ("PBXFileReference", "PBXFileSystemSynchronizedRootGroup"):
            continue
        if obj.get("sourceTree") not in ("<group>", "SOURCE_ROOT"):
            continue
        path = path_of(key)
        if path and not (ROOT / path).exists():
            findings.append(f"{relative}: lists {path}, which does not exist")
    return findings


def check_manual() -> list[str]:
    website = "docs/website"
    result = subprocess.run([sys.executable, str(ROOT / "docs/build-manual-html.py")],
                            cwd=ROOT, capture_output=True, text=True)
    if result.returncode != 0:
        return [f"docs/build-manual-html.py failed: {result.stderr.strip()}"]
    changed = subprocess.run(["git", "status", "--porcelain", "--", website],
                             cwd=ROOT, capture_output=True, text=True).stdout.strip()
    if changed:
        return [f"{website} is out of date — run python3 docs/build-manual-html.py and commit:\n{changed}"]
    return []


def main() -> int:
    sections = [
        ("String catalogs", check_catalogs),
        ("Package strings", check_package_strings),
        ("Package data", check_package_data),
        ("Xcode project", check_project),
        ("User manual", check_manual),
    ]
    failed = False
    for title, check in sections:
        findings = check()
        print(f"{'✗' if findings else '✓'} {title}")
        for finding in findings:
            print(f"    {finding}")
        failed = failed or bool(findings)
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
