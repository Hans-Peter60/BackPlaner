# Android-Portierung – Übergabe

Für jeden, der an der Android-Portierung weiterarbeitet (Mensch oder KI-Agent). Ergänzt `CLAUDE.md` (Konventionen) und `docs/Android-Bestandsaufnahme.md` (Plan, Begründungen, erledigte Schritte). Stand: 31.10.2026, Branch `claude/sleepy-wozniak-9n8mxc`, zuletzt erledigt: Schritt 4e.

## Wo was liegt

| Ordner | Inhalt | Wer bindet es ein |
|---|---|---|
| `BackPlaner/` | die iOS-App (Core Data, Firebase, SwiftUI) | – |
| `BakePlannerCore/` | Swift Package: plattformneutrale Logik und Datenmodelle, Speicher-Protokolle (`RecipeStore`, `ScheduledStepStore`), Vertragsprüfungen (`StoreContracts/`), erzeugte Daten für Android (`Generated/`) | iOS-App, Widget, Android-App |
| `BakePlannerStorage/` | Swift Package: eine SQLite-Datei (`BakePlannerDatabase`) mit `SQLiteRecipeStore`, `SQLiteShoppingListStore`, `SQLiteBakeHistoryStore` und `SQLiteStarterFeedingLogStore` über SkipSQLPlus | nur die Android-App |
| `BakePlannerAndroid/` | die Android-App (Skip Fuse, nativer Modus), Paketname `de.hpm64625.bakeplanner` | – |
| `android-probe/` | Probe-Dateien aus den Skip-Probeläufen, gehört zu keinem Ziel | – |

Die iOS-App benutzt die Speicher-Protokolle noch kaum: ihre Views arbeiten weiter direkt mit Core Data (`@FetchRequest`). `CoreDataRecipeStore` gibt es, benutzt wird er bisher nur vom Import der Sicherungsdatei.

## Bauen und testen

| Was | Wie |
|---|---|
| iOS-App und alle Paket-Tests von `BakePlannerCore` | `open BackPlaner.xcodeproj`, ⌘U (Testplan `UnitTests`). Hängt der Test-Runner, anderen Simulator wählen. |
| `BakePlannerCore` allein | `cd BakePlannerCore && swift test` |
| `BakePlannerStorage` | `cd BakePlannerStorage && swift test` (Mac) und `skip android test` (Android-Emulator muss laufen) |
| Android-App bauen | `cd BakePlannerAndroid && skip android build` |
| Android-App starten | Emulator starten, `open BakePlannerAndroid/Project.xcworkspace`, Schema „BakePlanner App“, iPhone-Simulator wählen, ⌘R. Skip startet die Android-Fassung im Emulator mit. |
| Paket-Tests auf Android | `cd BakePlannerCore && skip android test` |
| Repository-Prüfung | `python3 scripts/check-repo.py` |
| Erzeugte Paketdaten auffrischen | `python3 scripts/generate-package-data.py` |

## Arbeitsweise

- Ein kleiner Schritt nach dem anderen, jeder mit Plan, Zustimmung, Umsetzung und Test durch Hans-Peter. Er baut, testet und mergt selbst nach `main`.
- Entwickelt wird auf der Branch `claude/sleepy-wozniak-9n8mxc`. Nach dem Merge wechselt er zurück auf die Branch.
- Die iOS-App darf sich für Nutzer nicht verändern. Ausnahme sind Fehlerbehebungen, denen er zugestimmt hat. Jeder Commit-Betreff endet bei reinen Umbauten auf „(no change for users)“.
- Gespräche mit Hans-Peter auf Deutsch. Code, Kommentare und Commits auf Englisch, siehe `CLAUDE.md`.
- Jeder erledigte Schritt bekommt einen Eintrag in `docs/Android-Bestandsaufnahme.md`.

## Stolpersteine, die schon einmal Zeit gekostet haben

