//
//  BakePlannerWatchApp.swift
//  BakePlannerWatch
//
//  The bake mode on the wrist: the planned steps as the iPhone last sent
//  them, one at a time, with "Erledigt". The plan itself lives on the
//  iPhone; the watch holds a copy (PhonePlanSession) and sends back what
//  was done.
//

import SwiftUI

@main
struct BakePlannerWatchApp: App {
    @State private var session = PhonePlanSession()

    var body: some Scene {
        WindowGroup {
            WatchPlanView()
                .environment(session)
        }
    }
}
