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

import BakePlannerCore
import FirebaseAppCheck
import FirebaseCore
import SwiftUI
import UIKit
import UserNotifications

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

/// Registers for CloudKit's silent pushes, so changes from the other
/// devices arrive without waiting for the next launch.
final class CookPlannerAppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        application.registerForRemoteNotifications()
        return true
    }
}

@main
struct CookPlannerApp: App {
    @UIApplicationDelegateAdaptor(CookPlannerAppDelegate.self) private var appDelegate
    @Environment(\.scenePhase) private var scenePhase
    @State private var library: DishLibrary

    init() {
        // App Check before Firebase, so the first request carries a token.
        AppCheck.setAppCheckProviderFactory(CookPlannerAppCheckProviderFactory())
        FirebaseApp.configure()
        UNUserNotificationCenter.current().delegate = CookReminders.shared
        let library = DishLibrary.onDisk()
        _library = State(initialValue: library)
        CloudSync.shared.start(library: library, runLog: CookRunLog.shared)
    }

    var body: some Scene {
        WindowGroup {
            #if DEBUG
            // Development builds draw one example's timeline on its own with
            // the launch argument -TimelineSample <index>, for screenshots.
            if let index = Int(UserDefaults.standard.string(forKey: "TimelineSample") ?? ""),
               KitchenSampleDishes.all.indices.contains(index),
               let plan = DishPlan(dish: KitchenSampleDishes.all[index], budget: CookSettings.defaultBudget,
                                   burners: CookSettings.defaultBurners, ovens: CookSettings.defaultOvens) {
                ScrollView {
                    PlanTimelineView(layout: KitchenTimelineLayout(schedule: plan.schedule,
                                                                   components: plan.dish.components),
                                     now: UserDefaults.standard.string(forKey: "TimelineNow").flatMap(Double.init),
                                     initiallySelected: UserDefaults.standard.string(forKey: "TimelineSelect"))
                        .padding()
                }
                .warmBackground()
            } else {
                DishListView()
                    .environment(library)
            }
            #else
            DishListView()
                .environment(library)
            #endif
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { Task { await CloudSync.shared.fetchNow() } }
        }
    }
}
