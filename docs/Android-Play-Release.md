# BakePlanner für Google Play – Veröffentlichung

Was für die erste Ausgabe der Android-App im Play Store vorbereitet ist, wie der Store-Build entsteht und was in der Play Console und der Firebase Console noch von Hand zu tun ist. Stand 02.11.2026. Ergänzt `docs/Android-Uebergabe.md` (Arbeitsweise, Stolpersteine) und `docs/AppStore-Beschreibung.md` (die App-Store-Texte, aus denen die Play-Texte abgeleitet sind).

## 1. Was im Repository vorbereitet ist

| Punkt | Wo | Stand |
|---|---|---|
| Version | `BakePlannerAndroid/Skip.env`: `MARKETING_VERSION = 2.2`, `CURRENT_PROJECT_VERSION = 1` (Play: versionName / versionCode) | gesetzt; vor jedem weiteren Upload `CURRENT_PROJECT_VERSION` um 1 erhöhen |
| Paketname | `de.hpm64625.bakeplanner` (`PRODUCT_BUNDLE_IDENTIFIER` in `Skip.env`) | fest, nach dem ersten Upload nicht mehr änderbar |
| App-Icon | `Android/app/src/main/res/mipmap-*/ic_launcher*.png` (Legacy-Bild, Vordergrund, schwarzer Hintergrund), `mipmap-anydpi-v26/ic_launcher.xml` | das iPhone-Icon (`BackPlaner/Assets.xcassets/AppIcon`) als adaptives Icon: Bild auf 80 % der Fläche auf dem schwarzen Rand des Bildes; ohne Monochrom-Ebene (siehe Hinweis unten) |
| Manifest | `Android/app/src/main/AndroidManifest.xml` | Berechtigungen `INTERNET`, `POST_NOTIFICATIONS`, `CAMERA`; `allowBackup="false"` (siehe unten); Sprachen je App über `xml/locales_config.xml` (de, en, fr); `targetSdk` 36, `minSdk` 28 (aus dem Skip-Plugin) |
| Release-Build | `Android/app/build.gradle.kts` | signiert mit `keystore.properties`, R8 mit `proguard-rules.pro` (`-keep class bake.planner.**`), Ressourcen geschrumpft, nicht debuggbar |
| App Check | `Android/app/src/main/kotlin/Main.kt`, `installAppCheck()` | Debug-Build: Debug-Anbieter; Release-Build: **Play Integrity** (Schritt 11f) |
| Store-Texte | `Android/fastlane/metadata/android/{de-DE,en-US,fr-FR}/` | `title.txt`, `short_description.txt` (≤ 80 Zeichen), `full_description.txt` (≤ 4000), `changelogs/1.txt`; aus den App-Store-Texten ohne Siri, Watch, Widgets, Live-Aktivität und Übersetzung auf dem Gerät |
| Datenschutz | `docs/website/privacy.html` | Zeilen für Android ergänzt (keine Cloud-Sicherung eigener Rezepte, App Check über Play Integrity); Anker `#konto-loeschen` / `#account-deletion` / `#suppression-du-compte` für die Konto-Löschung |
| Signierschlüssel | `Android/app/keystore.jks` + `Android/app/keystore.properties` | **lokal, nicht im Repository** (`.gitignore`); siehe Abschnitt 2 |

**Icon im Launcher des Emulators:** Der Launcher des Emulators (Android 17, API 37) zeichnet das Icon verkleinert in einen Kreis mit einem hellen Rand in der Farbe des Bildes – mit `@color`- wie mit Bitmap-Hintergrund gleich, die APK enthält das adaptive Icon korrekt (`aapt2 dump badging`: `res/mipmap-anydpi-v26/ic_launcher.xml`). Das ist die Darstellung dieses Launchers für Icons ohne Monochrom-Ebene; Einstellungen, Play Store und ältere Launcher zeigen das Bild formatfüllend. Wer das vermeiden will, braucht eine **Monochrom-Ebene**: eine einfarbige Silhouette (Brot mit Kalender) als Vektorgrafik, 108 dp mit Motiv in den inneren 66 dp – ein Gestaltungsauftrag, kein Code.

**Kein Android-Auto-Backup:** Android sichert pro App höchstens 25 MB in Google Drive; die Rezept- und Backfotos überschreiten das schnell, und eine Sicherung, die stillschweigend scheitert, ist schlechter als keine. Die Sicherung ist „Alle eigenen Rezepte sichern“ (Menü „Mehr“), auch für den Gerätewechsel.

## 2. Signierschlüssel

Am 02.11.2026 mit `keytool` erzeugt: `Android/app/keystore.jks`, Alias `bakeplanner-upload`, RSA 2048, 10 000 Tage; die Passwörter stehen in `Android/app/keystore.properties`. Beide Dateien liegen nur auf diesem Mac.

