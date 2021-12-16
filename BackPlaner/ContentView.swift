//
//  ContentView.swift
//  BackPlaner
//
//  Created by Hans-Peter Müller on 24.11.21.
//

import SwiftUI
import CoreData

struct ContentView: View {
    
    @State private var tabSelection = 0
    
    @Environment(\.managedObjectContext) private var viewContext
    
    var manager:LocalNotificationManager = LocalNotificationManager()
    
    init() {
        manager.requestAuthorization()
    }
    
    var body: some View {
        

        NavigationView {
            VStack {

                NavigationLink(
                    destination: TabsFBView()
                ) {
                    ZStack {
                        Rectangle()
                            .foregroundColor(.white)
                            .cornerRadius(10)
                            .shadow(radius: 5)
                            .aspectRatio(CGSize(width: 335, height: 50), contentMode: .fit)
                        
                        Text("Public Rezepte")
                            .bold()
                            .foregroundColor(.black)
                    }
                }
                .padding()
                
                NavigationLink(
                    destination: TabsView()
                ) {
                    ZStack {
                        Rectangle()
                            .foregroundColor(.white)
                            .cornerRadius(10)
                            .shadow(radius: 5)
                            .aspectRatio(CGSize(width: 335, height: 50), contentMode: .fit)

                        Text("Private Rezepte")
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
                            .aspectRatio(CGSize(width: 335, height: 50), contentMode: .fit)

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
                            .aspectRatio(CGSize(width: 335, height: 50), contentMode: .fit)

                        Text("Geplante Schritte")
                            .bold()
                            .foregroundColor(.black)
                    }
                }
                .padding()


                NavigationLink(
                    destination: BakeHistoriesListView() // BakeHistoriesListView()
                ) {
                    ZStack {
                        Rectangle()
                            .foregroundColor(.white)
                            .cornerRadius(10)
                            .shadow(radius: 5)
                            .aspectRatio(CGSize(width: 335, height: 50), contentMode: .fit)

                        Text("Backhistorie")
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
    }
}
