//
//  RecipeFBListView.swift
//  PetersBackPlaner
//
//  Created by Hans-Peter Müller on 23.11.21.
//

import SwiftUI
import CoreData

struct RecipeFBListView: View {
    
    @Environment(\.managedObjectContext) private var viewContext
    @EnvironmentObject var modelFB: RecipeFBModel
    @EnvironmentObject var model:   RecipeModel
    @ObservedObject private var moderation = ModerationStore.shared

    @State private var filterBy  = ""
    @State private var nameOrTag = 1
    @State private var rating    = 0

    var recipeId: NSManagedObjectID?

    private var filteredFBRecipes: [RecipeFB] {
        // Exclude recipes from blocked authors or that the user reported/hid.
        let base = modelFB.recipesFB.filter {
            !moderation.shouldHide(authorId: $0.authorId, recipeId: $0.id)
        }
        let search = filterBy.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

        // Fast path: no filtering by text and no rating threshold
        if search.isEmpty && rating == 0 {
            return base
        }

        return base.filter { r in
            let matchesRating = r.rating >= rating
            guard !search.isEmpty else { return matchesRating }

            if nameOrTag == 1 {
                return matchesRating && r.name.lowercased().contains(search)
            } else {
                return matchesRating && r.tags.contains { $0.lowercased().contains(search) }
            }
        }
    }
    
    var body: some View {
        
        NavigationStack {
            
            VStack (alignment: .leading) {

                if modelFB.isLoading && modelFB.recipesFB.isEmpty {
                    ProgressView("Lade Rezepte …")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if filteredFBRecipes.isEmpty {
                    ContentUnavailableView(
                        filterBy.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Keine Rezepte geladen" : "Keine passenden Rezepte",
                        systemImage: "icloud.slash",
                        description: Text(filterBy.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Die Rezeptdatenbank hat noch keine Einträge geladen." : "Passe Suche, Tags oder Bewertung an.")
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    List {
                        ForEach(filteredFBRecipes) { r in
                            NavigationLink(
                            destination: TabsFBView(recipeFB: r),
                            label: {
                                
                                HStack(spacing: 12.0) {
                                    
                                    let uiImage = GlobalVariables.recipesImage[r.id ?? ""] ?? UIImage(systemName: "photo") ?? UIImage()
                                    Image(uiImage: uiImage)
                                        .resizable()
                                        .scaledToFill()
                                        .frame(width: 50, height: 50, alignment: .center)
                                        .clipped()
                                        .cornerRadius(8)

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
                                .accessibilityLabel(Text("\(r.name), Bewertung \(r.rating)"))
                            }
                        )
                    }
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                    .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
                }
                .listStyle(.plain)
                .clearScrollBackground()
                .refreshable {
                    await modelFB.refresh()
                }
                }
            }
            .warmBackground()
            .navigationTitle("Rezept-Datenbank")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $filterBy, prompt: "Rezept suchen")
            .searchScopes($nameOrTag) {
                Text("Name").tag(1)
                Text("Tags").tag(2)
            }
            .autocorrectionDisabled()
        }
    }
}
