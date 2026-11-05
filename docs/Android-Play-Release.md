# BakePlanner für Google Play – Veröffentlichung

Was für die erste Ausgabe der Android-App im Play Store vorbereitet ist, wie der Store-Build entsteht und was in der Play Console und der Firebase Console noch von Hand zu tun ist. Stand 03.11.2026 (Fortschritt in Abschnitt 7). Ergänzt `docs/Android-Uebergabe.md` (Arbeitsweise, Stolpersteine) und `docs/AppStore-Beschreibung.md` (die App-Store-Texte, aus denen die Play-Texte abgeleitet sind).

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

**Hintergrund-Lauf:** Dauert der Export länger als ein Tool-Zeitlimit, ihn aus einer Login-Shell starten (`zsh -lc` oder ein Skript, das `~/.zshrc` lädt). Aus einer nackten `nohup env ANDROID_HOME=… skip export …`-Umgebung bricht der Swift-Build mit „No Android NDK is installed at any of the standard locations“ ab (Stolperstein, 05.11.2026).

**16-KB-Seiten:** Seit November 2025 nimmt Play nur Apps mit nativen Bibliotheken an, die mit 16-KB-Speicherseiten laufen (Zielversion 35 und höher). Prüfen an einem `.so` aus dem Export: `$ANDROID_HOME/ndk/<version>/toolchains/llvm/prebuilt/darwin-x86_64/bin/llvm-readelf -l lib/arm64-v8a/libBakePlanner.so | grep LOAD` – `Align` muss `0x4000` sein, nicht `0x1000`. Ergebnis für den aktuellen Export: siehe Abschnitt 6.

## 4. Play Console – was von Hand zu tun ist

Reihenfolge wie im Dashboard der Play Console. Konto: das Google-Entwicklerkonto, mit dem auch Firebase („back-planer“) verwaltet wird.

### 4.1 App anlegen

- Name **BakePlanner**, Standardsprache **Deutsch (Deutschland)**, App (kein Spiel), kostenlos. Eine kostenlose App kann später nicht kostenpflichtig werden (In-App-Käufe gehen weiterhin).
- Paketname wird beim ersten Upload aus dem AAB übernommen.

### 4.2 Store-Eintrag („Hauptseite des Store-Eintrags“)

- **Texte:** je Sprache aus `Android/fastlane/metadata/android/<Sprache>/` (Titel, Kurzbeschreibung, Vollständige Beschreibung). Sprachen: Deutsch (de-DE), Englisch (en-US), Französisch (fr-FR).
- **App-Symbol:** 512 × 512 PNG, 32 Bit, ohne Transparenz: `docs/appstore/2.2/android/play-icon-512.png` (aus dem iPhone-Icon).
- **Funktionsgrafik:** 1024 × 500, Pflicht: `docs/appstore/2.2/android/<de|en|fr>/feature-graphic.png` – das Hintergrundfoto der App unter dem Schleier, das Icon links, Name und Satz „Sag, wann das Brot fertig sein soll.“ rechts in der Schrift der Screenshots. Erzeugt mit `swift scripts/play-feature-graphic.swift <de|en|fr> <ziel.png>`; die Texte stehen im Skript. Play nimmt je Sprache eine eigene Grafik.
- **Screenshots:** mindestens 2, höchstens 8 je Gerätetyp, 16:9 bis 9:16, 320 bis 3840 px. Telefon ist Pflicht; 7"- und 10"-Tablet nur, wenn die App dort beworben werden soll. Aufgenommen am 02.11.2026 im Emulator „Medium Phone“ (1080 × 2400) mit `adb exec-out screencap -p`, je Sprache zehn Bilder in `docs/appstore/2.2/android/<de|en|fr>/` mit denselben Motiven und Nummern wie die iPhone-Bilder (`docs/AppStore-Screenshots.md`); die Rohbilder liegen in `roh/` daneben (git-ignoriert). Die Überschriften stehen in `docs/appstore/play-captions.json` (von `captions.json` abgeleitet, ohne Apple Watch, mit der Rezeptliste als Bild 02) und werden mit `swift scripts/appstore-captions.swift docs/appstore/play-captions.json <sprache> <roh-ordner> <ziel-ordner>` über die Bilder gelegt. Für Play acht davon hochladen, Vorschlag in der Reihenfolge der Nummern 01–08. Die Sprache der App wird im Emulator mit `adb shell cmd locale set-app-locales de.hpm64625.bakeplanner --locales en-US` umgestellt; der Kalender beginnt auf Englisch sonntags, die Tipp-Positionen verschieben sich.
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

