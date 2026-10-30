# Android-Portierung: Bestandsaufnahme

Stand: 29.10.2026, Version 2.0 (Commit f3f1f0f). Grundlage: Durchsicht des Repositorys, kein Build.

## Umfang

| | |
|---|---|
| Swift-Code gesamt | ca. 42.300 Zeilen |
| App-Target | 133 Dateien, davon 57 Views (ca. 15.700 Zeilen) |
| Tests | 32 Dateien, ca. 285 Unit-Tests |
| Erweiterungen | Widgets + Live-Aktivität, Share-Extension, App Intents (Siri) |
| Server | Firebase: Firestore, Storage, Auth (anonym + Apple), App Check, Cloud Functions (TypeScript, Gemini/Vertex AI) |
| Deployment-Target | iOS 26 (App), iOS 27 (Unit-Test-Target), Swift-5-Sprachmodus |

## Die wichtigste Erkenntnis: Core Data

Die privaten Daten liegen in **Core Data mit `NSPersistentCloudKitContainer`** (9 Entitäten: Recipe, Component, Ingredient, Instruction, NextStep, BakeHistory, ShoppingCart, Item, StarterFeedingLog). `import CoreData` steht in **65 Dateien**, `@FetchRequest` 26-mal in den Views, und auch Kernlogik wie `BakePlan`, `BakePlanValidator`, `DoughComposition`, `RecurringBakePlanner` arbeitet direkt mit `NSManagedObjectContext` bzw. den Core-Data-Klassen.

**Skip unterstützt Core Data auf Android nicht** und plant das auch nicht (Objective-C-Laufzeit). Angeboten wird SkipSQL (SQLite). Das heißt: Vor jeder Portierung mit Skip muss die Datenschicht von der Logik und den Views getrennt werden. Das ist der größte Einzelposten der ganzen Portierung, bei Skip wie bei einer Kotlin-Neuentwicklung.

Guter Ansatzpunkt: Es gibt mit `RecipeExportData` / `RecipeExportIngredient` (Sicherungsformat) schon plattformneutrale Structs, und `FlourSubstitution` sowie `StarterYieldAdjustment` rechnen bereits darauf. Dieses Muster lässt sich auf die übrige Logik ausdehnen.

## Einordnung der Dateien

### Plattformneutral, direkt wiederverwendbar (nur Foundation/CoreGraphics)
`GeneralRecipeParser` (2.629 Z.), `TwoColumnRecipeParser`, `PlanTimeline`, `BakingGlossary`, `ShoppingListAmount`, `UnitLocalizer`, `StarterFeedingRatio`, `ScheduledStepComponent`, `ComponentProductMatcher`, `IngredientNameNormalizer`, `DoughTemperatureCalculator`, `PendingWebImport`, `DataService`, `IntentPhrasing`, `RecipeWebPageLoader` (URLSession, UIKit nur am Rand).
`Rational`, `FlourSubstitution`, `StarterYieldAdjustment` sind seit Schritt 1a frei von SwiftUI und Core Data. `RecipeFB` importiert noch SwiftUI (`@Observable`) – prüfen und lösen.

### Logik mit Core-Data-Kopplung (Daten-Schnittstelle nötig)
`TimedFoldExpansion`, `AdjustedRecipe`, `RecipeExport`, `RecipeModel`.

