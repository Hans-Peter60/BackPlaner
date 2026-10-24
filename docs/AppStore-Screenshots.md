# App-Store-Screenshots

Die Bilder für App Store Connect entstehen automatisch im Simulator, auf dem Mac:

```sh
scripts/appstore-screenshots.sh
```

Das Skript baut die App einmal, lässt den UI-Test `AppStoreScreenshots` auf zwei Simulatoren in drei Sprachen laufen und setzt anschließend über jedes Bild eine Überschrift (`scripts/appstore-captions.swift`, Texte in `docs/appstore/captions.json`). Ergebnis:

```
docs/appstore/2.0/iphone-6.9/de/01-rezept-backen.png … 10-teigtemperatur.png   (mit Überschrift, für den Store)
docs/appstore/2.0/iphone-6.9/de/roh/…                                          (ohne Überschrift, nicht in git)
docs/appstore/2.0/iphone-6.9/en/…, fr/…
docs/appstore/2.0/ipad-13/de/…  (en, fr)
```

Die Reihenfolge folgt der Produktseite: In den Suchergebnissen sind nur die ersten drei Bilder zu sehen, deshalb stehen dort die Dinge, die BakePlanner von Rezept-Apps unterscheiden. Die Überschriften (hier Deutsch; Englisch und Französisch in `captions.json`):

| Nr. | Bild | Inhalt | Überschrift |
|---|---|---|---|
| 01 | rezept-backen | Backen-Tab auf „Bis“ mit Datum, Schritte mit berechneten Beginnzeiten | Sag, wann das Brot fertig sein soll |
| 02 | startbildschirm | Hauptmenü mit der Karte „Als Nächstes“ | Erinnerung für jeden Schritt |
| 03 | backmodus | ein Schritt in großer Schrift, Zutaten, Vorlesen | In der Küche: ein Schritt, große Schrift |
| 04 | timeline | geplante Schritte als Timeline | Dein Backtag auf einen Blick |
| 05 | anstellgut-ta | Rechner „Anstellgut-TA“ aus dem Hauptmenü | Dein Anstellgut, Deine TA |
| 06 | mehl-ersetzen | Sheet „Mehl ersetzen“ aus der Mehlzeile des Rezepts | Mehl tauschen, Wasser folgt |
| 07 | rezept-details | Details eines Rezepts, mit Teigausbeute und Hydration | Portionsgröße, Teiggewicht, Teigausbeute |
| 08 | rezept-import | Formular „Neues Rezept“ mit Import aus Bildern und von Internetseiten | Aus dem Buch oder aus dem Netz |
| 09 | einkaufsliste | eine angelegte Einkaufsliste, nach Regalen gruppiert | Einkaufsliste nach Regalen |
| 10 | teigtemperatur | Rechner „Teigtemperatur“ | Die richtige Wassertemperatur |

Eine Überschrift besteht aus einer Zeile, nach einem `|` folgt eine kleinere zweite. Ein Bild, zu dessen Namen (ohne Nummer) kein Eintrag gehört, wird unverändert übernommen. Nach einer Textänderung müssen die Screenshots nicht neu entstehen:

```sh
CAPTIONS_ONLY=1 scripts/appstore-screenshots.sh
```

Der iPhone-Lauf liefert außerdem die Bilder der Handbücher, aus den rohen Aufnahmen: `docs/images/` (de), `docs/images/en/` und `docs/images/fr/` bekommen `hauptmenue.png` aus Bild 02 sowie `oeffentliche-rezepte.png`, `neues-rezept.png` und `einstellungen.png` aus drei zusätzlichen Aufnahmen (Nummern 91 bis 93), die nicht im App-Store-Ordner landen. Alle sind auf 402 Punkte Breite verkleinert. Danach `python3 docs/build-manual-html.py` ausführen, damit die Website die neuen Bilder bekommt.

## Voraussetzungen

