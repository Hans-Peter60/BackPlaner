# Firebase Security Rules — BackPlaner

Security rules for the public recipe database (Firestore) and recipe images
(Cloud Storage). They lock down the previously open/test-mode project and
enforce the UGC moderation model (App Store Guideline 1.2).

## Files
- `firestore.rules` — recipe database + moderation `reports`
- `storage.rules` — recipe images
- `tests/` — checks `firestore.rules` in the Firestore emulator
  (`cd firebase/tests && npm ci && npm test`, needs Java; runs in the GitHub
  Action on every pull request)

## Prerequisite: Anonymous Authentication (required)

The rules enforce *"only the author may edit or delete their recipe"* using the
server-verified `request.auth.uid`. This is only trustworthy with a real
identity. The app currently stamps recipes with `identifierForVendor`, which the
server **cannot** verify — a client could send any `authorId`.

Enable **Anonymous Auth** (invisible, no login screen, compatible with the
"no login" decision):

1. Firebase console → **Authentication → Sign-in method → Anonymous → Enable**.
2. In the app, sign in anonymously at launch and use `Auth.auth().currentUser?.uid`
   as `ModerationStore.authorId` (small code change — ask Claude to wire it up).

> Without Anonymous Auth, ownership of edit/delete **cannot** be enforced
> server-side: allowing the author's delete would mean allowing anyone's delete.
> Keep App Check enabled either way to block non-app traffic.

## Admins / moderators (delete any recipe)

Admins may delete **any** public recipe (not just their own). The app offers
this in three places: the ⋯ menu on the recipe screen ("Rezept löschen
(Admin)"), the button at the bottom of its Details tab, and a swipe on the row
in the Rezept-Datenbank list. Each asks for confirmation first. An admin is any
user whose `auth.uid` has a document in the `admins` collection.

The Storage rules consult that same collection through a cross-service rule
(`firestore.exists(...)`), so the admin delete also removes the recipe image
under `images/<uid>/…`. The first deploy of that rule prompts to grant the
Storage service agent the Firestore read role — accept, otherwise every
`isAdmin()` evaluation in Storage fails and the image stays behind.

Admins sign in with **Sign in with Apple** (not the anonymous identity) so the
uid is **stable across reinstalls**. It is native (AuthenticationServices), needs
no extra SPM package, and avoids the GoogleSignIn/Firebase version conflicts.
Normal users stay anonymous and can still read and create recipes — only
deletion of others' recipes is admin-gated.

One-time project setup (needed once, by the developer):

1. Xcode → target **BackPlaner → Signing & Capabilities → + Capability →
   Sign in with Apple**. (The `com.apple.developer.applesignin` entitlement is
   already in `BackPlaner.entitlements`; the capability wires it into the App ID
   / provisioning profile under automatic signing.)
2. Firebase console → **Authentication → Sign-in method** → enable **Apple**
   (keep **Anonymous** enabled for normal users). No plist change or URL scheme
   is required.

Granting admin rights (per admin):

3. That person signs in once via **Einstellungen → Administrator →
   "Mit Apple anmelden"**, so their Apple **User UID** appears in Firebase
   console → **Authentication → Users**.
4. Create the document **`admins/<that uid>`** (contents don't matter;
   `{ "note": "owner" }` is fine) — either in the console (Firestore → collection
   **`admins`** → add a document whose **ID is that uid**) or with the script,
   which finds the uid itself and refuses anonymous ones:
   ```
   cd scripts && npm install firebase-admin   # once
   node grant-admin.mjs --key=<serviceAccount.json>                  # list Apple accounts, mark admins
   node grant-admin.mjs --key=<serviceAccount.json> --apple --commit # make the only Apple account admin
   node grant-admin.mjs --key=… --uid=<uid> --revoke --commit        # take the rights away again
   ```
   The key comes from Firebase console → Project settings → Service accounts →
   "Generate new private key"; `scripts/*.json` is git-ignored.
5. Reopen **Einstellungen** → the account section shows "Administrator", and a
   public recipe offers "Rezept löschen (Admin)". "Abmelden" returns to the
   anonymous identity.

If "Administrator" does not appear although the document exists, the app is
signed in under a different uid than the one in `admins`. That happens when the
Apple account already had a Firebase account of its own (second device,
reinstall): linking then fails and the app signs into that existing account.
Run the script without `--uid` to see every Apple account with its last sign-in
and grant the one that signed in most recently. The log line
`Admin check: uid=… isAdmin=…` (Console app, category *firebase*, with Action → Include Debug Messages) names the uid the
app actually checked; `Admin check failed` instead means the read of
`admins/<uid>` was refused, i.e. the deployed rules are older than this repo.

The rules restrict the `admins` collection to **console-only writes**; a client
may read only its *own* admin document.

## Sign in with Apple (voluntary)

Every cloud recipe is public, in the collection `Recipe` with its image under
`images/<uid>/…`. A recipe the user may not publish stays on the device, where
iCloud keeps it in sync.

Ownership is `authorId == request.auth.uid`. By default that uid is the
installation's anonymous identity. **Sign in with Apple** (Einstellungen →
Konto) replaces it with one that survives a reinstall and is the same on every
device, so the author can edit and delete their published recipes everywhere.
The anonymous identity is *linked* rather than replaced, so the uid — and
ownership of everything published before — survives the sign-in. Moderators
sign in the same way; a moderator is an account listed in `admins`.

