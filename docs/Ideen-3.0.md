# Ideen für BakePlanner 3.0

Sammlung vom 03.11.2026, entstanden nach der Vorbereitung von 2.2 für App Store und Google Play. Nichts davon ist beschlossen; die Liste hält fest, was besprochen wurde, und schlägt einen Schnitt zwischen 3.0 und den 2.x-Versionen vor. Wer eine Richtung aufgreift, schreibt den Plan mit Schritten und offenen Entscheidungen in `docs/Android-Bestandsaufnahme.md` oder in ein eigenes Dokument und streicht den Punkt hier.

## Ausgangslage

- iPhone und Android haben seit 2.2 dieselbe Struktur (Tab-Leiste, Rezept als eine Seite, Backanleitung als Blatt) und teilen Logik und Datenmodelle im Paket `BakePlannerCore`.
- Private Daten liegen auf dem iPhone in iCloud (Core Data mit CloudKit), auf Android lokal in SQLite. Der Wechsel zwischen den Plattformen geht über die Sicherungsdatei (`RecipeExportData`, Formatversion 2).
- Öffentliche Rezepte, App Check und die Cloud-KI laufen für beide über Firebase (Projekt `back-planer`).
- Pro ist auf dem iPhone über StoreKit angelegt, aber über `config/monetization` auf „frei“ geschaltet; Android erscheint mit allen Funktionen frei. Play Billing wartet auf den gemeinsamen Umstieg (siehe `docs/Android-Play-Release.md`, Abschnitt 5).

## Das große Thema: ein Konto, beide Plattformen

**Ausgearbeitet am 04.11.2026 in `docs/Konto-und-Abgleich.md`** (Ist-Stand aus dem Code, Zielbild, Schritte K0–K11, Kostenschätzung, offene Entscheidungen). Kurzfassung: iCloud bleibt der Speicher des iPhones, Firebase wird der Kanal zwischen den Plattformen; ein `SyncEngine` im Paket arbeitet gegen die vorhandenen Speicher-Protokolle; private Dokumente unter `users/{uid}`, Fotos in Storage; Anmeldung mit Apple und Google; Pro-Anspruch als Custom Claim. Pläne bleiben in 3.0 gerätegebunden. Die erste Voraussetzung fehlt noch: gerätestabile UUIDs in beiden Speichern.

Dazu passt **Pro auf beiden Plattformen**: StoreKit 2 und Play Billing mit demselben Umfang (`Utilities/ProFeature.swift`), der Schalter `config/monetization` wird gemeinsam umgelegt. Der Kern (Rezepte, Plan, Erinnerungen, Backmodus, Historie, öffentliche Rezepte, Rechner) bleibt frei. Noch nicht ausgearbeitet; Schnittstelle zum Abgleich ist Schritt K7 des Plans.

## Bäcker-Funktionen, die zur Rechenstärke der App passen

