// Checks firestore.rules against the cases the app depends on, in the
// Firestore emulator:
//
//     cd firebase/tests && npm ci && npm test
//
// Needs Java (the emulator is a JAR); the GitHub Action runs it on every pull
// request. A case that fails names what the rules allow or refuse wrongly.

import { readFileSync } from 'node:fs'
import { initializeTestEnvironment, assertFails, assertSucceeds } from '@firebase/rules-unit-testing'
import { doc, getDoc, getDocs, setDoc, updateDoc, collection, query, where } from 'firebase/firestore'

const env = await initializeTestEnvironment({
  projectId: 'demo-backplaner',
  firestore: { rules: readFileSync(new URL('../firestore.rules', import.meta.url), 'utf8'), host: '127.0.0.1', port: 8080 },
})

await env.withSecurityRulesDisabled(async ctx => {
  const db = ctx.firestore()
  await setDoc(doc(db, 'admins/admin'), { note: 'x' })
  await setDoc(doc(db, 'Recipe/visible'), { name: 'Sichtbar', authorId: 'author', hidden: false })
  await setDoc(doc(db, 'Recipe/reported'), { name: 'Gemeldet', authorId: 'author', hidden: true })
  await setDoc(doc(db, 'Recipe/legacy'), { name: 'Alt', authorId: 'author' })
  for (const id of ['visible', 'reported']) {
    await setDoc(doc(db, `Recipe/${id}/instructions/1`), { instruction: 'kneten' })
    await setDoc(doc(db, `Recipe/${id}/components/c`), { name: 'Teig' })
    await setDoc(doc(db, `Recipe/${id}/components/c/ingredients/i`), { name: 'Mehl' })
  }
})

const as = uid => env.authenticatedContext(uid).firestore()
const user = as('someone'), author = as('author'), admin = as('admin')
let failed = 0
async function check(name, promise, expectOk) {
  try { await (expectOk ? assertSucceeds : assertFails)(promise); console.log('✓', name) }
  catch (e) { failed++; console.log('✗', name, e.message) }
}

await check('user: unfiltered list refused', getDocs(collection(user, 'Recipe')), false)
await check('user: filtered list allowed', getDocs(query(collection(user, 'Recipe'), where('hidden', '==', false))), true)
const listed = await getDocs(query(collection(user, 'Recipe'), where('hidden', '==', false)))
console.log('  listed:', listed.docs.map(d => d.id).join(', '))
await check('admin: unfiltered list allowed', getDocs(collection(admin, 'Recipe')), true)
await check('user: get visible', getDoc(doc(user, 'Recipe/visible')), true)
await check('user: get reported refused', getDoc(doc(user, 'Recipe/reported')), false)
await check('author: get own reported', getDoc(doc(author, 'Recipe/reported')), true)
await check('admin: get reported', getDoc(doc(admin, 'Recipe/reported')), true)
await check('user: get legacy (no field) refused', getDoc(doc(user, 'Recipe/legacy')), false)
await check('author: get own legacy', getDoc(doc(author, 'Recipe/legacy')), true)
await check('user: instructions of visible', getDocs(collection(user, 'Recipe/visible/instructions')), true)
await check('user: ingredients of visible', getDocs(collection(user, 'Recipe/visible/components/c/ingredients')), true)
await check('user: instructions of reported refused', getDocs(collection(user, 'Recipe/reported/instructions')), false)
await check('user: components of reported refused', getDocs(collection(user, 'Recipe/reported/components')), false)
await check('user: ingredients of reported refused', getDocs(collection(user, 'Recipe/reported/components/c/ingredients')), false)
await check('author: instructions of own reported', getDocs(collection(author, 'Recipe/reported/instructions')), true)
await check('admin: components of reported', getDocs(collection(admin, 'Recipe/reported/components')), true)
await check('create without hidden refused', setDoc(doc(user, 'Recipe/n1'), { name: 'N', authorId: 'someone' }), false)
await check('create hidden: true refused', setDoc(doc(user, 'Recipe/n2'), { name: 'N', authorId: 'someone', hidden: true }), false)
await check('create hidden: false allowed', setDoc(doc(user, 'Recipe/n3'), { name: 'N', authorId: 'someone', hidden: false }), true)
await check('author: subcollection write on own new recipe', setDoc(doc(user, 'Recipe/n3/instructions/1'), { instruction: 'x' }), true)
await check('author: totalWeight update', updateDoc(doc(user, 'Recipe/n3'), { totalWeight: 900 }), true)
await check('author: may not unhide own reported', updateDoc(doc(author, 'Recipe/reported'), { hidden: false }), false)
await check('author: may edit own reported otherwise', updateDoc(doc(author, 'Recipe/reported'), { totalWeight: 1 }), true)
await check('author: translation update on legacy', updateDoc(doc(author, 'Recipe/legacy'), { translations: {} }), true)
await check('reporter: hide visible', updateDoc(doc(user, 'Recipe/visible'), { hidden: true }), true)
await check('reporter: may not unhide', updateDoc(doc(user, 'Recipe/visible'), { hidden: false }), false)
await check('admin: unhide', updateDoc(doc(admin, 'Recipe/visible'), { hidden: false }), true)
await check('private recipes unaffected (owner list)', getDocs(query(collection(author, 'PrivateRecipe'), where('authorId', '==', 'author'))), true)

await env.cleanup()
console.log(failed ? `${failed} failed` : 'all passed')
process.exit(failed ? 1 : 0)
