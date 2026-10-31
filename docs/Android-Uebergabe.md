# Android-Portierung – Übergabe

Für jeden, der an der Android-Portierung weiterarbeitet (Mensch oder KI-Agent). Ergänzt `CLAUDE.md` (Konventionen) und `docs/Android-Bestandsaufnahme.md` (Plan, Begründungen, erledigte Schritte). Stand: 31.10.2026, Branch `claude/sleepy-wozniak-9n8mxc`, zuletzt erledigt: Schritt 4e.

## Wo was liegt

| Ordner | Inhalt | Wer bindet es ein |
|---|---|---|
| `BackPlaner/` | die iOS-App (Core Data, Firebase, SwiftUI) | – |
| `BakePlannerCore/` | Swift Package: plattformneutrale Logik und Datenmodelle, Speicher-Protokolle (`RecipeStore`, `ScheduledStepStore`), Vertragsprüfungen (`StoreContracts/`), erzeugte Daten für Android (`Generated/`) | iOS-App, Widget, Android-App |
| `BakePlannerStorage/` | Swift Package: eine SQLite-Datei (`BakePlannerDatabase`) mit `SQLiteRecipeStore`, `SQLiteShoppingListStore`, `SQLiteBakeHistoryStore`, `SQLiteStarterFeedingLogStore` und `SQLiteScheduledStepStore` über SkipSQLPlus | nur die Android-App |
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
- **Android-Katalog:** `BakePlannerAndroid/Sources/BakePlanner/Resources/Localizable.xcstrings` hat Quellsprache Deutsch und braucht en und fr. Alle Einträge stehen auf `"extractionState" : "manual"`, denn Xcode findet die Texte im über Skip gebauten Code nicht und würde sonst jeden auf „stale“ setzen. Die Schlüssel sind sortiert wie bei Xcode (ohne Rücksicht auf Groß- und Kleinschreibung und Umlaute, „Bild ändern“ vor „Bild entfernen“), die Datei endet ohne Zeilenumbruch. Nicht mehr benutzte Schlüssel von Hand entfernen. Xcode erzeugt aus den Schlüsseln Swift-Symbole: Zwei Schlüssel, die sich nur in Satzzeichen, Groß- und Kleinschreibung oder Umlauten unterscheiden („Geplante Schritte löschen“ und „… löschen?“), brechen den Build; dann einen anderen Text nehmen. `TextField("", …)` legt einen leeren Schlüssel an, deshalb Eingabefeldern immer eine Bezeichnung geben. Die Katalogversion ist „1.3“.
- **Sprache im Paket:** In nativem Swift folgt `Locale.current` auf Android nicht der Gerätesprache. Die Android-App reicht deshalb die Sprache aus `@Environment(\.locale)` an `AppSettings.systemLocale` weiter (`ContentView`); das Paket nimmt sie überall, wo keine Sprache in der App gewählt ist (erzeugte Plan-Schritte, Plan-Hinweise, Datumsformate, Paket-Texte). Nie `Locale.current` direkt im Paket verwenden, sondern `AppSettings.locale`.
- **Erinnerungen auf Android:** Angezeigt werden sie von `ReminderWorker` in `Android/app/src/main/kotlin/Reminders.kt`, nicht von SkipUIs Worker (der zeigt keine Einblendung). Benennt Skip `skip.ui.NotificationWorker` oder dessen Eingabedaten („title“, „body“, „id“) um, muss `ReminderWorkerFactory` mitziehen.
- **CGFloat/CGSize in der Android-App:** Auf Android definieren Foundation und SkipFuseUI beide `CGFloat`, `CGSize`, `CGPoint`; den Typnamen hinzuschreiben ist dort mehrdeutig und bricht den Build. In `Double` rechnen und den Typ ableiten lassen (`.init(…)`), siehe `PhotoShrinker.swift`. Fehler der Android-Seite zeigt am deutlichsten `skip android build` im Ordner `BakePlannerAndroid`.
- **Hinweis-Dialoge mit nur einem Knopf:** Hat ein `.alert` nur einen Knopf mit `role: .cancel`, zeigt Skip auf Android zwei „OK“. Den einzigen Knopf ohne Rolle anlegen.
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
   - **Bestand:** Entität `StarterFeedingLog` (Datum, Notiz, Reifezeit bis zum Höhepunkt in Minuten, Schwimmtest bestanden/nicht bestanden/nicht geprüft; Bezug zu `Recipe`, Rezept löschen löscht seine Fütterungen). Erfasst wird im Reiter „Anstellgut-Tagebuch“ eines Rezepts, das ein Anstellgut füttert (`StarterRecipe.isStarterFeeding`), und über Siri (`LogStarterFeedingIntent`, eine Fütterung innerhalb einer Stunde zählt nicht doppelt). Ändern lässt sich ein Eintrag auf dem iPhone nicht, nur löschen. Die Logik liegt schon im Paket: `StarterFeedingFacts`, `StarterFeedingRatio` (Verhältnis aus dem Rezept, Erkennung), `StarterYieldAdjustment`.
   - **7a (erledigt, siehe Bestandsaufnahme):** `StarterFeedingLogStore` im Paket (der Name `StarterFeedingStore` ist in der App schon vergeben) mit `StoredStarterFeeding` (Schlüssel, Rezept-Schlüssel, Datum, Fakten): Fütterungen eines Rezepts (neueste zuerst), anlegen, löschen. Das Bereinigen der Fakten (0 Minuten zählt nicht, Notiz getrimmt), heute im Core-Data-Setter, kommt ins Paket. Vertrag, Speicher im Arbeitsspeicher, `CoreDataStarterFeedingLogStore`. iOS-Views und Siri bleiben unverändert.
   - **7b (erledigt, siehe Bestandsaufnahme):** `SQLiteStarterFeedingLogStore`: Schema-Schritt 4 mit `starter_feeding` (Fremdschlüssel auf `recipe`, Löschen kaskadiert; nicht Gemessenes ist NULL). Vertrag auf Mac und Android.
   - **7c (erledigt, siehe Bestandsaufnahme):** Android: in der Rezeptansicht eines Anstellgut-Rezepts ein Abschnitt „Anstellgut-Tagebuch“ wie auf dem iPhone: Fütterungsverhältnis aus dem Rezept, „Neue Fütterung erfassen“ (Datum mit Uhrzeit, Reifezeit, Schwimmtest, Notiz), „Bisherige Fütterungen“ mit Wischen zum Löschen (mit Rückfrage). Kein eigener Reiter.
   - **7d (erledigt, siehe Bestandsaufnahme):** Die Gesamtsicherung nimmt die Fütterungen mit (Feld `starterFeedings` je Rezept, wie die Backhistorie), noch in Formatversion 2: seit Beginn der Portierung wurde nichts veröffentlicht, Version 2 ist also noch nirgends draußen.
   - **7e (erledigt, siehe Bestandsaufnahme): Ein Anstellgut wird gefüttert, nicht gebacken** (Wunsch Hans-Peter, 31.10.2026; Reiter „Füttern“, Text des letzten Schritts wie vorgeschlagen):
     - **Paket und Speicher:** `StarterFeedingLogStore` bekommt `update` (Ergebnis nachtragen: Reifezeit, Schwimmtest, Notiz; Datum bleibt), Vertrag erweitert, Core Data und SQLite (ohne Schemaänderung). Rhythmus-Regel im Paket: bei einem Anstellgut zählt der Rhythmus vom Beginn der letzten Fütterung.
     - **iPhone:** Planen eines Anstellguts (von Hand, öffentliches Rezept, automatischer Rhythmus) legt statt des Backhistorie-Eintrags einen Fütterungs-Eintrag zum **Beginn** des Plans an (noch ohne Ergebnis). Im Anstellgut-Tagebuch erscheint er als „geplant“, solange er in der Zukunft liegt; Antippen eines Eintrags öffnet „Ergebnis eintragen“ (Reifezeit, Schwimmtest, Notiz). Der letzte Plan-Schritt heißt bei einem Anstellgut nicht „Backvorgang ist beendet“, sondern lädt zum Eintragen des Ergebnisses ein. Siri „gefüttert“ innerhalb einer Stunde nach dem geplanten Beginn zählt wie bisher als dieselbe Fütterung. Beschriftungen im Reiter „Backen“ eines Anstellguts sprechen vom Füttern (neue Texte mit en/fr).
     - **Android:** Fütterungs-Einträge lassen sich antippen und das Ergebnis nachtragen; das Planen selbst kommt mit 8c.
     - **Bestand:** Anstellgut-Rezepte mit alten (ausgeblendeten) Backhistorie-Einträgen: der Rhythmus nimmt den jüngeren Zeitpunkt von letzter Fütterung und altem Eintrag, damit ein laufender Rhythmus nicht springt.
