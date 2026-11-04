# Ideen für BakePlanner 3.0

Sammlung vom 03.11.2026, entstanden nach der Vorbereitung von 2.2 für App Store und Google Play. Nichts davon ist beschlossen; die Liste hält fest, was besprochen wurde, und schlägt einen Schnitt zwischen 3.0 und den 2.x-Versionen vor. Wer eine Richtung aufgreift, schreibt den Plan mit Schritten und offenen Entscheidungen in `docs/Android-Bestandsaufnahme.md` oder in ein eigenes Dokument und streicht den Punkt hier.

## Ausgangslage

- iPhone und Android haben seit 2.2 dieselbe Struktur (Tab-Leiste, Rezept als eine Seite, Backanleitung als Blatt) und teilen Logik und Datenmodelle im Paket `BakePlannerCore`.
- Private Daten liegen auf dem iPhone in iCloud (Core Data mit CloudKit), auf Android lokal in SQLite. Der Wechsel zwischen den Plattformen geht über die Sicherungsdatei (`RecipeExportData`, Formatversion 2).
- Öffentliche Rezepte, App Check und die Cloud-KI laufen für beide über Firebase (Projekt `back-planer`).
- Pro ist auf dem iPhone über StoreKit angelegt, aber über `config/monetization` auf „frei“ geschaltet; Android erscheint mit allen Funktionen frei. Play Billing wartet auf den gemeinsamen Umstieg (siehe `docs/Android-Play-Release.md`, Abschnitt 5).

## Das große Thema: ein Konto, beide Plattformen

Der Abgleich privater Daten über Firebase: Rezepte, Pläne, Backhistorie und Anstellgut-Tagebuch folgen dem Nutzer auf jedes Gerät, iPhone wie Android. Das wäre die Botschaft einer 3.0 („deine Bäckerei auf jedem Gerät“) und der Grund, warum die Datenschicht seit der Android-Portierung hinter Protokollen mit plattformneutralen Structs liegt.

Was dazugehört:

- Anmeldung mit Apple **und** Google (heute: anonym, optional mit Apple verknüpft); Kontozusammenführung, wenn ein Nutzer auf beiden Plattformen schon Daten hat.
- Private Firestore-Sammlungen je Nutzer mit Regeln (`firebase/firestore.rules`, Regel-Tests in `firebase/tests`); Fotos in Storage, verkleinert wie in der Sicherung.
- Konfliktregeln: zuletzt geschrieben gewinnt je Feld oder je Rezept; Pläne und Erinnerungen bleiben gerätegebunden oder wandern mit (Entscheidung).
- Auf dem iPhone bleibt iCloud als Speicher, Firebase wird Abgleichkanal; oder iCloud wird abgelöst (Entscheidung mit Migrationsplan, Core-Data-Modell und CloudKit-Schema nicht ohne Rückfrage ändern).
- Offline-Fähigkeit: Firestore-Cache genügt für Lesen und Schreiben, Fotos brauchen eine Warteschlange.
- Kosten: Firestore-Lesevorgänge und Storage je Nutzer abschätzen; der Abgleich wäre ein Pro-Merkmal.

Dazu passt **Pro auf beiden Plattformen**: StoreKit 2 und Play Billing mit demselben Umfang (`Utilities/ProFeature.swift`), der Schalter `config/monetization` wird gemeinsam umgelegt. Der Kern (Rezepte, Plan, Erinnerungen, Backmodus, Historie, öffentliche Rezepte, Rechner) bleibt frei.

## Bäcker-Funktionen, die zur Rechenstärke der App passen

