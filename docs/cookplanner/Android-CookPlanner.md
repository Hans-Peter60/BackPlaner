# CookPlanner auf Android

Stand 26.11.2026. Entscheidung Hans-Peter: CookPlanner kommt auch auf Android, und zwar gleich mit Pro (Play Billing), wie die iPhone-App, die erst mit dem Kauf erscheint ([CookPlanner-Pro.md](CookPlanner-Pro.md)).

## Aufbau

| Teil | Wo | Herkunft |
|---|---|---|
| App (Skip Fuse, nativ) | `Android/CookPlannerAndroid` (Modul `CookPlanner`, Paketname `de.hpm64625.cookplanner`, Android-Paket `cook.planner`) | eigene Views wie bei BakePlanner (Variante B) |
| Planer, Gerichte, Menü, Kochjahr, Pro-Entscheidung | `BakePlannerCore` (Symlink `Android/BakePlannerCore`) | geteilt mit beiden iPhone-Apps und BakePlanner Android |
| Gerichte in SQLite | `Android/CookPlannerStorage` – eigenes Manifest, die Quellen sind ein Symlink auf `CookPlanner/CookPlannerStorage/Sources/CookPlannerStorage` | dieselbe Datenbank wie auf dem iPhone (`dishes.sqlite`) |
| Texte | `Android/CookPlannerAndroid/Sources/CookPlanner/Resources/Localizable.xcstrings`, erzeugt von `scripts/cookplanner/android-catalog.py` aus den Quellen; Englisch und Französisch aus dem iPhone-Katalog | `check-repo.py` prüft, dass er aktuell und vollständig ist |
| Einstellungen | `settings.json` neben der Datenbank (`SettingsFile`), Schlüssel wie auf dem iPhone (`settings.budgetMinutes` …) | UserDefaults trägt auf Android nicht (BakePlanners Erfahrung) |

**Warum ein eigenes Manifest für den Speicher:** Skips Export verlinkt alle lokalen Pakete nebeneinander in einen Ordner `Packages`. Dort zeigt das `../../BakePlannerCore` des iPhone-Manifests ins Leere („package at …/src/main/swift/BakePlannerCore cannot be accessed“). Das Android-Manifest sagt `../BakePlannerCore`; das iPhone-Paket bleibt unverändert. Neue Quelldateien im Speicher erscheinen auf beiden Seiten von selbst; neue Abhängigkeiten gehören in beide Manifeste.

## Bauen und prüfen