### Retired: author-only recipes

While version 2.0 was being developed, a recipe could also be kept in the cloud
for its author alone (collection `PrivateRecipe`, images under
`privateImages/<uid>/…`, create only with a permanent account). That storage was
removed again before 2.0 shipped; the app neither reads nor writes the
collection, and the rules no longer grant any access to it. The documents still in the project (the developer's own, exported
and re-imported as local recipes on 2026-10-14) are kept until they are deleted
from the console. `scripts/migrate-public-to-private.mjs`, which once moved
public recipes there, went with the feature.

## Pro switches: `config/monetization`

BakePlanner Pro (the one-time purchase `de.hpm64625.BackPlaner.pro`) is built
into the app but **dormant until this document says otherwise**. The document
is read by every signed-in app (`allow read: if isSignedIn()`) and by the
Functions through the Admin SDK; no client can write it — it is edited only in
the console (Firestore → Data → `config` → `monetization`). Create it by hand;
while it does not exist, everything is free.

| Field | Type | Meaning | Free value |
|---|---|---|---|
| `proRequired` | boolean | Lock the Pro features (PDF export, recipe hand-over, recurring plans, shopping lists, widgets, Live Activity) for installations without Pro. | `false` |
| `storeVisible` | boolean | Show the Pro section in the settings and the paywall in the features. Lets the store be shown — for the App Review, for first purchases — before anything is locked. A buyer sees the section regardless. | `false` |
| `freeImportsPerMonth` | number | Cloud imports (photo and web page analysis) per month without Pro; `0` = no monthly limit. The hourly limit applies either way. | `0` |
| `grandfatherBeforeBuild` | string | Installations first downloaded as a build (CFBundleVersion) *below* this one count as Pro without a purchase. Compared against `AppTransaction.originalAppVersion`. Omit to grandfather nobody. | absent |

A missing field keeps its free value, so a typo cannot lock the app. The app
caches the last document it read in the App Group and starts from it; the
widget extension reads only the resolved decision (`entitlements.widgetsUnlocked`).

**How the Functions know who has Pro.** With a monthly limit set, a cloud
import carries the App Store's signed purchase (`proTransaction`, a JWS) or,
for a grandfathered installation, the signed AppTransaction
(`proAppTransaction`). `functions/src/proVerification.ts` verifies the
signature chain against Apple's root certificates in `functions/certs/`
(Production first, then Sandbox; the Xcode environment never counts) and
checks bundle id, product id, revocation and — for grandfathering —
`originalApplicationVersion` against `grandfatherBeforeBuild`. A claim that
verified is remembered by its SHA-256 in the user's `aiRateLimits` document
for a week (`proClaimHash`, `proVerifiedAt`). The app's Apple ID
(6810684679) and bundle id are constants in that file. `cd functions && npm
test` runs the decision logic against a stub verifier.

Suggested rollout, one field at a time:
1. Submit the app with the product approved in App Store Connect and the
   document absent (or all free). The review can see the store with
   `storeVisible: true`.
2. `storeVisible: true` — the store is offered, nothing is locked yet.
3. `grandfatherBeforeBuild: "<build of the first Pro version>"`, then
   `proRequired: true` — existing installations keep their features, new ones
   buy Pro.
4. `freeImportsPerMonth: 3` once the imports' cost warrants it.

Rolling back is the same edit in reverse; no app update is needed. The
`-UITestingMonetization` launch argument fixes the configuration for the UI
tests and screenshots so they never depend on what the console says.

## Deploy

**Console (quickest):**
- Firestore → *Rules* tab → paste `firestore.rules` → **Publish**.
- Storage → *Rules* tab → paste `storage.rules` → **Publish**.

**CLI (optional):**

`firebase.json` (repo root) and `.firebaserc` (project `back-planer`) are already
wired to these files, so from the repo root just run:
```
firebase deploy --only firestore:rules,storage
```
Note `storage` without `:rules` — Storage targets are buckets, so
`--only storage:rules` fails with *"Could not find rules for the following
storage targets: rules"*.

`firebase-tools` (v15.30.0) is installed and logged in as
`hp60.mueller@gmail.com`. Both rule files were deployed from here on
10.09.2026, 17:24, so the published rules match this repo as of `93d0798`.

The CLI has **no** command to read the *deployed* rules back, so "which version
is live" can only be answered in the console (Firestore → Rules → history) or
by deploying again — which is idempotent and therefore the cheaper answer.