4. **Planen und geplante Schritte (Schritt 8), beschlossen am 31.10.2026 (vierter Reiter „Zeitleiste“, Pläne nicht in der Sicherung):**
   - **Bestand:** Entität `NextStep` (Rezeptname als Text, kein Bezug auf `Recipe`; Plan-ID, Schritt, Anweisung, Datum, Startzeit, Dauer, Menge, automatisch aus dem Rhythmus). Ein Rezept hat höchstens einen Plan; neu planen ersetzt ihn. Geplant wird in der Backansicht (`InstructionsView`: Plan aus dem Paket, Prüfung auf Nacht und belegten Ofen, Vorschläge); `BakePlanScheduler.putIntoEffect` legt Erinnerungen, die Schritte und den Backhistorie-Eintrag an. Die Schritte lesen und ändern: Zeitleiste, Planliste, Schritt verschieben (mit den folgenden), Backmodus, Karte „Nächster Schritt“, Widget und Live-Aktivität (`PlanSnapshot`), Siri (`PlannedStepIntents`: aktueller Schritt, erledigt, verschieben), automatischer Rhythmus (`RecurringBakePlanner`). Die Planungslogik liegt im Paket (`BakePlan`, `BakePlanValidator`, `BakePlanAdvisor`, `PlanTimeline`, `RecurringBakePlanner`, `CurrentStepRule`); `ScheduledStepStore` gibt es schon mit fünf Abfragen, umgesetzt in Core Data, ein Speicher im Arbeitsspeicher liegt in den App-Tests.
   - **8a (erledigt, siehe Bestandsaufnahme; Verschieben folgt später):** `ScheduledStepStore` um das erweitern, was die Ansichten brauchen: alle Schritte nach Datum, die eines Plans, einen Schritt erledigen (löschen), einen Plan löschen, Schritte verschieben (die Regel aus `PlannedStepStore.shiftedDate` ins Paket). Jeder Schritt bekommt einen Speicher-Schlüssel (alte Schritte haben keine `id`). Speicher im Arbeitsspeicher aus den App-Tests ins Paket, Vertrag, `CoreDataScheduledStepStore` erfüllt ihn. Die iOS-Views bleiben unverändert.
   - **8b (erledigt, siehe Bestandsaufnahme):** `SQLiteScheduledStepStore`: Schema-Schritt 5 mit `scheduled_step`. Vertrag auf Mac und Android.
   - **8c (erledigt, siehe Bestandsaufnahme):** Android: „Planen“ in der Rezeptansicht (Backende oder Beginn wählen, gewählte Menge; Hinweise auf Nacht und belegten Ofen, Vorschläge wie auf dem iPhone), der Plan ersetzt einen früheren; ein Backrezept bekommt den Backhistorie-Eintrag zum Backende, ein Anstellgut keinen. Ein vierter Reiter „Zeitleiste“ mit den kommenden Schritten nach Plan, Schritt erledigen, Plan löschen.
   - **8d: Erinnerungen auf Android.** Ergebnis der Prüfung (31.10.2026, Quellen: skip-ui und skip-fuse-ui auf GitHub, Stand 28.10.2026): SkipFuseUI bringt `UNUserNotificationCenter` auch im nativen Modus mit (`requestAuthorization`, `add`, `pendingNotificationRequests`, `removePendingNotificationRequests`, Delegate; Auslöser `UNTimeIntervalNotificationTrigger` und `UNCalendarNotificationTrigger`, ausgewertet wird nur das nächste Auslösedatum). Zugestellt wird über WorkManager (`OneTimeWorkRequest` mit Verzögerung), nicht über genaue Wecker: ist das Telefon lange unbenutzt (Doze), kann eine Erinnerung verspätet kommen. Nicht unterstützt: Aktionen an der Benachrichtigung (auf dem iPhone „Erledigt“/„Verschieben“), Ton- und Kategorie-Einstellungen. Android 13+ braucht die Erlaubnis `POST_NOTIFICATIONS` (im Manifest eintragen, beim ersten Planen erfragen). Für das Symbol in der Statusleiste erwartet Skip ein weißes, freigestelltes Bild `ic_notification` in den Android-Ressourcen.
     - **8d-1 (erledigt, siehe Bestandsaufnahme):** Beim Planen je künftigem Schritt eine Benachrichtigung wie auf dem iPhone (Titel „Backhinweis“, Text: Anweisung und Zutaten der Komponente), Kennung aus der Schritt-ID; „Erledigt“, „Plan löschen“ und „Plan ersetzen“ nehmen die zugehörigen Erinnerungen zurück. Erlaubnis beim ersten Planen; ohne Erlaubnis bleibt der Plan, die Zeitleiste sagt es. Symbol `ic_notification` als Vektorgrafik. Antippen öffnet die App.
     - **Später möglich, 8d-2:** genaue Wecker (`AlarmManager`, Erlaubnis „Wecker und Erinnerungen“) über eigenen Kotlin-Code, falls die Verspätungen stören.
   - **8e: Schritt verschieben** (beschlossen am 31.10.2026; iOS bleibt vorerst bei seiner eigenen Abfrage):
     - **Bestand iOS:** In der Liste der nächsten Schritte öffnet „Schritt verschieben“ ein Blatt (`ScheduledTasksView`): Minuten (höchstens 1440), „Früher“/„Später“, „Nur dieser Schritt“/„Alle nachfolgenden“, dazu „Bisher“ und „Neu“. Der neue Zeitpunkt muss in der Zukunft liegen. Nachfolger sind die Schritte desselben Plans (gleiche Plan-ID, bei alten Schritten ohne ID derselbe Rezeptname), die später liegen oder in derselben Minute mit höherer Schrittnummer (`NotificationActions.followingStepsPredicate`; so geht „Backvorgang ist beendet“ mit, ein Backofen-Schritt in derselben Minute nicht). Die Erinnerungen werden mitverschoben. Tests: `ScheduledStepShiftTests` (u. a. der frühere Fehler, dass eine Ruhezeit doppelt verschoben wurde).
     - **8e-1 (erledigt, siehe Bestandsaufnahme):** Die Regel als reine Logik ins Paket (`ScheduledStepShift`: welche Schritte mitgehen, wohin sie kommen, Fehler bei einem Zeitpunkt in der Vergangenheit), mit den Fällen aus `ScheduledStepShiftTests` als Paket-Tests. `ScheduledStepStore` bekommt `setDates` (neue Zeitpunkte je Schlüssel, in einem Zug), Vertrag erweitert, Speicher im Arbeitsspeicher, Core Data und SQLite (ohne Schemaänderung). Die iOS-Views und die Siri-Kurzbefehle bleiben unverändert.
     - **8e-2 (erledigt, siehe Bestandsaufnahme):** In der Zeitleiste öffnet Antippen eines Schritts das Blatt „Schritt verschieben“ wie auf dem iPhone (Texte aus dem iOS-Katalog). Verschoben werden die Schritte im Speicher und ihre Erinnerungen (gleiche Kennung, neuer Zeitpunkt; vergangene werden nicht neu gesetzt).
   - **8f: Automatischer Rhythmus** (beschlossen am 31.10.2026; auf Android bis Play Billing ohne Pro-Sperre):
     - **Bestand iOS:** Ein Rezept bekommt im Bearbeiten „Regelmäßig planen“ bzw. bei einem Anstellgut „Regelmäßig auffrischen“ mit „alle N Tage“ (1–60, Vorgabe 5; `recurrenceIntervalDays`, steht schon in der Sicherungsdatei) und darunter den nächsten Termin. Die Rezeptansicht zeigt „Nächste Fütterung …“ bzw. „Nächster Backtermin …“ (`NextFeedingView`). Jedes Mal, wenn die App in den Vordergrund kommt, plant `RecurringBakePlanner.scheduleDueOccurrences` jedes Rezept mit Rhythmus ein, das Schritte hat, einen Bezugspunkt (letzter Backhistorie-Eintrag bzw. letzte Fütterung, `rhythmFinish`) und keinen offenen Plan: nächster Beginn im Rhythmus nach jetzt, ab Beginn geplant, bei Konflikt mit einem anderen Plan ausgelassen, mit der Standard-Menge aus den Einstellungen; die Schritte sind als automatisch markiert und erscheinen erst zwei Tage vorher. Im Hintergrund läuft nichts. Auf dem iPhone ist der Rhythmus Pro.
     - **8f-0 (erledigt, siehe Bestandsaufnahme):** Die Vorschau im Bearbeiten misst noch vom letzten Backhistorie-Eintrag; bei einem Anstellgut muss sie wie die Rezeptansicht von der letzten Fütterung messen (`RecurringBakePlanner.rhythmFinish(of:)`). Ohne Bezugspunkt heißt es bei einem Anstellgut „nach der ersten Fütterung“ statt „nach dem ersten Backen“ (neuer Text, en/fr).
     - **8f-1 (erledigt, siehe Bestandsaufnahme):** Die Auswahl, welches Rezept jetzt fällig ist und mit welchem Plan (`RecurringBakePlanner.dueOccurrences`: Rezepte, Bezugspunkte, Schritt-Speicher, jetzt → Rezept und `BakePlan`), als reine Logik ins Paket, mit Tests. Die iOS-App behält vorerst ihren eigenen Durchlauf.
     - **8f-2 (erledigt, siehe Bestandsaufnahme):** Im Rezept-Editor „Regelmäßig planen“/„Regelmäßig auffrischen“ mit „alle N Tage“; in der Rezeptansicht der nächste Termin; beim Wechsel in den Vordergrund der Durchlauf wie auf dem iPhone (Schritte, Erinnerungen, Backhistorie-Eintrag bzw. Fütterung). Texte aus dem iOS-Katalog.
     - **Später möglich, 8f-3:** Durchlauf auch ohne Öffnen der App (WorkManager, täglich) – auf Android machbar, aber aufwendig, weil ein Kotlin-Worker die Swift-Logik aufrufen müsste.
   - Später: Backmodus, Widget.
   - Nicht in der Sicherungsdatei: Pläne sind kurzlebig und an die Erinnerungen des Geräts gebunden.
