//
//  BackPlanerApp.swift
//  BackPlaner
//
//  Created by Hans-Peter Müller on 08.02.24.
//

import SwiftUI

@main
struct BackPlanerApp: App {
    let persistenceController = PersistenceController.shared

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(\.managedObjectContext, persistenceController.container.viewContext)
        }
    }
}
