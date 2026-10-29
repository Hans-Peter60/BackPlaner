# App-Vorschauen 2.0 – Playbooks für die Aufnahme von Hand

Drei Vorschauen je Sprache (Deutsch, Englisch, Französisch), aufgenommen auf dem iPhone über den QuickTime Player, geschnitten in iMovie. Die Szenen und Einblendungen sind dieselben wie beim automatisierten Lauf (`scripts/appstore-previews.sh`, siehe [AppStore-Screenshots.md](AppStore-Screenshots.md)) und wie die Überschriften der Screenshots (`docs/appstore/captions.json`), damit Bilder und Videos auf der Produktseite eine Sprache sprechen.

## Vorgaben von Apple

| Was | Vorgabe |
|---|---|
| Länge | 15 bis 30 Sekunden je Vorschau |
| Anzahl | bis zu drei je Gerätegröße und Sprache |
| Format | Hochformat, H.264, 30 fps, iMovie-Export „App-Vorschau“ liefert die passende Auflösung (iPhone 6,9": 886 × 1920 oder 1080 × 1920; iPad 13": 1200 × 1600) |
| Inhalt | nur die App selbst. Keine Hände, kein Geräterahmen, keine Preise, keine Hinweise auf andere Plattformen |
| Ton | optional. In der Suche läuft die Vorschau stumm an, deshalb muss alles ohne Ton verständlich sein |
| Posterbild | wird in App Store Connect aus dem Video gewählt, am besten die Timeline (Szene 1) oder der Rechner (Szene 2) |

Die Vorschau steht in den Suchergebnissen **vor** den Screenshots und läuft dort automatisch an. Die ersten drei Sekunden entscheiden, also sofort mit dem Rezept beginnen und den Home-Bildschirm wegschneiden.

## Einmalige Vorbereitung

**iPhone**

1. BakePlanner 2.0 (Build 8) aus TestFlight oder dem App Store installieren, nicht den Debug-Build. Nur der Store-Build spricht mit der Produktions-iCloud und zeigt die echten Daten.
2. Fokus „Nicht stören“ einschalten, damit keine Mitteilungsbanner ins Bild fallen. Die Erinnerungen, die Szene 1 setzt, liegen in der Zukunft und stören nicht.
3. Helligkeit auf etwa 80 % und Auto-Helligkeit aus. Hellen Modus verwenden, so wie die Screenshots.
4. Textgröße auf Standard (Einstellungen → Anzeige & Helligkeit → Textgröße, Regler in der Mitte).
5. Aufräumen, was ins Bild käme: unter „Geplante Schritte“ alte Pläne löschen, unter „Einkaufsliste“ alte Listen löschen, in der Rezept-Datenbank unter „Lokal“ eine eventuell vorhandene Kopie von „Kartoffelbrot mit Saaten“ entfernen. Das Setzen der Erinnerungen legt diese Kopie an, sonst steht das Rezept doppelt in der Liste.
6. Das Demo-Rezept ist das öffentliche **„Kartoffelbrot mit Saaten“** (Rezept-Datenbank → Chip „Öffentlich“). Vor der englischen und französischen Aufnahme einmal in der jeweiligen Sprache öffnen und abwarten, bis die Übersetzung fertig ist (Globus-Symbol ohne Ladekreis). Dann ist sie zwischengespeichert und erscheint im Video ohne Wartezeit.

**Sprache der App umstellen**

Einstellungen → Apps → BakePlanner → Sprache → Deutsch / English / Français. Die App startet in der gewählten Sprache neu, das System bleibt deutsch. Nach jeder Sprache einmal alle drei Szenen aufnehmen, dann umstellen.

**QuickTime Player am Mac**

