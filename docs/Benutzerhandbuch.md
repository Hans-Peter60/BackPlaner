# BackPlaner – Benutzerhandbuch

Stand: 07.09.2026 · App-Version 1.0

---

## Inhalt

1. [Was BackPlaner macht](#1-was-backplaner-macht)
2. [Systemvoraussetzungen](#2-systemvoraussetzungen)
3. [Grundbegriffe](#3-grundbegriffe)
4. [Das Hauptmenü](#4-das-hauptmenü)
5. [Rezept-Datenbank (öffentliche Rezepte)](#5-rezept-datenbank-öffentliche-rezepte)
6. [Eigene Rezepte](#6-eigene-rezepte)
7. [Backanleitung und Reminder](#7-backanleitung-und-reminder)
8. [Neues Rezept anlegen](#8-neues-rezept-anlegen)
9. [Rezept bearbeiten](#9-rezept-bearbeiten)
10. [Geplante Schritte (Liste und Timeline)](#10-geplante-schritte-liste-und-timeline)
11. [Erinnerungen auf dem Sperrbildschirm](#11-erinnerungen-auf-dem-sperrbildschirm)
12. [Backhistorie und Back Hit-Liste](#12-backhistorie-und-back-hit-liste)
13. [Einkaufsliste](#13-einkaufsliste)
14. [Einstellungen](#14-einstellungen)
15. [Einheiten, Mengen und Portionsgrößen](#15-einheiten-mengen-und-portionsgrößen)
16. [Datenschutz, Moderation und Nutzungsbedingungen](#16-datenschutz-moderation-und-nutzungsbedingungen)
17. [Häufige Fragen und Fehlerbehebung](#17-häufige-fragen-und-fehlerbehebung)
18. [Bekannte Einschränkungen](#18-bekannte-einschränkungen)

---

## 1. Was BackPlaner macht

BackPlaner ist eine Backplanungs-App für Brot, Brötchen und Gebäck. Sie unterscheidet sich von einer reinen Rezept-Sammlung dadurch, dass sie **die Zeitplanung übernimmt**:

- Ein Rezept besteht nicht nur aus Zutaten, sondern aus **Verarbeitungsschritten mit Dauern**.
- Aus diesen Dauern berechnet die App die **Startzeit jedes einzelnen Schritts**.
- Du kannst rückwärts planen: „Das Brot soll um 18:00 Uhr fertig sein“ – die App sagt Dir, wann Du den Sauerteig ansetzen musst.
- Für jeden Schritt wird eine **lokale Erinnerung** gesetzt, inklusive automatisch eingefügtem Schritt „Backofen anstellen“ und „Backvorgang ist beendet“.

Dazu kommen: eine gemeinsame öffentliche Rezept-Datenbank, eigene private Rezepte, Zutaten-Import aus Fotos, Einkaufslisten, eine Backhistorie mit Fotos und Bewertungen sowie eine On-Device-Übersetzung öffentlicher Rezepte.

### Schnellstart: In fünf Schritten zum ersten Backplan

1. Öffne **Rezept-Datenbank** und wähle ein Rezept – oder lege unter **Neues Rezept anlegen** ein eigenes an.
2. Öffne im Rezept den Tab **Backen** beziehungsweise **Rezept backen**.
3. Wähle **Starten ab** oder **Fertig bis** und stelle Datum und Uhrzeit ein.
4. Prüfe die berechneten Beginnzeiten und tippe auf **Reminder setzen**.
5. Öffne **Geplante Schritte**, um alle Termine als Liste oder Timeline zu kontrollieren.

Für Erinnerungen muss BackPlaner Mitteilungen senden dürfen. Die ausführlichen Erklärungen findest Du in [Kapitel 7](#7-backanleitung-und-reminder), [Kapitel 10](#10-geplante-schritte-liste-und-timeline) und [Kapitel 17](#17-häufige-fragen-und-fehlerbehebung).

---

## 2. Systemvoraussetzungen

| Punkt | Wert |
|-------|------|
| Geräte | iPhone und iPad |
| Betriebssystem | iOS/iPadOS 18.6 oder neuer |
| Ausrichtung | iPhone: Hoch- und Querformat · iPad: alle Ausrichtungen |
| Sprachen | Deutsch, Englisch, Französisch (umschaltbar in den Einstellungen) |
| Darstellung | Hell- und Dunkelmodus, Dynamische Schriftgrößen |
| Internet | Für die öffentliche Rezept-Datenbank und die iCloud-Synchronisierung. Eigene Rezepte, Planung und Erinnerungen funktionieren auch vollständig offline; Änderungen werden später abgeglichen. |
| iCloud | Eigene Rezepte, geplante Schritte, Einkaufslisten und Backhistorien werden über iCloud zwischen allen Geräten mit demselben Apple-Account synchronisiert, sofern iCloud aktiviert ist. Die Erinnerungen selbst sind pro Gerät lokal. |
| Berechtigungen | Mitteilungen (für Erinnerungen), Fotomediathek und Kamera (für Rezeptbilder) |

Die App fragt die Erlaubnis für Mitteilungen beim ersten Start ab. Ohne diese Erlaubnis werden Backschritte weiterhin berechnet und in der Liste „Geplante Schritte“ angezeigt, es erscheinen aber **keine Erinnerungen**.

---

## 3. Grundbegriffe

Diese fünf Begriffe tauchen überall in der App auf:

**Rezept**
Die oberste Einheit: Name, Beschreibung, Bild, Bewertung, Tags, optionaler Link zur Quelle, Gesamtgewicht und Bearbeitungsdauer.

**Komponente**
Ein Teilansatz innerhalb eines Rezepts – zum Beispiel „Sauerteig“, „Vorteig“, „Hauptteig“, „Brühstück“. Jede Komponente hat eine Nummer (Sortierreihenfolge) und ihre eigene Zutatenliste. Das ist der Kern des Datenmodells: BackPlaner ist für mehrstufige Teigführungen gebaut.

**Zutat**
Gehört immer zu einer Komponente. Besteht aus Nummer, Menge, Einheit, Name und optional einem Bruch (Zähler/Nenner, in der App als **Z / N** bezeichnet).

**Verarbeitungsschritt**
Eine Arbeitsanweisung mit Schrittnummer und Dauer in Minuten. Die Schrittnummer ist eine Dezimalzahl und hat eine besondere Bedeutung:

- **Ganze Zahlen (1, 2, 3 …) sind Hauptschritte.** Sie laufen zeitlich nacheinander.
- **Nachkommastellen (2.1, 2.2, 2.3) sind Parallelschritte innerhalb eines Hauptschritts.** Sie starten alle zur selben Zeit; für die Gesamtdauer zählt nur die *längste* Dauer der Gruppe.

Beispiel: Wenn Du Sauerteig (12 h) und Brühstück (2 h) gleichzeitig ansetzt, gib beiden Schritt 1.1 und 1.2. Der nächste Hauptschritt 2 beginnt nach 12 Stunden, nicht nach 14.

**Portionsgröße**
Ein Skalierungsfaktor für alle Mengen: 0,5 / 1,0 / 1,5 / 2,0. **1,0 entspricht dem Rezept, wie es gespeichert ist.** 2,0 verdoppelt alle Mengen und das angezeigte Gesamtgewicht.

---

## 4. Das Hauptmenü

Nach dem Start erscheint das Hauptmenü mit acht Karten:

| Karte | Zweck |
|-------|-------|
| **Rezept-Datenbank** | Öffentliche, von allen Nutzern geteilte Rezepte durchsuchen |
| **Eigene Rezepte** | Deine lokal gespeicherten Rezepte |
| **Neues Rezept anlegen** | Rezept von Grund auf erstellen oder aus Fotos importieren |
| **Geplante Schritte** | Alle terminierten Backschritte als Liste oder Timeline |
| **Backhistorie** | Vergangene Backvorgänge mit Kommentaren und Fotos |
| **Back Hit-Liste** | Rezepte, sortiert nach Anzahl der Backvorgänge |
| **Einkaufsliste** | Alle angelegten Einkaufslisten |
| **Einstellungen** | Sprache, Standardwerte, Backplanung, Administrator |

Mit dem Zurück-Pfeil oben links kommst Du aus jedem Bereich wieder ins Hauptmenü.

---

## 5. Rezept-Datenbank (öffentliche Rezepte)

Die Rezept-Datenbank ist die gemeinsame Sammlung: Rezepte, die Du oder andere Nutzer öffentlich gespeichert haben.

### Suchen und filtern

- **Suchfeld** oben: durchsucht Rezeptnamen.
- **Suchbereich umschalten**: Unter dem Suchfeld kannst Du zwischen **Name** und **Tags** wählen. Bei „Tags“ wird in den Schlagworten gesucht (z. B. „Roggen“, „Vollkorn“, „Sauerteig“).
- **Nach unten ziehen** aktualisiert die Liste aus der Cloud.

Steht „Keine Rezepte geladen“, bestand beim Start keine Internetverbindung – zieh die Liste einmal nach unten.

### Ein öffentliches Rezept öffnen

Ein Rezept öffnet sich mit zwei Tabs am unteren Rand:

- **Rezept backen** – die Backanleitung mit Zeitplanung (siehe [Kapitel 7](#7-backanleitung-und-reminder))
- **Details** – Übersicht über Zutaten, Komponenten und Schritte

### Rezept übersetzen

Oben rechts findest Du das **Globus-Symbol**. Darüber wählst Du Deutsch, English oder Français. Die Übersetzung läuft **vollständig auf dem Gerät** (Apple Übersetzung) und betrifft Rezeptname, Beschreibung, Tags, Komponenten-, Zutatennamen und Schritttexte.

Hinweise:

- **Einheiten werden absichtlich nicht übersetzt**, damit die Mengenberechnung weiter funktioniert.
- Die erste Übersetzung einer Sprache dauert einen Moment (Fortschrittsanzeige statt Globus). Danach ist sie zwischengespeichert und sofort verfügbar.
- Beim ersten Öffnen zeigt die App das Rezept automatisch in Deiner Sprache, wenn dafür schon eine Übersetzung vorliegt.
- Das deutsche Original wird nie überschrieben.

### Ein öffentliches Rezept übernehmen

Im Tab **Rezept backen** gibt es die Schaltfläche **„Als eigenes Rezept speichern“**. Damit landet eine vollständige Kopie – samt Bild, Komponenten, Zutaten und Schritten – in „Eigene Rezepte“. Erst diese Kopie kannst Du bearbeiten.

### Melden, blockieren, löschen

Über das **Menü „…“** oben rechts:

- **Rezept melden** – Du wählst einen Grund (anstößig/beleidigend, Spam, Urheberrechtsverletzung, Sonstiges). Die Meldung geht zur Prüfung an den Betreiber, und das Rezept wird auf Deinem Gerät sofort ausgeblendet.
- **Autor blockieren** – alle Rezepte dieses Autors verschwinden auf Deinem Gerät aus der Liste.
- **Mein Rezept löschen** – erscheint nur bei Rezepten, die von *diesem* Gerät hochgeladen wurden. Das Rezept wird endgültig aus der öffentlichen Datenbank entfernt.

Blockierungen und Ausblendungen gelten nur lokal auf Deinem Gerät.

### Administrator-Funktion

Bist Du als Administrator angemeldet (siehe [Kapitel 14](#14-einstellungen)), erscheint im Tab **Details** zusätzlich **„Rezept löschen (Admin)“**. Damit lässt sich jedes öffentliche Rezept entfernen – gedacht für die Moderation gemeldeter Inhalte.

---

## 6. Eigene Rezepte

Hier liegen alle Rezepte, die lokal auf dem Gerät gespeichert sind: selbst angelegte und aus der Datenbank übernommene.

### Suchen und filtern

- **Suchfeld** mit Umschaltung **Name / Tags**.
- **Filter-Symbol** oben rechts: Mindestbewertung wählen (Alle Bewertungen, 1–5 Sterne und mehr). Ist ein Filter aktiv, wird das Symbol gefüllt dargestellt.

Die Suche ignoriert Groß- und Kleinschreibung und findet auch Wortteile: „roggen“ findet „Roggenbrot“, und bei Tags genügt ein Teil des Schlagworts. Such- und Bewertungsfilter lassen sich kombinieren.

### Rezept löschen

Zeile nach links wischen → **Löschen**. Es folgt eine Sicherheitsabfrage mit dem Rezeptnamen, damit ein versehentliches Wischen kein Rezept vernichtet. Mit dem Rezept werden auch seine Komponenten, Zutaten, Verarbeitungsschritte und Backhistorien-Einträge gelöscht.

Bereits geplante Schritte dieses Rezepts bleiben allerdings in „Geplante Schritte“ stehen – lösche sie dort separat, wenn Du sie nicht mehr brauchst.

### Die fünf Tabs eines eigenen Rezepts

| Tab | Inhalt |
|-----|--------|
| **Backen** | Backanleitung mit Zeitplanung und „Reminder setzen“ |
| **Details** | Bewertung, Beschreibung, Gesamtzutaten, Komponenten, Schrittübersicht |
| **Ändern** | Rezept bearbeiten (siehe [Kapitel 9](#9-rezept-bearbeiten)) |
| **Einkaufsliste** | Zutaten dieses Rezepts auf eine Einkaufsliste setzen |
| **+ Historie** | Einen Backvorgang mit Datum, Kommentar und Fotos nachtragen |

Im Tab **Details** kannst Du das Rezeptbild antippen, um es groß anzuzeigen.

---

## 7. Backanleitung und Reminder

Das ist der Kern der App. Der Aufbau ist bei eigenen und öffentlichen Rezepten gleich.

### Von oben nach unten

1. **Bild und Name** – Bild antippen zeigt es groß.
2. **Portionsgröße** (0,5 / 1,0 / 1,5 / 2,0), das daraus berechnete **Gesamtgewicht in Gramm** und – falls hinterlegt – der **Link zum Rezept**.
3. **Gesamtzutaten** – alle Zutaten über alle Komponenten hinweg zusammengefasst. Diese Liste ist zum Einkaufen und Abwiegen gedacht. Wasser wird bewusst weggelassen, ebenso Zutaten, die selbst ein Zwischenprodukt einer Komponente sind (z. B. „Sauerteig“ als Zutat des Hauptteigs) – sonst würden Mengen doppelt zählen.
4. **Komponenten** – nach Nummer sortiert, jede mit ihren Zutaten in der gewählten Portionsgröße.
5. **Steuerleiste** – siehe unten.
6. **Verarbeitungsschritte** – Tabelle mit Schritt, Beschreibung, Dauer und berechnetem **Beginn**. Als letzte Zeile erscheint „Fertig“ mit dem Endzeitpunkt.
7. **Back-Kommentare** (nur eigene Rezepte) – frühere Backhistorien-Einträge.
8. **Reminder setzen**.

### Die Steuerleiste

| Element | Funktion |
|---------|----------|
| **Dauer ändern** | Schalter. Aktiv erscheint pro Schritt ein Eingabefeld „Dauer [Min]“. |
| **Starten ab / Fertig bis** | Legt fest, wie das Datum unten interpretiert wird. Auf dem iPhone im Hochformat abgekürzt als **Ab / Bis**. |
| **Datum und Uhrzeit** | Der Bezugszeitpunkt der Planung. |

**Starten ab** bedeutet: Ich fange zu diesem Zeitpunkt an – wann bin ich fertig?
**Fertig bis** bedeutet: Ich will zu diesem Zeitpunkt fertig sein – wann muss ich anfangen? Die Spalte „Beginn“ rechnet dann rückwärts.

Ändere den Zeitpunkt und beobachte, wie sich die Spalte „Beginn“ sofort anpasst. Es wird noch nichts gespeichert.

### Dauern anpassen

1. **Dauer ändern** einschalten.
2. In den Feldern der rechten Spalte neue Minutenwerte eintragen. Leere Felder und Werte ≤ 0 werden ignoriert, der bisherige Wert bleibt.
3. **Dauer übernehmen** tippen.

Die App berechnet daraufhin alle Startzeiten und die Gesamt-Bearbeitungsdauer neu. Bei eigenen Rezepten werden die neuen Dauern dauerhaft gespeichert; bei öffentlichen Rezepten gelten sie nur für die aktuelle Planung.

### Reminder setzen

Ein Tippen auf **Reminder setzen** löst mehrere Dinge gleichzeitig aus:

1. Für **jeden Verarbeitungsschritt** wird eine lokale Erinnerung zur berechneten Startzeit gesetzt.
2. Zusätzlich wird automatisch der Schritt **„Backofen anstellen“** eingefügt – und zwar um die eingestellte **Vorheizzeit** vor dem letzten Schritt (Standard 15 Minuten, änderbar in den Einstellungen).
3. Ebenso wird **„Backvorgang ist beendet“** zum Endzeitpunkt eingeplant.
4. Alle Schritte landen in **„Geplante Schritte“**.
5. Bei eigenen Rezepten wird ein **Backhistorien-Eintrag** mit dem Enddatum und dem Platzhalter-Kommentar „kein Kommentar erfasst“ angelegt, den Du später ergänzen kannst.

Anschließend erscheint eine Bestätigung, zum Beispiel:

> **Reminder wurden gesetzt**
> 12 Erinnerungen gesetzt.
> Backofen anstellen um 16:45 Uhr.
> Fertig um 18:10 Uhr.

Die Texte „Backofen anstellen“ und „Backvorgang ist beendet“ erscheinen in der gerade aktiven Sprache (bei öffentlichen Rezepten in der Sprache, in der Du das Rezept ansiehst).

> **Ein Rezept hat immer genau einen Plan.** Tippst Du erneut auf „Reminder setzen“ – etwa weil Du das Brot auf einen anderen Tag verschieben willst –, ersetzt der neue Plan den alten vollständig: die alten Schritte verschwinden aus „Geplante Schritte“, und die alten Erinnerungen werden durch die neuen ersetzt. Es entstehen also keine Dubletten. Umgekehrt heißt das: dasselbe Rezept lässt sich nicht zweimal parallel für zwei verschiedene Termine einplanen.

---

## 8. Neues Rezept anlegen

Über **Hauptmenü → Neues Rezept anlegen**. Das Formular ist von oben nach unten aufgebaut.

### Rezept aus Bildern importieren

Ganz oben: **„Rezept aus Bildern importieren“**. Damit lässt sich ein gedrucktes oder abfotografiertes Rezept einlesen.

1. **Bilder auswählen** (bis zu 10 Seiten, die Reihenfolge der Auswahl wird übernommen) oder **Aufnehmen** für ein neues Foto.
2. Die gewählten Seiten erscheinen als Liste „Ausgewählte Seiten“; einzelne lassen sich über das Papierkorb-Symbol entfernen.
3. **„… Bild(er) analysieren“** startet die Texterkennung. Sie läuft auf dem Gerät, zeigt „Bild x von y wird gelesen …“ und kann jederzeit abgebrochen werden.
4. Danach zeigt die App eine **Zusammenfassung**: erkannter Name, Anzahl Komponenten, Zutaten und Arbeitsschritte, dazu die erkannten Komponenten mit Zutaten sowie die erkannte Zeitplanung.
5. **„Daten im Rezeptformular prüfen“** übernimmt alles ins normale Rezeptformular. **„Andere Bilder auswählen“** startet neu.

Die Erkennung ist auf ein **zweispaltiges Rezeptlayout mit Planungsbeispiel** ausgelegt und liefert bei geraden, gut lesbaren Fotos die besten Ergebnisse. Prüfe anschließend unbedingt **Mengen, Einheiten, Temperaturen und Zeiten** – gespeichert wird erst, wenn Du im Formular „Rezept speichern“ wählst.

### Ablage: privat oder öffentlich

Im Abschnitt **Speichern** wählst Du zwischen **Privat** und **Öffentlich**. Die Vorbelegung kommt aus den Einstellungen (Standard-Ablage).

- **Privat** – das Rezept bleibt auf dem Gerät und ist jederzeit änderbar.
- **Öffentlich** – das Rezept wird in die gemeinsame Datenbank hochgeladen. Vorher erscheint der Hinweis: **„Ein öffentliches Rezept kann nach dem Speichern nicht mehr geändert werden.“** Beim ersten Mal musst Du außerdem die Nutzungsbedingungen akzeptieren (siehe [Kapitel 16](#16-datenschutz-moderation-und-nutzungsbedingungen)).

Beim Import aus Bildern ist die Ablage zunächst immer auf „Privat“ gesetzt.

### Rezeptbild

**Fotomediathek** oder **Kamera** (Kamera-Schaltfläche nur auf Geräten mit Kamera).

> **Ein Bild ist Pflicht.** Ohne Rezeptbild erscheint beim Speichern die Meldung „Bild erforderlich“.

### Stammdaten und Tags

- **Name** – Pflichtfeld. Solange er leer ist, bleibt „Rezept speichern“ deaktiviert.
- **Beschreibung** – mehrzeiliges Textfeld.
- **Url Link** – optionaler Link zur Quelle, erscheint später als „Link zum Rezept“.
- **Tags** – Schlagwort eintippen, **+** tippen. Tags sind später durchsuchbar.

### Komponenten und Zutaten

Erst die Komponente, dann ihre Zutaten:

1. Nummer und Namen der Komponente eingeben (z. B. `1` / `Sauerteig`), **+** tippen. Die Nummer zählt automatisch hoch.
2. Unter jeder Komponente erscheint die Zutaten-Eingabezeile mit den Spalten:

| Spalte | Bedeutung |
|--------|-----------|
| **Nr.** | Sortierreihenfolge innerhalb der Komponente |
| **Menge / Gewicht** | Zahlenwert der Menge |
| **Einheit** | Auswahlmenü, siehe [Kapitel 15](#15-einheiten-mengen-und-portionsgrößen) |
| **Zutat** | Name der Zutat |
| **Z / N** | Bruchangabe – Zähler und Nenner, z. B. 1 / 2 für „½“ |

3. **+** fügt die Zutat hinzu, das Papierkorb-Symbol entfernt sie wieder. Bereits eingetragene Zeilen sind direkt editierbar.

Nur der **Name** ist zwingend – eine Zutat ohne Menge und Einheit ist erlaubt (etwa „Salz nach Geschmack“). Nutze entweder Menge/Gewicht **oder** die Bruchfelder, nicht beides für dieselbe Angabe.

### Verarbeitungsschritte

Spalten **Schritt**, **Beschreibung**, **Dauer** (Minuten). Nach dem Hinzufügen zählt die Schrittnummer automatisch weiter: von einer ganzen Zahl auf die nächste ganze Zahl, von einer Nachkommazahl in 0,1-Schritten. So legst Du parallele Teilschritte bequem als 2.1, 2.2, 2.3 an.

Denk an die Regel aus [Kapitel 3](#3-grundbegriffe): Nachkommaschritte laufen parallel, ganze Zahlen nacheinander.

### Speichern

- **Rezept speichern** – speichert privat bzw. lädt öffentlich hoch. Beim Upload erscheint „Rezept wird hochgeladen …“; danach entweder „Rezept wurde gespeichert“ oder eine konkrete Fehlermeldung.
- **Inhalte löschen** – leert das Formular komplett (ohne Rückfrage).

---

## 9. Rezept bearbeiten

Erreichbar über **Eigene Rezepte → Rezept → Tab „Ändern“**.

### Automatisches Speichern

Änderungen an **Name, Beschreibung, Url Link, Tags und Bewertung** werden automatisch gespeichert – kurz nach dem Tippen und spätestens beim Verlassen des Bildschirms. Es gibt dafür keine Bestätigungsmeldung.

Ein neues **Rezeptbild** wird sofort beim Auswählen gespeichert.

### Bewertung

Rechts oben die Sterne antippen: 1 bis 5 Sterne. Nochmaliges Tippen auf den ersten Stern setzt die Bewertung auf 0 zurück. Die Bewertung ist die Grundlage für den Bewertungsfilter in den Listen.

### Komponenten ändern

- **Hinzufügen**: Nummer und Name eingeben, **+**.
- **Bearbeiten**: Komponentenzeile antippen. Es öffnet sich „Komponente ändern“ mit Nummer, Name und der vollständigen Zutatenliste. Dort kannst Du Zutaten hinzufügen (**+**), löschen (Papierkorb) und durch Antippen einer Zutat im Dialog „Zutat ändern“ bearbeiten. Mit **Fertig** übernehmen, mit **Abbrechen** verwerfen.
- **Löschen**: Papierkorb neben der Komponente. Das Gesamtgewicht des Rezepts wird danach neu berechnet.

### Verarbeitungsschritte ändern

- **Hinzufügen**: Schritt, Beschreibung, Dauer eingeben, **+**. Startzeiten werden automatisch neu berechnet.
- **Bearbeiten**: Schrittzeile antippen → „Verarbeitungsschritt ändern“. Nach **Fertig** rechnet die App alle Startzeiten und die Bearbeitungsdauer neu.
- **Löschen**: Papierkorb neben der Zeile.

### Manuell speichern

- **Privat speichern** – speichert alles inklusive Bild, berechnet das Gesamtgewicht neu und bestätigt mit „Rezept wurde gespeichert“.
- **Öffentlich speichern** – lädt das Rezept in die gemeinsame Datenbank. Der Hinweis, dass ein öffentliches Rezept danach nicht mehr geändert werden kann, erscheint auch hier. Nach erfolgreichem Upload ist die Schaltfläche deaktiviert, weil das Rezept jetzt eine öffentliche Kopie besitzt.
- **Löschen** (oben links) – leert die Rezeptinhalte.

Wurde die öffentliche Kopie später gelöscht (durch Dich oder die Moderation), erkennt die App das beim nächsten Öffnen und macht „Öffentlich speichern“ wieder verfügbar.

---

## 10. Geplante Schritte (Liste und Timeline)

**Hauptmenü → Geplante Schritte.** Hier stehen alle Backschritte aus allen Rezepten, für die Du Reminder gesetzt hast – chronologisch, rezeptübergreifend. Unten wechselst Du zwischen zwei Ansichten.

### Ansicht „Geplante Schritte“ (Liste)

Jeder Schritt ist eine Karte mit Rezeptbild, Rezeptname, Startzeit, Datum, Dauer und Anweisung. Antippen öffnet die Detailansicht mit Rezept, Beginn, Schrittnummer, Dauer und vollständiger Beschreibung.

**Einen Schritt zeitlich verschieben** – über das Uhr-Symbol auf der Karte:

1. Minuten eingeben (maximal 1440, also 24 Stunden).
2. Richtung wählen: **Früher** oder **Später**.
3. Umfang wählen: **Nur dieser Schritt** oder **Alle nachfolgenden** (alle späteren Schritte desselben Rezepts wandern um denselben Betrag mit).
4. **Übernehmen**.

Die zugehörigen Erinnerungen werden automatisch mitverschoben. Liegt der neue Zeitpunkt in der Vergangenheit, lehnt die App das mit „Verschieben nicht möglich“ ab.

**Löschen:**

- **Einzelner Schritt**: Zeile nach links wischen. Die zugehörige Erinnerung wird mit entfernt.
- **Alle Schritte**: Papierkorb-Schaltfläche unten rechts, dann „Alle löschen“. Das entfernt alle geplanten Schritte **und** alle anstehenden Erinnerungen – auch die von Rezepten, die Du nicht mehr backen willst.

### Ansicht „Timeline“

Dieselben Schritte als senkrechte Zeitachse. Links steht der Zeitstempel – beim ersten Schritt eines Tages mit Wochentag und Datum, bei den folgenden nur die Uhrzeit. Punkte und Verbindungslinien machen sichtbar, welche Schritte zusammen an einem Tag liegen und wo größere Pausen sind. Praktisch für den Überblick über eine mehrtägige Teigführung.

Sind keine Schritte geplant, steht in beiden Ansichten: „Keine geplanten Schritte – Setze einen Reminder in der Backanleitung eines Rezepts.“

---

## 11. Erinnerungen auf dem Sperrbildschirm

Jede Erinnerung erscheint als Mitteilung mit dem Titel **„Backhinweis“**, dem Untertitel „Gedrückt halten für Erledigt oder Verschieben“ und dem Schritttext als Inhalt.

**Halte die Mitteilung gedrückt**, um zwei Aktionen zu erhalten:

- **Erledigt** – der Schritt wird aus „Geplante Schritte“ entfernt.
- **Verschieben um …** – gib die Minuten direkt in der Mitteilung ein. Danach folgt eine Rückfrage: **„Sollen alle nachfolgenden Schritte dieses Rezepts ebenfalls verschoben werden?“** mit den Optionen **Nur diesen Schritt** und **Alle nachfolgenden**.

Beim Verschieben wird immer ab **jetzt** gerechnet: „30 Minuten“ heißt „in 30 Minuten von jetzt an“. Bei „Alle nachfolgenden“ wandern alle späteren Schritte desselben Rezepts um dieselbe Differenz mit – so bleibt eine Teigführung in sich schlüssig, auch wenn Du mal später dran bist.

Mitteilungen werden auch angezeigt, während die App im Vordergrund läuft.

---

## 12. Backhistorie und Back Hit-Liste

### Backhistorie

**Hauptmenü → Backhistorie.** Eine chronologische Liste aller Backvorgänge (neueste zuerst) mit Datum, Rezeptname, Kommentar und Fotos.

- **Eintrag antippen** → „Backanmerkungen- / hinweise“: Kommentar bearbeiten und über **Fotomediathek** Fotos hinzufügen. Fotos lassen sich antippen und groß durchblättern. **Speichern** bestätigt mit „Historie wurde gespeichert“.
- **Eintrag löschen**: Zeile nach links wischen.
- **Suchen und filtern**: Suchfeld (Name/Tags) und Bewertungsfilter oben rechts.

### Einen Backvorgang nachtragen

**Eigene Rezepte → Rezept → Tab „+ Historie“.** Backdatum wählen (bis zu 10 Jahre zurück), Kommentar schreiben, Fotos aus der Mediathek hinzufügen, **Speichern**.

Ein Eintrag entsteht außerdem automatisch, wenn Du in der Backanleitung Reminder setzt – zunächst mit dem Platzhalter „kein Kommentar erfasst“, den Du später ersetzen kannst.

### Back Hit-Liste

**Hauptmenü → Back Hit-Liste.** Zeigt alle Rezepte, die schon einmal gebacken wurden, sortiert nach der Anzahl der Backvorgänge – oben Deine Klassiker. Je Rezept erscheinen Name, Anzahl und die Fotos aus den Backhistorien. Suche und Bewertungsfilter funktionieren wie in den anderen Listen.

---

## 13. Einkaufsliste

### Zutaten auf eine Liste setzen

**Eigene Rezepte → Rezept → Tab „Einkaufsliste“.**

- **Neue Liste**: Datum wählen, **Erstellen**. Existiert für dieses Datum schon eine Liste, werden die Zutaten dort ergänzt.
- **Bestehende Liste**: umschalten auf „Bestehende Liste“ und bei der gewünschten Liste **+** tippen. Zum Löschen die Zeile nach links wischen.

Bestätigt wird mit „Zutaten wurden auf die Einkaufsliste gesetzt“. Anschließend erscheint der Verweis **„Einkaufslisten anzeigen“**.

### Was auf die Liste kommt – und was nicht

Die App filtert bewusst:

- **Nicht aufgenommen** werden Zutaten, deren Name **Wasser, Salz, Anstellgut** oder **Sauerteig** enthält – das hat man im Haus bzw. es ist ein Zwischenprodukt.
- **Nicht aufgenommen** werden Zutaten ohne Einheit oder ohne verwertbare Menge.
- **Gleiche Zutaten werden zusammengefasst.** Dabei werden Temperaturangaben aus dem Namen entfernt: „Wasser (lauwarm)“, „Milch 30 °C“ und „Milch“ gelten als dieselbe Zutat. Groß-/Kleinschreibung und Umlaute spielen keine Rolle.
- **Einheiten werden umgerechnet**, wenn sie dieselbe Basiseinheit haben: 0,5 kg + 200 g werden zusammengerechnet, EL und ml ebenfalls. g und ml bleiben getrennt.

### Einkaufslisten ansehen

**Hauptmenü → Einkaufsliste.** Je Liste stehen das Datum („Einkaufsliste vom …“), die enthaltenen Rezepte und darunter alle Zutaten mit Menge und Einheit. **Löschen** entfernt die Liste nach Rückfrage.

---

## 14. Einstellungen

**Hauptmenü → Einstellungen.**

### Allgemein

| Einstellung | Beschreibung |
|-------------|--------------|
| **Sprache** | Systemsprache, Deutsch, Englisch oder Französisch. Wirkt auf die Oberfläche sowie auf Datums- und Zeitformate. |
| **Standard-Ablage** | Vorbelegung für neue Rezepte: **Privat** oder **Öffentlich**. Standard: Privat. |

### Rezepte

| Einstellung | Beschreibung |
|-------------|--------------|
| **Standard-Portionsgröße** | Wert, mit dem Rezepte geöffnet werden: 0,5 / 1,0 / 1,5 / 2,0. Standard: 1,0. |
| **Detailansicht verwenden** | Ein: Komponenten und Schritte aller öffentlichen Rezepte werden schon beim Laden der Liste mitgeladen – Rezepte öffnen sich schneller, der erste Ladevorgang dauert länger und braucht mehr Daten. Aus: Details werden erst beim Öffnen eines Rezepts geladen. Standard: ein. |

### Backplanung

| Einstellung | Beschreibung |
|-------------|--------------|
| **Vorheizzeit** | 0–120 Minuten in 5er-Schritten. Wird beim Setzen der Reminder verwendet, um den automatischen Schritt „Backofen anstellen“ vor den letzten Schritt zu legen. Standard: 15 Minuten. |
| **Backpause** | 0–120 Minuten. Standard: 10 Minuten. |
| **Tagesbeginn** | 0–23 Uhr. Standard: 6 Uhr. |
| **Tagesende** | Zwischen Tagesbeginn und 23 Uhr. Standard: 23 Uhr. |

> **Hinweis:** Von diesen vier Werten beeinflusst derzeit nur die **Vorheizzeit** die Berechnung. **Backpause, Tagesbeginn und Tagesende** werden gespeichert, aber noch nicht in die Zeitplanung einbezogen.

### Administrator

Für Moderatoren: **Mit Apple anmelden** erzeugt eine dauerhafte Kennung, die für Moderationsrechte freigeschaltet werden kann. Ist die Anmeldung erfolgreich und die Kennung freigeschaltet, erscheint in öffentlichen Rezepten die Schaltfläche „Rezept löschen (Admin)“. **Abmelden** kehrt zur normalen, anonymen Nutzung zurück.

Diese Funktion ist für den Betreiber der Rezept-Datenbank gedacht. Für das normale Backen ist keinerlei Anmeldung erforderlich.

---

## 15. Einheiten, Mengen und Portionsgrößen

### Verfügbare Einheiten

Die Einheit wählst Du über ein Auswahlmenü (Kurzform – Langform). Freitext ist möglich, wird aber rot umrandet, wenn er zu keiner bekannten Einheit passt – dann kann die App nicht umrechnen.

**Gewichtsbasiert (Basis Gramm)**

| Kurz | Einheit | entspricht |
|------|---------|-----------|
| g | Gramm | 1 g |
| kg | Kilogramm | 1000 g |
| mg | Milligramm | 0,001 g |
| pfd | Pfund | 500 g |
| Pr | Prise | 1 g |
| Msp | Messerspitze | 0,05 g |
| Bd | Bund | 10 g |
| Sc | Scheibe | 25 g |
| ei | Ei | 50 g |
| ei(s) / ei(m) / ei(l) / ei(xl) | Ei (S/M/L/XL) | 50 / 60 / 70 / 80 g |

**Volumenbasiert (Basis Milliliter)**

| Kurz | Einheit | entspricht |
|------|---------|-----------|
| ml | Milliliter | 1 ml |
| cl | Zentiliter | 10 ml |
| dl | Deziliter | 100 ml |
| l | Liter | 1000 ml |
| mass | Mass | 1000 ml |
| TL | Teelöffel | 5 ml |
| EL | Esslöffel | 15 ml |
| Tas | Tasse | 200 ml |
| Ss | Schuss | 10 ml |
| Sp | Spritzer | 0,27 ml |
| Tr | Tropfen | 0,067 ml |

### Umrechnung in Gewicht

Für das **Gesamtgewicht** des Rezepts rechnet die App Volumenangaben in Gramm um und berücksichtigt dabei die Dichte gängiger Backzutaten – zum Beispiel Mehl 0,66, Wasser 1,0, Öl 0,8, Honig 1,3, Zucker 1,0, Puderzucker 0,6, Butter 1,0, Kakao 0,6, Stärke 0,6, Nüsse und Mandeln 0,5, Grieß 0,5, Milch 1,0, Saft 1,0, Konfitüre 1,33. Der Faktor wird über den Zutatennamen erkannt: „Weizenmehl 550“ wird als Mehl behandelt.

Eine Tasse Mehl wird also als 200 ml × 0,66 = 132 g gewertet, eine Tasse Wasser als 200 g.

### Brüche (Z / N)

Für Angaben wie „½ Ei“ oder „¾ Würfel Hefe“ nutze die Felder **Z** (Zähler) und **N** (Nenner). Die App skaliert Brüche mit der Portionsgröße und kürzt sie automatisch; aus 2/2 wird 1, und der Rest wird als Bruch dargestellt („1 1/2“).

### Skalierung

Die Portionsgröße wirkt auf Gesamtzutaten, Komponenten-Zutatenlisten und das angezeigte Gesamtgewicht. Sie wirkt **nicht** auf Dauern – Teige gehen nicht schneller auf, nur weil man weniger davon macht.

**1,0 ist immer das gespeicherte Rezept.** Die Portionsgröße ist eine reine Anzeigeoption: Sie verändert das Rezept nicht.

---

## 16. Datenschutz, Moderation und Nutzungsbedingungen

### Wo Deine Daten liegen

- **Eigene Rezepte, geplante Schritte, Einkaufslisten und Backhistorien** liegen auf dem Gerät und in Deiner privaten iCloud-Datenbank. Sie sind nur für Dich und Deine eigenen Geräte sichtbar, nicht für andere Nutzer der App.
- **Öffentliche Rezepte** liegen in der gemeinsamen Cloud-Datenbank und sind für alle Nutzer der App sichtbar.
- **Übersetzungen** entstehen auf dem Gerät.
- Die App verwendet eine anonyme Kennung, damit Du eigene öffentliche Rezepte löschen kannst und andere Nutzer Autoren blockieren können. Ein Benutzerkonto ist nicht erforderlich; ein Login gibt es nur für Administratoren.

### Nutzungsbedingungen für öffentliche Rezepte

Bevor Du zum ersten Mal ein Rezept öffentlich speicherst, musst Du die Bedingungen akzeptieren. Kern:

- Ein öffentlich geteiltes Rezept ist für alle Nutzer der Rezept-Datenbank sichtbar.
- Es gilt **Null-Toleranz** gegenüber anstößigen, beleidigenden, rechtswidrigen oder urheberrechtsverletzenden Inhalten.
- Du bist allein verantwortlich für die von Dir geteilten Inhalte.
- Gemeldete Inhalte werden geprüft und **innerhalb von 24 Stunden** entfernt.
- Autoren, die wiederholt verstoßen, können ausgeschlossen werden.

Mit **Ablehnen** wird nichts hochgeladen; das Rezept bleibt im Formular und kann privat gespeichert werden.

### Was Du gegen unerwünschte Inhalte tun kannst

Über das Menü „…“ in einem öffentlichen Rezept: **Rezept melden** (mit Grund) oder **Autor blockieren**. Beides wirkt sofort auf Deinem Gerät. Details in [Kapitel 5](#5-rezept-datenbank-öffentliche-rezepte).

---

## 17. Häufige Fragen und Fehlerbehebung

**Es kommen keine Erinnerungen.**
Prüfe in *Einstellungen → Mitteilungen → BackPlaner*, ob Mitteilungen erlaubt sind. Prüfe außerdem, ob unter „Geplante Schritte“ überhaupt Schritte stehen – nur ein Tippen auf „Reminder setzen“ erzeugt Erinnerungen. Und: Erinnerungen für Zeitpunkte in der Vergangenheit werden nicht ausgelöst.

**Die Rezept-Datenbank ist leer („Keine Rezepte geladen“).**
Beim Start bestand keine Internetverbindung. Zieh die Liste nach unten, um erneut zu laden.

**Ich habe mein öffentliches Rezept hochgeladen und will es korrigieren.**
Das ist nicht möglich – öffentliche Rezepte sind unveränderlich. Lösche es über „…“ → **Mein Rezept löschen** und lade die korrigierte Fassung neu hoch. Die private Fassung bleibt dabei erhalten und wird danach wieder als „öffentlich speicherbar“ erkannt.

**Ich habe versehentlich zweimal „Reminder setzen“ getippt.**
Das ist unproblematisch: der zweite Plan ersetzt den ersten, Schritte und Erinnerungen bleiben eindeutig. Willst Du die Planung ganz zurücknehmen, lösche die Schritte des Rezepts in „Geplante Schritte“ (nach links wischen).

**Ich will dasselbe Rezept für zwei verschiedene Termine einplanen.**
Das geht nicht – jedes Rezept hat einen Plan, der zweite ersetzt den ersten. Als Umweg kannst Du das Rezept unter einem anderen Namen duplizieren (öffentlich speichern und über „Als eigenes Rezept speichern“ zurückholen, dann umbenennen) und beide getrennt planen.

**Das Gesamtgewicht passt nicht.**
Meist liegt es an einer Einheit, die die App nicht kennt (im Einheitenfeld rot umrandet) oder an einer Zutat ohne Einheit. Prüfe die Zutaten im Tab „Ändern“ und wähle die Einheit aus dem Menü.

**Eine Zutat fehlt auf der Einkaufsliste.**
Wasser, Salz, Anstellgut und Sauerteig werden absichtlich weggelassen, ebenso Zutaten ohne Einheit oder ohne Menge. Siehe [Kapitel 13](#13-einkaufsliste).

**Eine Zutat fehlt in den „Gesamtzutaten“.**
Wasser wird dort nicht aufgeführt; ebenso Zutaten, die selbst das Erzeugnis einer Komponente sind (z. B. „Sauerteig“ als Zutat im Hauptteig), damit Mengen nicht doppelt zählen. In der Komponentenliste darunter stehen sie vollständig.

**Ein Schritt beginnt zu einem unplausiblen Zeitpunkt.**
Prüfe die Schrittnummern: Nachkommaschritte (2.1, 2.2) laufen parallel, ganze Zahlen nacheinander. Ein versehentliches „3“ statt „2.2“ verlängert die Gesamtdauer erheblich.

**Der Import aus Bildern erkennt kaum etwas.**
Fotografiere gerade, gut ausgeleuchtet, eine Seite pro Bild und ohne starke Schatten. Die Erkennung ist auf ein zweispaltiges Layout mit Planungsbeispiel optimiert. Bei ungeeigneter Vorlage ist das manuelle Anlegen schneller.

**Die Übersetzung schlägt fehl.**
Die Übersetzung nutzt Apples On-Device-Übersetzung. Beim ersten Mal muss iOS das Sprachpaket bereitstellen – dafür kann eine Internetverbindung nötig sein. Versuche es später erneut oder wechsle zurück zur Originalsprache.

---

## 18. Bekannte Einschränkungen

- **Öffentliche Rezepte sind nach dem Hochladen unveränderlich.** Korrekturen erfordern Löschen und erneutes Hochladen.
- **Backpause, Tagesbeginn und Tagesende** aus den Einstellungen werden gespeichert, wirken aber noch nicht auf die Zeitplanung.
- **Ein Rezept kann nur einen Plan haben.** Erneutes „Reminder setzen“ ersetzt den vorherigen Plan; zwei Termine für dasselbe Rezept gleichzeitig sind nicht möglich.
- **Änderst Du ein Rezept nach dem Planen** (Schritte, Dauern), bleibt der bereits gesetzte Plan unverändert stehen – geplante Schritte sind eine Momentaufnahme. Setz die Reminder neu, damit die Änderung wirkt.
- Die Zuordnung von geplanten Schritten zu Rezepten erfolgt über den **Rezeptnamen**. Zwei eigene Rezepte mit identischem oder stark ähnlichem Namen können bei Bild und Verschieben durcheinandergeraten – vergib eindeutige Namen.
- **Der Import aus Bildern** ist auf ein zweispaltiges Rezeptlayout mit Planungsbeispiel ausgelegt; andere Layouts liefern unvollständige Ergebnisse.
- **Übersetzt werden Texte, keine Einheiten** – das ist beabsichtigt, damit die Mengenberechnung erhalten bleibt.
- **Es gibt keinen Export.** Eigene Rezepte synchronisieren zwar über iCloud (siehe [Kapitel 2](#2-systemvoraussetzungen)), lassen sich aber nicht als Datei sichern oder an andere weitergeben – dafür bleibt nur der Weg über „öffentlich speichern“.
- **Blockierte Autoren und gemeldete Rezepte** werden nur auf dem jeweiligen Gerät ausgeblendet.