5. **Anstellgut und Backhistorie:** Seit dem 31.10.2026 legt das Planen eines Anstellguts (eigenes oder öffentliches Rezept, auch im Rhythmus) keinen Backhistorie-Eintrag mehr an und markiert es nicht als gebacken. Einträge, die frühere Versionen dafür angelegt haben, bleiben gespeichert, werden aber nicht angezeigt (Backhistorie, Hit-Liste, Fotowolke, „Letztes Mal“, „Bisherige Backvorgänge“; auf Android im Reiter Backhistorie), Entscheidung Hans-Peter. Der Rhythmus eines Anstellguts misst seit 7e von der letzten Fütterung.
6. **Sicherungsdatei:** Version 2 mit Backhistorie (6d) und Anstellgut-Tagebuch (7d) ist umgesetzt. Für Anstellgut-Tagebuch usw. später ebenso, jeweils mit neuer Formatversion und Hans-Peters Zustimmung.
   - **Schritt 9: Fotos auf Android verkleinern** (erledigt, 9a und 9b, siehe Bestandsaufnahme). Befund: SkipFuseUI hat auch im nativen Modus `UIImage.preparingThumbnail(of:)` (auf Android `Bitmap.createScaledBitmap`), dazu `UIImage(data:)`, `size`, `scale` und `jpegData` – das reicht, ohne Kotlin.
     - **9a:** Eine Funktion in der Android-App wie `BackupPhoto.shrunk` auf dem iPhone: höchstens 2048 Pixel an der längeren Seite, JPEG 0,8; kleinere Bilder und Daten, die kein Bild sind, bleiben unverändert. Benutzt beim Sichern für die Fotos der Backhistorie (wie auf dem iPhone).
     - **9b (Vorschlag):** Zusätzlich gleich beim Auswählen verkleinern – Rezeptbild und Fotos der Backhistorie –, weil Android die Bilder in der SQLite-Datei hält und ein Kamerafoto mehrere MB hat. Auf dem iPhone bleiben die Originale (iCloud), dort ändert sich nichts.
     - **Zu prüfen:** Android liest beim Dekodieren die EXIF-Drehung nicht; ein hochkant aufgenommenes Foto kann nach dem Neukodieren liegen. Das gilt schon heute (die Auswahl kodiert neu als JPEG); bei Bedarf eigener Schritt.
7. **Später:** Planung und Erinnerungen auf Android (eigener Android-Code), Backmodus, öffentliche Rezepte über Firebase, Pro über Play Billing.
8. **Kleiner Wunsch, falls gewünscht:** eine Warnung, wenn sich zwei Pläne desselben Rezepts überschneiden. Die Plan-Prüfung vergleicht bisher nur verschiedene Rezepte.
