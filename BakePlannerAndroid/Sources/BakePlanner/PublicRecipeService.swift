import BakePlannerCore
import Foundation
#if os(Android)
import SkipFirebaseCore
import SkipFirebaseAuth
import SkipFirebaseAppCheck
@preconcurrency import SkipFirebaseFirestore
#endif

/// The public recipes in Firebase, shared with the iPhone: the same project,
/// documents and rules (RecipeFirestoreMapping). Android only — the Apple
/// build of this app has no Firebase configuration and leaves them out.
enum PublicRecipeService {

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

    /// The outcome of the connection check (step 11b): how many public
    /// recipes are visible, or what went wrong.
    enum ConnectionCheck: Equatable {
        case recipes(Int)
        case failed(String)
        case unavailable
    }

    /// Signs in anonymously, as the iPhone does, and counts the visible
    /// public recipes. The rules hand out only those not reported, and a
    /// query has to ask for exactly these.
    @MainActor
    static func checkConnection() async -> ConnectionCheck {
        #if os(Android)
        do {
            if Auth.auth().currentUser == nil {
                _ = try await Auth.auth().signInAnonymously()
            }
            let snapshot = try await Firestore.firestore()
                .collection(RecipeFB.collectionName)
                .whereField("hidden", isEqualTo: false)
                .getDocuments()
            return .recipes(snapshot.documents.count)
        } catch {
            logger.error("Public recipes could not be read: \(error)")
            return .failed(error.localizedDescription)
        }
        #else
        return .unavailable
        #endif
    }
}
