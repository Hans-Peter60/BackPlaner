#!/usr/bin/env node
//
// Moves recipes out of the public database into one author's private
// collection: every document in `Recipe` is recreated under
// `PrivateRecipe` owned by the given uid, its image is copied from
// `images/…` to `privateImages/<uid>/…`, and only then is the public
// original deleted.
//
// The order matters: copy → verify → back up → delete. A recipe is never
// removed from the public database before its private copy has been read
// back and found complete, so a failure in the middle leaves the public
// recipe intact (at worst there is an unused private copy).
//
// Usage:
//   node scripts/migrate-public-to-private.mjs --key=<serviceAccount.json> --uid=<targetUid>
//     → dry run: reports what would happen, changes nothing
//
//   node scripts/migrate-public-to-private.mjs --key=… --uid=… --commit
//     → performs the move
//
//   Options:
//     --email=<address>     look the uid up by account email instead of --uid
//     --keep-originals      copy only, leave the public recipes in place
//     --only=<id,id,…>      restrict to these recipe document ids
//     --backup=<file>       where to write the JSON backup
//                           (default: scripts/backup-public-recipes-<n>.json)
//
// Requires the Admin SDK:  npm install firebase-admin
// The service account key is a full-access credential — keep it out of the
// repository (scripts/*.json is git-ignored).

import { readFileSync, writeFileSync, existsSync } from 'node:fs'
import { randomUUID } from 'node:crypto'
import { initializeApp, cert } from 'firebase-admin/app'
import { getFirestore } from 'firebase-admin/firestore'
import { getStorage } from 'firebase-admin/storage'

// As configured in the app (GoogleService-Info.plist → STORAGE_BUCKET).
// Newer Firebase projects use the .firebasestorage.app name instead, so both
// are tried.
const STORAGE_BUCKET = 'back-planer.appspot.com'
const LEGACY_BUCKET  = 'back-planer.firebasestorage.app'

// ---------------------------------------------------------------- arguments

const args = new Map(
    process.argv.slice(2).map(a => {
        const [key, ...rest] = a.replace(/^--/, '').split('=')
        return [key, rest.length ? rest.join('=') : true]
    })
)

const keyPath        = args.get('key')
const targetUid      = args.get('uid')
const targetEmail    = args.get('email')
const commit         = args.get('commit') === true
const keepOriginals  = args.get('keep-originals') === true
const onlyIds        = typeof args.get('only') === 'string'
    ? args.get('only').split(',').map(s => s.trim()).filter(Boolean)
    : null

if (!keyPath || (!targetUid && !targetEmail)) {
    console.error(`
Fehlende Angaben.

  node scripts/migrate-public-to-private.mjs --key=<serviceAccount.json> --uid=<uid>

Den Schlüssel gibt es in der Firebase Console unter
  Projekteinstellungen → Dienstkonten → "Neuen privaten Schlüssel erzeugen".
Die uid steht unter
  Authentication → Users (die Zeile Deines Apple-Kontos).
Statt --uid geht auch --email=<Adresse des Kontos>.

Ohne --commit läuft nur ein Trockenlauf.`)
    process.exit(1)
}

if (!existsSync(keyPath)) {
    console.error(`Schlüsseldatei nicht gefunden: ${keyPath}`)
    process.exit(1)
}

// ---------------------------------------------------------------- firebase

const serviceAccount = JSON.parse(readFileSync(keyPath, 'utf8'))
initializeApp({ credential: cert(serviceAccount), storageBucket: STORAGE_BUCKET })

const db = getFirestore()

/// The bucket was renamed at some point; try the current name and fall back to
/// the legacy one, so the script works regardless of when the project was set up.
async function resolveBucket() {
    for (const name of [STORAGE_BUCKET, LEGACY_BUCKET]) {
        const bucket = getStorage().bucket(name)
        const [exists] = await bucket.exists()
        if (exists) return bucket
    }
    throw new Error(`Kein Storage-Bucket gefunden (probiert: ${STORAGE_BUCKET}, ${LEGACY_BUCKET})`)
}

async function resolveUid() {
    if (targetUid) return targetUid
    const { getAuth } = await import('firebase-admin/auth')
    const user = await getAuth().getUserByEmail(targetEmail)
    return user.uid
}

// ---------------------------------------------------------------- helpers

