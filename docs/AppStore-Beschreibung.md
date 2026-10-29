# App-Store-Produktseite (ab Version 2.0)

Die Texte für App Store Connect, je Sprache. Der Text zwischen den Linien wird unverändert eingefügt.

Solange die App noch keine Nutzer hat, berichtet die Produktseite keine Neuerungen, sondern stellt die Besonderheiten der App voran. Die eine Botschaft, die BakePlanner von Rezept-Apps unterscheidet: Du sagst, wann das Brot fertig sein soll, und die App rechnet rückwärts. Untertitel, Werbetext, die ersten Zeilen der Beschreibung und das erste Bild sagen alle dasselbe. Die Überschriften der Screenshots stehen in `docs/appstore/captions.json`, siehe [AppStore-Screenshots.md](AppStore-Screenshots.md).

## Name und Untertitel

Unter **App-Informationen**, je Sprache, höchstens 30 Zeichen. Beide fließen in die Suche ein, stärker als die Schlüsselwörter. Was dort steht, muss in den Schlüsselwörtern nicht noch einmal auftauchen.

| | Name | Untertitel | Zeichen |
|---|---|---|---|
| Deutsch | `BakePlanner` | `Sauerteigbrot rückwärts planen` | 30 |
| English | `BakePlanner` | `Plan sourdough bakes backward` | 29 |
| Français | `BakePlanner` | `Pain & levain, plan à rebours` | 29 |

Alternativen, falls der Untertitel breiter sein soll als Sauerteig: `Brot backen, rückwärts geplant` (30) · `Bread timing, planned backward` (30) · `Le pain planifié à rebours` (27).

## Werbetext

Auf der Versionsseite, höchstens 170 Zeichen. Er steht oben auf der Produktseite, lässt sich jederzeit ohne neue Prüfung ändern und zählt nicht für die Suche.

| Sprache | Werbetext | Zeichen |
|---|---|---|
| Deutsch | `Sag BakePlanner, wann das Brot fertig sein soll. Die App rechnet rückwärts, erinnert Dich an jeden Schritt und begleitet Dich in der Küche bis zum Ofen.` | 152 |
| English | `Tell BakePlanner when the bread should be ready. The app works backward, reminds you of every step and stays with you in the kitchen right up to the oven.` | 154 |
| Français | `Dites à BakePlanner quand le pain doit être prêt. L’app calcule à rebours, vous rappelle chaque étape et vous accompagne en cuisine jusqu’au four.` | 146 |

## Beschreibung

Höchstens 4000 Zeichen. Auf der Produktseite sind ohne „mehr“ nur die ersten drei Zeilen zu sehen, deshalb steht die Kernbotschaft im ersten Satz.

Die Sätze zu Siri setzen voraus, dass die Siri-Kurzbefehle im Build der Version 2.0 enthalten sind; sonst den zweiten Satz unter „In der Küche“ streichen.

### Deutsch

---

Wann muss der Sauerteig angesetzt werden, damit das Brot am Samstag um 18 Uhr aus dem Ofen kommt? BakePlanner rechnet es aus und erinnert Dich an jeden Schritt.

Ein Rezept besteht in BakePlanner nicht nur aus Zutaten, sondern aus Arbeitsschritten mit Dauern. Du wählst „Fertig bis“ oder „Starten ab“, und die App berechnet die Beginnzeit für Brühstück, Sauerteig, Kneten, Falten, Formen und Backen. „Backofen anstellen“ setzt sie von selbst dazu. Für jeden Schritt kommt eine Erinnerung auf iPhone, iPad und Apple Watch. Der nächste Schritt steht als Widget auf dem Home-Bildschirm und als Live-Aktivität auf dem Sperrbildschirm.

IN DER KÜCHE
Der Backmodus zeigt einen Schritt in großer Schrift, mit den Zutaten in der geplanten Portionsgröße, und liest ihn auf Wunsch vor. Mit Siri fragst Du nach dem nächsten Schritt, meldest ihn als erledigt oder verschiebst ihn, ohne das Display mit Teigfingern anzufassen.

BÄCKERRECHNER
• Anstellgut-TA: Das Rezept verlangt TA 150, Du führst Deines bei TA 200? Die App rechnet Anstellgutmenge und Wasser im Hauptteig um.
• Mehl ersetzen: Dinkel statt Weizen, Vollkorn statt Typ 550. Das Wasser folgt dem neuen Mehl, mit Hinweisen zur Verarbeitung.
• Teigtemperatur: die Schüttwassertemperatur für die gewünschte Teigtemperatur, mit Vorteig und Knetfaktor.
• Portionsgröße oder Teiggewicht frei wählbar. Teigausbeute, Hydration und Bäckerprozente rechnet die App mit.

