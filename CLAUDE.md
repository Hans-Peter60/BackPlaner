# BakePlanner (Projekt „BackPlaner")

iOS/iPadOS-App zum Planen von Brot- und Backrezepten. App-Store-Name **BakePlanner**, Bundle-Präfix `de.hpm64625.BackPlaner`. Entwickler: Hans-Peter Müller (Einzelentwickler).

## Aufbau
- `BakePlanner/` – alles, was nur zur iOS-App BakePlanner gehört: App, Widgets, Share-Extension, Watch, Tests, UI-Tests, Entitlements der Extensions und die Testpläne `UnitTests.xctestplan`/`AllTests.xctestplan`; das Projekt `BackPlaner.xcodeproj` bleibt im Wurzelordner (Xcode Cloud).
- `BakePlanner/BackPlaner/` – App-Target (SwiftUI, iOS 26+). `Views/` UI, `Utilities/` Logik und Dienste, `CoreData/` Modell, `DataFiles/` Firebase-Modelle (`RecipeFB*`), `Intents/` Siri/App Intents.
- `Android/` – alles nur für die Android-App: `BakePlannerAndroid/` (Skip-App, `skip android build`, Export für den Pixel), `BakePlannerStorage/` (SQLite), `BakePlannerSpeech/`, `BakePlannerMedia/`; `BakePlannerCore/` ist dort ein Symlink auf `../BakePlannerCore`, damit die Pakete es wie zuvor über `../BakePlannerCore` finden (Skips Export löst `../../` im generierten Paket falsch auf).
- `Android/CookPlannerAndroid/` – CookPlanner für Android (Skip Fuse, im Aufbau, Stand und Schritte in `docs/cookplanner/Android-CookPlanner.md`); `Android/CookPlannerStorage/` ist ein eigenes Manifest über den verlinkten Quellen von `CookPlanner/CookPlannerStorage`, Texte erzeugt `scripts/cookplanner/android-catalog.py`.
- `BakePlannerCore/` – lokales Swift Package mit plattformneutraler Logik und ihren Tests (Android-Portierung, im Aufbau); die App bindet es ein, die Tests laufen im Testplan `UnitTests` mit.
- `BakePlanner/BackPlanerWidgets/` – Widget und Live-Aktivität. `BakePlanner/BackPlanerShare/` – Share-Extension für den Web-Import.
- `CookPlanner/` (darin `CookPlanner/` App, `CookPlannerWidgets/`, `CookPlannerShare/`, `CookPlannerStorage/`) + `CookPlanner.xcodeproj` im Wurzelordner – zweite App „Kochen gegen die Uhr“ (Arbeitstitel, iOS, SwiftUI, Xcode-27-Projektformat `project.xcproj`), nutzt `KitchenScheduler`, `KitchenDish` und `KitchenSampleDishes` aus dem Paket; eigene Daten in `CookPlanner/CookPlannerStorage/` (SQLite über SkipSQLPlus, `swift test` dort). Stand in `docs/cookplanner/Idee-Gegen-die-Uhr.md`, TestFlight und Store-Texte in `docs/cookplanner/CookPlanner-Store.md`, Pro (Kauf `de.hpm64625.CookPlanner.pro`, Schalter `config/cookplannerMonetization`) in `docs/cookplanner/CookPlanner-Pro.md`. Der Katalog `CookPlanner/CookPlanner/Localizable.xcstrings` braucht explizite `de`-Einträge. Bauen: `xcodebuild -project CookPlanner.xcodeproj -scheme CookPlanner -destination 'id=<udid>' build`.
- `BakePlanner/BackPlanerTests/` – ca. 285 Unit-Tests (`UnitTests.xctestplan`, Standard für ⌘U). `BakePlanner/BackPlanerUITests/` – UI-Tests (`AllTests.xctestplan`).
- `functions/` – Cloud Functions (TypeScript): KI-Rezeptimport (`analyzeRecipeImages`, `analyzeRecipeText`), Pro-Prüfung (`proVerification.ts`).
- `firebase/` – Firestore- und Storage-Regeln, Regel-Tests im Emulator (`firebase/tests`).
- `docs/` – nach App getrennt: `docs/bakeplanner/` (Handbücher DE/EN/FR für iPhone und für Android `Android-*.md`, dazu CookPlanners Android-Handbücher in `docs/cookplanner/Android-*.md`; das HTML aller drei erzeugt `docs/bakeplanner/build-manual-html.py`, App-Store-Texte und -Bilder, Neuerungen, Android-Bestandsaufnahme, Ideen für 3.0 `Ideen-3.0.md`, Plan für Konto und Abgleich `Konto-und-Abgleich.md`, Pro-Einführung `Pro-Einfuehrung.md`), `docs/cookplanner/` (Idee und Stand `Idee-Gegen-die-Uhr.md`, Store-Texte, Store-Bilder); gemeinsam bleiben `docs/CI.md` und `docs/website/` (Abbild der Website, wird von Hand hochgeladen).
- `scripts/` – gemeinsam: `check-repo.py`, `generate-package-data.py`; nur BakePlanner in `scripts/bakeplanner/` (Screenshots, Play Console, Übersetzungsprüfung, Firebase-Admin), nur CookPlanner in `scripts/cookplanner/`.

