import {setGlobalOptions} from "firebase-functions";
import {HttpsError, onCall} from "firebase-functions/v2/https";
import {initializeApp} from "firebase-admin/app";
import {getFirestore, Timestamp} from "firebase-admin/firestore";
import {GoogleGenAI} from "@google/genai";
import {
  ProVerifier,
  decidePro,
  hasProClaim,
  makeAppleVerifier,
  proClaimHash,
  readProClaim,
} from "./proVerification.js";

initializeApp();

setGlobalOptions({
  region: "europe-west1",
  maxInstances: 2,
});

/**
 * Verifies the protected connection from BackPlaner to Cloud Functions.
 * A valid Firebase Auth session and App Check token are required.
 */
export const verifyProtectedConnection = onCall(
  {enforceAppCheck: true},
  (request) => {
    if (!request.auth) {
      throw new HttpsError(
        "unauthenticated",
        "Für diese Anfrage ist eine Anmeldung erforderlich.",
      );
    }

    return {
      ok: true,
      authenticated: true,
      appCheckVerified: request.app !== undefined,
    };
  },
);

const recipeSchema = {
  type: "OBJECT",
  required: [
    "title",
    "summary",
    "sourceLanguage",
    "preparationMinutes",
    "components",
    "instructions",
    "warnings",
  ],
  properties: {
    title: {type: "STRING"},
    summary: {type: "STRING"},
    sourceLanguage: {type: "STRING"},
    preparationMinutes: {type: "INTEGER"},
    components: {
      type: "ARRAY",
      items: {
        type: "OBJECT",
        required: ["name", "ingredients"],
        properties: {
          name: {type: "STRING"},
          ingredients: {
            type: "ARRAY",
            items: {
              type: "OBJECT",
              required: ["name", "amount", "unit"],
              properties: {
                name: {type: "STRING"},
                amount: {type: "NUMBER"},
                unit: {type: "STRING"},
              },
            },
          },
        },
      },
    },
    instructions: {
      type: "ARRAY",
      items: {
        type: "OBJECT",
        required: [
          "text",
          "durationMinutes",
          "componentName",
          "isBaking",
        ],
        properties: {
          text: {type: "STRING"},
          durationMinutes: {type: "INTEGER"},
          componentName: {type: "STRING"},
          isBaking: {type: "BOOLEAN"},
        },
      },
    },
    warnings: {
      type: "ARRAY",
      items: {type: "STRING"},
    },
  },
};

type RecipeImage = {
  data: string;
  mimeType: "image/jpeg" | "image/png";
};

