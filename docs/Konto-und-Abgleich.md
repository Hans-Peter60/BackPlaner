# Ein Konto, beide Plattformen: Plan für den Abgleich privater Daten (3.0)

Stand 04.11.2026. Ausgearbeitet aus `docs/Ideen-3.0.md` („Das große Thema“), auf Grundlage des Codes von Version 2.2. Nichts davon ist gebaut; die offenen Entscheidungen in Abschnitt 7 sind zuerst zu treffen. Wer baut, trägt den Fortschritt je Schritt hier unter Abschnitt 8 ein, wie in `docs/Android-Bestandsaufnahme.md`.

## 1. Ziel

Rezepte, Backhistorie, Anstellgut-Tagebuch und Einkaufslisten folgen dem Nutzer auf jedes Gerät, iPhone wie Android, über ein Konto bei Firebase. Das iPhone behält iCloud; Firebase ist der Kanal zwischen den Plattformen und zwischen Android-Geräten. Der Abgleich ist freiwillig (ein Schalter unter Einstellungen → Konto), braucht ein angemeldetes Konto (Apple oder Google) und ist als Pro-Merkmal vorgesehen. Ohne Konto und ohne Pro bleibt alles wie heute: lokal, iCloud, Sicherungsdatei.

## 2. Ist-Stand aus dem Code

| Bereich | Stand (2.2) | Folge für den Abgleich |
|---|---|---|
| Anmeldung iPhone | `RecipeFBModel`: anonym beim Start, „Mit Apple anmelden“ **verknüpft** das anonyme Konto (`link`), bei schon benutzter Apple-ID Wechsel zu diesem Konto; Abmelden → wieder anonym; Konto löschen (`user.delete`, bei Bedarf erneute Anmeldung); E-Mail wird nie gelesen | Apple-UID ist stabil über Geräte und Neuinstallation; Google fehlt |
| Anmeldung Android | `PublicRecipeService`: anonym; „Mit Apple anmelden“ **wechselt** per Browser (`OAuthProvider("apple.com")`), verknüpft nicht; Veröffentlichen nur angemeldet | gleiche UID wie auf dem iPhone, wenn dieselbe Apple-ID benutzt wird; Google fehlt |
| Firestore | Sammlungen `Recipe` (öffentlich, mit Untersammlungen), `admins`, `config`, `reports`; Regeln in `firebase/firestore.rules`, Tests in `firebase/tests/rules.test.mjs`; App Check für Firestore **nicht** erzwungen | keine Nutzer-Sammlung, keine Regel für private Daten |
| Storage | `images/{uid}/{uuid}.jpg` für öffentliche Rezepte (1024 px, JPEG 0,5), 5 MB-Grenze; alles andere verboten | kein Pfad für private Fotos |
| Functions | `analyzeRecipeImages`, `analyzeRecipeText`, `verifyProtectedConnection` in `europe-west1`, App Check erzwungen; Pro wird **je Aufruf** aus der mitgeschickten StoreKit-Transaktion geprüft (`proVerification.ts`), nirgends gespeichert; Monatszähler in `aiRateLimits/{uid}` | Regeln können heute nicht wissen, ob ein Nutzer Pro hat |
| Pro-Schalter | `config/monetization` (`proRequired`, `storeVisible`, `freeImportsPerMonth`, `grandfatherBeforeBuild`), steht auf „frei“; Play Billing fehlt | Abgleich als Pro-Merkmal braucht den gemeinsamen Umstieg (Plan in `docs/Android-Play-Release.md`, Abschnitt 5) |
| Speicher-Protokolle | Im Paket: `RecipeStore`, `BakeHistoryStore`, `StarterFeedingLogStore`, `ShoppingListStore`, `ScheduledStepStore`, je mit Vertrag; Umsetzungen `CoreData*Store` (iPhone) und `SQLite*Store` (Android, `BakePlannerStorage`) | der Abgleich kann gegen die Protokolle arbeiten, ohne Views und Core Data direkt zu berühren |
| Kennungen | Core Data: alle Entitäten haben ein optionales `id: UUID` (alte Objekte ohne), der Speicher-Schlüssel ist aber die Objekt-ID; SQLite: Schlüssel ist die Zeilennummer, keine UUID-Spalte; `NextStep` hat `planID` | **keine gerätestabile Kennung** — die erste Voraussetzung fehlt |
| Inhalt als Wert | `RecipeExportData` (Formatversion 2) mit Komponenten, Zutaten, Schritten, Bild, `bakeHistory`, `starterFeedings`; `StoredRecipe`, `StoredBakeHistory`, `StoredStarterFeeding`, `StoredShoppingList` | die Dokumente des Abgleichs können dieselben Felder tragen |
| Fotos | Core Data `Binary` (Rezeptbild) und `Transformable` (Backfotos); SQLite BLOB; Sicherung verkleinert auf 2048 px, JPEG 0,8 | gleiche Größe für die Cloud; Fotos getrennt von den Dokumenten |
| iCloud | `NSPersistentCloudKitContainer`, Container `iCloud.de.hpm64625.BackPlaner`, Verlaufsverfolgung an, Merge „Objekt gewinnt“ | bleibt; der Abgleich muss mit Änderungen rechnen, die über iCloud hereinkommen |
| Datenschutz | `docs/website/privacy.html`: private Daten „auf deinem Gerät, gesichert über deine iCloud“; Firestore nur für öffentliche Rezepte und den Monatszähler | Erklärung, App-Store-Datenschutzangaben und Play-Datensicherheit müssen nachziehen |

