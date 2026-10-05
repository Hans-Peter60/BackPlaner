#!/usr/bin/env node
//
// Grants (or revokes) moderator rights: writes the document `admins/<uid>`
// that the Firestore and Storage rules check in isAdmin(), and that the app
// reads in checkAdminStatus() to show the admin actions.
//
// The rules deliberately allow no client to write `admins`, so the document
// can only come from the Firebase console or from the Admin SDK — this script.
//
// Usage:
//   node scripts/grant-admin.mjs --key=<serviceAccount.json>
//     → lists the project's Apple accounts and whether each is an admin
//
//   node scripts/grant-admin.mjs --key=… --uid=<uid> [--commit]
//   node scripts/grant-admin.mjs --key=… --email=<address> [--commit]
//   node scripts/grant-admin.mjs --key=… --apple [--commit]
//     → makes that account an admin; --apple picks the only Apple account
//       there is (and refuses if there are several). Without --commit it is a
//       dry run that only reports what would happen.
//
//   Add --revoke to remove the admin document instead.
//
// Requires the Admin SDK:  npm install firebase-admin
// The service account key is a full-access credential — keep it out of the
// repository (scripts/*.json is git-ignored).

import { readFileSync, existsSync } from 'node:fs'
import { initializeApp, cert } from 'firebase-admin/app'
import { getFirestore, FieldValue } from 'firebase-admin/firestore'
import { getAuth } from 'firebase-admin/auth'

// ---------------------------------------------------------------- arguments

const args = new Map(
    process.argv.slice(2).map(a => {
        const [key, ...rest] = a.replace(/^--/, '').split('=')
        return [key, rest.length ? rest.join('=') : true]
    })
)

const keyPath     = args.get('key')
const targetUid   = typeof args.get('uid') === 'string' ? args.get('uid') : null
const targetEmail = typeof args.get('email') === 'string' ? args.get('email') : null
const pickApple   = args.get('apple') === true
const commit      = args.get('commit') === true
const revoke      = args.get('revoke') === true

if (!keyPath) {
    console.error(`
Fehlende Angaben.

  node scripts/grant-admin.mjs --key=<serviceAccount.json>               Konten auflisten
  node scripts/grant-admin.mjs --key=… --apple --commit                  das Apple-Konto zum Admin machen
  node scripts/grant-admin.mjs --key=… --uid=<uid> --commit              eine bestimmte uid zum Admin machen
  node scripts/grant-admin.mjs --key=… --uid=<uid> --revoke --commit     Admin-Rechte entziehen

Den Schlüssel gibt es in der Firebase Console unter
  Projekteinstellungen → Dienstkonten → "Neuen privaten Schlüssel erzeugen".
Vorher in der App einmal unter Einstellungen → Konto mit Apple anmelden.

Ohne --commit läuft nur ein Trockenlauf.`)
    process.exit(1)
}

if (!existsSync(keyPath)) {
    console.error(`Schlüsseldatei nicht gefunden: ${keyPath}`)
    process.exit(1)
}

// ---------------------------------------------------------------- firebase

initializeApp({ credential: cert(JSON.parse(readFileSync(keyPath, 'utf8'))) })

const db   = getFirestore()
const auth = getAuth()

const isApple = user => user.providerData.some(p => p.providerId === 'apple.com')

async function allUsers() {
    const users = []
    let pageToken
    do {
        const page = await auth.listUsers(1000, pageToken)
        users.push(...page.users)
        pageToken = page.pageToken
    } while (pageToken)
    return users
}

async function adminUids() {
    const snapshot = await db.collection('admins').get()
    return new Set(snapshot.docs.map(d => d.id))
}