/// Reads a recipe with everything hanging off it, so the copy and the backup
/// work from one consistent snapshot.
async function readRecipe(doc) {
    const components = []
    const componentDocs = await doc.ref.collection('components').get()
    for (const component of componentDocs.docs) {
        const ingredients = await component.ref.collection('ingredients').get()
        components.push({
            id: component.id,
            data: component.data(),
            ingredients: ingredients.docs.map(i => ({ id: i.id, data: i.data() }))
        })
    }

    const instructionDocs = await doc.ref.collection('instructions').get()

    return {
        id: doc.id,
        data: doc.data(),
        components,
        instructions: instructionDocs.docs.map(i => ({ id: i.id, data: i.data() }))
    }
}

/// Copies the recipe image into the private folder and returns the value for
/// the `image` field (the app prepends the folder and appends ".jpg" itself).
/// Returns null when the original has no image object.
async function copyImage(bucket, recipe, uid) {
    const image = recipe.data.image
    if (!image) return { imageField: '', copied: false, missing: false }

    const sourcePath = `images/${image}.jpg`
    const sourceFile = bucket.file(sourcePath)
    const [exists] = await sourceFile.exists()
    if (!exists) {
        return { imageField: image, copied: false, missing: true, sourcePath }
    }

    // The private path has to start with the owner's uid: the Storage rules
    // read ownership out of the path itself.
    const imageField = `${uid}/${randomUUID()}`
    const targetPath = `privateImages/${imageField}.jpg`

    if (commit) {
        await sourceFile.copy(bucket.file(targetPath))
    }
    return { imageField, copied: true, missing: false, sourcePath, targetPath }
}

async function writePrivateCopy(recipe, uid, imageField) {
    const target = db.collection('PrivateRecipe').doc(recipe.id)

    const data = {
        ...recipe.data,
        authorId: uid,
        visibility: 'private',
        image: imageField
    }
    // A private recipe cannot be reported, so a takedown flag carried over from
    // the public database would only hide it from its own author.
    delete data.hidden

    await target.set(data)

    for (const component of recipe.components) {
        const componentRef = target.collection('components').doc(component.id)
        await componentRef.set(component.data)
        for (const ingredient of component.ingredients) {
            await componentRef.collection('ingredients').doc(ingredient.id).set(ingredient.data)
        }
    }

    for (const instruction of recipe.instructions) {
        await target.collection('instructions').doc(instruction.id).set(instruction.data)
    }
}

/// Reads the private copy back and compares it against the snapshot. Only a
/// recipe that passes this may have its public original deleted.
async function verifyPrivateCopy(recipe, uid) {
    const target = db.collection('PrivateRecipe').doc(recipe.id)
    const snapshot = await target.get()

    if (!snapshot.exists) return 'Dokument fehlt'
    if (snapshot.data().authorId !== uid) return 'authorId stimmt nicht'
    if ((snapshot.data().name ?? '') !== (recipe.data.name ?? '')) return 'Name stimmt nicht'

    const components = await target.collection('components').get()
    if (components.size !== recipe.components.length) {
        return `Komponenten: ${components.size} statt ${recipe.components.length}`
    }
    for (const component of recipe.components) {
        const ingredients = await target.collection('components').doc(component.id)
            .collection('ingredients').get()
        if (ingredients.size !== component.ingredients.length) {
            return `Zutaten in "${component.data.name}": ${ingredients.size} statt ${component.ingredients.length}`
        }
    }

    const instructions = await target.collection('instructions').get()
    if (instructions.size !== recipe.instructions.length) {
        return `Schritte: ${instructions.size} statt ${recipe.instructions.length}`
    }

    return null
}

async function deletePublicRecipe(bucket, recipe) {
    const ref = db.collection('Recipe').doc(recipe.id)

    for (const component of recipe.components) {
        const componentRef = ref.collection('components').doc(component.id)
        for (const ingredient of component.ingredients) {
            await componentRef.collection('ingredients').doc(ingredient.id).delete()
        }
        await componentRef.delete()
    }
    for (const instruction of recipe.instructions) {
        await ref.collection('instructions').doc(instruction.id).delete()
    }
    await ref.delete()

    if (recipe.data.image) {
        await bucket.file(`images/${recipe.data.image}.jpg`).delete({ ignoreNotFound: true })
    }
}

