import BakePlannerCore
import Foundation
#if os(Android)
import SkipFirebaseCore
import SkipFirebaseAuth
import SkipFirebaseAppCheck
@preconcurrency import SkipFirebaseFirestore
@preconcurrency import SkipFirebaseStorage
@preconcurrency import SkipFirebaseFunctions
#endif

/// The public recipes in Firebase, shared with the iPhone: the same project,
/// documents and rules (RecipeFirestoreMapping). Android only — the Apple
/// build of this app has no Firebase configuration and lists none.
enum PublicRecipeService {

    enum ServiceError: Error {
        /// The Apple build of the Android app has no Firebase.
        case unavailable
        /// The cloud function answered with something that is no recipe.
        case invalidResponse
    }

    /// Has the cloud AI read the text of a recipe page (Cloud Function
    /// analyzeRecipeText, as the iPhone calls it). The page was loaded on
    /// the device; only its text and address are sent. Without Pro the
    /// function's monthly allowance applies.
    @MainActor
    static func analyzeRecipeText(_ text: String, sourceURL: URL) async throws -> CloudRecipeAnalysis {
        #if os(Android)
        try await signInIfNeeded()
        let callable = Functions.functions(region: "europe-west1").httpsCallable("analyzeRecipeText")
        callable.timeoutInterval = 250
        let address = sourceURL.absoluteString
        let payload: [String: Any] = ["text": text, "sourceURL": address]
        let result = try await callable.call(payload)
        guard let analysis = CloudRecipeAnalysis(response: result.data) else {
            throw ServiceError.invalidResponse
        }
        return analysis
        #else
        throw ServiceError.unavailable
        #endif
    }

    /// Sets Firebase up from google-services.json, with App Check before any
    /// request: Firestore refuses requests without it. The debug provider
    /// prints a token to the log on the first start ("Enter this debug
    /// secret into the allow list …"), which is registered once in the
    /// Firebase console; Play Integrity follows with the Play Store release.
    static func configure() {
        #if os(Android)
        FirebaseApp.configure()
        AppCheck.setAppCheckProviderFactory(AppCheckDebugProviderFactory())
        #endif
    }

    /// The visible public recipes, without components and steps, in the
    /// app's language where a translation is stored. Signs in anonymously
    /// first, as the iPhone does. The rules hand out only recipes that are
    /// not reported, and a query has to ask for exactly these.
    @MainActor
    static func recipes() async throws -> [RecipeFB] {
        #if os(Android)
        try await signInIfNeeded()
        let snapshot = try await Firestore.firestore()
            .collection(RecipeFB.collectionName)
            .whereField("hidden", isEqualTo: false)
            .getDocuments()
        return snapshot.documents.map { document in
            let recipe = RecipeFirestoreMapping.recipe(id: document.documentID, data: document.data())
            recipe.applyPreferredLocalization()
            return recipe
        }
        #else
        throw ServiceError.unavailable
        #endif
    }

    /// Reads a recipe's components (with their ingredients) and steps into
    /// it, unless they are there already, in the app's language.
    @MainActor
    static func loadDetails(of recipe: RecipeFB) async throws {
        #if os(Android)
        guard let id = recipe.id, recipe.components.isEmpty || recipe.instructions.isEmpty else { return }
        try await signInIfNeeded()
        let recipeDocument = Firestore.firestore().collection(RecipeFB.collectionName).document(id)

        let componentDocuments = try await recipeDocument
            .collection(RecipeFirestoreMapping.componentsCollection).getDocuments().documents
        var components: [ComponentFB] = []
        for document in componentDocuments {
            let component = RecipeFirestoreMapping.component(id: document.documentID, data: document.data())
            let ingredientDocuments = try await recipeDocument
                .collection(RecipeFirestoreMapping.componentsCollection).document(document.documentID)
                .collection(RecipeFirestoreMapping.ingredientsCollection).getDocuments().documents
            component.ingredients = ingredientDocuments.map {
                RecipeFirestoreMapping.ingredient(id: $0.documentID, data: $0.data())
            }
            components.append(component)
        }

        let instructionDocuments = try await recipeDocument
            .collection(RecipeFirestoreMapping.instructionsCollection).order(by: "step").getDocuments().documents
        let instructions = instructionDocuments.map {
            RecipeFirestoreMapping.instruction(id: $0.documentID, data: $0.data())
        }

        recipe.components = components
        recipe.instructions = instructions
        recipe.applyPreferredLocalization()
        #else
        throw ServiceError.unavailable
        #endif
    }

