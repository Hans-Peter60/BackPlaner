import {setGlobalOptions} from "firebase-functions";
import {HttpsError, onCall} from "firebase-functions/v2/https";
import {initializeApp} from "firebase-admin/app";
import {getFirestore, Timestamp} from "firebase-admin/firestore";
import {GoogleGenAI} from "@google/genai";

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
    await enforceRateLimit(uid);

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

    return generateRecipe(parts, {
      imageCount: images.length,
      startedAt,
    });
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
    await enforceRateLimit(uid);

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

    return generateRecipe(parts, {
      textLength: text.length,
      startedAt,
    });
  },
);

type RecipeAnalysisMetrics = {
  imageCount?: number;
  textLength?: number;
  startedAt: number;
};

/**
 * Sends the prepared prompt parts to Gemini and returns the schema-bound
 * recipe. Shared by the image and the web page analysis.
 * @param {object[]} parts Prompt parts in Gemini's content format.
 * @param {RecipeAnalysisMetrics} metrics Values for the completion log.
 * @return {Promise<object>} The recipe together with the model name.
 */
async function generateRecipe(
  parts: object[],
  metrics: RecipeAnalysisMetrics,
): Promise<{recipe: unknown; model: string}> {
  const project = process.env.GCLOUD_PROJECT ??
    process.env.GOOGLE_CLOUD_PROJECT;
  if (!project) {
    throw new HttpsError("internal", "Firebase-Projekt nicht verfügbar.");
  }

  const ai = new GoogleGenAI({vertexai: true, project, location: "eu"});
  try {
    const response = await ai.models.generateContent({
      model: "gemini-3.8-flash",
      contents: [{role: "user", parts}],
      config: {
        responseMimeType: "application/json",
        responseSchema: recipeSchema,
        maxOutputTokens: 8192,
      },
    });
    if (!response.text) {
      throw new Error("Gemini returned no text response.");
    }

    const recipe = JSON.parse(response.text);
    console.info("Recipe analysis completed", {
      imageCount: metrics.imageCount,
      textLength: metrics.textLength,
      durationMilliseconds: Date.now() - metrics.startedAt,
    });
    return {recipe, model: "gemini-3.8-flash"};
  } catch (error) {
    console.error("Recipe analysis failed", error);
    throw new HttpsError(
      "internal",
      "Das Rezept konnte momentan nicht analysiert werden.",
    );
  }
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

/**
 * Applies a per-user rolling hourly request limit backed by Firestore.
 * @param {string} uid Authenticated Firebase user ID.
 */
async function enforceRateLimit(uid: string): Promise<void> {
  const database = getFirestore();
  const reference = database.collection("aiRateLimits").doc(uid);
  const now = Timestamp.now();
  const hourInMilliseconds = 60 * 60 * 1000;

  await database.runTransaction(async (transaction) => {
    const snapshot = await transaction.get(reference);
    const windowStartedAt = snapshot.get("windowStartedAt") as
      Timestamp | undefined;
    const count = snapshot.get("count") as number | undefined;
    const windowExpired = !windowStartedAt ||
      now.toMillis() - windowStartedAt.toMillis() >= hourInMilliseconds;

    if (windowExpired) {
      transaction.set(reference, {windowStartedAt: now, count: 1});
      return;
    }
    if ((count ?? 0) >= hourlyRequestLimit) {
      throw new HttpsError(
        "resource-exhausted",
        "Das stündliche Analyse-Limit wurde erreicht.",
      );
    }
    transaction.update(reference, {count: (count ?? 0) + 1});
  });
}
