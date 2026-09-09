//
//  RecipeFBModel.swift
//  PetersBackPlaner
//
//  Created by Hans-Peter Müller on 22.11.21.
//

import Foundation
import UIKit
import FirebaseFirestore
import FirebaseStorage
import FirebaseAuth
import os

private enum RecipeImageUploadError: LocalizedError {
    case encodingFailed

    var errorDescription: String? {
        "Das Rezeptbild konnte nicht als JPEG gespeichert werden."
    }
}

/// A recipe that only its author may see needs an identity that survives a
/// reinstall, otherwise the recipe would be locked away with the next anonymous
/// uid. Only a permanent account (Sign in with Apple) provides one.
enum PrivateRecipeError: LocalizedError {
    case accountRequired

    var errorDescription: String? {
        "Für private Cloud-Rezepte ist eine Anmeldung mit Apple erforderlich. Ohne Konto wäre das Rezept nach einer Neuinstallation nicht mehr erreichbar."
    }
}

private extension UIImage {
    func scaledDownForUpload(maxPixelDimension: CGFloat) -> UIImage {
        let pixelSize = CGSize(width: size.width * scale, height: size.height * scale)
        let largestDimension = max(pixelSize.width, pixelSize.height)

        guard largestDimension > maxPixelDimension else { return self }

        let resizeFactor = maxPixelDimension / largestDimension
        let targetSize = CGSize(
            width: max(1, (pixelSize.width * resizeFactor).rounded()),
            height: max(1, (pixelSize.height * resizeFactor).rounded())
        )
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true

        return UIGraphicsImageRenderer(size: targetSize, format: format).image { context in
            UIColor.white.setFill()
            context.fill(CGRect(origin: .zero, size: targetSize))
            draw(in: CGRect(origin: .zero, size: targetSize))
        }
    }
}

class RecipeFBModel: ObservableObject {
    
    let db      = Firestore.firestore()
    let storage = Storage.storage()
    
    @Published var recipesFB = [RecipeFB]()
    @Published var storedID  = ""
    @Published var isLoading = false

    @Published var tabSelection = 0

    /// True when the signed-in (anonymous) user is a moderator/owner, i.e. their
    /// uid has a document in the Firestore `admins` collection. Admins may delete
    /// any public recipe, not just their own.
    @Published var isAdmin = false

    /// True once the user signed in with Apple, which turns the anonymous
    /// identity into a permanent one. Only then can author-only recipes be
    /// stored in the cloud and found again after a reinstall.
    @Published var isSignedInWithAccount = false

    /// Email of the permanent account, if Apple shared one (nil for anonymous
    /// users and for accounts created with a hidden relay address).
    @Published var accountEmail: String?

    /// uid the recipe list was last loaded for. A change of identity means a
    /// different set of author-only recipes, so the list has to be refetched.
    private var loadedForUid: String?

    /// Counter identifying the current list load, so a fetch that was
    /// superseded by a newer one cannot append its documents a second time.
    private var loadGeneration = 0

    var calcWeight:CalcIngredientWeight = CalcIngredientWeight()

    init() {
        // Auslesen der Rezepte aus der Firestore Datenbank
        getRecipesFB()

        // Track the identity: whether it is a moderator/owner and whether it is
        // permanent. Runs now and again whenever the auth state changes, since
        // the anonymous sign-in only completes shortly after launch (see
        // AppDelegate) — and a later Apple sign-in changes what is visible.
        Auth.auth().addStateDidChangeListener { [weak self] _, user in
            guard let self else { return }
            self.isSignedInWithAccount = user != nil && user?.isAnonymous == false
            self.accountEmail = user?.email
            self.checkAdminStatus()
            // Reload as soon as the identity actually changes, so the author's
            // own private recipes appear (and a signed-out user's disappear).
            if user?.uid != self.loadedForUid { self.getRecipesFB() }
        }

//        GlobalVariables.unitSets = DataService.getUnitSets()
//
//        for unitSet in GlobalVariables.unitSets {
//            print(unitSet.name, unitSet.factor)
//        }
    }
    
