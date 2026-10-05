#!/usr/bin/env python3
"""Checks the repository for the mistakes a build on the Mac would not catch.

Run by the GitHub Action on every pull request, and locally with

    pip install openstep-parser   # once
    python3 scripts/check-repo.py

- String catalogs: every string the app shows has an English and a French
  entry, so nothing ships in German by accident.
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