- **Backtag mit mehreren Broten.** Die Zeitleiste zeigt schon mehrere Pläne, und „Zusätzlich planen“ warnt bei überlappenden Backzeiten. Der nächste Schritt: Beim Planen eines zweiten Rezepts schlägt die App selbst vor, wann es starten muss, damit die Öfen nacheinander frei werden (Backofen-Anzahl aus den Einstellungen, Vorheizzeit und Backpause bekannt). Logik in `BakePlanScheduler` bzw. im Paket, mit Tests. **Umgesetzt am 05.11.2026:** `BakePlanAdvisor.ovenFreeDates` im Paket sucht wie bei den Nachtvorschlägen den nächstfrüheren und nächstspäteren Viertelstunden-Zeitpunkt, zu dem der Backvorgang in die Öfen passt (Anzahl und Backpause aus den Einstellungen), Zeitpunkte ohne Nachtschritte zuerst; beide Apps zeigen die Vorschläge unter den Hinweisen mit „Übernehmen“.
- **Reifezeit des Anstellguts vorhersagen.** Das Fütterungstagebuch kennt Zeit bis zum Höchststand, Schwimmtest und Notizen. Mit der Raumtemperatur je Fütterung ließe sich schätzen, wann das Anstellgut heute reif ist, und der Beginn von Schritt 1 danach legen. Erst sammeln (Temperaturfeld im Tagebuch), dann rechnen. **Umgesetzt am 05.11.2026:** Raumtemperatur je Fütterung im Tagebuch beider Apps (Core Data `StarterFeedingLog.roomTemperature`, SQLite Schema 7, Sicherungsformat 4); `StarterRipeness` im Paket schätzt mit Q10 = 2,5 (ab drei Fütterungen über 4 °C Spanne aus dem Tagebuch gefittet, Median der letzten acht) die Reifezeit bei der heutigen Temperatur; angezeigt im Tagebuch als „Bei 22 °C reif nach etwa 6h 30m“. Im Planungsblatt eines Anstellguts setzt „Reifezeit als Dauer übernehmen“ die Dauer des Reifeschritts auf die Schätzung, womit Beginn und Ende der Fütterung folgen (05.11.2026).
- **Teigeinlage aus der Form.** Kastenform in Zentimetern oder Gärkörbchen-Größe eingeben, die App rechnet das Teiggewicht und skaliert das Rezept. Teiggewicht als Eingabe gibt es, die Form fehlt; Faustformeln für Kasten (Volumen × Faktor je Teigart) und runde Körbchen. **Umgesetzt am 05.11.2026:** Rechner „Teigeinlage aus der Form“ in beiden Apps (`DoughWeightFromTin` im Paket): Kastenform und runde Form über Innenmaße und Füllfaktor je Teigart, Gärkörbchen rund und oval über die Nennwerte der Anbieter mit linearer Zwischenrechnung; auf dem iPhone öffnet „Rezept auf dieses Gewicht skalieren“ ein Rezept mit der Teigeinlage als Zielgewicht.
- **Rezept-Varianten mit Verlauf.** Angepasste Kopien entstehen heute beim Mehltausch und bei der Anstellgut-TA. Varianten werden an ihr Ursprungsrezept gehängt, mit „was ist anders“ und dem Backergebnis je Variante aus der Historie. **In Arbeit seit 04.11.2026** (beschlossen: gespeicherter Ursprungsverweis mit Notiz, dazu eine Bewertung je Backvorgang): Teil 1, die Unterschiedsberechnung `RecipeDifference`, liegt im Paket (Schritt 23a in `docs/Android-Bestandsaufnahme.md`); Teil 2, das Datenmodell mit Ursprungsverweis, Notiz, Bewertung je Backvorgang und Formatversion 3, ist Schritt 23b; Teil 3, die Oberfläche auf beiden Plattformen (Karte „Varianten“, Zeile „Variante von“, Vergleichsblatt, „Variante anlegen“, Sterne je Backvorgang, Listenfilter), ist Schritt 23c. Offen bleiben „Varianten im Vergleich“ als Tabelle und „Zur Hauptfassung machen“.

- **Temperaturabhängige Gare für Brote und Rückkopplung aus der Historie.** **Umgesetzt am 06.11.2026 (Schritt 27):** `ProofTiming` im Paket erkennt Vorteig-Reife, Stockgare und Stückgare am Wortlaut und rechnet sie mit der Q10-Regel des Anstellguts auf die heutige Raumtemperatur um – aus dem Rezept oder aus den Backvorgängen, die Stock-/Stückgare mit Raumtemperatur gemessen haben. Beide Apps zeigen im Planungsblatt die Karte „Gare heute“: Anpassung nur für diesen Plan, und auf Wunsch die gemessenen Gärzeiten (auf 22 °C zurückgerechnet) ins Rezept.

## Vorschläge vom 06.11.2026

Gesammelt nach der Siri-Aussprache; nichts davon ist beschlossen.

- **Schritte mit Zeitfenster.** Kühlschrankgare „12 bis 18 Stunden“ oder Autolyse „30 bis 60 Minuten“ als Minimum und Maximum je Schritt; der Planer dehnt zuerst innerhalb der Fenster, bevor er den ganzen Plan verschiebt. **Umgesetzt am 06.11.2026 (Schritt 28, Teil 1 und 2, mit Freigabe für das Core-Data-Modell):** `Instruction.minDuration`/`maxDuration`, SQLite 8, Sicherungsformat 5, `DurationWindow` liest Fenster auch aus dem Wortlaut, `BakePlanAdvisor.windowSuggestion` sucht die kleinste passende Änderung; Felder im Editor beider Apps, Vorschlag in den Planungsblättern. CloudKit-Schema am selben Tag nach Production ausgerollt.
- **Vorteig-Anteil und Plausibilität.** **Umgesetzt am 06.11.2026 (Schritt 32):** „Vorfermentiertes Mehl“ und „Hinweise“ (Salz, Frisch- und Trockenhefe) in der TA-Aufschlüsselung beider Apps.
- **Ofenangaben je Schritt strukturiert.** Temperatur, fallend auf, Schwaden als Felder; „Backofen anstellen“ und die Live-Aktivität kennen die Temperatur, und die Backtag-Prüfung lässt zwei Brote bei gleicher Temperatur in denselben Ofen. **Umgesetzt am 07.11.2026 (Schritt 35, Teil 1 und 2, mit Freigabe für das Core-Data-Modell):** `OvenSettings` im Paket, Felder an `Instruction`/`InstructionFB`/Sicherungsformat 6/SQLite 9; der Plan nimmt die Felder vor dem Wortlaut, `BakeWindow.temperature` lässt gleiche Temperaturen einen Ofen teilen; Abschnitt „Ofen“ im Schritt-Editor beider Apps, Zusammenfassung unter dem Schritt auf den Rezeptseiten.
- **Echte Wecker mit AlarmKit (iOS 26).** Klingeln auch bei Stumm und Fokus. **Umgesetzt am 06.11.2026 (Schritt 29, iPhone):** Einstellung „Wecker“ mit Aus / Ofenschritte / Alle Schritte statt je Schritt; `BakeAlarmManager` gleicht die Wecker bei jeder Planänderung ab, „Erledigt“ auf dem Wecker nimmt den Schritt aus dem Plan. Offen: ein Gegenstück auf Android.
- **Kalender und Erinnerungen.** **Umgesetzt am 06.11.2026 (Schritt 33, iPhone):** Kalender-Knopf in „Geplante Schritte“, Knopf „Erinnerungen“ je Einkaufsliste.
- **Kontrollzentrum und Aktionstaste.** **Umgesetzt am 06.11.2026 (Schritt 30):** Steuerelemente „Schritt erledigt“ und „Geplante Schritte“ im Widget-Target. Offen: Watch-Komplikation mit der Uhrzeit des nächsten Schritts.
- **Rezepte in Spotlight** als indizierte App-Entitäten. **Umgesetzt am 06.11.2026 (Schritt 31).**
- **Backtag-Zettel:** PDF mit der Zeitleiste aller geplanten Rezepte des Tages. **Umgesetzt am 06.11.2026 (Schritt 34, iPhone).**

