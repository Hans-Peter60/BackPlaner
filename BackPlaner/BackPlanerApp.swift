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
    
    @StateObject private var dataController = DataController()
    
    init() {
        FirebaseApp.configure()
        
        let recipeDb = Firestore.firestore()
    }
    
//    let dataController = DataController.shared

    var body: some Scene {
        WindowGroup {
            ContentView()
//                .environment(\.managedObjectContext, persistenceController.container.viewContext)
                .environment(\.managedObjectContext, dataController.container.viewContext)
        }
    }
}
