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
`BakePlan` (inkl. `BakePlanScheduler`), `BakePlanValidator`, `BakePlanAdvisor`, `RecurringBakePlanner`, `TimedFoldExpansion`, `AdjustedRecipe`, `RecipeExport`, `RecipeModel`.

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

## Offene Fragen
- Soll die Android-Version Pro als Einmalkauf über Play Billing bekommen, und gilt ein iOS-Kauf auch auf Android (dann serverseitige Prüfung über `proVerification.ts`)?
- Reicht für Android 1.0 lokale Speicherung plus Sicherungsdatei, oder ist Sync zwischen Android-Geräten Pflicht?
