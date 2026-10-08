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
/// Why deleting the account could not be carried out.
enum AccountDeletionError: LocalizedError {
    /// Firebase refuses to delete a user whose sign-in is no longer recent.
    /// The caller has to reauthenticate and try again.
    case requiresRecentLogin
    case notSignedIn

    var errorDescription: String? {
        switch self {
        case .requiresRecentLogin:
            return "Zur Sicherheit ist eine erneute Anmeldung nötig, bevor das Konto gelöscht werden kann."
        case .notSignedIn:
            return "Es ist kein Konto angemeldet, das gelöscht werden könnte."
        }
    }
}

enum PrivateRecipeError: LocalizedError {
    case accountRequired
    /// Whether a cloud copy still exists cannot be decided while signed out,
    /// because the author-only collection is unreadable for anonymous users.
    case ownershipUnknown

    var errorDescription: String? {
        switch self {
        case .accountRequired:
            return "Für private Cloud-Rezepte ist eine Anmeldung mit Apple erforderlich. Ohne Konto wäre das Rezept nach einer Neuinstallation nicht mehr erreichbar."
        case .ownershipUnknown:
            return "Ob dieses Rezept noch in der Cloud liegt, lässt sich nur mit angemeldetem Konto feststellen."
        }
    }
}

/// Why an edited cloud recipe could not be written back.
enum RecipeEditError: LocalizedError {
    case notSignedIn