### Apple-Dienste, auf Android zu ersetzen
| iOS | Datei(en) | Android-Ersatz |
|---|---|---|
| Core Data + CloudKit | `Persistence`, `CoreData/*` | SQLite (SkipSQL/Room), lokal; Sync später über Firestore |
| UserNotifications (Aktionen, Texteingabe) | `NotificationManager` (881 Z.) | AlarmManager + Notification-Actions/RemoteInput, Berechtigung für exakte Alarme |
| Vision (Texterkennung) | `RecipeImageAnalysisAgent`, `RecipeTitleRegionPickerView` | ML Kit Text Recognition – oder nur die Cloud Function `analyzeRecipeImages` |
| FoundationModels (Apple Intelligence) | `HybridRecipeImageAnalysisAgent` | entfällt; Cloud Function `analyzeRecipeText` nutzen |
| Translation | `RecipeTranslator` | ML Kit Translation (Glossar bleibt) |
| NaturalLanguage | `RecipeLanguageDetector` | ML Kit Language ID |
| StoreKit 2 (Pro, `de.hpm64625.BackPlaner.pro`) | `ProStore`, `Entitlements` | Google Play Billing; `proVerification.ts` um Play-Kaufbelege erweitern |
| Sign in with Apple | `RecipeFBModel` (Konto verknüpfen) | Firebase Auth mit Google; Apple über Web-Flow optional |
| App Check (App Attest/DeviceCheck) | `BackPlanerApp` | App Check mit Play Integrity |
| WidgetKit, ActivityKit | `BackPlanerWidgets`, `PlanSnapshot*`, `BakeActivityManager` | Glance-Widget, laufende Benachrichtigung (Version 2) |
| App Intents / Siri | `Intents/*` | App Actions/Shortcuts (Version 2 oder weglassen) |
| Share-Extension | `BackPlanerShare` | Share-Intent im Manifest |
| PDF-Export (UIKit) | `RecipePDFExporter` | Android `PdfDocument` |
| AVFoundation (Vorlesen) | Backmodus | Android TextToSpeech |
| UIKit-Brücken | `ImagePicker`, 2× `UIViewControllerRepresentable` | Photo Picker / Compose |

### Gut übertragbar
- **Firebase** (öffentliche Rezepte, Moderation, Bilder, Cloud Functions): offizielle Android-SDKs, gleiches Backend, gleiche Regeln. `authorId` ist bereits die Firebase-UID, ein Konto über beide Plattformen ist damit möglich.
- **Cloud Functions** für den KI-Import liegen auf dem Server und können von Android unverändert aufgerufen werden.
- **Tests**: Die ~285 Unit-Tests der Rechenlogik sind das Sicherheitsnetz, damit Android exakt gleich rechnet.

## Empfohlene Reihenfolge

1. **Daten-Schnittstelle einziehen (auf iOS, ohne Android):** Plattformneutrale Modell-Structs (Ausbau von `RecipeExportData`) und ein Repository-Protokoll; Core Data wird eine Implementierung davon. Logik-Dateien schrittweise von `NSManagedObjectContext` lösen. Jeder Schritt muss alle Unit-Tests grün halten. Das verbessert auch die iOS-App und ist ohne Android-Entscheidung sinnvoll.
2. **Plattformneutrale Logik in ein Swift Package** auslagern (`BakePlannerCore`), mit den Tests.
3. **Skip-Probelauf** mit dem Package plus ein, zwei einfachen Views (z. B. Teigtemperatur-Rechner, Einkaufsliste) – zeigt, wie viel SwiftUI Skip direkt übersetzt.
4. **Entscheidung:** Skip weiter oder Kotlin/Compose mit dem Swift-Package über das Swift SDK für Android bzw. Neuschreiben der Logik.
5. **Android 1.0:** Rezepte, Planung, Erinnerungen, Backmodus, Einkaufsliste, Historie, Anstellgut-Tagebuch, öffentliche Rezepte, Pro über Play Billing. Widgets, Live-Aktivität, Siri, Watch, Apple Intelligence später oder gar nicht.

## Stand der Umsetzung