/** Extraction rules shared by the image and the web page analysis. */
const sharedRecipeRules = [
  "Erfinde keine Zutaten, Mengen, Zeiten, Temperaturen oder Schritte.",
  "Bewahre die Originalsprache und trenne Sauerteig, Vorteig,",
  "Brühstück",
  "und Hauptteig in eigene Komponenten.",
  "Zutatenzeilen wie 'gesamter Roggensauerteig' oder 'gesamtes Quellstück'",
  "im Hauptteig sind Zutaten mit amount 0 und bleiben erhalten; die App",
  "erkennt daran, welche Komponente in welche andere eingeht.",
  "Für jede Komponente, die später in den Hauptteig eingeht (Sauerteig,",
  "Vorteig, Poolish, Quellstück, Brühstück, Kochstück …), fasse Herstellung",
  "und Reifung zu genau einem Arbeitsschritt zusammen: Der Text nennt die",
  "Zubereitung und die Reifeangabe, durationMinutes ist die Zeit vom",
  "Ansetzen bis zur Verwendung im Hauptteig. Enthält die Vorlage ein",
  "Planungsbeispiel mit Uhrzeiten, leite diese Dauer daraus ab (Beginn der",
  "Komponente bis Beginn des Hauptteigs). Vorlagen wiederholen unter jeder",
  "Komponente dieselben Sätze (wiegen, mischen, zudecken, reifen); daraus",
  "wird trotzdem nur ein Schritt je Komponente.",
  "Für den Hauptteig dagegen erzeuge für jede eigenständige Tätigkeit und",
  "jede Wartephase einen",
  "separaten Arbeitsschritt, auch wenn sie in der Vorlage im selben Absatz",
  "oder Aufzählungspunkt stehen. Zeitlich ausgelöste Zwischenaktionen",
  "wie 'nach 30 Minuten dehnen und falten' sind immer eigene Schritte.",
  "Wenn eine Gesamtphase eine Zwischenaktion enthält, teile die",
  "Wartezeit zeitlich korrekt vor und nach dieser Aktion auf.",
  "Beispiel:",
  "'1 Stunde ruhen, nach 30 Minuten falten' ergibt 30 Minuten ruhen,",
  "falten und weitere 30 Minuten ruhen. Fasse diese Schritte nicht",
  "wieder zu einem Satz zusammen.",
  "Ein ausdrücklich genanntes Vorheizen des Ofens ist immer ein",
  "eigener",
  "Schritt unmittelbar vor dem ersten Backschritt. Übernimm dabei die",
  "genannte Temperatur. Wenn keine Vorheizdauer angegeben ist, bleibt",
  "durationMinutes 0; die App setzt dann ihre konfigurierte",
  "Vorheizzeit.",
  "Jeder Arbeitsschritt muss für sich allein verständlich sein, weil die",
  "App ihn einzeln als Erinnerung anzeigt. Gehört ein Schritt zu einer",
  "Komponente (Sauerteig, Vorteig, Quellstück, Brühstück, Hauptteig …),",
  "beginne seinen Text mit dem Komponentennamen und einem Doppelpunkt,",
  "zum Beispiel 'Roggensauerteig: 12 Stunden bei 20 °C reifen lassen.',",
  "und trage denselben Namen in componentName ein. Verwende dafür exakt",
  "die Namen aus components.",
  "Nutze 0 oder eine leere Zeichenfolge für fehlende Werte und notiere",
  "unleserliche oder widersprüchliche Stellen in warnings.",
];

const maxImageCount = 10;
const maxImageBytes = 3 * 1024 * 1024;
const maxTotalBytes = 15 * 1024 * 1024;
const hourlyRequestLimit = 20;

export const analyzeRecipeImages = onCall(
  {
    enforceAppCheck: true,
    timeoutSeconds: 240,
    memory: "1GiB",
    maxInstances: 2,
  },
  async (request) => {
    const startedAt = Date.now();
    const uid = request.auth?.uid;
    if (!uid) {
      throw new HttpsError(
        "unauthenticated",
        "Für die Rezeptanalyse ist eine Anmeldung erforderlich.",
      );
    }

    const images = validateImages(request.data?.images);
    const allowance = await enforceRateLimit(uid, request.data,
      request.app?.appId);

    const parts = [
      {
        text: [
          "Analysiere alle Bilder gemeinsam als ein vollständiges Backrezept.",
          "Die Seiten stehen in der übermittelten Reihenfolge.",
          "Übernimm ausschließlich lesbare Angaben aus den Bildern.",
          ...sharedRecipeRules,
        ].join(" "),
      },
      ...images.map((image) => ({
        inlineData: {data: image.data, mimeType: image.mimeType},
      })),
    ];

    return {
      ...await generateRecipe(parts, {imageCount: images.length, startedAt}),
      ...allowance,
    };
  },
);

/**
 * Structures the text of a recipe web page, as extracted by the app, into
 * the same recipe shape as the image analysis. The page itself is fetched
 * by the app, so the server only ever sees the text the user chose to send.
 */
