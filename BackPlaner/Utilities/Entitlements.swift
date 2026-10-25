//
//  Entitlements.swift
//  BackPlaner
//
//  The one place that answers "may this feature be used?". Every Pro call
//  site asks here and nowhere else, so turning the purchase on is one
//  switch in the Firestore document, not a hunt through the views.
//
//  A feature is open when the configuration does not require Pro, or when
//  this installation has Pro — bought, or grandfathered as an installation
//  from before the purchase existed. Fail open: without a loaded
//  configuration everything is free.
//

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

    /// The decision, with the pieces it was made from.
    struct Resolution: Equatable, Sendable {
        /// Whether the Pro features are locked for installations without Pro.
        var proRequired: Bool
        /// Whether the Pro section and the paywall are shown.
        var storeVisible: Bool
        /// Whether this installation has Pro, bought or grandfathered.
        var isPro: Bool
        var isGrandfathered: Bool

        /// Whether a Pro feature may be used.
        var unlocked: Bool { !proRequired || isPro }
    }

    /// Pure, so the tests can cover every combination.
    nonisolated static func resolve(config: MonetizationConfig, purchased: Bool, originalAppVersion: String?) -> Resolution {
        let grandfathered = config.grandfathers(originalAppVersion: originalAppVersion)
        return Resolution(proRequired: config.proRequired,
                          // A buyer sees the section regardless, so the
                          // purchase is never invisible to the person who made it.
                          storeVisible: config.storeVisible || purchased,
                          isPro: purchased || grandfathered,
                          isGrandfathered: grandfathered)
    }

    var resolution: Resolution {
        Self.resolve(config: configStore.config,
                     purchased: store.hasPurchased,
                     originalAppVersion: store.originalAppVersion)
    }

    /// Whether `feature` may be used right now.
    func isUnlocked(_ feature: ProFeature) -> Bool {
        resolution.unlocked
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
            resolution.unlocked
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
