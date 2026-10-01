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

    const project = process.env.GCLOUD_PROJECT ??
      process.env.GOOGLE_CLOUD_PROJECT;
    if (!project) {
      throw new HttpsError("internal", "Firebase-Projekt nicht verfügbar.");
    }

    const ai = new GoogleGenAI({vertexai: true, project, location: "eu"});
    const parts = [
      {
        text: [
          "Analysiere alle Bilder gemeinsam als ein vollständiges Backrezept.",
          "Die Seiten stehen in der übermittelten Reihenfolge.",
          "Übernimm ausschließlich lesbare Angaben aus den Bildern.",
          "Erfinde keine Zutaten, Mengen, Zeiten, Temperaturen oder Schritte.",
          "Bewahre die Originalsprache und trenne Sauerteig, Vorteig,",
          "Brühstück",
          "und Hauptteig in eigene Komponenten.",
          "Erzeuge für jede eigenständige Tätigkeit und jede Wartephase einen",
          "separaten Arbeitsschritt, auch wenn sie im Bild im selben Absatz",
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
          "genannte Temperatur. Wenn keine Vorheizdauer gedruckt ist, bleibt",
          "durationMinutes 0; die App setzt dann ihre konfigurierte",
          "Vorheizzeit.",
          "Nutze 0 oder eine leere Zeichenfolge für fehlende Werte und notiere",
          "unleserliche oder widersprüchliche Stellen in warnings.",
        ].join(" "),
      },
      ...images.map((image) => ({
        inlineData: {data: image.data, mimeType: image.mimeType},
      })),
    ];

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
        imageCount: images.length,
        durationMilliseconds: Date.now() - startedAt,
      });
      return {recipe, model: "gemini-3.8-flash"};
    } catch (error) {
      console.error("Recipe analysis failed", error);
      throw new HttpsError(
        "internal",
        "Das Rezept konnte momentan nicht analysiert werden.",
      );
    }
  },
);

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