SAUERTEIG PFLEGEN
Wiederkehrende Rezepte wie die Auffrischung des Anstellguts plant die App nach dem letzten Mal von selbst neu. Im Fütterungstagebuch hältst Du Zeit bis zum Höchststand, Schwimmtest und Notizen fest.

REZEPTE
Fotografiere ein Rezept aus dem Buch oder teile eine Internetseite aus Safari: BakePlanner liest Zutaten, Komponenten und Schritte aus und löst „alle 30 Minuten falten, 4x“ in getaktete Schritte auf. In der gemeinsamen Rezept-Datenbank findest Du Rezepte anderer Bäcker. Sie werden auf dem Gerät übersetzt, mit einem Glossar, das Brühstück, Stockgare und Anstellgut richtig überträgt. Eigene Rezepte bleiben auf dem Gerät, bis Du sie veröffentlichst. Ein Konto ist nicht nötig, die Anmeldung mit Apple ist freiwillig.

EINKAUFEN UND DOKUMENTIEREN
Die Einkaufsliste ist nach Regalen sortiert und übernimmt die Mengen in der gewählten Portionsgröße. Die Backhistorie hält Foto, Messwerte und Ergebnis jedes Backtags fest – als Liste, Galerie, Hit-Liste oder Fotowolke, in der jedes Rezept so groß erscheint, wie oft Du es gebacken hast.

BakePlanner – sag, wann das Brot fertig sein soll. Den Rest rechnet die App.

---

### English

---

When does the sourdough have to go on so the bread comes out of the oven at 6 pm on Saturday? BakePlanner works it out and reminds you of every step.

In BakePlanner a recipe is not just a list of ingredients but steps with durations. You choose “Done by” or “Start from”, and the app calculates the start time for the scald, the sourdough, kneading, folding, shaping and baking. “Turn on the oven” it adds by itself. Every step comes with a reminder on iPhone, iPad and Apple Watch. The next step sits as a widget on the Home Screen and as a Live Activity on the Lock Screen.

IN THE KITCHEN
Bake Mode shows one step in big type, with its ingredients at the planned serving size, and reads it aloud if you like. Ask Siri for the next step, mark it done or push it back without touching the screen with doughy fingers.

BAKER’S CALCULATORS
• Starter TA: the recipe wants a starter at TA 150 and you keep yours at TA 200? The app converts the amount of starter and the water in the main dough.
• Replace flour: spelt instead of wheat, wholegrain instead of white. The water follows the new flour, with advice on handling it.
• Dough temperature: the water temperature for the dough temperature you want, with preferment and friction factor.
• Serving size or dough weight, as you like. Dough yield, hydration and baker’s percentages are calculated along.

CARING FOR THE SOURDOUGH
Recurring recipes such as refreshing the starter are planned anew by the app after each time. In the feeding diary you note the time to peak, the float test and remarks.

RECIPES
Photograph a recipe from a book or share a web page from Safari: BakePlanner reads ingredients, components and steps and turns “fold every 30 minutes, 4x” into timed steps. In the shared recipe database you find recipes from other bakers. They are translated on the device, with a glossary that gets scald, bulk fermentation and starter right. Your own recipes stay on the device until you publish them. No account is needed; signing in with Apple is voluntary.

SHOPPING AND KEEPING RECORDS
The shopping list is sorted by shelf and takes the amounts at the chosen serving size. The baking history keeps a photo, measurements and the result of every baking day – as a list, gallery, top list or photo cloud, where every recipe appears as big as the number of times you have baked it.

BakePlanner – say when the bread should be ready. The app works out the rest.

---

### Français

---

Quand faut-il lancer le levain pour que le pain sorte du four samedi à 18 h ? BakePlanner le calcule et vous rappelle chaque étape.

Dans BakePlanner, une recette n’est pas qu’une liste d’ingrédients : ce sont des étapes avec des durées. Vous choisissez « Terminé pour » ou « Commencer à », et l’app calcule l’heure de début de l’échaudage, du levain, du pétrissage, des rabats, du façonnage et de la cuisson. « Allumer le four », elle l’ajoute d’elle-même. Chaque étape a son rappel sur iPhone, iPad et Apple Watch. La prochaine étape s’affiche en widget sur l’écran d’accueil et en activité en direct sur l’écran verrouillé.

EN CUISINE
Le mode cuisson affiche une étape en grands caractères, avec ses ingrédients à la taille de portion planifiée, et la lit à voix haute si vous le souhaitez. Demandez à Siri la prochaine étape, marquez-la comme faite ou décalez-la, sans toucher l’écran avec les doigts pleins de pâte.

