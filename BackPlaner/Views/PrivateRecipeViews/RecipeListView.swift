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

    // The row's thumbnail is decorative (it is accessibilityHidden) and stays
    // 50 pt whatever the text size. At the accessibility sizes those 50 pt plus
    // the 12 pt gap are the difference between a name that wraps at its word
    // boundaries and one that breaks mid-word: the name column is 261 pt, and
    // "Sauerteigbrot" alone wants slightly more, so it came out "Sauerteigbr /
    // ot". Dropping the decoration there gives the name 323 pt.
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    
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
                    if filterBy.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && rating == 0 {
                        // Nothing here yet: offer the two ways a first recipe
                        // arrives, instead of a dead end.
                        ContentUnavailableView {
                            Label("Keine eigenen Rezepte", systemImage: "book.closed")
                        } description: {
                            Text("Hol Dir ein Rezept aus der Datenbank oder lege ein eigenes an – mit Komponenten, Zutaten und Schritten, aus denen die App Deinen Backplan rechnet.")
                        } actions: {
                            NavigationLink("Rezept-Datenbank öffnen") {
                                RecipeFBListView()
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(Theme.accentTop)

                            NavigationLink("Neues Rezept anlegen") {
                                AddNewRecipeDataView()
                            }
                            .buttonStyle(.bordered)
                            .tint(Theme.accentText)
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else {
                        ContentUnavailableView(
                            "Keine passenden Rezepte",
                            systemImage: "line.3.horizontal.decrease.circle",
                            description: Text("Passe Suche, Tags oder Bewertung an.")
                        )
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                } else {
                    List {
                        
                        ForEach(filteredRecipes, id: \.self) { r in
                            // Invisible link plus an own chevron, see
                            // RecipeFBListView: the List's disclosure indicator
                            // would sit outside the white card.
                            ZStack {
                                NavigationLink(destination: TabsView(recipe: r)) { EmptyView() }
                                    .opacity(0)
                                    .accessibilityHidden(true)

                                HStack(spacing: 12.0) {

                                    if !dynamicTypeSize.isAccessibilitySize {
                                        let image = UIImage(data: r.image) ?? UIImage()
                                        Image(uiImage: image)
                                            .resizable()
                                            .scaledToFill()
                                            .frame(width: 50, height: 50, alignment: .center)
                                            .clipped()
                                            .cornerRadius(8)
                                            .accessibilityHidden(true)
                                    }

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

                                    if !dynamicTypeSize.isAccessibilitySize {
                                        Image(systemName: "chevron.right")
                                            .font(.system(size: 14, weight: .semibold))
                                            .foregroundColor(Theme.subtitle)
                                    }
                                }
                                .cardStyle()
                                .accessibilityElement(children: .combine)
                                .accessibilityAddTraits(.isButton)
                                // The row draws no stars, so the label is the only
                                // place the rating is announced — with its scale,
                                // because a bare number says nothing.
                                .accessibilityLabel(Text("\(r.name), Bewertung \(r.rating) von 5 Sternen"))
                            }
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