## Rezepte hinein

- ~~**Text einfügen** als dritte Importart (iPhone und Android)~~ – **umgesetzt am 04.11.2026** (Schritt 22a in `docs/Android-Bestandsaufnahme.md`): „Rezept aus Text importieren“ auf dem iPhone, „Aus Text“ auf Android, dazu geteilter Text aus dem Android-Browser. Anlass waren Seiten, die ihr Rezept erst per JavaScript nachladen (Plötzblog, 01.11.2026).
- **Texterkennung auf dem Gerät für Android** (ML Kit als eigenes Kotlin-Modul wie `BakePlannerSpeech`), damit Fotos dort ohne Cloud gelesen werden, wie auf dem iPhone mit dem Modell auf dem Gerät.

## Gemeinschaft, mit Vorsicht

Bewertungen zu öffentlichen Rezepten und ein Zähler „schon n-mal gebacken“ (aus der Historie, nur mit Zustimmung), später „Bäckern folgen“. Melden und Blockieren gibt es, Moderation ist nur für den Betreiber. Jede weitere Interaktion erzeugt Moderationsaufwand für einen Einzelentwickler: Mit Bewertungen und Zählern anfangen, Kommentare weglassen.

## Apple-Seite

- Backmodus als eigene Apple-Watch-App (Erinnerungen kommen schon auf die Uhr). **Umgesetzt (Nov. 2026):** Watch-App `BakePlannerWatch` zeigt den Plan-Schnappschuss des iPhones über Watch Connectivity, „Erledigt“ geht zurück ans iPhone; Vorlesen und Verschieben bleiben auf dem iPhone.
- Interaktive Widgets mit „Erledigt“ und „Verschieben“ direkt vom Home-Bildschirm. **Umgesetzt (Nov. 2026, #25).**
- iPad: Tastaturkürzel, mehrere Fenster, und das Überlauf-Menü der Titelleiste auf Französisch beheben (siehe `docs/AppStore-Screenshots.md`). **Umgesetzt (Nov. 2026, #24).**
- „Designed for iPad“ auf dem Mac freigeben, nachdem Kamera-Import und Teilen dort geprüft sind. **Stand Nov. 2026:** baut und startet auf dem Mac ohne Fehler; die Kamera meldet sich als verfügbar (der Kamera-Knopf erscheint). Kamera-Import und Teilen auf dem Mac am 05.11.2026 von Hand geprüft, Freigabe in App Store Connect gesetzt.

## Vorgeschlagener Schnitt

| Version | Inhalt |
|---|---|
| **2.3 …** | Text-Import; Überlauf-Menü auf dem französischen iPad; iPhone-Duo-Screenshots und neue App-Vorschauen; Texterkennung auf Android; kleine Korrekturen aus dem Play-Testtrack |
| **3.0** | Konto mit Abgleich über beide Plattformen (Plan: `docs/Konto-und-Abgleich.md`); Pro über StoreKit und Play Billing; Backtag mit mehreren Broten; Teigeinlage aus der Form |
| **später** | Reifezeit-Vorhersage; Bewertungen öffentlicher Rezepte (Rezept-Varianten, Watch-App und interaktive Widgets sind seit Nov. 2026 umgesetzt) |

Leitlinien bleiben die aus `CLAUDE.md`: kleine Schritte auf eigenen Branches, Rechenlogik nie ohne Test, beide Apps halten einander nach, und Core-Data-Modell, CloudKit-Schema, Firestore-Regeln, Cloud Functions und Sicherungsformat nicht ohne Rückfrage ändern.