### Xcode und Projekt
- **Immer nur ein Xcode-Projekt offen:** Ein lokales Paket kann nur ein geöffnetes Projekt laden. Ist die iOS-App offen, fehlt der Android-App `BakePlannerCore`, und umgekehrt („Missing package product“, „already opened from another project“). Zum Wechseln Xcode mit ⌘Q beenden.
- **Android-App über den Workspace öffnen:** `BakePlannerAndroid/Project.xcworkspace`, nicht `Package.swift`. Sonst sind Run und Test ausgegraut.
- **`project.pbxproj` sortiert:** Neue Einträge in den Abschnitten `PBXBuildFile` und `PBXFileReference` nach ID sortiert einfügen. Sonst sortiert Xcode beim Öffnen um, und es gibt Konflikte. Freie IDs folgen dem Muster `6AFA48xx307E000100E105F9`, zuletzt vergeben ist `…EC…`. Neue Dateien im Paket brauchen keinen Eintrag.
- **Member Import Visibility:** In der App ist `SWIFT_UPCOMING_FEATURE_MEMBER_IMPORT_VISIBILITY` an. Jede Datei, die Member eines Pakettyps benutzt, braucht `import BakePlannerCore`, auch wenn sie den Typ nicht beim Namen nennt. Deshalb importieren alle App- und App-Test-Dateien das Paket. Ausnahmen sind die generierten Core-Data-Dateien und die drei mit Widget oder Share-Extension geteilten Dateien.
- **Structs aus dem Paket:** Erweiterungen in der App dürfen Felder eines Paket-Structs nicht direkt setzen. Sie müssen `self.init(...)` aufrufen, siehe `RecipeExportData(recipe:)`.
- **Protokoll-Anforderungen** haben kein `public`, das gilt automatisch.
- **Core Data:** `managedObjectID(forURIRepresentation:)` wirft bei einer Nicht-Core-Data-URI eine Objective-C-Ausnahme. `CoreDataRecipeStore` prüft deshalb vorher das Schema `x-coredata`.
- **Konsolenmeldung „Failed to find a unique match for an NSEntityDescription“** in Tests: harmlos. Sie entsteht durch mehrere Core-Data-Speicher im Arbeitsspeicher im selben Testprozess.

### Übersetzungen
- **Texte im Paket:** `String(localized: …, bundle: AppSettings.localizationBundle)` stehen im App-Katalog `BackPlaner/Localizable.xcstrings` als `"extractionState" : "manual"`. Sonst markiert Xcode sie als veraltet. `check-repo.py` prüft das, auch bei mehrzeiligen Aufrufen und Platzhaltern.
- **Symbolerzeugung:** Xcode erzeugt für manuelle Einträge Swift-Symbole und scheitert an Schlüsseln wie „„%@““. In der App ist deshalb `STRING_CATALOG_GENERATE_SYMBOLS = NO` gesetzt.
- **Erzeugte Paketdaten:** Ändern sich diese Einträge, `unit.*`-Einträge oder `UnitSets.json`, muss `scripts/generate-package-data.py` laufen. Sonst schlägt `check-repo.py` fehl.
- **Android-Katalog:** `BakePlannerAndroid/Sources/BakePlanner/Resources/Localizable.xcstrings` hat Quellsprache Deutsch und braucht en und fr. Alle Einträge stehen auf `"extractionState" : "manual"`, denn Xcode findet die Texte im über Skip gebauten Code nicht und würde sonst jeden auf „stale“ setzen. Die Schlüssel sind sortiert wie bei Xcode (ohne Rücksicht auf Groß- und Kleinschreibung und Umlaute, „Bild ändern“ vor „Bild entfernen“), die Datei endet ohne Zeilenumbruch. Nicht mehr benutzte Schlüssel von Hand entfernen.
- **Vorhandene Übersetzungen nutzen:** Für neue Android-Texte zuerst im iOS-Katalog nachsehen, ob es den Text samt Übersetzung schon gibt, und ihn übernehmen.

### Android und Skip
- **Wie die Pakete auf Android laufen:**
  - Auf Android gibt es kein `String(localized:bundle:locale:)`. Das Paket bringt einen Ersatz mit (`PortableLocalization.swift`, nur außerhalb von Apple-Plattformen kompiliert), der aus `Generated/PackageTranslations.swift` übersetzt.
  - Es gibt dort kein `Measurement.formatted`, kein `os` und kein CoreGraphics. Imports sind mit `#if canImport` abgesichert, Temperaturen werden auf Android einfach formatiert.
  - Der Ersatz-Logger heißt `CoreLogger`, der öffentliche Typ der Log-Kanäle ist `AppLogger`. `Logger` wäre mit Skip zusammengestoßen.
  - `Bundle.main` ist auf Android nicht die App. Die Einheitentabelle kommt deshalb aus `Generated/BundledUnitSetsData.swift`.
- **SQLite:** Im nativen Modus erreicht Swift das System-SQLite von Android nicht. `BakePlannerStorage` benutzt deshalb **SkipSQLPlus** mit `configuration: .plus`.
- **SwiftUI in Skip:**
  - `@State` darf nicht `private` sein.
  - Dateien mit `@Observable` brauchen `import SkipFuse`.
  - Die Android-App verwendet die Swift-6-Sprachversion, die Pakete die Swift-5-Sprachversion.
