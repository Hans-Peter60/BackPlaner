//
//  TabsView.swift
//  PetersBackPlaner
//
//  Created by Hans-Peter Müller on 05.11.21.
//

import SwiftUI
import CoreData

struct TabsView: View {
    
    var recipe:Recipe
    
    @State private var tabSelection = 0
    
    @Environment(\.managedObjectContext) private var viewContext
    @EnvironmentObject var modelFB: RecipeFBModel
    
    var body: some View {
        TabView (selection: $tabSelection) {
            
            InstructionsView(recipe: recipe)
                .tabItem {
                    VStack {
                        Image(systemName: "dial.max.fill")
                        Text("Backen")
                    }
                }
                .tag(0)
            
             RecipeDetailView(recipe: recipe)
                .tabItem {
                    VStack {
                        Image(systemName: "list.bullet.rectangle")
                        Text("Details")
                    }
                }
                .tag(1)
            
            EditRecipeView(recipeId: recipe.objectID)
               .tabItem {
                   VStack {
                       Image(systemName: "pencil.circle")
                       Text("Ändern")
                   }
               }
               .tag(2)

            ShoppingCartSelectFormView(recipe: recipe)
               .tabItem {
                   VStack {
                       Image(systemName: "cart.badge.plus")
                       Text("Einkaufsliste")
                   }
               }
               .tag(3)
            
            BakeHistoryAddView(recipeId: recipe.objectID)
               .tabItem {
                   VStack {
                       Image(systemName: "rectangle.and.pencil.and.ellipsis")
                       Text("+ Historie")
                   }
               }
               .tag(4)
        }
        // accentText, not accentBottom: the tab bar keeps the system's own
        // background, so the tint has to be light in dark mode, not dark.
        .tint(Theme.accentText)
    }
}
