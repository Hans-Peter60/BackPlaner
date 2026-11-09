# App-Store-Screenshots

Die Bilder für App Store Connect entstehen automatisch im Simulator, auf dem Mac:

```sh
scripts/appstore-screenshots.sh
```

Das Skript baut die App einmal, lässt den UI-Test `AppStoreScreenshots` auf drei Simulatoren in drei Sprachen laufen (iPhone, iPad, iPhone Duo zugeklappt und aufgeklappt) und setzt anschließend über jedes Bild eine Überschrift (`scripts/appstore-captions.swift`, Texte in `docs/appstore/captions.json`). Ergebnis:

```
docs/appstore/2.2/iphone-6.9/de/01-rezept-backen.png … 10-teigtemperatur.png   (mit Überschrift, für den Store)
docs/appstore/2.2/iphone-6.9/de/roh/…                                          (ohne Überschrift, nicht in git)
docs/appstore/2.2/iphone-6.9/en/…, fr/…
docs/appstore/2.2/ipad-13/de/…  (en, fr)
docs/appstore/2.2/iphone-duo-outer/de/…  (en, fr)   zugeklappt, Außendisplay 1398 × 2034
docs/appstore/2.2/iphone-duo-inner/de/…  (en, fr)   aufgeklappt, Innendisplay 2007 × 2853
```

> **Stand 2.2 (03.11.2026):** Die App hat seit 2.2 eine Tab-Leiste statt des Hauptmenüs, eine durchgehende Rezeptseite statt der fünf Tabs und die Backanleitung als Blatt über dem Rezept. Der Test `AppStoreScreenshots` ist darauf umgestellt. Aufgenommen sind **iPhone** (de, en, fr, je zehn Bilder) und **iPad** (de und en je zehn; **fr nur sieben**: 05, 08 und 10 fehlen, weil die Titelleiste des iPads auf Französisch „Mehr“ und „+“ in ein Überlauf-Menü faltet – die französischen Tab-Titel sind zu breit – und der Test die Einträge dort nicht findet; `visibilityPriority` auf den Items hat daran nichts geändert). **Behoben am 04.11.2026:** Die Tabs haben eine eigene Tabelle `Tabs.xcstrings` mit kurzen französischen Titeln („Courses“, „Historique“), das Suchfeld liegt auf dem iPad unter der Titelleiste und der Bewertungsfilter im Menü „Mehr“; damit stehen „Mehr“ und „+“ in allen drei Sprachen in der Leiste. (Seit 2.4 ist der Bewertungsfilter auf dem iPad wieder ein eigener Knopf; mit dem Suchfeld unter der Leiste passen die drei Knöpfe neben die Tabs.) Die fehlenden französischen iPad-Bilder lassen sich jetzt aufnehmen. Die **iPhone-Duo-Bilder für 2.2 fehlen noch**: zugeklappt lief nur Deutsch durch (Englisch und Französisch verfehlten den Tab „Recipes“), aufgeklappt kamen schwarze Bilder in der Größe des Außendisplays, und ein Lauf blieb hängen; die Duo-Bilder in App Store Connect zeigen bis dahin noch 2.1 und sollten dort entfernt werden. Die **App-Vorschauen (Videos)** sind ebenfalls noch von 2.1. Das Skript installiert die App seit 2.2 vor jeder Sprache neu, damit keine lokale Kopie aus dem vorigen Sprachlauf in der Liste steht.