1. iPhone per Kabel anschließen, entsperren, dem Mac vertrauen.
2. QuickTime Player → Ablage → Neue Videoaufnahme. Neben dem roten Aufnahmeknopf den Pfeil aufklappen und als **Kamera das iPhone** wählen. Mikrofon: „Keins“ oder das iPhone, falls Ton gewünscht. Qualität: Maximum.
3. Das iPhone zeigt jetzt im Spiegelbild die saubere Statusleiste (9:41, voller Akku, volles Netz). Das ist Absicht und erwünscht.
4. Aufnahme mit dem roten Knopf starten, am Ende wieder stoppen. Sichern unter `docs/appstore/2.1/preview/iphone-6.9/<sprache>/roh/<szene>.mov` (der Ordner `preview` ist git-ignoriert).

**Grundregeln beim Tippen**

- Vor jedem Tipp eine Sekunde ruhig halten, nach jedem Bildwechsel zwei bis drei Sekunden, damit der Betrachter lesen kann. Lieber zu langsam, kürzen geht immer.
- Wischen immer langsam und in einer Bewegung. Kein Zoomen, kein Zurückrudern. Bei einem Fehler die Aufnahme laufen lassen und die Szene von vorn tippen, der Schnitt nimmt die beste Fassung.
- Pro Szene 45 bis 60 Sekunden aufnehmen, geschnitten bleiben 25 bis 30.

## Vor jeder Aufnahme

- [ ] Geplante Schritte leer, Einkaufslisten leer, keine lokale Kopie des Demo-Rezepts
- [ ] App auf dem Hauptmenü, oben angekommen
- [ ] Fokus „Nicht stören“ an, Kabel sitzt, QuickTime zeigt das iPhone
- [ ] Sprache der App stimmt mit dem geplanten Video überein

## Playbook 1 – Planen und backen (Ziel 30 s)

Rezept → „Rezept backen“ → Fertig bis → Erinnerungen → Karte „Als Nächstes“ → Timeline → Backmodus.

| Ab s | Aktion auf dem iPhone | Was zu sehen ist | Einblendung |
|---|---|---|---|
| 0 | Im Hauptmenü **Rezept-Datenbank** tippen, dann **Kartoffelbrot mit Saaten** | Rezept öffnet auf „Details“ mit Bild, Gewicht und Zutaten | – |
| 3 | Tab **Rezept backen** tippen. Oben in der Steuerung **Bis** wählen, im Datumsfeld **morgen 12:00** einstellen, Picker schließen | Die Schritte zeigen berechnete Beginnzeiten | *Sag, wann das Brot fertig sein soll* |
| 8 | Zwei Sekunden halten, dann langsam nach unten wischen bis zum Knopf **Erinnerungen setzen** | Reihenfolge der Schritte mit Uhrzeiten, Ruhe über Nacht | *BakePlanner rechnet jeden Schritt zurück* |
| 13 | **Erinnerungen setzen** tippen. Erscheint „Bestehenden Plan ersetzen“, das wählen. Mitteilungs-Erlaubnis bestätigen, falls gefragt | Zusammenfassung: „N Erinnerungen gesetzt. Backofen anstellen um … Fertig um …“, zwei Sekunden halten, **OK** | *Erinnerung für jeden Schritt* |
| 18 | Zurück zum Hauptmenü (Zurück-Pfeil zweimal) | Karte **Als Nächstes** mit dem ersten Schritt und seiner Uhrzeit, drei Sekunden halten | – |
| 21 | **Geplante Schritte** tippen, dann Tab **Timeline** | Timeline des Backtags, drei Sekunden halten | – |
| 25 | Tab **Geplante Schritte**, dann den Knopf **Backmodus** | Ein Schritt in großer Schrift mit Zutaten und „Vorlesen“, vier Sekunden halten | *In der Küche: ein Schritt, große Schrift* |
| 30 | **Schließen** (X oben), eine Sekunde, Aufnahme stoppen | | |

