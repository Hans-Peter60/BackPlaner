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

Alle Zeiten sind **Schätzungen von Claude** für einen geübten Hobbykoch; die Rezepte nennen fast keine Arbeitszeiten. Hans-Peter lässt sie vorerst stehen, auch wenn die 35 Minuten damit nicht erreicht werden (19.11.). Budget 35 Minuten, 4 Platten, 1 Ofen; **die Öfen sind vorgeheizt, wenn die Uhr startet** (wie in der Sendung), deshalb gibt es keinen Vorheiz-Schritt. Die Gerichte liegen als `KitchenSampleDishes` im Paket und dienen der App als erste Daten. „Hände“ = Minuten gebunden, „allein“ = danach ohne Koch, „liegt max.“ = Höchstwartezeit des Ergebnisses bis zum nächsten Schritt (leer = hält sich). Fenster aus den Rezepten: a2 5–6, w3 6–8, h2 20–25 Minuten.

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

Arbeitstitel **CookPlanner** (Ordner `CookPlanner/`, Projekt `CookPlanner.xcodeproj`, Bundle-ID `de.hpm64625.CookPlanner`), im selben Repository neben BakePlanner, iOS zuerst. Das Projekt hat Hans-Peter am 19.11. in Xcode 27 angelegt (Projektdateien werden bei offenem Xcode nicht von außen geschrieben); es liegt im neuen Format `project.xcproj` (JSON) statt `project.pbxproj`, mit dem Ordner `CookPlanner` als synchronisiertem Ordner und dem lokalen Paket `BakePlannerCore`. `scripts/check-repo.py` prüft, dass Ordner und Paket existieren. Erster Build und Lauf auf dem iPhone-17e-Simulator am 19.11.: Liste, Plan, Kochmodus und Einstellungen funktionieren, Texte auf Deutsch. Deployment Target steht auf 27.3 (Vorgabe von Xcode); BakePlanner und das Paket verlangen 26.0.

| Datei | Inhalt |
|---|---|
| `CookPlannerApp.swift` | Einstieg, zeigt `DishListView` |
| `Theme.swift` | Palette, Schriften, Karten aus BakePlanner, ohne Bäckerei-Foto |
| `CookSettings.swift` | Budget, Platten und Öfen in den Defaults; `DishPlan` = Gericht + Plan + Wortlaut des Urteils |
| `DishListView.swift` | Liste der Beispielgerichte mit Urteil („Passt in 35 Minuten“ / „Fehlen 9 Minuten“), Einstellungsblatt |
| `DishPlanView.swift` | Urteil mit Begründung, Kette und Handminuten, Handarbeit je Komponente als Balken, Zeitplan, Warmhalte-Hinweise, „Kochen starten“ |
| `CookModeView.swift` | Countdown, „Jetzt“ (Hände) mit Haken je Handgriff, „Gleich“, „Läuft von allein“ (Haken für früher fertig), Erledigt-Zähler; nach jedem Haken und jeder Minute wird der Rest des Plans vom letzten Live-Plan aus neu gelegt (`KitchenScheduler.replan`), die Uhr zeigt „Fertig in Minute X, Y Minuten früher/später als geplant“; **Pause** hält die Uhr an (Pausenzeit wird abgezogen), **Rückgängig** nimmt den letzten Haken zurück, der Schritt ist dann wieder in Arbeit und was vorgerückt war, wartet wieder |
| `Localizable.xcstrings` | 40 Texte, de/en/fr (de explizit, weil die Entwicklungsregion eines neuen Projekts en ist) |
| `Assets.xcassets` | leeres App-Symbol, Akzentfarbe |

Noch ohne eigene Datenhaltung: Die Gerichte kommen aus `KitchenSampleDishes` im Paket. Der Store (SQLite über die Paket-Protokolle) kommt mit dem Import.

Bauen von der Kommandozeile: `xcodebuild -project CookPlanner.xcodeproj -scheme CookPlanner -destination 'id=<udid>' build`. Es gibt noch keine Tests im Projekt; die Logik ist im Paket getestet.

### Neuplanung beim Kochen (erledigt 19.11.)

`KitchenScheduler.replan(tasks, kitchen:, budget:, previous:, progress:)` setzt den Plan ab der aktuellen Minute fort. `KitchenProgress` trägt die Minute und die abgehakten Schritte mit ihrer Minute. Regeln:
- Abgehakte Schritte sind Fakten: Ende = Minute des Hakens, Beginn wie geplant oder früher.
- Ein Schritt gilt als begonnen, wenn sein geplanter Beginn vor jetzt liegt, seine Vorgänger bis dahin fertig waren und die Hände in dem Moment nicht auf einem anderen Schritt lagen. Hinter einem überfälligen Schneiden hat also nichts begonnen, was der Plan auch sagte.
- Ein reiner Handgriff hält die Hände, bis er abgehakt ist; überfällig gilt er als „braucht noch eine Minute“, Minute für Minute. Schritte mit unbeaufsichtigtem Teil enden nach der Uhr und können früher abgehakt werden.
- Alles Übrige wird ab jetzt neu gelegt, um das Laufende herum (Hände, Platten, Ofen bleiben belegt).
- Ein begonnener Schritt wird mit den Dauern seiner Aufgabe ab seinem Beginn fortgeschrieben, nicht mit den Zeiten der letzten Platzierung: Ein zurückgenommener Haken hinterlässt dort das Ende des Hakens (Test `tickTakenBack`).
- Der Kochmodus plant **vom letzten Live-Plan** aus weiter, nicht vom ursprünglichen: Sonst galt ein vorgezogener Schritt jede Minute wieder als nicht begonnen, und das Ende rutschte jede Minute um eine Minute (auf dem Simulator gefunden, Test `continuedPlanStandsStill`).

### Mitteilungen im Kochmodus (erledigt 20.11.)

`CookReminders`: lokale Mitteilungen, damit das iPhone beim Kochen gesperrt liegen darf – eine, wenn ein Handschritt beginnt („<Schritt>“ / „<Komponente> · jetzt dran“), eine, wenn ein Topf- oder Ofenschritt seine Zeit hinter sich hat („… · die Zeit ist um“). Sie folgen dem Live-Plan: beim Start, nach jedem Abhaken, Rückgängig und jeder Neuplanung neu gesetzt (nur wenn sich der Plan wirklich geändert hat), in der Pause und beim Beenden gelöscht; im Vordergrund mit Ton als Banner. Erlaubnis wird beim ersten „Start“ erfragt. Grenze des Verfahrens: Während das Telefon gesperrt ist, plant die App nicht neu; hakt der Koch nicht ab, meldet sich der nächste Schritt zur ursprünglichen Minute, und erst beim Öffnen rückt der Plan nach. Geprüft im Simulator (Banner in Minute 6 für „Haut zwischen Backpapier …“). Beim Start und beim Beenden räumt die App auch zugestellte Mitteilungen früherer Durchgänge aus der Mitteilungszentrale.

**Live-Aktivität (erledigt 20.11.):** Target `CookPlannerWidgetsExtension` (Ordner `CookPlanner/CookPlannerWidgets/`, von Hans-Peter in Xcode angelegt, „Supports Live Activities“ in der App), `CookActivityAttributes` (gemeinsame Datei beider Targets, nur Foundation, kein BakePlannerCore in der Extension), `CookActivityManager` (starten, aktualisieren, beenden; Stale-Date = Beginn des nächsten Handschritts, so springt der Sperrbildschirm ohne App auf „Jetzt dran“), `CookActivityWidget` (Sperrbildschirm: Label Jetzt/Jetzt dran/Warten/Pause, Schritt mit Komponente, „Gleich <Countdown> · <Schritt>“, rechts Countdown bis zum Anrichten und „n von m“; Dynamic Island kompakt Pfanne + Restzeit). Der Kochmodus speist sie bei Start, Abhaken, Rückgängig, Neuplanung, Pause und Weiter; „Beenden“ und das Schließen der Ansicht beenden sie. Eigener Katalog `CookPlanner/CookPlannerWidgets/Localizable.xcstrings` (de/en/fr, in `check-repo.py`). Im Simulator (iPhone 17e, ohne Dynamic Island) geprüft: Erstanzeige nach der Systemfrage „Live-Aktivitäten erlauben?“, Aktualisierung nach Abhaken, Pause zeigt „30 Min.“ statt Countdown, Beenden entfernt sie. Die Dynamic Island ist nur auf einem Gerät mit Island zu sehen.

