# CookPlanner: TestFlight und App-Store-Texte

Stand 26.11.2026. Der App-Eintrag in App Store Connect existiert (iOS, Name **CookPlanner**, Primärsprache Deutsch, Bundle-ID `de.hpm64625.CookPlanner`, SKU `cookplanner-ios`). Dieses Dokument sammelt, was für TestFlight und die Produktseite noch zu tun ist, und die Texte je Sprache. Muster: [AppStore-Beschreibung.md](../bakeplanner/AppStore-Beschreibung.md) und [CI.md](../CI.md) von BakePlanner.

## Was im Projekt schon drin ist

- `CookPlanner/CookPlanner/Info.plist`: URL-Schema `cookplanner`, Dokumenttyp `.cookplanner`, Hintergrundmodus für CloudKit-Pushes, Zugriffstexte für Kamera, Wecker, Mikrofon und Spracherkennung (de/en/fr in `InfoPlist.xcstrings`), `ITSAppUsesNonExemptEncryption = NO`.
- `CookPlanner/CookPlanner/PrivacyInfo.xcprivacy`: kein Tracking; erhobene Daten „Sonstige Nutzerinhalte“ (der Rezepttext geht zur Analyse in die Cloud) und „Nutzer-ID“ (anonyme Firebase-Anmeldung), beide nur für die App-Funktion; Required-Reason-API `UserDefaults` (CA92.1).
- Einstellungen, Portionen und Sammlungen über den iCloud-Schlüsselwertspeicher (Berechtigung `kvstore`); Siri, Kurzbefehle und Spotlight über App Intents (`AppShortcuts.xcstrings`).
- iCloud-Abgleich (CloudKit, Container `iCloud.de.hpm64625.CookPlanner`; **Schema seit 23.11. in Production**), App Attest (Produktion), App Group, Live-Aktivität, Wecker (AlarmKit), Share-Extension, App-Symbol mit Tiefe (#219).
- Version 1.0, Build 1 in den Build-Einstellungen; Xcode Cloud zählt den Build hoch, wenn im Workflow eingestellt.
- Webseiten (Upload ins Repository `Hans-Peter60/bakeplanner` wie bei BakePlanner): `docs/website/cookplanner.html` (Hilfe) und `docs/website/cookplanner-privacy.html` (Datenschutz), je de/en/fr.

## Xcode Cloud: Workflow „TestFlight“ (einmalig, in Xcode)

1. Projekt `CookPlanner.xcodeproj` in Xcode öffnen. Menü **Integrate → Create Workflow…** (gibt es schon eines: **Manage Workflows…**). Beim ersten Mal fragt Xcode nach dem Produkt: **CookPlanner** wählen; das Repository ist `Hans-Peter60/BackPlaner` (dasselbe wie BakePlanner, Xcode Cloud hat den Zugriff schon).
2. Name **„TestFlight“**. **Environment:** Xcode „Latest Release“, macOS „Latest“.
3. **Start Conditions:** „Branch Changes“ mit **`main`**; Haken bei **„Auto-cancel Builds“**. Optional unter „Files and Folders“ auf **Start** bei Änderungen in `CookPlanner/`, `CookPlanner/CookPlannerWidgets/`, `CookPlanner/CookPlannerShare/`, `CookPlanner/CookPlannerStorage/`, `BakePlannerCore/` beschränken, sonst baut jeder BakePlanner-Merge auch CookPlanner.
4. **Actions:** **Archive**, Scheme **CookPlanner**, Platform iOS, Deployment Preparation **„TestFlight (Internal Testing Only)“**. Fehlt das Scheme in der Liste, in Xcode **Product → Scheme → Manage Schemes…** und bei CookPlanner **Shared** anhaken, committen.
5. **Post-Actions:** **TestFlight Internal Testing** mit einer Gruppe (z. B. „Hans-Peter“); **Notify** per E-Mail bei Fehlern.
6. **Save**. Der erste Lauf startet sofort; er dauert 15–25 Minuten. Danach erscheint der Build unter App Store Connect → CookPlanner → TestFlight, die interne Gruppe bekommt ihn ohne Prüfung.

Bekanntes aus BakePlanner: Xcode Cloud hat kein App-Check-Debug-Token; die App braucht im Build keins, weil Release-Builds App Attest nutzen. Pakete kommen über Swift Package Manager, `Package.resolved` ist eingecheckt. Die 25 Rechenstunden im Monat teilen sich beide Apps.

## App Store Connect: einmalige Angaben

| Wo | Was |
|---|---|
| App-Informationen | Kategorie **Essen & Trinken**; Untertitel je Sprache (unten) |
| Datenschutzrichtlinie (URL) | `https://hans-peter60.github.io/bakeplanner/cookplanner-privacy.html` |
| Support-URL | `https://hans-peter60.github.io/bakeplanner/cookplanner.html` |
| App-Datenschutz | **Daten werden erhoben**, nicht zum Tracking: *Nutzerinhalte → Sonstige Nutzerinhalte* (Rezepttext für die Analyse, mit dem Nutzer verknüpft, App-Funktionalität) und *Kennungen → Nutzer-ID* (anonyme Anmeldung, App-Funktionalität) und *Käufe → Kaufverlauf* (der signierte Pro-Beleg geht mit der Analyse an die Function, mit dem Nutzer verknüpft, App-Funktionalität; steht so auch im `PrivacyInfo.xcprivacy`). **Nicht** angeben: Fotos (werden auf dem Gerät gelesen), Audio (die Sprachbefehle werden mit der Spracherkennung auf dem Gerät erkannt, nichts wird gespeichert oder übertragen), Gerichte und Protokolle (liegen nur in der iCloud des Nutzers, der Entwickler hat keinen Zugriff). Nichts zu Werbung oder Analytik |
| Altersfreigabe | alle Fragen „Nein“ → 4+ |
| Preis | Kostenlos, alle Länder |
| TestFlight → Testinformationen | Beta-Beschreibung: „Plane ein Gericht aus mehreren Teilen so, dass alles zugleich fertig ist, und koche es gegen die Uhr.“ E-Mail und Feedback-Adresse wie bei BakePlanner |
| Lokalisierungen | Deutsch (primär), Englisch, Französisch – die App hat alle drei |

## Name und Untertitel (je ≤ 30 Zeichen)

| | Name | Untertitel | Zeichen |
|---|---|---|---|
| Deutsch | `CookPlanner` | `Kochen gegen die Uhr, geplant` | 29 |
| English | `CookPlanner` | `Cooking against the clock` | 25 |
| Français | `CookPlanner` | `Cuisiner contre la montre` | 25 |

## Werbetext (≤ 170 Zeichen)

| Sprache | Werbetext | Zeichen |
|---|---|---|
| Deutsch | `Mehrere Teile, eine Person, 35 Minuten: CookPlanner legt die Schritte so, dass alles zugleich fertig wird, und führt Dich Schritt für Schritt durch die Küche.` | 158 |
| English | `Several parts, one cook, 35 minutes: CookPlanner lays out the steps so everything is ready at once, then walks you through the cooking step by step.` | 148 |
| Français | `Plusieurs éléments, une personne, 35 minutes : CookPlanner ordonne les étapes pour que tout soit prêt en même temps et vous guide pas à pas.` | 140 |

## Beschreibung (≤ 4000 Zeichen)

Die ersten drei Zeilen sind ohne „mehr“ sichtbar, deshalb steht die Kernbotschaft im ersten Satz. Der Abschnitt „COOKPLANNER PRO“ sagt, was frei bleibt und was der Einmalkauf freischaltet; CookPlanner erscheint erst mit dem Kauf (siehe [CookPlanner-Pro.md](CookPlanner-Pro.md)), deshalb steht er von Anfang an da. Längen: de 3633, en 3424, fr 3822 Zeichen.

### Deutsch

---

Ein Gericht aus Fleisch, Beilage, Sauce und Garnitur, eine Person am Herd und eine feste Zeit: CookPlanner legt die Arbeitsschritte so, dass alles zugleich fertig wird, und sagt Dir vorher, ob die Zeit reicht.

REZEPTE HEREINHOLEN
Tippe ein Gericht von Hand ein, füge einen Rezepttext ein, scanne eine Kochbuchseite oder hol es von einer Internetseite – auch direkt über „Teilen“ aus Safari. Die Analyse zerlegt das Rezept in Schritte, schätzt die Handarbeit, erkennt, was von allein köchelt oder backt, und übernimmt die Zutaten samt Mengen. Du prüfst alles im Editor, bevor es gespeichert wird.

DER PLAN
CookPlanner rechnet mit Deiner Küche: wie viele Platten, wie viele Öfen, wie viel Zeit. Die Zeitachse zeigt jede Komponente als eigene Spalte, Handarbeit und Wartezeit auf einen Blick, und das Urteil sagt klar, ob das Gericht ins Budget passt – und wenn nicht, warum. Für mehr oder weniger Personen rechnet es die Mengen um.

GEGEN DIE UHR
Im Kochmodus wählst Du: Challenge zählt das Zeitbudget rückwärts wie in der Sendung, Training lässt die Stoppuhr ab 0:00 laufen, Entspannt führt Dich ganz ohne Uhr durch die Schritte. Du siehst, was jetzt in Deinen Händen liegt, was gleich kommt und was von allein läuft; jeden Schritt hakst Du ab, der Rest wird sofort neu gelegt. Mitteilungen, ein Wecker für Topf und Ofen und die Restzeit auf dem Sperrbildschirm – das iPhone darf auf der Arbeitsfläche liegen bleiben.

HÄNDE FREI
CookPlanner liest jeden Schritt samt Zutaten vor. Mit den Sprachbefehlen sagst Du „Erledigt“, „Steht“, „Was kommt“ oder „Wie lange“, ohne das Display mit nassen Händen anzufassen; die Sprache wird auf dem Gerät erkannt. Siri beantwortet „Wie lange noch in CookPlanner“ auch bei gesperrtem iPhone.

EIN MENÜ AUS MEHREREN GÄNGEN
Stell Vorspeise, Hauptgang und Dessert aus Deinen Gerichten zusammen und leg fest, wie viele Minuten zwischen den Gängen liegen. CookPlanner plant das Menü als Ganzes: Der Hauptgang wird gekocht, während die Gäste die Vorspeise essen.

EINKAUFEN
Die Einkaufsliste fasst die Zutaten aller Komponenten zusammen und sortiert sie nach Abteilungen. Hake ab, was Du im Haus hast, und teile den Rest, etwa an Erinnerungen.

AUS JEDEM KOCHEN LERNEN
Jeder Durchgang wird mit der Stoppuhr festgehalten. Vergib Sterne, schreib eine Notiz, mach ein Foto – und übernimm auf Wunsch die gemessenen Zeiten, damit der nächste Plan noch genauer wird. Verlauf mit Galerie, Hit-Liste und Statistik. Am Jahresende druckt das Kochjahr-Buch Dein Jahr als PDF: Zahlen, Fotos je Monat, Lieblingsgerichte und was die Uhr Dich gelehrt hat.

DEINE GERICHTE
Suche, Sammlungen und Filter wie „Passt ins Budget“ oder „Ohne Ofen“; drei Beispiele aus einer Kochsendung sind dabei. Deine Gerichte und Einstellungen gleichen sich über iCloud zwischen iPhone und iPad ab; die Sicherung als Datei nimmt auch Protokolle und Fotos mit. Kurzbefehle, Spotlight und auf dem iPad Tastaturkürzel. Ohne Konto, ohne Werbung. Für die Analyse geht nur der Rezepttext an einen Dienst von Google; Fotos werden auf dem Gerät gelesen.

COOKPLANNER PRO
Alles zum Planen und Kochen gegen die Uhr bleibt kostenlos: Gerichte, Plan, Kochmodus mit Wecker, Einkaufsliste, Verlauf und iCloud-Abgleich. CookPlanner Pro ist ein Einmalkauf, kein Abo, und schaltet dazu frei: Menüs aus mehreren Gängen, Vorlesen und Sprachbefehle, das Kochjahr-Buch, die Kochstatistik, eigene Sammlungen, den Plan als PDF, das Übernehmen gemessener Zeiten und mehr Rezeptanalysen im Monat.

CookPlanner stammt vom Entwickler von BakePlanner und nutzt denselben Planer – nur dass hier nicht rückwärts zum Brot gerechnet wird, sondern vorwärts gegen die Uhr.

---

### English

---

A dish of meat, side, sauce and garnish, one cook at the stove and a fixed time: CookPlanner lays out the steps so everything is ready at the same moment, and tells you beforehand whether the time is enough.

BRING IN RECIPES
Type a dish in by hand, paste a recipe text, scan a cookbook page or fetch it from a web page – also straight from Safari's share sheet. The analysis breaks the recipe into steps, estimates the hands-on time, spots what simmers or bakes on its own and takes over the ingredients with their amounts. You check everything in the editor before it is saved.

THE PLAN
CookPlanner works with your kitchen: how many burners, how many ovens, how much time. The timeline shows every component as a column of its own, hands-on and waiting time at a glance, and the verdict says clearly whether the dish fits the budget – and if not, why. For more or fewer people it scales the amounts.

AGAINST THE CLOCK
In cook mode you choose: Challenge counts the time budget down like on TV, Practice runs the stopwatch from 0:00, Relaxed guides you through the steps with no clock at all. You see what is in your hands now, what comes next and what runs on its own; tick off each step and the rest is replanned at once. Notifications, an alarm for pots and oven and the time left on the lock screen – the iPhone can stay on the counter.

HANDS FREE
CookPlanner reads every step aloud with its ingredients. With voice commands you say "Done", "It's on", "What's next" or "How long" without touching the screen with wet hands; speech is recognised on the device. Siri answers "How long in CookPlanner" even with the iPhone locked.

A MENU OF SEVERAL COURSES
Put together starter, main and dessert from your dishes and set how many minutes lie between the courses. CookPlanner plans the menu as a whole: the main is cooked while the guests eat the starter.

SHOPPING
The shopping list merges the ingredients of all components and sorts them by aisle. Tick what you already have and share the rest, for example to Reminders.

LEARN FROM EVERY COOK
Every run is recorded with the stopwatch. Give stars, write a note, take a photo – and take over the measured times if you like, so the next plan is even closer. History with gallery, hit list and statistics. At the end of the year the cooking yearbook prints your year as a PDF: figures, photos by month, favourite dishes and what the clock taught you.

YOUR DISHES
Search, collections and filters such as "Fits the budget" or "No oven"; three examples from a TV cooking show are included. Your dishes and settings sync through iCloud between iPhone and iPad; the backup file also keeps records and photos. Shortcuts, Spotlight and keyboard shortcuts on the iPad. No account, no ads. For the analysis only the recipe text goes to a Google service; photos are read on the device.

COOKPLANNER PRO
Everything for planning and cooking against the clock stays free: dishes, plan, cook mode with alarms, shopping list, history and iCloud sync. CookPlanner Pro is a one-time purchase, not a subscription, and adds: menus of several courses, read aloud and voice commands, the cooking yearbook, cooking statistics, your own collections, the plan as a PDF, taking over measured times and more recipe analyses a month.

CookPlanner comes from the developer of BakePlanner and uses the same planner – only here it does not work backwards to the bread, but forwards against the clock.

---

### Français

---

Un plat avec viande, accompagnement, sauce et garniture, une seule personne aux fourneaux et un temps imparti : CookPlanner ordonne les étapes pour que tout soit prêt au même moment, et vous dit à l’avance si le temps suffit.

AJOUTER DES RECETTES
Saisissez un plat à la main, collez un texte de recette, numérisez une page de livre ou récupérez-la sur une page web – aussi directement via « Partager » dans Safari. L’analyse découpe la recette en étapes, estime le travail manuel, repère ce qui mijote ou cuit tout seul et reprend les ingrédients avec leurs quantités. Vous vérifiez tout dans l’éditeur avant l’enregistrement.

LE PLAN
CookPlanner tient compte de votre cuisine : combien de feux, combien de fours, combien de temps. La chronologie montre chaque composant dans sa propre colonne, travail manuel et attente d’un coup d’œil, et le verdict dit clairement si le plat tient dans le temps imparti – sinon, pourquoi. Pour plus ou moins de personnes, il recalcule les quantités.

CONTRE LA MONTRE
En mode cuisine, vous choisissez : Défi décompte le temps imparti comme à la télévision, Entraînement lance le chronomètre à 0:00, Détendu vous guide dans les étapes sans aucune horloge. Vous voyez ce que vous avez en main, ce qui suit et ce qui se fait tout seul ; cochez chaque étape et le reste est replanifié aussitôt. Notifications, alarme pour casseroles et four et temps restant sur l’écran verrouillé – l’iPhone peut rester sur le plan de travail.

LES MAINS LIBRES
CookPlanner lit chaque étape à voix haute avec ses ingrédients. Avec les commandes vocales, vous dites « C’est fait », « C’est parti », « Et après » ou « Combien de temps » sans toucher l’écran les mains mouillées ; la parole est reconnue sur l’appareil. Siri répond à « Combien de temps dans CookPlanner » même iPhone verrouillé.

UN MENU EN PLUSIEURS PLATS
Composez entrée, plat et dessert à partir de vos recettes et fixez le nombre de minutes entre les plats. CookPlanner planifie le menu d’un seul tenant : le plat principal cuit pendant que les invités mangent l’entrée.

LES COURSES
La liste de courses regroupe les ingrédients de tous les composants et les trie par rayon. Cochez ce que vous avez déjà et partagez le reste, par exemple vers Rappels.

APPRENDRE DE CHAQUE CUISSON
Chaque passage est relevé au chronomètre. Donnez des étoiles, écrivez une note, prenez une photo – et reprenez si vous voulez les durées mesurées pour que le prochain plan soit encore plus juste. Historique avec galerie, palmarès et statistiques. En fin d’année, le livre de l’année en cuisine imprime votre année en PDF : chiffres, photos par mois, plats préférés et ce que l’horloge vous a appris.

VOS PLATS
Recherche, collections et filtres comme « Tient dans le temps » ou « Sans four » ; trois exemples d’une émission de cuisine sont inclus. Vos plats et vos réglages se synchronisent via iCloud entre iPhone et iPad ; le fichier de sauvegarde garde aussi les comptes rendus et les photos. Raccourcis, Spotlight et raccourcis clavier sur l’iPad. Sans compte, sans publicité. Pour l’analyse, seul le texte de la recette part vers un service de Google ; les photos sont lues sur l’appareil.

COOKPLANNER PRO
Tout ce qu’il faut pour planifier et cuisiner contre la montre reste gratuit : plats, plan, mode cuisine avec alarmes, liste de courses, historique et synchronisation iCloud. CookPlanner Pro est un achat unique, sans abonnement, et ajoute : les menus en plusieurs plats, la lecture à voix haute et les commandes vocales, le livre de l’année, les statistiques, vos propres collections, le plan en PDF, la reprise des durées mesurées et plus d’analyses de recettes par mois.

CookPlanner vient du développeur de BakePlanner et utilise le même planificateur – sauf qu’ici on ne calcule pas à rebours jusqu’au pain, mais en avant contre la montre.

---

## Schlüsselwörter (≤ 100 Zeichen, Kommas ohne Leerzeichen)

| Sprache | Schlüsselwörter | Zeichen |
|---|---|---|
| Deutsch | `Kochen,Rezept,Timer,Zeitplan,Menü,Küche,Gericht,Herd,Ofen,Stoppuhr,Einkaufsliste,Wettkochen` | 91 |
| English | `cooking,recipe,timer,schedule,menu,kitchen,planner,dish,oven,stopwatch,shopping list,meal prep` | 94 |
| Français | `cuisine,recette,minuteur,planning,menu,plat,four,chronomètre,liste de courses,compte à rebours,repas` | 100 |

## Neuerungen (Version 1.0)

- DE: `Erste Version: Gerichte von Hand, aus Text, Fotos oder Webseiten; Plan mit Zeitachse und Urteil; Menüs aus mehreren Gängen; Kochmodus als Challenge, Training oder Entspannt mit Wecker, Vorlesen und Sprachbefehlen; Einkaufsliste; Verlauf mit Fotos und Kochjahr-Buch; Siri; iCloud-Abgleich.`
- EN: `First version: dishes by hand, from text, photos or web pages; a plan with timeline and verdict; menus of several courses; cook mode as Challenge, Practice or Relaxed with alarms, read-aloud and voice commands; shopping list; history with photos and a cooking yearbook; Siri; iCloud sync.`
- FR: `Première version : plats à la main, depuis un texte, des photos ou une page web ; plan avec chronologie et verdict ; menus en plusieurs plats ; mode cuisine en Défi, Entraînement ou Détendu avec alarmes, lecture à voix haute et commandes vocales ; liste de courses ; historique avec photos et livre de l’année ; Siri ; synchronisation iCloud.`

## In-App-Kauf „CookPlanner Pro“

Nicht verbrauchbar, Produkt-ID `de.hpm64625.CookPlanner.pro`, Referenzname `CookPlanner Pro`, Familienfreigabe an. Anzeigename ≤ 30, Beschreibung ≤ 45 Zeichen.

| Sprache | Anzeigename | Beschreibung | Zeichen |
|---|---|---|---|
| Deutsch | `CookPlanner Pro` | `Menüs, Vorlesen, Kochjahr-Buch und mehr` | 39 |
| English | `CookPlanner Pro` | `Menus, read aloud, yearbook and more` | 36 |
| Français | `CookPlanner Pro` | `Menus, lecture à voix haute, livre et plus` | 42 |

Prüf-Bildschirmfoto: die Kaufseite (`-CookProPaywall 1`, aus Xcode mit `CookPlanner/CookPlanner.storekit`, damit der Preis erscheint). Hinweis für die Prüfung des Kaufs: siehe den letzten Absatz der Prüfhinweise.

## Hinweise für die Prüfung

---

No account is needed; everything can be tested without signing in. The app signs in anonymously with Firebase only for the cloud analysis, to rate-limit it.

To see the core feature: on the "Gerichte" (Dishes) tab open one of the three example dishes under "Beispiele" → the plan shows whether the dish fits 35 minutes, the timeline per component and the ingredients → "Kochen starten" → choose "Challenge" (countdown) or "Training" (stopwatch) → "Start". The cook mode lists what is in your hands now, what comes next and what runs on its own; tick off a step with the checkmark and the rest is replanned. Allow notifications, alarms and Live Activities when asked: a notification announces each step, an alarm rings when a pot or the oven is done, the lock screen shows the remaining time. "Beenden" → "Beenden und Protokoll sichern" keeps the run in the "Gekocht" (Cooked) tab. A third mode, "Entspannt" (Relaxed), cooks without any clock.

Hands free: in cook mode, "Vorlesen" (Read aloud) speaks each step; "Sprachbefehle" (Voice commands) asks for the microphone and speech recognition and then listens for "Erledigt"/"Done", "Was kommt"/"What's next" or "Wie lange"/"How long". Recognition runs on the device with Apple's SpeechTranscriber; no audio is stored or sent anywhere. Siri: "How long in CookPlanner" or "Step done in CookPlanner" during a cook, also from the lock screen.

Menu: "+" → "Menü zusammenstellen" (Compose a menu), pick two example dishes as starter and main; the result is one plan with both courses. Cooking yearbook: "Gekocht" tab → "+" → "Kochjahr-Buch" makes a PDF of the year (needs at least one cooked entry; "Gekocht eintragen" adds one by hand).

Import: "+" → "Aus Text importieren" (paste any recipe text), "Aus Fotos importieren" (scan a cookbook page; the text is recognised on the device) or "Aus Webseite importieren" (any recipe page). Only the recipe text is sent to our Cloud Function (Google Gemini) for structuring; the result opens in an editor and is saved only with "Sichern". The share extension does the same from Safari's share sheet.

CookPlanner Pro (one-time, non-consumable "de.hpm64625.CookPlanner.pro"): Settings (slider icon) → "CookPlanner Pro" shows the purchase with "Pro freischalten" (Unlock Pro) and "Käufe wiederherstellen" (Restore purchases). Without Pro, these show the purchase sheet instead: "Menü zusammenstellen", the "Vorlesen"/"Sprachbefehle" buttons in cook mode, "Kochjahr-Buch", the statistics view of the "Gekocht" tab, saving a collection, the printer button and "Gemessene Zeiten … übernehmen" on a plan. Everything else, including the complete cook mode with alarms, is free.

Shopping list: on a dish's plan, the basket button. Settings (slider icon): time budget, burners and ovens, alarms, iCloud sync status, backup.

---

## Bildschirmfotos

Seit 26.11.2026 mit Überschrift wie bei BakePlanner: Die Rohbilder liegen je Gerät in `…/de/roh/`, darüber setzt `scripts/bakeplanner/appstore-captions.swift` Überschrift und Unterzeile aus `docs/cookplanner/appstore/captions.json` (gleiche Farben und Schrift wie CookPlanner). Pro-Motive tragen eine **„PRO“-Marke** über der Überschrift (Liste `pro`: **06 Statistik**, **07 Menü**); der Kochmodus (04) bleibt ohne, weil er frei ist. Neu zusammensetzen:

```
for d in iphone-6.9 ipad-13 iphone-duo-inner; do swift scripts/bakeplanner/appstore-captions.swift docs/cookplanner/appstore/captions.json de docs/cookplanner/appstore/1.0/$d/de/roh docs/cookplanner/appstore/1.0/$d/de; done
```

Rohbilder: Aufgenommen im Simulator (iPhone 17 Pro – laut BakePlanners Erfahrung nimmt App Store Connect die Maße der *Max*-Modelle nicht an –, iPad Pro 13 Zoll und iPhone Duo aufgeklappt, alle iOS 27.3) mit Statusleiste 9:41, Zeitbudget 45 Minuten und den Debug-Startargumenten: ohne Argument die Gerichteliste, `-PlanSample 0` der Plan, `-TimelineSample 0 -TimelineNow 13.5` die Zeitachse, `-CookSample 0 -CookElapsed 790 -settings.clockMode challenge` der laufende Kochmodus, `-ShoppingSample 0` die Einkaufsliste, `-HistoryDemo statistics` die Statistik, `-MenuSample 1 -settings.budgetMinutes 120` der Plan eines Menüs aus zwei Beispielen (Wirsingrolle als Vorspeise, Perlhuhnbrust als Hauptgang; das Budget-Argument muss **vor** dem allgemeinen stehen oder es ersetzen, sonst gewinnt das spätere); dazu `-settings.budgetMinutes 45 -AppleLanguages (de) -AppleLocale de_DE`. Die aufgeklappte Duo: `hinge -d <udid> open`, dann `hinge -d <udid> orient landscape-left` (Innendisplay hochkant), App mit dem Argument starten und `xcrun simctl io <udid> screenshot --display 3` – Berührungen erreichen das Innendisplay im Simulator nicht, die Startargumente brauchen keine. **Stolperstein:** Der erste Start nach `simctl install` ist langsam und übernimmt die Startargumente nicht zuverlässig (leerer Kochmodus, Liste mit 35 statt 45 Minuten) – vorher einmal ohne Bild starten und 10 Sekunden warten.

## Offen

- CookPlanner Pro: In-App-Kauf anlegen und mit 1.0 einreichen, erst danach die Schalter setzen – Reihenfolge in [CookPlanner-Pro.md](CookPlanner-Pro.md).

- Webseiten `cookplanner.html` und `cookplanner-privacy.html` ins Website-Repository hochladen (Hans-Peter), dann die beiden URLs oben in App Store Connect eintragen.
- Screenshots hochladen (die zusammengesetzten, nicht `roh/`): `docs/cookplanner/appstore/1.0/iphone-6.9/de/` (1206 × 2622), `…/ipad-13/de/` (2064 × 2752) und `…/iphone-duo-inner/de/` (2007 × 2853, iPhone Duo aufgeklappt), je sieben Bilder (Gerichte, Plan, Zeitachse, Kochen mit Vorlesen und Sprachbefehlen, Einkauf, Statistik, Menü; neu aufgenommen am 26.11.); ohne eigene Bilder für en/fr nimmt App Store Connect die deutschen. iPad bleibt unterstützt (Layout im Simulator geprüft, Hans-Peter nutzt die App auf dem iPad).
- Erster TestFlight-Build und echter Kochtest auf beiden Geräten (iCloud-Abgleich in Production, Wecker, Mitteilungen).