    /// The recipe's picture from Storage, nil when it has none or it cannot
    /// be read. Pictures are uploaded at most 1024 pixels wide, well below
    /// the limit.
    @MainActor
    static func imageData(of recipe: RecipeFB) async -> Data? {
        #if os(Android)
        guard !recipe.image.isEmpty else { return nil }
        do {
            try await signInIfNeeded()
            return try await Storage.storage().reference().child(recipe.imageStoragePath)
                .getDataAsync(maxSize: 5 * 1024 * 1024)
        } catch {
            logger.error("Picture of public recipe \(recipe.id ?? "") could not be read: \(error)")
            return nil
        }
        #else
        return nil
        #endif
    }

    /// Reports a public recipe, as the iPhone does: the report (once per
    /// reporter, the rules refuse a second one), and the recipe withheld
    /// from every user until an admin has looked at it. The time filed is
    /// the device's: the server-timestamp sentinel of the Android SDK does
    /// not reach native Swift.
    @MainActor
    static func report(_ recipe: RecipeFB, reason: String) async throws {
        #if os(Android)
        guard let recipeID = recipe.id, !recipeID.isEmpty else { return }
        try await signInIfNeeded()
        let reporter = Auth.auth().currentUser?.uid ?? ""
        let authorID = recipe.authorId ?? ""
        var report = RecipeFirestoreMapping.reportData(recipeId: recipeID, authorId: authorID,
                                                       reason: reason, reporter: reporter)
        report["createdAt"] = Date()
        let firestore = Firestore.firestore()
        try await firestore.collection(RecipeFirestoreMapping.reportsCollection)
            .document(RecipeFirestoreMapping.reportID(recipeId: recipeID, reporter: reporter))
            .setData(report)
        try await firestore.collection(RecipeFB.collectionName).document(recipeID)
            .updateData(RecipeFirestoreMapping.reportHideData)
        #else
        throw ServiceError.unavailable
        #endif
    }

    // MARK: Account

    /// Who is signed in: anonymous, or with an Apple account (the same uid
    /// as on the iPhone, so recipes published there count as one's own).
    struct Account: Equatable {
        var isSignedInWithApple = false
        var isAdmin = false
    }

    @MainActor
    static func account() async -> Account {
        #if os(Android)
        guard let user = Auth.auth().currentUser, !user.isAnonymous else { return Account() }
        return Account(isSignedInWithApple: true, isAdmin: await isAdmin(uid: user.uid))
        #else
        return Account()
        #endif
    }

    /// Signs in with Apple in the browser (Android has no native "Sign in
    /// with Apple"; Firebase opens Apple's page and comes back). The
    /// anonymous Android account is left, not linked: it owns nothing but
    /// reports, and linking an Apple ID already in use would take a second
    /// pass through the browser. No e-mail is asked for, as on the iPhone.
    @MainActor
    static func signInWithApple() async throws {
        #if os(Android)
        _ = try await Auth.auth().signIn(with: OAuthProvider(providerID: "apple.com"))
        #else
        throw ServiceError.unavailable
        #endif
    }

    /// Signs out and carries on anonymously, as the iPhone does.
    @MainActor
    static func signOut() async throws {
        #if os(Android)
        try Auth.auth().signOut()
        _ = try await Auth.auth().signInAnonymously()
        #else
        throw ServiceError.unavailable
        #endif
    }

    /// Deletes the Apple account's Firebase account, then carries on
    /// anonymously. Firebase refuses the deletion when the sign-in is not
    /// recent; then Apple is asked once more in the browser and the deletion
    /// tried again. Recipes published under the account stay public.
    @MainActor
    static func deleteAccount() async throws {
        #if os(Android)
        guard let user = Auth.auth().currentUser, !user.isAnonymous else { return }
        do {
            try await user.delete()
        } catch {
            logger.info("Account deletion needs a fresh sign-in: \(error)")
            _ = try await user.reauthenticate(with: OAuthProvider(providerID: "apple.com"))
            try await user.delete()
        }
        _ = try await Auth.auth().signInAnonymously()
        #else
        throw ServiceError.unavailable
        #endif
    }

    #if os(Android)
    /// An admin has a document under `admins/{uid}`, as on the iPhone; the
    /// rules let each user read only his own.
    @MainActor
    private static func isAdmin(uid: String) async -> Bool {
        do {
            return try await Firestore.firestore().collection("admins").document(uid).getDocument().exists
        } catch {
            logger.error("Admin status could not be read: \(error)")
            return false
        }
    }

    @MainActor
    private static func signInIfNeeded() async throws {
        if Auth.auth().currentUser == nil {
            _ = try await Auth.auth().signInAnonymously()
        }
    }
    #endif
}