### Planer-Feinschliff (erledigt 20.11.)

Zwei Befunde aus dem Import-Benchmark: **Die Höchstwartezeit bindet nur den ersten Nachfolger.** Beim Geschnetzelten hat das scharfe Anbraten `maxWait` 0 mit zwei Nachfolgern, dem Ablöschen in derselben Pfanne und dem Warmziehen am Ende; das Fleisch darf bis dahin liegen, so will es das Rezept. Sobald ein Nachfolger das Ergebnis genommen hat, setzt der Vorgänger keinem anderen mehr eine Frist, und `lateFollowUps` misst nur den ersten Nachfolger (Test `firstFollowUpOnly`; C ohne gemeldete Verspätung). **Drei Reihenfolgen statt einer.** Der Planer platziert jetzt mit drei Prioritäten (Hände-freies zuerst; längste Kette zuerst; Frisches zuletzt, also Schritte mit Höchstwartezeit hinter die anderen) und behält den besten Plan nach „Verspätung plus Länge“ (Tests `orderingsCompared`, `restedMeat` jetzt 15 statt 20 Minuten). Im Benchmark: B 40 statt 41, C ohne Verspätung, A unverändert 37 mit 6 Minuten Wartezeit des Perlhuhns – dort reicht keine der drei Reihenfolgen, weil das Fleisch früh in die Pfanne muss, damit die Hände danach frei sind.

### Import von Webseiten (Teil 1 erledigt 20.11.)

„+“ → „Aus Webseite importieren“ (`DishWebImportView`): Adresse eintippen oder einsetzen, die Seite lädt auf dem Gerät über `RecipeWebPageLoader` aus dem Paket (schema.org-Rezeptdaten zuerst, dann der lesbare Seitentext, zusammen höchstens 50 000 Zeichen), der Text geht an `analyzeDishSteps`, das Ergebnis in den Editor; Herkunft `web`. Die Ergebnis-Abschnitte teilen sich Text- und Web-Import (`DishImportResultSections`). Geprüft mit einem Chefkoch-Rezept (Reis-Hähnchen-Pfanne): Seite in unter einer Sekunde, Analyse 30 s bzw. 2 min, 7 Schritte in 2 Komponenten, passt in 35 Minuten; zwei Läufe derselben Seite unterscheiden sich in Komponentennamen und einzelnen Minuten – die KI ist nicht deterministisch, der Koch prüft ohnehin. Der Editor lässt sich nicht mehr wegwischen (ein Import wäre sonst stumm verloren), nur „Abbrechen“. Vorbereitet für die Share-Extension: `PendingDishImport` (App Group `group.de.hpm64625.CookPlanner`, Deep Link `cookplanner://import-web?url=…`), die Liste reagiert auf den Link und auf eine geparkte Adresse beim Aktivwerden; die Analyse startet nur von selbst, wenn die Adresse aus der Extension kommt (sonst könnte jede Webseite einen Cloud-Import auslösen). **Teil 2 (erledigt 20.11.): Share-Extension** `CookPlannerShare` (Target von Hans-Peter angelegt; App Group `group.de.hpm64625.CookPlanner` auf App und Extension, URL-Schema `cookplanner` in `CookPlanner/CookPlanner/Info.plist`, `PendingDishImport.swift` in beiden Targets). `ShareViewController` + `ShareImportView` nach dem Muster von BackPlanerShare: Aktivierungsregel „genau eine Webadresse“, Blatt mit „Importieren“/„Abbrechen“, Adresse in die App Group, App über den Deep Link öffnen (Responder-Chain-Trick wie bei BakePlanner), Rückfall „öffne die App selbst“. Eigener Katalog `CookPlanner/CookPlannerShare/Localizable.xcstrings` (de/en/fr, in `check-repo.py`). Geprüft im Simulator aus Safari (Chefkoch, Hähnchen-Reis-Pfanne): CookPlanner erscheint im Teilen-Menü, die App kommt nach „Importieren“ sofort nach vorn, die Analyse läuft von selbst an, nach 30 s „Gefunden“ mit 6 Schritten. Offen: Im Teilen-Menü steht noch das generische Symbol, weil die App kein eigenes Icon hat (kommt mit Schritt 4); der Seitentitel bringt bei Chefkoch den Autorenzusatz „von …“ mit – beim nächsten Prompt-Update „Titel ohne Autor“ ergänzen.

### App-Symbol (20.11.)

Name bleibt **CookPlanner** (Entscheidung 20.11.). Das Symbol folgt der Familie von BakePlanner: warmes Orange, das zu Schwarz ausläuft, ein Held in der Mitte – hier die Pfanne mit Spiegelei –, rechts unten die Plakette, hier eine Stoppuhr statt des Kalenders (mit Tiefe seit 23.11.). Gezeichnet mit Core Graphics in `scripts/cookplanner/cookplanner-icon.swift` (`swift scripts/cookplanner/cookplanner-icon.swift` schreibt `CookPlanner/CookPlanner/Assets.xcassets/AppIcon.appiconset/icon.png`, 1024 × 1024 ohne Alpha). BakePlanners Symbol ist ein fotorealistisches Bild aus einem Bildgenerator; wer das für CookPlanner nachzieht, ersetzt einfach die PNG-Datei. Prompt-Vorschlag dafür steht im Chat vom 20.11.: gusseiserne Pfanne von schräg oben, orange Glut-Hintergrund mit schwarzer Vignette, cremefarbene Stoppuhr-Plakette rechts unten im Stil der BakePlanner-Kalenderplakette.

### Zutaten und Einkaufsliste (erledigt 21.11.)

