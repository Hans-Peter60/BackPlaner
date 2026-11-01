import BakePlannerCore
import Foundation
#if os(Android)
import SkipFirebaseCore
import SkipFirebaseAuth
import SkipFirebaseAppCheck
@preconcurrency import SkipFirebaseFirestore
@preconcurrency import SkipFirebaseStorage
#endif

/// The public recipes in Firebase, shared with the iPhone: the same project,
/// documents and rules (RecipeFirestoreMapping). Android only — the Apple
/// build of this app has no Firebase configuration and lists none.
enum PublicRecipeService {

    enum ServiceError: Error {
        /// The Apple build of the Android app has no Firebase.
        case unavailable
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

    #if os(Android)
    @MainActor
    private static func signInIfNeeded() async throws {
        if Auth.auth().currentUser == nil {
            _ = try await Auth.auth().signInAnonymously()
        }
    }
    #endif
}
