# Idee: Kochen gegen die Uhr („Gegen die Uhr“, Arbeitstitel)

Stand 19.11.2026. Eine zweite App neben BakePlanner, die das gemeinsame Paket `BakePlannerCore` nutzt: ein Gericht aus mehreren Komponenten in einem festen Zeitbudget (35 Minuten wie in der ZDF-Sendung, deren Name in App und Store nicht vorkommen darf) oder zu einer festen Servierzeit, von einer Person allein, mit vier Platten und einem Ofen.

## Warum eine eigene App

- BakePlanner plant die Schritte eines Brots in Rezeptreihenfolge; der Backtag-Optimierer verschiebt ganze Brote gegeneinander. Ein Gericht mit vier Komponenten braucht einen Planer, der einzelne Arbeitsschritte umordnet.
- Herdplatten, Pfannen und ein 35-Minuten-Budget wären in einer Brot-App Fremdkörper, in der Oberfläche wie im Datenmodell.
- Der Markt für „Dinner-Timer“ ist englischsprachig gut besetzt (Holiday Dinner Planner, Pinch, prepSync, Cooking Time Planner, Focara, SousSmart). Lücken: Deutsch, Planung je Arbeitsschritt mit den Händen als Engpass, Import ohne Abtippen der Zeiten, festes Zeitbudget mit der Antwort „passt / fehlt X Minuten, weil …“.

## Was geteilt wird (Paket, nicht kopiert)

Zeiten (`DurationInput`, `DurationWindow`, `Plausible`, `DateTimeText`), Zeitleiste, Erinnerungen, aktueller Schritt, Sprachbefehle, Import (Web, Text, Foto, KI, Cloud Functions), Glossar und Lokalisierung, Einheiten, Einkaufsliste, Vorrat, Pro-Logik, Ofenprofile, Kalender-Konflikte. Aus der App: Theme, Backmodus als Kochmodus, Live-Aktivität, Widgets, Watch, Benachrichtigungen, Skripte und CI. Beim Brot bleibt: Gare, Anstellgut, TA, Bäckerformel, Mehltausch, Teigtemperatur, Jahrbuch.

Empfehlung: gleiches Repository (eigener Ordner, eigenes Xcode-Projekt, eigene Bundle-ID, eigener Skip-Ordner), Datenschicht von Anfang an SQLite über die Store-Protokolle des Pakets, kein Sync.

## Schritt 1 (erledigt): der Planer im Paket

`KitchenScheduler` in `BakePlannerCore/Sources/BakePlannerCore/KitchenScheduler.swift`, Tests in `KitchenSchedulerTests.swift`, die drei Gerichte in `KitchenDishes.swift`.

Modell: Ein Schritt (`KitchenTask`) hat **Handarbeit** (Minuten, in denen der Koch gebunden ist), danach **unbeaufsichtigte Zeit** („kochen lassen“), ein **Gerät** (Platte oder Ofen, belegt von Anfang bis Ende), **Vorgänger** (Schritte, die fertig sein müssen) und eine **Höchstwartezeit** (`maxWait`): wie lange das Ergebnis liegen darf, bis der nächste Schritt es braucht. 0 für „wenden“ nach dem Anbraten, 3 für geruhtes Fleisch bis zum Tranchieren, 10 für eine Sauce, die warm steht; ohne Angabe hält sich das Ergebnis. Die Küche hat Platten und Öfen (`Kitchen`, Standard 4 und 1).

Planung: vorwärts ab Minute 0. Zu jedem Zeitpunkt startet unter den startbereiten Schritten der mit der längsten Kette vor sich, sofern die Hände und das Gerät frei sind; Schritte ohne Handarbeit (Vorheizen, Ruhen) zuerst, bei Gleichstand der mit unbeaufsichtigter Zeit (der Topf vor dem Messer). Sobald ein Schritt mit Höchstwartezeit läuft, hat sein Folgeschritt einen **Zeitpunkt**, bis zu dem er beginnen muss: Bis dahin startet keine Handarbeit, die darüber hinausliefe, außer Arbeit, auf die der Folgeschritt selbst noch wartet. Reicht das nicht, weil der Folgeschritt auf etwas anderes wartet (die Haut im Ofen, eine belegte Platte), wird der Vorgänger im nächsten Durchlauf **zurückgehalten** und erst so spät begonnen, dass die Wartezeit eingehalten wird; das wiederholt sich die Kette hinauf, bis jede Vorgabe gehalten ist oder nichts mehr hilft. Was dann noch zu spät kommt (zwei Dinge, die ein Koch im selben Moment wenden müsste), steht in `lateFollowUps`. Fertige Teile, die lange liegen, listet `waits(atLeast:)` als **Warmhalte-Hinweis**.

