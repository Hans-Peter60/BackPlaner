# CookPlanner Pro

Stand 26.11.2026. CookPlanner erscheint erst, wenn der In-App-Kauf möglich ist (Entscheidung Hans-Peter, 26.11.2026), und startet dann gleich mit Pro. Es gibt deshalb **keine Großvaterregel**: Wer die App aus dem Store lädt, bekommt die freien Funktionen, Pro ist ein Einmalkauf.

## Was frei bleibt, was Pro ist

Frei bleibt alles, was man zum Planen und Kochen gegen die Uhr braucht: Gerichte von Hand, aus Fotos und Webseiten, der Plan mit Zeitachse und Urteil, Portionen, der Kochmodus in allen drei Uhr-Modi mit Abhaken und Neuplanung, Mitteilungen, Wecker und Live-Aktivität (sie verhindern angebrannte Töpfe), Einkaufsliste, Verlauf mit Messung der Zeiten, iCloud-Abgleich, Sicherung, Beispielgerichte, Siri („Wie lange noch“, „Schritt erledigt“), Spotlight und die iPad-Tastatur.

| Pro-Funktion | `KitchenProFeature` | Wo gesperrt |
|---|---|---|
| Menü aus mehreren Gängen | `.menu` | „+“ → „Menü zusammenstellen“ und ⇧⌘N (`DishListView`) |
| Vorlesen und Sprachbefehle | `.handsFree` | die beiden Knöpfe im Kochmodus (`CookModeView`); ein gespeichertes „Vorlesen an“ spricht ohne Pro nicht |
| Kochjahr-Buch | `.yearbook` | „Gekocht“ → „+“ (`CookHistoryView`) |
| Kochstatistik | `.statistics` | Darstellung „Statistik“ im Verlauf zeigt die Sperrseite |
| Eigene Sammlungen | `.collections` | „Sammlung sichern“ im Filtermenü; Suche, Filter und die fünf festen Chips bleiben frei |
| Plan als PDF | `.planPDF` | Drucker-Knopf auf dem Plan (`DishPlanView`) |
| Gemessene Zeiten übernehmen | `.learnedTimes` | Knopf auf dem Plan; das Messen bleibt frei |
| Mehr Rezeptanalysen | – | Monatskontingent in den Functions, siehe unten |

## Wie es gebaut ist

- **Paket:** `BakePlannerCore/Sources/BakePlannerCore/KitchenProAccess.swift` – `KitchenProFeature`, `KitchenProAccess.unlocked(_:config:purchased:)` und `storeVisible`, dazu `MonetizationConfig(firestoreRESTFields:)` für die REST-Antwort; Tests in `KitchenProAccessTests`.
- **App:** `CookPro.swift` – `CookProStore` (StoreKit 2, Produkt `de.hpm64625.CookPlanner.pro`), `CookProConfigStore` (liest `config/cookplannerMonetization` über die REST-Schnittstelle von Firestore, anonym angemeldet, mit App-Check-Token; Ergebnis in UserDefaults zwischengespeichert, beim Zurückkehren in die App neu gelesen), `CookPro` (die Entscheidung, `proClaim` für die Functions). `CookProPaywallView.swift` – Kaufseite, `CookProBadge`, `withCookPro(_:offer:_:)`, `.cookProPaywall(_:)`, `CookProLockedScreen`.
- **Einstellungen:** Abschnitt „CookPlanner Pro“ ganz oben, sobald der Laden sichtbar ist.
- **Ohne Dokument oder offline:** alles frei (fail open, wie BakePlanner). Die Firestore-Regeln erlauben angemeldeten Apps das Lesen von `config/*` schon – keine Regeländerung nötig.
- **Zum Ausprobieren (nur Debug-Builds):** `-CookProRequired 1` (sperrt, Firestore überschreibt es nicht), `-CookProStoreVisible 1`, `-CookProPurchased 1|0`, `-CookProPaywall 1` (Kaufseite allein, für das Prüf-Bildschirmfoto). Echte Käufe aus Xcode: `CookPlanner/CookPlanner.storekit` unter **Product → Scheme → Edit Scheme… → Run → Options → StoreKit Configuration** wählen.

## Schalter: Firestore `config/cookplannerMonetization`

Eigenes Dokument, damit BakePlanner und CookPlanner getrennt schalten. Felder wie bei BakePlanner (`MonetizationConfig`):

| Feld | Wirkung |
|---|---|
| `storeVisible` (bool) | Pro-Abschnitt in den Einstellungen; sperrt nichts |
| `proRequired` (bool) | sperrt die Pro-Funktionen ohne Kauf; zeigt den Laden auch ohne `storeVisible` |
| `freeImportsPerMonth` (Zahl) | Analysen über die Cloud je Kalendermonat ohne Pro; 0 oder fehlend = keine Monatsgrenze (gelesen von den Functions) |

Solange das Dokument fehlt, ist alles frei – so bleibt es auf Hans-Peters Geräten, bis der Kauf existiert.

## Einführen (Reihenfolge)

1. Gewerbe und Steuernummer, dann App Store Connect → **Vereinbarungen, Steuern und Bankverbindung**: Vertrag für bezahlte Apps (gilt für beide Apps).
2. App Store Connect → CookPlanner → **In-App-Käufe**: „Nicht verbrauchbar“, Referenzname `CookPlanner Pro`, Produkt-ID `de.hpm64625.CookPlanner.pro`, Preis, Familienfreigabe an, Texte aus `CookPlanner-Store.md` (Abschnitt „In-App-Kauf“), Prüf-Bildschirmfoto der Kaufseite (`-CookProPaywall 1` mit StoreKit-Konfiguration, damit der Preis erscheint).
3. In TestFlight mit einem Sandbox-Konto kaufen und wiederherstellen.
4. Firestore: Dokument `config/cookplannerMonetization` anlegen mit `storeVisible: true`, `proRequired: true`, `freeImportsPerMonth: 5` (Kontingent erst, wenn die Functions mit der CookPlanner-Prüfung deployt sind).
5. Version 1.0 mit dem Kauf zusammen zur Prüfung einreichen; Pro-Abschnitt der Beschreibung und der Prüfhinweis zum Kauf stehen in `CookPlanner-Store.md`.

## Zurücknehmen

`proRequired` auf `false` – beim nächsten Öffnen der App ist alles wieder frei.

## Offen

- Preis: Vorschlag 4,99 € einmalig (weniger Pro-Umfang als BakePlanner mit 9,99 €); die StoreKit-Datei nutzt diesen Wert nur zum Testen.
- Store-Bilder mit „PRO“-Marke für die Pro-Motive (Menü, Kochmodus mit Vorlesen) wie bei BakePlanner.