CALCULATEURS DE BOULANGER
• TA du levain chef : la recette demande un levain chef à TA 150 et vous entretenez le vôtre à TA 200 ? L’app recalcule la quantité de levain chef et l’eau de la pâte principale.
• Remplacer la farine : épeautre au lieu de blé, complète au lieu de blanche. L’eau suit la nouvelle farine, avec des conseils pour la travailler.
• Température de la pâte : la température de l’eau de coulage pour la température de pâte souhaitée, avec pré-ferment et facteur de friction.
• Taille de portion ou poids de pâte, au choix. Rendement de pâte, hydratation et pourcentages du boulanger suivent.

ENTRETENIR LE LEVAIN
Les recettes récurrentes comme le rafraîchi du levain chef, l’app les replanifie d’elle-même après chaque fois. Dans le journal de nourrissage, vous notez le temps jusqu’au pic, le test de flottaison et vos remarques.

RECETTES
Photographiez une recette dans un livre ou partagez une page web depuis Safari : BakePlanner lit les ingrédients, les composants et les étapes, et transforme « rabattre toutes les 30 minutes, 4x » en étapes minutées. Dans la base de recettes partagée, vous trouvez les recettes d’autres boulangers. Elles sont traduites sur l’appareil, avec un glossaire qui rend correctement échaudage, pointage et levain chef. Vos propres recettes restent sur l’appareil jusqu’à ce que vous les publiiez. Aucun compte n’est nécessaire ; la connexion avec Apple est facultative.

COURSES ET SUIVI
La liste de courses est triée par rayon et reprend les quantités à la taille de portion choisie. L’historique de cuisson garde une photo, les mesures et le résultat de chaque journée de boulange – en liste, galerie, palmarès ou nuage de photos, où chaque recette apparaît aussi grande que le nombre de fois où vous l’avez cuite.

BakePlanner – dites quand le pain doit être prêt. L’app calcule le reste.

---

## Schlüsselwörter

Durch Kommas getrennt, ohne Leerzeichen danach, höchstens 100 Zeichen. Name und Untertitel zählen ohnehin mit, deshalb fehlen „Sauerteig“, „planen“ und ihre Entsprechungen. „Essen & Trinken“ ist die Kategorie der App und findet nichts zusätzlich.

| Sprache | Schlüsselwörter | Zeichen |
|---|---|---|
| Deutsch | `Backen,Brot,Rezepte,Backplan,Teig,Vorteig,Erinnerung,Einkaufsliste,Bäcker,Timer,Hefe,Roggen,Dinkel` | 98 |
| English | `baking,bread,recipe,schedule,dough,loaf,timer,reminder,shopping list,baker,yeast,rye,starter,oven` | 97 |
| Français | `boulange,recette,pâte,minuteur,rappel,liste de courses,four,boulanger,levure,seigle,baguette,cuisson` | 100 |

## Neuerungen in dieser Version

Die ausführlichen Texte für 2.1 stehen in [Neuerungen-2.1.md](Neuerungen-2.1.md) (je Sprache unter 4000 Zeichen); die von 2.0 in [Neuerungen-2.0.md](Neuerungen-2.0.md). Reicht ein Satz:

- DE: `Version 2.1 zeigt den Backtag als Ablaufplan, fasst die Backhistorie mit Hit-Liste und Fotowolke zusammen, erkennt Anstellgut an seinen Zutaten und füttert immer zur selben Uhrzeit. Dazu Korrekturen beim Verschieben von Schritten und beim Zurückdrehen des Ofens.`
- EN: `Version 2.1 shows your baking day as a project plan, sums the baking history up in a top list and a photo cloud, tells a starter by its ingredients and feeds it at the same time every day. Plus fixes for rescheduling steps and turning the oven down.`
- FR: `La version 2.1 présente la journée de boulange en planning, résume l’historique en palmarès et nuage de photos, reconnaît le levain chef à ses ingrédients et le nourrit chaque jour à la même heure. Avec des corrections pour le décalage des étapes et la baisse du four.`

## Hinweise für die Prüfung

Im Feld **Hinweise** der Versionsseite (die Prüfer lesen Englisch). Verkürzt die Prüfung, weil der Prüfer die Planung ohne Suchen findet:

---

No account is needed; everything can be tested without signing in. Sign in with Apple is optional and only ties published recipes to the user.

To see the core feature: Main menu → “Recipe database” → open “Kartoffelbrot mit Saaten” (or any public recipe) → tab “Bake recipe” → choose “Done by” and a date two days ahead → the start time of every step is calculated backward → “Set reminders” (allow notifications). The main menu then shows the next step; “Scheduled steps” shows the list, the timeline and “Bake mode”.

The three calculators (dough temperature, replace flour, starter TA) are in the main menu. Recipe import from photos uses an on-device model by default; the cloud option is explained in Settings → Privacy & AI.

---

## Website

Die Startseite unter `docs/website/index.html` sagt „Plane und backe dein perfektes Brot“. Der neue Untertitel gehört dort dazu, damit Suchende dieselbe Botschaft wiederfinden; die Tagline in der App kann bleiben.