- **Schritt 1a** (Branch `claude/sleepy-wozniak-9n8mxc`): Hinweistexte (`LocalizedStringKey`) von `FlourSubstitution` und `StarterYieldAdjustment` in die zugehörigen Views verschoben; die Core-Data-Brücken `DoughComposition.components(of: Recipe)` und `Rational.ComponentDependency.from([Component])` liegen jetzt in `CoreData/CoreDataLogicAdapters.swift`. `DoughComposition`, `Rational`, `FlourSubstitution` und `StarterYieldAdjustment` importieren damit nur noch Foundation; für Sprache und Einstellungen hängen sie noch an `AppSettings`. Für Nutzer ändert sich nichts.
- **Schritt 1b:** Die Bezeichnungen von `BakeHistoryFacts.Kind` (`title`) liegen jetzt in `BakeHistoryFactsFormSection.swift`; die Core-Data-Brücken `BakeHistory.facts`/`hasNotes`, `Recipe.lastCompletedBakeHistory` und `StarterFeedingLog.facts` in `CoreDataLogicAdapters.swift`. `BakeHistoryFacts` und `StarterFeedingFacts` importieren nur noch Foundation. Für Nutzer ändert sich nichts.
- **Schritt 1c:** Alles, was beim Planen Core Data oder Erinnerungen berührt, liegt jetzt in `Utilities/BakePlanScheduler.swift`: der `BakePlanScheduler` selbst, `BakePlan.issues(in:)`, `BakePlanValidator.scheduledBakeWindows(…, in:)`, `BakePlanAdvisor.nightFreeDates(for:in:)`, aus `RecurringBakePlanner` `planDuration(of: Recipe)`, `nextStart(for:)` und `scheduleDueOccurrences`, dazu `NextStep.isVisible`. `BakePlan`, `BakePlanValidator`, `BakePlanAdvisor` und `RecurringBakePlanner` importieren nur noch Foundation. Offen: `BakePlanValidator` schreibt über `AppLog` (`os.Logger`) ins Apple-Log. Für Nutzer ändert sich nichts.
- **Schritt 1d:** Erstes Repository-Protokoll: `ScheduledStepStore` mit dem Struct `ScheduledStepData` (`Utilities/ScheduledStepStore.swift`), Core-Data-Umsetzung `CoreDataScheduledStepStore` (`CoreData/`). Die Planung (Ofenzeiten anderer Pläne, Nachtvorschläge, Plan-Prüfung, Schritte speichern, abfragen, löschen) arbeitet darüber; die Aufrufe mit `in: context` bleiben als dünne Hülle. Neue Tests in `ScheduledStepStoreTests` mit einem Speicher im Arbeitsspeicher und mit Core Data im Speicher. Noch direkt an `NextStep`: Views (`@FetchRequest`), Siri-Intents, Benachrichtigungen, Widget-Schnappschuss, `RecipeModel`. Für Nutzer ändert sich nichts.
- **Schritt 1e:** Die Regel „welcher geplante Schritt ist gerade dran“ steht einmal in `Utilities/CurrentStepRule.swift` (App und Widget) statt viermal (Widget-Schnappschuss, Siri, Hauptmenü-Karte, Backmodus); die Sichtbarkeit automatisch geplanter Schritte ist `RecurringBakePlanner.isVisible(date:isAutomaticRecurrence:at:)`, auch für `ScheduledStepData`. Tests in `CurrentStepRuleTests`. Siri-Aktionen, Benachrichtigungen und Widget-Schnappschuss bleiben bewusst iOS-only. Für Nutzer ändert sich nichts.
- **Schritt 1f (nur Tests):** `RecipePersistenceTests` hält fest, wie eigene Rezepte heute in Core Data geschrieben werden: Sicherung schreiben und lesen, Import (immer neue Rezepte, neuere Formatversion abgelehnt), angepasste Kopie (Komponenten ersetzt, Rest bleibt), Faltschritte im gespeicherten Rezept (gleich wie im Array, kein zweites Mal), Übernahme eines öffentlichen Rezepts (Felder, Gramm-Summe, zweite Übernahme lässt die eigene Kopie unverändert, siehe Fehlerbehebung unten). Sicherheitsnetz für die Rezept-Schnittstelle (1g/1h).
- **Fehlerbehebung (außerhalb der Portierung):** Ein öffentliches Rezept überschreibt seine eigene Kopie nicht mehr. Beim erneuten Planen oder Speichern gingen vorher Änderungen an der Kopie und ihre ganze Backhistorie (Notizen, Fotos, Messwerte) verloren. Der Backhistorie-Eintrag eines geplanten öffentlichen Rezepts geht jetzt direkt an die Kopie (`RecipeModel.recordPlannedBake`).
- **Schritt 1g:** Die Logik, die eigene Rezepte nur liest, rechnet auf dem Rezeptinhalt als Wert (`RecipeExportData`, auf Wunsch ohne Bild): Anstellgut-Erkennung und Fütterungsverhältnis, Komponente eines geplanten Schritts (Erinnerungen, Backmodus), PDF-Inhalt (`RecipePrintData`, jetzt in `Utilities/RecipePrintData.swift`), Plandauer. `ComponentColumn` und die Gesamtzutaten-Rechnung liegen jetzt in `Utilities/ComponentColumn.swift` statt in einer View. Die Aufrufe mit dem Core-Data-Rezept bleiben als Hülle in `CoreDataLogicAdapters.swift`. Tests in `RecipeContentTests` vergleichen mit den Fassungen für öffentliche Rezepte und mit Core Data. Für Nutzer ändert sich nichts.
- **Schritt 2a:** Die letzten App-Bausteine, an denen die Logik hing, sind geteilt. `Utilities/AppSettingsCore.swift` deklariert `AppSettings` (Sprache, Sprachpaket, generierte Texte, gespeicherte Planungswerte), `AppSettingsKeys`, `AppLanguage` und `RecipeStoragePreference` ohne SwiftUI; `AppSettings.swift` ergänzt nur noch Titel, Moderation und eigene Einheiten. `DataFiles/GlobalVariablesCore.swift` deklariert `GlobalVariables` (Einheiten, Planungswerte, Zeitraum) und `AppLog` (`os.Logger`, ohne `os` eine einfache Ausgabe); die eigenen Einheiten reicht die App beim Start über `GlobalVariables.customUnitSets` ein. `Utilities/RecipeExportFormat.swift` enthält das Sicherungsformat samt Schreiben (`encoded()`) und Lesen (`RecipeImport.decodeFile`). `AdjustedRecipe`, `TimedFoldExpansion` und `RecipeExport` haben ihre Core-Data-Teile an `CoreDataLogicAdapters.swift` bzw. `RecipeExport.swift` abgegeben. Aufrufe bleiben unverändert. Tests in `RecipeFileFormatTests`. Für Nutzer ändert sich nichts.

