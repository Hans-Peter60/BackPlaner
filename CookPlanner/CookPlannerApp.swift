//
//  CookPlannerApp.swift
//  CookPlanner
//
//  Cooking against the clock: a dish of several parts, one cook, a few
//  burners, an oven and a time budget. The planning is BakePlannerCore's
//  KitchenScheduler; this app shows its plans and runs them as a cook mode.
//  Working title; see docs/Idee-Gegen-die-Uhr.md.
//

import SwiftUI

@main
struct CookPlannerApp: App {
    var body: some Scene {
        WindowGroup {
            DishListView()
        }
    }
}