## 3. Zielbild

### 3.1 Grundsatz

Der lokale Speicher bleibt die Quelle für die Oberfläche (Core Data auf dem iPhone, SQLite auf Android). Ein `SyncEngine` im Paket `BakePlannerCore` gleicht ihn mit einem Cloud-Speicher ab; er kennt nur die Speicher-Protokolle, ein Journal und eine Schnittstelle `CloudStore`, deren Umsetzungen Firestore und Storage ansprechen (iPhone: Firebase-SDK in der App, Android: skip-firebase). So läuft die Logik mit Speichern im Arbeitsspeicher in den Paket-Tests, auch als „zwei Geräte gegen eine Cloud“.

Kein Echtzeit-Listener auf private Daten: abgeglichen wird beim Start, beim Wechsel in den Vordergrund, nach eigenen Änderungen (verzögert gesammelt) und auf Wunsch von Hand. Das hält Lesevorgänge und Komplexität klein; ein Listener kann später dazukommen.

### 3.2 Was abgeglichen wird

| Daten | 3.0 | Begründung |
|---|---|---|
| Eigene Rezepte mit Bild | ja | Kern |
| Backhistorie mit Fotos | ja | gehört zum Rezept, Formatversion 2 kennt sie schon |
| Anstellgut-Tagebuch | ja | dito |
| Einkaufslisten | ja, ohne öffentliche Rezept-Namen zu prüfen | klein, folgt dem Rezept-Schlüssel |
| Geplante Schritte (Pläne) | **nein** (Entscheidung 7.2) | Erinnerungen sind gerätegebunden; „Erledigt“ und „Verschieben“ müssten die Erinnerungen des anderen Geräts umsetzen; Rhythmus-Automatik liefe doppelt |
| Einstellungen, eigene Einheiten, blockierte Autoren | nein | gerätebezogen; eigene Einheiten später als eigener kleiner Schritt |

### 3.3 Kennungen

Jeder abgeglichene Datensatz braucht eine UUID, die auf allen Geräten dieselbe ist:

- iPhone: das vorhandene Attribut `id` wird **einmalig für alte Objekte nachgefüllt** (Rezepte, Backhistorie, Fütterungen, Einkaufslisten, Komponenten/Zutaten/Schritte brauchen keine). Das ist ein Core-Data-Schreibvorgang, keine Modelländerung; er geht über iCloud auf die anderen Geräte des Nutzers. Bisher wurde das bewusst vermieden, damit alte Rezepte nichts in die iCloud schreiben — für den Abgleich ist es nötig und läuft erst, wenn der Nutzer ihn einschaltet (oder, einfacher, einmal beim ersten Start von 3.0; Entscheidung 7.6).
- Android: Schema-Schritt 6 ergänzt `uuid` in `recipe`, `bake_history`, `starter_feeding`, `shopping_list` und füllt bestehende Zeilen.
- Die `Stored*`-Structs bekommen `uuid`; der bisherige `id`-Schlüssel bleibt, damit nichts an den Views und Verträgen bricht.

