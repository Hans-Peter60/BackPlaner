#!/usr/bin/env python3
"""The review list for translations nobody has confirmed yet, and back.

Every string the app shows has an English and a French entry, but many came
from Xcode's machine translation ("machine_translated" in the catalog) and
were never read by a person. This script lists them for review and takes the
reviewed list back:

    python3 scripts/translation-review.py export
        writes docs/Uebersetzungspruefung-offen.md (to read) and
        docs/Uebersetzungspruefung-offen.csv (to fill in Numbers or Excel)

    python3 scripts/translation-review.py import docs/Uebersetzungspruefung-offen.csv
        applies the filled columns "Anmerkung EN" and "Anmerkung FR":
          ok           the translation stays and counts as reviewed
          other text   replaces the translation, which then counts as reviewed
          empty        nothing changes, the text stays on the list
        then export again to get the shorter list.

The CSV uses semicolons and UTF-8 with a byte order mark, which Excel and
Numbers open without asking. A line break inside a text is shown as ⏎, a
plural as "one: …" and "other: …" on lines of their own (⏎ between them).
"""

from __future__ import annotations

import csv
import json
import sys
from collections import OrderedDict
from datetime import date
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
CATALOGS = [
    "BackPlaner/Localizable.xcstrings",
    "BackPlaner/InfoPlist.xcstrings",
    "BackPlanerShare/Localizable.xcstrings",
]
LANGUAGES = ("en", "fr")
OUT_MD = ROOT / "docs/Uebersetzungspruefung-offen.md"
OUT_CSV = ROOT / "docs/Uebersetzungspruefung-offen.csv"
HEADER = ["Nr", "Katalog", "Deutsch", "Englisch", "Franzoesisch", "Status", "Hinweis",
          "Anmerkung EN", "Anmerkung FR"]
NEWLINE = "⏎"


def load(relative: str) -> OrderedDict:
    return json.loads((ROOT / relative).read_text(encoding="utf-8"), object_pairs_hook=OrderedDict)


def save(relative: str, catalog: OrderedDict) -> None:
    path = ROOT / relative
    original = path.read_text(encoding="utf-8")
    text = json.dumps(catalog, indent=2, separators=(",", " : "), ensure_ascii=False)
    path.write_text(text + ("\n" if original.endswith("\n") else ""), encoding="utf-8")


def units(localization: dict):
    """(variant, stringUnit) pairs: one plain unit, or one per plural form."""
    if "stringUnit" in localization:
        yield None, localization["stringUnit"]
    for kind in localization.get("variations", {}).values():
        for variant, nested in kind.items():
            if "stringUnit" in nested:
                yield variant, nested["stringUnit"]


def shown(localization: dict) -> str:
    parts = [(f"{variant}: " if variant else "") + unit.get("value", "")
             for variant, unit in units(localization)]
    return NEWLINE.join(part.replace("\n", NEWLINE) for part in parts)


def pending(entry: dict) -> list[str]:
    """The languages whose translation nobody has confirmed."""
    localizations = entry.get("localizations", {})
    return [language for language in LANGUAGES
            if any(unit.get("state") != "translated"
                   for _, unit in units(localizations.get(language, {})))]


def german(key: str, entry: dict) -> str:
    localization = entry.get("localizations", {}).get("de")
    return shown(localization) if localization else key.replace("\n", NEWLINE)


def hint(text: str) -> str:
    notes = []
    if "%" in text:
        notes.append("Platzhalter")
    if len(text) > 120:
        notes.append("langer Text")
    return ", ".join(notes)


def rows() -> list[list[str]]:
    result = []
    for relative in CATALOGS:
        for key, entry in load(relative)["strings"].items():
            if not key or entry.get("shouldTranslate") is False or entry.get("extractionState") == "stale":
                continue
            languages = pending(entry)
            if not languages:
                continue
            localizations = entry.get("localizations", {})
            status = " / ".join(
                f"{language}={next((u.get('state') for _, u in units(localizations.get(language, {})) if u.get('state') != 'translated'), 'translated')}"
                for language in LANGUAGES)
            source = german(key, entry)
            result.append([str(len(result) + 1), relative, source,
                           shown(localizations.get("en", {})), shown(localizations.get("fr", {})),
                           status, hint(source), "", ""])
    return result


