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
import PDFKit
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
        DishLibrary.current = library
        DishSpotlightIndexer.shared.schedulePass()
        CloudSync.shared.start(library: library, runLog: CookRunLog.shared)
        // Budget, kitchen, clock mode and the saved collections follow the
        // cook to the other devices.
        SettingsSync.shared.start()
        // The Pro purchase and its switches; nothing is locked until the
        // switch in Firestore says so.
        CookPro.shared.start()
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
            } else if UserDefaults.standard.bool(forKey: "YearbookPDF") {
                // -YearbookPDF: the yearbook of the newest year from the records
                // on this device into Documents/yearbook.pdf, plus a PNG per page,
                // for checking the layout.
                Text(verbatim: "yearbook.pdf")
                    .onAppear {
                        let runs = CookRunLog.shared.runs
                        guard let year = KitchenYearbook.years(of: runs).first else { return }
                        let document = CookYearbookDocument.load(year: year, cookName: "Hans-Peter")
                        let data = CookYearbookRenderer.render(document)
                        let folder = URL.documentsDirectory
                        try? data.write(to: folder.appendingPathComponent("yearbook.pdf"))
                        if let pdf = PDFDocument(data: data) {
                            for index in 0..<pdf.pageCount {
                                guard let page = pdf.page(at: index) else { continue }
                                let image = page.thumbnail(of: CGSize(width: 1190, height: 1684), for: .mediaBox)
                                try? image.pngData()?.write(to: folder.appendingPathComponent("yearbook-\(index + 1).png"))
                            }
                        }
                    }
            } else if UserDefaults.standard.bool(forKey: "CookProPaywall") {
                // -CookProPaywall 1: the Pro sheet on its own, for checking it
                // and for the review screenshot of the purchase.
                CookProPaywallView(highlighted: .menu)
            } else if UserDefaults.standard.bool(forKey: "MenuSample") {
                // -MenuSample 1: the plan of a two-course menu from the
                // examples (stuffed cabbage, then guinea fowl), for screenshots.
                let samples = KitchenSampleDishes.all
                let menu = KitchenMenu.combined(
                    name: String(localized: "Menü"),
                    courses: [KitchenMenuCourse(dish: samples[1], label: String(localized: "Vorspeise"), gapAfterMinutes: 20),
                              KitchenMenuCourse(dish: samples[0], label: String(localized: "Hauptgang"))],
                    id: "menu-sample"
                ) { course in String(localized: "\(course) servieren") }
                NavigationStack { DishPlanView(dish: menu) }
                    .environment(library)
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
            if phase == .active {
                Task { await CloudSync.shared.fetchNow() }
                // A switch turned in the console reaches a running app.
                Task { await CookProConfigStore.shared.refresh() }
            }
        }
        .commands { CookPlannerCommands() }
    }
}
