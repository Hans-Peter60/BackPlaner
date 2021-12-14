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
    
    let persistenceController = PersistenceController.shared
    
    init() {
        FirebaseApp.configure()
        
        let recipeDb = Firestore.firestore()
    }
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(\.managedObjectContext, persistenceController.container.viewContext)
        }
    }
}