def export() -> None:
    table = rows()
    with OUT_CSV.open("w", encoding="utf-8-sig", newline="") as file:
        writer = csv.writer(file, delimiter=";", quoting=csv.QUOTE_ALL)
        writer.writerow(HEADER)
        writer.writerows(table)

    def cell(text: str) -> str:
        return text.replace("|", "\\|")

    lines = [
        "# Übersetzungsprüfung – offene Texte",
        "",
        f"Stand: {date.today().strftime('%d.%m.%Y')} · {len(table)} Texte, deren englische oder französische "
        "Übersetzung noch niemand bestätigt hat (meist Xcodes maschinelle Übersetzung).",
        "",
        "Ausgefüllt wird die CSV-Datei daneben (`Uebersetzungspruefung-offen.csv`), etwa in Numbers oder Excel. "
        "Diese Seite ist nur zum Lesen.",
        "",
        "**So geht es:**",
        "",
        "- In **Anmerkung EN** bzw. **Anmerkung FR** entweder `ok` eintragen (die Übersetzung passt) "
        "oder die bessere Fassung. Leer lassen heißt: noch nicht geprüft.",
        "- Die Datei als CSV speichern (Semikolon getrennt, UTF-8) und zurückgeben. "
        "Übernommen wird sie mit `python3 scripts/translation-review.py import docs/Uebersetzungspruefung-offen.csv`.",
        "",
        "**Beim Korrigieren bitte beachten:**",
        "",
        "- `%@`, `%lld`, `%1$@` sind Platzhalter, die die App zur Laufzeit füllt (Namen, Zahlen, Uhrzeiten). "
        "Sie müssen erhalten bleiben; ihre Reihenfolge darf sich ändern, wenn die Nummer mitgeht (`%1$@`, `%2$@`).",
        f"- `{NEWLINE}` steht für einen Zeilenumbruch im Text.",
        "- Bei Pluralformen gibt es je Zahl eine eigene Fassung, gekennzeichnet mit `one:` und `other:`; "
        "eine Korrektur schreibt beide in dieser Form.",
        "- Englisch: amerikanische Schreibung, Titel und Schaltflächen in Satzschreibung "
        "(„Save recipe“, nicht „Save Recipe“), wie im größten Teil der App. "
        "Französisch: Anrede mit « vous », Leerzeichen vor `:` `;` `?` `!`.",
        "",
        "| # | Deutsch | Englisch | Französisch | Hinweis |",
        "|---|---|---|---|---|",
    ]
    lines += [f"| {r[0]} | {cell(r[2])} | {cell(r[3])} | {cell(r[4])} | {r[6]} |" for r in table]
    OUT_MD.write_text("\n".join(lines) + "\n", encoding="utf-8")
    print(f"{len(table)} open texts → {OUT_MD.relative_to(ROOT)}, {OUT_CSV.relative_to(ROOT)}")


def apply_note(localization: dict, note: str) -> bool:
    """Confirms or replaces one language's translation; False if the note
    does not fit the entry (a plural correction without its forms)."""
    pairs = list(units(localization))
    if note.lower() == "ok":
        for _, unit in pairs:
            unit["state"] = "translated"
        return True
    text = note.replace(NEWLINE, "\n")
    if len(pairs) == 1 and pairs[0][0] is None:
        pairs[0][1]["value"] = text
        pairs[0][1]["state"] = "translated"
        return True
    forms = {}
    for line in text.split("\n"):
        variant, sep, value = line.partition(":")
        if sep:
            forms[variant.strip()] = value.strip()
    if not all(variant in forms for variant, _ in pairs):
        return False
    for variant, unit in pairs:
        unit["value"] = forms[variant]
        unit["state"] = "translated"
    return True


def import_(path: str) -> None:
    with open(path, encoding="utf-8-sig", newline="") as file:
        reader = csv.DictReader(file, delimiter=";")
        reviewed = [row for row in reader if (row.get("Anmerkung EN") or "").strip()
                    or (row.get("Anmerkung FR") or "").strip()]

    catalogs = {relative: load(relative) for relative in CATALOGS}
    keys = {relative: {german(key, entry): key for key, entry in catalog["strings"].items()}
            for relative, catalog in catalogs.items()}

    applied, problems = 0, []
    for row in reviewed:
        relative = row.get("Katalog") or CATALOGS[0]
        catalog = catalogs.get(relative)
        key = keys.get(relative, {}).get(row["Deutsch"])
        if catalog is None or key is None:
            problems.append(f"Nr {row['Nr']}: „{row['Deutsch'][:50]}“ is no longer in {relative}")
            continue
        localizations = catalog["strings"][key].setdefault("localizations", OrderedDict())
        for language, column in (("en", "Anmerkung EN"), ("fr", "Anmerkung FR")):
            note = (row.get(column) or "").strip()
            if not note:
                continue
            if language not in localizations:
                localizations[language] = OrderedDict(stringUnit=OrderedDict(state="translated", value=""))
            if apply_note(localizations[language], note):
                applied += 1
            else:
                problems.append(f"Nr {row['Nr']} {language}: a plural needs every form "
                                f"({', '.join(v for v, _ in units(localizations[language]))})")

    for relative, catalog in catalogs.items():
        save(relative, catalog)
    print(f"{applied} translations confirmed or replaced")
    for problem in problems:
        print(f"  ! {problem}")


if __name__ == "__main__":
    if len(sys.argv) >= 2 and sys.argv[1] == "export":
        export()
    elif len(sys.argv) == 3 and sys.argv[1] == "import":
        import_(sys.argv[2])
    else:
        print(__doc__)
        sys.exit(1)
