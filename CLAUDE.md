# BakePlanner (Projekt „BackPlaner")

iOS/iPadOS-App zum Planen von Brot- und Backrezepten. App-Store-Name **BakePlanner**, Bundle-Präfix `de.hpm64625.BackPlaner`. Entwickler: Hans-Peter Müller (Einzelentwickler).

## Aufbau
- `BackPlaner/` – App-Target (SwiftUI, iOS 26+). `Views/` UI, `Utilities/` Logik und Dienste, `CoreData/` Modell, `DataFiles/` Firebase-Modelle (`RecipeFB*`), `Intents/` Siri/App Intents.
- `BakePlannerCore/` – lokales Swift Package mit plattformneutraler Logik und ihren Tests (Android-Portierung, im Aufbau); die App bindet es ein, die Tests laufen im Testplan `UnitTests` mit.
- `BackPlanerWidgets/` – Widget und Live-Aktivität. `BackPlanerShare/` – Share-Extension für den Web-Import.
- `BackPlanerTests/` – ca. 285 Unit-Tests (`UnitTests.xctestplan`, Standard für ⌘U). `BackPlanerUITests/` – UI-Tests (`AllTests.xctestplan`).
- `functions/` – Cloud Functions (TypeScript): KI-Rezeptimport (`analyzeRecipeImages`, `analyzeRecipeText`), Pro-Prüfung (`proVerification.ts`).
- `firebase/` – Firestore- und Storage-Regeln, Regel-Tests im Emulator (`firebase/tests`).
- `docs/` – Handbücher (DE/EN/FR, HTML wird mit `docs/build-manual-html.py` erzeugt), App-Store-Texte, CI-Doku (`docs/CI.md`), Android-Bestandsaufnahme.

## Daten
- **Private Daten:** Core Data mit `NSPersistentCloudKitContainer` (iCloud-Container `iCloud.de.hpm64625.BackPlaner`). Entitäten: Recipe, Component, Ingredient, Instruction, NextStep, BakeHistory, ShoppingCart, Item, StarterFeedingLog.
- **Öffentliche Rezepte:** Firestore + Storage. Anmeldung anonym über Firebase Auth, optional mit Apple verknüpft; `authorId` = Firebase-UID.
- **Sicherungsformat:** `RecipeExportData` / `RecipeExportIngredient` (`BakePlannerCore/Sources/BakePlannerCore/RecipeExportFormat.swift`, Core-Data-Anbindung in `Utilities/RecipeExport.swift`) – plattformneutrale Structs, auch Brücke für einen späteren Plattformwechsel. Format nicht ohne Versionierung ändern.
- **Pro:** StoreKit 2, Einmalkauf `de.hpm64625.BackPlaner.pro`; Umfang in `Utilities/ProFeature.swift`. Kern (Rezepte, Plan, Erinnerungen, Backmodus, Historie, öffentliche Rezepte, Rechner) bleibt kostenlos.

## Prüfen und Testen
- Unit-Tests: `xcodebuild test -scheme BackPlaner -testPlan UnitTests -destination 'id=<udid>'`. Hängt der Test-Runner beim Start, anderen Simulator nehmen (iOS 27.x).
- Repository-Prüfung (String-Kataloge en/fr vollständig, Projektdatei, Handbuch-HTML aktuell): `python3 scripts/check-repo.py`.
- Functions: `cd functions && npm run lint && npm run build`. Regeln: `cd firebase/tests && npm test` (braucht Java).
- Details: `docs/CI.md`. Die App selbst baut Xcode Cloud, GitHub Actions prüft den Rest.

## Konventionen
- Quelltext-Kommentare und Commit-Nachrichten auf Englisch; Commit-Betreff beschreibt das Ergebnis für den Nutzer (z. B. „The timeline opens first under …").
- UI-Texte auf Deutsch als Schlüssel in `Localizable.xcstrings`; **jeder neue Text braucht en und fr**, sonst schlägt `check-repo.py` fehl.
- Texte im Paket `BakePlannerCore` (`String(localized:…, bundle: AppSettings.localizationBundle)`) stehen im App-Katalog `BackPlaner/Localizable.xcstrings` als manuelle Einträge (`extractionState: manual`), weil Xcode sie im App-Code nicht mehr findet; `check-repo.py` prüft das.
- Neue Swift-Dateien müssen in `project.pbxproj` eingetragen sein.
- Handbuch geändert → `python3 docs/build-manual-html.py` ausführen.
- Logik gehört nach `Utilities/` und bekommt Unit-Tests; Rechenlogik (TA, Portionen, Zeitplan, Einheiten) nie ohne Test ändern.

## Android-Portierung (geplant)
Stand und Plan: `docs/Android-Bestandsaufnahme.md`. Leitlinien:
- Weg: zuerst auf iOS die Datenschicht hinter ein Repository-Protokoll mit plattformneutralen Structs legen (Skip unterstützt Core Data auf Android nicht), dann Logik in ein Swift Package, dann Skip-Probelauf.
- Firebase bleibt das gemeinsame Backend; private Daten auf Android zunächst lokal (SQLite), Plattformwechsel über die Sicherungsdatei.
- Arbeiten in kleinen Schritten, je Schritt ein eigener Branch; alle Unit-Tests müssen nach jedem Schritt grün sein; die iOS-App darf sich für Nutzer nicht verändern.
- Nicht ohne Rückfrage: Core-Data-Modell oder CloudKit-Schema ändern, Firestore-Regeln ändern, Cloud Functions deployen, Sicherungsformat ändern.
