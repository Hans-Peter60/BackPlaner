# Firebase Security Rules — BackPlaner

Security rules for the public recipe database (Firestore) and recipe images
(Cloud Storage). They lock down the previously open/test-mode project and
enforce the UGC moderation model (App Store Guideline 1.2).

## Files
- `firestore.rules` — recipe database + moderation `reports`
- `storage.rules` — recipe images

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

Admins may delete **any** public recipe (not just their own) via the "Rezept
löschen (Admin)" button in the app's public recipe detail view. An admin is any
user whose `auth.uid` has a document in the `admins` collection.

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
4. Firestore → collection **`admins`** → add a document whose **ID is that uid**
   (contents don't matter; `{ "note": "owner" }` is fine).
5. Reopen a public recipe → the "Rezept löschen (Admin)" button appears.
   "Abmelden" returns to the anonymous identity.

The rules restrict the `admins` collection to **console-only writes**; a client
may read only its *own* admin document.

## Private (author-only) recipes

There are two kinds of cloud recipes:

- **Public** — collection `Recipe`, images under `images/<uid>/…`, readable by
  every user. Only for recipes that infringe no copyright.
- **Author-only** — collection `PrivateRecipe`, images under
  `privateImages/<uid>/…`, readable **only** by the author. For a recipe the user
  may not publish but still wants stored somewhere other than the device.

Both carry a `visibility` field (`"public"` / `"private"`); a recipe without one
counts as public, so no existing document needs a backfill.

Why two collections instead of one collection plus a filter: a Firestore query
must be provably allowed for *every* document it may return. With a mixed
collection every listing would depend on document data, and each of the existing
recipes would have to be backfilled with `visibility` before it could be found
again. Separate collections leave the public database untouched.

**A permanent account is required.** Ownership is `authorId == request.auth.uid`,
and an anonymous uid is gone once the app is deleted — the author would be locked
out of his own recipes for good. The rules therefore reject `create` in
`PrivateRecipe` for anonymous users (`sign_in_provider != 'anonymous'`), and the
app asks for **Sign in with Apple** before saving one (Einstellungen → Konto, or
the sheet that appears when saving). The anonymous identity is *linked* rather
than replaced, so the uid — and ownership of everything published before —
survives the sign-in.

Consequences worth knowing:
- Private recipes are **not** subject to moderation: they cannot be reported, and
  admins have no access (nothing is shared, so there is nothing to review).
- Signing out returns to an anonymous identity; the private recipes stay in the
  cloud and reappear after signing in with the same Apple account.
- Like a public one, a cloud recipe cannot be edited afterwards — to change it,
  delete it and upload again.

## Deploy

**Console (quickest):**
- Firestore → *Rules* tab → paste `firestore.rules` → **Publish**.
- Storage → *Rules* tab → paste `storage.rules` → **Publish**.

**CLI (optional):**

`firebase.json` (repo root) and `.firebaserc` (project `back-planer`) are already
wired to these files, so from the repo root just run:
```
firebase deploy --only firestore:rules,storage:rules
```
(Requires `firebase-tools`: `npm i -g firebase-tools` and a one-time `firebase login`.)

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
   recipe is gone for every user, including its author — `getRecipesFB` skips
   hidden documents for everyone except admins.
3. Each user can report a given recipe only once (deterministic report id +
   create-only rule), and a reporter can only ever *hide*, never unhide.
4. An admin opens the recipe (admins still see hidden ones) and either
   - deletes it permanently — *Rezept löschen (Admin)*, or
   - releases it again — *Rezept wieder freigeben* (`setRecipeHidden`).
5. Open reports are reviewed in the Firebase console
   (Firestore → `reports`, `status: "open"`). Keep handled reports as a record
   of the decision; do not delete them.

Known limitation: a hidden recipe is filtered out on the client, and the
document itself is still readable through the raw API until an admin deletes it.
Making that airtight requires `allow read` to check `hidden` plus a
`whereField("hidden", isEqualTo: false)` query — which additionally needs every
existing recipe backfilled with `hidden: false`, because a missing field does
not match that query.

## What the rules do
- **Recipe**: read for signed-in app users; create only with a valid name and
  the caller's own `authorId`; update/delete only by that author — plus an admin,
  who may also release a hidden recipe, and any reporter, who may set *only*
  `hidden` and only to `true`. Subcollections
  (`components`/`ingredients`/`instructions`) writable only by the recipe's
  author. **Admins** (uid present in `admins`) may additionally delete any recipe
  and its subcollections.
- **admins**: console-managed registry of moderator uids; a client may read only
  its own admin document, never write.
- **reports**: clients may only *create* reports (stamped with their uid); no
  client can read/modify them — moderation happens in the console.
- **PrivateRecipe**: read/update/delete only by the author (`authorId ==
  auth.uid`), create only with a **permanent** (non-anonymous) account, same for
  the subcollections. No admin branch — private content is not moderated.
- **Storage images**: uploads capped at 5 MB and must be an image type.
  `images/<uid>/…` is readable by every signed-in user but writable only by its
  owner; `privateImages/<uid>/…` is readable **only** by its owner. The legacy
  flat path `images/<uuid>.jpg` stays readable and writable for signed-in users.