    /// Uploads a recipe to the cloud. `visibility` decides whether it joins the
    /// shared database everyone reads, or the author's own collection that the
    /// security rules keep private to him.
    func uploadRecipeToFirestore(r: RecipeFB, i: UIImage, visibility: RecipeVisibility = .everyone, completion: ((Result<Void, Error>) -> Void)? = nil) {

        // Anonymous authentication finishes asynchronously during app launch.
        // Wait for it here as well so Storage rules never see request.auth == nil.
        guard let currentUser = Auth.auth().currentUser else {
            Auth.auth().signInAnonymously { [weak self] _, error in
                DispatchQueue.main.async {
                    if let error {
                        completion?(.failure(error))
                    } else {
                        self?.uploadRecipeToFirestore(r: r, i: i, visibility: visibility, completion: completion)
                    }
                }
            }
            return
        }

        // An author-only recipe is tied to its owner's uid. An anonymous uid is
        // gone once the app is removed, so the recipe would be unreachable —
        // refuse instead of writing something the author can lose.
        guard visibility == .everyone || !currentUser.isAnonymous else {
            completion?(.failure(PrivateRecipeError.accountRequired))
            return
        }

        let uploadImage = i.scaledDownForUpload(maxPixelDimension: 1_024)
        guard let data = uploadImage.jpegData(compressionQuality: 0.5) else {
            completion?(.failure(RecipeImageUploadError.encodingFailed))
            return
        }

        r.id = UUID().uuidString
        r.visibility = visibility
        recipesFB.append(r)

        let cloudRecipes = db.collection(visibility.collectionName)

        // Include the authenticated owner in the Storage path. This lets the
        // Storage rules enforce that users only create/delete their own images.
        r.image = currentUser.uid + "/" + UUID().uuidString
        r.applyPreferredLocalization()
        r.capturePreferredLocalization()

        // Report success only once both the image upload and the recipe document
        // have committed; surface the first error so the UI can inform the user.
        let group = DispatchGroup()
        var firstError: Error?

        // MARK: Upload image into cloud storage
        let storageRef = storage.reference()
        let imageRef   = storageRef.child(r.imageStoragePath)
        let metadata   = StorageMetadata()
        metadata.contentType = "image/jpeg"

        group.enter()
        imageRef.putData(data, metadata: metadata) { _, error in
            if let error { firstError = firstError ?? error }
            group.leave()
        }

        let calculatedInstructions = Rational.calculateStartTimes(
            r.instructions,
            Date(),
            dependencies: Rational.ComponentDependency.from(r.components)
        )

        // Create a Firebase document
        var recipeData: [String: Any] = [
            "name":           r.name,
            "prepTime":       GlobalVariables.totalDuration,
            "totalWeight":    r.totalWeight,
            "summary":        r.summary,
            "urlLink":        r.urlLink,
            "image":          r.image,
            "tags":           r.tags,
            "authorId":       ModerationStore.shared.authorId,
            "visibility":     visibility.rawValue,
            "sourceLanguage": r.sourceLanguage
        ]
        let recipeTranslations = r.firestoreTranslationsData
        if !recipeTranslations.isEmpty {
            recipeData["translations"] = recipeTranslations
        }

        group.enter()
        let cloudRecipe = cloudRecipes.document(r.id ?? UUID().uuidString)
        cloudRecipe.setData(recipeData) { error in
            if let error { firstError = firstError ?? error }
            group.leave()
        }

        // Set the components
        for c in r.components {
            
            var componentData: [String: Any] = [
                "name":   c.name,
                "number": c.number
            ]
            let componentTranslations = c.firestoreTranslationsData
            if !componentTranslations.isEmpty {
                componentData["translations"] = componentTranslations
            }

            let cloudComponent = cloudRecipe.collection("components").addDocument(data: componentData)
            
            for i in c.ingredients {
                
                // Create an ingredient document
                var ingredientData: [String: Any] = [
                    "name":       i.name,
                    "number":     i.number,
                    "unit":       i.unit,
                    "weight":     i.weight,
                    "normWeight": i.normWeight,
                    "num":        i.num,
                    "denom":      i.denom
                ]
                let ingredientTranslations = i.firestoreTranslationsData
                if !ingredientTranslations.isEmpty {
                    ingredientData["translations"] = ingredientTranslations
                }
                let _ = cloudComponent.collection("ingredients").addDocument(data: ingredientData)
                
                if i.unit == "g" || i.unit == "Gramm" {
                    i.normWeight = i.weight
                }
                else {
                    i.normWeight = calcWeight.calcIngredientWeight(weight: i.weight, unit: i.unit, name: i.name, num: i.num, denom: i.denom)
                }
                r.totalWeight += i.normWeight
            }
        }
        
        // Set the Instructions
        for i in calculatedInstructions {
            
            var instructionData: [String: Any] = [
                "instruction": i.instruction,
                "step":        i.step,
                "duration":    i.duration,
                "startTime":   i.startTime ?? 0,
                "date":        i.date ?? 0
            ]
            if let componentName = i.componentName {
                instructionData["componentName"] = componentName
            }
            let instructionTranslations = i.firestoreTranslationsData
            if !instructionTranslations.isEmpty {
                instructionData["translations"] = instructionTranslations
            }
            let _ = cloudRecipe.collection("instructions").addDocument(data: instructionData)
        }
        
        // Create a Firebase document
        cloudRecipe.updateData(["totalWeight":r.totalWeight])

        group.notify(queue: .main) {
            if let firstError {
                AppLog.firebase.error("Recipe upload failed: \(firstError)")
                completion?(.failure(firstError))
            } else {
                completion?(.success(()))
            }
        }
    }
    
