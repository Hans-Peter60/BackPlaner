// Verifies that an installation really has BakePlanner Pro before the
// monthly allowance of free cloud imports is waived for it.
//
// The app sends what StoreKit gave it: the signed transaction of the Pro
// purchase (JWS), or — for an installation from before Pro existed — the
// signed AppTransaction, whose originalApplicationVersion is the build the
// app was first downloaded as. Both are signed by Apple, so the server can
// check the signature chain against Apple's root certificates and then
// read the payload without trusting the app at all.
//
// Only the Production and Sandbox environments are accepted. A JWS from the
// Xcode environment (StoreKit configuration file in the simulator) carries
// no Apple signature and could be forged by anyone, so it never counts.

import {createHash} from "crypto";
import {readFileSync} from "fs";
import {join} from "path";
import {
  AppTransaction,
  Environment,
  JWSTransactionDecodedPayload,
  SignedDataVerifier,
  VerificationException,
  VerificationStatus,
} from "@apple/app-store-server-library";

export const bundleId = "de.hpm64625.BackPlaner";
/** The app's Apple ID in App Store Connect (BakePlanner). */
export const appAppleId = 6810684679;
/** The non-consumable product, as in ProStore.productID. */
export const proProductId = "de.hpm64625.BackPlaner.pro";

/** A JWS is a few kilobytes; anything far beyond that is not one. */
const maxJWSLength = 32_000;

/** What the app sends along with an import to say it has Pro. */
export type ProClaim = {
  /** The signed transaction of the Pro purchase. */
  transaction?: string;
  /** The signed AppTransaction, for grandfathering. */
  appTransaction?: string;
};

/**
 * Reads the Pro claim out of the untrusted callable payload. Anything that
 * is not a plausible JWS string is dropped silently: a malformed claim
 * only means "no Pro", never an error for the import itself.
 * @param {unknown} data The callable payload.
 * @return {ProClaim} The claim, possibly empty.
 */
export function readProClaim(data: unknown): ProClaim {
  const claim: ProClaim = {};
  if (typeof data !== "object" || data === null) return claim;
  const body = data as {proTransaction?: unknown; proAppTransaction?: unknown};
  if (isPlausibleJWS(body.proTransaction)) {
    claim.transaction = body.proTransaction;
  }
  if (isPlausibleJWS(body.proAppTransaction)) {
    claim.appTransaction = body.proAppTransaction;
  }
  return claim;
}

/**
 * @param {unknown} value A candidate.
 * @return {boolean} Whether it looks like a compact JWS (three base64url
 * parts).
 */
