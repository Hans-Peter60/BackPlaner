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

    var body: some View {
        TabView(selection: $tab) {
            Tab("Gerichte", systemImage: "fork.knife", value: .dishes) {
                DishListView(selectedTab: $tab)
            }
            Tab("Gekocht", systemImage: "clock.arrow.circlepath", value: .cooked) {
                CookHistoryView()
            }
        }
    }
}