Falls im Plan Mond-Symbole (Nacht-Warnungen) auftauchen, statt „Bis morgen 12:00“ **Ab heute 20:00** wählen, so wie der automatisierte Lauf. Der Teig ruht dann über Nacht, und kein Schritt fällt in die Nacht. Die Einblendung bleibt dieselbe.

## Playbook 2 – Die Rechner (Ziel 25 s)

Portionsgröße ×2 → Mehl ersetzen → Anstellgut-TA → Teigtemperatur.

| Ab s | Aktion auf dem iPhone | Was zu sehen ist | Einblendung |
|---|---|---|---|
| 0 | **Rezept-Datenbank** → **Kartoffelbrot mit Saaten** | Tab „Details“ mit Portionsgröße, Gewicht, Teigausbeute | – |
| 3 | In der Portionsgröße **2,0** tippen (englisch: 2.0) | Gewicht und alle Zutatenmengen verdoppeln sich, drei Sekunden halten | *Alles rechnet mit* |
| 7 | Nach unten zur Mehlzeile des Hauptteigs (**Weizenmehl 1050**) wischen und sie antippen | Sheet **Mehl ersetzen** mit „Im Rezept“ und „Ersetzen durch“ | – |
| 10 | Unter **Ersetzen durch** ein anderes Mehl wählen, z. B. Dinkelmehl 630 | Wasser-Anpassung und Hinweise unter „Worauf achten“ erscheinen, vier Sekunden halten, dann **Abbrechen** | *Mehl tauschen, Wasser folgt* |
| 15 | Die Anstellgut-Zeile (**… TA150**) antippen | Sheet **Anstellgut-TA anpassen** | – |
| 17 | Bei „Vorhanden“ **220** tippen | Neue Anstellgut-Menge und „Wasser im Teig: …“ ändern sich, drei Sekunden halten, dann **Abbrechen** | *Dein Anstellgut, Deine TA* |
| 21 | Zurück zum Hauptmenü, **Teigtemperatur** tippen | Rechner mit Schüttwassertemperatur | – |
| 23 | Die Raum- oder Mehltemperatur um ein paar Grad verstellen | Die Wassertemperatur springt mit, vier Sekunden halten, Aufnahme stoppen | *Die richtige Wassertemperatur* |

Die Rechner kommen in der App in zwei Fassungen vor, aus dem Hauptmenü und aus der Zutatenzeile heraus. Im Video zählt die zweite: Sie zeigt, dass der Rechner das Rezept kennt.

## Playbook 3 – Rezepte hinein, Einkaufsliste heraus, jede Sprache (Ziel 25 s)

Formular „Neues Rezept“ mit Import → Einkaufsliste nach Regalen → öffentliches Rezept in anderer Sprache.

| Ab s | Aktion auf dem iPhone | Was zu sehen ist | Einblendung |
|---|---|---|---|
| 0 | Im Hauptmenü **Neues Rezept anlegen** tippen | Formular mit „Rezept aus Bildern importieren“ und „Rezept von einer Internetseite importieren“, drei Sekunden halten | *Aus dem Buch oder aus dem Netz* |
| 4 | Zurück, **Rezept-Datenbank** → **Kartoffelbrot mit Saaten** → Tab **Einkaufsliste** | Zutaten zum Einkaufen in der gewählten Portionsgröße | – |
| 8 | **Einkaufsliste erstellen** tippen, Bestätigung mit **OK** schließen | Kurze Meldung, dass die Liste angelegt ist | – |
| 11 | Zurück zum Hauptmenü, **Einkaufsliste** tippen | Die Liste nach Regalen gruppiert (Mehl, Kühlregal, …), vier Sekunden halten | *Einkaufsliste nach Regalen* |
| 16 | Zurück, **Rezept-Datenbank** → **Kartoffelbrot mit Saaten** | Rezept in der App-Sprache, zwei Sekunden halten | – |
| 18 | **Globus** oben rechts tippen, eine andere Sprache wählen: im deutschen Video **English**, im englischen und französischen **Deutsch** | Name, Zutaten und Schritte wechseln die Sprache, drei bis vier Sekunden halten, Aufnahme stoppen | *Öffentliche Rezepte in Deiner Sprache* |