### Kandidaten für das Package `BakePlannerCore` (Stand nach 2a)
Alle importieren Foundation; `BakeHistoryTally`, `PlanTimeline`, `GeneralRecipeParser` und `TwoColumnRecipeParser` zusätzlich CoreGraphics (nur `CGFloat`/`CGRect`, die Foundation auf anderen Plattformen selbst mitbringt), `GlobalVariablesCore` und `DataService` `os` für das Log (mit Ersatz, wo es `os` nicht gibt).
`AppSettingsCore`, `GlobalVariablesCore`, `DataService`, `Rational`, `UnitLocalizer`, `ShoppingListAmount`, `IngredientNameNormalizer`, `ComponentProductMatcher`, `ComponentColumn`, `DoughComposition`, `DoughTemperatureCalculator`, `FlourSubstitution`, `StarterYieldAdjustment`, `StarterFeedingRatio`, `StarterFeedingFacts`, `BakeHistoryFacts`, `BakeHistoryTally`, `AdjustedRecipe`, `TimedFoldExpansion`, `RecipeExportFormat`, `RecipePrintData`, `ScheduledStepComponent`, `ScheduledStepStore`, `CurrentStepRule`, `PlanTimeline`, `BakePlan`, `BakePlanValidator`, `BakePlanAdvisor`, `RecurringBakePlanner`, `BakingGlossary`, `GeneralRecipeParser`, `TwoColumnRecipeParser`, `PendingWebImport`.
Dazu `RecipeFB.swift` (die öffentlichen Rezept-Modelle, auf die mehrere davon zugreifen): seit Schritt 2a-2 nur Foundation und `Observation`. `Bundle.main` (Einheitentabelle, Sprachpakete) bleibt im iOS-Package richtig, weil es dort die App ist; auf Android hängt die Lösung vom Weg ab.

### Skip-Probelauf (Schritt 3, vorgezogen)
`android-probe/` enthält Kopien von `DoughTemperatureCalculator`, `IngredientNameNormalizer`, `CurrentStepRule` und dem Sicherungsformat, ein `@Observable`-Modell, eine SwiftUI-Ansicht und XCTest-Tests. Der Ordner gehört zu keinem Xcode-Ziel. Anleitung in `android-probe/README.md`; das Ergebnis entscheidet, wie das Package (Schritt 2b) aussieht.