- **Backtag mit mehreren Broten.** Die Zeitleiste zeigt schon mehrere Pläne, und „Zusätzlich planen“ warnt bei überlappenden Backzeiten. Der nächste Schritt: Beim Planen eines zweiten Rezepts schlägt die App selbst vor, wann es starten muss, damit die Öfen nacheinander frei werden (Backofen-Anzahl aus den Einstellungen, Vorheizzeit und Backpause bekannt). Logik in `BakePlanScheduler` bzw. im Paket, mit Tests.
- **Reifezeit des Anstellguts vorhersagen.** Das Fütterungstagebuch kennt Zeit bis zum Höchststand, Schwimmtest und Notizen. Mit der Raumtemperatur je Fütterung ließe sich schätzen, wann das Anstellgut heute reif ist, und der Beginn von Schritt 1 danach legen. Erst sammeln (Temperaturfeld im Tagebuch), dann rechnen.
- **Teigeinlage aus der Form.** Kastenform in Zentimetern oder Gärkörbchen-Größe eingeben, die App rechnet das Teiggewicht und skaliert das Rezept. Teiggewicht als Eingabe gibt es, die Form fehlt; Faustformeln für Kasten (Volumen × Faktor je Teigart) und runde Körbchen.
- **Rezept-Varianten mit Verlauf.** Angepasste Kopien entstehen heute beim Mehltausch und bei der Anstellgut-TA. Varianten könnten an ihr Ursprungsrezept gehängt werden, mit „was ist anders“ und dem Backergebnis je Variante aus der Historie.

## Rezepte hinein

- ~~**Text einfügen** als dritte Importart (iPhone und Android)~~ – **umgesetzt am 04.11.2026** (Schritt 22a in `docs/Android-Bestandsaufnahme.md`): „Rezept aus Text importieren“ auf dem iPhone, „Aus Text“ auf Android, dazu geteilter Text aus dem Android-Browser. Anlass waren Seiten, die ihr Rezept erst per JavaScript nachladen (Plötzblog, 01.11.2026).
- **Texterkennung auf dem Gerät für Android** (ML Kit als eigenes Kotlin-Modul wie `BakePlannerSpeech`), damit Fotos dort ohne Cloud gelesen werden, wie auf dem iPhone mit dem Modell auf dem Gerät.

## Gemeinschaft, mit Vorsicht

Bewertungen zu öffentlichen Rezepten und ein Zähler „schon n-mal gebacken“ (aus der Historie, nur mit Zustimmung), später „Bäckern folgen“. Melden und Blockieren gibt es, Moderation ist nur für den Betreiber. Jede weitere Interaktion erzeugt Moderationsaufwand für einen Einzelentwickler: Mit Bewertungen und Zählern anfangen, Kommentare weglassen.

## Apple-Seite

- Backmodus als eigene Apple-Watch-App (Erinnerungen kommen schon auf die Uhr).
- Interaktive Widgets mit „Erledigt“ und „Verschieben“ direkt vom Home-Bildschirm.
- iPad: Tastaturkürzel, mehrere Fenster, und das Überlauf-Menü der Titelleiste auf Französisch beheben (siehe `docs/AppStore-Screenshots.md`).
- „Designed for iPad“ auf dem Mac freigeben, nachdem Kamera-Import und Teilen dort geprüft sind.

## Vorgeschlagener Schnitt

| Version | Inhalt |
|---|---|
| **2.3 …** | Text-Import; Überlauf-Menü auf dem französischen iPad; iPhone-Duo-Screenshots und neue App-Vorschauen; Texterkennung auf Android; kleine Korrekturen aus dem Play-Testtrack |
| **3.0** | Konto mit Abgleich über beide Plattformen; Pro über StoreKit und Play Billing; Backtag mit mehreren Broten; Teigeinlage aus der Form |
| **später** | Reifezeit-Vorhersage; Rezept-Varianten mit Verlauf; Bewertungen; Watch-App; interaktive Widgets |

Leitlinien bleiben die aus `CLAUDE.md`: kleine Schritte auf eigenen Branches, Rechenlogik nie ohne Test, beide Apps halten einander nach, und Core-Data-Modell, CloudKit-Schema, Firestore-Regeln, Cloud Functions und Sicherungsformat nicht ohne Rückfrage ändern.