Rezepte, die über die Sicherungsdatei auf das andere Gerät kamen, haben dort eine andere UUID: Sie erscheinen nach dem ersten Abgleich doppelt. Dafür gibt es beim Einschalten eine Hinweisseite und eine Zusammenführung nach Name und Inhalt (gleicher Name, gleiche Komponenten und Schritte → zusammenlegen, Backhistorie vereinen); keine stille Automatik.

### 3.4 Dokumente in Firestore

Alles unter `users/{uid}`:

| Pfad | Inhalt |
|---|---|
| `users/{uid}` | `schemaVersion`, `createdAt`, `lastSyncAt` je Gerät (Karte `devices`), vom Server geschrieben `pro` (Abschnitt 3.7) |
| `users/{uid}/recipes/{uuid}` | die Felder von `RecipeExportData` ohne Bild und ohne `bakeHistory`/`starterFeedings`; dazu `firestoreId` (eigene Kopie eines öffentlichen Rezepts), `adjustedOn`, `bakeHistoryFlag`, `imageHash`, `imagePath`, `updatedAt`, `deleted`, `deviceId` |
| `users/{uid}/bakes/{uuid}` | `recipeId`, Datum, Kommentar, Fakten, `photoHashes`, `photoPaths`, `updatedAt`, `deleted` |
| `users/{uid}/feedings/{uuid}` | `recipeId`, Datum, Reifezeit, Schwimmtest, Notiz, `updatedAt`, `deleted` |
| `users/{uid}/shoppingLists/{uuid}` | Datum, `recipeIds`, `publicRecipeNames`, Zeilen als Array, `updatedAt`, `deleted` |

Komponenten, Zutaten und Schritte liegen als Arrays **im** Rezeptdokument (ein Rezept ist Text im Kilobyte-Bereich, die 1-MiB-Grenze ist fern). Das macht Rezept lesen, schreiben und Konflikt lösen zu je einem Dokument. Flache Sammlungen für Backhistorie und Fütterungen statt Untersammlungen je Rezept, damit „alles seit Zeitpunkt X“ eine Abfrage ist.

Gelöschtes wird als Grabstein (`deleted: true`, Felder geleert) behalten, sonst erfährt das zweite Gerät nichts vom Löschen; Grabsteine älter als 90 Tage räumt eine geplante Function ab.

Die Abbildung Struct ↔ Dokument liegt im Paket (`SyncRecordMapping`, nach dem Muster von `RecipeFirestoreMapping`), mit Zahlen tolerant gelesen (Int/Int64/Double, wegen des Android-SDK) und mit eigener `syncSchemaVersion` im Nutzer-Dokument. Ältere Apps lesen neuere Versionen nicht und sagen das, wie bei der Sicherungsdatei.

### 3.5 Fotos in Storage

`users/{uid}/recipes/{uuid}.jpg` und `users/{uid}/bakes/{uuid}/{hash}.jpg`, verkleinert wie die Sicherung (2048 px, JPEG 0,8, `PhotoShrinker` auf Android, `RecipeExport.longestEdge` auf dem iPhone). Das Dokument trägt den Hash; ein Gerät lädt ein Foto nur, wenn es den Hash nicht hat. Hochladen läuft über eine Warteschlange im Journal: erst Foto, dann Dokument mit Hash; bricht es ab, bleibt das Dokument ohne neuen Hash und der nächste Lauf holt es nach. Regel: 5 MB je Datei, nur Bilder, nur der Eigentümer.

### 3.6 Abgleich im Einzelnen

