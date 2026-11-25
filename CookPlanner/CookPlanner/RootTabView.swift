//
//  RootTabView.swift
//  CookPlanner
//
//  The app's two places, as a tab bar the way iOS apps keep their main
//  areas: the dishes with their plans, and everything cooked. Settings
//  stay a button in the dish list's bar; a dish's shopping list stays with
//  the dish.
//

import SwiftUI

enum CookTab: Hashable {
    case dishes
    case cooked
}

struct RootTabView: View {

    @State private var tab: CookTab = .dishes
    @State private var runLog = CookRunLog.shared

    var body: some View {
        TabView(selection: $tab) {
            Tab("Gerichte", systemImage: "fork.knife", value: .dishes) {
                DishListView(selectedTab: $tab)
            }
            Tab("Gekocht", systemImage: "clock.arrow.circlepath", value: .cooked) {
                CookHistoryView()
            }
        }
        // The record file speaks up here, whichever tab is open.
        .alert("Kochhistorie", isPresented: Binding(get: { runLog.lastError != nil },
                                                    set: { if !$0 { runLog.lastError = nil } })) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(runLog.lastError ?? "")
        }
    }
}
