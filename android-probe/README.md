# Skip-Probelauf für BakePlanner

Ein kleiner Versuch, ob [Skip](https://skip.tools) Logik und Ansichten aus BakePlanner nach Android bringt, ohne die App selbst anzufassen. Dieser Ordner gehört zu keinem Xcode-Ziel. Die App baut und verhält sich unverändert.

## Was drin ist

| Datei | Was sie prüft |
|---|---|
| `Sources/BakePlannerProbe/DoughTemperatureCalculator.swift` | Kopie aus der App, reine Rechnung |
| `Sources/BakePlannerProbe/IngredientNameNormalizer.swift` | Kopie, reguläre Ausdrücke (`NSRegularExpression`), Unicode, Akzente |
| `Sources/BakePlannerProbe/CurrentStepRule.swift` | Kopie, Generics, Datumsrechnung |
| `Sources/BakePlannerProbe/RecipeExportFormat.swift` | Kopie des Sicherungsformats (JSON), Fehlertexte vereinfacht |
| `Sources/BakePlannerProbe/ProbeRecipe.swift` | `@Observable`-Modell wie die öffentlichen Rezepte, dazu eine Sicherungsdatei, wie sie das iPhone schreibt |
| `Sources/BakePlannerProbe/ProbeView.swift` | SwiftUI: Formular, Stepper, Schalter, Listen, formatierte Zahlen und Uhrzeiten |
| `Tests/BakePlannerProbeTests/BakePlannerProbeTests.swift` | dieselben Erwartungen wie die Unit-Tests der App, als XCTest |

## Ablauf

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

### 3. Die Probe-Dateien hineinkopieren

Im Terminal, im BakePlanner-Ordner (den Pfad anpassen):

```bash
cp android-probe/Sources/BakePlannerProbe/*.swift ~/Developer/bakeplanner-probe/Sources/BakePlannerProbe/
```

```bash
cp android-probe/Tests/BakePlannerProbeTests/*.swift ~/Developer/bakeplanner-probe/Tests/BakePlannerProbeTests/
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
- **Tests auf beiden Plattformen**, im Ordner `~/Developer/bakeplanner-probe`:

```bash
skip test
```

### 5. Was ich zurück brauche

1. Die Ausgabe von `skip version`, und welcher Modus (nativ oder transpiliert).
2. Je einen Screenshot der Probe auf dem iPhone-Simulator und im Android-Emulator.
3. Die Ausgabe von `skip test`, vor allem die Zusammenfassung am Ende.
4. Falls etwas nicht baut: die Fehlermeldungen, als Text oder Screenshot (Xcode: Issue-Navigator, ⌘5).

### Worauf zu achten ist

- **Wassertemperatur:** Ändert sie sich sofort, wenn ein Stepper bewegt wird? Das zeigt, ob Observation und Bindungen funktionieren.
- **Zutatennamen:** Erscheinen „Wasser“ und „Hefe“ ohne Temperaturangaben, gleich wie auf dem iPhone? Das zeigt, ob die regulären Ausdrücke funktionieren.
- **Sicherungsdatei:** Die Zeile darunter sollte „Weißbrot: 1 Komponente(n), 2 Schritte, 830,5 g“ lauten, mit Komma bei deutscher Spracheinstellung.
- **Uhrzeit:** Hat „Gerade dran“ dasselbe Format wie auf dem iPhone?

Skip verlangt für geschlossene oder kommerzielle Projekte nach einer Probezeit unter Umständen eine Lizenz. Die aktuellen Bedingungen stehen auf skip.tools. Für diesen Probelauf spielt das keine Rolle.