Die Übersetzung in Schritt 18 ist nur dann sofort da, wenn sie zuvor einmal auf dem Gerät erzeugt wurde (siehe Vorbereitung, Punkt 6). Erscheint ein Hinweis zum Laden einer Sprache, erlauben, dann ohne Aufnahme warten und die Szene wiederholen.

## Einblendungen in den drei Sprachen

Große Zeile zuerst, nach dem `|` die kleinere zweite Zeile. Pro Einblendung zwei bis drei Sekunden stehen lassen, am oberen Bildrand über der Navigationsleiste oder im unteren Drittel, wo gerade nichts Wichtiges liegt.

| Szene | Deutsch | English | Français |
|---|---|---|---|
| 1 | Sag, wann das Brot fertig sein soll \| BakePlanner rechnet jeden Schritt zurück | Say when the bread should be ready \| BakePlanner works every step back from there | Dites quand le pain doit être prêt \| BakePlanner remonte chaque étape à rebours |
| 1 | Erinnerung für jeden Schritt \| Auf iPhone, iPad und Apple Watch | A reminder for every step \| On iPhone, iPad and Apple Watch | Un rappel pour chaque étape \| Sur iPhone, iPad et Apple Watch |
| 1 | Dein Backtag auf einen Blick | Your baking day at a glance | Votre journée de boulange d’un coup d’œil |
| 1 | In der Küche: ein Schritt, große Schrift \| Mit den Zutaten, auf Wunsch vorgelesen | In the kitchen: one step, big type \| With its ingredients, read aloud on request | En cuisine : une étape, en grand \| Avec ses ingrédients, lue à voix haute si vous voulez |
| 2 | Portionsgröße, Teiggewicht, Teigausbeute \| Alles rechnet mit | Serving size, dough weight, dough yield \| Everything scales along | Portion, poids de pâte, rendement \| Tout se recalcule |
| 2 | Mehl tauschen, Wasser folgt \| Dinkel, Roggen, Vollkorn: mit Hinweisen | Swap the flour, the water follows \| Spelt, rye, wholegrain: with advice | Changez de farine, l’eau suit \| Épeautre, seigle, complète : avec conseils |
| 2 | Dein Anstellgut, Deine TA \| Die App rechnet Anstellgut und Wasser um | Your starter, your TA \| The app adjusts starter and water | Votre levain chef, votre TA \| L’app recalcule levain chef et eau |
| 2 | Die richtige Wassertemperatur \| Für die Teigtemperatur, die das Rezept will | The right water temperature \| For the dough temperature the recipe wants | La bonne température de l’eau \| Pour la température de pâte voulue |
| 3 | Aus dem Buch oder aus dem Netz \| Foto oder Link: die App liest das Rezept aus | From the book or from the web \| Photo or link: the app reads the recipe | Du livre ou du web \| Photo ou lien : l’app lit la recette |
| 3 | Einkaufsliste nach Regalen \| In der gewählten Portionsgröße | Shopping list by shelf \| At the serving size you chose | Liste de courses par rayon \| À la taille de portion choisie |
| 3 | Öffentliche Rezepte in Deiner Sprache | Public recipes in your language | Les recettes publiques dans votre langue |

Die Texte der Szenen 1 und 2 sind wörtlich die Screenshot-Überschriften aus `captions.json`. Die beiden letzten Zeilen der Szene 3 gibt es nur im Video. Dieselben Texte stehen, in dieser Reihenfolge, in `docs/appstore/preview-captions.json`, aus der die Overlay-Bilder für iMovie entstehen (siehe Schnitt, Punkt 6).

## Schnitt in iMovie

