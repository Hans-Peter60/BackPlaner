// The Pro decision in every combination, against a stub verifier: what
// Apple's library would return after a successful signature check, or the
// failure it would throw. The signature check itself is Apple's code and
// needs Apple-signed data, so it is not exercised here.
//
//     cd functions && npm test

import {test} from "node:test";
import assert from "node:assert/strict";
import {
  compareBuilds,
  decidePro,
  hasProClaim,
  proClaimHash,
  readProClaim,
} from "../lib/proVerification.js";

const jws = (label) => `${label}.payload.signature`;

/** A verifier answering with fixed payloads, or throwing. */
function stubVerifier({transaction, appTransaction} = {}) {
  return {
    verifyTransaction: async () => {
      if (transaction instanceof Error) throw transaction;
      return transaction;
    },
    verifyAppTransaction: async () => {
      if (appTransaction instanceof Error) throw appTransaction;
      return appTransaction;
    },
  };
}

const validPurchase = {
  bundleId: "de.hpm64625.BackPlaner",
  productId: "de.hpm64625.BackPlaner.pro",
  type: "Non-Consumable",
};

test("readProClaim keeps plausible JWS strings and drops the rest", () => {
  const claim = readProClaim({
    proTransaction: jws("tx"),
    proAppTransaction: "not a jws",
    images: [],
  });
  assert.equal(claim.transaction, jws("tx"));
  assert.equal(claim.appTransaction, undefined);
  assert.ok(hasProClaim(claim));

  assert.deepEqual(readProClaim(null), {});
  assert.deepEqual(readProClaim({pro: true}), {});
  assert.ok(!hasProClaim(readProClaim({pro: true})));
  assert.deepEqual(readProClaim({proTransaction: "a".repeat(40_000)}), {});
});

test("the claim hash covers the whole signed data", () => {
  const a = proClaimHash({transaction: jws("one")});
  const b = proClaimHash({transaction: jws("two")});
  const c = proClaimHash({appTransaction: jws("one")});
  assert.notEqual(a, b);
  assert.notEqual(a, c);
  assert.equal(a, proClaimHash({transaction: jws("one")}));
});

test("builds compare as numbers, segment by segment", () => {
  assert.ok(compareBuilds("9", "10") < 0);
  assert.ok(compareBuilds("100", "10") > 0);
  assert.ok(compareBuilds("1.0", "10") < 0);
  assert.equal(compareBuilds("8", "8"), 0);
});

test("a verified, unrevoked purchase of the Pro product is Pro", async () => {
  const decision = await decidePro({transaction: jws("tx")}, {
    verifier: stubVerifier({transaction: validPurchase}),
  });
  assert.deepEqual(decision, {isPro: true, reason: "purchase"});
});

test("a purchase of another product or app is not Pro", async () => {
  const otherProduct = await decidePro({transaction: jws("tx")}, {
    verifier: stubVerifier({
      transaction: {...validPurchase, productId: "com.example.other"},
    }),
  });
  assert.equal(otherProduct.isPro, false);

  const otherApp = await decidePro({transaction: jws("tx")}, {
    verifier: stubVerifier({
      transaction: {...validPurchase, bundleId: "com.example.app"},
    }),
  });
  assert.equal(otherApp.isPro, false);
});

test("a refunded purchase is not Pro", async () => {
  const decision = await decidePro({transaction: jws("tx")}, {
    verifier: stubVerifier({
      transaction: {...validPurchase, revocationDate: 1_700_000_000_000},
    }),
  });
  assert.deepEqual(decision, {isPro: false, reason: "transaction: revoked"});
});

test("a signature that does not verify is not Pro, and does not throw",
  async () => {
    const decision = await decidePro({transaction: jws("forged")}, {
      verifier: stubVerifier({transaction: new Error("bad signature")}),
    });
    assert.equal(decision.isPro, false);
    assert.match(decision.reason, /bad signature/);
  });

test("an installation from before the threshold build is grandfathered",
  async () => {
    const verifier = stubVerifier({
      appTransaction: {
        bundleId: "de.hpm64625.BackPlaner",
        originalApplicationVersion: "8",
      },
    });
    const old = await decidePro({appTransaction: jws("app")}, {
      verifier, grandfatherBeforeBuild: "10",
    });
    assert.deepEqual(old, {isPro: true, reason: "grandfathered"});

    const atThreshold = await decidePro({appTransaction: jws("app")}, {
      verifier: stubVerifier({
        appTransaction: {
          bundleId: "de.hpm64625.BackPlaner",
          originalApplicationVersion: "10",
        },
      }),
      grandfatherBeforeBuild: "10",
    });
    assert.equal(atThreshold.isPro, false);

    const noThreshold = await decidePro({appTransaction: jws("app")}, {
      verifier,
    });
    assert.equal(noThreshold.isPro, false);
  });

test("the purchase is checked before the app transaction", async () => {
  const decision = await decidePro(
    {transaction: jws("tx"), appTransaction: jws("app")},
    {
      verifier: stubVerifier({
        transaction: {...validPurchase, productId: "other"},
        appTransaction: {
          bundleId: "de.hpm64625.BackPlaner",
          originalApplicationVersion: "1",
        },
      }),
      grandfatherBeforeBuild: "10",
    },
  );
  // A wrong product is a definite "no": the app transaction is not
  // consulted as a fallback for a claim that already failed.
  assert.equal(decision.isPro, false);
});

test("an empty claim is not Pro", async () => {
  const decision = await decidePro({}, {verifier: stubVerifier()});
  assert.deepEqual(decision, {isPro: false, reason: "no claim"});
});