## Daten
- **Private Daten:** Core Data mit `NSPersistentCloudKitContainer` (iCloud-Container `iCloud.de.hpm64625.BackPlaner`). Entitäten: Recipe, Component, Ingredient, Instruction, NextStep, BakeHistory, ShoppingCart, Item, StarterFeedingLog.
- **Öffentliche Rezepte:** Firestore + Storage. Anmeldung anonym über Firebase Auth, optional mit Apple verknüpft; `authorId` = Firebase-UID.
- **Sicherungsformat:** `RecipeExportData` / `RecipeExportIngredient` (`BakePlannerCore/Sources/BakePlannerCore/RecipeExportFormat.swift`, Core-Data-Anbindung in `Utilities/RecipeExport.swift`) – plattformneutrale Structs, auch Brücke für einen späteren Plattformwechsel. Format nicht ohne Versionierung ändern.
- **Pro:** StoreKit 2, Einmalkauf `de.hpm64625.BackPlaner.pro`; Umfang in `Utilities/ProFeature.swift`. Kern (Rezepte, Plan, Erinnerungen, Backmodus, Historie, öffentliche Rezepte, Rechner) bleibt kostenlos.

## Prüfen und Testen
- Unit-Tests: `xcodebuild test -project BackPlaner.xcodeproj -scheme BackPlaner -testPlan UnitTests -destination 'id=<udid>'` (seit CookPlanner liegen zwei Projekte im Wurzelordner, `-project` ist Pflicht). Hängt der Test-Runner beim Start, anderen Simulator nehmen (iOS 27.x).
- Repository-Prüfung (String-Kataloge en/fr vollständig, Paket-Texte und erzeugte Paketdaten aktuell, Projektdatei, Handbuch-HTML aktuell): `python3 scripts/check-repo.py`.
- Functions: `cd functions && npm run lint && npm run build`. Regeln: `cd firebase/tests && npm test` (braucht Java).
- Play Console: `python3 scripts/bakeplanner/play-console.py status|upload <AAB>` (Dienstkonto-Schlüssel außerhalb des Repos, `docs/bakeplanner/Android-Play-Release.md` Abschnitt 8).
- Details: `docs/CI.md`. Die App selbst baut Xcode Cloud, GitHub Actions prüft den Rest.

## Konventionen
- Quelltext-Kommentare und Commit-Nachrichten auf Englisch; Commit-Betreff beschreibt das Ergebnis für den Nutzer (z. B. „The timeline opens first under …").
- UI-Texte auf Deutsch als Schlüssel in `Localizable.xcstrings`; **jeder neue Text braucht en und fr**, sonst schlägt `check-repo.py` fehl.
- Ein **neuer String-Katalog** (eigenes Target oder eigene Tabelle, z. B. `Tabs.xcstrings`, `BakePlanner/BakePlannerWatch/Localizable.xcstrings`) braucht zusätzlich **explizite `de`-Einträge** (Wert = Schlüssel): Die Entwicklungsregion des Projekts ist `en`, ohne `de`-Einträge entsteht kein `de.lproj`, und ein deutsches Gerät fällt auf Englisch oder die zweite Systemsprache zurück.
- Texte im Paket `BakePlannerCore` (`String(localized:…, bundle: AppSettings.localizationBundle)`) stehen im App-Katalog `BakePlanner/BackPlaner/Localizable.xcstrings` als manuelle Einträge (`extractionState: manual`), weil Xcode sie im App-Code nicht mehr findet; `check-repo.py` prüft das.
- Für Android bringt das Paket Übersetzungen und Einheiten als erzeugte Dateien mit (`BakePlannerCore/Sources/BakePlannerCore/Generated/`). Nach Änderungen an diesen Katalogeinträgen, an `unit.*`-Einträgen oder an `UnitSets.json`: `python3 scripts/generate-package-data.py` ausführen; `check-repo.py` prüft, dass die Dateien aktuell sind.
- Neue Swift-Dateien müssen in `project.pbxproj` eingetragen sein.
- Handbuch geändert → `python3 docs/bakeplanner/build-manual-html.py` ausführen.
- Logik gehört nach `Utilities/` und bekommt Unit-Tests; Rechenlogik (TA, Portionen, Zeitplan, Einheiten) nie ohne Test ändern.

## Android-Portierung (geplant)
Stand und Plan: `docs/bakeplanner/Android-Bestandsaufnahme.md`. Wer weiterarbeitet, liest zuerst `docs/bakeplanner/Android-Uebergabe.md` (Bauen und Testen, Arbeitsweise, bekannte Stolpersteine, offene Schritte). Leitlinien:
- Weg: zuerst auf iOS die Datenschicht hinter ein Repository-Protokoll mit plattformneutralen Structs legen (Skip unterstützt Core Data auf Android nicht), dann Logik in ein Swift Package, dann Skip-Probelauf.
- Firebase bleibt das gemeinsame Backend; private Daten auf Android zunächst lokal (SQLite), Plattformwechsel über die Sicherungsdatei.
- Arbeiten in kleinen Schritten, je Schritt ein eigener Branch; alle Unit-Tests müssen nach jedem Schritt grün sein; die iOS-App darf sich für Nutzer nicht verändern.
- Nicht ohne Rückfrage: Core-Data-Modell oder CloudKit-Schema ändern, Firestore-Regeln ändern, Cloud Functions deployen, Sicherungsformat ändern.