1. Play Console → **Mit Google Play geschützt** (früher „App-Integrität“) → Play Integrity API → „Jetzt loslegen“ → vorhandenes Cloud-Projekt **back-planer** verknüpfen. Die Zertifikate stehen auf derselben Seite unter „App-Signatur“ (Google Play Store-Schutz).
2. Firebase Console → **App Check → Apps**: bei der Android-App zusätzlich zum Debug-Anbieter **Play Integrity** registrieren; unter Projekteinstellungen → Android-App die SHA-256-Fingerabdrücke des Upload-Schlüssels **und** des Play-App-Signing-Schlüssels eintragen (die Anmeldung mit Apple braucht sie ebenfalls). Den Debug-Anbieter mit dem Emulator-Token stehen lassen, sonst geht der Debug-Build nicht mehr.
3. Erst wenn die Metriken aus dem Testtrack verifizierte Android-Anfragen zeigen, App Check für Firestore/Storage/Functions „erzwingen“. Stand 02.11.2026 ist es für Firestore **nicht** erzwungen: der Release-Build liest die öffentlichen Rezepte auch im Emulator, wo Play Integrity keinen Nachweis liefern kann. Solange das so bleibt, schützt App Check nur die Cloud Functions.

### 4.6 Interner Test, dann Produktion

1. **Interner Test**: Release anlegen, AAB hochladen, Release-Notizen aus `changelogs/1.txt`, eigene Gmail-Adresse als Tester, den Opt-in-Link auf dem Android-Telefon öffnen und die App **über Play** installieren (Play Integrity bestätigt nur, was über Play kam; eine nebenbei installierte APK bekommt keinen gültigen Nachweis).
2. Auf dem Gerät prüfen: öffentliche Rezepte laden (App Check), Anmeldung mit Apple, Planen mit Erinnerungen (Erlaubnis „Mitteilungen“), Kamera-Import, Teilen aus Chrome, PDF teilen, Sicherung schreiben und lesen, Dunkelmodus, Sprache Englisch/Französisch in den Systemeinstellungen der App.
3. **Vorabbericht** der Play Console (automatische Tests auf echten Geräten) auf Abstürze und Barrierefreiheitshinweise durchsehen.
4. Downloadgröße je Gerät in der Console nachsehen (erwartet rund 55–60 MB, siehe Übergabe „Größe der Android-App“).
5. **Produktion**: Länder wählen (zunächst Deutschland, Österreich, Schweiz, Frankreich, Belgien, Luxemburg, Großbritannien, Irland, USA, Kanada – überall, wo de/en/fr gesprochen wird; der Rest kann später dazu), Release mit demselben AAB oder einem neuen mit höherem `versionCode`, Prüfung durch Google abwarten (bei einem neuen Konto bis zu sieben Tage; neue Privatkonten brauchen vorher 14 Tage geschlossenen Test mit 12 Testern – in der Console nachsehen, ob das für dieses Konto gilt).

## 5. Entscheidungen, die noch offen sind

- **Pro / Play Billing – entschieden am 02.11.2026:** Android erscheint mit allen Funktionen frei („Pro-Modus“ für alle). Play Billing kommt erst, wenn auch die iPhone-App auf Pro umgestellt wird – dort schaltet das Firestore-Dokument `config/monetization` (`proRequired`, `storeVisible`) die Sperre fern, und es steht auf „frei“. Beide Plattformen bleiben so gleich; der Schritt „Pro über Play Billing“ (Bestandsaufnahme, Pro-Kauf) wartet, bis dieser Schalter umgelegt werden soll, und wird dann zusammen mit ihm gebaut.
- **Echtes Gerät:** der Testtrack ist nur mit einem Android-Telefon zu prüfen (Play Integrity, Kamera, Benachrichtigungen im Doze).

## 6. Letzter Export

Wird nach jedem `skip export --release` hier nachgetragen: Datum, Version, Pfad des AAB, Größe, Ergebnis der 16-KB-Prüfung.