    /// Writes the cached translations of a recipe (and its components, ingredients and
    /// instructions) back to Firestore so other users benefit from them.
    ///
    /// To protect the original, a document's `translations` map is only written when it
    /// still contains the source (German) entry — otherwise that document is skipped, so
    /// a machine translation can never overwrite or drop the original German version.
    func saveTranslations(_ recipe: RecipeFB) {
        guard let recipeId = recipe.id, !recipeId.isEmpty else { return }
        let source = RecipeTranslator.sourceLanguageCode(for: recipe)

        // Guard: never touch Firestore unless the source (German) version is preserved.
        guard recipe.hasCachedTranslation(languageCode: source) else {
            AppLog.firebase.error("saveTranslations skipped — source '\(source)' translation missing, would drop the original")
            return
        }

        let recipeRef = db.collection(recipe.visibility.collectionName).document(recipeId)

        // Recipe-level translations.
        let recipeTranslations = recipe.firestoreTranslationsData
        if recipeTranslations[source] != nil {
            recipeRef.updateData(["translations": recipeTranslations])
        }

        // Components and their ingredients.
        for component in recipe.components {
            guard let componentId = component.id, !componentId.isEmpty else { continue }
            let componentRef = recipeRef.collection("components").document(componentId)

            let componentTranslations = component.firestoreTranslationsData
            if componentTranslations[source] != nil {
                componentRef.updateData(["translations": componentTranslations])
            }

            for ingredient in component.ingredients {
                guard let ingredientId = ingredient.id, !ingredientId.isEmpty else { continue }
                let ingredientTranslations = ingredient.firestoreTranslationsData
                if ingredientTranslations[source] != nil {
                    componentRef.collection("ingredients").document(ingredientId)
                        .updateData(["translations": ingredientTranslations])
                }
            }
        }

        // Instructions.
        for instruction in recipe.instructions {
            guard let instructionId = instruction.id, !instructionId.isEmpty else { continue }
            let instructionTranslations = instruction.firestoreTranslationsData
            if instructionTranslations[source] != nil {
                recipeRef.collection("instructions").document(instructionId)
                    .updateData(["translations": instructionTranslations])
            }
        }
    }

    /// Loads the recipe list: the shared public database plus, for a permanently
    /// signed-in author, his own author-only recipes.
    func getRecipesFB(completion: (() -> Void)? = nil) {

        let user = Auth.auth().currentUser
        loadedForUid = user?.uid

        isLoading = true
        // Reset so a reload (pull-to-refresh) does not duplicate recipes.
        recipesFB = []
        // Two fetches can overlap (launch, admin check, pull-to-refresh). Stamp
        // this run so results of a superseded one are dropped instead of being
        // appended a second time.
        loadGeneration += 1
        let generation = loadGeneration

        let group = DispatchGroup()

        group.enter()
        loadRecipes(from: .everyone, ownedBy: nil, generation: generation) { group.leave() }

        // Author-only recipes are readable for their owner alone. They are also
        // only ever written by a permanent account, so an anonymous user has
        // none to query for.
        if let user, !user.isAnonymous {
            group.enter()
            loadRecipes(from: .authorOnly, ownedBy: user.uid, generation: generation) { group.leave() }
        }

        group.notify(queue: .main) {
            guard generation == self.loadGeneration else { return }
            self.isLoading = false
            completion?()
        }
    }