- Schneller Compiler-Check: `cd Android/CookPlannerAndroid && skip android build` (Swift für Android, wenige Sekunden). Nach dem Verschieben von Paketen vorher `swift package reset`.
- APK für das Pixel: `zsh -lc 'ANDROID_HOME=$HOME/Library/Android/sdk skip export --release --no-ios --arch aarch64 -d .build/export'` (gut sechs Minuten), dann `~/Library/Android/sdk/platform-tools/adb install -r .build/export/CookPlanner-release.apk` und `adb shell am start -n de.hpm64625.cookplanner/cook.planner.MainActivity`. Ohne `Android/app/keystore.properties` signiert Gradle mit dem Debug-Schlüssel – für den Store kommt ein eigener Upload-Schlüssel (siehe unten).
- Texte: nach jeder neuen `String(localized: "…", bundle: .module)` `python3 scripts/cookplanner/android-catalog.py`; fehlt eine Übersetzung im iPhone-Katalog, meldet das Skript sie, dann en/fr von Hand in den Android-Katalog schreiben und das Skript noch einmal laufen lassen.
- **Versionen wie BakePlanner:** `Package.resolved` ist von BakePlanner Android übernommen (skip 1.9.20, skip-kit 1.1.6 …), damit beide Apps dieselben Skip-Stände nutzen. Nach `skip init` zog das Gerüst neuere Stände.
- **Sichern ohne Rückmeldung:** `withDocumentExporter` mit `onCompletion` stürzte nach dem Speichern ab (SIGTRAP in SkipBridges `Result`-Übergabe, skip-kit 1.1.6 und 1.1.7). Die App gibt deshalb keine Rückmeldung an; Androids Dialog bestätigt selbst. Mit `contentType: .data` bleibt der Name `….cookplanner`, mit `.json` hängte Android `.json` an.
- **Datum in der App-Sprache:** `Date.formatted()` folgt auf Android nicht der Gerätesprache (zeigte „at 5:22 PM“); immer `.formatted(… .locale(AppSettings.locale))`.
- **Akzentfarbe in Blättern von der Wurzel:** Ein Blatt, das an der Wurzel hängt (der wieder aufgenommene Kochmodus), liegt außerhalb von `.tint`; die Ansicht setzt die Farbe selbst.
- **Mitteilungen nur im Vordergrund neu planen:** Android lässt die App im Hintergrund weiterlaufen. Plante der Kochmodus dort jede Minute neu, schob ein nicht abgehakter Schritt die Mitteilung des nächsten immer weiter, und sie kam nie. Wie auf dem iPhone, wo die App ruht, bleiben die Mitteilungen im Hintergrund auf ihren Zeiten.
- **Zurückziehen über alle Kennungen:** `pendingNotificationRequests()` bleibt auf Android leer; `CookReminders.cancel(schedule:)` zieht jede Kennung zurück, die die Schritte des Plans haben können (`cookplanner.start.<id>`, `cookplanner.end.<id>`), auch aus einem früheren Prozess.
- **Mitteilungen prüfen:** `adb shell am broadcast -a androidx.work.diagnostics.REQUEST_DIAGNOSTICS -p de.hpm64625.cookplanner`, dann im Log `WM-DiagnosticsWrkr` – die zweite Spalte ist die Job-Nummer; `adb shell cmd jobscheduler run -f -n androidx.work.systemjobscheduler de.hpm64625.cookplanner <Nr>` löst eine sofort aus, `dumpsys notification --noredact` zeigt Titel und Text.
- **`%@` für das Katalog-Skript:** Die Markierung `/*%@*/` gehört in die Klammern der Interpolation, `\(name /*%@*/)`; dahinter stünde sie als Text in der Zeichenkette (so zeigte die erste Fassung „Wirsing/*%@*/ · jetzt dran“).
- Alle Stolpersteine von BakePlanner Android gelten auch hier ([Android-Uebergabe.md](../bakeplanner/Android-Uebergabe.md), Abschnitt „Android und Skip“): rund 80 bekannte SF-Symbole, `@State` nicht `private`, `@Observable` braucht `import SkipFuse`, Blätter mit `appSheet`, Sprache über `AppSettings.systemLocale`, `accessibilityLabel` mit `Text(…)`, kein `monospacedDigit()`.

## Schritte

