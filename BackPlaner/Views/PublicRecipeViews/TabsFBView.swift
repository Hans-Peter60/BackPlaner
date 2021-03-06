//
//  TabsFBView.swift
//  BackPlaner
//
//  Created by Hans-Peter Müller on 08.12.21.
//

import SwiftUI
import CoreData

struct TabsFBView: View {
    
    @State private var tabSelection = 1
    
    @Environment(\.managedObjectContext) private var viewContext
    @EnvironmentObject var modelFB: RecipeFBModel
    
    var body: some View {
        TabView (selection: $tabSelection) {
            
            InstructionsFBListView()
                .tabItem {
                    VStack {
                        Image(systemName: "dial.max.fill")
                        Text("Rezept backen")
                    }
                }
                .tag(GlobalVariables.bakeListTab)
            
             RecipeFBListView()
                .tabItem {
                    VStack {
                        Image(systemName: "list.bullet.rectangle")
                        Text("Rezeptliste")
                    }
                }
                .tag(GlobalVariables.listTab)
        }
    }
}
