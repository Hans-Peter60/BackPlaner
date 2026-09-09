//
//  RecipeListView.swift
//  PetersBackPlaner App
//
//  Created by Hans-Peter Müller on 2021-01-14.
//

import SwiftUI
import CoreData
import os

struct RecipeListView: View {
    
    @Environment(\.managedObjectContext) private var viewContext
    
    @EnvironmentObject var model:RecipeModel
    
    @FetchRequest(sortDescriptors: [NSSortDescriptor(key: "name", ascending: true)])
    private var recipes: FetchedResults<Recipe>
    
    @State private var filterBy  = ""
    @State private var nameOrTag = 1
    @State private var rating    = 0
    @State private var confirmationShown = false
    @State private var recipeToDelete: Recipe?
    @State private var deleteHaptic = false

    var recipeId: NSManagedObjectID?
    
    private var filteredRecipes: [Recipe] {

        let search = filterBy.trimmingCharacters(in: .whitespacesAndNewlines)

        // No filter text, so only apply the rating threshold
        if search.isEmpty {
            return recipes.filter { $0.rating >= rating }
        }

        // Filter by the search term and return a subset of recipes which contain
        // it in the name or in one of the tags. Matching is case-insensitive and
        // works on substrings, and the rating threshold keeps applying — so both
        // filters can be used together.
        return recipes.filter { r in

            guard r.rating >= rating else { return false }

            if nameOrTag == 1 {
                return r.name.localizedCaseInsensitiveContains(search)
            }
            return r.tags.contains { $0.localizedCaseInsensitiveContains(search) }
        }
    }
    
    var body: some View {
        
        NavigationStack {
            
            VStack (alignment: .leading) {

                if filteredRecipes.isEmpty {
                    ContentUnavailableView(
                        filterBy.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Keine eigenen Rezepte" : "Keine passenden Rezepte",
                        systemImage: "book.closed",
                        description: Text(filterBy.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Lege ein neues Rezept an, um es hier zu sehen." : "Passe Suche, Tags oder Bewertung an.")
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    List {
                        
                        ForEach(filteredRecipes, id: \.self) { r in
                            
                            NavigationLink(
                            destination: TabsView(recipe: r),
                            label: {
                                
                                HStack(spacing: 12.0) {

                                    let image = UIImage(data: r.image) ?? UIImage()
                                    Image(uiImage: image)
                                        .resizable()
                                        .scaledToFill()
                                        .frame(width: 50, height: 50, alignment: .center)
                                        .clipped()
                                        .cornerRadius(8)
                                        .accessibilityHidden(true)

                                    VStack (alignment: .leading, spacing: 3) {
                                        Text(r.name)
                                            .font(Theme.brandFont(16))
                                            .foregroundColor(Theme.cardTitle)
                                            .multilineTextAlignment(.leading)

                                        RecipeTagsView(tags: r.tags)
                                            .font(Theme.bodyFont(12))
                                            .foregroundColor(Theme.subtitle)
                                            .multilineTextAlignment(.leading)
                                    }

                                    Spacer(minLength: 0)
                                }
                                .cardStyle()
                                .accessibilityElement(children: .combine)
                                // The row draws no stars, so the label is the only
                                // place the rating is announced — with its scale,
                                // because a bare number says nothing.
                                .accessibilityLabel(Text("\(r.name), Bewertung \(r.rating) von 5 Sternen"))
                            })
                    }
                    .onDelete { indexSet in
                        // Defer the actual deletion until the user confirms, so a
                        // whole recipe is never removed on an accidental swipe.
                        guard let index = indexSet.first, filteredRecipes.indices.contains(index) else { return }
                        recipeToDelete = filteredRecipes[index]
                        confirmationShown = true
                    }
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                    .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
                }
                .listStyle(.plain)
                .clearScrollBackground()
                }
            }
            .warmBackground()
            .navigationTitle("Eigene Rezepte")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $filterBy, prompt: "Rezept suchen")
            .searchScopes($nameOrTag) {
                Text("Name").tag(1)
                Text("Tags").tag(2)
            }
            .autocorrectionDisabled()
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Picker("Mindestbewertung", selection: $rating) {
                            Text("Alle Bewertungen").tag(0)
                            ForEach(1...5, id: \.self) { stars in
                                Text("\(stars) Sterne und mehr").tag(stars)
                            }
                        }
                    } label: {
                        Label("Nach Bewertung filtern",
                              systemImage: rating > 0 ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle")
                    }
                }
            }
            .confirmationDialog("Rezept löschen?", isPresented: $confirmationShown, titleVisibility: .visible, presenting: recipeToDelete) { recipe in
                Button("Löschen", role: .destructive) {
                    delete(recipe)
                }
                Button("Abbrechen", role: .cancel) { }
            } message: { recipe in
                Text("„\(recipe.name)“ wird dauerhaft gelöscht.")
            }
            .sensoryFeedback(.success, trigger: deleteHaptic)
        }
    }

    private func delete(_ recipe: Recipe) {
        viewContext.delete(recipe)
        do {
            try viewContext.save()
            deleteHaptic.toggle()
        }
        catch {
            AppLog.persistence.error("Could not delete recipe: \(error)")
        }
    }
}