export const analyzeRecipeText = onCall(
  {
    enforceAppCheck: true,
    timeoutSeconds: 240,
    memory: "1GiB",
    maxInstances: 2,
  },
  async (request) => {
    const startedAt = Date.now();
    const uid = request.auth?.uid;
    if (!uid) {
      throw new HttpsError(
        "unauthenticated",
        "Für die Rezeptanalyse ist eine Anmeldung erforderlich.",
      );
    }

    const text = validateText(request.data?.text);
    const sourceURL = validateSourceURL(request.data?.sourceURL);
    const allowance = await enforceRateLimit(uid, request.data,
      request.app?.appId);

    const parts = [
      {
        text: [
          "Der folgende Text stammt von einer Internetseite mit einem",
          "Backrezept. Er kann strukturierte Rezeptdaten (schema.org) und den",
          "sichtbaren Seitentext enthalten; beides beschreibt dasselbe Rezept.",
          "Ignoriere Navigation, Werbung, Kommentare, Newsletter-Hinweise und",
          "Verweise auf andere Rezepte. Übernimm ausschließlich Angaben, die",
          "im Text stehen.",
          ...sharedRecipeRules,
          sourceURL ? `Quelle: ${sourceURL}` : "",
          "\n\nSEITENTEXT:\n",
          text,
        ].join(" "),
      },
    ];

    return {
      ...await generateRecipe(parts, {textLength: text.length, startedAt}),
      ...allowance,
    };
  },
);

/**
 * A cooked dish as CookPlanner plans it: work steps with the minutes the
 * cook is busy, the minutes the step then runs on its own, where it
 * happens, and what it waits for.
 */
const dishSchema = {
  type: "OBJECT",
  required: [
    "title",
    "servings",
    "sourceLanguage",
    "components",
    "steps",
    "ingredients",
    "warnings",
  ],
  properties: {
    title: {type: "STRING"},
    servings: {type: "INTEGER"},
    sourceLanguage: {type: "STRING"},
    components: {type: "ARRAY", items: {type: "STRING"}},
    steps: {
      type: "ARRAY",
      items: {
        type: "OBJECT",
        required: [
          "text",
          "componentName",
          "handsMinutes",
          "unattendedMinutes",
          "unattendedMinMinutes",
          "unattendedMaxMinutes",
          "station",
          "ovenTemperature",
          "maxWaitMinutes",
          "dependsOn",
          "ingredientIndices",
        ],
        properties: {
          text: {type: "STRING"},
          componentName: {type: "STRING"},
          handsMinutes: {type: "INTEGER"},
          unattendedMinutes: {type: "INTEGER"},
          unattendedMinMinutes: {type: "INTEGER"},
          unattendedMaxMinutes: {type: "INTEGER"},
          station: {type: "STRING", enum: ["none", "burner", "oven"]},
          ovenTemperature: {type: "INTEGER"},
          maxWaitMinutes: {type: "INTEGER"},
          dependsOn: {type: "ARRAY", items: {type: "INTEGER"}},
          ingredientIndices: {type: "ARRAY", items: {type: "INTEGER"}},
        },
      },
    },
    ingredients: {
      type: "ARRAY",
      items: {
        type: "OBJECT",
        required: ["name", "amount", "unit", "componentName", "note"],
        properties: {
          name: {type: "STRING"},
          amount: {type: "NUMBER"},
          unit: {type: "STRING"},
          componentName: {type: "STRING"},
          note: {type: "STRING"},
        },
      },
    },
    warnings: {type: "ARRAY", items: {type: "STRING"}},
  },
};