> **Stand 2.3 (05.11.2026):** Für 2.3 wurden iPhone und iPad in allen drei Sprachen neu aufgenommen (`VERSION=2.3 DEVICES="iphone ipad"`) und Bild für Bild mit den rohen 2.2-Aufnahmen verglichen (Anteil abweichender Pixel und ihr Rechteck; Datum, Uhrzeit und Scrollposition weichen immer ab). Geändert haben sich nur **07 rezept-details** (das Waagen-Symbol neben dem Teiggewicht öffnet den Rechner „Teigeinlage“) und **08 rezept-import** (dritte Importart „Rezept aus Text importieren“, längerer Fußtext). Deshalb enthält `docs/appstore/2.3/` **nur diese beiden Motive** je Gerät und Sprache; die übrigen acht Bilder bleiben in App Store Connect aus 2.2 stehen, ihre Fassung liegt weiter in `docs/appstore/2.2/`. Die Überschrift von 08 nennt jetzt „Foto, Link oder Text“. Von den Handbuchbildern wurden `neues-rezept.png` und `oeffentliche-rezepte.png` (je de, en, fr) erneuert; das zweite zeigte seit 2.2 den iCloud-Hinweis des Simulators („Du musst deinen Apple Account und dein Passwort eingeben“), den der Test jetzt mit „Abbrechen“ schließt und danach die neu geladene Liste abwartet (`StoreUITestCase.allow`, `AppStoreScreenshots`). Außerdem kennt der Test die seit dem 04.11. kurzen französischen Tab-Titel „Courses“ und „Historique“; mit den langen brach der französische Lauf nach Bild 07 ab („There is no shoppingLists tab“). Die Duo-Bilder und die App-Vorschauen sind unverändert offen.

Die Reihenfolge folgt der Produktseite: In den Suchergebnissen sind nur die ersten drei Bilder zu sehen, deshalb stehen dort die Dinge, die BakePlanner von Rezept-Apps unterscheiden. Die Überschriften (hier Deutsch; Englisch und Französisch in `captions.json`):

| Nr. | Bild | Inhalt | Überschrift |
|---|---|---|---|
| 01 | rezept-backen | Backanleitung (Blatt „Planen“) auf „Bis“ mit Datum, Schritte mit berechneten Beginnzeiten | Sag, wann das Brot fertig sein soll |
| 02 | startbildschirm | Rezeptliste mit Tab-Leiste und der Leiste „Als Nächstes“ | Erinnerung für jeden Schritt |
| 03 | backmodus | ein Schritt in großer Schrift, Zutaten, Vorlesen | In der Küche: ein Schritt, große Schrift |
| 04 | timeline | geplante Schritte als Timeline | Dein Backtag auf einen Blick |
| 05 | anstellgut-ta | Rechner „Anstellgut-TA“ aus dem Menü „Mehr“ | Dein Anstellgut, Deine TA |
| 06 | mehl-ersetzen | Sheet „Mehl ersetzen“ aus der Mehlzeile des Rezepts | Mehl tauschen, Wasser folgt |
| 07 | rezept-details | Rezeptseite mit Teigausbeute, Hydration und den Schaltflächen Planen / Einkaufsliste | Portionsgröße, Teiggewicht, Teigausbeute |
| 08 | rezept-import | Formular „Neues Rezept“ mit Import aus Bildern, von Internetseiten und aus Text | Aus dem Buch oder aus dem Netz |
| 09 | einkaufsliste | eine angelegte Einkaufsliste, nach Regalen gruppiert | Einkaufsliste nach Regalen |
| 10 | teigtemperatur | Rechner „Teigtemperatur“ | Die richtige Wassertemperatur |

Eine Überschrift besteht aus einer Zeile, nach einem `|` folgt eine kleinere zweite. Ein Bild, zu dessen Namen (ohne Nummer) kein Eintrag gehört, wird unverändert übernommen. Nach einer Textänderung müssen die Screenshots nicht neu entstehen:

```sh
CAPTIONS_ONLY=1 scripts/appstore-screenshots.sh
```

Der iPhone-Lauf liefert außerdem die Bilder der Handbücher, aus den rohen Aufnahmen: `docs/images/` (de), `docs/images/en/` und `docs/images/fr/` bekommen `hauptmenue.png` aus Bild 02 sowie `oeffentliche-rezepte.png`, `neues-rezept.png` und `einstellungen.png` aus drei zusätzlichen Aufnahmen (Nummern 91 bis 93), die nicht im App-Store-Ordner landen. Alle sind auf 402 Punkte Breite verkleinert. Danach `python3 docs/build-manual-html.py` ausführen, damit die Website die neuen Bilder bekommt.

## Voraussetzungen

