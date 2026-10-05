# Übersetzungsprüfung – offene Texte

Stand: 05.10.2026 · 170 Texte, deren englische oder französische Übersetzung noch niemand bestätigt hat (meist Xcodes maschinelle Übersetzung).

Ausgefüllt wird die CSV-Datei daneben (`Uebersetzungspruefung-offen.csv`), etwa in Numbers oder Excel. Diese Seite ist nur zum Lesen.

**So geht es:**

- In **Anmerkung EN** bzw. **Anmerkung FR** entweder `ok` eintragen (die Übersetzung passt) oder die bessere Fassung. Leer lassen heißt: noch nicht geprüft.
- Die Datei als CSV speichern (Semikolon getrennt, UTF-8) und zurückgeben. Übernommen wird sie mit `python3 scripts/translation-review.py import docs/Uebersetzungspruefung-offen.csv`.

**Beim Korrigieren bitte beachten:**

- `%@`, `%lld`, `%1$@` sind Platzhalter, die die App zur Laufzeit füllt (Namen, Zahlen, Uhrzeiten). Sie müssen erhalten bleiben; ihre Reihenfolge darf sich ändern, wenn die Nummer mitgeht (`%1$@`, `%2$@`).
- `⏎` steht für einen Zeilenumbruch im Text.
- Bei Pluralformen gibt es je Zahl eine eigene Fassung, gekennzeichnet mit `one:` und `other:`; eine Korrektur schreibt beide in dieser Form.
- Englisch: amerikanische Schreibung, Titel und Schaltflächen in Satzschreibung („Save recipe“, nicht „Save Recipe“), wie im größten Teil der App. Französisch: Anrede mit « vous », Leerzeichen vor `:` `;` `?` `!`.

