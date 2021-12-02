//
//  BackPlanerApp.swift
//  BackPlaner
//
//  Created by Hans-Peter Müller on 02.12.21.
//

import SwiftUI
import Firebase

@main
struct BackPlanerApp: App {
    
    init() {
        FirebaseApp.configure()
        
        let recipeDb = Firestore.firestore()
    }
    
    let persistenceController = PersistenceController.shared

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(\.managedObjectContext, persistenceController.container.viewContext)
        }
    }
}
