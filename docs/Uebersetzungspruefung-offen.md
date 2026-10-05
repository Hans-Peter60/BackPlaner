# Übersetzungsprüfung – offene Texte

Stand: 05.10.2026 · 0 Texte, deren englische oder französische Übersetzung noch niemand bestätigt hat (meist Xcodes maschinelle Übersetzung).

Ausgefüllt wird die CSV-Datei daneben (`Uebersetzungspruefung-offen.csv`), etwa in Numbers oder Excel. Diese Seite ist nur zum Lesen.

**So geht es:**

- In **Anmerkung EN** bzw. **Anmerkung FR** entweder `ok` eintragen (die Übersetzung passt) oder die bessere Fassung. Leer lassen heißt: noch nicht geprüft.
- Die Datei als CSV speichern (Semikolon getrennt, UTF-8) und zurückgeben. Übernommen wird sie mit `python3 scripts/translation-review.py import docs/Uebersetzungspruefung-offen.csv`.

**Beim Korrigieren bitte beachten:**

- `%@`, `%lld`, `%1$@` sind Platzhalter, die die App zur Laufzeit füllt (Namen, Zahlen, Uhrzeiten). Sie müssen erhalten bleiben; ihre Reihenfolge darf sich ändern, wenn die Nummer mitgeht (`%1$@`, `%2$@`).
- `⏎` steht für einen Zeilenumbruch im Text.
- Bei Pluralformen gibt es je Zahl eine eigene Fassung, gekennzeichnet mit `one:` und `other:`; eine Korrektur schreibt beide in dieser Form.
- Englisch: amerikanische Schreibung, Titel und Schaltflächen in Satzschreibung („Save recipe“, nicht „Save Recipe“), wie im größten Teil der App. Französisch: Anrede mit « vous », Leerzeichen vor `:` `;` `?` `!`.

| # | Deutsch | Englisch | Französisch | Hinweis |
|---|---|---|---|---|
