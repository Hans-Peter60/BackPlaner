//
//  Entitlements.swift
//  BackPlaner
//
//  The one place that answers "may this feature be used?". Every Pro call
//  site asks here and nowhere else, so turning the purchase on is one
//  switch in the Firestore document, not a hunt through the views.
//
//  A feature is open when the configuration does not require Pro, when
//  this installation bought Pro, or when it is grandfathered — downloaded
//  before the purchase existed — and the feature was already in the app on
//  that day (ProFeature.introducedBuild). What was free when someone came
//  stays free for them; what came later costs them what it costs everyone.
//  Fail open: without a loaded configuration everything is free.
//

import BakePlannerCore
import Foundation
import Observation
import WidgetKit
import os

@Observable
@MainActor
final class Entitlements {

    static let shared = Entitlements(configStore: .shared, store: .shared)

    private let configStore: MonetizationConfigStore
    private let store: ProStore

    init(configStore: MonetizationConfigStore, store: ProStore) {
        self.configStore = configStore
        self.store = store
    }

    /// The decision, with the pieces it was made from — the package's,
    /// shared with Android (BakePlannerCore/ProAccess.swift).
    typealias Resolution = ProResolution

    nonisolated static func resolve(config: MonetizationConfig, purchased: Bool, originalAppVersion: String?) -> Resolution {
        ProAccess.resolve(config: config, purchased: purchased, originalAppVersion: originalAppVersion)
    }

    var resolution: Resolution {
        Self.resolve(config: configStore.config,
                     purchased: store.hasPurchased,
                     originalAppVersion: store.originalAppVersion)
    }

    /// Whether `feature` may be used right now.
    func isUnlocked(_ feature: ProFeature) -> Bool {
        resolution.unlocked(feature)
    }

    /// Whether there is nothing left to buy: Pro was bought, or every
    /// feature is open anyway. A grandfathered installation that lacks the
    /// newer features is offered the purchase.
    var hasEverything: Bool {
        resolution.unlocksEverything
    }

    /// What a cloud import sends so the Functions can verify Pro for
    /// themselves: the App Store's signed purchase, or for a grandfathered
    /// installation the signed AppTransaction. Empty without Pro, and
    /// under a UI-test override, which has nothing signed to show.
    var proClaim: [String: String] {
        let resolution = resolution
        guard resolution.isPro else { return [:] }
        if store.hasPurchased, let jws = store.purchaseJWS {
            return ["proTransaction": jws]
        }
        if resolution.isGrandfathered, let jws = store.appTransactionJWS {
            return ["proAppTransaction": jws]
        }
        return [:]
    }

    var isPro: Bool { resolution.isPro }
    var storeVisible: Bool { resolution.storeVisible }
    var proRequired: Bool { resolution.proRequired }

    /// Starts the configuration and the store, and keeps the widget's copy
    /// of the decision current. Called once at launch.
    func start() {
        configStore.start()
        store.start()
        mirrorForWidgets()
    }

    /// The widget extension cannot ask StoreKit or Firestore in time for a
    /// timeline, so the resolved decision is written into the App Group
    /// (read by `PlanSnapshot.widgetsUnlocked`) and the timelines reload
    /// whenever it changes.
    private func mirrorForWidgets() {
        let unlocked = withObservationTracking { [self] in
            resolution.unlocked(.widgets)
        } onChange: { [weak self] in
            Task { @MainActor in
                self?.mirrorForWidgets()
            }
        }
        let defaults = UserDefaults(suiteName: PlanSnapshot.appGroupIdentifier)
        let previous = defaults?.object(forKey: PlanSnapshot.widgetsUnlockedKey) as? Bool
        guard previous != unlocked else { return }
        defaults?.set(unlocked, forKey: PlanSnapshot.widgetsUnlockedKey)
        WidgetCenter.shared.reloadAllTimelines()
        AppLog.store.info("Widgets unlocked: \(unlocked)")
    }
}
