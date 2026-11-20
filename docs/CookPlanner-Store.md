# CookPlanner: TestFlight und App-Store-Texte

Stand 20.11.2026. Der App-Eintrag in App Store Connect existiert (iOS, Name **CookPlanner**, Primärsprache Deutsch, Bundle-ID `de.hpm64625.CookPlanner`, SKU `cookplanner-ios`). Dieses Dokument sammelt, was für den ersten TestFlight-Build und die Produktseite noch zu tun ist, und die Texte je Sprache. Muster: [AppStore-Beschreibung.md](AppStore-Beschreibung.md) und [CI.md](CI.md) von BakePlanner.

## Was im Projekt schon drin ist

- `CookPlanner/Info.plist`: URL-Schema `cookplanner`, `ITSAppUsesNonExemptEncryption = NO` (nur HTTPS über Systembibliotheken; erspart die Exportfrage bei jedem Build).
- `CookPlanner/PrivacyInfo.xcprivacy`: kein Tracking; erhobene Daten „Sonstige Nutzerinhalte“ (der Rezepttext geht zur Analyse in die Cloud) und „Nutzer-ID“ (anonyme Firebase-Anmeldung), beide nur für die App-Funktion; Required-Reason-API `UserDefaults` (CA92.1). Die Firebase-Pakete bringen ihre eigenen Manifeste mit.
- App-Symbol, App Attest (Produktion), App Group, Live-Aktivitäten, Share-Extension – alles seit den PRs #183 bis #189.
- Version 1.0, Build 1 in den Build-Einstellungen; Xcode Cloud zählt den Build hoch, wenn im Workflow eingestellt.

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
| App-Informationen | Kategorie **Essen & Trinken**; Untertitel je Sprache (unten); Datenschutzrichtlinie: eigene Seite unter `docs/website/` anlegen (die von BakePlanner nennt BakePlanner) – nötig vor externem TestFlight und vor der Einreichung |
| App-Datenschutz | **Daten werden erhoben**, nicht zum Tracking: *Nutzerinhalte → Sonstige Nutzerinhalte* (Rezepttext für die Analyse, mit dem Nutzer verknüpft, App-Funktionalität) und *Kennungen → Nutzer-ID* (anonyme Anmeldung, App-Funktionalität). Nichts zu Werbung oder Analytik |
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

Die ersten drei Zeilen sind ohne „mehr“ sichtbar, deshalb steht die Kernbotschaft im ersten Satz.

### Deutsch

---

Ein Gericht aus Fleisch, Beilage, Sauce und Garnitur, eine Person am Herd und eine feste Zeit: CookPlanner legt die Arbeitsschritte so, dass alles zugleich fertig wird, und sagt Dir vorher, ob die Zeit reicht.

SO FUNKTIONIERT ES
Du gibst ein Rezept ein, tippst es ab oder holst es aus dem Netz: Text einsetzen, Adresse eingeben oder die Seite aus Safari teilen. Die Analyse zerlegt es in Schritte, schätzt die Handarbeit, erkennt, was von allein köchelt oder backt, und schlägt vor, was worauf warten muss. Du prüfst alles im Editor, bevor es gespeichert wird.

DER PLAN
CookPlanner rechnet mit Deiner Küche: wie viele Platten, wie viele Öfen, wie viel Zeit. Der Plan zeigt, wann welcher Schritt dran ist, und sagt klar, ob das Gericht ins Budget passt – und wenn nicht, warum: zu viel Handarbeit, eine zu lange Kette oder Geräte, die sich in die Quere kommen. Was warm gehalten werden muss, kommt möglichst spät, Fleisch ruht genau so lange, wie es soll.

GEGEN DIE UHR
Im Kochmodus läuft der Countdown. Du siehst, was jetzt in Deinen Händen liegt, was gleich kommt und was von allein läuft. Jeden Schritt hakst Du ab; bist Du schneller oder langsamer, wird der Rest sofort neu gelegt. Pause und Rückgängig gibt es auch. Eine Mitteilung meldet jeden Schritt, der Sperrbildschirm zeigt die Restzeit und den nächsten Schritt – das iPhone darf auf der Arbeitsfläche liegen bleiben.

DEINE GERICHTE
Eigene Gerichte legst Du von Hand an oder importierst sie; drei Beispiele aus einer Kochsendung sind dabei. Alles bleibt auf Deinem Gerät. Für die Analyse wird nur der Rezepttext an einen Dienst von Google gesendet; die Webseite selbst lädt Dein iPhone.

CookPlanner stammt vom Entwickler von BakePlanner und nutzt denselben Planer – nur dass hier nicht rückwärts zum Brot gerechnet wird, sondern vorwärts gegen die Uhr.

---

### English

---

One dish with meat, sides, sauce and garnish, one cook at the stove and a fixed time: CookPlanner lays out the work steps so everything is ready at once, and tells you beforehand whether the time will do.

HOW IT WORKS
Enter a recipe, type it in or fetch it from the web: paste the text, enter an address or share the page from Safari. The analysis splits it into steps, estimates the hands-on work, recognises what simmers or bakes on its own and proposes what has to wait for what. You check everything in the editor before it is saved.

THE PLAN
CookPlanner works with your kitchen: how many burners, how many ovens, how much time. The plan shows when each step is due and says plainly whether the dish fits the budget – and if not, why: too much hands-on work, a chain that is too long, or appliances in each other's way. What has to be kept warm comes as late as possible, meat rests exactly as long as it should.

