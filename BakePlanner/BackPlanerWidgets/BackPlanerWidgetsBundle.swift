//
//  BackPlanerWidgetsBundle.swift
//  BackPlanerWidgets
//
//  Created by Hans-Peter Müller on 02.10.26.
//

import WidgetKit
import SwiftUI

@main
struct BackPlanerWidgetsBundle: WidgetBundle {
    var body: some Widget {
        BackPlanerWidgets()
        BakeActivityWidget()
        // Control Center, Lock Screen and Action button.
        MarkStepDoneControl()
        OpenPlanControl()
    }
}
