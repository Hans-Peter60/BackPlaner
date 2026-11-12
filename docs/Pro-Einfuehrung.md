# Pro einführen – Schritt 1: Kontingent für Cloud-Importe

Stand: 11.11.2026. Erster Schritt auf dem Weg zu BakePlanner Pro als bezahltem Umfang: Der KI-Import aus Fotos und Text (Cloud Functions `analyzeRecipeImages`, `analyzeRecipeText`, Gemini über Vertex AI) kostet je Aufruf Geld. Ohne Pro gibt es künftig eine feste Zahl freier Importe im Monat, mit Pro keine Grenze. Alles andere bleibt frei, wie in `CLAUDE.md` festgelegt.

## Was schon gebaut ist

| Teil | Wo | Verhalten |
|---|---|---|
| Schalter | Firestore `config/monetization`, Feld `freeImportsPerMonth` (Zahl; 0 = kein Limit) | App und Functions lesen dasselbe Dokument (`MonetizationConfig`, `readMonetizationLimits`), Cache in den Functions eine Minute |
| Zählung | Firestore `aiRateLimits/{uid}`: `month` („2026-11“, UTC), `monthCount`, dazu `windowStartedAt`/`count` für das Stundenlimit (20 je Stunde, gilt immer) | `enforceRateLimit` in `functions/src/index.ts`; der Monat startet bei null |
| Pro-Nachweis | Die iPhone-App schickt die signierte StoreKit-Transaktion (`proTransaction`) bzw. die AppTransaction (`proAppTransaction`); `proVerification.ts` prüft Apples Signatur | Ein geprüfter Nachweis wird 7 Tage per Hash im `aiRateLimits`-Dokument gemerkt; nur Production/Sandbox zählen, Xcode-Umgebung nie |
| Großvaterregel | Feld `grandfatherBeforeBuild` (Build-Nummer als Text) | Installationen, deren `originalAppVersion` kleiner ist, sind Bestandsnutzer. **Seit 12.11.2026 je Funktion:** Ein Bestandsnutzer behält jede Pro-Funktion, deren `ProFeature.introducedBuild` nicht größer ist als sein Erst-Build (Einkaufsliste, PDF, Weitergabe, wiederkehrende Pläne, Widgets, Live-Aktivität: seit Build 1; Vorrat, Backtag, Sammlungen/„Fertig bis“, Statistik, Bäckerprozent: Build 21). Cloud-Importe bleiben für Bestandsnutzer ohne Limit (Functions prüfen die AppTransaction wie bisher). Wer eine neuere Funktion will, sieht die Kaufseite mit dem Hinweis „Was es damals gab, bleibt frei“ |
| Android | Firebase-App-ID der Android-App steht in `appIdsWithoutMonthlyLimit` (`functions/src/index.ts`) | **Vom Monatslimit ausgenommen**, solange es dort keinen Kauf gibt (Play Billing kommt mit dem Pro-Umstieg beider Plattformen); das Stundenlimit gilt |
| Antwort | Die Functions liefern `freeImports: {used, limit}` mit, nur wenn ein Limit greift | Die App zeigt nach dem Import „Noch 2 kostenlose Cloud-Importe …“, „Noch ein …“ und beim letzten „Das war der letzte …“ (`CloudRecipeAnalysis.FreeImports.notice`) |
| Limit erreicht | Function antwortet `resource-exhausted` mit `reason: monthly-limit` | Die App analysiert auf dem Gerät weiter und erklärt es („Die kostenlosen Cloud-Importe dieses Monats sind aufgebraucht … Mit BakePlanner Pro gibt es kein Monatslimit.“) |
| Kauf | StoreKit 2, `de.hpm64625.BackPlaner.pro`, Pro-Abschnitt in den Einstellungen und Paywall | Sichtbar nur bei `storeVisible == true` (oder nach Kauf); `proRequired` sperrt darüber hinaus die Pro-Merkmale aus `ProFeature` – das bleibt für Schritt 1 **aus** |

Im UI-Test lässt sich das Limit vortäuschen: Startargument `-UITestingMonetization freeImports:3` (siehe `Utilities/UITestSupport.swift`).

## Stand und Vorbedingung (11.11.2026)

**Der Schalter bleibt aus.** Einen Kauf „BakePlanner Pro“ gibt es in App Store Connect noch nicht: Dafür braucht Hans-Peter zuerst eine Gewerbeanmeldung und dann den Vertrag für bezahlte Apps bei Apple (App Store Connect → Vereinbarungen, Steuer und Bankverbindung: Steuerformulare, Bankkonto). Beides macht er erst, wenn die App ein paar Nutzer hat; bis dahin sind die Vertex-AI-Kosten bei wenigen Nutzern überschaubar. Ein Monatslimit ohne kaufbares Pro wäre eine Grenze ohne Ausweg, und der Hinweis „Mit BakePlanner Pro gibt es kein Monatslimit“ wäre falsch.

Reihenfolge, wenn es so weit ist:

1. Gewerbe anmelden (Kleinunternehmer reicht für den Anfang).
2. App Store Connect → Vereinbarungen: Vertrag für bezahlte Apps annehmen, Steuer- und Bankdaten eintragen; Google Play braucht für Play Billing entsprechend ein Zahlungsprofil.
3. In-App-Kauf `de.hpm64625.BackPlaner.pro` (Einmalkauf, nicht verbrauchbar) anlegen, Preis und Texte in de/en/fr, Prüf-Screenshot; mit der nächsten App-Version einreichen.
4. Erst dann die Schritte unten.

## Einschalten (von Hand, Firebase Console)

Vorher prüfen:

1. **App Store Connect → BakePlanner → In-App-Käufe:** „BakePlanner Pro“ muss den Status *Bereit zum Verkauf* haben. Ohne verkaufbaren Kauf darf das Limit nicht eingeschaltet werden – sonst gibt es eine Grenze ohne Ausweg.
2. Die Functions mit der Android-Ausnahme und der `freeImports`-Antwort sind deployt: `cd functions && npm test && npm run deploy` (Rückfrage laut `CLAUDE.md`).
3. Eine App-Version mit der Vorwarnung („Noch 2 …“) ist im Store – sonst sehen Nutzer erst beim Erreichen des Limits einen Hinweis. Die Grenze selbst funktioniert auch mit älteren Versionen (ab 2.2).

Dann in **Firebase Console → Firestore → `config/monetization`**:

| Feld | Wert | Wirkung |
|---|---|---|
| `storeVisible` | `true` | Pro-Abschnitt in den Einstellungen und Kaufknopf erscheinen; nichts wird gesperrt |
| `freeImportsPerMonth` | `5` | fünf Cloud-Importe je Kalendermonat ohne Pro (iPhone, iPad, Mac) |
| `proRequired` | `false` lassen | Einkaufsliste, PDF, Widgets usw. bleiben für alle offen |
| `grandfatherBeforeBuild` | die Build-Nummer des **ersten Builds mit eingeschaltetem Pro** (z. B. `"22"`) | Alle Installationen davor sind Bestandsnutzer: Sie behalten die Funktionen ihres Erst-Builds (siehe Großvaterregel oben) und haben kein Import-Limit; nur Neuinstallationen zahlen für alles. Entscheidung Hans-Peter vom 12.11.2026: „Was bis zur eigenen Installation frei war, bleibt frei; alles Neuere nur mit Pro.“ Will man Vorrat und Co. nur für 2.3-Installationen sperren, muss Pro mit dem ersten 2.4-Store-Build zusammen starten (ein 2.4 mit offener Schranke schenkt diesen Installationen die 2.4-Funktionen) |

Die Functions übernehmen den Wert innerhalb einer Minute, die App beim nächsten Start.

## Beobachten

- **Functions-Logs** (`cd functions && npm run logs` oder Console): „Pro claim decided“ mit `isPro`/`reason`; `resource-exhausted` mit `monthly-limit`.
- **Firestore `aiRateLimits`:** `monthCount` je Nutzer; wer oft am Limit ist, ist ein Pro-Kandidat.
- **Vertex-AI-Kosten** in der Google-Cloud-Abrechnung des Projekts `back-planer`: vor und nach dem Einschalten vergleichen.

## Zurücknehmen

`freeImportsPerMonth` auf `0` setzen – binnen einer Minute gilt kein Monatslimit mehr; `monthCount` läuft weiter, stört aber nicht.

## Offen

- Android bekommt das Limit erst mit Play Billing; dann die App-ID aus `appIdsWithoutMonthlyLimit` nehmen und in `PublicRecipeService` den Fehler `monthly-limit` wie das iPhone behandeln (Hinweis statt roher Fehlermeldung).
- Preisempfehlung vom 12.11.2026: Einmalkauf 9,99 € (untere Grenze 7,99 €), Familienfreigabe an, Small Business Program beantragen; auch mit Pro eine Fair-Use-Grenze für Cloud-Importe (z. B. 100 im Monat) erwägen.
- Neue Pro-Funktion einführen: Fall in `ProFeature` (Paket, `BakePlannerCore/Sources/BakePlannerCore/ProAccess.swift`) anlegen **mit `introducedBuild` = erster Store-Build, der sie enthält**, Titel/Beschreibung/Symbol in der App-Erweiterung (`BackPlaner/Utilities/ProFeature.swift`), Texte de/en/fr, Gate (`ProGate`/`ProLockedScreen`), Kaufseiten-Reihenfolge prüfen, Handbuch Kapitel 14 ergänzen.
- **Seit 12.11.2026 liegt die Entscheidung im Paket:** `ProFeature`, `MonetizationConfig` (inkl. Lesen des Firestore-Dokuments) und `ProAccess.resolve(config:purchased:originalAppVersion:) -> ProResolution` in `ProAccess.swift`, Tests in `ProAccessTests`. Die iOS-App (`Entitlements`) reicht nur noch StoreKit-Kauf und `originalAppVersion` hinein; Android kann dieselbe Funktion mit Play Billing und dem Datum der Erstinstallation aufrufen (Plan in `docs/Android-Uebergabe.md`).
