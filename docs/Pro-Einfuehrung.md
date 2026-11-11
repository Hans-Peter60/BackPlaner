# Pro einführen – Schritt 1: Kontingent für Cloud-Importe

Stand: 11.11.2026. Erster Schritt auf dem Weg zu BakePlanner Pro als bezahltem Umfang: Der KI-Import aus Fotos und Text (Cloud Functions `analyzeRecipeImages`, `analyzeRecipeText`, Gemini über Vertex AI) kostet je Aufruf Geld. Ohne Pro gibt es künftig eine feste Zahl freier Importe im Monat, mit Pro keine Grenze. Alles andere bleibt frei, wie in `CLAUDE.md` festgelegt.

## Was schon gebaut ist

| Teil | Wo | Verhalten |
|---|---|---|
| Schalter | Firestore `config/monetization`, Feld `freeImportsPerMonth` (Zahl; 0 = kein Limit) | App und Functions lesen dasselbe Dokument (`MonetizationConfig`, `readMonetizationLimits`), Cache in den Functions eine Minute |
| Zählung | Firestore `aiRateLimits/{uid}`: `month` („2026-11“, UTC), `monthCount`, dazu `windowStartedAt`/`count` für das Stundenlimit (20 je Stunde, gilt immer) | `enforceRateLimit` in `functions/src/index.ts`; der Monat startet bei null |
| Pro-Nachweis | Die iPhone-App schickt die signierte StoreKit-Transaktion (`proTransaction`) bzw. die AppTransaction (`proAppTransaction`); `proVerification.ts` prüft Apples Signatur | Ein geprüfter Nachweis wird 7 Tage per Hash im `aiRateLimits`-Dokument gemerkt; nur Production/Sandbox zählen, Xcode-Umgebung nie |
| Großvaterregel | Feld `grandfatherBeforeBuild` (Build-Nummer als Text) | Installationen, deren `originalAppVersion` kleiner ist, gelten als Pro – in der App und in den Functions |
| Android | Firebase-App-ID der Android-App steht in `appIdsWithoutMonthlyLimit` (`functions/src/index.ts`) | **Vom Monatslimit ausgenommen**, solange es dort keinen Kauf gibt (Play Billing kommt mit dem Pro-Umstieg beider Plattformen); das Stundenlimit gilt |
| Antwort | Die Functions liefern `freeImports: {used, limit}` mit, nur wenn ein Limit greift | Die App zeigt nach dem Import „Noch 2 kostenlose Cloud-Importe …“, „Noch ein …“ und beim letzten „Das war der letzte …“ (`CloudRecipeAnalysis.FreeImports.notice`) |
| Limit erreicht | Function antwortet `resource-exhausted` mit `reason: monthly-limit` | Die App analysiert auf dem Gerät weiter und erklärt es („Die kostenlosen Cloud-Importe dieses Monats sind aufgebraucht … Mit BakePlanner Pro gibt es kein Monatslimit.“) |
| Kauf | StoreKit 2, `de.hpm64625.BackPlaner.pro`, Pro-Abschnitt in den Einstellungen und Paywall | Sichtbar nur bei `storeVisible == true` (oder nach Kauf); `proRequired` sperrt darüber hinaus die Pro-Merkmale aus `ProFeature` – das bleibt für Schritt 1 **aus** |

Im UI-Test lässt sich das Limit vortäuschen: Startargument `-UITestingMonetization freeImports:3` (siehe `Utilities/UITestSupport.swift`).

## Einschalten (von Hand, Firebase Console)

Vorher prüfen:

1. **App Store Connect → BakePlanner → In-App-Käufe:** „BakePlanner Pro“ muss den Status *Bereit zum Verkauf* haben. Ist der Kauf noch nicht geprüft, muss er mit einer App-Version eingereicht werden (In-App-Kauf im Versionsformular anhängen). Ohne verkaufbaren Kauf darf das Limit nicht eingeschaltet werden – sonst gibt es eine Grenze ohne Ausweg.
2. Die Functions mit der Android-Ausnahme und der `freeImports`-Antwort sind deployt: `cd functions && npm test && npm run deploy` (Rückfrage laut `CLAUDE.md`).
3. Eine App-Version mit der Vorwarnung („Noch 2 …“) ist im Store – sonst sehen Nutzer erst beim Erreichen des Limits einen Hinweis. Die Grenze selbst funktioniert auch mit älteren Versionen (ab 2.2).

Dann in **Firebase Console → Firestore → `config/monetization`**:

| Feld | Wert | Wirkung |
|---|---|---|
| `storeVisible` | `true` | Pro-Abschnitt in den Einstellungen und Kaufknopf erscheinen; nichts wird gesperrt |
| `freeImportsPerMonth` | `5` | fünf Cloud-Importe je Kalendermonat ohne Pro (iPhone, iPad, Mac) |
| `proRequired` | `false` lassen | Einkaufsliste, PDF, Widgets usw. bleiben für alle offen |
| `grandfatherBeforeBuild` | leer lassen **oder** `"21"` | Mit `"21"` zählen alle Installationen aus der Zeit vor 2.4 (21) als Pro und haben kein Limit; nur Neuinstallationen werden begrenzt. Entscheidung Hans-Peter (offen) |

Die Functions übernehmen den Wert innerhalb einer Minute, die App beim nächsten Start.

## Beobachten

- **Functions-Logs** (`cd functions && npm run logs` oder Console): „Pro claim decided“ mit `isPro`/`reason`; `resource-exhausted` mit `monthly-limit`.
- **Firestore `aiRateLimits`:** `monthCount` je Nutzer; wer oft am Limit ist, ist ein Pro-Kandidat.
- **Vertex-AI-Kosten** in der Google-Cloud-Abrechnung des Projekts `back-planer`: vor und nach dem Einschalten vergleichen.

## Zurücknehmen

`freeImportsPerMonth` auf `0` setzen – binnen einer Minute gilt kein Monatslimit mehr; `monthCount` läuft weiter, stört aber nicht.

## Offen

- Android bekommt das Limit erst mit Play Billing; dann die App-ID aus `appIdsWithoutMonthlyLimit` nehmen und in `PublicRecipeService` den Fehler `monthly-limit` wie das iPhone behandeln (Hinweis statt roher Fehlermeldung).
- Der nächste Pro-Schritt laut `docs/Ideen-3.0.md`: Rezept nach Bäckerprozent anlegen.