**Journal** (`SyncJournal` im Paket, je Gerät, nicht im Core-Data-Modell, nicht in iCloud): je Datensatz UUID, zuletzt gesendeter Inhalts-Hash, zuletzt gesehener `updatedAt` aus der Cloud, offene Foto-Uploads; je Sammlung der Zeitpunkt des letzten Abrufs. Ablage als JSON-Datei in Application Support (klein, `Codable`), für Android dasselbe; keine zusätzliche SQLite-Tabelle nötig. Damit bleiben Core-Data-Modell und CloudKit-Schema unberührt.

**Push:** Alle lokalen Datensätze lesen (ohne Bilder), Hash des Inhalts bilden, mit dem Journal vergleichen; Geändertes und Neues schreiben (`updatedAt` = Serverzeit), aus dem Journal Verschwundenes als Grabstein; dann Fotos der geänderten Datensätze, deren Hash sich geändert hat.

**Pull:** Je Sammlung `where updatedAt > letzter Abruf` (Index nötig), Ergebnis auf den lokalen Speicher anwenden: unbekannte UUID → anlegen; bekannte → Konfliktregel; Grabstein → lokal löschen (Rezept löschen zieht Backhistorie und Fütterungen mit, wie heute in beiden Speichern).

**Konfliktregel** (Entscheidung 7.3): je Datensatz gewinnt die spätere Änderung („last writer wins“ je Dokument). Ein Rezept ist dabei eine Einheit samt Komponenten und Schritten. Zeitbasis ist der Server-Zeitstempel des Dokuments; lokale Änderungen, die seit dem letzten Abruf gemacht wurden und auf ein in der Cloud ebenfalls geändertes Dokument treffen, verlieren gegen die Cloud **nur dann**, wenn deren Zeitstempel jünger ist als der Zeitpunkt der lokalen Änderung (den das Journal mit dem Hash festhält). Je Feld zusammenführen wäre bei Rezepten (Arrays von Komponenten) nicht sinnvoll.

**iCloud und Firebase zugleich** (zwei iPhones/iPads eines Nutzers): Beide Geräte sehen über iCloud dieselben Objekte mit derselben UUID. Gerät B findet nach dem iCloud-Merge ein „neues“ lokales Rezept und schreibt es in die Cloud, wo es Gerät A schon abgelegt hat — gleicher Pfad, gleicher Hash, also ein wirkungsloses Überschreiben oder, bei Hash-Gleichheit, gar kein Schreiben. Entscheidend ist, dass der Push den Hash mit dem **Cloud**-Dokument vergleicht, wenn das Journal den Datensatz nicht kennt. Das wird in den Paket-Tests als Szenario „zwei Geräte, geteilter lokaler Speicher“ abgedeckt.

**Offline:** Dokumente über den Firestore-Cache; ohne Netz endet der Lauf nach dem Journal-Vergleich, nichts geht verloren. Fotos warten in der Warteschlange. Auf Android ist zu prüfen, ob skip-firebase den Offline-Cache einschaltet (Schritt K0).

### 3.7 Konto, Anmeldung, Pro

- **Anbieter:** Apple (vorhanden) und Google. Google auf beiden Plattformen über den Firebase-Web-Ablauf (`OAuthProvider("google.com")`), damit kein weiteres SDK in die iOS-App muss und Android keinen Kotlin-Code braucht (Entscheidung 7.4). Beide Anbieter lassen sich an **einem** Firebase-Konto verknüpfen; die Konto-Seite zeigt, welche verbunden sind, und bietet „Google hinzufügen“ bzw. „Apple hinzufügen“.
- **Zwei Konten mit Daten** (Nutzer hat auf dem iPhone mit Apple, auf Android mit Google angemeldet und beide haben schon abgeglichen): Firebase kann zwei bestehende Konten nicht verschmelzen. Weg: In der App „Konten zusammenführen“ → mit dem zweiten Anbieter anmelden, dessen Cloud-Daten in das erste Konto kopieren (UUIDs bleiben), das zweite Konto löschen, den zweiten Anbieter ans erste Konto hängen. Als Function im Admin-SDK, nicht im Client.
- **Abgleich nur angemeldet:** Ein anonymes Konto geht bei Neuinstallation verloren; die Regeln lassen private Daten deshalb nur für `sign_in_provider != "anonymous"` zu.
- **Pro:** Die Regeln prüfen `request.auth.token.pro == true`. Den Anspruch setzt eine Function `refreshProStatus` als Custom Claim, nachdem sie die StoreKit-Transaktion mit `proVerification.ts` geprüft hat (später ebenso den Play-Kaufbeleg); die App ruft sie nach dem Kauf, bei „Käufe wiederherstellen“ und einmal je Start, wenn der Claim fehlt. Solange `config/monetization.proRequired == false` ist, setzt die Function den Claim für jeden, der ihn verlangt (Fail-open wie die App). So kann der Abgleich vor dem Pro-Umstieg ausgeliefert und getestet werden, und der Umstieg bleibt ein Konsolen-Schalter.
- **Konto löschen** löscht auch `users/{uid}` samt Fotos: Function auf das Auth-Ereignis „Nutzer gelöscht“ (Admin-SDK, rekursiv), nicht im Client. Abmelden lässt die lokalen Daten stehen und hält den Abgleich an. „Daten in der Cloud löschen“ als eigener Punkt ohne Konto-Löschung.