- **02.11.2026, Version 2.2 (1):** `skip export --release --no-ios --no-export-project -d .build/export` (5 min 12 s). `BakePlannerAndroid/.build/export/BakePlanner-release.aab` (190 MB, alle Architekturen) und `BakePlanner-release.apk` (558 MB, nur zum Prüfen). `aapt2 dump badging`: `versionCode=1`, `versionName=2.2`, `targetSdkVersion=36`. Signiert mit dem Upload-Schlüssel (SHA-256 `48:32:fe:b6:a4:82:6d:36:81:9f:ab:53:a0:bd:06:16:48:c4:17:d9:db:00:a3:9a:04:3f:4a:2b:b7:30:77:d4`). 16-KB-Prüfung: `LOAD`-Segmente von `libBakePlanner.so`, `libswiftCore.so`, `libFoundation.so` mit `Align 0x4000`; `zipalign -c -P 16 -v 4` meldet „Verification successful“. Im Emulator installiert (nach Deinstallation des Debug-Builds, andere Signatur): startet, Rezeptliste mit öffentlichen Rezepten, Hintergrundfoto, Icon. Das AAB ist bereit für den internen Testtrack.
- **05.11.2026, Version 2.3 (2):** derselbe Befehl (8 min 10 s; der erste Lauf dauerte mehr als 10 Minuten, weil Gradle nach den vielen Änderungen seit 2.2 alles neu baute). `BakePlanner-release.aab` 192 MB, `BakePlanner-release.apk` 563 MB; `aapt2 dump badging`: `versionCode=2`, `versionName=2.3`, `targetSdkVersion=36`; Upload-Schlüssel wie oben; `libBakePlanner.so` mit `Align 0x4000`. Das APK per `adb install -r` auf dem Pixel 7 (Android 16) über die am 02.11. direkt installierte 2.2 (1) gelegt – gleiche Signatur, Daten bleiben – startet und zeigt Rezepte. Inhalt gegenüber 2.2: Rezept-Varianten, Rezept aus Text, Backtag-Vorschläge, Teigeinlage-Rechner (auch aus dem Rezept, mit Teigart aus den Zutaten), Raumtemperatur und Reifezeit im Anstellgut-Tagebuch. Das AAB ist für ein zweites Release im geschlossenen Test gedacht.

## 7. Fortschritt in der Play Console

- **03.11.2026 – Konto und App:** Entwicklerkonto „HPM BakePlanner Dev“ (Privatkonto, Google-Konto wie Firebase), Gerätebestätigung über die Play-Console-App auf einem Android-Telefon. App „BakePlanner“ mit Paketname `de.hpm64625.bakeplanner` angelegt, Store-Eintrag in de-DE, en-US, fr-FR mit Icon, Funktionsgrafik und Screenshots 01–08, App-Inhalte-Fragebogen nach Abschnitt 4.3/4.4 ausgefüllt.
- **03.11.2026 – Geschlossener Test (Alpha):** Release 1 (2.2) mit dem AAB aus Abschnitt 6 hochgeladen, Play App Signing mit von Google erzeugtem Schlüssel, Testerliste „BakePlanner Test“, Feedback `BakePlanner@gmx.info`, Land Deutschland (weitere Länder bei Bedarf nachtragen). Zur Prüfung durch Google eingereicht. **Weil das Konto ein neues Privatkonto ist, gilt die Testpflicht:** 12 Tester 14 Tage durchgehend im geschlossenen Test, erst danach Antrag auf Produktionszugang; der interne Test aus Abschnitt 4.6 entfällt, geprüft wird im Alpha-Track.
- **03.11.2026 – Play Integrity und App Check (Abschnitt 4.5):** App-Signaturschlüssel von Play (SHA-256 beginnt mit `99:55:49:75`) und Upload-Schlüssel in Firebase unter der Android-App eingetragen, zusätzlich zum Debug-Schlüssel (`3c:45:6e:31…`). In App Check ist die Android-App mit **Play Integrity** registriert (Token 1 h), Debug-Tokens bleiben. Die Play Integrity API ist in der Play Console mit dem Cloud-Projekt `back-planer` verknüpft. App Check wird weiterhin nicht erzwungen (siehe Abschnitt 4.5 Punkt 3).
- **05.11.2026 – Build 2.3 (2):** AAB exportiert (Abschnitt 6), noch nicht hochgeladen; auf dem Pixel 7 direkt per `adb` installiert.
- **Offen:** Release 2 (2.3) in den Alpha-Track hochladen, Opt-in-Link nach Freigabe an die Tester, Prüfung auf einem echten Gerät nach Abschnitt 4.6 Punkt 2–4, Produktionszugang nach den 14 Tagen, dann Produktion nach Abschnitt 4.6 Punkt 5.