    /// Fetches one recipe collection. `ownerUid` restricts the query to the
    /// caller's own documents, which is what the security rules demand for the
    /// author-only collection.
    private func loadRecipes(from visibility: RecipeVisibility,
                             ownedBy ownerUid: String?,
                             generation: Int,
                             completion: @escaping () -> Void) {

        let storageRef = storage.reference()

        var query: Query = db.collection(visibility.collectionName)
        if let ownerUid {
            query = query.whereField("authorId", isEqualTo: ownerUid)
        }

        query.getDocuments { snapshot, error in

            defer { completion() }

            // A newer load has taken over in the meantime; its results count.
            guard generation == self.loadGeneration else { return }

            if let error {
                AppLog.firebase.error("Could not load \(visibility.collectionName): \(error.localizedDescription)")
                return
            }

            guard let snapshot else { return }

            // Loop through the documents returned
            for doc in snapshot.documents {

                // A reported recipe is withheld from every user right away
                // (App Store Guideline 1.2). Only admins still receive it,
                // so they can review it and either release or delete it.
                let isHidden = doc["hidden"] as? Bool ?? false
                if isHidden && !self.isAdmin { continue }

                let r      = RecipeFB()

                r.id          = doc.documentID
                r.visibility  = visibility
                r.hidden      = isHidden
                r.authorId    = doc["authorId"]    as? String ?? ""
                r.name        = doc["name"]        as? String ?? ""
                r.image       = doc["image"]       as? String ?? ""
                r.summary     = doc["summary"]     as? String ?? ""
                r.urlLink     = doc["urlLink"]     as? String ?? ""
                r.prepTime    = doc["prepTime"]    as? Int    ?? 0
                r.totalWeight     = doc["totalWeight"]     as? Double ?? 0
                r.tags            = doc["tags"]            as? [String] ?? [String]()
                r.sourceLanguage  = doc["sourceLanguage"]  as? String ?? ""
                if let translations = doc["translations"] as? [String: Any] {
                    r.translations = translations.mapValues { RecipeTextFB(firestoreData: $0) }
                }
                r.applyPreferredLocalization()

                if GlobalVariables.detailView {
                    self.getInstructionsFB(r, r.id!)
                    self.getComponentsFB(r, r.id!)
                }
                self.recipesFB.append(r)

                let imageRef = storageRef.child(r.imageStoragePath)

                // Download in memory with a maximum allowed size of 1MB (1 * 1024 * 1024 bytes)
                imageRef.getData(maxSize: 1 * 2048 * 2048) { data, error in
                    if error != nil {
                        // Uh-oh, an error occurred!
                        AppLog.firebase.error("Error - no image found")
                    } else {
                        // Data is returned
                        GlobalVariables.recipesImage[r.id ?? ""] = UIImage(data: data!) ?? UIImage()
                    }
                }
            }
        }
    }

    /// Files a moderation report for a public recipe (App Store Guideline 1.2)
    /// and takes the recipe down for EVERY user in the same step, so offensive
    /// content disappears immediately instead of within some review window. An
    /// admin reviews it afterwards and either deletes it or releases it again
    /// via `setRecipeHidden(_:hidden:)`.
    ///
    /// The report id is `{recipeId}_{uid}`, so each user can report a given
    /// recipe only once: the security rules allow `create` but never `update`,
    /// which makes a second attempt fail on the server.
    func reportRecipe(_ recipe: RecipeFB, reason: String) {
        guard let recipeId = recipe.id, !recipeId.isEmpty else { return }
        let reporter = ModerationStore.shared.authorId

        db.collection("reports").document("\(recipeId)_\(reporter)").setData([
            "recipeId":   recipeId,
            "authorId":   recipe.authorId ?? "",
            "reason":     reason,
            "reportedBy": reporter,
            "status":     "open",
            "createdAt":  FieldValue.serverTimestamp()
        ]) { error in
            if let error {
                AppLog.firebase.error("Report could not be filed: \(error.localizedDescription)")
            }
        }

        // Only `hidden` is written here, deliberately: the security rule has to
        // match the changed keys exactly, and Firestore sentinels (serverTimestamp,
        // increment) make that condition impossible to verify in the Rules
        // Playground. Timestamps and the report count live in `reports` anyway.
        db.collection("Recipe").document(recipeId).updateData([
            "hidden": true
        ]) { error in
            if let error {
                AppLog.firebase.error("Reported recipe could not be hidden: \(error.localizedDescription)")
            } else {
                recipe.hidden = true
            }
        }
    }