- **Dateiauswahl:** `fileImporter` ist in Skip auf Android nur ein Platzhalter. Stattdessen `withDocumentPicker` aus **SkipKit**. Auf iOS muss man den Zugriff selbst holen (`startAccessingSecurityScopedResource`), auf Android liefert der Picker eine Kopie.
- **Dialoge:** Android schließt einen `.alert` vor der Aktion des Knopfes. Die Sichtbarkeit (`isPresented`) gehört deshalb nicht an dieselben Daten, die die Aktion braucht. Sonst sind sie beim Ausführen schon weg, siehe Löschen in `ContentView`.
- **Leiste oben:** Android zeigt nur zwei Einträge mit `placement: .primaryAction` und lässt weitere ohne Meldung weg. Mehr Aktionen gehören in ein `Menu`.
- **Bilder:** `UIImage(data:)`, `Image(uiImage:)` und `jpegData` gibt es in Skip Fuse auch auf Android. SkipKits `withMediaPicker` liefert auf Android eine `content://`-Adresse, die Swift nicht lesen kann; für Bilder deshalb `withDocumentPicker` mit `[.image]`.
- **Erinnerungen** (Probe vom 30.10.2026):
  - Es fehlen `UNNotificationAction`, Texteingabe-Aktionen und Kategorien.
  - `UNCalendarNotificationTrigger` stürzt ab, `UNTimeIntervalNotificationTrigger` funktioniert.
  - `pendingNotificationRequests()` bleibt leer, der Delegate wird nie aufgerufen.
  - Planung mit Erinnerungen braucht auf Android also eigenen Code.
- **Testdateien auf den Emulator:** per Drag & Drop ins Emulator-Fenster oder `adb push … /sdcard/Download/`. In der Dateiauswahl über ☰ → Downloads.

### Umgebung
- **Repository außerhalb von iCloud:** `~/Developer/BackPlaner`. In `~/Documents` hat iCloud Kopien mit „ 2“ im Namen angelegt (doppelte Typen) und Code-Signaturen gestört.
- **Die Sicherung der iOS-App** entsteht nur fürs Teilen-Menü, über Einstellungen → „Alle eigenen Rezepte sichern“. Auf den Mac kommt sie per AirDrop oder „In Dateien sichern“.

## Entscheidungen, die schon gefallen sind

- **Skip Fuse** (nativ), Android-App mit **eigenen Views** (Variante B), im selben Repository, Paketname `de.hpm64625.bakeplanner`.
- **Datenschicht:** SkipSQL. Zuerst nur Rezepte, die übrigen Datenarten danach.
- **Öffentliche Rezepte:** Ein öffentliches Rezept überschreibt seine eigene Kopie nicht. Geplante Schritte suchen zuerst das öffentliche Rezept (`PlannedStepSource`).
- **Texte im Paket:** Variante A, die Übersetzungen bleiben im App-Katalog.

## Offen

1. **Einkaufsliste (Schritt 5), beschlossen am 31.10.2026:**
   - **5a (erledigt, siehe Bestandsaufnahme):** Die Logik steckte in der View `BackPlaner/Views/ShoppingCartViews/ShoppingCartSelectFormView.swift`: Wasser, Salz und Anstellgut aussortieren, Komponenten-Zeilen weglassen, auf die Menge umrechnen, Eier in Stück, Namen vereinheitlichen, gleiche Zutaten zusammenfassen (auch über Einheiten), Brüche addieren. Sie kommt ins Paket (`ShoppingListBuilder`), ebenso `ShoppingListCategory`, dessen Regal-Überschriften als Erweiterung in der App bleiben. Die iOS-View ruft das Paket auf, ihr Verhalten bleibt gleich (`ShoppingListTests` grün, neue Paket-Tests).
   - **5b (erledigt, siehe Bestandsaufnahme):** `ShoppingListStore` mit Structs (Liste: Datum, Rezeptnamen, Zeilen), Vertrag, Speicher im Arbeitsspeicher, `CoreDataShoppingListStore` (Entität `ShoppingCart` mit `Ingredient`-Zeilen, Bezug zu `Recipe`, `cloudRecipeNames`).
   - **5c (erledigt, siehe Bestandsaufnahme):** `SQLiteShoppingListStore` in `BakePlannerStorage`, Vertrag auf Mac und Android.
   - **5d (erledigt, siehe Bestandsaufnahme):** Android: Reiter „Rezepte“ / „Einkaufslisten“, Listen nach Datum, Zeilen nach Regalen, Menge ändern, Zeile entfernen, Liste löschen; in der Rezeptdetailansicht „Auf die Einkaufsliste“ (neue oder bestehende Liste, gewählte Menge).
   - Nicht dabei: Übersetzung der Zutatennamen öffentlicher Rezepte (Apple-Übersetzungsdienst), Abhaken (kann die iOS-App auch nicht).
