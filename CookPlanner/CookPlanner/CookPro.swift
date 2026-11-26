//
//  CookPro.swift
//  CookPlanner
//
//  CookPlanner Pro: one non-consumable purchase, bought once. Three parts,
//  as in BakePlanner:
//
//  - `CookProStore` talks to StoreKit: loads the product, buys and
//    restores it, follows the transactions the App Store delivers on its
//    own (a purchase on the iPad, a refund).
//  - `CookProConfigStore` reads the switches from the Firestore document
//    `config/cookplannerMonetization` (proRequired, storeVisible,
//    freeImportsPerMonth) through Firestore's REST interface — the app has
//    no Firestore SDK, and one document a launch does not need one.
//  - `CookPro` answers "may this feature be used?" from both, through the
//    package's `KitchenProAccess`. Every Pro call site asks here.
//
//  Fail open: without a loaded configuration nothing is locked, so the app
//  works offline on first launch and stays fully usable until the purchase
//  exists in App Store Connect and the switch is turned on.
//

import BakePlannerCore
import FirebaseAppCheck
import FirebaseAuth
import FirebaseCore
import Foundation
import Observation
import StoreKit
import os

@Observable
@MainActor
final class CookPro {

    static let shared = CookPro(configStore: .shared, store: .shared)

    private let configStore: CookProConfigStore
    private let store: CookProStore

    init(configStore: CookProConfigStore, store: CookProStore) {
        self.configStore = configStore
        self.store = store
    }

    var config: MonetizationConfig { configStore.config }
    var hasPurchased: Bool { store.hasPurchased }

    /// Whether `feature` may be used right now.
    func isUnlocked(_ feature: KitchenProFeature) -> Bool {
        KitchenProAccess.unlocked(feature, config: config, purchased: store.hasPurchased)
    }

    /// Whether the settings show the Pro section.
    var storeVisible: Bool {
        KitchenProAccess.storeVisible(config: config, purchased: store.hasPurchased)
    }

    /// What a cloud analysis sends so the Functions can verify Pro for
    /// themselves: the App Store's signed purchase. Empty without one.
    var proClaim: [String: String] {
        guard store.hasPurchased, let jws = store.purchaseJWS else { return [:] }
        return ["proTransaction": jws]
    }

    /// Starts the configuration and the store. Called once at launch.
    func start() {
        configStore.start()
        store.start()
    }
}

// MARK: - StoreKit

@Observable
@MainActor
final class CookProStore {

    static let shared = CookProStore()

    /// The product as configured in App Store Connect (and in
    /// CookPlanner/CookPlanner.storekit for runs from Xcode).
    static let productID = "de.hpm64625.CookPlanner.pro"

    private static let purchasedCacheKey = "pro.purchased"
    private static let log = Logger(subsystem: "de.hpm64625.CookPlanner", category: "pro")

    /// The product with its localized price; nil until loaded, or when the
    /// App Store could not be reached.
    private(set) var product: Product?

    /// Whether a verified, unrevoked purchase exists. Starts from the
    /// cached answer of the last run, so the app does not flicker through
    /// a locked state while StoreKit is still answering.
    private(set) var hasPurchased: Bool

    /// The purchase as the App Store signed it (JWS), for the Functions.
    private(set) var purchaseJWS: String?

    private(set) var isPurchasing = false

    /// Whether loading the product failed, so the paywall can say so.
    private(set) var productUnavailable = false

    private var updatesTask: Task<Void, Never>?

    init() {
        #if DEBUG
        // -CookProPurchased 1|0: pretend the purchase exists or not.
        if let override = UserDefaults.standard.object(forKey: "CookProPurchased") as? String {
            hasPurchased = override == "1"
            debugOverride = true
            return
        }
        #endif
        hasPurchased = UserDefaults.standard.bool(forKey: Self.purchasedCacheKey)
    }

    #if DEBUG
    private var debugOverride = false
    #endif

    /// Starts following the App Store; harmless to call again.
    func start() {
        #if DEBUG
        if debugOverride { return }
        #endif
        guard updatesTask == nil else { return }
        updatesTask = Task { [weak self] in
            for await result in Transaction.updates {
                guard let self else { return }
                if case .verified(let transaction) = result {
                    await transaction.finish()
                }
                await self.refreshPurchases()
            }
        }
        Task {
            await loadProduct()
            await refreshPurchases()
        }
    }

    func loadProduct() async {
        do {
            product = try await Product.products(for: [Self.productID]).first
            productUnavailable = product == nil
        } catch {
            productUnavailable = true
            Self.log.error("Pro product could not be loaded: \(error.localizedDescription)")
        }
    }

    /// Re-reads the current entitlements. A refunded purchase disappears
    /// from them, and Pro ends with it.
    func refreshPurchases() async {
        var purchased = false
        var jws: String?
        for await result in Transaction.currentEntitlements {
            if case .verified(let transaction) = result,
               transaction.productID == Self.productID,
               transaction.revocationDate == nil {
                purchased = true
                jws = result.jwsRepresentation
            }
        }
        purchaseJWS = jws
        setPurchased(purchased)
    }