    /// Withholds a reported recipe from all users, or releases it again after
    /// review. Admins only — the security rules enforce the same restriction.
    func setRecipeHidden(_ recipe: RecipeFB, hidden: Bool, completion: ((Result<Void, Error>) -> Void)? = nil) {
        guard isAdmin, let recipeId = recipe.id, !recipeId.isEmpty else {
            completion?(.success(()))
            return
        }

        db.collection("Recipe").document(recipeId).updateData([
            "hidden": hidden
        ]) { error in
            DispatchQueue.main.async {
                if let error {
                    AppLog.firebase.error("Visibility could not be changed: \(error.localizedDescription)")
                    completion?(.failure(error))
                } else {
                    recipe.hidden = hidden
                    completion?(.success(()))
                }
            }
        }
    }

    /// Deletes a public recipe the current device authored (App Store Guideline
    /// 1.2: users can remove their own content). Removes the subcollections and
    /// the stored image best-effort, then the recipe document, and updates the
    /// in-memory list. No-op if the recipe was authored by someone else.
    func deleteOwnRecipe(_ recipe: RecipeFB, completion: ((Result<Void, Error>) -> Void)? = nil) {
        guard recipe.authorId == ModerationStore.shared.authorId else {
            completion?(.success(()))
            return
        }
        performDelete(recipe, completion: completion)
    }

    /// Checks whether the cloud document linked from a local recipe still
    /// exists — in the public database or in the author's own collection. This
    /// lets the local recipe be uploaded again after its cloud copy was deleted
    /// elsewhere.
    func cloudRecipeExists(id: String, completion: @escaping (Result<Bool, Error>) -> Void) {
        // Only a permanent account can own author-only recipes, so an anonymous
        // user never has to look there.
        var collections = [RecipeVisibility.everyone]
        if let user = Auth.auth().currentUser, !user.isAnonymous {
            collections.append(.authorOnly)
        }

        let group = DispatchGroup()
        var exists = false
        var failures = 0
        var firstError: Error?

        for visibility in collections {
            group.enter()
            db.collection(visibility.collectionName).document(id).getDocument { snapshot, error in
                if let error {
                    // Reading a document that is not the caller's own is denied
                    // by the rules, which is indistinguishable from "not there".
                    failures += 1
                    firstError = firstError ?? error
                } else if snapshot?.exists == true {
                    exists = true
                }
                group.leave()
            }
        }

        group.notify(queue: .main) {
            if exists {
                completion(.success(true))
            } else if failures == collections.count, let firstError {
                // Every lookup failed, so nothing is actually known.
                completion(.failure(firstError))
            } else {
                completion(.success(false))
            }
        }
    }

    /// Refreshes `isAdmin` by checking whether the current uid has a document in
    /// the Firestore `admins` collection. No-op (not admin) if signed out.
    func checkAdminStatus() {
        guard let uid = Auth.auth().currentUser?.uid else {
            AppLog.firebase.debug("Admin check skipped — no signed-in user yet")
            isAdmin = false
            return
        }
        db.collection("admins").document(uid).getDocument { [weak self] snapshot, error in
            if let error {
                // A permission error here usually means the updated Firestore
                // rules (which allow reading admins/{uid}) aren't deployed yet.
                AppLog.firebase.error("Admin check failed for uid \(uid): \(error.localizedDescription)")
                self?.isAdmin = false
                return
            }
            let result = snapshot?.exists == true
            AppLog.firebase.debug("Admin check: uid=\(uid) isAdmin=\(result)")
            guard let self else { return }
            // The launch fetch in init() runs BEFORE this check completes, so at
            // that point isAdmin is still false and hidden (reported) recipes are
            // skipped even for a moderator. Reload the list whenever the admin
            // state actually changes, so admins see what they need to review.
            let changed = self.isAdmin != result
            self.isAdmin = result
            if changed { self.getRecipesFB() }
        }
    }