- **Sichern:** `keystore.jks` und `keystore.properties` an einen zweiten Ort (Passwortmanager, verschlüsseltes Laufwerk). Ohne sie lässt sich kein Update hochladen – Google kann den Upload-Schlüssel auf Antrag zurücksetzen (Play App Signing), das dauert aber Tage.
- **Play App Signing:** Google signiert die ausgelieferte App mit einem eigenen Schlüssel; der hier ist nur der Upload-Schlüssel. Beide SHA-256-Fingerabdrücke braucht Firebase (App Check, Anmeldung mit Apple):
  - Upload-Schlüssel: `keytool -list -v -keystore BakePlannerAndroid/Android/app/keystore.jks -alias bakeplanner-upload` (Passwort aus `keystore.properties`).
  - Play-App-Signing-Schlüssel: Play Console → Testen und veröffentlichen → App-Integrität → App-Signatur.
- **Neuer Mac:** Dateien kopieren, fertig; `build.gradle.kts` liest `keystore.properties` relativ zu `Android/app`.

## 3. Store-Build erzeugen

```sh
cd BakePlannerAndroid
ANDROID_HOME=$HOME/Library/Android/sdk skip export --release --no-ios -d .build/export
```

Das baut die Swift-Module für Android, transpiliert die Brückenmodule und lässt Gradle `bundleRelease` laufen; das AAB liegt danach unter `.build/export/` (Pfad siehe Ausgabe des Befehls, Abschnitt 6 unten nennt den letzten Stand). `gradle bundleRelease` direkt in `Android/` funktioniert **nicht** außerhalb des Xcode-Builds: die erzeugten Paketverweise unter `.build/plugins/outputs/…/Packages/` zeigen dann ins Leere (Stolperstein, 02.11.2026).

Vor jedem Upload:

1. `CURRENT_PROJECT_VERSION` in `Skip.env` erhöhen (Play verlangt einen höheren `versionCode`), bei einer neuen Fassung auch `MARKETING_VERSION`.
2. `python3 scripts/check-repo.py` und die Unit-Tests müssen grün sein.
3. Export wie oben; das AAB nicht umbenennen, Play liest Version und Paketname aus der Datei.

**16-KB-Seiten:** Seit November 2025 nimmt Play nur Apps mit nativen Bibliotheken an, die mit 16-KB-Speicherseiten laufen (Zielversion 35 und höher). Prüfen an einem `.so` aus dem Export: `$ANDROID_HOME/ndk/<version>/toolchains/llvm/prebuilt/darwin-x86_64/bin/llvm-readelf -l lib/arm64-v8a/libBakePlanner.so | grep LOAD` – `Align` muss `0x4000` sein, nicht `0x1000`. Ergebnis für den aktuellen Export: siehe Abschnitt 6.

## 4. Play Console – was von Hand zu tun ist

Reihenfolge wie im Dashboard der Play Console. Konto: das Google-Entwicklerkonto, mit dem auch Firebase („back-planer“) verwaltet wird.

### 4.1 App anlegen

- Name **BakePlanner**, Standardsprache **Deutsch (Deutschland)**, App (kein Spiel), kostenlos. Eine kostenlose App kann später nicht kostenpflichtig werden (In-App-Käufe gehen weiterhin).
- Paketname wird beim ersten Upload aus dem AAB übernommen.

### 4.2 Store-Eintrag („Hauptseite des Store-Eintrags“)

- **Texte:** je Sprache aus `Android/fastlane/metadata/android/<Sprache>/` (Titel, Kurzbeschreibung, Vollständige Beschreibung). Sprachen: Deutsch (de-DE), Englisch (en-US), Französisch (fr-FR).
- **App-Symbol:** 512 × 512 PNG, 32 Bit, ohne Transparenz: `sips -Z 512 BackPlaner/Assets.xcassets/AppIcon.appiconset/icon-light.png --out /tmp/play-icon.png`.
- **Funktionsgrafik:** 1024 × 500 JPG/PNG, Pflicht. **Noch zu gestalten** – Vorschlag: der Hintergrund aus `bakery-backdrop.jpg`, darauf das Icon und der Satz „Sag, wann das Brot fertig sein soll“ (Nunito ExtraBold, wie die Screenshot-Überschriften in `docs/appstore/captions.json`).
- **Screenshots:** mindestens 2, höchstens 8 je Gerätetyp, 16:9 bis 9:16, 320 bis 3840 px. Telefon ist Pflicht; 7"- und 10"-Tablet nur, wenn die App dort beworben werden soll. **Noch nicht aufgenommen** (Beschluss 02.11.2026: erst nach den Designänderungen; dieselben Motive wie `docs/AppStore-Screenshots.md`, Emulator „Medium Phone“ 1080 × 2400, `adb exec-out screencap -p`).
- **Kategorie:** App → Essen & Trinken. **Tags:** Rezepte, Kochen & Backen.
- **Kontaktdaten:** E-Mail `BakePlanner@gmx.info`, Website `https://hans-peter60.github.io/bakeplanner/`.