// ---------------------------------------------------------------- main

const uid = await resolveUid()
const bucket = await resolveBucket()

console.log(`Projekt:  ${serviceAccount.project_id}`)
console.log(`Bucket:   ${bucket.name}`)
console.log(`Ziel-uid: ${uid}`)
console.log(`Modus:    ${commit ? (keepOriginals ? 'KOPIEREN (Originale bleiben)' : 'VERSCHIEBEN (Originale werden gelöscht)') : 'Trockenlauf — es wird nichts geändert'}`)
console.log()

const publicDocs = await db.collection('Recipe').get()
let recipes = publicDocs.docs
if (onlyIds) {
    recipes = recipes.filter(d => onlyIds.includes(d.id))
}

if (recipes.length === 0) {
    console.log('Keine öffentlichen Rezepte gefunden — nichts zu tun.')
    process.exit(0)
}

console.log(`${recipes.length} öffentliche Rezepte gefunden.\n`)

const snapshots = []
const authors = new Map()
let moved = 0
const problems = []

for (const doc of recipes) {
    const recipe = await readRecipe(doc)
    snapshots.push(recipe)

    const author = recipe.data.authorId ?? '(ohne authorId)'
    authors.set(author, (authors.get(author) ?? 0) + 1)

    const label = `${recipe.data.name || '(ohne Namen)'} [${recipe.id}]`
    const shape = `${recipe.components.length} Komponenten, `
        + `${recipe.components.reduce((n, c) => n + c.ingredients.length, 0)} Zutaten, `
        + `${recipe.instructions.length} Schritte`

    const image = await copyImage(bucket, recipe, uid)
    const imageNote = image.missing
        ? `Bild FEHLT in Storage (${image.sourcePath})`
        : image.imageField
            ? `Bild → ${image.targetPath ?? 'privateImages/…'}`
            : 'kein Bild hinterlegt'

    if (!commit) {
        console.log(`• ${label}`)
        console.log(`    ${shape}; ${imageNote}`)
        if (recipe.data.hidden === true) {
            console.log(`    Hinweis: war gemeldet/ausgeblendet — die Kopie wird sichtbar sein`)
        }
        if (author !== uid) {
            console.log(`    Hinweis: bisheriger Autor ${author} — die Kopie gehört danach Dir`)
        }
        continue
    }

    try {
        await writePrivateCopy(recipe, uid, image.imageField)
        const failure = await verifyPrivateCopy(recipe, uid)
        if (failure) {
            problems.push(`${label}: Kopie unvollständig (${failure}) — Original NICHT gelöscht`)
            console.log(`✗ ${label}: ${failure} — Original bleibt erhalten`)
            continue
        }

        if (!keepOriginals) {
            await deletePublicRecipe(bucket, recipe)
        }
        moved += 1
        console.log(`✓ ${label} — ${shape}; ${imageNote}`)
        if (image.missing) {
            problems.push(`${label}: Bild fehlte in Storage, Rezept hat jetzt kein Bild`)
        }
    } catch (error) {
        problems.push(`${label}: ${error.message} — Original NICHT gelöscht`)
        console.log(`✗ ${label}: ${error.message}`)
    }
}

// The backup is written in every mode: in a dry run it is the snapshot to
// inspect, and in a real run the only copy that does not live in the cloud.
const backupPath = typeof args.get('backup') === 'string'
    ? args.get('backup')
    : `scripts/backup-public-recipes-${snapshots.length}.json`
writeFileSync(backupPath, JSON.stringify(snapshots, null, 2), 'utf8')

console.log()
console.log('Autoren der öffentlichen Rezepte:')
for (const [author, count] of authors) {
    console.log(`  ${count.toString().padStart(3)} × ${author}${author === uid ? '  (Du)' : ''}`)
}
console.log()
console.log(`Backup geschrieben: ${backupPath}`)

if (!commit) {
    console.log()
    console.log('Das war ein Trockenlauf. Für die echte Migration dieselbe Zeile mit --commit aufrufen.')
} else {
    console.log(`${moved} von ${recipes.length} Rezepten ${keepOriginals ? 'kopiert' : 'verschoben'}.`)
    if (problems.length) {
        console.log('\nNicht abgeschlossen:')
        for (const problem of problems) console.log(`  - ${problem}`)
        process.exit(1)
    }
}