Ergebnis (`KitchenSchedule`): Zeitleiste, Gesamtdauer, **kritischer Pfad** (längste Kette), **Handminuten** gesamt und je Komponente, Wartezeiten („Birne wartet 11 Minuten aufs Anrichten“), verpasste Höchstwartezeiten, Startzeiten auf der Uhr für eine Servierzeit, und bei Überschreitung des Budgets der **Grund**:

| Grund | Bedeutung |
|---|---|
| `criticalPath` | Die längste Kette ist länger als das Budget. Parallel arbeiten hilft nicht; nur kürzere Schritte helfen. |
| `hands` | Die Handarbeit allein übersteigt das Budget. Eine Person reicht nicht; Schritte streichen oder vereinfachen. |
| `packing` | Kette und Hände passten, aber sie kollidieren an Händen oder Geräten. |

## Die drei Gerichte (Menü vom 19.11.2026, Warenkorb Mario Kotaska)

Alle Zeiten sind **Schätzungen von Claude** für einen geübten Hobbykoch; die Rezepte nennen fast keine Arbeitszeiten. Hans-Peter lässt sie vorerst stehen, auch wenn die 35 Minuten damit nicht erreicht werden (19.11.). Budget 35 Minuten, 4 Platten, 1 Ofen; **die Öfen sind vorgeheizt, wenn die Uhr startet** (wie in der Sendung), deshalb gibt es keinen Vorheiz-Schritt. Die Gerichte liegen als `KitchenSampleDishes` im Paket und dienen der App als erste Daten. „Hände“ = Minuten gebunden, „allein“ = danach ohne Koch, „liegt max.“ = Höchstwartezeit des Ergebnisses bis zum nächsten Schritt (leer = hält sich).

### A. Gebratene Perlhuhnbrust mit Bergkäse-Rahm-Wirsing, Kräuterseitlingen und Verjus-Birne (Matthias Gaugl)

| Nr. | Schritt | Hände | allein | Gerät | nach | liegt max. |
|---|---|---|---|---|---|---|
| a1 | Perlhuhn trocken tupfen, Sehnen entfernen, Haut salzen | 2 | | | |  |
| a2 | Perlhuhn auf der Haut braten | 1 | 5 | Platte | a1 | 0 |
| a3 | Wenden, Butter, Knoblauch, Thymian, arrosieren | 3 | | Platte | a2 | 0 |
| a4 | Perlhuhn ruhen lassen | 0 | 5 | | a3 | 3 |
| a5 | Perlhuhn würzen und tranchieren | 2 | | | a4 | 3 |
| w1 | Wirsing in Streifen, Schalotte und Knoblauch würfeln | 5 | | | |  |
| w2 | Anschwitzen, Wirsing zugeben, Fond und Sahne angießen | 4 | | Platte | w1 |  |
| w3 | Wirsing cremig garen | 0 | 7 | Platte | w2 |  |
| w4 | Bergkäse reiben | 2 | | | |  |
| w5 | Miso anrühren, Käse unterziehen, abschmecken | 2 | | Platte | w3, w4 |  |
| p1 | Kräuterseitlinge in Scheiben schneiden | 3 | | | |  |
| p2 | Pilze ohne Bewegung goldbraun braten | 1 | 3 | Platte | p1 | 0 |
| p3 | Wenden, zweite Seite, Butter, Knoblauch, Thymian, würzen | 3 | | Platte | p2 |  |
| b1 | Birne vierteln, entkernen, schneiden | 2 | | | |  |
| b2 | Birne anbraten, Honig, Verjus, glasieren | 5 | | Platte | b1 | 10 |
| g1 | Orange reiben, Kräuter zupfen, Käse reiben | 2 | | | |  |
| s1 | Anrichten | 3 | | | a5, w5, p3, b2, g1 |  |

