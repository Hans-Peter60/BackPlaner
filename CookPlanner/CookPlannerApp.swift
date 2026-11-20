//
//  CookPlannerApp.swift
//  CookPlanner
//
//  Cooking against the clock: a dish of several parts, one cook, a few
//  burners, an oven and a time budget. The planning is BakePlannerCore's
//  KitchenScheduler; this app shows its plans and runs them as a cook mode.
//  The cook's own dishes are kept by CookPlannerStorage; the cloud import
//  goes through Firebase (Functions, App Check, anonymous Auth) in the
//  same project as BakePlanner. Working title; see docs/Idee-Gegen-die-Uhr.md.
//

import FirebaseAppCheck
import FirebaseCore
import SwiftUI

/// App Attest on devices; in DEBUG builds (Simulator, development) the
/// debug provider, whose token printed at first launch is registered once
/// in the Firebase console (App Check → Apps → CookPlanner → Debug tokens).
final class CookPlannerAppCheckProviderFactory: NSObject, AppCheckProviderFactory {
    func createProvider(with app: FirebaseApp) -> AppCheckProvider? {
        #if DEBUG
        return AppCheckDebugProvider(app: app)
        #else
        return AppAttestProvider(app: app)
        #endif
    }
}

@main
struct CookPlannerApp: App {
    @State private var library: DishLibrary

    init() {
        // App Check before Firebase, so the first request carries a token.
        AppCheck.setAppCheckProviderFactory(CookPlannerAppCheckProviderFactory())
        FirebaseApp.configure()
        _library = State(initialValue: DishLibrary.onDisk())
    }

    var body: some Scene {
        WindowGroup {
            DishListView()
                .environment(library)
        }
    }
}