function isPlausibleJWS(value: unknown): value is string {
  return typeof value === "string" &&
    value.length > 0 &&
    value.length <= maxJWSLength &&
    /^[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+$/.test(value);
}

/**
 * Whether the claim carries anything worth verifying.
 * @param {ProClaim} claim The claim.
 * @return {boolean} True when a transaction or an app transaction is present.
 */
export function hasProClaim(claim: ProClaim): boolean {
  return claim.transaction !== undefined || claim.appTransaction !== undefined;
}

/**
 * A stable fingerprint of the claim, so a claim verified once can be
 * recognised again without repeating the signature check. The hash covers
 * the complete signed data: a different JWS with the same transaction id
 * would hash differently and be verified afresh.
 * @param {ProClaim} claim The claim.
 * @return {string} A hex SHA-256.
 */
export function proClaimHash(claim: ProClaim): string {
  return createHash("sha256")
    .update(claim.transaction ?? "")
    .update("\n")
    .update(claim.appTransaction ?? "")
    .digest("hex");
}

/**
 * Compares two build numbers the way the app does (`.numeric`): segment by
 * segment as numbers, so "9" sorts before "10" and "1.0" before "2".
 * @param {string} a A build number.
 * @param {string} b Another.
 * @return {number} Negative when a < b, zero when equal, positive when a > b.
 */
export function compareBuilds(a: string, b: string): number {
  const left = a.split(".").map((part) => parseInt(part, 10) || 0);
  const right = b.split(".").map((part) => parseInt(part, 10) || 0);
  const length = Math.max(left.length, right.length);
  for (let index = 0; index < length; index++) {
    const difference = (left[index] ?? 0) - (right[index] ?? 0);
    if (difference !== 0) return difference;
  }
  return 0;
}

/** The two verifications the decision needs; Apple's library behind it. */
export interface ProVerifier {
  verifyTransaction(jws: string): Promise<JWSTransactionDecodedPayload>;
  verifyAppTransaction(jws: string): Promise<AppTransaction>;
}

/**
 * Apple's root certificates, shipped with the Functions (functions/certs,
 * downloaded from apple.com/certificateauthority). Both roots are needed:
 * App Store signatures chain to either.
 * @return {Buffer[]} The DER-encoded certificates.
 */
export function loadAppleRootCertificates(): Buffer[] {
  const directory = join(__dirname, "..", "certs");
  return ["AppleRootCA-G3.cer", "AppleIncRootCertificate.cer"]
    .map((name) => readFileSync(join(directory, name)));
}

/**
 * A verifier that accepts Production first and Sandbox second (TestFlight
 * and sandbox testers), each with Apple's full signature and revocation
 * checks. The library ties a verifier to one environment and rejects the
 * other with INVALID_ENVIRONMENT, so the two are tried in turn.
 * @param {Buffer[]} roots Apple's root certificates.
 * @return {ProVerifier} The verifier.
 */
export function makeAppleVerifier(
  roots: Buffer[] = loadAppleRootCertificates(),
): ProVerifier {
  const verifiers = [
    new SignedDataVerifier(
      roots, true, Environment.PRODUCTION, bundleId, appAppleId),
    new SignedDataVerifier(roots, true, Environment.SANDBOX, bundleId),
  ];

  const tryEach = async <T>(
    attempt: (verifier: SignedDataVerifier) => Promise<T>,
  ): Promise<T> => {
    let lastError: unknown;
    for (const verifier of verifiers) {
      try {
        return await attempt(verifier);
      } catch (error) {
        lastError = error;
        const wrongEnvironment = error instanceof VerificationException &&
          error.status === VerificationStatus.INVALID_ENVIRONMENT;
        if (!wrongEnvironment) throw error;
      }
    }
    throw lastError;
  };

  return {
    verifyTransaction: (jws) =>
      tryEach((verifier) => verifier.verifyAndDecodeTransaction(jws)),
    verifyAppTransaction: (jws) =>
      tryEach((verifier) => verifier.verifyAndDecodeAppTransaction(jws)),
  };
}

export type ProDecision = {
  isPro: boolean;
  /** For the log: "purchase", "grandfathered", or why not. */
  reason: string;
};

/**
 * Decides whether the claim proves Pro: a verified, unrevoked purchase of
 * the Pro product for this app, or a verified AppTransaction whose first
 * build lies before `grandfatherBeforeBuild`. Verification failures are
 * reported as "not Pro" with the reason; they never throw, because the
 * import must go on (under the monthly limit) whatever the claim says.
 * @param {ProClaim} claim The claim.
 * @param {object} options The verifier and the grandfathering threshold.
 * @return {Promise<ProDecision>} The decision.
 */
export async function decidePro(
  claim: ProClaim,
  options: {verifier: ProVerifier; grandfatherBeforeBuild?: string},
): Promise<ProDecision> {
  if (claim.transaction) {
    try {
      const transaction = await options.verifier
        .verifyTransaction(claim.transaction);
      if (transaction.bundleId !== bundleId) {
        return {isPro: false, reason: "transaction: wrong bundle"};
      }
      if (transaction.productId !== proProductId) {
        return {isPro: false, reason: "transaction: wrong product"};
      }
      if (transaction.revocationDate !== undefined &&
          transaction.revocationDate !== null) {
        return {isPro: false, reason: "transaction: revoked"};
      }
      return {isPro: true, reason: "purchase"};
    } catch (error) {
      return {isPro: false, reason: `transaction: ${describe(error)}`};
    }
  }

  if (claim.appTransaction) {
    const threshold = options.grandfatherBeforeBuild;
    if (!threshold) {
      return {isPro: false, reason: "appTransaction: no grandfathering"};
    }
    try {
      const appTransaction = await options.verifier
        .verifyAppTransaction(claim.appTransaction);
      if (appTransaction.bundleId !== bundleId) {
        return {isPro: false, reason: "appTransaction: wrong bundle"};
      }
      const original = appTransaction.originalApplicationVersion;
      if (!original) {
        return {isPro: false, reason: "appTransaction: no original version"};
      }
      if (compareBuilds(original, threshold) < 0) {
        return {isPro: true, reason: "grandfathered"};
      }
      return {isPro: false, reason: "appTransaction: too recent"};
    } catch (error) {
      return {isPro: false, reason: `appTransaction: ${describe(error)}`};
    }
  }

  return {isPro: false, reason: "no claim"};
}

/**
 * @param {unknown} error A thrown value.
 * @return {string} A short description for the log.
 */
function describe(error: unknown): string {
  if (error instanceof VerificationException) {
    return `verification ${VerificationStatus[error.status]}`;
  }
  return error instanceof Error ? error.message : String(error);
}