### 3.8 Oberfläche

Einstellungen → Konto:

- Anmeldung mit Apple **oder** Google, verbundene Anbieter, Abmelden, Konto löschen (wie heute, plus Google).
- Schalter „Abgleich über das Konto“ (Pro-Schloss wie bei den anderen Pro-Merkmalen). Einschalten führt durch: Hinweis, was in die Cloud geht; Vorschau „n Rezepte auf diesem Gerät, m im Konto, k doppelt (Name gleich)“; dann der erste Abgleich mit Fortschritt (Fotos zählen).
- Status: „Zuletzt abgeglichen …“, „x Fotos warten“, „Jetzt abgleichen“, Fehler mit Erklärung (kein Netz, kein Pro mehr, Speicher voll).
- Nach dem Einschalten keine weiteren Fragen; Konflikte entscheidet die Regel.

Auf Android dieselbe Seite in `SettingsView`; die Texte kommen aus dem iOS-Katalog.

### 3.9 Datenschutz und Stores

- `privacy.html` (de/en/fr): neue Zeile „eigene Rezepte, Backhistorie, Anstellgut-Tagebuch, Einkaufslisten — bei eingeschaltetem Abgleich in Firebase (Firestore und Storage, Google), nur für dein Konto lesbar, löschbar in der App“; Region des Firestore-Standorts nennen (in der Konsole nachsehen; die Functions laufen in `europe-west1`).
- App Store: Datenschutz-Angaben um „Nutzerinhalte, mit dem Konto verknüpft“ ergänzen. Play: Datensicherheit entsprechend (`docs/Android-Play-Release.md`, Abschnitt 4.4).
- Handbuch Kapitel Konto/Sicherung (de/en/fr), danach `python3 docs/build-manual-html.py`.

## 4. Was sich **nicht** ändert

- Core-Data-Modell und CloudKit-Schema: keine neuen Attribute; das Nachfüllen von `id` ist ein Datenschreibvorgang.
- Sicherungsformat: unverändert (Formatversion 2); die Sicherungsdatei bleibt der Weg ohne Konto.
- Öffentliche Rezepte, Moderation, App Check: unverändert; die neuen Regeln kommen dazu.
- Für Nutzer ohne Konto oder ohne Schalter: nichts.

## 5. Schritte, je ein Branch

Reihenfolge so, dass jeder Schritt mit grünen Tests endet und die Apps für Nutzer unverändert lässt, bis K8 den Schalter zeigt. Die Punkte mit **Rückfrage** brauchen Hans-Peters Freigabe vor dem Ausführen (Regeln, Functions, Konsole).