    var errorDescription: String? {
        switch self {
        case .notSignedIn:
            return "Das Rezept kann gerade nicht gespeichert werden, weil keine Anmeldung besteht. Bitte versuche es gleich noch einmal."
        }
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


    /// True when the signed-in (anonymous) user is a moderator/owner, i.e. their
    /// uid has a document in the Firestore `admins` collection. Admins may delete
    /// any public recipe, not just their own.
    @Published var isAdmin = false

    /// True once the user signed in with Apple, which turns the anonymous
    /// identity into a permanent one. Only then can author-only recipes be
    /// stored in the cloud and found again after a reinstall.
    @Published var isSignedInWithAccount = false

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
            // The account's email is deliberately never read. Sign in with
            // Apple is requested without the email scope, so the app has no
            // use for it, and not touching it keeps the privacy policy's
            // promise true of the code as well as of the request.
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

        // The recipe's language is the language of ITS OWN text, not the one the
        // app happens to be set to. Stamping the interface language filed a
        // French recipe entered in a German app as German, and the translation
        // menu then had no way back into German.
        let sourceLanguage = r.sourceLanguage.isEmpty
            ? (RecipeLanguageDetector.detectedLanguage(of: r) ?? RecipeFB.preferredLanguageCode)
            : RecipeFB.baseLanguageCode(from: r.sourceLanguage)

        // A recipe being published from a private copy may be showing a
        // translation right now; put the original back before snapshotting it.
        if r.hasCachedTranslation(languageCode: sourceLanguage) {
            r.showLocalization(languageCode: sourceLanguage)
        }
        r.sourceLanguage = sourceLanguage
        r.storeLocalization(languageCode: sourceLanguage)

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
        // The list query asks for `hidden == false`, and Firestore never
        // matches a missing field, so a public recipe has to carry it from the
        // start. The rules refuse a new public recipe without it.
        if visibility == .everyone {
            recipeData["hidden"] = false
        }

        group.enter()
        let cloudRecipe = cloudRecipes.document(r.id ?? UUID().uuidString)
        cloudRecipe.setData(recipeData) { error in
            if let error { firstError = firstError ?? error }
            group.leave()
        }

        // The loop below adds up every ingredient, so the counter has to start
        // at zero. Uploading a recipe that already carried a total — one coming
        // from Core Data or from the image import — would otherwise store twice
        // its actual weight.
        r.totalWeight = 0

        // Set the components
        for c in r.components {

            let cloudComponent = cloudRecipe.collection("components").addDocument(data: componentData(for: c))

            for i in c.ingredients {

                // Normalise BEFORE writing the document. The other way round the
                // ingredient kept whatever normWeight it happened to carry while
                // the recipe total was summed from the fresh value — so the
                // stored ingredients disagreed with the stored total.
                normalizeWeight(of: i)
                r.totalWeight += i.normWeight

                // Create an ingredient document
                let _ = cloudComponent.collection("ingredients").addDocument(data: ingredientData(for: i))
            }
        }

        // Set the Instructions
        for i in calculatedInstructions {
            let _ = cloudRecipe.collection("instructions").addDocument(data: instructionData(for: i))
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

        // Recipe-level translations. The source language travels with them: a
        // recipe whose language was corrected must not be read back with the
        // old one, or the correction would have to be repeated on every device.
        let recipeTranslations = recipe.firestoreTranslationsData
        if recipeTranslations[source] != nil {
            recipeRef.updateData([
                "translations": recipeTranslations,
                "sourceLanguage": source
            ])
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

    // MARK: - Document shapes

    /// Sets the ingredient's normalised weight from its amount and unit.
    private func normalizeWeight(of ingredient: IngredientFB) {
        if ingredient.unit == "g" || ingredient.unit == "Gramm" {
            ingredient.normWeight = ingredient.weight
        } else {
            ingredient.normWeight = calcWeight.calcIngredientWeight(weight: ingredient.weight,
                                                                    unit: ingredient.unit,
                                                                    name: ingredient.name,
                                                                    num: ingredient.num,
                                                                    denom: ingredient.denom)
        }
    }

    private func componentData(for component: ComponentFB) -> [String: Any] {
        var data: [String: Any] = [
            "name":   component.name,
            "number": component.number
        ]
        let translations = component.firestoreTranslationsData
        if !translations.isEmpty {
            data["translations"] = translations
        }
        return data
    }

    private func ingredientData(for ingredient: IngredientFB) -> [String: Any] {
        var data: [String: Any] = [
            "name":       ingredient.name,
            "number":     ingredient.number,
            "unit":       ingredient.unit,
            "weight":     ingredient.weight,
            "normWeight": ingredient.normWeight,
            "num":        ingredient.num,
            "denom":      ingredient.denom
        ]
        let translations = ingredient.firestoreTranslationsData
        if !translations.isEmpty {
            data["translations"] = translations
        }
        return data
    }

    private func instructionData(for instruction: InstructionFB) -> [String: Any] {
        var data: [String: Any] = [
            "instruction": instruction.instruction,
            "step":        instruction.step,
            "duration":    instruction.duration,
            "startTime":   instruction.startTime ?? 0,
            "date":        instruction.date ?? 0
        ]
        if let componentName = instruction.componentName {
            data["componentName"] = componentName
        }
        let translations = instruction.firestoreTranslationsData
        if !translations.isEmpty {
            data["translations"] = translations
        }
        return data
    }

    // MARK: - Editing a cloud recipe

    /// Writes an edited recipe back to its cloud document: the author's own
    /// recipe, or — for a public one — any recipe an admin corrects. The
    /// security rules allow exactly these two cases server-side.
    ///
    /// The recipe document is updated in place. Its components, ingredients
    /// and steps are replaced wholesale, in one batch: the editor may have
    /// added, removed and reordered them, and a diff would have to track all
    /// of that only to arrive at the same documents. The batch also means a
    /// failure leaves the stored version untouched. A recipe stays far below
    /// the batch limit of 500 writes.
    ///
    /// On success `recipe` takes over the edited content, so the screen that
    /// shows it — and its entry in the list — update without a reload.
    func saveEdits(of recipe: RecipeFB, from edited: RecipeFB, newImage: UIImage?, completion: @escaping (Result<Void, Error>) -> Void) {
        guard let recipeId = recipe.id, !recipeId.isEmpty, let currentUser = Auth.auth().currentUser else {
            completion(.failure(RecipeEditError.notSignedIn))
            return
        }

        // The picture first: a document naming a picture that failed to
        // upload would be worse than keeping the old picture.
        uploadReplacementImage(newImage, owner: currentUser.uid, visibility: edited.visibility) { [weak self] imageResult in
            guard let self else { return }

            let newImagePath: String?
            switch imageResult {
            case .failure(let error):
                DispatchQueue.main.async { completion(.failure(error)) }
                return
            case .success(let path):
                newImagePath = path
            }

            let previousImagePath = edited.image
            if let newImagePath { edited.image = newImagePath }

            self.replaceRecipeContent(recipeId: recipeId, edited: edited) { result in
                DispatchQueue.main.async {
                    switch result {
                    case .failure(let error):
                        // The document still names the old picture, so the
                        // new one would be an orphan.
                        if let newImagePath {
                            self.storage.reference()
                                .child(edited.visibility.imageFolder + "/" + newImagePath + ".jpg")
                                .delete { _ in }
                            edited.image = previousImagePath
                        }
                        completion(.failure(error))

                    case .success:
                        if newImagePath != nil, let newImage {
                            if !previousImagePath.isEmpty {
                                // Best effort, as when deleting a recipe.
                                self.storage.reference()
                                    .child(edited.visibility.imageFolder + "/" + previousImagePath + ".jpg")
                                    .delete { _ in }
                            }
                            GlobalVariables.recipesImage[recipeId] = newImage
                        }
                        recipe.adopt(edited)
                        completion(.success(()))
                    }
                }
            }
        }
    }

    /// Stores a replacement picture under the caller's own uid and hands back
    /// its path, or nil when there is no new picture. A fresh path rather than
    /// overwriting the old one: an admin may not write into another author's
    /// folder, and the old picture is only removed once the document names
    /// the new one.
    private func uploadReplacementImage(_ image: UIImage?,
                                        owner uid: String,
                                        visibility: RecipeVisibility,
                                        completion: @escaping (Result<String?, Error>) -> Void) {
        guard let image else {
            completion(.success(nil))
            return
        }

        let uploadImage = image.scaledDownForUpload(maxPixelDimension: 1_024)
        guard let data = uploadImage.jpegData(compressionQuality: 0.5) else {
            completion(.failure(RecipeImageUploadError.encodingFailed))
            return
        }

        let path     = uid + "/" + UUID().uuidString
        let metadata = StorageMetadata()
        metadata.contentType = "image/jpeg"

        storage.reference().child(visibility.imageFolder + "/" + path + ".jpg").putData(data, metadata: metadata) { _, error in
            if let error {
                AppLog.firebase.error("Replacement image upload failed: \(error.localizedDescription)")
                completion(.failure(error))
            } else {
                completion(.success(path))
            }
        }
    }

    /// Updates the recipe document and swaps its subcollections for the
    /// edited ones, atomically.
    private func replaceRecipeContent(recipeId: String, edited: RecipeFB, completion: @escaping (Result<Void, Error>) -> Void) {
        let recipeRef = db.collection(edited.visibility.collectionName).document(recipeId)

        // The editor shows and changes the original text, so the cached
        // translations of the other languages are stale now: they translate a
        // recipe that no longer exists, and left in place they would show
        // other users the old recipe under the new name. They are translated
        // again on demand.
        edited.resetTranslations(keeping: RecipeTranslator.sourceLanguageCode(for: edited))

        // The same bookkeeping as the upload: start times and the total
        // duration follow from the steps, the total weight from the ingredients.
        edited.instructions = Rational.calculateStartTimes(
            edited.instructions,
            Date(),
            dependencies: Rational.ComponentDependency.from(edited.components)
        )
        edited.prepTime    = GlobalVariables.totalDuration
        edited.totalWeight = 0
        for component in edited.components {
            for ingredient in component.ingredients {
                normalizeWeight(of: ingredient)
                edited.totalWeight += ingredient.normWeight
            }
        }

        // The stored children have to be read before they can be deleted; the
        // in-memory recipe may not have finished loading them when the editor
        // opened. Unlike a deletion this must not carry on past a read error,
        // or the leftovers would show up as duplicates.
        fetchChildReferences(of: recipeRef) { [weak self] result in
            guard let self else { return }

            let existingChildren: [DocumentReference]
            switch result {
            case .failure(let error):
                completion(.failure(error))
                return
            case .success(let references):
                existingChildren = references
            }

            let batch = self.db.batch()
            existingChildren.forEach { batch.deleteDocument($0) }

            // `authorId`, `hidden` and `visibility` are deliberately left
            // alone: the rules refuse an author who changes them.
            batch.updateData([
                "name":           edited.name,
                "summary":        edited.summary,
                "urlLink":        edited.urlLink,
                "image":          edited.image,
                "tags":           edited.tags,
                "prepTime":       edited.prepTime,
                "totalWeight":    edited.totalWeight,
                "sourceLanguage": edited.sourceLanguage,
                "translations":   edited.firestoreTranslationsData
            ], forDocument: recipeRef)

            for component in edited.components {
                let componentRef = recipeRef.collection("components").document()
                component.id = componentRef.documentID
                batch.setData(self.componentData(for: component), forDocument: componentRef)

                for ingredient in component.ingredients {
                    let ingredientRef = componentRef.collection("ingredients").document()
                    ingredient.id = ingredientRef.documentID
                    batch.setData(self.ingredientData(for: ingredient), forDocument: ingredientRef)
                }
            }

            for instruction in edited.instructions {
                let instructionRef = recipeRef.collection("instructions").document()
                instruction.id = instructionRef.documentID
                batch.setData(self.instructionData(for: instruction), forDocument: instructionRef)
            }

            batch.commit { error in
                if let error {
                    AppLog.firebase.error("Recipe edit could not be saved: \(error.localizedDescription)")
                    completion(.failure(error))
                } else {
                    completion(.success(()))
                }
            }
        }
    }

    /// The references of every stored component, ingredient and step of a
    /// recipe. Firestore delivers its callbacks on the main queue, so the
    /// array needs no lock.
    private func fetchChildReferences(of recipeRef: DocumentReference, completion: @escaping (Result<[DocumentReference], Error>) -> Void) {
        var references = [DocumentReference]()
        var firstError: Error?
        let group = DispatchGroup()

        group.enter()
        recipeRef.collection("instructions").getDocuments { snapshot, error in
            if let error { firstError = firstError ?? error }
            references += (snapshot?.documents ?? []).map(\.reference)
            group.leave()
        }

        group.enter()
        recipeRef.collection("components").getDocuments { snapshot, error in
            if let error { firstError = firstError ?? error }
            for component in snapshot?.documents ?? [] {
                references.append(component.reference)
                // Entered before the outer leave below, so the group cannot
                // run dry while ingredients are still being read.
                group.enter()
                component.reference.collection("ingredients").getDocuments { ingredientSnapshot, ingredientError in
                    if let ingredientError { firstError = firstError ?? ingredientError }
                    references += (ingredientSnapshot?.documents ?? []).map(\.reference)
                    group.leave()
                }
            }
            group.leave()
        }

        group.notify(queue: .main) {
            if let firstError {
                completion(.failure(firstError))
            } else {
                completion(.success(references))
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
        // The rules hand out a reported (hidden) public recipe to admins and
        // its author only, and a query has to prove it asks for nothing else:
        // without this filter the whole list would be refused. Admins query
        // unfiltered so they still see what they have to review.
        if visibility == .everyone && !isAdmin {
            query = query.whereField("hidden", isEqualTo: false)
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
                // (App Store Guideline 1.2). The query already leaves it out
                // for everyone but admins, and the rules refuse it; this check
                // only keeps the list right should either ever change.
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
        // An anonymous user cannot read the author-only collection at all. A
        // "not found" would then be a guess, and acting on it would re-enable
        // the upload buttons for a recipe that does exist privately — an
        // accidental duplicate in the cloud. Report that nothing is known
        // instead, which leaves the buttons as they are.
        guard let user = Auth.auth().currentUser, !user.isAnonymous else {
            db.collection(RecipeVisibility.everyone.collectionName).document(id).getDocument { snapshot, error in
                DispatchQueue.main.async {
                    if let error {
                        completion(.failure(error))
                    } else if snapshot?.exists == true {
                        completion(.success(true))
                    } else {
                        completion(.failure(PrivateRecipeError.ownershipUnknown))
                    }
                }
            }
            return
        }

        let collections = RecipeVisibility.allCases

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
    ///
    /// `isSignedInWithAccount` is refreshed here rather than left to the auth
    /// state listener. Linking an Apple credential onto the anonymous user
    /// keeps the same uid, so `addStateDidChangeListener` never fires — and the
    /// whole app would go on believing nobody is signed in until the next
    /// launch: no account section in the settings, and the save flow asking to
    /// sign in again although it just happened.
    private func finishSignIn() {
        let user = Auth.auth().currentUser
        isSignedInWithAccount = user != nil && user?.isAnonymous == false
        checkAdminStatus()
        getRecipesFB()
    }

    /// Deletes the signed-in account for good (App Store Guideline 5.1.1(v)
    /// requires this wherever an app lets people create one).
    ///
    /// Removed are the author-only recipes with their subcollections and their
    /// images, then the account itself. PUBLISHED recipes deliberately stay:
    /// they are shared content other users may already be baking from. Their
    /// `authorId` then points at an account that no longer exists, so only an
    /// admin can take them down afterwards.
    ///
    /// Recipes stored on the device are untouched — they belong to the device
    /// and its iCloud, not to this account.
    func deleteAccount(completion: @escaping (Result<Void, Error>) -> Void) {
        guard let user = Auth.auth().currentUser, !user.isAnonymous else {
            completion(.failure(AccountDeletionError.notSignedIn))
            return
        }
        let uid = user.uid

        deletePrivateRecipes(of: uid) { [weak self] in
            guard let self else { return }

            // Sweep the whole image folder afterwards, so an upload that failed
            // halfway does not leave a private picture behind.
            self.deletePrivateImages(of: uid) {
                user.delete { error in
                    DispatchQueue.main.async {
                        if let error = error as NSError? {
                            if error.code == AuthErrorCode.requiresRecentLogin.rawValue {
                                completion(.failure(AccountDeletionError.requiresRecentLogin))
                            } else {
                                AppLog.firebase.error("Account could not be deleted: \(error.localizedDescription)")
                                completion(.failure(error))
                            }
                            return
                        }

                        // The account is gone; carry on anonymously so browsing
                        // and publishing keep working.
                        self.isAdmin = false
                        Auth.auth().signInAnonymously { _, signInError in
                            if let signInError {
                                AppLog.firebase.error("Anonymous re-sign-in after deletion failed: \(signInError.localizedDescription)")
                            }
                            self.getRecipesFB()
                            completion(.success(()))
                        }
                    }
                }
            }
        }
    }

    /// Deletes every author-only recipe of `uid`, each with its subcollections
    /// and its image, and takes them out of the in-memory list.
    private func deletePrivateRecipes(of uid: String, completion: @escaping () -> Void) {
        db.collection(RecipeVisibility.authorOnly.collectionName)
            .whereField("authorId", isEqualTo: uid)
            .getDocuments { [weak self] snapshot, error in
                guard let self else { return }

                if let error {
                    AppLog.firebase.error("Private recipes could not be listed for deletion: \(error.localizedDescription)")
                }

                let documents = snapshot?.documents ?? []
                guard !documents.isEmpty else {
                    completion()
                    return
                }

                let group = DispatchGroup()
                for document in documents {
                    // A stand-in carrying just what performDelete needs, so the
                    // deletion does not depend on the list having been loaded.
                    let recipe = RecipeFB()
                    recipe.id         = document.documentID
                    recipe.authorId   = uid
                    recipe.visibility = .authorOnly
                    recipe.image      = document["image"] as? String ?? ""

                    group.enter()
                    self.performDelete(recipe) { _ in group.leave() }
                }
                group.notify(queue: .main) { completion() }
            }
    }

    /// Empties the account's private image folder. Best effort: a leftover
    /// object must not stop the account from being deleted.
    private func deletePrivateImages(of uid: String, completion: @escaping () -> Void) {
        let folder = storage.reference().child("\(RecipeVisibility.authorOnly.imageFolder)/\(uid)")

        folder.listAll { result, error in
            if let error {
                AppLog.firebase.error("Private images could not be listed: \(error.localizedDescription)")
                completion()
                return
            }

            let items = result?.items ?? []
            guard !items.isEmpty else {
                completion()
                return
            }

            let group = DispatchGroup()
            for item in items {
                group.enter()
                item.delete { _ in group.leave() }
            }
            group.notify(queue: .main) { completion() }
        }
    }

    /// Confirms the identity again with a fresh Apple credential, which is what
    /// Firebase demands before deleting an account that signed in a while ago.
    func reauthenticateWithApple(idTokenString: String, rawNonce: String, completion: @escaping (Result<Void, Error>) -> Void) {
        guard let user = Auth.auth().currentUser else {
            completion(.failure(AccountDeletionError.notSignedIn))
            return
        }

        let credential = OAuthProvider.appleCredential(withIDToken: idTokenString,
                                                       rawNonce: rawNonce,
                                                       fullName: nil)
        user.reauthenticate(with: credential) { _, error in
            DispatchQueue.main.async {
                if let error {
                    AppLog.firebase.error("Reauthentication failed: \(error.localizedDescription)")
                    completion(.failure(error))
                } else {
                    completion(.success(()))
                }
            }
        }
    }

    /// Signs the account out and returns to an anonymous identity so browsing
    /// and publishing keep working. The author-only recipes stay in the cloud
    /// and reappear after the next sign-in with the same Apple account.
    func signOutAccount(completion: ((Result<Void, Error>) -> Void)? = nil) {
        // Reports a failure instead of swallowing it: this used to be `try?`,
        // so a sign-out that did not happen looked exactly like one that did.
        do {
            try Auth.auth().signOut()
        } catch {
            AppLog.firebase.error("Sign-out failed: \(error.localizedDescription)")
            completion?(.failure(error))
            return
        }

        // Set here rather than waiting for the auth state listener, for the same
        // reason `finishSignIn` does: the settings must not lag behind the
        // identity they describe.
        isSignedInWithAccount = false
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
            // The sign-out itself succeeded even if the anonymous re-sign-in
            // did not, so the user is told what he asked about; the log records
            // the rest.
            completion?(.success(()))
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

    /// Loads a recipe's components (with their ingredients) and steps if they
    /// are not there yet, and reports once both have arrived. The baking tab,
    /// the details tab and the automatic translation all need the complete
    /// recipe, and the ingredients come in one request per component.
    func loadDetails(of recipe: RecipeFB, completion: @escaping () -> Void) {
        let recipeId = recipe.id ?? ""
        let group = DispatchGroup()

        if recipe.components.isEmpty {
            group.enter()
            getComponentsFB(recipe, recipeId) { group.leave() }
        }
        if recipe.instructions.isEmpty {
            group.enter()
            getInstructionsFB(recipe, recipeId) { group.leave() }
        }

        group.notify(queue: .main, execute: completion)
    }

    func getInstructionsFB(_ r:RecipeFB, _ recipeDocID:String, completion: (() -> Void)? = nil) {

        let collection = db.collection(r.visibility.collectionName).document(recipeDocID).collection("instructions").order(by: "step")

        collection.getDocuments  { snapshot, error in

            defer { completion?() }

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
    
    /// `completion` runs once the components and all of their ingredients are in.
    func getComponentsFB(_ r:RecipeFB, _ recipeDocID:String, completion: (() -> Void)? = nil) {

        let collection = db.collection(r.visibility.collectionName).document(recipeDocID).collection("components")

        collection.getDocuments  { snapshot, error in

            let ingredientLoads = DispatchGroup()

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

                    ingredientLoads.enter()
                    self.getIngredientsFB(c, recipeDocID, c.id!, visibility: r.visibility) { ingredientLoads.leave() }
                    r.components.append(c)
                }
            }

            ingredientLoads.notify(queue: .main) { completion?() }
        }
    }

    func getIngredientsFB(_ c:ComponentFB, _ recipeDocID:String, _ componentDocID:String, visibility: RecipeVisibility = .everyone, completion: (() -> Void)? = nil) {

        let collection = db.collection(visibility.collectionName).document(recipeDocID).collection("components").document(componentDocID).collection("ingredients")

        collection.getDocuments  { snapshot, error in

            defer { completion?() }

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
