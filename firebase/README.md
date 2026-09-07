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

## What the rules do
- **Recipe**: read for signed-in app users; create only with a valid name and
  the caller's own `authorId`; update/delete only by that author. Subcollections
  (`components`/`ingredients`/`instructions`) writable only by the recipe's
  author. **Admins** (uid present in `admins`) may additionally delete any recipe
  and its subcollections.
- **admins**: console-managed registry of moderator uids; a client may read only
  its own admin document, never write.
- **reports**: clients may only *create* reports (stamped with their uid); no
  client can read/modify them — moderation happens in the console.
- **Storage images**: read/write/delete for signed-in app users; uploads capped
  at 5 MB and must be an image type.
