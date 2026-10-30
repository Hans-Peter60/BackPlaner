# Skip-Probelauf für BakePlanner

Ein kleiner Versuch, ob [Skip](https://skip.dev) Logik und Ansichten aus BakePlanner nach Android bringt, ohne die App selbst anzufassen. Dieser Ordner gehört zu keinem Xcode-Ziel. Die App baut und verhält sich unverändert.

## Was drin ist

| Datei | Was sie prüft |
|---|---|
| `Sources/BakePlannerProbe/ProbeRecipe.swift` | `@Observable`-Modell wie die öffentlichen Rezepte, dazu eine Sicherungsdatei, wie sie das iPhone schreibt |
| `Sources/BakePlannerProbe/ProbeView.swift` | SwiftUI über `SkipFuseUI`: Formular, Stepper, Schalter, Listen, formatierte Zahlen und Uhrzeiten |
| `Sources/BakePlannerProbe/NotificationProbeView.swift` | Erinnerungen (zweiter Lauf, siehe unten) |
| `Tests/BakePlannerProbeTests/BakePlannerProbeTests.swift` | dieselben Erwartungen wie die Unit-Tests der App, als XCTest |

Die Logik kommt seit Schritt 2b nicht mehr als Kopie, sondern aus dem Paket `BakePlannerCore` im BakePlanner-Ordner: Teigtemperatur, Zutatennamen, „welcher Schritt ist dran“ und das Sicherungsformat. Die Probe prüft damit, ob das echte Paket auf Android baut und rechnet.

## Ablauf

Die Probe ist für den nativen Modus („Skip Fuse“) geschrieben: `ProbeView` importiert `SkipFuseUI`, `ProbeRecipe` zusätzlich `SkipFuse`, und `@State` ist nicht `private`. Sie baut deshalb nur in einem Skip-Projekt.

Die Befehle von Skip ändern sich zwischen Versionen. Wo unten ein Befehl nicht passt, gilt, was `skip checkup` und `skip init --help` auf deinem Mac sagen.

### 1. Skip installieren und prüfen

```bash
brew install skiptools/skip/skip
```

```bash
skip checkup
```

`skip checkup` prüft Xcode, das Android SDK und Gradle und sagt, was fehlt. Den Hinweisen folgen, bis alles grün ist. Meist fehlt **Android Studio**. Nach der Installation einmal öffnen, die vorgeschlagenen SDK-Komponenten installieren und unter **Device Manager** einen Emulator anlegen, zum Beispiel ein aktuelles Pixel-Gerät. Den Emulator vor Schritt 4 starten.

Für den nativen Modus (siehe Schritt 2) zusätzlich:

```bash
skip android sdk install
```

### 2. Probe-Projekt anlegen, außerhalb des BakePlanner-Ordners

Nicht unter „Dokumente“ oder „Schreibtisch“ anlegen: Liegen sie in der iCloud-Synchronisierung, scheitert die Code-Signatur („CodeSign … failed“). `~/Developer` ist sicher.

```bash
skip init --help
```

Skip kennt zwei Arten:
- **nativ („Skip Fuse“):** Swift läuft kompiliert auf Android.
- **transpiliert („Skip Lite“):** Der Code wird nach Kotlin übersetzt.

Für BakePlanner ist der **native Modus** der interessantere, weil die Logik dort als echtes Swift läuft. Die Option dafür steht in der Hilfe, in neueren Versionen etwa `--native-app`. Wenn Zeit ist, lohnt sich ein zweiter Durchlauf mit dem transpilierten Modus zum Vergleich.

```bash
mkdir -p ~/Developer && cd ~/Developer
```

```bash
skip init --open-xcode --appid=de.hpm64625.BakePlannerProbe bakeplanner-probe BakePlannerProbe
```

Die Option für den nativen Modus aus der Hilfe dazuschreiben. Skip legt `~/Developer/bakeplanner-probe` an und öffnet es in Xcode.

### 3. Die Probe-Dateien hineinkopieren und das Paket einbinden

Im Terminal, im BakePlanner-Ordner (den Pfad anpassen). Stammen noch Kopien aus einem früheren Lauf im Probe-Projekt (`CurrentStepRule.swift`, `DoughTemperatureCalculator.swift`, `IngredientNameNormalizer.swift`, `RecipeExportFormat.swift`), diese dort zuerst löschen, sonst gibt es die Typen doppelt:

```bash
rm -f ~/Developer/bakeplanner-probe/Sources/BakePlannerProbe/{CurrentStepRule,DoughTemperatureCalculator,IngredientNameNormalizer,RecipeExportFormat}.swift
```

```bash
cp android-probe/Sources/BakePlannerProbe/*.swift ~/Developer/bakeplanner-probe/Sources/BakePlannerProbe/
```

Ein natives App-Projekt legt Skip ohne Testziel an. Den Ordner anlegen und die Tests hineinkopieren:

```bash
mkdir -p ~/Developer/bakeplanner-probe/Tests/BakePlannerProbeTests
```

```bash
cp android-probe/Tests/BakePlannerProbeTests/*.swift ~/Developer/bakeplanner-probe/Tests/BakePlannerProbeTests/
```

Dann `~/Developer/bakeplanner-probe/Package.swift` an drei Stellen ergänzen:

1. Unter `platforms:` die Mindestversionen auf die des Pakets anheben: `.iOS(.v26)` und `.macOS(.v15)`.
2. In der Liste `dependencies: [ … ]` des Pakets das BakePlanner-Paket eintragen, mit dem vollen Pfad deines BakePlanner-Ordners:

```swift
        .package(path: "/Users/hans-peter/Documents/Apps/BackPlaner/BakePlannerCore"),
```

3. Beim `.target(name: "BakePlannerProbe", …)` in dessen `dependencies: [ … ]` das Produkt ergänzen, und nach dem Target das Testziel:

```swift
                .product(name: "BakePlannerCore", package: "BakePlannerCore"),
```

```swift
        .testTarget(name: "BakePlannerProbeTests", dependencies: ["BakePlannerProbe"]),
```

Falls Skip die Ordner anders genannt hat, mit `ls -R ~/Developer/bakeplanner-probe/Sources ~/Developer/bakeplanner-probe/Tests` nachsehen und die passenden nehmen.

Dann in Xcode die von Skip erzeugte `ContentView.swift` öffnen und den Inhalt von `body` durch `ProbeView()` ersetzen:

```swift
var body: some View {
    ProbeView()
}
```

### 4. Laufen lassen

- **iOS und Android zusammen:** Der Android-Emulator läuft. In Xcode das iOS-Ziel auf einem Simulator starten (⌘R). Skip baut dabei die Android-Fassung mit und startet sie im Emulator. Der erste Build dauert lange, weil Gradle viel herunterlädt.
- **Tests**, im Ordner `~/Developer/bakeplanner-probe`. Auf dem Mac:

```bash
swift test
```

Und auf dem laufenden Android-Emulator:

```bash
skip android test
```

Kennt deine Skip-Version den Befehl nicht, zeigt `skip android --help` den passenden.

### 5. Was ich zurück brauche

1. Die Ausgabe von `skip version`, und welcher Modus (nativ oder transpiliert).
2. Je einen Screenshot der Probe auf dem iPhone-Simulator und im Android-Emulator.
3. Die Ausgaben von `swift test` und `skip android test`, vor allem die Zusammenfassung am Ende.
4. Falls etwas nicht baut: die Fehlermeldungen, als Text oder Screenshot (Xcode: Issue-Navigator, ⌘5).

### Worauf zu achten ist

- **Wassertemperatur:** Ändert sie sich sofort, wenn ein Stepper bewegt wird? Das zeigt, ob Observation und Bindungen funktionieren.
- **Zutatennamen:** Erscheinen „Wasser“ und „Hefe“ ohne Temperaturangaben, gleich wie auf dem iPhone? Das zeigt, ob die regulären Ausdrücke funktionieren.
- **Sicherungsdatei:** Die Zeile darunter sollte „Weißbrot: 1 Komponente(n), 2 Schritte, 830,5 g“ lauten, mit Komma bei deutscher Spracheinstellung.
- **Uhrzeit:** Hat „Gerade dran“ dasselbe Format wie auf dem iPhone?

Skip verlangt für geschlossene oder kommerzielle Projekte nach einer Probezeit unter Umständen eine Lizenz. Die aktuellen Bedingungen stehen auf skip.dev. Für diesen Probelauf spielt das keine Rolle.

## Zweiter Lauf: Erinnerungen

`NotificationProbeView.swift` prüft die Erinnerungen so, wie BakePlanner sie benutzt (`NotificationManager.swift`):
- Erlaubnis anfragen
- Erinnerung zu einer festen Uhrzeit mit Zusatzdaten
- die Aktionen „Erledigt“ und „Verschieben um …“ mit Texteingabe
- ausstehende Erinnerungen abfragen und einzeln löschen
- Rückmeldung beim Antippen einer Aktion

Die Probe-Ansicht führt über „Erinnerungen testen“ dorthin.

1. Im BakePlanner-Ordner `git pull` ausführen, dann die zwei Dateien ins Probe-Projekt kopieren:

```bash
cp android-probe/Sources/BakePlannerProbe/NotificationProbeView.swift android-probe/Sources/BakePlannerProbe/ProbeView.swift ~/Developer/bakeplanner-probe/Sources/BakePlannerProbe/
```

2. In `~/Developer/bakeplanner-probe/Android/app/src/main/AndroidManifest.xml` innerhalb von `<manifest …>` und vor `<application` ergänzen, falls noch nicht vorhanden:

```xml
<uses-permission android:name="android.permission.POST_NOTIFICATIONS"/>
<uses-permission android:name="android.permission.SCHEDULE_EXACT_ALARM"/>
```

3. ⌘R, auf beiden Geräten „Erinnerungen testen“ öffnen und die Prüfliste durchgehen:

| | Vorgehen | Zu notieren |
|---|---|---|
| A | „Erlaubnis anfragen“ | Erscheint die Systemabfrage? Was steht im Protokoll? |
| B | „Drei Erinnerungen“ antippen, App offen lassen | Kommen sie zur geplanten Minute? Steht „Im Vordergrund angekommen“ im Protokoll? |
| C | „Ausstehende anzeigen“, dann „Die 2-Minuten-Erinnerung löschen“ | Werden drei angezeigt? Kommt die gelöschte trotzdem? |
| D | „Drei Erinnerungen“ antippen, App in den Hintergrund (Home) | Kommen sie pünktlich? Sind „Erledigt“ und „Verschieben um …“ zu sehen? |
| E | iPhone: bei einer Erinnerung „Erledigt“ antippen, bei einer anderen „Verschieben um …“ mit „15“. Android: die Erinnerung selbst antippen (Aktionen gibt es dort nicht, siehe unten) | Was steht danach im Protokoll der App? |
| F | „Erinnerung in 1 Minute, dann App schließen“, App aus der App-Übersicht wegwischen | Kommt die Erinnerung trotzdem? |

Ergebnis des ersten Builds (30.10.2026): Auf Android stellt Skip `UNNotificationAction`, `UNTextInputNotificationAction`, `UNNotificationCategory` und `UNTextInputNotificationResponse` nicht bereit, und `pendingNotificationRequests()` liefert untypisierte Werte. Die Probe lässt diese Teile auf Android deshalb weg (`#if !os(Android)`).

## Dritter Lauf: das echte Paket auf Android

Seit Schritt 2b liegt die plattformneutrale Logik der App im Paket `BakePlannerCore`. Dieser Lauf prüft, ob es auf Android baut und seine Tests dort bestehen.

1. Im BakePlanner-Ordner `git pull`, dann die Schritte 3 und 4 oben wiederholen: Kopien im Probe-Projekt löschen, die Probe-Dateien kopieren, `Package.swift` um das Paket ergänzen.
2. ⌘R wie bisher: Läuft die Probe auf iPhone und Android wie beim ersten Lauf?
3. Die Tests der Probe im Probe-Ordner:

```bash
skip android test
```

4. Die Tests des Pakets selbst auf dem laufenden Android-Emulator, im Ordner `BakePlannerCore` des BakePlanner-Ordners. Der Build-Ordner muss außerhalb von iCloud liegen:

```bash
skip android test --scratch-path ~/Developer/build/BakePlannerCore-android
```

Kennt deine Skip-Version die Option `--scratch-path` nicht, zeigt `skip android test --help` die passende.

Was ich zurück brauche: die Ausgaben der beiden `skip android test`, vor allem Fehlermeldungen beim Bauen und die Zusammenfassung am Ende. Zu erwarten sind Meldungen zu Teilen, die es auf Android so nicht gibt, etwa `String(localized:bundle:)` oder `Bundle.main` (Einheitentabelle, Sprachpakete). Genau die will dieser Lauf finden.