**Ergebnis:** 44 Minuten, **fehlen 9**, Grund **Hände** (40 Handminuten, kritischer Pfad nur 21). Handarbeit je Komponente: Wirsing 13, Perlhuhn 8, Pilze 7, Birne 7, Anrichten 3, Garnitur 2. Ohne die Höchstwartezeiten wären es 40 Minuten: Die Frische kostet 4, weil das Perlhuhn (anbraten, wenden, ruhen, tranchieren) ans Ende rückt und die Hände dort zweimal kurz leer laufen. Der Planer legt das Fleisch in Minute 20 ein, wendet es in 26, lässt es 29–34 ruhen und tranchiert 36–38 fürs Anrichten um 41. Warmhalte-Hinweise: Garnitur 21 min, geschnittene Pilze 20, Wirsing 18, geschnittene Birne 13.

### B. Gefüllte Wirsingrolle mit Sahnesauce, Birnen-Haselnuss-Kompott und Estragon-Öl (Christina Schomburg)

| Nr. | Schritt | Hände | allein | Gerät | nach | liegt max. |
|---|---|---|---|---|---|---|
| r1 | Perlgraupen waschen, mit Lorbeer in Salzwasser kochen | 2 | 25 | Platte | |  |
| r2 | Wirsingblätter von den Adern befreien | 3 | | | |  |
| r3 | Wirsingblätter in Salzwasser garen | 1 | 8 | Platte | r2 |  |
| r4 | Blätter abtropfen lassen | 1 | | | r3 |  |
| r5 | Haut abziehen, Fleisch vom Knochen lösen, würfeln | 3 | | | |  |
| r6 | Haut langsam ausbraten | 1 | 8 | Platte | r5 |  |
| r7 | Fleisch in Öl anbraten | 3 | | Platte | r5 |  |
| r8 | Kräuterseitlinge klein schneiden, anbraten, würzen | 4 | | Platte | |  |
| r9 | Käse fein würfeln | 1 | | | |  |
| r10 | Graupen abgießen, Füllung mischen, mit Verjus abschmecken | 3 | | | r1, r7, r8, r9 |  |
| r11 | Blätter füllen, rollen, rundherum anbraten | 5 | | Platte | r10, r4 |  |
| k1 | Birne schälen, entkernen, würfeln | 2 | | | |  |
| k2 | Birne in Butter dünsten, abschmecken | 2 | 5 | Platte | k1 |  |
| n1 | Haselnüsse im Ofen rösten | 1 | 8 | Ofen | |  |
| n2 | Nüsse hacken und unterheben | 1 | | | n1, k2 |  |
| s1 | Sahne und Fond reduzieren | 1 | 8 | Platte | |  |
| s2 | Sauce mit Verjus und Miso abschmecken | 1 | | | s1 |  |
| e1 | Öl auf 60 °C erhitzen | 1 | 3 | Platte | |  |
| e2 | Estragon pürieren, passieren, salzen | 3 | | | e1 |  |
| x1 | Anrichten | 3 | | | r11, n2, s2, e2 |  |

**Ergebnis:** 43 Minuten, **fehlen 8**. Kritischer Pfad 38 Minuten (Graupen 27 → Füllung 3 → Rollen und Anbraten 5 → Anrichten 3), also schon die Kette über dem Budget; die Hände mit 42 Minuten noch mehr. Das Rezept passt nur, wenn die Graupen kürzer kochen oder die Füllung ohne sie beginnt. Hier hat kein Schritt eine Höchstwartezeit; Warmhalte-Hinweise für Pilze (14 min), Nüsse (13), Sauce (13), Fleisch (11), Kompott (10), Wirsingblätter (10).

### C. Geschnetzeltes von der Perlhuhnbrust in Verjus-Estragon-Rahm, Kräuterseitlinge, karamellisierte Birne, knusprige Haut (Fanny Pietzschmann)

