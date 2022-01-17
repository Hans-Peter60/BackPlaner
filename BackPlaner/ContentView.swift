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
    
    var recipeId: NSManagedObjectID?
    
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
                        
                        Text("Rezept-Datenbank")
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

                        Text("Eigene Rezepte")
                            .bold()
                            .foregroundColor(.black)
                    }
                }
                .padding()
                NavigationLink(
                    destination: AddRecipeView() // EditRecipeView(recipeId: recipeId)
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
                    destination: ScheduledTasksView()
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
                    destination: BakeHistoriesListView()
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

                NavigationLink(
                    destination: ShoppingCartsView()
                ) {
                    ZStack {
                        Rectangle()
                            .foregroundColor(.white)
                            .cornerRadius(10)
                            .shadow(radius: 5)
                            .aspectRatio(CGSize(width: 335, height: 50), contentMode: .fit)

                        Text("Einkaufsliste")
                            .bold()
                            .foregroundColor(.black)
                    }
                }
                .padding()

          }.navigationTitle("Back Planer")
                .navigationBarTitleDisplayMode(.large)
        }
//        .navigationViewStyle(StackNavigationViewStyle())
        .environmentObject(RecipeModel())
        .environmentObject(RecipeFBModel())
    }
}