2. **Backhistorie (Schritt 6), beschlossen am 31.10.2026 (mit drittem Reiter):**
   - **Bestand:** Entität `BakeHistory` (Datum, Kommentar, Fotos als `[Data]`, Raum- und Teigtemperatur, Stück- und Stockgare in Minuten, Mehl, Ergebnis; Bezug zu `Recipe`, Rezept löschen löscht seine Einträge). Einträge entstehen von Hand (`BakeHistoryAddView`), beim Planen (`BakePlanScheduler.putIntoEffect`: Eintrag zum Backende mit Platzhalter-Kommentar, ohne `id`) und beim Planen öffentlicher Rezepte (`RecipeModel.recordPlannedBake`); dabei wird `Recipe.bakeHistoryFlag` gesetzt. Die Logik liegt schon im Paket: `BakeHistoryFacts` (Eingaben lesen, Texte, Platzhalter-Kommentar, letzter vergangener Eintrag) und `BakeHistoryTally` (Hitliste, Fotowolke).
   - **6a (erledigt, siehe Bestandsaufnahme):** `BakeHistoryStore` im Paket mit `StoredBakeHistory` (Schlüssel, Rezept-Schlüssel, Datum, Kommentar, Fotos, Fakten): alle Einträge (neueste zuerst, Fotos nur auf Wunsch), Einträge eines Rezepts, ein Eintrag, anlegen (setzt `bakeHistoryFlag` des Rezepts), ändern, löschen. Das Bereinigen der Fakten (leere Texte und 0 Minuten zählen nicht), heute im Core-Data-Setter, kommt ins Paket. Vertrag, Speicher im Arbeitsspeicher, `CoreDataBakeHistoryStore` (Schlüssel ist die Objekt-ID, weil geplante Einträge keine `id` haben). Die iOS-Views bleiben unverändert.
   - **6b (erledigt, siehe Bestandsaufnahme):** `SQLiteBakeHistoryStore` in `BakePlannerStorage`: Schema-Schritt 3 mit `bake_history` (Fremdschlüssel auf `recipe`, Löschen kaskadiert) und `bake_history_image` (Reihenfolge, JPEG). Vertrag auf Mac und Android.
   - **6c (erledigt, siehe Bestandsaufnahme):** Android: in der Rezeptansicht ein Abschnitt „Backhistorie“ (Einträge mit Datum, Fakten, Kommentar, erstem Foto; Tippen ändert, Wischen löscht mit Rückfrage) und „Eintrag hinzufügen“ (Datum, Kommentar, Fakten wie auf dem iPhone, Fotos über die Dateiauswahl als JPEG); ein dritter Reiter „Backhistorie“ mit allen Einträgen, neueste zuerst, umschaltbar auf die Hitliste.
   - **6d (erledigt, siehe Bestandsaufnahme):** Die Sicherungsdatei nimmt die Backhistorie mit, damit sie zwischen iPhone und Android wechselt. Freigegeben am 31.10.2026 (Fotos ja, auf Bildschirmgröße verkleinert; einzeln geteiltes Rezept ohne; geplante Einträge mit):
     - **Ort:** jedes Rezept in der Datei bekommt ein optionales Feld `bakeHistory` (Liste von Einträgen: Datum, Kommentar, Fotos als JPEG/Base64, Raum- und Teigtemperatur, Stock- und Stückgare in Minuten, Mehl, Ergebnis; nicht erfasste Werte fehlen). Die Einträge reisen so mit ihrem Rezept, ohne Schlüssel.
     - **Version:** `formatVersion` 2 nur für Dateien, die Backhistorie enthalten; eine Datei ohne Backhistorie bleibt Version 1 und Zeichen für Zeichen wie heute. Die App liest 1 und 2. Eine ältere App lehnt eine Datei der Version 2 mit „mit einer neueren Version erstellt“ ab, statt die Backhistorie still zu verlieren.
     - **Wann mit Backhistorie:** die Gesamtsicherung („Alle eigenen Rezepte sichern“, iPhone-Einstellungen und Android). Ein einzeln geteiltes Rezept bleibt ohne Backhistorie (persönlich, und der Empfänger kann es auch mit älterer App lesen).
     - **Einlesen:** Rezepte kommen wie heute als neue Rezepte dazu, ihre Einträge hängen an der neuen Kopie; ein Rezept mit Einträgen gilt als gebacken (`bakeHistoryFlag`). Zweimal eingelesen gibt es Rezepte und Einträge doppelt, wie heute bei den Rezepten.
     - **Umsetzung:** Format und Lesen/Schreiben im Paket (`RecipeBackup` bekommt neben dem `RecipeStore` den `BakeHistoryStore`), iOS-Einstellungen und Android-Menü nutzen es, Handbuch (DE/EN/FR) ergänzt. Tests: Rundreise mit Backhistorie in Arbeitsspeicher, Core Data und SQLite; Datei ohne Backhistorie bleibt Version 1; Version 3 wird abgelehnt.
   - Nicht dabei: Galerie und Fotowolke (später), Einträge aus der Planung (kommen mit der Planung auf Android).