| Nr. | Schritt | Hände | allein | Gerät | nach | liegt max. |
|---|---|---|---|---|---|---|
| m1 | Haut lösen, Fleisch in Streifen, Schalotte würfeln, Estragon schneiden | 6 | | | |  |
| m2 | Fleisch 60 Sekunden scharf anbraten, herausnehmen, würzen | 2 | | Platte | m1 | 1 |
| m3 | Schalotte, ablöschen, einkochen, Fond reduzieren, Sahne sämig | 4 | 4 | Platte | m2 | 10 |
| m4 | Kalte Butter, Estragon, Fleisch warmziehen | 2 | | Platte | m3 | 3 |
| h1 | Haut zwischen Backpapier, beschweren, in den Ofen | 2 | | | m1 |  |
| h2 | Haut goldbraun backen (20 von „20–25“) | 0 | 20 | Ofen | h1 |  |
| h3 | Haut salzen | 1 | | | h2 |  |
| p1 | Kräuterseitlinge in Scheiben, Schalotte würfeln | 4 | | | |  |
| p2 | Pilze 2 Minuten anbraten, wenden, salzen, Thymian | 4 | | Platte | p1 | 0 |
| b1 | Birne in Spalten schneiden, entkernen | 2 | | | |  |
| b2 | Birne 2 Minuten pro Seite karamellisieren | 5 | | Platte | b1 | 10 |
| g1 | Haselnüsse grob hacken | 2 | | | |  |
| x1 | Anrichten | 3 | | | m4, h3, p2, b2, g1 |  |

**Ergebnis:** 37 Minuten, **fehlen 2**, Grund **Hände** (37 Handminuten). Kritischer Pfad 32 Minuten (Haut lösen und Fleisch schneiden 6 → Haut einlegen 2 → backen 20 → salzen 1 → Anrichten 3); mit vorgeheiztem Ofen passt die Kette ins Budget. Die Höchstwartezeiten der Sauce schieben Anbraten, Sauce und Warmziehen nach hinten (Minute 14–33), so dass das Fleisch nicht 15 Minuten steht; dadurch liegen die Hände dichter, und der Plan ist eine Minute kürzer als ohne.

| Gericht | Dauer | Budget 35 | Grund | Kette | Hände |
|---|---|---|---|---|---|
| A Perlhuhnbrust | 44 min | fehlen 9 | Hände | 21 | 40 |
| B Wirsingrolle | 43 min | fehlen 8 | Hände, Kette ebenfalls über 35 | 38 | 42 |
| C Geschnetzeltes | 37 min | fehlen 2 | Hände | 32 | 37 |

### Was die drei Pläne zeigen

- Der Planer antwortet, wie erhofft: nicht nur „passt nicht“, sondern **woran** es liegt und **welche Komponente** die Hände frisst. Bei A und C würde eine Vereinfachung der Garnitur oder der Birne reichen; bei B ist das Rezept selbst zu lang.
- Dass alle drei knapp nicht passen, liegt auch an den Schätzungen. In der Sendung schaffen es die Kandidaten, mit sichtbarer Hektik. Sind meine Handzeiten je Schritt eine Minute zu hoch, kippen A und C ins Passende.
- Die Höchstwartezeiten ändern die Pläne so, wie ein Koch denkt: Fleisch und Sauce rücken ans Ende, Vorbereitung nach vorn. Das kostet bei A vier Minuten, weil eine Person am Ende nicht alles gleichzeitig kann; bei C spart es eine.
- Welche Schritte eine Höchstwartezeit brauchen, ist Rezeptwissen, kein Planerwissen: Ohne die 0 am Arrosieren begann das Ruhen 13 Minuten nach der Pfanne. Beim Import muss diese Angabe mitkommen (KI-Vorschlag, Koch korrigiert).

## Was der Planer noch nicht kann (Reihenfolge nach Nutzen)