1. iMovie → **Neu erstellen → App-Vorschau**. iMovie erkennt am importierten Clip das Gerät und stellt das Projekt auf dessen Maße.
2. Rohvideo importieren (Ablage → Medien importieren) und in die Timeline ziehen.
3. **Anfang trimmen**: alles bis zum ersten Antippen im Hauptmenü weg, das Video beginnt mit dem Öffnen der Rezept-Datenbank. **Ende trimmen**: nach dem letzten Halten, bevor der Finger wieder etwas tut.
4. Lange Wartezeiten (Übersetzung, Sheet-Animationen) herausschneiden: Clip an der Stelle teilen (⌘B), Mittelstück löschen. Harte Schnitte sind in App-Vorschauen üblich, Überblendungen weglassen.
5. Prüfen, dass die Gesamtlänge zwischen 15 und 30 Sekunden liegt (unten rechts). Lieber 25 bis 28 Sekunden, nicht auf 30,0 zielen.
6. **Einblendungen als Overlay-Bilder.** iMovies eigene Titelvorlagen werden nicht benutzt: Ihre Namen und Positionen unterscheiden sich je nach Version, und keine sieht aus wie die Überschriften auf den Screenshots. Stattdessen rendert ein Skript jede Einblendung als transparentes PNG in den Farben und der Schrift der Screenshots, das in iMovie über dem Video liegt:
   ```sh
   swift scripts/appstore-preview-captions.swift docs/appstore/preview-captions.json de docs/appstore/2.1/preview/captions/de
   swift scripts/appstore-preview-captions.swift docs/appstore/preview-captions.json de docs/appstore/2.1/preview/captions/de --position bottom
   ```
   (genauso für `en` und `fr`). Die Texte stehen in `docs/appstore/preview-captions.json`, die Bilder heißen `1-1-fertig-bis.png`, `1-2-erinnerung.png`, … nach Szene und Reihenfolge; mit `--position bottom` entstehen dieselben als `…-unten.png` für Stellen, an denen oben gerade etwas passiert. Die Bilder sind 886 × 1920 Pixel wie das fertige iPhone-Video (für ein anderes Maß `--size 1200x1600`) und außerhalb der Textkachel durchsichtig. Der Ordner liegt unter `preview/` und ist git-ignoriert; nach einer Textänderung einfach neu rendern.

   So kommen sie ins Video:
   - **Importieren**: Ablage → Medien importieren (⌘I), den Ordner `captions/<sprache>` wählen, alle PNGs importieren. Sie erscheinen in „Meine Medien“.
   - **Über den Clip legen**: das PNG aus „Meine Medien“ in die Timeline ziehen, und zwar **oberhalb** des Videoclips an die Stelle, an der die Einblendung beginnen soll. Es wird zu einem Overlay-Clip über dem Video. (Landet es stattdessen hinter dem Video in der Hauptspur, ⌘Z und etwas höher fallen lassen.)
   - **Als Ausschnitt einstellen**: Overlay-Clip anklicken, über dem Vorschaufenster das Symbol mit den zwei überlappenden Rechtecken (Overlay-Einstellungen) wählen und im Menü **„Ausschnitt“** einstellen. Das ist bei einem Bild meist schon voreingestellt. Die durchsichtigen Teile des PNGs lassen das Video durch; nur die Textkachel ist zu sehen. Direkt daneben „Überblenden“ auf etwa 0,3 s stellen, dann blendet die Kachel weich ein und aus.
   - **Ken-Burns ausschalten**: beim ausgewählten Overlay das Zuschneide-Symbol wählen und **„Anpassen“** statt „Ken Burns“ einstellen, sonst wandert die Kachel langsam durchs Bild. Bei gleichem Pixelmaß wie das Video füllt das Bild dann den Rahmen exakt.
   - **Dauer**: am rechten Rand des Overlay-Clips auf 2,5 bis 3 s ziehen oder im Clip-Informationsfenster (ⓘ) eintippen. Bildclips bekommen in iMovie zunächst vier Sekunden.
   - **Weitere Einblendungen**: jeweils das nächste PNG an die nächste Stelle über dem Video ziehen und dieselben drei Einstellungen setzen (Ausschnitt, Anpassen, Überblenden), dann die Dauer. iMovie merkt sich die Einstellungen nicht pro Projekt, es sind aber nur drei Klicks je Clip.
   - Die erste Einblendung erst nach etwa einer Sekunde beginnen lassen, weil App Store Connect das Posterbild aus dem Video wählt und dafür ein Bild ohne Text besser passt.

   Falls du doch iMovies Titel nehmen willst: im Titelbrowser (⌘5) mit der Maus über die Vorlagen fahren und eine wählen, bei der der Text still steht und oben oder unten sitzt, nicht in der Mitte. Die Namen weichen je nach iMovie-Version ab.