3. **Anstellgut-Tagebuch (Schritt 7), beschlossen am 31.10.2026 (Abschnitt in der Rezeptansicht):**
   - **Bestand:** Entität `StarterFeedingLog` (Datum, Notiz, Reifezeit bis zum Höhepunkt in Minuten, Schwimmtest bestanden/nicht bestanden/nicht geprüft; Bezug zu `Recipe`, Rezept löschen löscht seine Fütterungen). Erfasst wird im Reiter „Anstellgut-Tagebuch“ eines Rezepts, das ein Anstellgut füttert (`StarterFeedingRatio.isStarterFeeding`), und über Siri (`LogStarterFeedingIntent`, eine Fütterung innerhalb einer Stunde zählt nicht doppelt). Ändern lässt sich ein Eintrag auf dem iPhone nicht, nur löschen. Die Logik liegt schon im Paket: `StarterFeedingFacts`, `StarterFeedingRatio` (Verhältnis aus dem Rezept, Erkennung), `StarterYieldAdjustment`.
   - **7a (erledigt, siehe Bestandsaufnahme):** `StarterFeedingLogStore` im Paket (der Name `StarterFeedingStore` ist in der App schon vergeben) mit `StoredStarterFeeding` (Schlüssel, Rezept-Schlüssel, Datum, Fakten): Fütterungen eines Rezepts (neueste zuerst), anlegen, löschen. Das Bereinigen der Fakten (0 Minuten zählt nicht, Notiz getrimmt), heute im Core-Data-Setter, kommt ins Paket. Vertrag, Speicher im Arbeitsspeicher, `CoreDataStarterFeedingLogStore`. iOS-Views und Siri bleiben unverändert.
   - **7b (erledigt, siehe Bestandsaufnahme):** `SQLiteStarterFeedingLogStore`: Schema-Schritt 4 mit `starter_feeding` (Fremdschlüssel auf `recipe`, Löschen kaskadiert; nicht Gemessenes ist NULL). Vertrag auf Mac und Android.
   - **7c (erledigt, siehe Bestandsaufnahme):** Android: in der Rezeptansicht eines Anstellgut-Rezepts ein Abschnitt „Anstellgut-Tagebuch“ wie auf dem iPhone: Fütterungsverhältnis aus dem Rezept, „Neue Fütterung erfassen“ (Datum mit Uhrzeit, Reifezeit, Schwimmtest, Notiz), „Bisherige Fütterungen“ mit Wischen zum Löschen (mit Rückfrage). Kein eigener Reiter.
   - **7d:** Die Gesamtsicherung nimmt die Fütterungen mit (Feld `starterFeedings` je Rezept, wie die Backhistorie), noch in Formatversion 2: seit Beginn der Portierung wurde nichts veröffentlicht, Version 2 ist also noch nirgends draußen.
4. **Die übrigen Speicher:** geplante Schritte. Protokoll und Vertrag in `BakePlannerCore`, Core-Data-Umsetzung in der App, SQLite-Umsetzung in `BakePlannerStorage`, nach dem Muster der Rezepte.
5. **Sicherungsdatei:** Version 2 mit Backhistorie ist umgesetzt (6d). Für Anstellgut-Tagebuch usw. später ebenso, jeweils mit neuer Formatversion und Hans-Peters Zustimmung. Offen: Fotos auf Android vor dem Sichern verkleinern (SkipUI hat dafür keine geprüfte Funktion).
6. **Später:** Planung und Erinnerungen auf Android (eigener Android-Code), Backmodus, öffentliche Rezepte über Firebase, Pro über Play Billing.
7. **Kleiner Wunsch, falls gewünscht:** eine Warnung, wenn sich zwei Pläne desselben Rezepts überschneiden. Die Plan-Prüfung vergleicht bisher nur verschiedene Rezepte.
