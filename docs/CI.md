# Automatische Prüfungen

Jeder Pull Request wird an zwei Stellen geprüft:

| Wo | Was | Wird eingerichtet |
|---|---|---|
| **GitHub Actions** (`.github/workflows/checks.yml`) | String-Kataloge vollständig (en/fr), Projektdatei gültig, Handbuch-Webseiten aktuell, Cloud Functions Lint und Build | über das Repository, läuft von selbst |
| **Xcode Cloud** | App bauen, Unit-Tests und UI-Tests im Simulator | einmalig in Xcode (siehe unten) |

Die GitHub-Prüfung braucht keinen Mac und kostet praktisch nichts. Alles, was die App selbst betrifft, läuft in Xcode Cloud. Im Apple Developer Program sind 25 Rechenstunden im Monat enthalten; ein Testlauf dauert einige Minuten.

## GitHub Actions

Läuft bei jedem Pull Request und jedem Push auf `main`. Die gleichen Prüfungen lokal:

```sh
pip install openstep-parser   # einmalig
python3 scripts/check-repo.py

cd functions && npm ci && npm run lint && npm run build
```

Schlägt **„User manual“** fehl, wurde ein Handbuch geändert, ohne die Webseiten neu zu erzeugen:
`python3 docs/build-manual-html.py` ausführen und das Ergebnis mit committen.

Schlägt **„String catalogs“** fehl, hat ein neuer Text keine englische oder französische Übersetzung. Xcode legt neue Texte beim Bauen im Katalog an; die Übersetzungen dazu fehlen dann noch.

## Xcode Cloud einrichten (einmalig)

Ein Xcode-Cloud-Produkt für BackPlaner ist bereits angelegt (`BackPlaner.xcodeproj/xcshareddata/xcodecloud/manifest.json`). Es fehlt nur ein Workflow, der bei Pull Requests testet.

1. Die Workflow-Verwaltung öffnen, je nach Xcode-Version an einer dieser Stellen:
   - Menü **Integrate → Manage Workflows…** (oder **Create Workflow…**, solange es noch keinen gibt),
   - Report-Navigator (**⌘9**) → Reiter **Cloud** → Rechtsklick auf das Produkt → **Manage Workflows…**,
   - im Browser: **App Store Connect → Apps → BakePlanner → Xcode Cloud → Manage Workflows**.
2. Einen neuen Workflow anlegen (**+**) oder den vorhandenen „Default“-Workflow bearbeiten. Name zum Beispiel **„Pull-Request-Tests“**.
3. **General:** Haken bei **„Restrict Editing“** nach Belieben. Unter **Repository** muss `Hans-Peter60/BackPlaner` stehen. Fragt Xcode nach Zugriff auf GitHub, die Xcode-Cloud-App für das Repository erlauben.
4. **Environment:** Xcode-Version **„Latest Release“** (sie muss das iOS-27-SDK enthalten), macOS **„Latest“**.
5. **Start Conditions:** zuerst über das **⊕** neben „Start Conditions“ **„Pull Request Changes“** hinzufügen:
   - Source Branch: **Any Branch**
   - Target Branch: **main**
   - **„Auto-cancel Builds“** einschalten, damit ein neuer Push den alten Lauf abbricht.

   Erst danach die vorgeschlagene Bedingung „Branch Changes“ markieren und mit **⌫** oder Rechtsklick → **Delete** entfernen. Ein Workflow braucht mindestens eine Start-Bedingung, deshalb lässt sich die einzige nicht löschen.
6. **Actions:** eine **„Archive“**-Aktion entfernen, falls vorhanden. **„Test“** hinzufügen:
   - Scheme: **BackPlaner**
   - Platform: **iOS**
   - Destination: **„Recommended iPhones“** oder gezielt ein aktuelles iPhone mit der neuesten iOS-Version
   - **„Required to pass“** einschalten
7. **Post-Actions:** **„Notify“** hinzufügen, E-Mail bei **Failure**.
8. **Save**. Beim nächsten Pull Request erscheint unten in der Pull-Request-Seite eine Prüfung von Xcode Cloud.

Optional, aber empfehlenswert: Auf GitHub unter **Settings → Branches → Add branch ruleset** für `main` festlegen, dass die Prüfungen grün sein müssen, bevor gemergt werden kann (**„Require status checks to pass“**: die beiden Jobs von „Checks“ und die Xcode-Cloud-Prüfung).

### Was in Xcode Cloud anders ist als auf dem eigenen Mac

- **Firebase:** Der Simulator in Xcode Cloud hat kein registriertes App-Check-Debug-Token. Zugriffe auf Firestore schlagen dort fehl. Die Tests sind darauf ausgelegt: Die UI-Tests lassen die Rezept-Datenbank bewusst aus und arbeiten mit einem leeren Speicher im Arbeitsspeicher (`-UITesting`).
- **Mitteilungen:** Die Abfrage „BackPlaner möchte Mitteilungen senden“ beantworten die UI-Tests selbst.
- **`ci_scripts`:** werden nicht gebraucht. Alle Abhängigkeiten kommen über Swift Package Manager; `Package.resolved` ist eingecheckt.
