//
//  CookPlannerWidgetsBundle.swift
//  CookPlannerWidgets
//
//  The extension holds the Live Activity of the dish being cooked.
//

import SwiftUI
import WidgetKit

@main
struct CookPlannerWidgetsBundle: WidgetBundle {
    var body: some Widget {
        CookActivityWidget()
    }
}
