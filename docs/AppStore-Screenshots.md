# App-Store-Screenshots

Die Bilder für App Store Connect entstehen automatisch im Simulator, auf dem Mac:

```sh
scripts/appstore-screenshots.sh
```

Das Skript baut die App einmal und lässt dann den UI-Test `AppStoreScreenshots` auf zwei Simulatoren in drei Sprachen laufen. Ergebnis:

```
docs/appstore/2.0/iphone-6.9/de/01-startbildschirm.png … 08-anstellgut-ta.png
docs/appstore/2.0/iphone-6.9/en/…
docs/appstore/2.0/iphone-6.9/fr/…
docs/appstore/2.0/ipad-13/de/…  (en, fr)
```

| Nr. | Bild | Inhalt |
|---|---|---|
| 01 | startbildschirm | Hauptmenü mit der Karte „Nächster Schritt“ |
| 02 | rezept-datenbank | öffentliche Rezepte mit Bildern |
| 03 | rezept-details | Details eines Rezepts, mit Teigausbeute und Hydration |
| 04 | rezept-backen | Zeitplanung: Datum, Schritte, Beginnzeiten |
| 05 | backmodus | ein Schritt in großer Schrift |
| 06 | timeline | geplante Schritte als Timeline |
| 07 | einkaufsliste | Zutaten des Rezepts für die Einkaufsliste, mit Portionsgröße |
| 08 | anstellgut-ta | Rechner „Anstellgut-TA“ aus dem Hauptmenü (neu in 2.0) |

Der iPhone-Lauf liefert außerdem die Bilder der Handbücher: `docs/images/` (de), `docs/images/en/` und `docs/images/fr/` bekommen `hauptmenue.png` und `oeffentliche-rezepte.png` aus den Bildern 01 und 02 sowie `neues-rezept.png` und `einstellungen.png` aus zwei zusätzlichen Aufnahmen (Nummern 91 und 92), die nicht im App-Store-Ordner landen. Alle sind auf 402 Punkte Breite verkleinert. Danach `python3 docs/build-manual-html.py` ausführen, damit die Website die neuen Bilder bekommt.

## Voraussetzungen

- **Simulatoren:** „iPhone 17 Pro“ (1206 × 2622 – eine der vier iPhone-Größen, die App Store Connect für den 6,9"/6,5"-Platz annimmt; die *Max*-Modelle liefern andere Maße und werden abgelehnt) und „iPad Pro 13-inch (M5)“ (13", 2064 × 2752). Heißen sie in Deiner Xcode-Version anders, gibst Du sie mit an:
  `IPHONE="iPhone 17 Pro" IPAD="iPad Pro 13-inch (M4)" scripts/appstore-screenshots.sh`
  Die verfügbaren Namen zeigt `xcrun simctl list devices available`.
- **Rezept-Datenbank online:** Der Test arbeitet mit den echten Daten des Simulators und der echten Rezept-Datenbank. Der Simulator braucht Netz und ein registriertes App-Check-Debug-Token – wie beim Start aus Xcode. Einmal die App im jeweiligen Simulator aus Xcode starten genügt, um das zu prüfen.
- **Rezept:** Gezeigt wird „Sauerteigbrot mit Kartoffeln und Saaten“. Ein anderes wählst Du mit `RECIPE="Übernacht-Sauerteig-Baguettes" scripts/appstore-screenshots.sh` (der Anfang des Namens genügt).

Der Test plant das Rezept, damit Startbildschirm, Backmodus und Timeline etwas zeigen. Dieser Plan bleibt im Simulator stehen. Die Statusleiste zeigt 9:41, volle Balken und vollen Akku, der Simulator läuft im hellen Erscheinungsbild.

Nur eine Sprache: `LANGS="fr" scripts/appstore-screenshots.sh`. Andere Versionsnummer für den Ordner: `VERSION=2.1 …`.

In einem normalen Testlauf (⌘U, Xcode Cloud) überspringt sich der Screenshot-Test selbst.

## App-Vorschauen (Videos)

Die Rohvideos für die App-Vorschauen entstehen auf demselben Weg:

```sh
scripts/appstore-previews.sh
```

Der UI-Test `AppPreview` fährt die App durch drei Szenen, während `simctl` den Simulator-Bildschirm aufnimmt; vorher löscht er die geplanten Schritte früherer Läufe, damit die Plan-Szene einen frischen Plan zeigt. Jedes Rohvideo beginnt auf dem Home-Bildschirm und enthält hinten rund 15 Sekunden Leerlauf, beides wird im Schnitt entfernt. Ergebnis: `docs/appstore/2.0/preview/<gerät>/<sprache>/1-plan.mov`, `2-calculators.mov`, `3-shopping.mov` (git-ignoriert). Eine Szene allein: `SCENES=plan LANGS=de DEVICES=iphone scripts/appstore-previews.sh`.

| Szene | Inhalt | Einblendungen (Vorschlag) |
|---|---|---|
| 1 plan | Rezept → „Rezept backen“ → „Fertig bis“ → Erinnerungen setzen → Karte „Als Nächstes“ → Timeline → Backmodus | „Wann soll das Brot fertig sein?“ · „BakePlanner rechnet rückwärts“ · „Erinnerungen für jeden Schritt“ · „In der Küche: ein Schritt, große Schrift“ |
| 2 calculators | Portionsgröße ×2 → Mehl ersetzen → Anstellgut-TA 220 → Teigtemperatur | „Doppelte Menge, ein Tipp“ · „Mehl tauschen, Wasser folgt“ · „Dein Anstellgut, Deine TA“ |
| 3 shopping | Neues Rezept mit Import → Einkaufsliste nach Regalen → öffentliches Rezept in anderer Sprache | „Aus dem Netz oder vom Foto“ · „Einkaufsliste nach Regalen“ · „Öffentliche Rezepte in Deiner Sprache“ |

Schnitt und Export in **iMovie**, Projektart „App-Vorschau“: Clip importieren, Anfang (App-Start) und Ende trimmen, Titel setzen, exportieren – iMovie liefert die Maße, die App Store Connect annimmt. Vorgaben: 15–30 Sekunden, Hochformat, 30 fps, bis zu drei Vorschauen je Gerätegröße; die Vorschau läuft in der Suche stumm an, Ton ist optional. Posterbild in App Store Connect wählen, am besten die Timeline. Für das iPad genügt Szene 1.

## Hochladen

App Store Connect → BakePlanner → Version → je Sprache oben rechts umschalten → **iPhone 6,9"-Display** bzw. **iPad 13"-Display** → die Bilder des passenden Ordners hineinziehen. Die Reihenfolge ergibt sich aus den Nummern im Dateinamen.