- **Simulatoren:** „iPhone 17 Pro“ (1206 × 2622 – eine der vier iPhone-Größen, die App Store Connect für den 6,9"/6,5"-Platz annimmt; die *Max*-Modelle liefern andere Maße und werden abgelehnt) und „iPad Pro 13-inch (M5)“ (13", 2064 × 2752). Heißen sie in Deiner Xcode-Version anders, gibst Du sie mit an:
  `IPHONE="iPhone 17 Pro" IPAD="iPad Pro 13-inch (M4)" scripts/appstore-screenshots.sh`
  Die verfügbaren Namen zeigt `xcrun simctl list devices available`.
- **Rezept-Datenbank online:** Der Test arbeitet mit den echten Daten des Simulators und der echten Rezept-Datenbank. Der Simulator braucht Netz und ein registriertes App-Check-Debug-Token – wie beim Start aus Xcode. Einmal die App im jeweiligen Simulator aus Xcode starten genügt, um das zu prüfen.
- **Übersetzungen im Cache:** Der Simulator kann nicht übersetzen (das Translation-Framework meldet dort „Unable to Translate“). Die englischen und französischen Läufe zeigen das Rezept deshalb aus den Übersetzungen, die im Rezeptdokument in Firestore gespeichert sind (`translations.en`, `translations.fr`). Fehlen sie – etwa weil das Rezept umbenannt oder bearbeitet wurde, was den Cache leert –, bricht der Test mit „Translating into English failed“ ab. Abhilfe: das Rezept einmal auf einem echten Gerät öffnen und über das Globus-Menü nach English und Français übersetzen; danach läuft das Skript wieder durch.
- **Rezept:** Gezeigt wird „Kartoffelbrot mit Saaten“. Ein anderes wählst Du mit `RECIPE="Übernacht-Sauerteig-Baguettes" scripts/appstore-screenshots.sh` (der Anfang des Namens genügt). Das Rezept sollte eine Mehlzeile „1050“ haben, aus der Bild 06 entsteht; sonst zeigt Bild 06 den Rechner aus dem Hauptmenü.

Der Test plant das Rezept auf „Fertig bis“ zum ersten 15:00 Uhr, das mindestens einen Tag entfernt liegt (Startargument `-UITestingPlanFinish`, siehe `StoreUITestCase.planFinish`): Rückwärts über die 19 Stunden des Rezepts beginnt der Plan am Vorabend gegen 20:00 Uhr, der Teig ruht über Nacht, und kein Schritt erscheint als Nacht-Warnung. Dieser Plan bleibt im Simulator stehen. Die Statusleiste zeigt 9:41, volle Balken und vollen Akku, der Simulator läuft im hellen Erscheinungsbild.

Nur eine Sprache: `LANGS="fr" scripts/appstore-screenshots.sh`. Andere Versionsnummer für den Ordner: `VERSION=2.1 …`.

In einem normalen Testlauf (⌘U, Xcode Cloud) überspringt sich der Screenshot-Test selbst.

## App-Vorschauen (Videos)

Die Rohvideos für die App-Vorschauen entstehen auf demselben Weg:

```sh
scripts/appstore-previews.sh
```

Der UI-Test `AppPreview` fährt die App durch drei Szenen, während `simctl` den Simulator-Bildschirm aufnimmt; vor jeder Szene löscht er (ohne Aufnahme) die geplanten Schritte, die Einkaufslisten und die lokale Kopie des Rezepts, die das Setzen der Erinnerungen anlegt – sonst stünde das Rezept doppelt in der Liste. Der Plan beginnt um 20:00 Uhr (Startargument `-UITestingPlanStart`, siehe `StoreUITestCase.planStart`; das Screenshot-Skript lässt vor jeder Sprache dieselbe Aufräum-Vorbereitung laufen), damit der Teig über Nacht ruht und kein Schritt als Nacht-Warnung erscheint. Jedes Rohvideo beginnt auf dem Home-Bildschirm und enthält hinten rund 15 Sekunden Leerlauf, beides wird im Schnitt entfernt. Ergebnis: `docs/appstore/2.0/preview/<gerät>/<sprache>/1-plan.mov`, `2-calculators.mov`, `3-shopping.mov` (git-ignoriert). Eine Szene allein: `SCENES=plan LANGS=de DEVICES=iphone scripts/appstore-previews.sh`.

| Szene | Inhalt | Einblendungen (dieselben Worte wie die Screenshot-Überschriften) |
|---|---|---|
| 1 plan | Rezept → „Rezept backen“ → „Fertig bis“ → Erinnerungen setzen → Karte „Als Nächstes“ → Timeline → Backmodus | „Sag, wann das Brot fertig sein soll“ · „BakePlanner rechnet jeden Schritt zurück“ · „Erinnerung für jeden Schritt“ · „In der Küche: ein Schritt, große Schrift“ |
| 2 calculators | Portionsgröße ×2 → Mehl ersetzen → Anstellgut-TA 220 → Teigtemperatur | „Alles rechnet mit“ · „Mehl tauschen, Wasser folgt“ · „Dein Anstellgut, Deine TA“ · „Die richtige Wassertemperatur“ |
| 3 shopping | Neues Rezept mit Import → Einkaufsliste nach Regalen → öffentliches Rezept in anderer Sprache | „Aus dem Buch oder aus dem Netz“ · „Einkaufsliste nach Regalen“ · „Öffentliche Rezepte in Deiner Sprache“ |

Schnitt und Export in **iMovie**, Projektart „App-Vorschau“: Clip importieren, Anfang (App-Start) und Ende trimmen, Titel setzen, exportieren – iMovie liefert die Maße, die App Store Connect annimmt. Vorgaben: 15–30 Sekunden, Hochformat, 30 fps, bis zu drei Vorschauen je Gerätegröße; die Vorschau läuft in der Suche stumm an und steht vor den Bildern, Ton ist optional. Posterbild in App Store Connect wählen, am besten die Timeline. Für das iPad genügt Szene 1.

## Hochladen

App Store Connect → BakePlanner → Version → je Sprache oben rechts umschalten → **iPhone 6,9"-Display** bzw. **iPad 13"-Display** → die Bilder des passenden Ordners hineinziehen (nicht die aus `roh/`). Die Reihenfolge ergibt sich aus den Nummern im Dateinamen. Die Texte der Produktseite stehen in [AppStore-Beschreibung.md](AppStore-Beschreibung.md).