/** How a recipe becomes work steps for one cook against the clock. */
const dishRules = [
  "Der folgende Text ist ein Kochrezept für ein Gericht aus mehreren",
  "Komponenten (Hauptzutat, Beilagen, Sauce, Garnitur). Zerlege die",
  "Zubereitung in einzelne Arbeitsschritte, so wie eine Person sie",
  "nacheinander ausführt, und bewahre die Sprache des Rezepts.",
  "Jeder Schritt gehört zu genau einer Komponente; nenne die Komponenten",
  "in components (wie die Abschnitte des Rezepts) und trage den Namen in",
  "componentName ein. Der letzte Schritt ist das Anrichten mit leerem",
  "componentName.",
  "handsMinutes: nur die Minuten, in denen der Koch an diesem Schritt",
  "wirklich arbeitet (schneiden, rühren, wenden, arrosieren, anrichten,",
  "Pfanne erhitzen) – schätze sie für einen geübten Hobbykoch, auch wenn",
  "das Rezept keine Zeit nennt; Sekunden auf ganze Minuten aufrunden.",
  "unattendedMinutes: Minuten, die der Schritt danach ohne den Koch läuft.",
  "Alles, was brät, köchelt, reduziert, backt oder ruht, ohne dass jemand",
  "eingreift, zählt hierher, auch wenn es nur 2–3 Minuten sind ('ohne",
  "Bewegung braten', 'einkochen lassen', 'reduzieren'); 0 wenn keine.",
  "Beispiel: 'Pilze ohne Bewegung goldbraun braten, wenden, zweite Seite",
  "rösten, würzen' → handsMinutes 2, unattendedMinutes 3. 'N Minuten pro",
  "Seite': Gesamtzeit Seiten × N, davon je eine Minute Handarbeit fürs",
  "Einlegen, Wenden und Herausnehmen, der Rest unattended. Nennt das",
  "Rezept für die unbeaufsichtigte Zeit eine Spanne ('20–25 Minuten'),",
  "setze unattendedMinutes auf den unteren Wert und",
  "unattendedMinMinutes/unattendedMaxMinutes auf die Spanne; sonst und",
  "für reine Handarbeit beide 0.",
  "station: 'burner' für Topf oder Pfanne auf dem Herd, 'oven' für den",
  "Backofen, sonst 'none'. ovenTemperature in °C für Ofenschritte, sonst",
  "0. Vorheizen ist kein Schritt: Der Ofen ist heiß, wenn die Uhr startet.",
  "maxWaitMinutes: wie lange das Ergebnis liegen darf, bis der nächste",
  "Schritt es braucht: 0 nur, wenn es in derselben Pfanne sofort",
  "weitergehen muss (Wenden nach dem Anbraten, Ablöschen; das Ruhen",
  "beginnt sofort nach dem Braten), 3 für geruhtes Fleisch bis zum",
  "Tranchieren, 10 für alles, was abgedeckt warm bleibt (gebratene Pilze,",
  "glasierte Birnen, Sauce, Gemüse in Sahne), -1 wenn es sich hält",
  "(Geschnittenes, Kaltes, Geröstetes, Öl).",
  "dependsOn: für jeden Schritt die Indizes (ab 0) aller Schritte, deren",
  "Ergebnis er braucht – Pflichtangabe. Meist ist das der vorige Schritt",
  "derselben Komponente; ein Misch- oder Füllschritt nennt alle Schritte,",
  "deren Teile hineinkommen; das Anrichten nennt den letzten Schritt jeder",
  "Komponente. Leer nur bei Schritten, die gleich zu Beginn starten",
  "können (waschen, schneiden, Graupen aufsetzen). Was nicht voneinander",
  "abhängt, darf nicht verkettet werden, auch nicht innerhalb einer",
  "Komponente: In 'Für die Wirsingrolle' werden Graupen, Blätter, Haut,",
  "Fleisch und Pilze unabhängig vorbereitet, erst die Füllung wartet auf",
  "sie. Nur frühere Indizes, keine Kreise.",
  "servings: für wie viele Personen, 0 wenn nicht genannt.",
  "ingredients: alle Zutaten des Rezepts, je eine mit name (ohne Menge),",
  "amount als Zahl (0, wenn keine Menge genannt ist, etwa bei Salz;",
  "'1-2 EL' → 1.5), unit wie im Rezept ('g', 'ml', 'EL', 'TL', 'Stück',",
  "'Zweig', leer bei bloßer Stückzahl), componentName wie bei den",
  "Schritten und note für Zusätze ('fein gewürfelt', 'zum Braten',",
  "'kalt'); Reihenfolge wie im Rezept, Dopplungen je Komponente getrennt",
  "lassen. ingredientIndices: je Schritt die Indizes (ab 0) der Zutaten,",
  "die in diesem Schritt in die Hand genommen werden – Schneiden,",
  "Zugeben, Würzen, Anrichten; leer, wenn keine.",
  "Der Titel ist der Name des Gerichts ohne Autorenzusatz ('… von …').",
  "Erfinde keine Zutaten, Zeiten oder Schritte; notiere Unklares in",
  "warnings.",
];