    /// Completes Sign in with Apple against Firebase using the identity token and
    /// the raw nonce that was hashed into the Apple request. The Apple account's
    /// uid is STABLE across reinstalls, which is what author-only recipes are
    /// tied to; it can also be listed in the `admins` collection for a permanent
    /// admin. On success `isAdmin` and the recipe list refresh.
    ///
    /// The anonymous identity is UPGRADED (linked) rather than replaced, so the
    /// uid — and with it the ownership of everything this device published
    /// before — is preserved. If the Apple account already has an account of its
    /// own (a second device, or a reinstall), that one is signed into instead;
    /// the anonymous uid is then abandoned, which is unavoidable.
    func signInWithApple(idTokenString: String, rawNonce: String, completion: @escaping (Result<Void, Error>) -> Void) {
        let credential = OAuthProvider.appleCredential(withIDToken: idTokenString,
                                                       rawNonce: rawNonce,
                                                       fullName: nil)

        guard let user = Auth.auth().currentUser, user.isAnonymous else {
            signIn(with: credential, completion: completion)
            return
        }

        user.link(with: credential) { [weak self] _, error in
            guard let error = error as NSError? else {
                self?.finishSignIn()
                completion(.success(()))
                return
            }

            guard error.code == AuthErrorCode.credentialAlreadyInUse.rawValue else {
                AppLog.firebase.error("Apple account could not be linked: \(error.localizedDescription)")
                completion(.failure(error))
                return
            }

            // Firebase hands back a fresh credential here; the original one has
            // already been consumed by the failed link attempt.
            let existing = error.userInfo[AuthErrorUserInfoUpdatedCredentialKey] as? AuthCredential ?? credential
            self?.signIn(with: existing, completion: completion)
        }
    }

    private func signIn(with credential: AuthCredential, completion: @escaping (Result<Void, Error>) -> Void) {
        Auth.auth().signIn(with: credential) { [weak self] _, error in
            if let error {
                AppLog.firebase.error("Apple sign-in failed: \(error.localizedDescription)")
                completion(.failure(error))
                return
            }
            self?.finishSignIn()
            completion(.success(()))
        }
    }

    /// Picks up the new identity: moderator rights and the recipes it may see.
    private func finishSignIn() {
        checkAdminStatus()
        getRecipesFB()
    }

    /// Signs the account out and returns to an anonymous identity so browsing
    /// and publishing keep working. The author-only recipes stay in the cloud
    /// and reappear after the next sign-in with the same Apple account.
    func signOutAccount(completion: (() -> Void)? = nil) {
        try? Auth.auth().signOut()
        isAdmin = false
        Auth.auth().signInAnonymously { [weak self] _, error in
            if let error {
                AppLog.firebase.error("Anonymous re-sign-in failed: \(error.localizedDescription)")
            }
            self?.checkAdminStatus()
            // isAdmin was cleared above, so checkAdminStatus() sees no change and
            // won't reload. Fetch explicitly, otherwise hidden recipes loaded as
            // an admin — or the author-only recipes — would stay visible to the
            // now anonymous user.
            self?.getRecipesFB()
            completion?()
        }
    }

    /// Admin/owner moderation: deletes ANY public recipe, not just the caller's
    /// own. Gated by `isAdmin`; the Firestore rules must additionally permit uids
    /// listed in the `admins` collection for this to succeed server-side.
    /// Author-only recipes are never shared, so they are not subject to
    /// moderation and stay out of an admin's reach.
    func deleteRecipeAsAdmin(_ recipe: RecipeFB, completion: ((Result<Void, Error>) -> Void)? = nil) {
        guard recipe.visibility == .everyone, isAdmin else {
            completion?(.success(()))
            return
        }
        performDelete(recipe, completion: completion)
    }

    /// Shared deletion routine: removes the subcollections and the stored image
    /// best-effort, then the recipe document, and updates the in-memory list.
    private func performDelete(_ recipe: RecipeFB, completion: ((Result<Void, Error>) -> Void)? = nil) {
        guard let id = recipe.id, !id.isEmpty else {
            completion?(.success(()))
            return
        }

        let recipeRef = db.collection(recipe.visibility.collectionName).document(id)
        let group = DispatchGroup()

        // instructions subcollection
        group.enter()
        recipeRef.collection("instructions").getDocuments { snapshot, _ in
            snapshot?.documents.forEach { $0.reference.delete() }
            group.leave()
        }

        // components (each with an ingredients subcollection)
        group.enter()
        recipeRef.collection("components").getDocuments { snapshot, _ in
            let components = snapshot?.documents ?? []
            let inner = DispatchGroup()
            for component in components {
                inner.enter()
                component.reference.collection("ingredients").getDocuments { ingredientSnapshot, _ in
                    ingredientSnapshot?.documents.forEach { $0.reference.delete() }
                    component.reference.delete()
                    inner.leave()
                }
            }
            inner.notify(queue: .main) { group.leave() }
        }

        group.notify(queue: .main) {
            if !recipe.image.isEmpty {
                self.storage.reference().child(recipe.imageStoragePath).delete { _ in }
            }
            recipeRef.delete { error in
                if let error {
                    // The recipe was NOT removed server-side, so leave it in the
                    // list and report the failure instead of pretending it worked.
                    AppLog.firebase.error("Could not delete recipe: \(error)")
                    DispatchQueue.main.async { completion?(.failure(error)) }
                } else {
                    // Publish the removal on the main thread so the list refreshes.
                    DispatchQueue.main.async {
                        self.recipesFB.removeAll { $0.id == id }
                        completion?(.success(()))
                    }
                }
            }
        }
    }