AGAINST THE CLOCK
In cook mode the countdown runs. You see what is in your hands now, what comes next and what runs on its own. Tick off each step; if you are faster or slower, the rest is laid out afresh at once. Pause and undo are there too. A notification announces every step, the lock screen shows the time left and the next step – the phone may stay on the counter.

YOUR DISHES
Create your own dishes by hand or import them; three examples from a cooking show are included. Everything stays on your device. For the analysis only the recipe text is sent to a Google service; the web page itself is loaded by your iPhone.

CookPlanner comes from the developer of BakePlanner and uses the same planner – except that here it does not work backward to the bread, but forward against the clock.

---

### Français

---

Un plat avec viande, garniture, sauce et finition, une personne aux fourneaux et un temps fixé : CookPlanner ordonne les étapes pour que tout soit prêt en même temps, et vous dit à l'avance si le temps suffira.

COMMENT ÇA MARCHE
Saisissez une recette, tapez-la ou allez la chercher sur le web : collez le texte, entrez une adresse ou partagez la page depuis Safari. L'analyse la découpe en étapes, estime le travail manuel, reconnaît ce qui mijote ou cuit tout seul et propose ce qui doit attendre quoi. Vous vérifiez tout dans l'éditeur avant l'enregistrement.

LE PLAN
CookPlanner compte avec votre cuisine : combien de feux, combien de fours, combien de temps. Le plan montre quand chaque étape arrive et dit clairement si le plat tient dans le budget – et sinon, pourquoi : trop de travail manuel, une chaîne trop longue ou des appareils qui se gênent. Ce qui doit rester chaud vient le plus tard possible, la viande repose exactement le temps voulu.

CONTRE LA MONTRE
En mode cuisine, le compte à rebours tourne. Vous voyez ce que vous avez en main, ce qui vient ensuite et ce qui tourne tout seul. Cochez chaque étape ; plus rapide ou plus lent, le reste est replacé aussitôt. Pause et annulation sont là aussi. Une notification annonce chaque étape, l'écran verrouillé montre le temps restant et l'étape suivante – le téléphone peut rester sur le plan de travail.

VOS PLATS
Créez vos plats à la main ou importez-les ; trois exemples d'une émission culinaire sont inclus. Tout reste sur votre appareil. Pour l'analyse, seul le texte de la recette est envoyé à un service de Google ; la page web est chargée par votre iPhone.

CookPlanner vient du développeur de BakePlanner et utilise le même planificateur – sauf qu'ici on ne calcule pas à rebours vers le pain, mais en avant, contre la montre.

---

## Schlüsselwörter (≤ 100 Zeichen, Kommas ohne Leerzeichen)

| Sprache | Schlüsselwörter | Zeichen |
|---|---|---|
| Deutsch | `Kochen,Rezept,Timer,Zeitplan,Menü,Küche,Planer,Gericht,Herd,Ofen,Schritte,Countdown,Wettkochen` | 94 |
| English | `cooking,recipe,timer,schedule,menu,kitchen,planner,dish,stove,oven,steps,countdown,dinner,meal prep` | 99 |
| Français | `cuisine,recette,minuteur,planning,menu,planificateur,plat,four,étapes,compte à rebours,dîner,repas` | 98 |

## Neuerungen (Version 1.0)

- DE: `Erste Version: Gerichte eingeben oder aus Text und Webseiten importieren, Plan mit Urteil und Grund, Kochmodus mit Countdown, Mitteilungen und Sperrbildschirm.`
- EN: `First version: enter dishes or import them from text and web pages, a plan with verdict and reason, cook mode with countdown, notifications and lock screen.`
- FR: `Première version : saisissez des plats ou importez-les depuis un texte ou une page web, un plan avec verdict et raison, le mode cuisine avec compte à rebours, notifications et écran verrouillé.`

## Hinweise für die Prüfung

---

No account is needed; everything can be tested without signing in. The app signs in anonymously with Firebase on the first cloud import, only to rate-limit the analysis.

To see the core feature: open one of the three example dishes under "Beispiele" (for instance "Perlhuhn-Geschnetzeltes …") → the plan shows the timeline and whether the dish fits 35 minutes → "Kochen starten" → "Start". The cook mode counts down, lists what is in your hands now, what comes next and what runs on its own; tick off a step with the checkmark and the rest is replanned. Allow notifications and Live Activities when asked: a notification announces each step, the lock screen shows the remaining time.

Import: "+" → "Aus Text importieren" (paste any recipe text) or "Aus Webseite importieren" (any recipe page, e.g. from chefkoch.de); the page is loaded on the device and only its recipe text is sent to our Cloud Function (Google Gemini) for structuring. The share extension does the same from Safari's share sheet. The result opens in an editor and is saved only with "Sichern".

Settings (slider icon): time budget, number of burners and ovens; the plans update accordingly.

---

## Offen

- Datenschutzrichtlinie für CookPlanner auf der Website (vor externem TestFlight).
- Screenshots (6,9-Zoll-iPhone Pflicht; iPad entfällt, wenn die App nur für iPhone angeboten wird – im Target steht derzeit iPhone und iPad).
- Prompt: Autorenzusatz aus Seitentiteln („… von Patzi“) entfernen.
