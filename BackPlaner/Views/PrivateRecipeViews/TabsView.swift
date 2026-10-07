//
//  TabsView.swift
//  PetersBackPlaner
//
//  Created by Hans-Peter Müller on 05.11.21.
//

import SwiftUI
import CoreData

struct TabsView: View {

    /// Tags of the tabs.
    static let bakingTab = 0
    static let detailsTab = 1

    var recipe:Recipe

    /// A recipe opens on its details. The baking tab works out the plan
    /// (start times, plan check, suggestions against the night), so it is
    /// built only once it is chosen, and then kept.
    @State private var tabSelection: Int
    @State private var bakingTabOpened: Bool

    @Environment(\.managedObjectContext) private var viewContext
    @EnvironmentObject var modelFB: RecipeFBModel

    /// `startsInBakingView` for the way in from "Neu planen", where planning
    /// is the point.
    init(recipe: Recipe, startsInBakingView: Bool = false) {
        self.recipe = recipe
        _tabSelection = State(initialValue: startsInBakingView ? Self.bakingTab : Self.detailsTab)
        _bakingTabOpened = State(initialValue: startsInBakingView)
    }

    var body: some View {
        TabView (selection: $tabSelection) {

            Group {
                if bakingTabOpened {
                    InstructionsView(recipe: recipe)
                } else {
                    Color.clear
                }
            }
                .tabItem {
                    VStack {
                        Image(systemName: "dial.max.fill")
                        Text("Backen")
                    }
                }
                .tag(Self.bakingTab)
            
             RecipeDetailView(recipe: recipe)
                .tabItem {
                    VStack {
                        Image(systemName: "list.bullet.rectangle")
                        Text("Details")
                    }
                }
                .tag(Self.detailsTab)
            
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
        .onChange(of: tabSelection) { _, selection in
            if selection == Self.bakingTab { bakingTabOpened = true }
        }
    }
}