| Schritt | Inhalt | Prüfung |
|---|---|---|
| **K0 Proben** | (a) skip-firebase: Server-Zeitstempel (`FieldValue.serverTimestamp()`) und Offline-Cache aus nativem Swift (die Übergabe nennt den Zeitstempel als nicht erreichbar); Ausweichweg: Function `stampWrite` oder Zeitstempel vom Client mit Toleranz. (b) Firestore-Standort und Preise in der Konsole nachsehen (Abschnitt 6). (c) Google-Anmeldung per Web-Ablauf auf beiden Plattformen in der Firebase-Konsole einrichten und im Emulator/Simulator einmal durchspielen | Notiz in Abschnitt 8 |
| **K1 Kennungen** | `uuid` in `StoredRecipe`, `StoredBakeHistory`, `StoredStarterFeeding`, `StoredShoppingList`; Core-Data-Speicher liefern `id` und füllen es beim Lesen nach, wenn es fehlt (Entscheidung 7.6); SQLite Schema-Schritt 6 mit `uuid`-Spalten; Verträge: „uuid bleibt über Schließen/Öffnen gleich“, „zwei Speicher, dieselbe uuid nach Import“ | Paket-Tests, `CoreData*StoreTests`, `swift test` und `skip android test` in `BakePlannerStorage` |
| **K2 Dokumente** | `SyncRecordMapping` im Paket: Struct ↔ `[String: Any]` für Rezept, Backeintrag, Fütterung, Einkaufsliste; Inhalts-Hash (SHA-256 über eine kanonische JSON-Form, Bild getrennt); `syncSchemaVersion` | Rundreise-Tests, Hash-Stabilität über Plattformen (Zahl 1.0 vs 1, Reihenfolge) |
| **K3 Journal** | `SyncJournal` (Protokoll) mit `FileSyncJournal` (JSON) und Speicher im Arbeitsspeicher; Foto-Warteschlange | Paket-Tests |
| **K4 Engine** | `CloudStore`-Protokoll (Dokumente lesen seit Zeitpunkt, schreiben, Fotos laden/speichern) mit `InMemoryCloudStore`; `SyncEngine.run()` mit Push, Pull, Konfliktregel, Grabsteinen, Foto-Warteschlange, Zusammenführung doppelter Rezepte (Vorschlag und Ausführung getrennt) | Szenario-Tests: zwei Geräte; Änderung auf beiden; Löschen; Foto-Abbruch; iCloud-Echo (geteilter lokaler Speicher); Rezept ohne Bild → mit Bild |
| **K5 Firebase-Anbindung** | iPhone: `FirestoreCloudStore` in der App; Android: dasselbe mit skip-firebase (Batch-Schreiben, siehe Stolperstein „Sendable“); Regeln für `users/{uid}/**` und Storage `users/{uid}/**` mit Tests im Emulator (`firebase/tests`); Index `updatedAt` je Sammlung (`firestore.indexes.json`) — **Rückfrage** vor dem Deploy | Regel-Tests; ein Testkonto, zwei Simulatoren/Emulatoren |
| **K6 Konto** | Google-Anmeldung (Web-Ablauf) auf beiden Plattformen; Anbieter verknüpfen und anzeigen; Function `onUserDeleted` löscht `users/{uid}` und Fotos; Function `mergeAccounts` — **Rückfrage** vor dem Deploy | UI-Smoke-Tests; Function-Tests mit Emulator |
| **K7 Pro-Anspruch** | Function `refreshProStatus` (StoreKit-JWS prüfen, Claim setzen; Fail-open solange `proRequired == false`); Regeln prüfen den Claim; App ruft sie nach Kauf/Wiederherstellen/Start; `ProFeature.sync` — **Rückfrage** vor dem Deploy | Function-Tests (vorhandene Verifier-Fakes), Regel-Tests |
| **K8 Oberfläche iPhone** | Konto-Seite, Schalter, Einrichtungsablauf, Status, Fehler; Abgleich beim Start/Vordergrund/nach Änderungen (über die vorhandenen Speicher-Aufrufe, nicht über Views); Texte de/en/fr | UI-Tests, `check-repo.py` |
| **K9 Oberfläche Android** | dasselbe in `BakePlannerAndroid`; Hintergrund: nur Vordergrund-Läufe (wie der Rhythmus) | Emulator |
| **K10 Texte** | Handbuch, Datenschutzerklärung, App-Store- und Play-Angaben, `docs/Neuerungen-3.0.md` | `check-repo.py`, Handbuch-HTML |
| **K11 Testlauf** | Zwei Wochen mit eigenen Geräten (iPhone, iPad, Android-Telefon), danach TestFlight/geschlossener Test; Kosten in der Konsole nachsehen | Notiz in Abschnitt 8 |