/**
 * Structures a cooking recipe into CookPlanner's work steps. Same guards
 * as the recipe analysis: a signed-in user, App Check, the hourly limit
 * and — unless the app is exempt — the monthly allowance.
 */
export const analyzeDishSteps = onCall(
  {
    enforceAppCheck: true,
    timeoutSeconds: 240,
    memory: "1GiB",
    maxInstances: 2,
  },
  async (request) => {
    const startedAt = Date.now();
    const uid = request.auth?.uid;
    if (!uid) {
      throw new HttpsError(
        "unauthenticated",
        "Für die Rezeptanalyse ist eine Anmeldung erforderlich.",
      );
    }

    const text = validateText(request.data?.text);
    const allowance = await enforceRateLimit(uid, request.data,
      request.app?.appId);

    const parts = [
      {
        text: [
          ...dishRules,
          "\n\nREZEPT:\n",
          text,
        ].join(" "),
      },
    ];

    // Two attempts of at most 100 s each fit into the 240 s deadline.
    const generated = await generateRecipe(parts,
      {textLength: text.length, startedAt}, dishSchema, "Dish", 100_000);
    return {
      dish: generated.recipe,
      model: generated.model,
      ...allowance,
    };
  },
);

type RecipeAnalysisMetrics = {
  imageCount?: number;
  textLength?: number;
  startedAt: number;
};

/**
 * Sends the prepared prompt parts to Gemini and returns the schema-bound
 * answer. Shared by the image, the web page and the dish analysis.
 * @param {object[]} parts Prompt parts in Gemini's content format.
 * @param {RecipeAnalysisMetrics} metrics Values for the completion log.
 * @param {object} schema The response schema; the recipe's by default.
 * @param {string} label What the log calls the analysis.
 * @param {number} timeoutMs Optional limit per attempt in milliseconds.
 * @return {Promise<object>} The answer together with the model name.
 */
async function generateRecipe(
  parts: object[],
  metrics: RecipeAnalysisMetrics,
  schema: object = recipeSchema,
  label = "Recipe",
  timeoutMs?: number,
): Promise<{recipe: unknown; model: string}> {
  const project = process.env.GCLOUD_PROJECT ??
    process.env.GOOGLE_CLOUD_PROJECT;
  if (!project) {
    throw new HttpsError("internal", "Firebase-Projekt nicht verfügbar.");
  }

  const ai = new GoogleGenAI({vertexai: true, project, location: "eu"});
  // The model occasionally stops mid-answer or does not answer at all (a
  // dish with many steps came back as an unterminated string once, one
  // request ran into the function's deadline); a second try usually
  // succeeds, so a failed first attempt is repeated while enough of the
  // deadline is left.
  const attempts = 2;
  const retryBefore = 150_000;
  for (let attempt = 1; attempt <= attempts; attempt++) {
    try {
      const response = await ai.models.generateContent({
        model: "gemini-3.8-flash",
        contents: [{role: "user", parts}],
        config: {
          responseMimeType: "application/json",
          responseSchema: schema,
          maxOutputTokens: 16384,
          httpOptions: timeoutMs ? {timeout: timeoutMs} : undefined,
        },
      });
      if (!response.text) {
        throw new Error("Gemini returned no text response.");
      }
      const recipe = JSON.parse(response.text);
      console.info(`${label} analysis completed`, {
        imageCount: metrics.imageCount,
        textLength: metrics.textLength,
        attempt,
        durationMilliseconds: Date.now() - metrics.startedAt,
      });
      return {recipe, model: "gemini-3.8-flash"};
    } catch (error) {
      const elapsed = Date.now() - metrics.startedAt;
      if (attempt < attempts && elapsed < retryBefore) {
        console.warn(`${label} analysis failed, trying again`,
          {error: String(error), elapsed});
        continue;
      }
      console.error(`${label} analysis failed`, error);
      throw new HttpsError(
        "internal",
        "Das Rezept konnte momentan nicht analysiert werden.",
      );
    }
  }
  throw new HttpsError(
    "internal",
    "Das Rezept konnte momentan nicht analysiert werden.",
  );
}

