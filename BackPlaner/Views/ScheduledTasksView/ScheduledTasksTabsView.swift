//
//  ScheduledTasksTabsView.swift
//  BackPlaner
//
//  Hosts the two "next steps" screens — the plain list and the timeline — in a
//  single tabbed container, mirroring the public-recipe tabs (Backen/Details).
//  This lets the main menu offer one entry instead of two, while the user still
//  switches between "Liste" and "Timeline" at the bottom.
//

import SwiftUI

struct ScheduledTasksTabsView: View {

    @State private var tabSelection = 0

    var body: some View {
        TabView(selection: $tabSelection) {

            ScheduledTasksView()
                .tabItem {
                    VStack {
                        Image(systemName: "calendar")
                        Text("Geplante Schritte")
                    }
                }
                .tag(0)

            ScheduledTasksTimeLineView()
                .tabItem {
                    VStack {
                        Image(systemName: "chart.bar.doc.horizontal.fill")
                        Text("Timeline")
                    }
                }
                .tag(1)
        }
        .tint(Theme.accentText)
    }
}
