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

struct ScheduledTasksTabsView: View {

    @State private var showsTimeline = true

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
                ScheduledTasksView()
            }
        }
        .warmBackground()
    }
}