function describe(user, admins) {
    const providers = user.providerData.map(p => p.providerId)
    const kind = providers.length === 0 ? 'ANONYM' : providers.join(', ')
    const lastSignIn = user.metadata.lastSignInTime
        ? new Date(user.metadata.lastSignInTime).toLocaleString('de-DE')
        : '—'
    return `  uid  ${user.uid}${admins.has(user.uid) ? '   ← Admin' : ''}\n`
         + `       ${kind}${user.email ? `  ${user.email}` : ''}, zuletzt angemeldet ${lastSignIn}`
}

/// Lists the permanent accounts — the only ones worth making an admin — and,
/// separately, any admin document whose uid has no account any more.
async function printAccounts() {
    const [users, admins] = await Promise.all([allUsers(), adminUids()])
    const apple = users.filter(isApple)
    const anonymous = users.length - apple.length

    if (apple.length === 0) {
        console.log('Kein Apple-Konto vorhanden — melde Dich in der App unter Einstellungen → Konto einmal mit Apple an.')
    } else {
        console.log(`${apple.length} Apple-Konto/Konten:\n`)
        for (const user of apple) console.log(describe(user, admins) + '\n')
    }
    console.log(`(${anonymous} anonyme Konten nicht aufgeführt.)`)

    const known = new Set(users.map(u => u.uid))
    const orphaned = [...admins].filter(uid => !known.has(uid))
    if (orphaned.length) {
        console.log('\nAdmin-Dokumente ohne zugehöriges Konto (können mit --revoke entfernt werden):')
        for (const uid of orphaned) console.log(`  ${uid}`)
    }
}

async function resolveUser() {
    if (targetUid) return auth.getUser(targetUid)
    if (targetEmail) return auth.getUserByEmail(targetEmail)

    const apple = (await allUsers()).filter(isApple)
    if (apple.length === 1) return apple[0]
    if (apple.length === 0) {
        throw new Error('Kein Apple-Konto vorhanden — erst in der App mit Apple anmelden.')
    }
    throw new Error(`Es gibt ${apple.length} Apple-Konten. Bitte mit --uid=… eines auswählen (Liste: ohne weitere Optionen aufrufen).`)
}

// ---------------------------------------------------------------- main

async function main() {
    if (!targetUid && !targetEmail && !pickApple) {
        await printAccounts()
        return
    }

    let user
    try {
        user = await resolveUser()
    } catch (error) {
        // Revoking must stay possible for a uid whose account is already gone.
        if (!(revoke && targetUid && error.code === 'auth/user-not-found')) throw error
    }

    const uid = user?.uid ?? targetUid
    const ref = db.collection('admins').doc(uid)
    const exists = (await ref.get()).exists

    if (revoke) {
        if (!exists) {
            console.log(`${uid} ist kein Admin — nichts zu tun.`)
            return
        }
        if (!commit) {
            console.log(`Trockenlauf: admins/${uid} würde gelöscht. Mit --commit ausführen.`)
            return
        }
        await ref.delete()
        console.log(`Admin-Rechte für ${uid} entzogen.`)
        return
    }

    console.log(describe(user, new Set(exists ? [uid] : [])))

    // An anonymous uid disappears with the app, so rights granted to it would
    // be lost on the next reinstall — and could not be revoked by anyone who
    // does not know the uid. Only a permanent account qualifies.
    if (!isApple(user)) {
        console.error('\nDieses Konto ist nicht mit Apple angemeldet. Admin-Rechte nur für ein Apple-Konto vergeben.')
        process.exit(1)
    }

    if (exists) {
        console.log('\nIst bereits Admin — nichts zu tun.')
        return
    }
    if (!commit) {
        console.log(`\nTrockenlauf: admins/${uid} würde angelegt. Mit --commit ausführen.`)
        return
    }

    await ref.set({ note: 'owner', grantedAt: FieldValue.serverTimestamp() })
    console.log(`\nadmins/${uid} angelegt. In der App die Einstellungen neu öffnen — dort erscheint „Administrator“.`)
}

main().catch(error => {
    console.error(`Fehler: ${error.message}`)
    process.exit(1)
})