    /// Async wrapper around `getRecipesFB` so it can drive `.refreshable`.
    /// Completes once the recipe documents have been (re)loaded.
    @MainActor
    func refresh() async {
        await withCheckedContinuation { continuation in
            getRecipesFB {
                continuation.resume()
            }
        }
    }

    func getInstructionsFB(_ r:RecipeFB, _ recipeDocID:String) {
        
        let collection = db.collection(r.visibility.collectionName).document(recipeDocID).collection("instructions").order(by: "step")
        
        collection.getDocuments  { snapshot, error in
            
            if let snapshot, error == nil {
                
                // Loop through the documents returned
                for doc in snapshot.documents {
                    
                    let i = InstructionFB()
                    
                    i.id          = doc.documentID
                    i.instruction = doc["instruction"] as? String ?? ""
                    i.duration    = doc["duration"] as? Int ?? 0
                    i.startTime   = doc["startTime"] as? Int ?? 0
                    i.step        = doc["step"] as? Double ?? 1
                    i.componentName = doc["componentName"] as? String
                    if let translations = doc["translations"] as? [String: Any] {
                        i.translations = translations.mapValues { InstructionTextFB(firestoreData: $0) }
                    }
                    i.applyLocalization(languageCode: RecipeFB.preferredLanguageCode)

                    r.instructions.append(i)
                }
            }
        }
    }
    
    func getComponentsFB(_ r:RecipeFB, _ recipeDocID:String) {
        
        let collection = db.collection(r.visibility.collectionName).document(recipeDocID).collection("components")
        
        collection.getDocuments  { snapshot, error in
            
            if let snapshot, error == nil {
                
                // Loop through the documents returned
                for doc in snapshot.documents {
                    
                    let c = ComponentFB()
                    
                    c.id     = doc.documentID
                    c.name   = doc["name"] as? String ?? ""
                    c.number = doc["number"] as? Int ?? 0
                    if let translations = doc["translations"] as? [String: Any] {
                        c.translations = translations.mapValues { NamedTextFB(firestoreData: $0) }
                    }
                    c.applyLocalization(languageCode: RecipeFB.preferredLanguageCode)
                    
                    self.getIngredientsFB(c, recipeDocID, c.id!, visibility: r.visibility)
                    r.components.append(c)
                }
            }
        }
    }
    
    func getIngredientsFB(_ c:ComponentFB, _ recipeDocID:String, _ componentDocID:String, visibility: RecipeVisibility = .everyone) {

        let collection = db.collection(visibility.collectionName).document(recipeDocID).collection("components").document(componentDocID).collection("ingredients")
        
        collection.getDocuments  { snapshot, error in
            
            if let snapshot, error == nil {
                
                // Loop through the documents returned
                for doc in snapshot.documents {
                    
                    let i = IngredientFB()
                    
                    i.id         = doc.documentID
                    i.name       = doc["name"]       as? String ?? ""
                    i.number     = doc["number"]     as? Int ?? 0
                    i.unit       = doc["unit"]       as? String ?? ""
                    i.weight     = doc["weight"]     as? Double ?? 0
                    i.normWeight = doc["normWeight"] as? Double ?? i.weight
                    i.num        = doc["num"]        as? Int ?? 0
                    i.denom      = doc["denom"]      as? Int ?? 0
                    if let translations = doc["translations"] as? [String: Any] {
                        i.translations = translations.mapValues { IngredientTextFB(firestoreData: $0) }
                    }
                    i.applyLocalization(languageCode: RecipeFB.preferredLanguageCode)
                    
                    c.ingredients.append(i)
                }
            }
        }
    }
}
