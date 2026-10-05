#!/usr/bin/env node
//
// Gives every public recipe the field `hidden: false` that it is missing.
//
// The Firestore rules withhold a reported recipe (`hidden: true`) from all
// users but admins and its author, and the app lists recipes with
// `where hidden == false`. Firestore never matches a missing field, so a
// recipe published before the field existed would vanish from the list. This
// script adds the field to those recipes; recipes that already carry it,
// reported ones included, stay as they are.
//
// Run it BEFORE an app version with the `hidden` filter talks to the
// database, and once more right before deploying the rules: an older app
// version may have published recipes without the field in between.
//
// Usage:
//   node scripts/backfill-hidden.mjs --key=<serviceAccount.json>
//     → dry run: counts the recipes and lists the ones it would change
//
//   node scripts/backfill-hidden.mjs --key=… --commit
//     → writes `hidden: false` to those recipes
//
// Requires the Admin SDK:  npm install firebase-admin
// The service account key is a full-access credential — keep it out of the
// repository (scripts/*.json is git-ignored).

import { readFileSync, existsSync } from 'node:fs'
import { initializeApp, cert } from 'firebase-admin/app'
import { getFirestore } from 'firebase-admin/firestore'

// ---------------------------------------------------------------- arguments

const args = new Map(
    process.argv.slice(2).map(a => {
        const [key, ...rest] = a.replace(/^--/, '').split('=')
        return [key, rest.length ? rest.join('=') : true]
    })
)

const keyPath = args.get('key')
const commit  = args.get('commit') === true

if (typeof keyPath !== 'string') {
    console.error(`
Fehlende Angaben.

  node scripts/backfill-hidden.mjs --key=<serviceAccount.json>            Trockenlauf
  node scripts/backfill-hidden.mjs --key=<serviceAccount.json> --commit   Feld eintragen

Den Schlüssel gibt es in der Firebase Console unter
  Projekteinstellungen → Dienstkonten → "Neuen privaten Schlüssel erzeugen".`)
    process.exit(1)
}

if (!existsSync(keyPath)) {
    console.error(`Schlüsseldatei nicht gefunden: ${keyPath}`)
    process.exit(1)
}

// ---------------------------------------------------------------- firebase

initializeApp({ credential: cert(JSON.parse(readFileSync(keyPath, 'utf8'))) })
const db = getFirestore()

// ---------------------------------------------------------------- main

async function main() {
    const snapshot = await db.collection('Recipe').get()

    const missing  = snapshot.docs.filter(doc => typeof doc.get('hidden') !== 'boolean')
    const reported = snapshot.docs.filter(doc => doc.get('hidden') === true)

    console.log(`${snapshot.size} öffentliche Rezepte, davon`)
    console.log(`  ${snapshot.size - missing.length - reported.length} sichtbar (hidden: false)`)
    console.log(`  ${reported.length} gemeldet und ausgeblendet (hidden: true)`)
    console.log(`  ${missing.length} ohne das Feld`)

    if (missing.length === 0) {
        console.log('\nNichts zu tun.')
        return
    }

    console.log('')
    for (const doc of missing) {
        const value = doc.get('hidden')
        const note = value === undefined ? '' : `   (hidden war ${JSON.stringify(value)})`
        console.log(`  ${doc.id}  ${doc.get('name') ?? '—'}${note}`)
    }

    if (!commit) {
        console.log(`\nTrockenlauf: ${missing.length} Rezepte würden hidden: false erhalten. Mit --commit ausführen.`)
        return
    }

    // A batch takes at most 500 writes.
    for (let start = 0; start < missing.length; start += 500) {
        const batch = db.batch()
        for (const doc of missing.slice(start, start + 500)) {
            batch.update(doc.ref, { hidden: false })
        }
        await batch.commit()
    }
    console.log(`\n${missing.length} Rezepte haben jetzt hidden: false.`)
}

main().catch(error => {
    console.error(`Fehler: ${error.message}`)
    process.exit(1)
})