7. Optional ein leises Musikbett aus den iMovie-Soundeffekten, Lautstärke um 30 %. Bei Ton vom iPhone (Vorlesen in Szene 1) diesen behalten, Musik dort absenken.
8. **Export**: Ablage → Bereitstellen → **App-Vorschau**. Speichern als `docs/appstore/2.1/preview/iphone-6.9/<sprache>/1-plan.mp4`, `2-calculators.mp4`, `3-shopping.mp4`.

Für jede Sprache ein eigenes iMovie-Projekt (duplizieren und Clips tauschen geht am schnellsten, die Titelpositionen bleiben dann gleich).

## Hochladen

App Store Connect → BakePlanner → Version 2.0 → oben rechts die Sprache wählen → **iPhone 6,9"-Display** → die drei Videos vor die Screenshots ziehen, Reihenfolge 1-plan, 2-calculators, 3-shopping. Nach dem Verarbeiten je Video das **Posterbild** wählen (Timeline bzw. Rechner). Danach „Sichern“. Die Vorschauen lassen sich auch zu einer bereits eingereichten Version nachtragen, solange sie noch nicht freigegeben ist, oder nach der Freigabe mit der nächsten Produktseiten-Änderung.

Das iPad braucht nur Szene 1. Die Aufnahme läuft genauso über QuickTime mit dem iPad als Kamera; iMovie erkennt das Format.

## Wenn etwas hakt

| Problem | Abhilfe |
|---|---|
| QuickTime bietet das iPhone nicht als Kamera an | Kabel neu stecken, iPhone entsperren, „Diesem Computer vertrauen“ bestätigen, QuickTime neu starten |
| Statusleiste zeigt die echte Uhrzeit | Das passiert nur ohne Kabel (Bildschirmaufnahme am iPhone). Über QuickTime am Mac aufnehmen |
| Rezept steht doppelt in der Liste | Lokale Kopie unter „Lokal“ löschen (Vorbereitung, Punkt 5) |
| Mond-Symbole im Plan | „Ab heute 20:00“ statt „Bis morgen 12:00“ |
| Übersetzung lädt im Bild | Vorher einmal ohne Aufnahme übersetzen lassen, dann wiederholen |
| Die Textkachel wandert oder ist beschnitten | Beim Overlay-Clip das Zuschneide-Symbol → „Anpassen“ wählen (Ken Burns aus) |
| Statt der Kachel ist ein beiges Rechteck mit schwarzem Rand zu sehen | Der Overlay-Modus steht nicht auf „Ausschnitt“, oder das PNG wurde in der Hauptspur abgelegt statt darüber |
| iMovie exportiert nicht als App-Vorschau | Projektart prüfen: Es muss ein Projekt vom Typ „App-Vorschau“ sein, kein „Film“. Notfalls neues Projekt anlegen und Clips hineinziehen |
| App Store Connect lehnt das Video ab | Länge 15 bis 30 s, 30 fps, Hochformat prüfen. iMovie-Export „App-Vorschau“ erfüllt die Maße, QuickTime-Exporte nicht |