### 4.3 App-Inhalte (Richtlinien-Fragebogen)

| Frage | Antwort |
|---|---|
| Datenschutzerklärung | `https://hans-peter60.github.io/bakeplanner/privacy.html` |
| Werbung | Nein, die App enthält keine Werbung |
| App-Zugriff | Alle Funktionen sind ohne besondere Zugangsdaten verfügbar (die Anmeldung mit Apple ist freiwillig; Moderation ist nur für den Betreiber) |
| Inhaltsfreigabe (IARC) | Kategorie „Dienstprogramm, Produktivität, Kommunikation oder Sonstiges“; alle Fragen zu Gewalt, Sexualität, Drogen, Glücksspiel mit Nein; **nutzergenerierte Inhalte: Ja** (öffentliche Rezepte; Nutzer können melden und blockieren, siehe Handbuch Kapitel 5) → voraussichtlich USK 0 / PEGI 3 / Everyone |
| Zielgruppe und Inhalte | Altersgruppen **18 und älter** wählen (nicht „für Kinder“: sonst gelten die Family-Richtlinien; die App richtet sich an Erwachsene, auch wenn sie unbedenklich ist) |
| Nachrichten- und Nachrichten-App | Nein |
| COVID-19 | Nein |
| Finanzfunktionen | Nein |
| Staatliche Apps | Nein |
| Gesundheit | Nein |
| Löschung von Konten | Ja, die App erlaubt das Anlegen eines Kontos (Apple-Anmeldung) → Löschung **in der App** (Einstellungen → Konto → Konto löschen) und **per Link**: `https://hans-peter60.github.io/bakeplanner/privacy.html#konto-loeschen`; dort steht auch, dass veröffentlichte Rezepte auf Wunsch per E-Mail gelöscht werden |

### 4.4 Datensicherheit (Data safety)

Grundlage ist die Datenschutzerklärung. Antworten, die zur App passen:

- **Erhebt oder teilt die App Nutzerdaten?** Ja.
- **Verschlüsselt übertragen:** Ja (Firebase, TLS).
- **Löschung anfordern:** Ja (in der App und per E-Mail).
- **Datentypen:**
  - *Geräte- oder andere IDs* – die anonyme Firebase-Nutzerkennung und der App-Check-Nachweis; erhoben, nicht geteilt; Zweck App-Funktionen und Betrugsprävention/Sicherheit; nicht optional (ohne sie keine öffentlichen Rezepte).
  - *Personenbezogene Daten → E-Mail-Adresse* – nur bei freiwilliger Anmeldung mit Apple, als die Adresse, die Apple an Firebase weitergibt (oft eine Weiterleitungsadresse von Apple); optional; Zweck Kontoverwaltung. **Vor dem Ausfüllen prüfen**, ob in Firebase Console → Authentication bei angemeldeten Nutzern eine E-Mail steht; steht keine, diese Zeile weglassen.
  - *Fotos und Videos* – Rezeptbilder, die der Nutzer selbst veröffentlicht (geteilt mit anderen Nutzern) und Rezeptfotos, die er ausdrücklich an die Cloud-KI gibt; optional; Zweck App-Funktionen.
  - *App-Aktivitäten → Von Nutzern erstellte Inhalte* – veröffentlichte Rezepte und Meldungen; optional; Zweck App-Funktionen.
  - *App-Informationen und -Leistung → Absturzprotokolle, Diagnose* – **Nein**: die App bindet weder Crashlytics noch Analytics ein (nur Firebase Auth, Firestore, Storage, Functions, App Check).
- **Datenverarbeitung durch Dritte:** Google (Firebase, Vertex AI für die Cloud-KI nach Einwilligung) als Auftragsverarbeiter, wie in der Datenschutzerklärung.

### 4.5 Play Integrity und App Check (aus Schritt 11f der Übergabe)

