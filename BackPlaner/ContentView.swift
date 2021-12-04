//
//  ContentView.swift
//  BackPlaner2
//
//  Created by Hans-Peter Müller on 24.11.21.
//

import SwiftUI
import CoreData

struct ContentView: View {
    
    @State private var tabSelection = 0
    
    @Environment(\.managedObjectContext) private var viewContext
    @EnvironmentObject var modelFB: RecipeFBModel
    
    var manager:LocalNotificationManager = LocalNotificationManager()
    
    init() {
        manager.requestAuthorization()
    }
    
    var body: some View {
        

        NavigationView {
            VStack {

                NavigationLink(
                    destination: TabsView()
                ) {
                    ZStack {
                        Rectangle()
                            .foregroundColor(.white)
                            .cornerRadius(10)
                            .shadow(radius: 5)
                            .aspectRatio(CGSize(width: 335, height: 175), contentMode: .fit)
                        
                        Text("Liste der Rezepte")
                            .bold()
                            .foregroundColor(.black)
                    }
                }
                .padding()
                
                NavigationLink(
                    destination: AddRecipeView(tabSelection: $tabSelection)
                ) {
                    ZStack {
                        Rectangle()
                            .foregroundColor(.white)
                            .cornerRadius(10)
                            .shadow(radius: 5)
                            .aspectRatio(CGSize(width: 335, height: 175), contentMode: .fit)

                        Text("Neues Rezept anlegen")
                            .bold()
                            .foregroundColor(.black)
                    }
                }
                .padding()
                
                NavigationLink(
                    destination: ScheduledTasksView(tabSelection: $tabSelection)
                ) {
                    ZStack {
                        Rectangle()
                            .foregroundColor(.white)
                            .cornerRadius(10)
                            .shadow(radius: 5)
                            .aspectRatio(CGSize(width: 335, height: 175), contentMode: .fit)

                        Text("Nächste Schritte")
                            .bold()
                            .foregroundColor(.black)
                    }
                }
                .padding()

            }.navigationTitle("Back Planer")
                .navigationBarTitleDisplayMode(.large)
        }
        .environmentObject(RecipeModel())
        .environmentObject(RecipeFBModel())
        .environmentObject(LocalNotificationManager())
    }
        
    struct ContentView_Previews: PreviewProvider {
        static var previews: some View {
            ContentView().environment(\.managedObjectContext, PersistenceController.preview.container.viewContext)
        }
    }
}
