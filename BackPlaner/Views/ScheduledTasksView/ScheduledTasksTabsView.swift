//
//  ScheduledTasksTabsView.swift
//  BackPlaner
//
//  Hosts the two "next steps" screens — the timeline and the plain list —
//  behind one segmented control, as the Android app has it. The timeline,
//  the project plan, opens first. Until 2.2 the two were tabs of their own;
//  with the app's root now a tab bar, a second bar of tabs would stack on
//  the first.
//

import BakePlannerCore
import SwiftUI

/// A step to open the shift sheet for, handed in from the widget's
/// "Verschieben" link. Equatable by its token, so the same step tapped
/// twice opens the sheet twice.
struct ScheduledStepShiftRequest: Equatable {
    let stepID: String
    let token = UUID()
}

struct ScheduledTasksTabsView: View {

    @State private var showsTimeline = true
    /// From the widget: the list opens with the step's shift sheet.
    var shiftRequest: ScheduledStepShiftRequest?

    var body: some View {
        VStack(spacing: 0) {
            Picker("Darstellung", selection: $showsTimeline) {
                Text("Timeline").tag(true)
                Text("Liste").tag(false)
            }
            .pickerStyle(.segmented)
            .accessibilityIdentifier("scheduled.display")
            .padding(.horizontal, 12)
            .padding(.vertical, 6)

            if showsTimeline {
                ScheduledTasksTimeLineView()
            } else {
                ScheduledTasksView(shiftRequest: shiftRequest)
            }
        }
        .warmBackground()
        .onChange(of: shiftRequest, initial: true) { _, request in
            if request != nil { showsTimeline = false }
        }
    }
}