1. Play Console → Testen und veröffentlichen → **App-Integrität** → Play Integrity API mit dem Google-Cloud-Projekt von Firebase („back-planer“) verknüpfen.
2. Firebase Console → **App Check → Apps**: bei der Android-App zusätzlich zum Debug-Anbieter **Play Integrity** registrieren; unter Projekteinstellungen → Android-App die SHA-256-Fingerabdrücke des Upload-Schlüssels **und** des Play-App-Signing-Schlüssels eintragen (die Anmeldung mit Apple braucht sie ebenfalls). Den Debug-Anbieter mit dem Emulator-Token stehen lassen, sonst geht der Debug-Build nicht mehr.
3. Erst wenn die Metriken aus dem Testtrack verifizierte Android-Anfragen zeigen, App Check für Firestore/Storage/Functions „erzwingen“. Stand 02.11.2026 ist es für Firestore **nicht** erzwungen: der Release-Build liest die öffentlichen Rezepte auch im Emulator, wo Play Integrity keinen Nachweis liefern kann. Solange das so bleibt, schützt App Check nur die Cloud Functions.

### 4.6 Interner Test, dann Produktion

1. **Interner Test**: Release anlegen, AAB hochladen, Release-Notizen aus `changelogs/1.txt`, eigene Gmail-Adresse als Tester, den Opt-in-Link auf dem Android-Telefon öffnen und die App **über Play** installieren (Play Integrity bestätigt nur, was über Play kam; eine nebenbei installierte APK bekommt keinen gültigen Nachweis).
2. Auf dem Gerät prüfen: öffentliche Rezepte laden (App Check), Anmeldung mit Apple, Planen mit Erinnerungen (Erlaubnis „Mitteilungen“), Kamera-Import, Teilen aus Chrome, PDF teilen, Sicherung schreiben und lesen, Dunkelmodus, Sprache Englisch/Französisch in den Systemeinstellungen der App.
3. **Vorabbericht** der Play Console (automatische Tests auf echten Geräten) auf Abstürze und Barrierefreiheitshinweise durchsehen.
4. Downloadgröße je Gerät in der Console nachsehen (erwartet rund 55–60 MB, siehe Übergabe „Größe der Android-App“).
5. **Produktion**: Länder wählen (zunächst Deutschland, Österreich, Schweiz, Frankreich, Belgien, Luxemburg, Großbritannien, Irland, USA, Kanada – überall, wo de/en/fr gesprochen wird; der Rest kann später dazu), Release mit demselben AAB oder einem neuen mit höherem `versionCode`, Prüfung durch Google abwarten (bei einem neuen Konto bis zu sieben Tage; neue Privatkonten brauchen vorher 14 Tage geschlossenen Test mit 12 Testern – in der Console nachsehen, ob das für dieses Konto gilt).

## 5. Entscheidungen, die noch offen sind

- **Pro / Play Billing.** Auf Android sind heute alle Funktionen frei, die auf dem iPhone zu „BakePlanner Pro“ gehören (PDF, Rezepte weitergeben, wiederkehrende Pläne, Einkaufslisten). Für die erste Ausgabe geht das als Einführungsphase; Play Billing (Einmalkauf wie im App Store, Prüfung der Belege in `proVerification.ts`) ist ein eigener Schritt von mehreren Tagen, siehe Bestandsaufnahme (Pro-Kauf). Soll der Kauf vor der ersten Ausgabe kommen, verschiebt sich die Veröffentlichung entsprechend.
- **Funktionsgrafik und Screenshots** (4.2) fehlen; ohne sie lässt sich der Store-Eintrag nicht abschicken.
- **Echtes Gerät:** der Testtrack ist nur mit einem Android-Telefon zu prüfen (Play Integrity, Kamera, Benachrichtigungen im Doze).

## 6. Letzter Export

Wird nach jedem `skip export --release` hier nachgetragen: Datum, Version, Pfad des AAB, Größe, Ergebnis der 16-KB-Prüfung.

- **02.11.2026, Version 2.2 (1):** `skip export --release --no-ios --no-export-project -d .build/export` (5 min 12 s). `BakePlannerAndroid/.build/export/BakePlanner-release.aab` (190 MB, alle Architekturen) und `BakePlanner-release.apk` (558 MB, nur zum Prüfen). `aapt2 dump badging`: `versionCode=1`, `versionName=2.2`, `targetSdkVersion=36`. Signiert mit dem Upload-Schlüssel (SHA-256 `48:32:fe:b6:a4:82:6d:36:81:9f:ab:53:a0:bd:06:16:48:c4:17:d9:db:00:a3:9a:04:3f:4a:2b:b7:30:77:d4`). 16-KB-Prüfung: `LOAD`-Segmente von `libBakePlanner.so`, `libswiftCore.so`, `libFoundation.so` mit `Align 0x4000`; `zipalign -c -P 16 -v 4` meldet „Verification successful“. Im Emulator installiert (nach Deinstallation des Debug-Builds, andere Signatur): startet, Rezeptliste mit öffentlichen Rezepten, Hintergrundfoto, Icon. Das AAB ist bereit für den internen Testtrack.