const maxTextCharacters = 60_000;
const minTextCharacters = 40;

/**
 * Bounds the page text before it reaches the paid model.
 * @param {unknown} value Untrusted callable payload.
 * @return {string} The validated text.
 */
function validateText(value: unknown): string {
  if (typeof value !== "string") {
    throw new HttpsError("invalid-argument", "Es wurde kein Text übermittelt.");
  }
  const text = value.trim();
  if (text.length < minTextCharacters) {
    throw new HttpsError(
      "invalid-argument",
      "Der übermittelte Text ist zu kurz für ein Rezept.",
    );
  }
  if (text.length > maxTextCharacters) {
    throw new HttpsError(
      "invalid-argument",
      `Der Text darf höchstens ${maxTextCharacters} Zeichen lang sein.`,
    );
  }
  return text;
}

/**
 * Accepts an optional http(s) source address for the prompt and the log.
 * @param {unknown} value Untrusted callable payload.
 * @return {string | undefined} The address, or undefined when absent.
 */
function validateSourceURL(value: unknown): string | undefined {
  if (value === undefined || value === null || value === "") {
    return undefined;
  }
  if (typeof value !== "string" || value.length > 2_048) {
    throw new HttpsError("invalid-argument", "Ungültige Quelladresse.");
  }
  try {
    const url = new URL(value);
    if (url.protocol !== "https:" && url.protocol !== "http:") {
      throw new Error("unsupported protocol");
    }
    return url.toString();
  } catch {
    throw new HttpsError("invalid-argument", "Ungültige Quelladresse.");
  }
}

/**
 * Validates and bounds image data before it reaches the paid model.
 * @param {unknown} value Untrusted callable payload.
 * @return {RecipeImage[]} Validated images.
 */
function validateImages(value: unknown): RecipeImage[] {
  if (!Array.isArray(value) ||
      value.length === 0 ||
      value.length > maxImageCount) {
    throw new HttpsError(
      "invalid-argument",
      `Es müssen 1 bis ${maxImageCount} Bilder übermittelt werden.`,
    );
  }

  let totalBytes = 0;
  return value.map((item) => {
    if (!item || typeof item !== "object") {
      throw new HttpsError("invalid-argument", "Ungültige Bilddaten.");
    }
    const candidate = item as Record<string, unknown>;
    const data = candidate.data;
    const mimeType = candidate.mimeType;
    if (typeof data !== "string" ||
        (mimeType !== "image/jpeg" && mimeType !== "image/png")) {
      throw new HttpsError("invalid-argument", "Ungültiges Bildformat.");
    }

    const byteCount = Buffer.byteLength(data, "base64");
    if (byteCount === 0 || byteCount > maxImageBytes) {
      throw new HttpsError(
        "invalid-argument",
        "Ein Bild ist leer oder größer als 3 MB.",
      );
    }
    totalBytes += byteCount;
    if (totalBytes > maxTotalBytes) {
      throw new HttpsError(
        "invalid-argument",
        "Die Bilder sind zusammen größer als 15 MB.",
      );
    }
    return {data, mimeType};
  });
}

/** Verified Pro claims are remembered this long before being re-checked. */
const proVerificationValidMilliseconds = 7 * 24 * 60 * 60 * 1000;

let appleVerifier: ProVerifier | undefined;

/**
 * Whether this installation has BakePlanner Pro — decided from what the
 * app sends (see proVerification.ts), never from its word alone. A claim
 * that was verified recently is recognised by its hash in the user's
 * `aiRateLimits` document, so the signature check runs about once a week
 * per installation rather than on every import.
 * @param {string} uid Authenticated Firebase user ID.
 * @param {unknown} data Untrusted callable payload.
 * @param {MonetizationLimits} limits The switches in force.
 * @return {Promise<boolean>} True only for a verified purchase or a
 * verified grandfathered installation.
 */