Pro auf beiden Plattformen (Play Billing, Umstieg von `config/monetization`) ist ein eigener Plan; K7 ist die Schnittstelle dazu: Die Function nimmt später zusätzlich einen Play-Beleg an.

## 6. Kosten, Größenordnung

Annahmen je aktivem Nutzer mit Abgleich: 50 Rezepte, 200 Backeinträge, 100 Fütterungen, 20 Einkaufslisten; 300 Fotos à 0,4 MB = 120 MB in Storage; 1 MB Dokumente in Firestore; 10 App-Starts am Tag, davon im Mittel ein Lauf mit Änderungen.

| Posten | je Nutzer und Monat | 1 000 Nutzer |
|---|---|---|
| Firestore-Lesevorgänge | 10 Starts × 5 Abfragen × 30 Tage ≈ 1 500 (Abfragen ohne Treffer kosten je einen Lesevorgang) plus Erstabruf ≈ 400 | ≈ 2 Mio |
| Firestore-Schreibvorgänge | ≈ 100 | ≈ 100 000 |
| Firestore-Speicher | 1 MB | 1 GB |
| Storage-Speicher | 120 MB | 120 GB |
| Storage-Download | Erstabruf auf einem zweiten Gerät 120 MB, danach nur Neues | ≈ 20 GB |

Das liegt bei den Listenpreisen (Stand meines Wissens; **in der Konsole unter Nutzung und Abrechnung nachsehen, Preise ändern sich**) im Bereich weniger Euro bis zweistellig im Monat für 1 000 aktive Nutzer; der größte Posten ist der Storage-Speicher für Fotos. Hebel, falls nötig: Fotos auf 1600 px, Backfotos auf fünf je Eintrag begrenzen, Erstabruf ohne Fotos (nachladen beim Öffnen). Das Projekt läuft wegen der Functions ohnehin im Blaze-Tarif; ein Budget-Alarm in der Google-Cloud-Konsole gehört zu K11.

## 7. Offene Entscheidungen (Hans-Peter)

1. **iCloud bleibt** als Speicher des iPhones, Firebase ist der Kanal (Vorschlag: ja). Alternative: iCloud ablösen — braucht Migrationsplan, ändert Core-Data-Aufbau und verliert den Vorteil, dass iPhone und iPad ohne Konto abgleichen.
2. **Pläne nicht abgleichen** in 3.0 (Vorschlag: ja); eine spätere Fassung könnte sie nur lesend zeigen („auf dem iPhone geplant“).
3. **Konfliktregel** je Datensatz, spätere Änderung gewinnt (Vorschlag: ja).
4. **Google-Anmeldung** über den Firebase-Web-Ablauf statt nativer SDKs (Vorschlag: ja; Nachteil: ein Browserfenster statt des System-Dialogs).
5. **Abgleich als Pro-Merkmal** (Vorschlag: ja; bis zum Pro-Umstieg für alle offen, Abschnitt 3.7).
6. **UUIDs nachfüllen** für alte Core-Data-Objekte: beim ersten Start von 3.0 für alle (einfach, ein iCloud-Schub) oder erst beim Einschalten des Abgleichs (schonender, mehr Fälle in den Speichern). Vorschlag: beim Einschalten, und zusätzlich beim Lesen im Speicher, wenn es fehlt.
7. **Doppelte Rezepte** nach Sicherungsdatei-Import: Vorschlag per Zusammenführungsliste im Einrichtungsablauf (Abschnitt 3.3), nicht automatisch.
8. **Grenzen:** Fotos je Backeintrag (Vorschlag 10), Größe (2048 px wie die Sicherung), Grabsteine 90 Tage.
9. **Zeitplan:** K0–K4 sind ohne Konsole und ohne Rückfrage machbar und verändern nichts für Nutzer; ab K5 braucht es Deploys. Vorschlag: K0–K4 zuerst, dann Entscheidung über den Rest mit den Befunden aus K0.

## 8. Fortschritt

Noch nichts begonnen.
