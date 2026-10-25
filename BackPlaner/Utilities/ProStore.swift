//
//  ProStore.swift
//  BackPlaner
//
//  The StoreKit side of BakePlanner Pro: one non-consumable product, bought
//  once. Loads the product, buys and restores it, follows the transactions
//  the App Store delivers on its own (a purchase on another device, a
//  refund), and reads the build the app was first downloaded as, which
//  decides whether an installation is grandfathered.
//
//  Whether any of this *matters* is not decided here but in `Entitlements`,
//  which combines the purchase with the remote configuration.
//

import Foundation
import Observation
import StoreKit
import os

@Observable
@MainActor
final class ProStore {

    static let shared = ProStore()

    /// The product as configured in App Store Connect (and in
    /// BackPlaner.storekit for the simulator).
    static let productID = "de.hpm64625.BackPlaner.pro"

    private static let purchasedCacheKey = "entitlements.proPurchased"

    /// The product with its localized price; nil until loaded, or when the
    /// App Store could not be reached.
    private(set) var product: Product?

    /// Whether a verified, unrevoked purchase of Pro exists. Starts from the
    /// cached answer of the last run so the app does not flicker through a
    /// locked state while StoreKit is still answering.
    private(set) var hasPurchased: Bool

    /// `AppTransaction.originalAppVersion`: on iOS the build number of the
    /// version this installation was first downloaded as. nil until read,
    /// and in a simulator without a StoreKit configuration.
    private(set) var originalAppVersion: String?

    private(set) var isPurchasing = false

    /// Whether loading the product failed, so the paywall can say so
    /// instead of showing an empty price.
    private(set) var productUnavailable = false

    private let defaults: UserDefaults?
    private var updatesTask: Task<Void, Never>?

    init(defaults: UserDefaults? = UserDefaults(suiteName: PlanSnapshot.appGroupIdentifier)) {
        self.defaults = defaults
        if let override = UITestSupport.monetizationOverride {
            hasPurchased = override.purchased
            originalAppVersion = override.originalAppVersion
        } else {
            hasPurchased = defaults?.bool(forKey: Self.purchasedCacheKey) ?? false
        }
    }

    /// Starts following the App Store. Called once at launch; harmless to
    /// call again. Does nothing under a UI-test override.
    func start() {
        guard updatesTask == nil, UITestSupport.monetizationOverride == nil else { return }
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
            await loadOriginalAppVersion()
        }
    }

    func loadProduct() async {
        do {
            product = try await Product.products(for: [Self.productID]).first
            productUnavailable = product == nil
        } catch {
            productUnavailable = true
            AppLog.store.error("Pro product could not be loaded: \(error.localizedDescription)")
        }
    }

    /// Re-reads the current entitlements. A refunded or revoked purchase
    /// disappears from them, so Pro ends with it.
    func refreshPurchases() async {
        var purchased = false
        for await result in Transaction.currentEntitlements {
            if case .verified(let transaction) = result,
               transaction.productID == Self.productID,
               transaction.revocationDate == nil {
                purchased = true
            }
        }
        setPurchased(purchased)
    }

    /// Buys Pro. Returns true when the purchase went through, false when
    /// the user cancelled or the purchase is pending (Ask to Buy); throws
    /// when the App Store refused it.
    func purchase() async throws -> Bool {
        guard let product else { throw ProStoreError.productUnavailable }
        isPurchasing = true
        defer { isPurchasing = false }

        let result = try await product.purchase()
        switch result {
        case .success(let verification):
            guard case .verified(let transaction) = verification else {
                throw ProStoreError.unverified
            }
            await transaction.finish()
            setPurchased(true)
            return true
        case .pending, .userCancelled:
            return false
        @unknown default:
            return false
        }
    }

    /// Asks the App Store for the purchases of this Apple Account — the
    /// "Käufe wiederherstellen" button every store has to offer.
    func restore() async throws {
        try await AppStore.sync()
        await refreshPurchases()
    }

    private func loadOriginalAppVersion() async {
        do {
            if case .verified(let appTransaction) = try await AppTransaction.shared {
                originalAppVersion = appTransaction.originalAppVersion
            }
        } catch {
            // No receipt: a simulator without a StoreKit configuration, or
            // a development build. Nobody is grandfathered then.
            AppLog.store.debug("App transaction unavailable: \(error.localizedDescription)")
        }
    }

    private func setPurchased(_ purchased: Bool) {
        guard purchased != hasPurchased else { return }
        hasPurchased = purchased
        defaults?.set(purchased, forKey: Self.purchasedCacheKey)
        AppLog.store.info("Pro purchased: \(purchased)")
    }
}

enum ProStoreError: LocalizedError {
    case productUnavailable
    case unverified

    var errorDescription: String? {
        switch self {
        case .productUnavailable:
            return String(localized: "Der Kauf ist im Moment nicht möglich. Bitte versuche es später noch einmal.",
                          bundle: AppSettings.localizationBundle, locale: AppSettings.locale)
        case .unverified:
            return String(localized: "Der Kauf konnte nicht bestätigt werden.",
                          bundle: AppSettings.localizationBundle, locale: AppSettings.locale)
        }
    }
}