async function resolvePro(
  uid: string,
  data: unknown,
  limits: MonetizationLimits,
): Promise<boolean> {
  const claim = readProClaim(data);
  if (!hasProClaim(claim)) return false;

  const hash = proClaimHash(claim);
  const reference = getFirestore().collection("aiRateLimits").doc(uid);
  const snapshot = await reference.get();
  const verifiedAt = snapshot.get("proVerifiedAt") as Timestamp | undefined;
  if (snapshot.get("proClaimHash") === hash && verifiedAt &&
      Date.now() - verifiedAt.toMillis() < proVerificationValidMilliseconds) {
    return true;
  }

  appleVerifier ??= makeAppleVerifier();
  const decision = await decidePro(claim, {
    verifier: appleVerifier,
    grandfatherBeforeBuild: limits.grandfatherBeforeBuild,
  });
  console.info("Pro claim decided", {isPro: decision.isPro,
    reason: decision.reason});
  if (decision.isPro) {
    await reference.set(
      {proClaimHash: hash, proVerifiedAt: Timestamp.now()}, {merge: true});
  }
  return decision.isPro;
}

/** How many imports a month the app may make without Pro; 0 = no limit. */
type MonetizationLimits = {
  freeImportsPerMonth: number;
  /** Installations first downloaded before this build count as Pro. */
  grandfatherBeforeBuild?: string;
};

let cachedLimits: {value: MonetizationLimits; readAt: number} | undefined;
const limitsCacheMilliseconds = 60 * 1000;

/**
 * Reads the Pro switches from `config/monetization` — the same document the
 * app reads, so both switch together. Cached for a minute per instance; a
 * missing document or a failed read means "no monthly limit", as in the app.
 * @return {Promise<MonetizationLimits>} The limits in force.
 */
async function readMonetizationLimits(): Promise<MonetizationLimits> {
  if (cachedLimits &&
      Date.now() - cachedLimits.readAt < limitsCacheMilliseconds) {
    return cachedLimits.value;
  }
  const value: MonetizationLimits = {freeImportsPerMonth: 0};
  try {
    const snapshot = await getFirestore().doc("config/monetization").get();
    const raw = snapshot.get("freeImportsPerMonth");
    if (typeof raw === "number" && Number.isFinite(raw) && raw > 0) {
      value.freeImportsPerMonth = Math.floor(raw);
    }
    const build = snapshot.get("grandfatherBeforeBuild");
    if (typeof build === "string" && build.length > 0) {
      value.grandfatherBeforeBuild = build;
    } else if (typeof build === "number" && Number.isFinite(build)) {
      value.grandfatherBeforeBuild = String(build);
    }
  } catch (error) {
    console.error("Monetization config could not be read", error);
  }
  cachedLimits = {value, readAt: Date.now()};
  return value;
}

/**
 * The calendar month of `timestamp` as "YYYY-MM", in UTC: the key under which
 * the monthly imports are counted.
 * @param {Timestamp} timestamp The moment.
 * @return {string} The month key.
 */
function monthKey(timestamp: Timestamp): string {
  return timestamp.toDate().toISOString().slice(0, 7);
}

/**
 * The Firebase app IDs (App Check) of the apps that are exempt from the
 * monthly allowance: the Android app, which has no purchase yet — Play
 * Billing comes with the Pro switch for both platforms (see
 * docs/Pro-Einfuehrung.md) — and CookPlanner. The hourly limit applies to
 * them all the same.
 */
export const appIdsWithoutMonthlyLimit = new Set([
  "1:936649524074:android:b46e983de39481f7d65b13",
  // CookPlanner (iOS): no purchase of its own yet.
  "1:936649524074:ios:73d0fac7786ca027d65b13",
]);

/**
 * What the response tells the app about its free imports: how many it has
 * used this month and how many it gets. Empty for Pro, for the exempt apps
 * and while no monthly limit is set — then nothing is worth saying.
 */