1. **Spannen statt Punktzeiten** („20–25 Minuten backen“), wie die Schrittfenster in BakePlanner.
2. **Ofentemperatur** als Konflikt (160 °C Haut gegen 220 °C Gratin). Vorlage: `BakePlan` und die Ofenteilung im Backtag-Optimierer.
3. **Neuplanung während des Kochens**, wenn ein Schritt früher oder später fertig wird.
4. **Vorschläge** („Kartoffeln kleiner schneiden: 15 statt 20 Minuten“) brauchen Wissen über Schritte, das erst mit dem Import und einer Tabelle üblicher Zeiten kommt.
5. **Warmhalten als Platz**: Eine warm gestellte Sauce belegt eigentlich eine Platte auf kleiner Flamme; heute nur ein Hinweis.
6. Das Zurückhalten ist eine Heuristik: Es nimmt den ersten Plan ohne verpasste Wartezeit, nicht den kürzesten. Bei A bleiben so zweimal zwei Minuten Hände ungenutzt. Ein besserer Suchlauf (mehrere Reihenfolgen probieren, die kürzeste behalten) ist später möglich, die Pläne sind klein.

## Schritt 2 (begonnen 19.11.): das App-Gerüst „CookPlanner“

Arbeitstitel **CookPlanner** (Ordner `CookPlanner/`, Bundle-ID `de.hpm64625.CookPlanner`), im selben Repository neben BakePlanner, iOS zuerst. Die Dateien liegen im Ordner; das Xcode-Projekt legt Hans-Peter an, weil Projektdateien bei offenem Xcode nicht von außen geschrieben werden (siehe unten).

| Datei | Inhalt |
|---|---|
| `CookPlannerApp.swift` | Einstieg, zeigt `DishListView` |
| `Theme.swift` | Palette, Schriften, Karten aus BakePlanner, ohne Bäckerei-Foto |
| `CookSettings.swift` | Budget, Platten und Öfen in den Defaults; `DishPlan` = Gericht + Plan + Wortlaut des Urteils |
| `DishListView.swift` | Liste der Beispielgerichte mit Urteil („Passt in 35 Minuten“ / „Fehlen 9 Minuten“), Einstellungsblatt |
| `DishPlanView.swift` | Urteil mit Begründung, Kette und Handminuten, Handarbeit je Komponente als Balken, Zeitplan, Warmhalte-Hinweise, „Kochen starten“ |
| `CookModeView.swift` | Countdown, „Jetzt“ (Hände), „Gleich“, „Läuft von allein“, Erledigt-Zähler; die Uhr ist die des Plans, Neuplanung fehlt noch |
| `Localizable.xcstrings` | 40 Texte, de/en/fr (de explizit, weil die Entwicklungsregion eines neuen Projekts en ist) |
| `Assets.xcassets` | leeres App-Symbol, Akzentfarbe |

Noch ohne eigene Datenhaltung: Die Gerichte kommen aus `KitchenSampleDishes` im Paket. Der Store (SQLite über die Paket-Protokolle) kommt mit dem Import.

**Projekt anlegen (Hans-Peter, einmalig):** In Xcode *File → New → Project → iOS → App*, Product Name `CookPlanner`, Organization Identifier `de.hpm64625`, Interface SwiftUI, Language Swift, Testing System None, Storage None; **außerhalb** des Repositories speichern. Dann nur den Ordner `CookPlanner.xcodeproj` in die Wurzel des Repositories neben `BackPlaner.xcodeproj` kopieren (die vom Assistenten erzeugten Quelldateien werden nicht gebraucht; der Projektordner `CookPlanner` ist der im Repository). Projekt öffnen, *File → Add Package Dependencies → Add Local…* → Ordner `BakePlannerCore`, Produkt `BakePlannerCore` dem Target `CookPlanner` hinzufügen. Deployment Target iOS 26. Bauen.

## Nächste Schritte

1. Xcode-Projekt anlegen (Hans-Peter), erster Build und Lauf auf dem Simulator, Bild ins Dokument.
2. `scripts/check-repo.py` prüft dann auch `CookPlanner.xcodeproj`; Xcode-Cloud-Workflow für CookPlanner.
3. Neuplanung im Kochmodus („fertig“ früher oder später), Spannen, Ofentemperatur.
4. Import mit Arbeitszeiten, Abhängigkeiten und Höchstwartezeiten (KI schlägt vor, der Koch korrigiert), eigener Store, Store-Texte, Android über Skip.
