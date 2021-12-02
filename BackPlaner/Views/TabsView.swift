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
    
    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \Item.timestamp, ascending: true)],
        animation: .default)
    
    private var items: FetchedResults<Item>
    
    var body: some View {
        TabView (selection: $tabSelection) {
            
             RecipeFBListView()
                .tabItem {
                    VStack {
                        Image(systemName: "list.bullet.rectangle")
                        Text("Liste FB")
                    }
                }
                .tag(GlobalVariables.listTab)
            
//            RecipeFBFeaturedView()
//                .tabItem {
//                    VStack {
//                        Image(systemName: "star.fill")
//                        Text("Featured")
//                    }
//                }
//                .tag(GlobalVariables.featuredTab)
//
            InstructionsFBListView()
                .tabItem {
                    VStack {
                        Image(systemName: "dial.max.fill")
                        Text("Backen")
                    }
                }
                .tag(GlobalVariables.bakeListTab)
        }
        .environmentObject(RecipeFBModel())
        .environmentObject(RecipeModel())
    }

    struct TabsView_Previews: PreviewProvider {
        static var previews: some View {
            TabsView().environment(\.managedObjectContext, PersistenceController.preview.container.viewContext)
        }
    }
}