- **Simulatoren:** „iPhone 17 Pro“ (1206 × 2622 – eine der vier iPhone-Größen, die App Store Connect für den 6,9"/6,5"-Platz annimmt; die *Max*-Modelle liefern andere Maße und werden abgelehnt), „iPad Pro 13-inch (M5)“ (13", 2064 × 2752) und „iPhone Duo“ (iOS 27.1). Heißen sie in Deiner Xcode-Version anders, gibst Du sie mit an:
  `IPHONE="iPhone 17 Pro" IPAD="iPad Pro 13-inch (M4)" DUO="iPhone Duo" scripts/appstore-screenshots.sh`
  Die verfügbaren Namen zeigt `xcrun simctl list devices available`.
- **iPhone Duo klappen:** Xcode 27.1 hat dafür keinen Befehl, nur den Regler im Device Hub. Das Skript nutzt das Werkzeug `hinge` (`brew install artemnovichkov/tap/hinge`), das den Winkel über eine private Simulator-Schnittstelle setzt; ein Xcode-Update kann es brechen. Zugeklappt läuft die App auf dem Außendisplay wie auf einem iPhone; die Statusleiste steht dort rechts neben der Kameraaussparung, das ist die Gestaltung des Außendisplays (Einstellungen und Home-Bildschirm sehen genauso aus). Aufgeklappt dreht das Skript das Gerät nach `landscape-left`, damit das Innendisplay hochkant steht (2007 × 2853) und die App dort die iPad-Aufteilung zeigt; normal gehalten wäre das Innendisplay quer, die Aufnahme käme auf der Seite liegend heraus, und die Wischgesten des Tests gingen in die falsche Richtung. App Store Connect nimmt 1398 × 2034 (außen) und 2007 × 2853 (innen) an und zeigt mit Duo-Bildern einen Hinweis „für iPhone Duo optimiert“ auf der Produktseite; ab April 2027 sind sie für Apps mit dem iOS-27.1-SDK Pflicht. Die Aufnahmen kommen einen Pixel kleiner heraus als verlangt, die Überschriften-Stufe bringt sie auf die exakte Größe (`--size`; `--rotate cw` gäbe es für die Queraufnahme).
- **Rezept-Datenbank online:** Der Test arbeitet mit den echten Daten des Simulators und der echten Rezept-Datenbank. Der Simulator braucht Netz und ein registriertes App-Check-Debug-Token. Das Skript reicht das Token des ersten Simulators, auf dem die App schon lief, als `FIRAAppCheckDebugToken` an die App weiter (oder `APP_CHECK_DEBUG_TOKEN=…`), damit ein neuer Simulator wie der Duo nicht erst in der Firebase-Konsole registriert werden muss.
- **Übersetzungen im Cache:** Der Simulator kann nicht übersetzen (das Translation-Framework meldet dort „Unable to Translate“). Die englischen und französischen Läufe zeigen das Rezept deshalb aus den Übersetzungen, die im Rezeptdokument in Firestore gespeichert sind (`translations.en`, `translations.fr`). Fehlen sie – etwa weil das Rezept umbenannt oder bearbeitet wurde, was den Cache leert –, bricht der Test mit „Translating into English failed“ ab. Abhilfe: das Rezept einmal auf einem echten Gerät öffnen und über das Globus-Menü nach English und Français übersetzen; danach läuft das Skript wieder durch.
- **Rezept:** Gezeigt wird „Kartoffelbrot mit Saaten“. Ein anderes wählst Du mit `RECIPE="Übernacht-Sauerteig-Baguettes" scripts/appstore-screenshots.sh` (der Anfang des Namens genügt). Das Rezept sollte eine Mehlzeile „1050“ haben, aus der Bild 06 entsteht; sonst zeigt Bild 06 den Rechner aus dem Menü „Mehr“.

Der Test plant das Rezept auf „Fertig bis“ zum ersten 15:00 Uhr, das mindestens einen Tag entfernt liegt (Startargument `-UITestingPlanFinish`, siehe `StoreUITestCase.planFinish`): Rückwärts über die 19 Stunden des Rezepts beginnt der Plan am Vorabend gegen 20:00 Uhr, der Teig ruht über Nacht, und kein Schritt erscheint als Nacht-Warnung. Dieser Plan bleibt im Simulator stehen. Die Statusleiste zeigt 9:41, volle Balken und vollen Akku, der Simulator läuft im hellen Erscheinungsbild.

Nur eine Sprache: `LANGS="fr" scripts/appstore-screenshots.sh`. Nur bestimmte Geräte: `DEVICES="duo-outer duo-inner" …` (Rollen: `iphone`, `ipad`, `duo-outer`, `duo-inner`). Andere Versionsnummer für den Ordner: `VERSION=2.1 …`. Jeder Lauf je Gerät und Sprache dauert etwa sieben Minuten; der Simulator wird vor jedem neu gestartet, weil ein zweiter Lauf auf demselben Start gelegentlich nicht zurückkam.

In einem normalen Testlauf (⌘U, Xcode Cloud) überspringt sich der Screenshot-Test selbst.

> **Stand 2.3, iPhone Duo (07.11.2026):** **Zugeklappt** (Außendisplay, 1398 × 2034) laufen alle drei Sprachen durch (`VERSION=2.3 DEVICES=duo-outer`), die Bilder liegen in `docs/appstore/2.3/iphone-duo-outer/`. Der englische Lauf scheiterte zunächst am Knopf „Einkaufsliste erstellen“, dessen Label dort nicht exakt „Create shopping list“ hieß; der Test sucht den Knopf jetzt über die Kennung `shoppingList.create` und wartet länger, weil die Namen des öffentlichen Rezepts vorher übersetzt werden. Ein englischer Lauf blieb außerdem nach dem letzten Bild hängen (App nicht mehr auf dem Display, `xcodebuild` kam nicht zurück) – der bekannte Hänger, Lauf wiederholen. **Aufgeklappt** (Innendisplay) ist im Simulator von Xcode 27 **nicht automatisierbar:** Sobald der `hinge` die Duo öffnet, erreichen synthetische Berührungen das Innendisplay nicht (weder aus dem UI-Test noch aus Xcodes Geräte-Interaktion), die Hierarchie meldet das Fenster auf ein Drittel verkleinert (223 × 290 Punkte), und `XCUIScreen` liefert nur das dunkle Außendisplay – daher die schwarzen Bilder. Passend dazu bietet der Simulator in Xcode 27 für die Duo keine Umschaltung zwischen Außen- und Innendisplay mehr an (Beobachtung von Hans-Peter, 07.11.2026): Das Innendisplay ist dort nur noch ein Framebuffer ohne Fenster, den weder die Anzeige noch die Eingabe des Simulators bedienen. Die App selbst läuft richtig: `xcrun simctl io <udid> screenshot --display 3` (Screen „LCD-1“, 2007 × 2853 hochkant bei `hinge orient landscape-left`, 2853 × 2007 quer bei `portrait`) zeigt sie. Ohne Berührungen bräuchte die App Start-Argumente oder URL-Routen, die jedes Motiv direkt öffnen; das ist offen. Bis dahin für die Duo nur die zugeklappten Bilder hochladen und die aufgeklappten von 2.1 in App Store Connect entfernen oder stehen lassen.

## Apple Watch

Die Watch-Bilder entstehen nicht über den UI-Test, sondern direkt im Watch-Simulator mit einem festen Demo-Plan in der Watch-App: Das Startargument `-UITestingWatchDemo` lässt `PhonePlanSession` statt des iPhone-Plans fünf Schritte des „Kartoffelbrot mit Saaten“ zeigen (Texte in `BakePlannerWatch/Localizable.xcstrings`, de/en/fr), `-UITestingWatchDemoStep <n>` öffnet Schritt n (ab 0); die Uhrzeiten laufen ab dem Start („in 17 Min.“, „in 3 Std., 15 Min.“). Ohne das Argument verhält sich die App wie immer.

```sh
W=<UDID des Simulators „Apple Watch Ultra 4 (49mm)“>; BID=de.hpm64625.BackPlaner.watchkitapp
xcodebuild -scheme BakePlannerWatch -destination "platform=watchOS Simulator,id=$W" -derivedDataPath /tmp/watchbuild build
xcrun simctl boot $W; xcrun simctl install $W /tmp/watchbuild/Build/Products/Debug-watchsimulator/BakePlannerWatch.app
xcrun simctl launch $W $BID -AppleLanguages "(de)" -AppleLocale de_DE -UITestingWatchDemo -UITestingWatchDemoStep 0
sleep 5; xcrun simctl io $W screenshot docs/appstore/2.3/watch/de/01-schritt-zutaten.png
```

Aufgenommen am 07.11.2026 je Sprache drei Bilder ohne Überschrift (422 × 514 Pixel, die Größe der Apple Watch Ultra in App Store Connect): `01-schritt-zutaten` (Schritt 0, Hauptteig kneten mit Zutaten), `02-ofen-anstellen` (Schritt 3) und `03-backen` (Schritt 4, mit „Erledigt“). Die Statusleiste der Watch lässt sich im Simulator nicht auf 9:41 stellen (`simctl status_bar` wird für watchOS nicht unterstützt), die Uhrzeit ist deshalb die der Aufnahme.

## App-Vorschauen (Videos)

Die Rohvideos für die App-Vorschauen entstehen auf demselben Weg:

```sh
scripts/appstore-previews.sh
```

Der UI-Test `AppPreview` fährt die App durch drei Szenen, während `simctl` den Simulator-Bildschirm aufnimmt; vor jeder Szene löscht er (ohne Aufnahme) die geplanten Schritte, die Einkaufslisten und die lokale Kopie des Rezepts, die das Setzen der Erinnerungen anlegt – sonst stünde das Rezept doppelt in der Liste. Der Plan beginnt um 20:00 Uhr (Startargument `-UITestingPlanStart`, siehe `StoreUITestCase.planStart`; das Screenshot-Skript lässt vor jeder Sprache dieselbe Aufräum-Vorbereitung laufen), damit der Teig über Nacht ruht und kein Schritt als Nacht-Warnung erscheint. Jedes Rohvideo beginnt auf dem Home-Bildschirm und enthält hinten rund 15 Sekunden Leerlauf, beides wird im Schnitt entfernt. Ergebnis: `docs/appstore/2.2/preview/<gerät>/<sprache>/1-plan.mov`, `2-calculators.mov`, `3-shopping.mov` (git-ignoriert). Eine Szene allein: `SCENES=plan LANGS=de DEVICES=iphone scripts/appstore-previews.sh`.

| Szene | Inhalt | Einblendungen (dieselben Worte wie die Screenshot-Überschriften) |
|---|---|---|
| 1 plan | Rezept → „Planen“ → „Fertig bis“ → Erinnerungen setzen → Leiste „Als Nächstes“ → Timeline → Backmodus | „Sag, wann das Brot fertig sein soll“ · „BakePlanner rechnet jeden Schritt zurück“ · „Erinnerung für jeden Schritt“ · „In der Küche: ein Schritt, große Schrift“ |
| 2 calculators | Portionsgröße ×2 → Mehl ersetzen → Anstellgut-TA 220 → Teigtemperatur | „Alles rechnet mit“ · „Mehl tauschen, Wasser folgt“ · „Dein Anstellgut, Deine TA“ · „Die richtige Wassertemperatur“ |
| 3 shopping | Neues Rezept mit Import → Einkaufsliste nach Regalen → öffentliches Rezept in anderer Sprache | „Aus dem Buch oder aus dem Netz“ · „Einkaufsliste nach Regalen“ · „Öffentliche Rezepte in Deiner Sprache“ |

Für die Aufnahme von Hand auf dem iPhone (QuickTime Player am Mac) gibt es die Playbooks in [AppStore-Vorschau-Playbooks.md](AppStore-Vorschau-Playbooks.md), mit denselben Szenen und Einblendungen.

Schnitt und Export in **iMovie**, Projektart „App-Vorschau“: Clip importieren, Anfang (App-Start) und Ende trimmen, Titel setzen, exportieren – iMovie liefert die Maße, die App Store Connect annimmt. Vorgaben: 15–30 Sekunden, Hochformat, 30 fps, bis zu drei Vorschauen je Gerätegröße; die Vorschau läuft in der Suche stumm an und steht vor den Bildern, Ton ist optional. Posterbild in App Store Connect wählen, am besten die Timeline. Für das iPad genügt Szene 1.

## Hochladen

App Store Connect → BakePlanner → Version → je Sprache oben rechts umschalten → **iPhone 6,9"-Display**, **iPad 13"-Display** bzw. **iPhone Duo** (Außen- und Innendisplay) → die Bilder des passenden Ordners hineinziehen (nicht die aus `roh/`). Die Reihenfolge ergibt sich aus den Nummern im Dateinamen. Die Texte der Produktseite stehen in [AppStore-Beschreibung.md](AppStore-Beschreibung.md).