Wunsch Hans-Peter: Einkaufsliste und die Zutaten am Kochschritt. **Modell** (#195): `KitchenIngredient` (Name, Menge, Einheit, Komponente, Hinweis) am Gericht, `ingredientIDs` am Schritt; Dateiformat 2, SQLite-Schema 2 (`ingredient`, `step_ingredient`), Cloud-Antwort mit `ingredients` und `ingredientIndices` je Schritt, Prompt fragt danach und nach einem Titel ohne Autorenzusatz – **Function noch nicht deployt**. **Oberfläche** (dieser Schritt): Abschnitt „Zutaten“ im Editor mit eigenem Blatt (Menge, Einheit mit Schnellwahl, Komponente, Hinweis; Löschen nimmt die Zutat auch aus den Schritten), im Schritt-Blatt „Zutaten dieses Schritts“ zum Anhaken (die der eigenen Komponente zuerst); im Kochmodus steht unter jedem Schritt in „Jetzt“ und „Gleich“ eine Korb-Zeile mit den Zutaten; Plan-Karte „N Zutaten“ und Korb in der Leiste öffnen die **Einkaufsliste** nach Komponenten, zum Abhaken (gemerkt je Gericht), „Alle abhaken“/„Zurücksetzen“ und Teilen der offenen Posten als Text. Die drei Beispielgerichte haben ihre Zutaten aus den Sendungsrezepten samt Zuordnung zu den Schritten (`KitchenShoppingList`, Tests). Geprüft im Simulator.

### Stoppuhr und Protokoll (erledigt 21.11.)

Wunsch Hans-Peter: die Uhr umdrehen. Der Kochmodus zeigt jetzt die Stoppuhr ab 0:00 (Pausen zählen nicht), darunter „Plan N Min. · noch mm:ss“ bzw. die Zeit über dem Plan. Jedes Abhaken merkt sich die Sekunde; „Erledigt“ listet die Schritte mit ihrer Zeit. „Beenden“ fragt „Beenden und Protokoll sichern“, „Beenden ohne Protokoll“ oder „Weiterkochen“ (als Meldung, der Dialog zeigte auf dem iPhone kein Weiterkochen). Das **Protokoll** (`KitchenCookRun`, JSON-Datei `cook-runs.json` neben der Datenbank, `CookRunLog`) hält je Schritt fest: erledigt bei, gebraucht, geplant, Unterschied; ein Handschritt zählt ab dem vorigen Abhaken oder ab seiner Planminute, wenn die später lag; Töpfe und Wartezeiten ohne Abhaken enden nach Plan (Uhr-Symbol). Ein vorzeitig beendeter Durchgang sagt „Vorzeitig beendet: n von m Schritten“ statt eines Unterschieds. Auf dem Plan steht die Karte „Gekocht“ mit den letzten Durchgängen. Später: aus den Protokollen die Schätzungen des Gerichts nachstellen.

### Ablaufplan als PDF (23.11.)

Wunsch Hans-Peter: die Zeitachse eines Gerichts ausgeben oder drucken, mit allen Texten und Zutaten, wahlweise mit Startuhrzeit. Auf dem Plan der Drucker-Knopf öffnet „Ablaufplan als PDF“: Schalter „Mit Startzeit“ (Datum und Uhrzeit, voreingestellt die übernächste Viertelstunde, darunter „Fertig um …“), dann „PDF teilen oder drucken“ (Teilen-Blatt mit Drucken, Sichern, Mail …). Das PDF (A4, `PlanPDFRenderer`, Inhalt `KitchenPlanSheet` im Paket mit Tests): Kopf mit Urteil, Start und Ende oder „Dauer … Min., Zeiten ab Minute 0“ und Personen; **Zeitachse** als Diagramm, je Komponente eine Zeile in ihrer Farbe, Handarbeit gefüllt, „läuft allein“ gestreift, jeder Balken mit seiner Schrittnummer, Uhrzeiten oder Minuten an der Achse; **Ablauf** als Tabelle mit Nummer, Zeit von–bis, vollem Schritttext, Komponente, Händen, Zeit allein, Herd/Ofen mit Temperatur und den Zutaten des Schritts; **Zutaten** je Komponente. Es gilt die gewählte Portionszahl. Debug: `-PlanPDFSample <n> [-PlanPDFStart <Minuten nach Mitternacht>]` schreibt `Documents/plan.pdf`.

### Kochmodus aus der Entfernung lesbar (23.11.)

Wunsch Hans-Peter: Beim Schneiden oder am Herd steht man weiter weg. Der Schritt unter **„Jetzt“** steht jetzt groß: Name 30 pt halbfett über die ganze Breite (42 pt auf iPad und aufgeklappter Duo), Zutaten und Restzeit 20 pt (26 pt), der Haken ein gefüllter Knopf mit 72 × 72 pt Fläche (88 pt). „Hände frei …“ und „Fertig, anrichten!“ ebenfalls groß; „Gleich“ und „Läuft von allein“ bleiben klein, damit der aktuelle Schritt heraussticht. Die Schrift wächst mit der iOS-Textgröße mit. Neu: Solange der Kochmodus offen ist, bleibt der Bildschirm an (`isIdleTimerDisabled`). Store-Bild 04 auf allen drei Geräten neu.

### App-Symbol mit Tiefe (23.11.)

Wunsch Hans-Peter: näher an BakePlanners Symbol, mit 3D-Wirkung. `scripts/cookplanner/cookplanner-icon.swift` zeichnet jetzt Licht von links oben und Schatten für jede Form: Glut, die zu den Ecken schwarz wird; gusseiserne Pfanne mit hellem Rand, Glanzbogen, Innenwand und warm angestrahltem Boden; ein Spiegelei mit glänzendem Dotter als warmer Blickfang wie das Brot; als Plakette eine runde, gekippte Stoppuhr mit Krone, cremefarbener Lünette und orangem, glänzendem Zifferblatt (statt der flachen Karte). Weiterhin ohne Bildgenerator, 1024 × 1024 ohne Alpha.

### Robustheit 1: Daten bleiben erhalten (25.11.)

Aus einer Durchsicht der App auf Robustheit (vier Bereiche, Befunde in der PR-Beschreibung von #231). Erster Schritt, die Datensicherheit:

- **Gerichte ohne Plan verschwinden nicht mehr.** Löschte man im Editor einen Schritt, auf den andere warteten, oder stand die Küche auf 0 Öfen, kam aus dem Scheduler ein Fehler, und die Liste zeichnete die Zeile gar nicht – das Gericht war weder zu bearbeiten noch zu löschen. Jetzt: `KitchenDish.removingTasks(ids:)` hängt die Kette um den gelöschten Schritt herum zusammen, `consistent()` wirft Abhängigkeiten ins Leere, doppelte Schritt-Ids und Zutatenverweise ohne Zutat weg (Editor beim Sichern, `.cookplanner`-Import über `KitchenDishRecord.dish`). Die Liste zeigt jede Zeile; ohne Plan steht der Grund darin (`DishPlan.failure`: Ofen/Platte fehlt in den Einstellungen, Schritt wartet auf einen gelöschten, Kreis), die Plan-Ansicht zeigt „Kein Plan“ mit demselben Grund und „Bearbeiten“.
- **Kochhistorie:** `cook-runs.json` hat jetzt eine Versionsnummer (`KitchenCookRunFile`, liest auch das alte nackte Array). Lässt sich die Datei nicht lesen, wird sie nicht mehr beim nächsten Eintrag überschrieben, sondern als `cook-runs.broken-<Zeit>.json` beiseitegelegt, die Historie beginnt leer, und ein Hinweis sagt es. Eine Datei einer neueren App-Version bleibt unangetastet (nur lesen). Schreibfehler erscheinen als Hinweis statt still zu verschwinden.
- **Datenbank aus einer neueren App:** `CookPlannerDatabase` prüft `PRAGMA user_version` vor der Migration; eine neuere Datei wirft `CookPlannerDatabaseError.newerSchema` statt in SkipSQLs Migrationsschleife zu stürzen (`currentVersion..<count` mit currentVersion > count). Die App läuft dann im Arbeitsspeicher weiter.
- **Arbeitsspeicher-Betrieb ist sichtbar:** Öffnet sich die Datenbank nicht, steht oben in der Liste dauerhaft ein Hinweis (`DishLibrary.storageWarning`) statt eines einmaligen Alerts.

Offen aus der Durchsicht, in eigenen Schritten: Kochmodus (Zustand überlebt das Beenden nicht, Haken in der Hands-Phase eines Topfschritts, Wecker-Planung), Sync (Konflikte offline, Kontowechsel), Kleinkram (Import abbrechbar, Portionen unter ¼, Temp-Dateien).

### Robustheit 2: Kochmodus (25.11.)

- **Topf aufgesetzt ist nicht Topf fertig.** Bisher zeigte ein Schritt mit Hands- und Garanteil („Reis aufsetzen 2+15“) in seinen Hands-Minuten den großen Haken, und der Haken beendete den ganzen Schritt – die Garminuten verschwanden, Folgeschritte rückten vor, der Wecker fiel weg, und die gelernten Zeiten hätten `unattended = 0` vorgeschlagen. Jetzt trägt so ein Schritt in der Hands-Phase eine **Flamme** („Steht, läuft von allein“): `KitchenProgress.handsDone` merkt die Minute, `replan` setzt `handsEnd` dorthin und lässt die Garzeit von da laufen (mit Fenster bis zum Fensterende weiter, wie ein nie getickter Topf). Der Schritt wandert nach „Läuft von allein“ und wird dort abgehakt oder endet nach der Uhr. Rückgängig nimmt die Flamme zurück; sind die Hands-Minuten dann schon vorbei, gilt der Topf wie geplant als rechtzeitig aufgesetzt.
- **Ein Kochvorgang überlebt das Beenden der App.** `CookRunState` (UserDefaults) hält Start, Pausen, jeden Haken und jede Flamme; `RootTabView` öffnet den Kochmodus beim Start wieder, wenn der letzte Lauf jünger als 6 Stunden ist und das Gericht noch da; sonst wird aufgeräumt (Wecker, Erinnerungen, Live-Aktivität), was ein abgebrochener Lauf hinterließ. Geprüft im Simulator: App beendet und neu gestartet – die Uhr läuft weiter, die Haken sind da.
- **Wecker nacheinander:** `CookAlarms` plant und löscht in einer Warteschlange; ein Wecker steht erst in `scheduled`, wenn AlarmKit ihn angenommen hat. Vorher konnte eine Pause direkt nach einem Haken einen Wecker übrig lassen, der nach der Pause klingelt.
- **Erinnerungen:** `sync` ersetzt nur noch die eigenen ausstehenden Mitteilungen (`cook.start.*`, `cook.end.*`); zugestellte Banner bleiben, obwohl sich der Plan bei einem überfälligen Handschritt jede Minute ändert. Die Banner des vorigen Laufs gehen beim Start weg.
- **Berechtigungen:** Nach den Abfragen beim Start wird ab der aktuellen Minute neu geplant (vorher konnte die Signatur den Lauf ohne Wecker festhalten). Sind Mitteilungen und Wecker beide aus, sagt es eine Zeile in der Uhr-Karte.
- **Gemessene Zeiten:** Der Start eines Handschritts richtet sich nach dem letzten Zeitpunkt, an dem die Hände frei wurden (letzter Haken eines reinen Handschritts oder letzte Flamme), nicht mehr nach Topf-Haken.
- Live-Aktivität: `finishDate` aus Uhrstart + Plan, nicht aus `now`, damit ein Refresh ohne Änderung kein Update schickt.

### Steak statt Spiegelei (23.11.)

Wunsch Hans-Peter: in der Pfanne ein Steak statt des Spiegeleis. Das Skript zeichnet jetzt ein Ribeye mit angebratenem Fettrand, dunkler Kruste, drei Grillstreifen, Glanzpunkten und einem Rosmarinzweig als grünem Akzent; Pfanne, Glut und Stoppuhr bleiben. Nebenbei finden `cookplanner-icon.swift` und `play-feature-graphic.swift` den Wurzelordner wieder (seit dem Umzug nach `scripts/<app>/` eine Ebene tiefer).

### Einkaufsliste zusammengefasst (23.11.)

Wunsch Hans-Peter: Die Zutaten stehen je Komponente getrennt – fürs Kochen richtig, fürs Einkaufen nicht. Die Einkaufsliste hat jetzt **eine Zeile je Ding**: gleiche Zutaten (`IngredientNameNormalizer.comparisonKey`, wie BakePlanners Liste und Vorrat vergleichen) werden eins, die Mengen addiert – g mit kg, ml mit l, Stück mit Stück, sonst gleiche Einheit; was sich nicht addieren lässt, steht nebeneinander („50 g + 1 EL Butter“); Zutaten ohne Menge (Salz) einmal (`KitchenShoppingList.lines`, Tests). Sortiert nach Regalen wie bei BakePlanner (`ShoppingListCategory`), darunter klein die Komponenten, die die Zutat brauchen. Ein Haken gilt für alle Zutaten der Zeile; „Fehlendes teilen“ gibt die zusammengefassten Zeilen weiter. Zutatenkarte, Editor und Kochmodus bleiben je Komponente. Nebenbei: Muskatnuss steht im Regal Gewürze statt Nüsse (gilt auch für BakePlanner). Startargument `-ShoppingSample <n>` (Debug).

### Tab-Leiste statt Verlaufs-Blatt (23.11.)

Nach dem iOS-Muster (Hauptbereiche als Tabs, Aktionen in der Leiste, kurze Aufgaben als Blatt): `RootTabView` mit **Gerichte** und **Gekocht**; der Verlauf ist kein Blatt mehr, sein „Fertig“ fällt weg. Oben in „Gerichte“ bleiben Filter, „+“ und Einstellungen. Eine geöffnete Datei oder eine Seite aus der Teilen-Erweiterung holt den Tab „Gerichte“ nach vorn. Die Suchfelder stehen fest unter dem Titel (`navigationBarDrawer(.always)`), sonst blendet iOS sie mit Tab-Leiste bis zum Herunterziehen aus.

### Einkaufsliste: Vorhandenes abhaken, Fehlendes teilen (23.11.)

Entscheidung Hans-Peter: CookPlanner schreibt nicht selbst in die Erinnerungen (das bekommt nur BakePlanner). In der Einkaufsliste eines Gerichts hakt man ab, was **schon im Haus** ist (gemerkt je Gericht, Menü „Alles im Haus“/„Nichts im Haus“); der Knopf unten **„Fehlendes teilen (N)“** gibt nur den Rest weiter, eine Zutat je Zeile ohne Überschriften (`KitchenShoppingList.missingText`, Test), damit z. B. die App Erinnerungen über das Teilen-Blatt gewählt werden kann. Ob Erinnerungen beim Teilen jede Zeile zu einem eigenen Eintrag macht, ist auf dem Gerät noch zu prüfen; sonst den Text kopieren und in der Liste einfügen (das trennt nach Zeilen).

### Koch-Historie wie in BakePlanner (erledigt 22.11.)

Ausbau des Verlaufs „Gekocht“ nach BakePlanners Backhistorie. **Vier Ansichten** (Umschalter oben, gemerkt): Liste nach Monaten, **Galerie** der Fotos, **Hit-Liste** (Gerichte nach Schnitt der Sterne, dann Häufigkeit) und **Statistik** (gekocht, verschiedene Gerichte, Sterne im Schnitt, „Gegen den Plan“ aus den vollständigen Stoppuhr-Durchgängen, Balken der letzten zwölf Monate, am häufigsten gekocht; `KitchenCookStatistics` im Paket, Tests). **Suche** nach Gericht und **Mindestbewertung** (Filter oben links). **„+“ → „Gekocht eintragen“**: ein ohne Stoppuhr gekochtes Gericht mit Datum, Sternen, Notiz und Foto (`KitchenCookRun.manualEntry`, ein Eintrag ohne Schritte; das Datum eines Fotos wird übernommen). **„+“ → „Aus Fotos übernehmen“**: bis zu 30 Fotos, Datum und Titel aus den Metadaten (`PhotoMetadata`), das Gericht wird vorgeschlagen, wenn sein Name im Titel steht, je Foto änderbar oder „Nicht übernehmen“. Fotos werden verkleinert gelesen (ImageIO, 1600 px). Ein Eintrag ohne Stoppuhr zeigt im Blatt statt der Zeiten „Gekocht am“ zum Ändern. Alles gleicht sich über iCloud ab. Nicht übernommen: Fotowolke und Jahrbuch-PDF. Startargument `-HistoryDemo <list|gallery|hitList|statistics>` (Debug) für Bildschirmfotos.

### Abgleich über iCloud (erledigt 22.11.)

Wunsch Hans-Peter: iPhone und iPad mit denselben Daten. `CloudSync` mit **CKSyncEngine** in der privaten CloudKit-Datenbank, Container `iCloud.de.hpm64625.CookPlanner` (von der automatischen Signierung angelegt), Zone „CookPlanner“. Je eigenes Gericht ein Record „Dish“ (Feld `payload` = das Gericht als `KitchenDishFile` mit einem Gericht, eine spätere Formatversion wird abgelehnt), je Kochprotokoll ein Record „CookRun“ (`payload` JSON, Foto als Asset `photo`); Namen `dish-<id>`, `run-<id>`. Speichern und Löschen in `DishLibrary` und `CookRunLog` melden die Änderung, Änderungen anderer Geräte kommen über `applyRemote`/`removeRemote` ohne Rücksendung. Beim ersten Start wird alles Vorhandene hochgeladen; abgerufen wird beim Start, beim Wechsel in den Vordergrund und über stille Pushes (`aps-environment`, Hintergrundmodus remote-notification). Konflikt: die spätere Änderung gewinnt. Einstellungen (Budget, Küche, Wecker, Uhr, Sammlungen, Portionen, Einkaufshaken) bleiben je Gerät. Einstellungen → „Abgleich“ zeigt den iCloud-Stand und „Jetzt abgleichen“. **Vor TestFlight/App Store:** in der CloudKit-Konsole das Schema (Record-Typen Dish und CookRun) von Development nach Production übernehmen – Entwickler-Builds auf den Geräten nutzen die Development-Umgebung. Geprüft 22.11.: das iPhone lud 5 Gerichte und 1 Protokoll hoch, das iPad hatte danach alle.

### Auswahl der Gerichte (erledigt 22.11.)

Wie BakePlanners intelligente Sammlungen. **Suche** unten in der Liste über Name, Komponenten und Zutaten (ohne Groß/Klein und Akzente). **Leiste** mit fertigen Sammlungen: Passt ins Budget, Schnell (bis 30 Min.), Ohne Ofen, Lieblinge (Schnitt der Sterne ab 4), Noch nie gekocht, Lange nicht gekocht (60 Tage); nochmal tippen hebt auf. **Filter-Menü** (Knopf oben links neben „Gekocht“): Dauer, Geräte (mit Ofen, nur Herd, ohne Hitze), Herkunft (eigene, importiert, Beispiele), Verlauf, dazu „Passt ins Budget“ und „Wenig Handarbeit“ (Hände höchstens 60 % des Plans); „Filter zurücksetzen“ und **„Sammlung sichern“** – eigene Sammlungen stehen hinter den fertigen in der Leiste, lange drücken zum Umbenennen oder Löschen (UserDefaults `savedDishCollections`). Dauer und Budget gelten für die aktuelle Küche. Logik im Paket (`KitchenDishFacets`, `KitchenDishFilter`, `KitchenDishCollection`, `SavedKitchenDishCollection`, Tests), für Android wiederverwendbar.

### Zeitachse (erledigt 22.11.)

Wunsch Hans-Peter: ein Ablaufplan wie BakePlanners Zeitachse, damit Komponenten und Parallelen sichtbar werden. `PlanTimelineView`: Zeit läuft nach unten (14 pt je Minute, Linien alle 5, kräftiger alle 15 Minuten), je Komponente eine Spalte in eigener Farbe, je Schritt ein Balken von Start bis Ende – Handarbeit hell gefüllt, die Zeit allein (Topf, Ofen, Ruhen) schraffiert, mit Platte/Ofen-Symbol und Minuten. Überlappende Schritte einer Komponente stehen nebeneinander (`KitchenTimelineLayout`, Spuren je Überlappungsgruppe, Tests); eine Spalte ist so breit, wie ihre Spuren brauchen (mind. 76 pt je Spur), passt nicht alles, scrollt die Zeitachse seitlich. Tippen auf einen Balken zeigt die Einzelheiten. Auf dem Plan ersetzt sie die Liste (Umschalter Zeitachse/Liste, gemerkt); im Kochmodus öffnet der neue Knopf oben die Zeitachse des laufenden Plans mit roter Jetzt-Linie und blassen erledigten Schritten. Startargument `-TimelineSample <n>` (nur Debug) zeigt die Zeitachse eines Beispiels für Bildschirmfotos. Im Simulator mit den drei Beispielen geprüft.

### Challenge oder Training (erledigt 21.11.)

Wunsch Hans-Peter: die Uhr wählbar. Vor dem Start steht im Kochmodus die Wahl **Challenge** (die Uhr zählt das Zeitbudget rückwärts, ohne Budget den Plan, ab der letzten Minute orange, danach rot ins Minus mit „Zeit um – m:ss drüber“) oder **Training** (Stoppuhr ab 0:00 wie bisher, mit „noch“ bzw. „über dem Plan“). Die Wahl bleibt gespeichert (`CookClockMode`, voreingestellt Challenge). Protokoll, Erinnerungen, Wecker und Live-Aktivität laufen in beiden Arten gleich.

### Gemessene Zeiten übernehmen (erledigt 21.11.)

Aus den Protokollen lernt das Gericht seine Zeiten (`KitchenTimeLearning`, Tests). Je Schritt zählt der Median der abgehakten Zeiten aus den letzten bis zu fünf Durchgängen; Schritte, die nur nach Plan endeten, zählen nicht. Ein reiner Handschritt übernimmt die Zeit als Handminuten; bei Töpfen und Ofenschritten bleibt die Handarbeit, und die Zeit allein passt sich an (ein Fenster wird bei Bedarf erweitert). Vorschläge erscheinen nur, wenn sie vom Gericht abweichen. Auf der Karte „Gekocht“ steht dann „Gemessene Zeiten für N Schritte übernehmen“; das Blatt zeigt je Schritt alt → neu und die Zahl der Durchgänge. „Übernehmen“ sichert das eigene Gericht; bei einem Beispielgericht heißt der Knopf „Als eigenes Gericht“ und legt eine Kopie mit den gemessenen Zeiten an (die Kopie hat eine neue Kennung, ihre Protokolle beginnen neu).

### Portionen und Wecker (erledigt 21.11.)

Aus BakePlanner übernommen. **Portionen** (`KitchenPortions`, Tests): Auf der Zutaten-Karte des Plans steht „Für N Personen“, wenn das Rezept die Zahl nennt, sonst „Menge ×1“ in Stufen von ×½ bis ×4; die Wahl gilt je Gericht. Nur die Mengen ändern sich, die Schritte behalten ihre Minuten. Gezählte Einheiten (Stück, Zehe, EL, TL, Prise …) runden auf halbe, mindestens ½; Gramm und Milliliter auf 10 ab 500, auf 5 ab 100, sonst auf 1 oder ½. Einkaufsliste und Kochmodus zeigen die umgerechneten Mengen, der Editor die des Rezepts. **Wecker** (`CookAlarms`, AlarmKit): Hat ein Topf oder der Ofen seine Zeit erreicht, klingelt ein Wecker, auch bei stummem iPhone und im Fokus; dieser Schritt bekommt dann keine Mitteilung „die Zeit ist um“. Die Wecker folgen dem laufenden Plan wie die Mitteilungen, Pause und Beenden nehmen sie zurück. Einstellung „Wecker für Topf und Ofen“, voreingestellt an; die Erlaubnis fragt der Start der Uhr ab. Auf dem iPhone noch nicht geprüft.

### Sichern und Teilen (erledigt 21.11.)

Gerichte als Datei: `KitchenDishFile` (Format 2, unverändert) mit der Endung **.cookplanner**, in Info.plist als exportierter Typ `de.hpm64625.CookPlanner.dishes` (konform zu JSON) mit Dokumenttyp, damit ein Tippen auf die Datei in Mail, Nachrichten oder Dateien CookPlanner öffnet. **Teilen:** Teilen-Knopf auf dem Plan eines eigenen Gerichts (Dateiname = Gerichtsname). **Sichern:** Einstellungen → „Sicherung“ → „Eigene Gerichte sichern“ (eine Datei „CookPlanner JJJJ-MM-TT.cookplanner“) und „Gerichte importieren“ über die Dateiauswahl. **Einlesen** (`KitchenDishTransfer.merge`, Tests) ersetzt nie etwas: Gerichte mit bekannter Kennung und die Beispiele bleiben, wie sie sind; ein unbekanntes Beispiel kommt als eigenes Gericht. Die Meldung sagt „N Gerichte übernommen, M waren schon da“; eine Datei aus einer neueren Version wird abgelehnt. Kochprotokolle und Portionswahl sind nicht enthalten. Auf dem iPhone noch nicht geprüft.

### Import aus Fotos (erledigt 21.11.)

Menü „+“ → „Aus Fotos importieren“: „Seiten scannen“ (Dokumentkamera von VisionKit, findet und begradigt die Seite, mehrere Seiten nacheinander) oder „Fotos auswählen“ (bis zu 4). Der Text wird **auf dem Gerät** erkannt (`PhotoTextReader`: Vision `RecognizeDocumentsRequest`, das Spalten und Listen zusammenhält, sonst zeilenweise `RecognizeTextRequest`; Deutsch, Englisch, Französisch) und landet im Textfeld, wo man ihn prüft; danach läuft die bekannte Textanalyse (`analyzeDishSteps`), das Gericht trägt die Quelle „Foto“. **Keine neue Function, kein Deploy**; die Fotos verlassen das Gerät nicht. Kamera-Zugriffstext in `InfoPlist.xcstrings`. Am Mac mit einer gezeichneten Rezeptseite geprüft; Handschrift dürfte schwächer gelingen – dann wäre eine Bild-Function wie bei BakePlanner der nächste Schritt.

### Verlauf mit Sternen, Notiz und Foto (erledigt 21.11.)

Wie BakePlanners Backhistorie, aufbauend auf den Stoppuhr-Protokollen. `KitchenCookRun` hat drei optionale Felder dazubekommen: `rating` (1–5), `note`, `photoFileName` (ältere Protokolle lesen sich weiter, Test). Das Protokoll-Blatt beginnt mit „Wie war’s?“: Sterne (nochmal tippen nimmt sie weg), Notiz, Foto aufnehmen oder wählen, vergrößern, entfernen. Fotos liegen als JPEG (längste Seite 1600 pt) in `Application Support/CookPlanner/Photos`, Vorschaubilder werden einmal je Foto gerechnet; Löschen des Protokolls löscht das Foto mit. Wer am Ende „Beenden und Protokoll sichern“ wählt, landet gleich in diesem Blatt. Die Karte „Gekocht“ auf dem Plan zeigt Vorschaubild und Sterne; der neue Knopf oben links in der Gerichteliste öffnet **„Gekocht“**, alle Durchgänge nach Monaten mit Foto, Gericht, Datum, Zeit, Sternen und Notiz. Protokolle und Fotos sind (noch) nicht in der .cookplanner-Sicherung.

### Beef Wellington (21.11.)

Hans-Peters Test mit dem Küchenschlacht-Menü vom 17.11. (Gaugl, Beef Wellington, Gratin, Jus, Salat): 65 Minuten. Nachgerechnet mit einer neuen KI-Antwort: 78 Minuten, Kette 58, Hände 54. Zwei Ursachen. **Planer:** Die Vorwärtsplatzierung nahm die Hände für eine Nebenarbeit (Gratin schneiden, Salat), während der Schritt mit der längsten Kette (Wellington einrollen, in den Ofen) Minuten später bereit wurde und dann wartete. Neue Variante „Vorausschau“: Handarbeit beginnt nicht, wenn ein Schritt mit längerer Kette fertig vorbereitet ist, bevor sie fertig wäre; sie läuft neben den drei Reihenfolgen und der beste Plan gewinnt (Test `lookAhead`). Dieselbe Antwort ergibt 69 statt 78 Minuten; die übrigen Gerichte bleiben gleich. **KI:** Sie fasste Hacken und Braten, Backen und Ruhen zu je einem Schritt zusammen und schätzte „kurz kaltstellen“ auf 10 Minuten. Der Prompt verlangt jetzt Vorbereitung und Garen als getrennte Schritte, Ruhen ohne Ofen, 5 Minuten für „kurz kaltstellen/abkühlen“ ohne Zeitangabe und Umrühren beim Einkochen als Zeit allein (Deploy durch Hans-Peter). Auch dann bleibt das Gericht mit einer Kette aus Duxelles, Kühlen, Backen und Ruhen um 45 Minuten – in der Sendung schafft man es mit Hektik.

### Zeitspannen (erledigt 19.11.)

Ein Schritt kann für seinen unbeaufsichtigten Teil ein **Fenster** tragen (`KitchenTask.unattendedWindow`, „Haut 20–25 Minuten backen“); geplant wird mit dem Nennwert, der im Fenster liegt. `KitchenScheduler.fit(tasks, kitchen:, budget:)` kürzt, wenn das Gericht nicht passt und nicht die Hände der Grund sind, die Fensterschritte auf dem kritischen Pfad (sonst beliebige) bis zur Fensteruntergrenze und nur so weit wie nötig, und liefert die Kürzungen mit (`KitchenFit.shortenings`). Die Planansicht zeigt sie als Karte „So passt es“ („Haut goldbraun backen: 22 statt 25 Minuten“); fehlt es trotz kürzester Zeiten, steht das dort. Beim Kochen läuft ein Fensterschritt nach seinem geplanten Ende weiter, bis er abgehakt wird, längstens bis zum Fensterende; der Kochmodus zeigt „noch 20–25 Min.“ bzw. „bis zu 5 Min.“. In den Beispielgerichten haben Fenster: Perlhuhn auf der Haut 5–6, Wirsing 6–8, Haut im Ofen 20–25; weil dort die Hände der Engpass sind, kürzt `fit` nichts.

### Ofentemperatur (erledigt 19.11.)

Ein Ofenschritt trägt seine Temperatur (`KitchenTask.ovenTemperature`, nur für `station == .oven`). Ein Ofen nimmt beliebig viele Schritte gleichzeitig auf, aber nur bei einer Temperatur; ein Schritt ohne Angabe passt zu jeder. Der Planer legt einen Ofenschritt zuerst in einen Ofen, der schon auf seiner Temperatur steht, sonst in einen leeren; sonst wartet er. Bei der Neuplanung behält ein laufender Ofenschritt seine Temperatur, ein Gratin bei 220 °C wartet also auf die Haut bei 160 °C. Zeitplan und Kochmodus zeigen „Ofen 160 °C“. Beispielgerichte: Haut und Haselnüsse bei 160 °C. Noch nicht modelliert: die Zahl der Einschübe und die Zeit zum Umheizen.

## Schritt 3 (Skizze 19.11.): eigene Gerichte – Editor, Speicher, Import

Bisher kennt die App nur die drei Beispielgerichte. Damit sie nutzbar wird, braucht sie eigene Gerichte: erfasst von Hand, aus Text oder Foto importiert, gespeichert auf dem Gerät.

### 3a. Editor und Speicher (gebaut 19./20.11.)

Der Prüfbildschirm nach einem Import und der Editor für ein Gericht von Hand sind **derselbe Bildschirm**; er wird also in jedem Fall gebraucht und kam zuerst.

Umgesetzt (Entscheidung 19.11.: eigener Speicher statt `BakePlannerStorage`):
- **Kern:** `KitchenDish` mit Herkunft (`KitchenDishSource`: Beispiel, Hand, Text, Foto, Web), Portionen, Datum und `duplicate()`; `KitchenDishFile` (Format 1, Codable-Datensätze mit expliziten Schlüsseln, spätere Versionen werden abgewiesen, Zahlen über `Plausible` begrenzt); Protokoll `KitchenDishStore` (alle, eines, speichern = anlegen oder ganz ersetzen, löschen) mit `KitchenDishStoreContract` und `InMemoryKitchenDishStore`; `KitchenDishDefaults.withDependencies` füllt leere Vorgänger (Schritt folgt dem vorherigen seiner Komponente, der letzte wartet auf alle Komponenten).
- **Paket `CookPlannerStorage`** (neu, `CookPlanner/CookPlannerStorage/`): `CookPlannerDatabase` (SkipSQLPlus, PRAGMA user_version-Migrationen, Tabellen `dish`, `step`, `step_dependency`), `SQLiteKitchenDishStore`; Tests: Vertrag, Bestand über Schließen und Öffnen, fehlgeschlagenes Speichern lässt den alten Stand stehen. Abhängigkeiten wie `BakePlannerStorage` (gleiche `Package.resolved`). **In Xcode muss das Paket dem Projekt `CookPlanner` als lokales Paket hinzugefügt werden** (File → Add Package Dependencies → Add Local… → `CookPlannerStorage`).
- **App:** `DishLibrary` (@Observable, Datei `Application Support/CookPlanner/dishes.sqlite`, ohne Datei fällt sie auf den In-Memory-Store zurück und meldet es), Liste mit „Meine Gerichte“ und „Beispiele“ (Wischen löscht, Kontextmenü: Bearbeiten, „Als Vorlage übernehmen“), `DishEditorView` (Name, Portionen, Schritte verschieben/löschen, Plan mit Urteil und Kürzungen, der bei jeder Änderung mitläuft, Fehler des Planers sichtbar), `StepEditorView` (Text, Komponente mit Auswahl, Hände, danach allein, Zeitspanne, Gerät, Ofentemperatur, „muss bald weitergehen“, „Wartet auf“ aus den vorherigen Schritten), „Bearbeiten“ in der Planansicht eigener Gerichte. Auf dem Simulator geprüft (20.11.): Anlegen, Schritte, Speichern, Umbenennen, Vorlage aus einem Beispiel, Löschen; ein Gericht überlebt den Neustart der App. Nachgebessert: Zeitspanne belegt sich aus der eingegebenen Dauer vor, der Umordnen-Knopf sitzt im Abschnittskopf „Schritte“ statt in der Titelleiste, die Tastatur hat „Fertig“.

Hinweise: Xcodes Build schreibt `CookPlanner/CookPlanner/Localizable.xcstrings` in seinem Format (`"key" : value`) um und zieht Texte ohne `Text(verbatim:)` als Schlüssel hinein; reine Zahlenanzeigen deshalb immer `verbatim`. Der Build-Plug-in von `skip` (über `skip-sql`) muss je Version einmal in Xcode mit „Trust & Enable“ freigegeben werden, sonst scheitert auch `xcodebuild`.

Ursprüngliche Skizze:

- **Modell:** `KitchenDish` bekommt Herkunft (Text, Foto, Web, Hand), Datum und Portionen; die Schritte bleiben `KitchenTask`. Dazu ein **versioniertes Dateiformat** (`KitchenDishFile`, `formatVersion 1`, Codable), wie `RecipeExportData` bei BakePlanner: Grundlage für den Speicher, für Sichern/Teilen und für den späteren Plattformwechsel. Nicht ohne Versionierung ändern.
- **Speicher:** Protokoll `KitchenDishStore` (alle, eines, speichern, löschen) im Paket mit Vertragstests (wie `StoreContracts/`). Erste Umsetzung: **eine JSON-Datei je Gericht** in Application Support, atomar geschrieben. Gerichte sind klein (20 Schritte), SQLite bringt hier nichts; `BakePlannerStorage` (SkipSQLPlus) bliebe als Option, wenn Historie und Bilder dazukommen. Kein Sync, wie beschlossen; Sichern über das Dateiformat.
- **Editor:** Liste der Komponenten und Schritte. Je Schritt: Text, Komponente, Hände (Minuten), danach allein (Minuten), Fenster von–bis, Gerät (keins/Platte/Ofen), Ofentemperatur, „liegt max.“, und **Vorgänger** als Auswahl aus den vorherigen Schritten. Vorgabe für die Vorgänger, damit niemand Pfeile ziehen muss: Schritte derselben Komponente folgen aufeinander; „Anrichten“ hängt vom letzten Schritt jeder Komponente ab. Unten der Plan mit Urteil und „So passt es“ wie in der Planansicht, der bei jeder Änderung mitläuft; Planerfehler (Kreis, unbekannter Vorgänger) werden angezeigt statt stumm verschluckt.
- **Liste:** eigene Gerichte oben, die Beispiele darunter (oder als „Beispiele“ einblendbar); Wischen zum Löschen; Duplizieren eines Beispiels als Vorlage.

### 3b. Import (gebaut 20.11.)

Umgesetzt: Cloud Function **`analyzeDishSteps`** (deployt 20.11. mit Freigabe) mit dem Kochschema (Titel, Portionen, Komponenten, Schritte mit Text, Komponente, Handminuten, Minuten allein, Spanne, Gerät `none/burner/oven`, Ofentemperatur, `maxWaitMinutes` mit −1 = hält sich, `dependsOn` als Indizes, Warnungen) und den Regeln im Prompt; gleiche Schutzmechanismen wie der Rezeptimport (Anmeldung, App Check, Stundenlimit), die CookPlanner-App-ID `1:936649524074:ios:73d0fac7786ca027d65b13` ist von der Monatsgrenze ausgenommen. Im Kern liest `CloudDishImport` die Antwort in ein `KitchenDish` (Zahlen über `Plausible`, nur rückwärts gerichtete Abhängigkeiten, leere Schritte raus, Vorgaben aufgefüllt; Tests). In der App: Firebase (Functions, App Check mit Debug-Provider im Simulator, anonyme Anmeldung beim ersten Import), `DishImportClient`, `DishTextImportView` unter „+“ → „Aus Text importieren“ (Text tippen oder `PasteButton`, „Analysieren“, Zusammenfassung mit Hinweisen der KI, „Prüfen und bearbeiten“ öffnet den Editor, gespeichert wird erst mit „Sichern“).

**Erster Maßstab (20.11., alle drei Sendungsrezepte als Text, Prompt der ersten Fassung):** Analyse 25–60 s. Die KI liest Komponenten, Geräte, Ofentemperatur (Haut 160 °C, 20–25) und Spannen (Wirsing 6–8, Perlhuhn 5–6) richtig und trifft die Handarbeit insgesamt fast wie meine Tabellen: A 41 (Tabelle 40), B 43 (42), C 29–30 (37). Hinweise sind brauchbar („Ruhezeit ‚einige Minuten‘ auf 3 geschätzt“, „Öl zum Anbraten fehlt in der Zutatenliste“). Drei Abweichungen mit Folgen:

| | Beobachtung | Folge im Plan | Änderung |
|---|---|---|---|
| B | Acht Schritte in der Komponente „Wirsingrolle“, `dependsOn` nur bei Füllung, Rolle und Anrichten gesetzt; die Vorgabe „Schritte einer Komponente folgen aufeinander“ kettete Graupen (25 min) → Blätter → Haut → Fleisch → Pilze | 82 statt 43 Minuten | Prompt: `dependsOn` ist Pflicht für jeden Schritt, Unabhängiges wird nicht verkettet. `CloudDishImport`: Nennt die Antwort irgendwo Abhängigkeiten, gelten sie wie angegeben (leer = kann sofort starten; nur ungültige genannt = Vorgänger der Komponente); nur eine Antwort ganz ohne bekommt die Komponenten-Ketten. Mit derselben Antwort: 47 Minuten |
| A | Höchstwartezeiten knapper als in der Tabelle (Pilze 5, Birne 10, Käse-Wirsing 10, Tranchen 3) bei 41 Handminuten: Am Ende müssen mehr Handminuten liegen, als in die letzten zehn Minuten passen | Der Planer hielt alles zurück, bis die Wartezeiten eingehalten waren: 69 Minuten mit 20 Minuten Leerlauf | `KitchenScheduler`: Eine verspätete Minute wiegt so viel wie eine Planminute; Zurückhalten lohnt nur, solange es mehr Frische spart, als es Zeit kostet (Test `holdBackWeighedAgainstLength`). Mit derselben Antwort: 42 Minuten, Perlhuhn liegt 7 und Tranchen 7 Minuten länger als gewünscht, wird gemeldet |
| A, C | Ganze Bratschritte als Handarbeit („ohne Bewegung goldbraun braten“ 5 Hände, 0 allein), Spanne 3–4 an einem Schritt ohne Zeit allein; „2 Minuten pro Seite“ als 2 Hände + 2 allein (Gesamtzeit stimmt), „60 Sekunden“ als 1 + 1 | Handarbeit eher zu hoch, Pläne pessimistisch | Prompt: Brat-, Köchel-, Reduzierzeiten ohne Eingreifen zählen allein, auch 2–3 Minuten, mit Beispiel; „pro Seite“ = Seiten × Minuten, je eine Minute Hand fürs Einlegen, Wenden, Herausnehmen; Sekunden aufrunden; Spannen nur für Zeit allein; `maxWait` 0 nur in derselben Pfanne, 10 für Warmgehaltenes |

**Zweite Runde (20.11., geschärfter Prompt, deployt von Hans-Peter):** Alle drei Antworten nennen jetzt für jeden Schritt `dependsOn`, die unabhängigen Vorbereitungen der Wirsingrolle stehen nebeneinander, Bratzeiten ohne Eingreifen zählen allein („Pilze ohne Bewegung braten, wenden“ → 2 Hände, 3 allein), Spannen nur noch an Zeit allein.

| Gericht | Schritte | Handminuten KI (Tabelle) | Plan KI (Tabelle) | Grund |
|---|---|---|---|---|
| A Perlhuhnbrust | 17 | 33 (40) | 37 min, fehlen 2 (44) | Kette 22 und Hände 33 kollidieren; Perlhuhn liegt 6 Minuten länger als gewünscht |
| B Wirsingrolle | 14 | 37 (42) | 40 min, fehlen 5 (43) | Kette: Graupen 27 → Füllung 2 → Rolle 8 → Anrichten 3 |
| C Geschnetzeltes | 19 | 24 (37) | 31 min, passt (37) | Kette Haut im Ofen 20–25; die KI schätzt viele Schritte mit nur einer Minute |

Die KI schätzt die Handarbeit jetzt eher knapper als ich (bei C deutlich); das entspricht dem Eindruck aus der Sendung, dass es mit Hektik gerade reicht. Zwei Nebenbefunde: Bei C setzt die KI `maxWait` 0 ans scharfe Anbraten, dessen Fleisch aber erst zwölf Minuten später zurück in die Sauce kommt – der Planer meldet das als Verspätung, obwohl das Rezept es so will (die Höchstwartezeit gilt für alle Nachfolger, nicht nur den ersten). Und zwei von sieben Aufrufen scheiterten (eine abgeschnittene Antwort „Unterminated string in JSON“, einmal die 240-s-Frist der Function); der zweite Versuch gelang jeweils sofort. Die Function wiederholt einen gescheiterten ersten Versuch deshalb selbst (Zeitgrenze 100 s je Versuch beim Kochimport, `maxOutputTokens` 16384) – **noch nicht deployt**.

**Editor:** Bis dahin ersetzte der Editor leere Abhängigkeiten beim Speichern durch die Komponenten-Kette; damit hätte jede importierte Wirsingrolle wieder 75 Minuten gedauert. Jetzt gelten Abhängigkeiten wörtlich (ohne Angabe kann ein Schritt sofort beginnen); ein neu getippter Schritt bekommt den vorherigen Schritt seiner Komponente vorgeschlagen, sobald die Komponente steht, bis der Koch die Auswahl ändert, und „Auf alle Komponenten warten“ setzt die Abhängigkeiten des Anrichtens. Bestehende von Hand getippte Gerichte ohne Abhängigkeiten verlieren die stillen Ketten (betrifft nur Testdaten).

Rohantworten der KI liegen im Debug-Build unter Application Support/CookPlanner/imports als JSON (`DishImportClient.keepForTuning`).

Messaufbau: Debug-Build mit Startargument `-ImportTextFile /tmp/rezept.txt` füllt den Importtext vor (der `PasteButton` reagiert nicht auf synthetische Tipps, `simctl pbcopy` direkt nach dem Booten kam nicht an). Die Antwort-JSONs der Simulator-App: `xcrun simctl get_app_container <udid> de.hpm64625.CookPlanner data`.

Debug-Token für App Check im Simulator (iPhone 17e): in der Firebase-Konsole eingetragen 20.11.; ein anderer Simulator braucht ein eigenes (steht beim Start in der Konsole). **Auf dem Gerät (20.11.):** Der erste Import vom iPhone scheiterte mit „Unauthenticated“, Function-Log: App-Check-Token ungültig. Firebase nimmt keine App-Attest-Tokens aus der Sandbox, in der ein direkt signierter Build ohne Capability läuft; seit der App-Attest-Capability mit Umgebung `production` (`CookPlanner/CookPlanner.entitlements`) klappt der Import auf dem iPhone 16 Pro Max im Release-Build. Gerätebuild von Hand: `xcodebuild -project CookPlanner.xcodeproj -scheme CookPlanner -configuration Release -destination 'id=<udid>' -derivedDataPath /tmp/cpdevice -allowProvisioningUpdates build`, dann `xcrun devicectl device install app --device <udid> <.app>` und `… process launch`.

Ursprüngliche Skizze:

- **Eingänge:** Text einfügen (erster Test: die drei Rezept-PDFs der Sendung als Text), Fotos (Kamera/Fotos, wie `RecipeImageImportView`), Webseite (später über die Share-Extension wie BakePlanner).
- **Neue Cloud Function** `analyzeDishSteps` neben `analyzeRecipeText`/`analyzeRecipeImages`, gleiche Infrastruktur (Gemini mit Schema, App Check, Stundenlimit, Protokoll). Eigenes Schema fürs Kochen: Titel, Portionen, Komponenten, Schritte mit `text`, `componentName`, `handsMinutes`, `unattendedMinutes`, `unattendedMinMinutes`/`unattendedMaxMinutes`, `station` (none/burner/oven), `ovenTemperature`, `maxWaitMinutes`, `dependsOn` (Indizes), `warnings`. Die Regeln im Prompt: Arbeitszeit eines geübten Hobbykochs schätzen, Wartezeiten vom Rezept nehmen, Spannen als Fenster, „sofort“ (wenden, ruhen) als `maxWait` 0, Ofen-Temperaturen aus dem Text, Abhängigkeiten nur, wo das Rezept sie vorgibt (Füllung braucht Graupen), nichts erfinden, Unklares in `warnings`.
- **Lesen der Antwort** im Paket (`CloudDishImport`, Muster `CloudRecipeImport`): in `KitchenDish` übersetzen, Plausibilität (`Plausible`), Zyklen entfernen, fehlende Vorgänger nach der Komponenten-Vorgabe ergänzen. Tests mit gespeicherten Antworten.
- **Prüfen vor dem Speichern:** Die Antwort landet im Editor (3a), alles Geschätzte ist markiert, erst „Speichern“ legt das Gericht an.
- **Erster Maßstab:** Die drei Sendungsrezepte als Text importieren und die KI-Schätzungen mit den Tabellen oben vergleichen. Danach Prompt nachschärfen.
- **Firebase:** CookPlanner braucht eine eigene App im Firebase-Projekt `back-planer` (Bundle-ID `de.hpm64625.CookPlanner`, `GoogleService-Info.plist`, App Check mit App Attest/Debug-Provider) – legt Hans-Peter in der Firebase-Konsole an. Das Monatskontingent: Die neue App-ID vorerst in `appIdsWithoutMonthlyLimit` eintragen (wie die Android-App), weil es für CookPlanner noch kein Pro gibt; das Stundenlimit gilt trotzdem. Functions deployen nur nach Rückfrage.
- **Ohne Netz:** zunächst kein Fallback; von Hand im Editor. Eine Tabelle üblicher Handgriffe (würfeln 2 min, schälen …) für eine Schätzung auf dem Gerät ist denkbar, sobald echte Importe zeigen, wo die KI danebenliegt.

### Aufwand und Reihenfolge

1. 3a Modell, Dateiformat, Speicher mit Vertragstests, Editor, Liste: etwa ein Arbeitstag, nur iOS, keine Freigaben nötig.
2. 3b Function, Prompt, Antwort-Leser mit Tests, Import-Bildschirme: etwa ein Arbeitstag plus Firebase-App und Deploy durch Hans-Peter.
3. Danach: Sichern/Teilen der Gerichtsdatei, Android über Skip, Store-Texte.

## Nächste Schritte

1. Echtes Kochen mit der App (Hans-Peter), dann weitere Gerichte importieren (eigene Rezepte, Webseiten-Texte) und die Schätzungen prüfen.
2. Fotos und Webseiten als Eingang (wie BakePlanner: `RecipeImageImportView`, Share-Extension).
3. Android über Skip (Sichern/Teilen der Gerichtsdatei erledigt 21.11.). TestFlight: App-Eintrag in App Store Connect angelegt (20.11.), Workflow-Anleitung, Datenschutz-Angaben und Store-Texte in [CookPlanner-Store.md](CookPlanner-Store.md).
