//
//  TabsView.swift
//  BackPlaner
//
//  Created by Hans-Peter Müller on 05.11.21.
//

import SwiftUI
import CoreData

struct TabsView: View {
    
    @State private var tabSelection = 0
    
    @Environment(\.managedObjectContext) private var viewContext
    @EnvironmentObject var modelFB: RecipeFBModel
    
    var body: some View {
        TabView (selection: $tabSelection) {
            
             RecipeListView()
                .tabItem {
                    VStack {
                        Image(systemName: "list.bullet.rectangle")
                        Text("Eigene Rezeptliste")
                    }
                }
                .tag(GlobalVariables.listTab)
            
            InstructionsListView()
                .tabItem {
                    VStack {
                        Image(systemName: "dial.max.fill")
                        Text("Eigenes Rezept backen")
                    }
                }
                .tag(GlobalVariables.bakeListTab)
        }
    }
}