Erste Befunde (Skip 1.9.20, nativer Modus „Skip Fuse“):
- `@State private var` lässt sich nicht nach Android überbrücken; `@State` muss mindestens `internal` sein. In der App betrifft das 341 Stellen.
- Dateien mit `@Observable` brauchen `import SkipFuse`, Ansichten `import SkipFuseUI` statt `SwiftUI`; sonst treiben die Modelle die Android-Oberfläche nicht an. In der App betrifft das 5 Dateien mit `@Observable`.
- Das Skip-Projekt darf nicht in einem iCloud-synchronisierten Ordner liegen, sonst scheitert die Code-Signatur.
- Das Skip-Projekt baut im Swift-6-Sprachmodus mit strenger Nebenläufigkeitsprüfung; die App ist im Swift-5-Modus. Gemeinsam genutzte `static`-Werte nicht-`Sendable`-Typen werden abgelehnt (in der App etwa die vielen `static var` von `GlobalVariables`). Für das Package entweder den Swift-5-Modus einstellen oder diese Stellen absichern.
- Ergebnis des Laufs (iPhone-17-Pro-Simulator mit iOS 27, Android-Emulator mit API 37): Teigtemperatur, Zutatennamen-Bereinigung (reguläre Ausdrücke, Umlaute), „gerade dran“ (Datumsrechnung) und das Einlesen einer iPhone-Sicherungsdatei liefern auf Android dieselben Ergebnisse wie auf iOS. Formular, Abschnitte, Stepper, Schalter und Listen erscheinen als Android-Bedienelemente. Ein `@Observable`-Modell aktualisiert die Android-Oberfläche erst mit `import SkipFuse` in seiner Datei; ohne den Import bleibt die Anzeige stehen, während einfache `@State`-Werte funktionieren. Zahlen und Uhrzeiten folgen der Gerätesprache (Emulator auf Englisch: „8:08 AM“, „830.5“).
- Tests: `skip android test` lief auf dem Emulator (`aarch64-unknown-linux-android`) mit 11 von 11 bestandenen XCTest-Tests: dieselben Erwartungen wie in den iOS-Unit-Tests. Ein natives App-Projekt hat zunächst kein Testziel; es wird in `Package.swift` ergänzt.

### Empfehlung zu Schritt 4 (Stand 30.10.2026)
**Skip im nativen Modus („Skip Fuse“).** Die Logik läuft auf Android unverändert als Swift und besteht dieselben Tests; die SwiftUI-Ansichten werden mit mechanischen Anpassungen weiterverwendet (`@State` ohne `private`, `import SkipFuse`/`SkipFuseUI`, Swift-6-Modus oder Absicherung gemeinsam genutzter Werte). Ein Kotlin-Neubau müsste die rund 42.000 Zeilen Logik und Oberfläche ein zweites Mal schreiben und pflegen.

Offene Risiken, je mit eigenem Probelauf vor dem Bau zu klären:
| Bereich | Stand bei Skip | Einschätzung |
|---|---|---|
| Firebase (Firestore, Auth, Storage, Functions) | `skip-firebase`, leitet an das offizielle Android-SDK weiter; anonyme Anmeldung und OAuth vorhanden, Firestore-Transaktionen nicht | gut; App Check mit Play Integrity noch prüfen |
| Erinnerungen | Teile von `UserNotifications` in SkipUI überbrückt, `skip-notify` noch Platzhalter | **größtes Risiko**: exakte Weckzeiten, Aktionen mit Texteingabe, Android-Berechtigungen; vermutlich eigener Kotlin-Code (`#if SKIP`) |
| Private Daten | Core Data gibt es nicht; `skip-sql` (SQLite) | Repository-Protokolle (wie `ScheduledStepStore`) mit SQLite-Umsetzung; Umzug über die Sicherungsdatei |
| Pro-Kauf | `skip-marketplace` (StoreKit / Play Billing) | Reife unklar; prüfen, sonst eigener Kotlin-Code; `proVerification.ts` für Play-Belege erweitern |
| Texterkennung, Apple Intelligence, Übersetzung | nicht vorhanden | Cloud Functions `analyzeRecipeImages`/`analyzeRecipeText` nutzen |
| Widgets, Live-Aktivität, Siri, Watch | nicht vorhanden | für Android 1.0 weglassen |

## Offene Fragen
- Soll die Android-Version Pro als Einmalkauf über Play Billing bekommen, und gilt ein iOS-Kauf auch auf Android (dann serverseitige Prüfung über `proVerification.ts`)?
- Reicht für Android 1.0 lokale Speicherung plus Sicherungsdatei, oder ist Sync zwischen Android-Geräten Pflicht?
