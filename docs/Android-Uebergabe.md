# Android-Portierung – Übergabe

Für jeden, der an der Android-Portierung weiterarbeitet (Mensch oder KI-Agent). Ergänzt `CLAUDE.md` (Konventionen) und `docs/Android-Bestandsaufnahme.md` (Plan, Begründungen, erledigte Schritte). Stand: 31.10.2026, Branch `claude/sleepy-wozniak-9n8mxc`, zuletzt erledigt: Schritt 4e.

## Wo was liegt

| Ordner | Inhalt | Wer bindet es ein |
|---|---|---|
| `BackPlaner/` | die iOS-App (Core Data, Firebase, SwiftUI) | – |
| `BakePlannerCore/` | Swift Package: plattformneutrale Logik und Datenmodelle, Speicher-Protokolle (`RecipeStore`, `ScheduledStepStore`), Vertragsprüfungen (`StoreContracts/`), erzeugte Daten für Android (`Generated/`) | iOS-App, Widget, Android-App |
| `BakePlannerStorage/` | Swift Package: eine SQLite-Datei (`BakePlannerDatabase`) mit `SQLiteRecipeStore` und `SQLiteShoppingListStore` über SkipSQLPlus | nur die Android-App |
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
2. **Die übrigen Speicher:** Backhistorie, Anstellgut-Tagebuch, geplante Schritte. Jeweils Protokoll und Vertrag in `BakePlannerCore`, Core-Data-Umsetzung in der App, SQLite-Umsetzung in `BakePlannerStorage`, nach dem Muster der Rezepte.
3. **Wartet auf Hans-Peters Entscheidung:** Soll die Sicherungsdatei um Backhistorie, Anstellgut-Tagebuch usw. erweitert werden? Das braucht eine neue Formatversion. Laut `CLAUDE.md` nur mit seiner Zustimmung.
4. **Später:** Planung und Erinnerungen auf Android (eigener Android-Code), Backmodus, öffentliche Rezepte über Firebase, Pro über Play Billing.
5. **Kleiner Wunsch, falls gewünscht:** eine Warnung, wenn sich zwei Pläne desselben Rezepts überschneiden. Die Plan-Prüfung vergleicht bisher nur verschiedene Rezepte.