export type ImportAllowance = {
  freeImports?: {used: number; limit: number};
};

/**
 * The monthly limit for one caller: the configured allowance, unless the
 * caller has Pro, comes from an exempt app, or no allowance is set.
 * @param {number} freeImportsPerMonth The configured allowance; 0 = none.
 * @param {boolean} hasPro Whether the caller's Pro claim was verified.
 * @param {string | undefined} appId The caller's Firebase app ID.
 * @return {number} The limit to enforce; 0 means unlimited.
 */
export function monthlyLimitFor(
  freeImportsPerMonth: number,
  hasPro: boolean,
  appId: string | undefined,
): number {
  if (freeImportsPerMonth <= 0 || hasPro) return 0;
  if (appId && appIdsWithoutMonthlyLimit.has(appId)) return 0;
  return freeImportsPerMonth;
}

/**
 * Applies the per-user limits backed by Firestore: a rolling hourly limit
 * for everyone, and — once `config/monetization` sets one — a monthly
 * allowance of free imports for installations without Pro. Both live in the
 * user's `aiRateLimits` document.
 * @param {string} uid Authenticated Firebase user ID.
 * @param {unknown} data The callable payload, carrying the Pro claim.
 * @param {string | undefined} appId The caller's Firebase app ID from App
 * Check, to exempt the apps that cannot buy Pro yet.
 * @return {Promise<ImportAllowance>} What to tell the app about its
 * remaining free imports, counting this one.
 */
async function enforceRateLimit(
  uid: string,
  data: unknown,
  appId: string | undefined,
): Promise<ImportAllowance> {
  const database = getFirestore();
  const reference = database.collection("aiRateLimits").doc(uid);
  const now = Timestamp.now();
  const hourInMilliseconds = 60 * 60 * 1000;
  const limits = await readMonetizationLimits();
  const exempt = appId !== undefined && appIdsWithoutMonthlyLimit.has(appId);
  // Pro only matters while a monthly limit is set; without one nobody
  // needs to prove anything, and no signature is checked.
  const hasPro = limits.freeImportsPerMonth > 0 && !exempt &&
    await resolvePro(uid, data, limits);
  const monthlyLimit = monthlyLimitFor(limits.freeImportsPerMonth, hasPro,
    appId);
  const month = monthKey(now);

  return database.runTransaction(async (transaction) => {
    const snapshot = await transaction.get(reference);
    const windowStartedAt = snapshot.get("windowStartedAt") as
      Timestamp | undefined;
    const count = snapshot.get("count") as number | undefined;
    const windowExpired = !windowStartedAt ||
      now.toMillis() - windowStartedAt.toMillis() >= hourInMilliseconds;

    if (!windowExpired && (count ?? 0) >= hourlyRequestLimit) {
      throw new HttpsError(
        "resource-exhausted",
        "Das stündliche Analyse-Limit wurde erreicht.",
        {reason: "hourly-limit"},
      );
    }

    // The month's count: a new month starts at zero.
    const storedMonth = snapshot.get("month") as string | undefined;
    const monthCount = storedMonth === month ?
      (snapshot.get("monthCount") as number | undefined) ?? 0 :
      0;

    if (monthlyLimit > 0 && monthCount >= monthlyLimit) {
      throw new HttpsError(
        "resource-exhausted",
        "Die kostenlosen Importe dieses Monats sind aufgebraucht.",
        {reason: "monthly-limit", limit: monthlyLimit},
      );
    }

    // Merge: the document also remembers the verified Pro claim.
    transaction.set(reference, {
      windowStartedAt: windowExpired ? now : windowStartedAt,
      count: windowExpired ? 1 : (count ?? 0) + 1,
      month,
      monthCount: monthCount + 1,
    }, {merge: true});

    const allowance: ImportAllowance = {};
    if (monthlyLimit > 0) {
      allowance.freeImports = {used: monthCount + 1, limit: monthlyLimit};
    }
    return allowance;
  });
}
