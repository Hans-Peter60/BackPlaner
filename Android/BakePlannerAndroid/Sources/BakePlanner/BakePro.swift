import BakePlannerCore
import Foundation
import Observation
import PlayBilling
import SkipFuse
#if os(Android)
import SkipFirebaseAuth
import SkipFirebaseFirestore
#endif

/// BakePlanner Pro on Android: the switches from Firestore, the one-time
/// purchase from Google Play, and the iPhone's decision
/// (`ProAccess.resolve` in the package) made from both. The switches live
/// in their own document, `config/monetizationAndroid`, so Pro can go live
/// on Android without locking the iPhone before its purchase exists (and
/// the other way round). Fail open: without the document everything is
/// free. Nobody is grandfathered: Android starts with Pro.
@MainActor
@Observable
final class BakePro {
    static let shared = BakePro()

    /// The product in the Play Console: a one-time product, 9,99 €.
    static let productID = "pro"
    static let configDocument = "monetizationAndroid"
    private static let purchasedKey = "pro.purchased"
    private static let configKey = "pro.config"

    private(set) var config: MonetizationConfig { didSet { publish() } }
    private(set) var purchased: Bool { didSet { publish() } }

    /// Whether the oven profiles may be used, readable from anywhere (the
    /// settings reader is not on the main actor). Without Pro the app plans
    /// as if there were no profiles; the saved ones stay and come back with
    /// the purchase.
    nonisolated(unsafe) static var ovenProfilesOpen = true
    private(set) var pending = false
    private(set) var price = ""
    /// Play answered, but without the product (no Play, not in the console).
    private(set) var productUnavailable = false
    /// The feature whose paywall is showing; set by a locked control.
    var offer: ProFeature?
    var showsOffer = false

    private let store = PlayStorePurchase(productID: BakePro.productID)
    private var started = false
    private var seenResults = 0
    /// The outcome of the last purchase ("cancelled", "error 6" …), for the paywall.
    private(set) var lastFailure: String?

    private init() {
        purchased = SettingsFile.value(forKey: Self.purchasedKey) as? Bool ?? false
        if let text = SettingsFile.value(forKey: Self.configKey) as? String, let data = text.data(using: .utf8),
           let cached = try? JSONDecoder().decode(MonetizationConfig.self, from: data) {
            config = cached
        } else {
            config = .free
        }
        publish()
    }

    private func publish() {
        Self.ovenProfilesOpen = resolution.unlocked(.ovenProfiles)
    }

    var resolution: ProResolution {
        ProAccess.resolve(config: config, purchased: purchased, originalAppVersion: nil)
    }

    func isUnlocked(_ feature: ProFeature) -> Bool {
        resolution.unlocked(feature)
    }

    /// Whether settings show the Pro section and locks offer the purchase.
    var storeVisible: Bool {
        resolution.storeVisible || config.proRequired
    }

    /// The paywall for `feature`, shown by the root view.
    func offer(_ feature: ProFeature?) {
        offer = feature
        showsOffer = true
    }

    /// At launch and whenever the app comes to the foreground: the switches
    /// and the purchases read again.
    func start() {
        if !started {
            started = true
            store.start()
        } else {
            store.refresh()
        }
        Task { await refreshConfig() }
        follow(seconds: 15)
    }

    /// Opens Play's purchase sheet.
    func purchase() {
        lastFailure = nil
        if !store.purchase() {
            lastFailure = String(localized: "Der Kauf ist im Moment nicht möglich. Bitte versuche es später noch einmal.", bundle: .module)
            return
        }
        follow(seconds: 300)
    }

    /// Restoring is reading the purchases again: Play keeps them with the
    /// Google account. A code redeemed in the Play Store arrives the same way.
    func restore() {
        lastFailure = nil
        store.start()
        follow(seconds: 20)
    }

    /// The billing module answers by its state; it is copied in here for a
    /// while after each step, so the views can observe it.
    private func follow(seconds: Int) {
        Task {
            for _ in 0..<(seconds * 2) {
                copyState()
                try? await Task.sleep(nanoseconds: 500_000_000)
            }
            copyState()
        }
    }

    private func copyState() {
        if store.state == "ready" && price != store.price { price = store.price }
        let unavailable = store.state == "unavailable"
        if productUnavailable != unavailable { productUnavailable = unavailable }
        if pending != store.pending { pending = store.pending }
        // Only a positive answer from Play changes a cached purchase: no
        // network at launch must not take Pro away.
        if store.purchased && !purchased {
            purchased = true
            SettingsFile.set(true, forKey: Self.purchasedKey)
            showsOffer = false
        }
        if store.resultCount != seenResults {
            seenResults = store.resultCount
            switch store.lastResult {
            case "cancelled", "", "purchased", "owned":
                break
            case "pending":
                lastFailure = String(localized: "Die Zahlung ist noch nicht abgeschlossen. Pro wird freigeschaltet, sobald Google Play sie bestätigt.", bundle: .module)
            default:
                lastFailure = String(localized: "Der Kauf konnte nicht abgeschlossen werden.", bundle: .module)
                logger.error("Pro purchase: \(self.store.lastResult)")
            }
        }
    }

    /// The document `config/monetizationAndroid`, read signed in
    /// anonymously (the rules let any signed-in app read `config/`).
    private func refreshConfig() async {
        #if os(Android)
        do {
            if Auth.auth().currentUser == nil {
                _ = try await Auth.auth().signInAnonymously()
            }
            let snapshot = try await Firestore.firestore().collection("config").document(Self.configDocument).getDocument()
            let fresh = snapshot.exists ? MonetizationConfig(firestoreData: snapshot.data() ?? [:]) : .free
            guard fresh != config else { return }
            config = fresh
            if let data = try? JSONEncoder().encode(fresh), let text = String(data: data, encoding: .utf8) {
                SettingsFile.set(text, forKey: Self.configKey)
            }
            logger.info("Pro config: required \(fresh.proRequired), visible \(fresh.storeVisible)")
        } catch {
            // Keep what was cached; offline is no reason to lock or unlock.
            logger.error("Pro config could not be read: \(error)")
        }
        #endif
    }
}