    /// Buys Pro. True when the purchase went through, false when cancelled
    /// or pending (Ask to Buy); throws when the App Store refused it.
    func purchase() async throws -> Bool {
        guard let product else { throw CookProError.productUnavailable }
        isPurchasing = true
        defer { isPurchasing = false }

        switch try await product.purchase() {
        case .success(let verification):
            guard case .verified(let transaction) = verification else {
                throw CookProError.unverified
            }
            await transaction.finish()
            purchaseJWS = verification.jwsRepresentation
            setPurchased(true)
            return true
        case .pending, .userCancelled:
            return false
        @unknown default:
            return false
        }
    }

    /// "Käufe wiederherstellen", which every store has to offer.
    func restore() async throws {
        try await AppStore.sync()
        await refreshPurchases()
    }

    private func setPurchased(_ purchased: Bool) {
        guard purchased != hasPurchased else { return }
        hasPurchased = purchased
        UserDefaults.standard.set(purchased, forKey: Self.purchasedCacheKey)
        Self.log.info("Pro purchased: \(purchased)")
    }
}

enum CookProError: LocalizedError {
    case productUnavailable
    case unverified

    var errorDescription: String? {
        switch self {
        case .productUnavailable:
            return String(localized: "Der Kauf ist im Moment nicht möglich. Bitte versuche es später noch einmal.")
        case .unverified:
            return String(localized: "Der Kauf konnte nicht bestätigt werden.")
        }
    }
}

// MARK: - Remote switches

@Observable
@MainActor
final class CookProConfigStore {

    static let shared = CookProConfigStore()

    private static let cacheKey = "pro.config"
    private static let log = Logger(subsystem: "de.hpm64625.CookPlanner", category: "pro")

    /// The switches in force: the last ones read, cached across launches,
    /// free until a first answer arrives.
    private(set) var config: MonetizationConfig

    private var started = false
    /// Set by the debug launch arguments: Firestore must not overwrite them.
    private var fixed = false

    init() {
        #if DEBUG
        // -CookProRequired 1 [-CookProStoreVisible 1]: the switches without
        // Firestore, for trying the locks and the paywall.
        if UserDefaults.standard.string(forKey: "CookProRequired") != nil
            || UserDefaults.standard.string(forKey: "CookProStoreVisible") != nil {
            config = MonetizationConfig(proRequired: UserDefaults.standard.string(forKey: "CookProRequired") == "1",
                                        storeVisible: UserDefaults.standard.string(forKey: "CookProStoreVisible") == "1")
            fixed = true
            return
        }
        #endif
        if let data = UserDefaults.standard.data(forKey: Self.cacheKey),
           let cached = try? JSONDecoder().decode(MonetizationConfig.self, from: data) {
            config = cached
        } else {
            config = .free
        }
    }

    /// Reads the document once at launch and again whenever the app comes
    /// back after a while; harmless to call repeatedly.
    func start() {
        guard !started else { return }
        started = true
        Task { await refresh() }
    }

    func refresh() async {
        guard !fixed else { return }
        do {
            let fresh = try await Self.fetch()
            guard fresh != config else { return }
            config = fresh
            if let data = try? JSONEncoder().encode(fresh) {
                UserDefaults.standard.set(data, forKey: Self.cacheKey)
            }
            Self.log.info("Pro config: required \(fresh.proRequired), visible \(fresh.storeVisible)")
        } catch {
            // Keep what was cached; offline is no reason to lock or unlock.
            Self.log.error("Pro config could not be read: \(error.localizedDescription)")
        }
    }

    /// GET of the document through Firestore's REST interface, signed in
    /// anonymously (the rules let any signed-in app read `config/`) and
    /// with the App Check token. A missing document means the free default.
    private static func fetch() async throws -> MonetizationConfig {
        if Auth.auth().currentUser == nil {
            try await Auth.auth().signInAnonymously()
        }
        guard let user = Auth.auth().currentUser else { return .free }
        let idToken = try await user.getIDToken()
        let projectID = FirebaseApp.app()?.options.projectID ?? "back-planer"
        let url = URL(string: "https://firestore.googleapis.com/v1/projects/\(projectID)/databases/(default)/documents/\(KitchenProAccess.configDocument)")!
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 20)
        request.setValue("Bearer \(idToken)", forHTTPHeaderField: "Authorization")
        if let appCheck = try? await AppCheck.appCheck().token(forcingRefresh: false) {
            request.setValue(appCheck.token, forHTTPHeaderField: "X-Firebase-AppCheck")
        }
        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        if status == 404 { return .free }
        guard status == 200 else { throw URLError(.badServerResponse) }
        let object = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let fields = object?["fields"] as? [String: Any] ?? [:]
        return MonetizationConfig(firestoreRESTFields: fields)
    }
}
