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
            
             RecipeFBListView()
                .tabItem {
                    VStack {
                        Image(systemName: "list.bullet.rectangle")
                        Text("Rezeptliste")
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
                        Text("Rezept backen")
                    }
                }
                .tag(GlobalVariables.bakeListTab)
        }
    }

//    struct TabsFBView_Previews: PreviewProvider {
//        static var previews: some View {
//            TabsView().environment(\.managedObjectContext, PersistenceController.preview.container.viewContext)
//        }
//    }
}
