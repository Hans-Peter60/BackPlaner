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

## Voraussetzungen

- **Simulatoren:** „iPhone 17 Pro“ (1206 × 2622 – eine der vier iPhone-Größen, die App Store Connect für den 6,9"/6,5"-Platz annimmt; die *Max*-Modelle liefern andere Maße und werden abgelehnt) und „iPad Pro 13-inch (M5)“ (13", 2064 × 2752). Heißen sie in Deiner Xcode-Version anders, gibst Du sie mit an:
  `IPHONE="iPhone 17 Pro" IPAD="iPad Pro 13-inch (M4)" scripts/appstore-screenshots.sh`
  Die verfügbaren Namen zeigt `xcrun simctl list devices available`.
- **Rezept-Datenbank online:** Der Test arbeitet mit den echten Daten des Simulators und der echten Rezept-Datenbank. Der Simulator braucht Netz und ein registriertes App-Check-Debug-Token – wie beim Start aus Xcode. Einmal die App im jeweiligen Simulator aus Xcode starten genügt, um das zu prüfen.
- **Rezept:** Gezeigt wird „Sauerteigbrot mit Kartoffeln und Saaten“. Ein anderes wählst Du mit `RECIPE="Übernacht-Sauerteig-Baguettes" scripts/appstore-screenshots.sh` (der Anfang des Namens genügt).

Der Test plant das Rezept, damit Startbildschirm, Backmodus und Timeline etwas zeigen. Dieser Plan bleibt im Simulator stehen. Die Statusleiste zeigt 9:41, volle Balken und vollen Akku, der Simulator läuft im hellen Erscheinungsbild.

Nur eine Sprache: `LANGS="fr" scripts/appstore-screenshots.sh`. Andere Versionsnummer für den Ordner: `VERSION=2.1 …`.

In einem normalen Testlauf (⌘U, Xcode Cloud) überspringt sich der Screenshot-Test selbst.

## Hochladen

App Store Connect → BakePlanner → Version → je Sprache oben rechts umschalten → **iPhone 6,9"-Display** bzw. **iPad 13"-Display** → die Bilder des passenden Ordners hineinziehen. Die Reihenfolge ergibt sich aus den Nummern im Dateinamen.