| Schritt | Inhalt | Stand |
|---|---|---|
| 1 | Grundgerüst: Gerichteliste (eigene und Beispiele) mit Urteil, Plan mit Urteil, Handarbeit je Komponente und Ablauf, Einstellungen (Budget, Platten, Öfen) | erledigt 26.11., auf dem Pixel 7 geprüft |
| 2 | Gerichte anlegen, bearbeiten, löschen, ein Beispiel „Als Vorlage übernehmen“; Editor mit Zutaten und Schritten auf eigenen Seiten (Dauer, Zeitspanne, Gerät, Ofentemperatur, „Muss bald weitergehen“, Zutaten des Schritts, „Wartet auf“); Sichern aller Gerichte und Teilen eines Gerichts als `.cookplanner`-Datei über Androids „Speichern unter“, Import über die Dateiauswahl (bestehende bleiben, wie auf dem iPhone) | erledigt 26.11., auf dem Pixel 7 geprüft |
| 3 | Kochmodus: Challenge, Training, Entspannt; „Erledigt“, „Steht“ für Topf und Ofen, Rückgängig, Pause, Neuplanung jede Minute und bei jedem Haken, Bildschirm bleibt an; Lauf in `cook-run.json` (nach dem Beenden der App öffnet der nächste Start ihn wieder, bis 6 Stunden); Protokoll in `cook-runs.json` (Format des iPhones), auf dem Plan unter „Gekocht“ | erledigt 26.11., auf dem Pixel 7 geprüft |
| 3b | Mitteilungen „<Schritt> · jetzt dran“ und „<Komponente> · die Zeit ist um“ als Banner (eigener Worker `Android/app/src/main/kotlin/Reminders.kt` auf dem Kanal `cookplanner.steps` mit hoher Wichtigkeit, WorkManager-Konfiguration in `Main.kt`, Startup-Initializer im Manifest entfernt; `CookReminders.swift` folgt dem Plan, die nächsten 20); Frage nach der Erlaubnis beim Start, Hinweis, wenn sie fehlt | erledigt 26.11., auf dem Pixel 7 geprüft |
| 4a | Tab „Gekocht“: Protokolle nach Monat, Protokoll mit Sternen, Notiz, Zeiten je Schritt gegen den Plan, Löschen; „Gekocht eintragen“ ohne Stoppuhr; Sicherung „Gerichte und Protokolle sichern“ (mit Fotos, benannt nach Datum), Import übernimmt Protokolle und Fotos | erledigt 26.11., auf dem Pixel 7 geprüft |
| 4b | Einkaufsliste, Portionen | offen |
| 4c | Suche und Filter | offen |
| 4d | Fotos an Protokollen (Kamera, Dateiauswahl) | offen |
| 5 | Import aus Text und Webseiten über die Function `analyzeDishSteps` (skip-firebase) | offen, braucht Firebase (unten) |
| 6 | Pro: Play Billing über eine Kotlin-Brücke, Kaufseite, Sperren mit `KitchenProAccess`, Prüfung des Kauf-Tokens in den Functions, Promo-Codes | offen, braucht Play Console (unten) |
| 7 | Pro-Funktionen: Vorlesen (`BakePlannerSpeech`), Sprachbefehle (Android SpeechRecognizer), Plan als PDF, Kochjahr-Buch, Menü, Statistik, Sammlungen, gemessene Zeiten | offen |
| 8 | Symbol, Nunito-Schrift, Store-Texte, Bilder, Play-Veröffentlichung | offen |

Nicht auf Android (wie bei BakePlanner): iCloud-Abgleich, Live-Aktivität, Siri und Kurzbefehle, Spotlight, Wecker über AlarmKit (dafür Android-Wecker oder laute Mitteilung, in Schritt 3 zu entscheiden).

## Was Hans-Peter beisteuern muss

1. **Firebase (vor Schritt 5):** In der Firebase-Konsole im Projekt `back-planer` eine Android-App mit Paketname `de.hpm64625.cookplanner` anlegen (SHA-1/SHA-256 des Debug-Schlüssels, später des Upload-Schlüssels), `google-services.json` herunterladen und mir geben; App Check → Apps: Play Integrity und Debug-Anbieter, das Debug-Token aus dem ersten Start eintragen.
2. **Play Console (vor Schritt 6):** App „CookPlanner“ anlegen (Paketname `de.hpm64625.cookplanner`), Zahlungsprofil (setzt wie bei Apple Gewerbe und Steuernummer voraus), Einmalprodukt `pro` mit Preis; dem Dienstkonto von `play-console.py` Zugriff auf die neue App geben (Upload und Kaufprüfung).
3. **Upload-Schlüssel (vor dem ersten Upload):** ein eigener Keystore für CookPlanner, außerhalb des Repositorys, wie bei BakePlanner (`docs/bakeplanner/Android-Play-Release.md`).
