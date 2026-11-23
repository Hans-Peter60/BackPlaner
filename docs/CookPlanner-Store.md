# CookPlanner: TestFlight und App-Store-Texte

Stand 23.11.2026. Der App-Eintrag in App Store Connect existiert (iOS, Name **CookPlanner**, Primärsprache Deutsch, Bundle-ID `de.hpm64625.CookPlanner`, SKU `cookplanner-ios`). Dieses Dokument sammelt, was für TestFlight und die Produktseite noch zu tun ist, und die Texte je Sprache. Muster: [AppStore-Beschreibung.md](AppStore-Beschreibung.md) und [CI.md](CI.md) von BakePlanner.

## Was im Projekt schon drin ist

- `CookPlanner/Info.plist`: URL-Schema `cookplanner`, Dokumenttyp `.cookplanner`, Hintergrundmodus für CloudKit-Pushes, Zugriffstexte für Kamera und Wecker (de/en/fr in `InfoPlist.xcstrings`), `ITSAppUsesNonExemptEncryption = NO`.
- `CookPlanner/PrivacyInfo.xcprivacy`: kein Tracking; erhobene Daten „Sonstige Nutzerinhalte“ (der Rezepttext geht zur Analyse in die Cloud) und „Nutzer-ID“ (anonyme Firebase-Anmeldung), beide nur für die App-Funktion; Required-Reason-API `UserDefaults` (CA92.1).
- iCloud-Abgleich (CloudKit, Container `iCloud.de.hpm64625.CookPlanner`; **Schema seit 23.11. in Production**), App Attest (Produktion), App Group, Live-Aktivität, Wecker (AlarmKit), Share-Extension, App-Symbol mit Tiefe (#219).
- Version 1.0, Build 1 in den Build-Einstellungen; Xcode Cloud zählt den Build hoch, wenn im Workflow eingestellt.
- Webseiten (Upload ins Repository `Hans-Peter60/bakeplanner` wie bei BakePlanner): `docs/website/cookplanner.html` (Hilfe) und `docs/website/cookplanner-privacy.html` (Datenschutz), je de/en/fr.

## Xcode Cloud: Workflow „TestFlight“ (einmalig, in Xcode)

1. Projekt `CookPlanner.xcodeproj` in Xcode öffnen. Menü **Integrate → Create Workflow…** (gibt es schon eines: **Manage Workflows…**). Beim ersten Mal fragt Xcode nach dem Produkt: **CookPlanner** wählen; das Repository ist `Hans-Peter60/BackPlaner` (dasselbe wie BakePlanner, Xcode Cloud hat den Zugriff schon).
2. Name **„TestFlight“**. **Environment:** Xcode „Latest Release“, macOS „Latest“.
3. **Start Conditions:** „Branch Changes“ mit **`main`**; Haken bei **„Auto-cancel Builds“**. Optional unter „Files and Folders“ auf **Start** bei Änderungen in `CookPlanner/`, `CookPlannerWidgets/`, `CookPlannerShare/`, `CookPlannerStorage/`, `BakePlannerCore/` beschränken, sonst baut jeder BakePlanner-Merge auch CookPlanner.
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
| App-Datenschutz | **Daten werden erhoben**, nicht zum Tracking: *Nutzerinhalte → Sonstige Nutzerinhalte* (Rezepttext für die Analyse, mit dem Nutzer verknüpft, App-Funktionalität) und *Kennungen → Nutzer-ID* (anonyme Anmeldung, App-Funktionalität). **Nicht** angeben: Fotos (werden auf dem Gerät gelesen), Gerichte und Protokolle (liegen nur in der iCloud des Nutzers, der Entwickler hat keinen Zugriff). Nichts zu Werbung oder Analytik |
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

Die ersten drei Zeilen sind ohne „mehr“ sichtbar, deshalb steht die Kernbotschaft im ersten Satz. Längen: de 2345, en 2190, fr 2434 Zeichen.

### Deutsch

---

Ein Gericht aus Fleisch, Beilage, Sauce und Garnitur, eine Person am Herd und eine feste Zeit: CookPlanner legt die Arbeitsschritte so, dass alles zugleich fertig wird, und sagt Dir vorher, ob die Zeit reicht.

REZEPTE HEREINHOLEN
Tippe ein Gericht von Hand ein, füge einen Rezepttext ein, scanne eine Kochbuchseite oder hol es von einer Internetseite – auch direkt über „Teilen“ aus Safari. Die Analyse zerlegt das Rezept in Schritte, schätzt die Handarbeit, erkennt, was von allein köchelt oder backt, und übernimmt die Zutaten samt Mengen. Du prüfst alles im Editor, bevor es gespeichert wird.

DER PLAN
CookPlanner rechnet mit Deiner Küche: wie viele Platten, wie viele Öfen, wie viel Zeit. Die Zeitachse zeigt jede Komponente als eigene Spalte, Handarbeit und Wartezeit auf einen Blick, und das Urteil sagt klar, ob das Gericht ins Budget passt – und wenn nicht, warum. Für mehr oder weniger Personen rechnet es die Mengen um.

GEGEN DIE UHR
Im Kochmodus wählst Du: Challenge zählt das Zeitbudget rückwärts wie in der Sendung, Training lässt die Stoppuhr ab 0:00 laufen. Du siehst, was jetzt in Deinen Händen liegt, was gleich kommt und was von allein läuft; jeden Schritt hakst Du ab, der Rest wird sofort neu gelegt. Mitteilungen, ein Wecker für Topf und Ofen und die Restzeit auf dem Sperrbildschirm – das iPhone darf auf der Arbeitsfläche liegen bleiben.

EINKAUFEN
Die Einkaufsliste fasst die Zutaten aller Komponenten zusammen und sortiert sie nach Abteilungen. Hake ab, was Du im Haus hast, und teile den Rest, etwa an Erinnerungen.

AUS JEDEM KOCHEN LERNEN
Jeder Durchgang wird mit der Stoppuhr festgehalten. Vergib Sterne, schreib eine Notiz, mach ein Foto – und übernimm auf Wunsch die gemessenen Zeiten, damit der nächste Plan noch genauer wird. Verlauf mit Galerie, Hit-Liste und Statistik.

DEINE GERICHTE
Suche, Sammlungen und Filter wie „Passt ins Budget“ oder „Ohne Ofen“; drei Beispiele aus einer Kochsendung sind dabei. Deine Gerichte gleichen sich über iCloud zwischen iPhone und iPad ab, Sicherung und Weitergabe als Datei. Ohne Konto, ohne Werbung. Für die Analyse geht nur der Rezepttext an einen Dienst von Google; Fotos werden auf dem Gerät gelesen.

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
In cook mode you choose: Challenge counts the time budget down like on TV, Practice runs the stopwatch from 0:00. You see what is in your hands now, what comes next and what runs on its own; tick off each step and the rest is replanned at once. Notifications, an alarm for pots and oven and the time left on the lock screen – the iPhone can stay on the counter.

SHOPPING
The shopping list merges the ingredients of all components and sorts them by aisle. Tick what you already have and share the rest, for example to Reminders.

LEARN FROM EVERY COOK
Every run is recorded with the stopwatch. Give stars, write a note, take a photo – and take over the measured times if you like, so the next plan is even closer. History with gallery, hit list and statistics.

YOUR DISHES
Search, collections and filters such as "Fits the budget" or "No oven"; three examples from a TV cooking show are included. Your dishes sync through iCloud between iPhone and iPad, with backup and sharing as a file. No account, no ads. For the analysis only the recipe text goes to a Google service; photos are read on the device.

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
En mode cuisine, vous choisissez : Défi décompte le temps imparti comme à la télévision, Entraînement lance le chronomètre à 0:00. Vous voyez ce que vous avez en main, ce qui suit et ce qui se fait tout seul ; cochez chaque étape et le reste est replanifié aussitôt. Notifications, alarme pour casseroles et four et temps restant sur l’écran verrouillé – l’iPhone peut rester sur le plan de travail.

LES COURSES
La liste de courses regroupe les ingrédients de tous les composants et les trie par rayon. Cochez ce que vous avez déjà et partagez le reste, par exemple vers Rappels.

APPRENDRE DE CHAQUE CUISSON
Chaque passage est relevé au chronomètre. Donnez des étoiles, écrivez une note, prenez une photo – et reprenez si vous voulez les durées mesurées pour que le prochain plan soit encore plus juste. Historique avec galerie, palmarès et statistiques.

VOS PLATS
Recherche, collections et filtres comme « Tient dans le temps » ou « Sans four » ; trois exemples d’une émission de cuisine sont inclus. Vos plats se synchronisent via iCloud entre iPhone et iPad, avec sauvegarde et partage sous forme de fichier. Sans compte, sans publicité. Pour l’analyse, seul le texte de la recette part vers un service de Google ; les photos sont lues sur l’appareil.

CookPlanner vient du développeur de BakePlanner et utilise le même planificateur – sauf qu’ici on ne calcule pas à rebours jusqu’au pain, mais en avant contre la montre.

---

## Schlüsselwörter (≤ 100 Zeichen, Kommas ohne Leerzeichen)

| Sprache | Schlüsselwörter | Zeichen |
|---|---|---|
| Deutsch | `Kochen,Rezept,Timer,Zeitplan,Menü,Küche,Gericht,Herd,Ofen,Stoppuhr,Einkaufsliste,Wettkochen` | 91 |
| English | `cooking,recipe,timer,schedule,menu,kitchen,planner,dish,oven,stopwatch,shopping list,meal prep` | 94 |
| Français | `cuisine,recette,minuteur,planning,menu,plat,four,chronomètre,liste de courses,compte à rebours,repas` | 100 |

## Neuerungen (Version 1.0)

- DE: `Erste Version: Gerichte von Hand, aus Text, Fotos oder Webseiten; Plan mit Zeitachse und Urteil; Kochmodus als Challenge oder Training mit Wecker; Einkaufsliste; Verlauf mit Fotos; iCloud-Abgleich.`
- EN: `First version: dishes by hand, from text, photos or web pages; a plan with timeline and verdict; cook mode as Challenge or Practice with alarms; shopping list; history with photos; iCloud sync.`
- FR: `Première version : plats à la main, depuis un texte, des photos ou une page web ; plan avec chronologie et verdict ; mode cuisine en Défi ou Entraînement avec alarmes ; liste de courses ; historique avec photos ; synchronisation iCloud.`

## Hinweise für die Prüfung

---

No account is needed; everything can be tested without signing in. The app signs in anonymously with Firebase only for the cloud analysis, to rate-limit it.

To see the core feature: on the "Gerichte" (Dishes) tab open one of the three example dishes under "Beispiele" → the plan shows whether the dish fits 35 minutes, the timeline per component and the ingredients → "Kochen starten" → choose "Challenge" (countdown) or "Training" (stopwatch) → "Start". The cook mode lists what is in your hands now, what comes next and what runs on its own; tick off a step with the checkmark and the rest is replanned. Allow notifications, alarms and Live Activities when asked: a notification announces each step, an alarm rings when a pot or the oven is done, the lock screen shows the remaining time. "Beenden" → "Beenden und Protokoll sichern" keeps the run in the "Gekocht" (Cooked) tab.

Import: "+" → "Aus Text importieren" (paste any recipe text), "Aus Fotos importieren" (scan a cookbook page; the text is recognised on the device) or "Aus Webseite importieren" (any recipe page). Only the recipe text is sent to our Cloud Function (Google Gemini) for structuring; the result opens in an editor and is saved only with "Sichern". The share extension does the same from Safari's share sheet.

Shopping list: on a dish's plan, the basket button. Settings (slider icon): time budget, burners and ovens, alarms, iCloud sync status, backup.

---

## Offen

- Webseiten `cookplanner.html` und `cookplanner-privacy.html` ins Website-Repository hochladen (Hans-Peter), dann die beiden URLs oben in App Store Connect eintragen.
- Screenshots: 6,9-Zoll-iPhone Pflicht; die App läuft auch auf dem iPad (13-Zoll-Bilder nötig, solange das Target iPad einschließt).
- Erster TestFlight-Build und echter Kochtest auf beiden Geräten (iCloud-Abgleich in Production, Wecker, Mitteilungen).
