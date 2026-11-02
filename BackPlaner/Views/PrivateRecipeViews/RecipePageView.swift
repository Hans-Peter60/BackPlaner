//
//  RecipePageView.swift
//  BackPlaner
//
//  One of the user's own recipes as a single page — picture, amount,
//  ingredients, components, the last bake, the steps, the earlier bakes —
//  with planning, the shopping list, a bake entry and editing opened from
//  it as sheets. Until 2.2 the same content was spread over five tabs
//  (Backen, Details, Ändern, Einkaufsliste, + Historie); the Android app
//  showed it as one page from the start, and that read better.
//
//  The serving scale lives here and is handed to the page and to every
//  sheet, so the amount chosen on the page is the one a plan's reminders
//  and a shopping list carry.
//

import BakePlannerCore
import SwiftUI
import CoreData

struct RecipePageView: View {

    var recipe: Recipe

    /// The serving scale, shared by the page and its sheets.
    @State private var selectedServingSize = AppSettings.storedServingSize
    /// A target dough weight in grams; overrides the serving-size factor.
    @State private var targetWeight: Int?

    @State private var showsPlan: Bool
    @State private var showsEditor = false
    @State private var showsShoppingList = false
    @State private var showsBakeEntry = false
    @State private var showsFeedingDiary = false

    @Environment(\.managedObjectContext) private var viewContext
    @EnvironmentObject var modelFB: RecipeFBModel

    /// `startsInBakingView` for the way in from "Neu planen", where planning
    /// is the point: the plan sheet opens with the page.
    init(recipe: Recipe, startsInBakingView: Bool = false) {
        self.recipe = recipe
        _showsPlan = State(initialValue: startsInBakingView)
    }

    private var isStarter: Bool { StarterRecipe.isStarterFeeding(recipe) }

    var body: some View {
        RecipeDetailView(recipe: recipe,
                         selectedServingSize: $selectedServingSize,
                         targetWeight: $targetWeight,
                         onPlan: { showsPlan = true },
                         onShoppingList: { showsShoppingList = true },
                         onBakeEntry: { showsBakeEntry = true },
                         onFeedingDiary: { showsFeedingDiary = true })
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Bearbeiten") {
                    showsEditor = true
                }
                .accessibilityIdentifier("recipe.edit")
            }
        }
        // Planning: the date and mode, the plan's findings, the steps with
        // their start times, and "Erinnerungen setzen".
        .sheet(isPresented: $showsPlan) {
            NavigationStack {
                InstructionsView(recipe: recipe,
                                 selectedServingSize: $selectedServingSize,
                                 targetWeight: $targetWeight)
            }
        }
        .sheet(isPresented: $showsEditor) {
            NavigationStack {
                EditRecipeView(recipeId: recipe.objectID)
                    .toolbar {
                        // An X, not the word: the editor's own "Löschen"
                        // shares the leading side, and with two titles there
                        // the bar's title shrank to "Rezept bearbe…".
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Schließen", systemImage: "xmark", role: .close) {
                                showsEditor = false
                            }
                            .accessibilityIdentifier("recipe.closeEditor")
                        }
                    }
            }
        }
        // Shopping lists are a Pro feature; locked, the sheet offers Pro.
        .sheet(isPresented: $showsShoppingList) {
            NavigationStack {
                ProLockedScreen(.shoppingList) {
                    ShoppingCartSelectFormView(recipe: recipe,
                                               selectedServingSize: $selectedServingSize,
                                               targetWeight: $targetWeight)
                }
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Schließen") {
                            showsShoppingList = false
                        }
                    }
                }
            }
        }
        // A starter is fed, not baked: it gets its feeding diary instead of
        // a bake history entry; every other recipe the other way round.
        .sheet(isPresented: $showsBakeEntry) {
            NavigationStack {
                BakeHistoryAddView(recipeId: recipe.objectID)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Schließen") {
                                showsBakeEntry = false
                            }
                        }
                    }
            }
        }
        .sheet(isPresented: $showsFeedingDiary) {
            NavigationStack {
                StarterFeedingLogView(recipeId: recipe.objectID)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Schließen") {
                                showsFeedingDiary = false
                            }
                        }
                    }
            }
        }
    }
}
