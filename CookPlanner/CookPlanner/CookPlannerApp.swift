//
//  CookPlannerApp.swift
//  CookPlanner
//
//  Cooking against the clock: a dish of several parts, one cook, a few
//  burners, an oven and a time budget. The planning is BakePlannerCore's
//  KitchenScheduler; this app shows its plans and runs them as a cook mode.
//  The cook's own dishes are kept by CookPlannerStorage; the cloud import
//  goes through Firebase (Functions, App Check, anonymous Auth) in the
//  same project as BakePlanner. Working title; see docs/cookplanner/Idee-Gegen-die-Uhr.md.
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
        // Budget, kitchen, clock mode and the saved collections follow the
        // cook to the other devices.
        SettingsSync.shared.start()
    }

    var body: some Scene {
        WindowGroup {
            #if DEBUG
            // Development builds draw one example's timeline on its own with
            // the launch argument -TimelineSample <index>, for screenshots.
            if let index = Int(UserDefaults.standard.string(forKey: "PlanPDFSample") ?? ""),
               KitchenSampleDishes.all.indices.contains(index),
               let plan = DishPlan(dish: KitchenSampleDishes.all[index], budget: CookSettings.defaultBudget,
                                   burners: CookSettings.defaultBurners, ovens: CookSettings.defaultOvens) {
                // -PlanPDFSample <index> [-PlanPDFStart <minutes after midnight>]: writes the
                // printed plan into Documents/plan.pdf, for checking the layout.
                Text(verbatim: "plan.pdf")
                    .onAppear {
                        let start = Int(UserDefaults.standard.string(forKey: "PlanPDFStart") ?? "").map {
                            Calendar.current.startOfDay(for: .now).addingTimeInterval(TimeInterval($0 * 60))
                        }
                        try? PlanPDFRenderer.render(plan, start: start)
                            .write(to: URL.documentsDirectory.appendingPathComponent("plan.pdf"))
                    }
            } else if let index = Int(UserDefaults.standard.string(forKey: "PlanSample") ?? ""),
               KitchenSampleDishes.all.indices.contains(index) {
                // -PlanSample <index>: an example's plan, for screenshots.
                NavigationStack { DishPlanView(dish: KitchenSampleDishes.all[index]) }
                    .environment(library)
            } else if let index = Int(UserDefaults.standard.string(forKey: "CookSample") ?? ""),
                      KitchenSampleDishes.all.indices.contains(index),
                      let plan = DishPlan(dish: KitchenSampleDishes.all[index],
                                          budget: UserDefaults.standard.object(forKey: CookSettings.budgetKey) as? Int
                                              ?? Int(UserDefaults.standard.string(forKey: CookSettings.budgetKey) ?? "")
                                              ?? CookSettings.defaultBudget,
                                          burners: CookSettings.defaultBurners, ovens: CookSettings.defaultOvens) {
                // -CookSample <index> -CookElapsed <seconds>: the cook mode under way, for screenshots.
                CookModeView(plan: plan,
                             startedSecondsAgo: TimeInterval(UserDefaults.standard.string(forKey: "CookElapsed") ?? "") ?? 600)
            } else if let index = Int(UserDefaults.standard.string(forKey: "ShoppingSample") ?? ""),
               KitchenSampleDishes.all.indices.contains(index) {
                // -ShoppingSample <index>: an example's shopping list, for screenshots.
                ShoppingListView(dish: KitchenSampleDishes.all[index])
            } else if let layout = UserDefaults.standard.string(forKey: "HistoryDemo").flatMap(CookHistoryLayout.init(rawValue:)) {
                // -HistoryDemo <layout>: the history with a few entries, for screenshots.
                CookHistoryView()
                    .environment(library)
                    .onAppear {
                        UserDefaults.standard.set(layout.rawValue, forKey: "history.layout")
                        guard CookRunLog.shared.runs.isEmpty else { return }
                        let samples = KitchenSampleDishes.all
                        for (index, stars) in [5, 4, 3, 5, 4, 2].enumerated() {
                            let dish = samples[index % samples.count]
                            CookRunLog.shared.add(.manualEntry(dishID: dish.id, dishName: dish.name,
                                                               date: .now.addingTimeInterval(-Double(index) * 20 * 86_400),
                                                               rating: stars, note: index == 0 ? "Gäste begeistert" : nil))
                        }
                    }
            } else if let index = Int(UserDefaults.standard.string(forKey: "TimelineSample") ?? ""),
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
                RootTabView()
                    .environment(library)
            }
            #else
            RootTabView()
                .environment(library)
            #endif
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { Task { await CloudSync.shared.fetchNow() } }
        }
    }
}