It does **not** run on this Mac's default Node. `/usr/local/bin/node` is a
standalone v16.14 installation from 2022, and the CLI requires >= 20. Rather
than replace it — other projects may depend on that version — Node 22 sits
beside it as the Homebrew formula `node@22`, deliberately left *unlinked* so
`node` on the PATH stays v16. `/opt/homebrew/bin/firebase` is therefore not the
usual symlink but a wrapper that pins the interpreter:

```sh
exec /opt/homebrew/opt/node@22/bin/node \
     /opt/homebrew/lib/node_modules/firebase-tools/lib/bin/firebase.js "$@"
```

The `opt` path survives `brew unlink`, so the wrapper keeps working. If a
`brew upgrade` ever bumps node@22 to a new major, adjust the two paths above.
Symptom of a broken pin: *"Firebase CLI v15 is incompatible with Node.js
v16.14.0"*.

> If the **"Rezept löschen (Admin)"** button appears but deleting fails with
> *"Missing or insufficient permissions"*, the deployed `Recipe` delete rule is an
> older version without the `|| isAdmin()` branch — redeploy the current
> `firestore.rules` above and confirm the current admin's Apple **uid** has a
> document in the `admins` collection.

## Moderation workflow (App Store Guideline 1.2)

Reported content is taken down **immediately**, not within a review window — so
the 24-hour expectation is met by the system, not by how fast a human reacts.

1. A user reports a recipe (recipe screen → ⋯ → *Rezept melden*).
2. The app writes `reports/{recipeId}_{uid}` **and** sets `hidden: true` on the
   recipe document — exactly that one field, no Firestore sentinels, so the rule
   condition can be reproduced in the Rules Playground. From that moment the
   rules hand the recipe and its subcollections only to admins and its author;
   the app's list query asks for `hidden == false` and so no longer returns it.
   (The author can still open it by id, e.g. from a local copy, but cannot
   release it: his update rule keeps `hidden` unchanged.)
3. Each user can report a given recipe only once (deterministic report id +
   create-only rule), and a reporter can only ever *hide*, never unhide.
4. An admin opens the recipe (admins still see hidden ones) and either
   - deletes it permanently — *Rezept löschen (Admin)*, or
   - releases it again — *Rezept wieder freigeben* (`setRecipeHidden`).
5. Open reports are reviewed in the Firebase console
   (Firestore → `reports`, `status: "open"`). Keep handled reports as a record
   of the decision; do not delete them.

Still readable: the recipe's **image** in Storage. Its path does not contain
the recipe id, so the Storage rules cannot look up whether the recipe is
hidden. The path holds two random UUIDs and is listed only in the (withheld)
recipe document.

### Rolling out the server-side `hidden` check

Before 2026-10, a hidden recipe was only filtered out by the app, and the raw
API still returned it. The current rules withhold it on the server. That
requires every public recipe to carry `hidden` — Firestore never matches a
missing field, so the app's `where hidden == false` would skip such a recipe —
and it refuses app versions that query without that filter. Hence the order:

1. **Backfill** — before any build with the filter talks to the database
   (the Xcode build on your own iPhone included):
   ```
   node scripts/backfill-hidden.mjs --key=<serviceAccount.json>            # dry run
   node scripts/backfill-hidden.mjs --key=<serviceAccount.json> --commit
   ```
2. **Release** the app version with the filter and wait until users have
   updated. Until the rules are deployed, an older version may still publish
   recipes without `hidden`; the new version does not list those.
3. **Backfill again** (catches those recipes), then **deploy** `firestore.rules`.
   From then on an older app version can neither list nor publish public
   recipes (its query lacks the filter, its new recipes lack the field) — it
   shows an empty recipe database.

## What the rules do
- **Recipe**: read for signed-in app users while `hidden == false`; a hidden
  (reported) recipe only for admins and its author — the same for its
  subcollections. Create only with a valid name, the caller's own `authorId`
  and `hidden: false`; update/delete only by that author, who may not change
  `hidden` — plus an admin, who may also release a hidden recipe, and any
  reporter, who may set *only* `hidden` and only to `true`. Subcollections
  (`components`/`ingredients`/`instructions`) writable only by the recipe's
  author. **Admins** (uid present in `admins`) may additionally delete any recipe
  and its subcollections.
- **admins**: console-managed registry of moderator uids; a client may read only
  its own admin document, never write.
- **reports**: clients may only *create* reports (stamped with their uid); no
  client can read/modify them — moderation happens in the console.
- **PrivateRecipe** (retired): no rule, so every access is denied.
- **Storage images**: uploads capped at 5 MB and must be an image type.
  `images/<uid>/…` is readable by every signed-in user but writable only by its
  owner, and deletable by the owner or an admin. The legacy flat path
  `images/<uuid>.jpg` stays readable and writable for signed-in users;
  `privateImages/…` (retired) is denied by the catch-all.
