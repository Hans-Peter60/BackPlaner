// The monthly limit per caller: who gets the allowance, who is exempt.
//
//     cd functions && npm test

import {test} from "node:test";
import assert from "node:assert/strict";
import {appIdsWithoutMonthlyLimit, monthlyLimitFor} from "../lib/index.js";

const android = [...appIdsWithoutMonthlyLimit][0];
const iphone = "1:936649524074:ios:2f737f317cf14538d65b13";

test("without a configured allowance nobody is limited", () => {
  assert.equal(monthlyLimitFor(0, false, iphone), 0);
  assert.equal(monthlyLimitFor(0, false, undefined), 0);
});

test("the iPhone without Pro gets the allowance", () => {
  assert.equal(monthlyLimitFor(5, false, iphone), 5);
  assert.equal(monthlyLimitFor(5, false, undefined), 5);
});

test("a verified Pro purchase lifts the limit", () => {
  assert.equal(monthlyLimitFor(5, true, iphone), 0);
});

test("the Android app is exempt while it cannot buy Pro", () => {
  assert.equal(monthlyLimitFor(5, false, android), 0);
});
