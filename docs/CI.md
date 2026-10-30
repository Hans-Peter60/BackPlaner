# Automatische Prüfungen

Jeder Pull Request wird an zwei Stellen geprüft:

| Wo | Was | Wird eingerichtet |
|---|---|---|
| **GitHub Actions** (`.github/workflows/checks.yml`) | String-Kataloge vollständig (en/fr), Texte des Pakets `BakePlannerCore` im App-Katalog, erzeugte Paketdaten aktuell, Projektdatei gültig, Handbuch-Webseiten aktuell, Cloud Functions Lint und Build, Firestore-Regeln im Emulator | über das Repository, läuft von selbst |
| **Xcode Cloud** | App bauen, Unit-Tests und UI-Tests im Simulator | einmalig in Xcode (siehe unten) |

Die GitHub-Prüfung braucht keinen Mac und kostet praktisch nichts. Alles, was die App selbst betrifft, läuft in Xcode Cloud. Im Apple Developer Program sind 25 Rechenstunden im Monat enthalten; ein Testlauf dauert einige Minuten.

## Tests auf dem Mac

Das Schema `BackPlaner` hat zwei Testpläne (`UnitTests.xctestplan`, `AllTests.xctestplan` im Projektordner):

| Testplan | Inhalt | Wofür |
|---|---|---|
| **UnitTests** (Standard für ⌘U) | die 285 Unit-Tests in `BackPlanerTests` | jeder Lauf während der Arbeit; die Tests selbst brauchen unter einer Sekunde, der ganze Lauf auf einem gebooteten Simulator etwa eine halbe Minute |
| **AllTests** | Unit-Tests und UI-Tests | Xcode Cloud, vor einem Release; die UI-Tests starten die App mehrfach und brauchen einige Minuten |

Umschalten in Xcode über das Schema-Menü → **Edit Scheme… → Test → Test Plans**, oder im Testnavigator oben. Auf der Kommandozeile `xcodebuild test -scheme BackPlaner -testPlan UnitTests -destination 'id=<udid>'`; für wiederholte Läufe einmal `build-for-testing`, dann `test-without-building`.

Als Host der Unit-Tests startet die App verkürzt (`UITestSupport.isUnitTestHost`): Firebase wird konfiguriert, aber Datenbank-Aufräumen, Widget-Publisher, Benachrichtigungen, Hintergrundfoto und die anonyme Anmeldung entfallen, und das Fenster bleibt leer. Die Tests bauen sich ihre In-Memory-Container selbst. Für die UI-Tests startet die App vollständig.

Hängt ein Lauf beim Start des Test-Runners („test runner hung before establishing connection“), liegt es am Simulator, nicht an den Tests: abbrechen und einen anderen Simulator nehmen statt zu warten. Das Unit-Test-Target verlangt iOS 27; der iPhone-Duo-Simulator (iOS 27.1) hat sich als zuverlässig erwiesen.

## GitHub Actions

Läuft bei jedem Pull Request und jedem Push auf `main`. Die gleichen Prüfungen lokal:

```sh
pip install openstep-parser   # einmalig
python3 scripts/check-repo.py

cd functions && npm ci && npm run lint && npm run build

cd firebase/tests && npm ci && npm test   # braucht Java
```

Schlägt **„User manual“** fehl, wurde ein Handbuch geändert, ohne die Webseiten neu zu erzeugen:
`python3 docs/build-manual-html.py` ausführen und das Ergebnis mit committen.

Schlägt **„Firestore rules“** fehl, erlauben oder verbieten die Regeln in `firebase/firestore.rules` etwas anderes, als die App erwartet. Die Ausgabe nennt den Fall, etwa „user: get reported refused“. Entweder ist die Regeländerung falsch, oder die App hat sich geändert und der Test in `firebase/tests/rules.test.mjs` muss mit.

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

   Die vorgeschlagene Bedingung **„Branch Changes“** lässt sich nicht entfernen, und sie braucht mindestens einen Branch, sonst bleibt **Save** gesperrt. Dort **`main`** eintragen: Dann testet Xcode Cloud zusätzlich jeden Stand von `main` nach einem Merge. Das kostet etwas mehr Rechenzeit, liegt aber weit innerhalb der enthaltenen 25 Stunden.
6. **Actions:** eine **„Archive“**-Aktion entfernen, falls vorhanden. **„Test“** hinzufügen:
   - Scheme: **BackPlaner**
   - Testplan: **AllTests** (Unit- und UI-Tests). Der Standard-Testplan des Schemas ist **UnitTests**, damit ⌘U auf dem Mac nur die Unit-Tests ausführt; die UI-Tests gehören in Xcode Cloud und vor ein Release.
   - Platform: **iOS**
   - Destination: **„Recommended iPhones“** oder gezielt ein aktuelles iPhone mit der neuesten iOS-Version
   - **„Required to pass“** einschalten
7. **Post-Actions:** **„Notify“** hinzufügen, E-Mail bei **Failure**.
8. **Save**. Beim nächsten Pull Request erscheint unten in der Pull-Request-Seite eine Prüfung von Xcode Cloud.

Optional, aber empfehlenswert: Auf GitHub unter **Settings → Branches → Add branch ruleset** für `main` festlegen, dass die Prüfungen grün sein müssen, bevor gemergt werden kann (**„Require status checks to pass“**: die drei Jobs von „Checks“ und die Xcode-Cloud-Prüfung).

### Was in Xcode Cloud anders ist als auf dem eigenen Mac

- **Firebase:** Der Simulator in Xcode Cloud hat kein registriertes App-Check-Debug-Token. Zugriffe auf Firestore schlagen dort fehl. Die Tests sind darauf ausgelegt: Die UI-Tests lassen die Rezept-Datenbank bewusst aus und arbeiten mit einem leeren Speicher im Arbeitsspeicher (`-UITesting`).
- **Mitteilungen:** Die Abfrage „BackPlaner möchte Mitteilungen senden“ beantworten die UI-Tests selbst.
- **`ci_scripts`:** werden nicht gebraucht. Alle Abhängigkeiten kommen über Swift Package Manager; `Package.resolved` ist eingecheckt.