| # | Deutsch | Englisch | Französisch | Hinweis |
|---|---|---|---|---|
| 1 | „%@“ | “%@” | « %@ » | Platzhalter |
| 2 | „%@“ wird als Administrator endgültig aus der öffentlichen Datenbank entfernt. | “%@” will be permanently removed from the public database as an administrator. | « %@ » sera supprimée définitivement de la base de données publique en tant qu’administrateur. | Platzhalter |
| 3 | %1$@, privates Rezept, Bewertung %2$lld von 5 Sternen | %1$@, private recipe, rating %2$lld out of 5 stars | %1$@, recette privée, note %2$lld sur 5 étoiles | Platzhalter |
| 4 | %1$lld von %2$lld Sternen | %1$lld out of %2$lld stars | %1$lld sur %2$lld étoiles | Platzhalter |
| 5 | Abmelden fehlgeschlagen | Sign-out failed | Échec de la déconnexion |  |
| 6 | Adresse der Rezeptseite | Address of the Recipe Page | Adresse de la page de recette |  |
| 7 | Alle Rezepte | All recipes | Toutes les recettes |  |
| 8 | Allgemeine Rezeptvorlage | General recipe source | Source de recette générale |  |
| 9 | Als öffentliches Rezept speichern | Save as a public recipe | Enregistrer comme recette publique |  |
| 10 | Als Rezeptnamen übernehmen | Use as the recipe name | Utiliser comme nom de la recette |  |
| 11 | Andere Seite laden | Load a Different Page | Charger une autre page |  |
| 12 | Anmeldung erforderlich | Sign-in required | Connexion requise |  |
| 13 | Apple-Konto | Apple Account | Compte Apple |  |
| 14 | Auf der Seite wurde kein Rezept mit Zutaten und Arbeitsschritten gefunden. | No recipe with ingredients and steps was found on the page. | Aucune recette avec des ingrédients et des étapes n’a été trouvée sur la page. |  |
| 15 | Auswahl | Selection | Sélection |  |
| 16 | Backfoto anzeigen | Show baking photo | Afficher la photo de cuisson |  |
| 17 | Backöfen | Ovens | Fours |  |
| 18 | BackPlaner speichert die übertragenen Rezeptbilder und Seitentexte weder in Firebase Storage noch in der Rezept-Datenbank. Sie werden innerhalb der Analyseanfrage verarbeitet und nicht dauerhaft abgelegt. | BackPlaner stores neither the transmitted recipe images nor the page texts in Firebase Storage or in the recipe database. They are processed within the analysis request and are not kept permanently. | BackPlaner n’enregistre ni les images de recettes ni les textes de pages transmis, que ce soit dans Firebase Storage ou dans la base de données de recettes. Ils sont traités dans le cadre de la demande d’analyse et ne sont pas conservés durablement. | langer Text |
| 19 | Bearbeitungsdauer: %@ | Working time: %@ | Durée de travail : %@ | Platzhalter |
| 20 | Benutzerhandbuch | User Manual | Manuel de l’utilisateur |  |
| 21 | Bitte ein Kürzel angeben. | Enter an abbreviation. | Saisissez une abréviation. |  |
| 22 | Bitte einen Namen angeben. | Enter a name. | Saisissez un nom. |  |
| 23 | Blockierte Autoren | Blocked Authors | Auteurs bloqués |  |
| 24 | Blockierte Autoren erscheinen sofort wieder in der Rezept-Datenbank. Ein gemeldetes Rezept bleibt dagegen für alle Nutzer ausgeblendet, bis ein Administrator es geprüft hat — das Zurücknehmen wirkt erst danach. | Authors you unblock reappear in the recipe database right away. A reported recipe, however, stays hidden from all users until an administrator has reviewed it — clearing it here only takes effect after that. | Les auteurs que vous débloquez réapparaissent immédiatement dans la base de recettes. En revanche, une recette signalée reste masquée pour tous les utilisateurs jusqu’à ce qu’un administrateur l’ait examinée : l’effacement ne prend effet qu’après. | langer Text |
| 25 | Blockierungen aufheben | Unblock All Authors | Débloquer tous les auteurs |  |
| 26 | Bruch | Fraction | Fraction |  |
| 27 | Cloud-Rezept kann nicht geändert werden | Cloud recipe cannot be changed | La recette dans le cloud ne peut pas être modifiée |  |
| 28 | Das Kürzel „%@“ ist schon vergeben. | The abbreviation “%@” is already taken. | L’abréviation « %@ » est déjà utilisée. | Platzhalter |
| 29 | Das Rezept bleibt auf dem Gerät und wird über Deine iCloud gesichert. | The recipe stays on the device and is backed up through your iCloud. | La recette reste sur l’appareil et est sauvegardée dans votre iCloud. |  |
| 30 | Das Rezept liegt jetzt unter „Eigene Rezepte“ auf diesem Gerät und wird über Deine iCloud gesichert. Dort kannst Du es bearbeiten, ohne das öffentliche Rezept zu verändern. | The recipe is now in “My recipes” on this device and is backed up through your iCloud. You can edit it there without changing the public recipe. | La recette se trouve maintenant dans « Mes recettes » sur cet appareil et est sauvegardée dans votre iCloud. Vous pouvez l’y modifier sans toucher à la recette publique. | langer Text |
| 31 | Das Rezept steht jetzt allen Nutzern zur Verfügung. Deine private Fassung ist unverändert — Du kannst sie über „Weitere Aktionen“ löschen, wenn Du sie nicht doppelt behalten willst. | The recipe is now available to all users. Your private version is unchanged—you can delete it from “More actions” if you don’t want to keep two copies of it. | La recette est désormais disponible pour tous les utilisateurs. Votre version privée est inchangée — vous pouvez la supprimer via « Plus d’actions » si vous ne souhaitez pas la conserver en double. | langer Text |
| 32 | Das Rezept wird endgültig aus Deiner privaten Ablage in der Rezept-Datenbank entfernt. | The recipe will be permanently removed from your private storage in the recipe database. | La recette sera supprimée définitivement de votre emplacement privé dans la base de recettes. |  |
| 33 | Das Rezept wird für alle Nutzer sichtbar und kann danach nicht mehr geändert werden. Veröffentliche nur Rezepte, die keine Urheberrechte verletzen. Deine private Fassung bleibt erhalten. | The recipe becomes visible to all users and can no longer be changed afterward. Only publish recipes that don’t infringe copyright. Your private version is kept. | La recette devient visible par tous les utilisateurs et ne pourra plus être modifiée ensuite. Ne publiez que des recettes qui ne portent atteinte à aucun droit d’auteur. Votre version privée est conservée. | langer Text |
| 34 | Das Rezept wird für alle Nutzer sichtbar. Veröffentliche nur Rezepte, die keine Urheberrechte verletzen. | The recipe becomes visible to all users. Only publish recipes that don’t infringe copyright. | La recette devient visible par tous les utilisateurs. Ne publiez que des recettes qui ne portent atteinte à aucun droit d’auteur. |  |
| 35 | Das Rezept wird in der Rezept-Datenbank gesichert, ist aber nur für Dich sichtbar. Geeignet für Rezepte, die Du nicht veröffentlichen darfst. Dazu ist eine Anmeldung mit Apple nötig. | The recipe is saved in the recipe database, but is visible only to you. Suitable for recipes you aren’t allowed to publish. This requires Sign in with Apple. | La recette est enregistrée dans la base de recettes, mais elle n’est visible que par vous. Convient aux recettes que vous n’avez pas le droit de publier. Pour cela, vous devez vous connecter avec Apple. | langer Text |
| 36 | Das Rezept wurde ohne KI aus den strukturierten Daten der Seite übernommen. Komponenten und Dauern bitte besonders prüfen. | The recipe was taken from the page’s structured data without AI. Please check the components and durations with particular care. | La recette a été reprise sans IA à partir des données structurées de la page. Vérifiez tout particulièrement les composants et les durées. | langer Text |
| 37 | Das sieht noch nicht nach einer vollständigen Internetadresse aus. | This does not look like a complete web address yet. | Cela ne ressemble pas encore à une adresse web complète. |  |
| 38 | Dauer in Minuten | Duration in minutes | Durée en minutes |  |
| 39 | Dauer: %lld Minuten | Duration: %lld minutes | Durée : %lld minutes | Platzhalter |
| 40 | Dauer: %lld Std. | Duration: %lld h | Durée : %lld h | Platzhalter |
| 41 | Dauer: %1$lld Std. %2$lld Min. | Duration: %1$lld h %2$lld min | Durée : %1$lld h %2$lld min | Platzhalter |
| 42 | Dauer: 1 Minute | Duration: 1 minute | Durée : 1 minute |  |
| 43 | Deine privaten Rezepte in der Rezept-Datenbank sind erst wieder sichtbar, wenn Du Dich erneut anmeldest. Rezepte auf diesem Gerät und von Dir veröffentlichte Rezepte bleiben unberührt. | Your private recipes in the recipe database become visible again only after you sign in. Recipes on this device and recipes you published are untouched. | Vos recettes privées dans la base de recettes ne seront de nouveau visibles qu’après une nouvelle connexion. Les recettes présentes sur cet appareil et celles que vous avez publiées ne sont pas touchées. | langer Text |
| 44 | Deine privaten Rezepte in der Rezept-Datenbank werden mit ihren Bildern gelöscht und die Anmeldung wird aufgehoben. Rezepte, die Du veröffentlicht hast, bleiben für alle Nutzer sichtbar. Rezepte auf diesem Gerät bleiben erhalten. Das lässt sich nicht widerrufen. | Your private recipes in the recipe database are deleted along with their images, and your Apple Account is unlinked. Recipes you’ve published stay visible to all users. Recipes on this device are kept. This can’t be undone. | Vos recettes privées dans la base de recettes sont supprimées avec leurs images et votre compte Apple est dissocié. Les recettes que vous avez publiées restent visibles par tous les utilisateurs. Les recettes présentes sur cet appareil sont conservées. Cette action est irréversible. | langer Text |
| 45 | Deine privaten Rezepte und die Anmeldung sind entfernt. Du kannst die App weiter verwenden und Dich jederzeit neu anmelden. | Your private recipes and your sign-in have been removed. You can keep using the app and sign in again at any time. | Vos recettes privées et votre connexion ont été supprimées. Vous pouvez continuer à utiliser l’app et vous reconnecter à tout moment. | langer Text |
| 46 | Der Rezepttext der Seite wird verschlüsselt über den geschützten BackPlaner-Server von Google Vertex AI analysiert. Dafür ist einmalig Deine Einwilligung nötig. | The page’s recipe text is analyzed by Google Vertex AI through the protected BackPlaner server, in encrypted form. This requires your consent once. | Le texte de recette de la page est analysé de manière chiffrée par Google Vertex AI via le serveur protégé de BackPlaner. Votre consentement est nécessaire une seule fois. | langer Text |
| 47 | Der Rezepttext der von Dir angegebenen Internetseite und ihre Adresse werden verschlüsselt an den geschützten Firebase-Endpunkt von BackPlaner und von dort an Google Vertex AI übertragen. Google ist dabei ein externer KI-Anbieter. Zur Absicherung und Nutzungsbegrenzung werden außerdem eine pseudonyme Firebase-Nutzerkennung, der App-Check-Nachweis sowie Anfragezeit und -anzahl verarbeitet. | The recipe text of the web page you entered and its address are transmitted in encrypted form to BackPlaner’s protected Firebase endpoint and from there to Google Vertex AI. Google is an external AI provider. To secure the service and limit usage, a pseudonymous Firebase user ID, the App Check attestation, and the time and number of requests are also processed. | Le texte de recette de la page web que vous avez indiquée ainsi que son adresse sont transmis de manière chiffrée au point de terminaison Firebase protégé de BackPlaner, puis à Google Vertex AI. Google est un fournisseur d’IA externe. Pour la sécurisation et la limitation d’usage, un identifiant d’utilisateur Firebase pseudonyme, l’attestation App Check ainsi que l’heure et le nombre des demandes sont également traités. | langer Text |
| 48 | Der Seitentext verlässt das Gerät nicht. Ohne Apple Intelligence werden nur die strukturierten Rezeptdaten der Seite übernommen. | The page text does not leave the device. Without Apple Intelligence, only the page’s structured recipe data is used. | Le texte de la page ne quitte pas l’appareil. Sans Apple Intelligence, seules les données de recette structurées de la page sont reprises. | langer Text |
| 49 | Details zu %@ | Details for %@ | Détails de %@ | Platzhalter |
| 50 | Die Adresse ist keine gültige Internetadresse. Sie muss mit https:// beginnen oder einen Domainnamen enthalten. | This is not a valid web address. It must start with https:// or contain a domain name. | Cette adresse n’est pas une adresse web valide. Elle doit commencer par https:// ou contenir un nom de domaine. |  |
| 51 | Die Analyse in der Cloud erfolgt nur auf Grundlage Deiner vorherigen ausdrücklichen Einwilligung. Ohne Einwilligung wird keine Cloud-Analyse gestartet. | Analysis in the cloud only takes place on the basis of your prior explicit consent. Without consent, no cloud analysis is started. | L’analyse dans le cloud n’a lieu que sur la base de votre consentement préalable et explicite. Sans consentement, aucune analyse cloud n’est lancée. | langer Text |
| 52 | Die Anmeldung wird für private Cloud-Rezepte benötigt: nur so bleiben sie nach einer Neuinstallation erreichbar. Administratoren verwalten damit gemeldete Rezepte. | Signing in is required for private cloud recipes: It’s the only way they stay accessible after you reinstall the app. Administrators use it to manage reported recipes. | La connexion est nécessaire pour les recettes privées dans le cloud : c’est le seul moyen de les garder accessibles après une réinstallation. Les administrateurs s’en servent pour gérer les recettes signalées. | langer Text |
| 53 | Die Backzeit (%1$@) überschneidet sich mit %2$@. Zusammen wären das mehr Backvorgänge, als Du Backöfen hast (%3$lld). | The baking time (%1$@) overlaps with %2$@. Together that would be more bakes than you have ovens (%3$lld). | Le temps de cuisson (%1$@) chevauche %2$@. Cela ferait plus de cuissons en même temps que vous n’avez de fours (%3$lld). | Platzhalter |
| 54 | Die Backzeit (%1$@) überschneidet sich mit der Backzeit von „%2$@“ (%3$@) und braucht deshalb einen weiteren Backofen. | The baking time (%1$@) overlaps with the baking time of “%2$@” (%3$@) and therefore needs another oven. | Le temps de cuisson (%1$@) chevauche le temps de cuisson de « %2$@ » (%3$@) et nécessite donc un four supplémentaire. | Platzhalter |
| 55 | Die Daten werden verschlüsselt an eine geschützte Google Firebase Cloud Function von BackPlaner in der Region europe-west1 übertragen. Die ausgewählten Bilder beziehungsweise der Seitentext werden von dort an Google Vertex AI (Gemini) am Standort EU zur Analyse weitergegeben. Die Internetseite selbst lädt Dein Gerät direkt. | The data is transmitted in encrypted form to a protected Google Firebase Cloud Function of BackPlaner in the europe-west1 region. From there, the selected images or the page text are passed on to Google Vertex AI (Gemini) in the EU for analysis. The web page itself is loaded directly by your device. | Les données sont transmises de manière chiffrée à une Cloud Function Google Firebase protégée de BackPlaner dans la région europe-west1. De là, les images sélectionnées ou le texte de la page sont transmis à Google Vertex AI (Gemini), situé dans l’UE, pour analyse. La page web elle-même est chargée directement par votre appareil. | langer Text |
| 56 | Die Menge gilt für diese Einkaufsliste. Das Rezept bleibt unverändert. | The amount applies to this shopping list. The recipe stays unchanged. | La quantité s’applique à cette liste de courses. La recette reste inchangée. |  |
| 57 | Die Seite konnte nicht geladen werden (Fehler %lld). Manche Seiten verlangen eine Anmeldung oder sperren den Abruf. | The page could not be loaded (error %lld). Some pages require a login or block automated access. | La page n’a pas pu être chargée (erreur %lld). Certaines pages exigent une connexion ou bloquent la consultation. | Platzhalter |
| 58 | Die Seite konnte nicht geladen werden. Bitte prüfe die Adresse und die Internetverbindung. | The page could not be loaded. Please check the address and your internet connection. | La page n’a pas pu être chargée. Vérifiez l’adresse et la connexion Internet. |  |
| 59 | Die Seite selbst wird von Deinem Gerät geladen. Der Text wird ausschließlich analysiert, um daraus einen Rezeptentwurf mit Zutaten und Arbeitsschritten zu erstellen. BackPlaner speichert den übertragenen Text nicht in Firebase Storage oder in der Rezept-Datenbank. | The page itself is loaded by your device. The text is analyzed solely to create a recipe draft with ingredients and steps. BackPlaner does not store the transmitted text in Firebase Storage or in the recipe database. | La page elle-même est chargée par votre appareil. Le texte est analysé uniquement pour en créer un brouillon de recette avec les ingrédients et les étapes. BackPlaner n’enregistre pas le texte transmis dans Firebase Storage ni dans la base de données de recettes. | langer Text |
| 60 | Die Umrechnung muss größer als 0 sein. | The conversion has to be greater than 0. | La conversion doit être supérieure à 0. |  |
| 61 | Die Verarbeitung erfolgt ausschließlich, um Zutaten, Mengen, Zeiten und Arbeitsschritte aus den Bildern oder dem Seitentext zu erkennen und daraus einen Rezeptentwurf zu erstellen. Die technischen Daten dienen der Absicherung des Endpunkts und dem Schutz vor missbräuchlicher oder übermäßiger Nutzung. | Processing takes place solely to recognize ingredients, amounts, times, and steps in the images or the page text and to create a recipe draft from them. The technical data serves to secure the endpoint and to protect against abusive or excessive use. | Le traitement sert exclusivement à reconnaître les ingrédients, les quantités, les durées et les étapes dans les images ou le texte de la page, puis à en créer un brouillon de recette. Les données techniques servent à sécuriser le point de terminaison et à protéger contre une utilisation abusive ou excessive. | langer Text |
| 62 | Du bist abgemeldet | You’re signed out | Déconnexion effectuée |  |
| 63 | Du hast noch keine eigene Einheit angelegt. Die mitgelieferten Einheiten stehen in der Auswahlliste immer zur Verfügung. | You haven’t added a unit of your own yet. The units that come with the app are always available in the list. | Vous n’avez pas encore ajouté d’unité personnalisée. Les unités fournies avec l’app sont toujours disponibles dans la liste. |  |
| 64 | Du kannst stattdessen jederzeit die lokale Analyse verwenden. Dann verlässt der Seitentext Dein Gerät nicht. | You can use the local analysis instead at any time. The page text then does not leave your device. | Vous pouvez à tout moment utiliser l’analyse locale à la place. Le texte de la page ne quitte alors pas votre appareil. |  |
| 65 | Eigene Einheiten | Custom units | Unités personnalisées |  |
| 66 | Ein Rezept in der Rezept-Datenbank kann nach dem Speichern nicht mehr geändert werden. Es ist nur für Dich sichtbar. | A recipe in the recipe database can no longer be changed after it has been saved. It’s visible only to you. | Une recette dans la base de recettes ne peut plus être modifiée après son enregistrement. Elle n’est visible que par vous. |  |
| 67 | Eine Einheit sagt der App, wie sie eine Menge in ein Gewicht umrechnet. Davon leben die Gesamtzutaten, die Bäckerprozente und die Einkaufsliste. Deshalb braucht auch eine eigene Einheit eine Umrechnung — ohne sie würde „2 Becher Mehl“ als 2 Gramm zählen. | A unit tells the app how to turn an amount into a weight. The total ingredients, the baker’s percentages and the shopping list all depend on it, which is why a unit of your own needs a conversion too — without one, “2 cups of flour” would count as 2 grams. | Une unité indique à l’app comment convertir une quantité en poids. Le total des ingrédients, les pourcentages boulangers et la liste de courses en dépendent : c’est pourquoi une unité personnalisée a aussi besoin d’une conversion. Sans elle, « 2 tasses de farine » compterait pour 2 grammes. | langer Text |
| 68 | Einheit auswählen, unbekannte Einheit | Select unit, unknown unit | Sélectionner une unité, unité inconnue |  |
| 69 | Einheit hinzufügen | Add unit | Ajouter une unité |  |
| 70 | Einheit nicht angelegt | Unit not added | Unité non ajoutée |  |
| 71 | Erkannte Vorlage | Detected source | Source détectée |  |
| 72 | Erneut anmelden | Sign in again | Se reconnecter |  |
| 73 | Es werden weder Name noch E-Mail-Adresse abgefragt. | You’re not asked for your name or email address. | Ni votre nom ni votre adresse e-mail ne sont demandés. |  |
| 74 | Fotografiere alle Seiten oder wähle sie in der richtigen Reihenfolge aus. Gut lesbare, gerade Bilder liefern das beste Ergebnis. Beschneide die Bilder so, dass Logos, Kopf- und Fußzeilen möglichst wegfallen. | Take a photo of every page or select the pages in the correct order. Straight, clearly readable images give the best results. Crop the images so that logos, headers and footers are left out. | Photographiez toutes les pages ou sélectionnez-les dans le bon ordre. Des images droites et bien lisibles donnent les meilleurs résultats. Recadrez les images afin d’écarter autant que possible les logos, en-têtes et pieds de page. | langer Text |
| 75 | Füge die Adresse einer Internetseite mit einem Backrezept ein. Die App lädt die Seite, liest Zutaten und Arbeitsschritte aus und zeigt sie Dir vor dem Speichern. | Paste the address of a web page with a baking recipe. The app loads the page, reads the ingredients and steps, and shows them to you before saving. | Collez l’adresse d’une page web contenant une recette de boulangerie. L’app charge la page, en extrait les ingrédients et les étapes et vous les présente avant l’enregistrement. | langer Text |
| 76 | Für Angaben wie ½ Würfel Hefe. Leer lassen, wenn Du mit der Menge oben arbeitest. | For amounts like ½ cube of yeast. Leave these empty if you use the amount above. | Pour des indications comme ½ cube de levure. Laissez ces champs vides si vous utilisez la quantité ci-dessus. |  |
| 77 | Für dieses Rezept sind keine Zutaten hinterlegt, die auf eine Einkaufsliste passen. | This recipe doesn’t have any ingredients that can be added to a shopping list. | Cette recette ne contient aucun ingrédient pouvant être ajouté à une liste de courses. |  |
| 78 | Gemessen in | Measured in | Mesurée en |  |
| 79 | Gesamtzutaten: | Total ingredients: | Total des ingrédients : |  |
| 80 | gezählt | counted | comptée |  |
| 81 | Gramm | Grams | Grammes |  |
| 82 | Hilfe | Help | Aide |  |
| 83 | Hilfe und Kontakt | Help and Contact | Aide et contact |  |
| 84 | https://… | https://… | https://… |  |
| 85 | Import nicht möglich | Unable to Import | Importation impossible |  |
| 86 | Internetadresse | Web Address | Adresse web |  |
| 87 | Internetadresse der Rezeptseite | Web address of the recipe page | Adresse web de la page de recette |  |
| 88 | Keine Dauer erkannt | No duration detected | Aucune durée détectée |  |
| 89 | Keine Zutaten vorhanden | No ingredients available | Aucun ingrédient disponible |  |
| 90 | KI-Analyse beim Rezeptimport | AI Analysis for Recipe Import | Analyse IA à l’importation de recettes |  |
| 91 | Komponente bearbeiten | Edit component | Modifier le composant |  |
| 92 | Konto | Account | Compte |  |
| 93 | Konto endgültig löschen? | Permanently delete account? | Supprimer définitivement le compte ? |  |
| 94 | Konto löschen | Delete account | Supprimer le compte |  |
| 95 | Konto wird gelöscht … | Deleting account… | Le compte est en cours de suppression… |  |
| 96 | Konto wurde gelöscht | Account was deleted | Le compte a été supprimé |  |
| 97 | Kürzel | Abbreviation | Abréviation |  |
| 98 | Kürzel der Einheit | Abbreviation of the unit | Abréviation de l’unité |  |
| 99 | Lokal | Local | Local |  |
| 100 | Mehrere Seiten können gemeinsam analysiert werden; von einer Internetseite genügt die Adresse. Anschließend lässt sich alles bearbeiten. | You can analyze multiple pages together; for a web page, the address is enough. Everything can be edited afterwards. | Vous pouvez analyser plusieurs pages ensemble ; pour une page web, l’adresse suffit. Tout peut ensuite être modifié. | langer Text |
| 101 | Meldungen auf diesem Gerät zurücknehmen | Clear Reports on This Device | Effacer les signalements sur cet appareil |  |
| 102 | Menge | Amount | Quantité |  |
| 103 | Menge ändern | Change amount | Modifier la quantité |  |
| 104 | Milliliter | Milliliters | Millilitres |  |
| 105 | Mit „Nur auf diesem Gerät“ werden weder Rezeptbilder noch Seitentexte an Firebase oder Google Vertex AI übertragen. Je nach Verfügbarkeit verwendet die App Apple Intelligence auf dem Gerät, die lokale Texterkennung oder die strukturierten Rezeptdaten der Seite. | With “On This Device Only”, neither recipe images nor page texts are transmitted to Firebase or Google Vertex AI. Depending on availability, the app uses Apple Intelligence on the device, local text recognition, or the page’s structured recipe data. | Avec « Sur cet appareil uniquement », ni les images de recettes ni les textes de pages ne sont transmis à Firebase ou à Google Vertex AI. Selon la disponibilité, l’app utilise Apple Intelligence sur l’appareil, la reconnaissance de texte locale ou les données de recette structurées de la page. | langer Text |
| 106 | Mit Apple anmelden | Sign in with Apple | Se connecter avec Apple |  |
| 107 | Moderation | Moderation | Modération |  |
| 108 | Name der Einheit | Name of the unit | Nom de l’unité |  |
| 109 | Name wählen | Choose name | Choisir le nom |  |
| 110 | Name: %@ | Name: %@ | Nom : %@ | Platzhalter |
| 111 | Namen auf der Seite auswählen | Choose the name on the page | Choisir le nom sur la page |  |
| 112 | Nenner | Denominator | Dénominateur |  |
| 113 | Neue Einheit | New unit | Nouvelle unité |  |
| 114 | Noch kein Rezeptbild | No recipe image yet | Pas encore d’image de recette |  |
| 115 | Nummer | Number | Numéro |  |
| 116 | Nur auf dem Gerät | On this device only | Uniquement sur l’appareil |  |
| 117 | Nur auf dem Gerät speichern | Save on this device only | Enregistrer uniquement sur l’appareil |  |
| 118 | Nur meine | Mine only | Les miennes |  |
| 119 | Öffentlich für alle | Public for everyone | Public pour tous |  |
| 120 | Öffnet die Seiten im Browser. | Opens the pages in your browser. | Ouvre les pages dans le navigateur. |  |
| 121 | Privat in der Cloud | Private in the cloud | Privé dans le cloud |  |
| 122 | Privat in der Cloud speichern | Save privately in the cloud | Enregistrer en privé dans le cloud |  |
| 123 | Private Rezepte in der Rezept-Datenbank gehören zu Deinem Apple-Konto. Ohne Anmeldung wäre das Rezept nach einer Neuinstallation nicht mehr erreichbar. | Private recipes in the recipe database belong to your Apple Account. Without signing in, the recipe would no longer be accessible after you reinstall the app. | Les recettes privées dans la base de recettes sont liées à votre compte Apple. Sans connexion, la recette ne serait plus accessible après une réinstallation. | langer Text |
| 124 | Quelle | Source | Source |  |
| 125 | Rezept veröffentlichen? | Publish recipe? | Publier la recette ? |  |
| 126 | Rezept von einer Internetseite | Recipe from a Web Page | Recette depuis une page web |  |
| 127 | Rezept von einer Internetseite importieren | Import recipe from a web page | Importer une recette depuis une page web |  |
| 128 | Rezept wird auf dem Gerät analysiert … | Analyzing recipe on this device … | Analyse de la recette sur l’appareil … |  |
| 129 | Rezept wird in der Cloud analysiert … | Analyzing recipe in the cloud … | Analyse de la recette dans le cloud … |  |
| 130 | Rezept wird veröffentlicht … | Publishing recipe… | La recette est en cours de publication… |  |
| 131 | Rezept wurde veröffentlicht | Recipe was published | La recette a été publiée |  |
| 132 | Rezeptbild | Recipe image | Image de la recette |  |
| 133 | Rezeptbild vergrößern | Enlarge recipe image | Agrandir l’image de la recette |  |
| 134 | Rezepte filtern | Filter recipes | Filtrer les recettes |  |
| 135 | Rezeptname | Recipe name | Nom de la recette |  |
| 136 | Schritt %@ | Step %@ | Étape %@ | Platzhalter |
| 137 | Seite | Page | Page |  |
| 138 | Seite laden und analysieren | Load and Analyze Page | Charger et analyser la page |  |
| 139 | Seite nicht verfügbar | Page not available | Page indisponible |  |
| 140 | Seite wird geladen … | Loading page … | Chargement de la page … |  |
| 141 | Seiten mit Anmeldung, Bezahlschranke oder Cookie-Hinweis lassen sich oft nicht auslesen. Für den privaten Gebrauch ist der Import unbedenklich; veröffentliche fremde Rezepte nur mit Erlaubnis. | Pages behind a login, paywall, or cookie notice often cannot be read. Importing for private use is fine; publish other people’s recipes only with permission. | Les pages avec connexion, paywall ou bandeau de cookies ne peuvent souvent pas être lues. L’importation pour un usage privé ne pose pas de problème ; ne publiez les recettes d’autrui qu’avec leur autorisation. | langer Text |
| 142 | Speichern fehlgeschlagen | Saving failed | Échec de l’enregistrement |  |
| 143 | Spezial (zweispaltig) | Special (two-column) | Spécial (deux colonnes) |  |
| 144 | Sprache wählen | Choose language | Choisir la langue |  |
| 145 | Stimmt der Name nicht, tippe ihn oben an — dann kannst du die richtige Zeile direkt auf der Seite auswählen. | If the name is wrong, tap it above — you can then pick the right line directly on the page. | Si le nom est incorrect, appuyez dessus ci-dessus : vous pourrez alors choisir la bonne ligne directement sur la page. |  |
| 146 | Stück | Pieces | Pièces |  |
| 147 | Tippe den Namen unten ein. | Type the name below. | Saisissez le nom ci-dessous. |  |
| 148 | Tippe die Zeile an, die der Rezeptname sein soll. Steht der Name nicht auf der Seite, kannst du ihn unten eintippen. | Tap the line that should be the recipe name. If the name isn’t on the page, you can type it below. | Appuyez sur la ligne qui doit servir de nom à la recette. Si le nom ne figure pas sur la page, saisissez-le ci-dessous. |  |
| 149 | Übersetzt … | Translating … | Traduction en cours … |  |
| 150 | Umrechnung | Conversion | Conversion |  |
| 151 | Unter dieser Adresse liegt keine Internetseite, sondern zum Beispiel eine PDF- oder Bilddatei. | This address does not lead to a web page but, for example, to a PDF or image file. | Cette adresse ne mène pas à une page web, mais par exemple à un fichier PDF ou image. |  |
| 152 | Url Link | URL link | Lien URL |  |
| 153 | Verarbeitungsschritt bearbeiten | Edit processing step | Modifier l’étape de préparation |  |
| 154 | Veröffentlichen | Publish | Publier |  |
| 155 | Veröffentlichen fehlgeschlagen | Publishing failed | Échec de la publication |  |
| 156 | Von Dir gemeldete Rezepte | Recipes You Reported | Recettes que vous avez signalées |  |
| 157 | Weitere Aktionen | More actions | Plus d’actions |  |
| 158 | Wenn Du die geschützte Cloud-KI auswählst, verarbeitet BackPlaner die von Dir ausgewählten Rezeptbilder oder den Rezepttext und die Adresse der von Dir angegebenen Internetseite sowie technische Schutzdaten der Anfrage. Dazu gehören eine pseudonyme Firebase-Nutzerkennung und der Nachweis von Firebase App Check. | If you choose the protected cloud AI, BackPlaner processes the recipe images you selected or the recipe text and address of the web page you entered, together with technical protection data of the request. This includes a pseudonymous Firebase user ID and the Firebase App Check attestation. | Si vous choisissez l’IA cloud protégée, BackPlaner traite les images de recettes que vous avez sélectionnées ou le texte de recette et l’adresse de la page web que vous avez indiquée, ainsi que des données techniques de protection de la demande. Celles-ci comprennent un identifiant d’utilisateur Firebase pseudonyme et l’attestation Firebase App Check. | langer Text |
| 159 | Wie viel Gramm eine Einheit wiegt. Ein Pfund wären 500. | How many grams one unit weighs. A pound would be 500. | Combien de grammes pèse une unité. Une livre correspondrait à 500. |  |
| 160 | Wie viele Milliliter eine Einheit enthält. Ein Becher wären etwa 250. Das Gewicht rechnet die App je Zutat daraus. | How many milliliters one unit holds. A cup would be about 250. The app works out the weight from that, per ingredient. | Combien de millilitres contient une unité. Une tasse correspondrait à environ 250. L’app en déduit le poids pour chaque ingrédient. |  |
| 161 | Wird gezählt, nicht gewogen. Die Umrechnung bleibt 1. | Counted rather than weighed. The conversion stays 1. | Comptée, pas pesée. La conversion reste 1. |  |
| 162 | Zähler | Numerator | Numérateur |  |
| 163 | Zur Sicherheit musst Du Dich noch einmal anmelden, bevor das Konto gelöscht wird. | For security, you need to sign in once more before the account is deleted. | Par mesure de sécurité, vous devez vous reconnecter avant la suppression du compte. |  |
| 164 | Zutat bearbeiten | Edit ingredient | Modifier l’ingrédient |  |
| 165 | Zutat entfernen | Remove ingredient | Retirer l’ingrédient |  |
| 166 | Zutat von der Einkaufsliste entfernen | Remove ingredient from shopping list | Retirer l’ingrédient de la liste de courses |  |
| 167 | BakePlanner | BakePlanner | BakePlanner |  |
| 168 | BakePlanner | BakePlanner | BakePlanner |  |
| 169 | BakePlanner verwendet die Kamera, um Fotos deiner Rezepte und fertigen Backwaren aufzunehmen. | BakePlanner uses the camera to take photos of your recipes and finished bakes. | BakePlanner utilise l’appareil photo pour prendre des photos de vos recettes et de vos préparations terminées. |  |
| 170 | BakePlanner greift auf deine Fotomediathek zu, damit du Bilder deiner Rezepte und Backwaren hinzufügen kannst. | BakePlanner accesses your photo library so you can add pictures of your recipes and bakes. | BakePlanner accède à votre photothèque afin que vous puissiez ajouter des images de vos recettes et de vos préparations. |  |
