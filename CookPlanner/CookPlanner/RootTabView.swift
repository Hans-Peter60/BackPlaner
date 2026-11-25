//
//  RootTabView.swift
//  CookPlanner
//
//  The app's two places, as a tab bar the way iOS apps keep their main
//  areas: the dishes with their plans, and everything cooked. Settings
//  stay a button in the dish list's bar; a dish's shopping list stays with
//  the dish.
//

import BakePlannerCore
import SwiftUI

enum CookTab: Hashable {
    case dishes
    case cooked
}

struct RootTabView: View {

    @Environment(DishLibrary.self) private var library
    @AppStorage(CookSettings.budgetKey) private var budget = CookSettings.defaultBudget
    @AppStorage(CookSettings.burnersKey) private var burners = CookSettings.defaultBurners
    @AppStorage(CookSettings.ovensKey) private var ovens = CookSettings.defaultOvens
    @State private var tab: CookTab = .dishes
    @State private var runLog = CookRunLog.shared
    @State private var sync = CloudSync.shared
    /// A run the last launch left under way, taken up again.
    @State private var resumed: ResumedRun?
    @State private var checkedForRun = false

    /// The plan and the state of a run to continue.
    private struct ResumedRun: Identifiable {
        let plan: DishPlan
        let state: CookRunState
        var id: String { state.dishID }
    }

    var body: some View {
        TabView(selection: $tab) {
            Tab("Gerichte", systemImage: "fork.knife", value: .dishes) {
                DishListView(selectedTab: $tab)
            }
            Tab("Gekocht", systemImage: "clock.arrow.circlepath", value: .cooked) {
                CookHistoryView()
            }
        }
        .onAppear(perform: resumeRunIfAny)
        .fullScreenCover(item: $resumed) { run in
            CookModeView(plan: run.plan, restoring: run.state)
        }
        // Another Apple ID on the device: what is here may be someone else's.
        .alert("Anderes iCloud-Konto", isPresented: Binding(get: { sync.accountSwitchPending },
                                                           set: { if !$0 { sync.resolveAccountSwitch(uploadLocalData: false) } })) {
            Button("In das Konto übertragen") { sync.resolveAccountSwitch(uploadLocalData: true) }
            Button("Nur hier behalten", role: .cancel) { sync.resolveAccountSwitch(uploadLocalData: false) }
        } message: {
            Text("Auf diesem Gerät ist jetzt ein anderes iCloud-Konto angemeldet. Sollen die Gerichte und Protokolle, die hier gespeichert sind, in dieses Konto übertragen werden? Was dort schon liegt, kommt in jedem Fall herunter.")
        }
        // The record file speaks up here, whichever tab is open.
        .alert("Kochhistorie", isPresented: Binding(get: { runLog.lastError != nil },
                                                    set: { if !$0 { runLog.lastError = nil } })) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(runLog.lastError ?? "")
        }
    }

    /// Opens the cook mode again if the app ended with a run under way;
    /// otherwise clears what such a run may have left behind.
    private func resumeRunIfAny() {
        guard !checkedForRun else { return }
        checkedForRun = true
        defer { CookRunState.cleanUpLeftovers() }
        guard let state = CookRunState.load() else { return }
        guard state.isResumable,
              let dish = library.dish(id: state.dishID) ?? KitchenSampleDishes.all.first(where: { $0.id == state.dishID }),
              let plan = DishPlan(dish: dish.scaled(by: CookSettings.portionFactor(for: dish.id)),
                                  budget: budget, burners: burners, ovens: ovens) else {
            CookRunState.clear()
            return
        }
        resumed = ResumedRun(plan: plan, state: state)
    }
}
