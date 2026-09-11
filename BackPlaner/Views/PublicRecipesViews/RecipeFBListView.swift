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
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @EnvironmentObject var modelFB: RecipeFBModel
    @EnvironmentObject var model:   RecipeModel
    @ObservedObject private var moderation = ModerationStore.shared

    @State private var filterBy  = ""
    @State private var nameOrTag = 1
    @State private var rating    = 0
    @State private var ownership = OwnershipFilter.all

    var recipeId: NSManagedObjectID?

    /// Restricts the list to the user's own recipes — the ones he published and
    /// the private ones only he can see.
    private enum OwnershipFilter: String, CaseIterable, Identifiable {
        case all
        case mine

        var id: String { rawValue }

        var title: LocalizedStringKey {
            switch self {
            case .all:  return "Alle Rezepte"
            case .mine: return "Nur meine"
            }
        }
    }

    private var filteredFBRecipes: [RecipeFB] {
        // Exclude recipes from blocked authors or that the user reported/hid.
        var base = modelFB.recipesFB.filter {
            !moderation.shouldHide(authorId: $0.authorId, recipeId: $0.id)
        }
        if ownership == .mine {
            let me = moderation.authorId
            base = base.filter { $0.authorId == me }
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
                    // An active filter is the likely reason for an empty list,
                    // so don't claim the database failed to load.
                    let isFiltering = !filterBy.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                        || ownership == .mine
                        || rating > 0
                    ContentUnavailableView(
                        isFiltering ? "Keine passenden Rezepte" : "Keine Rezepte geladen",
                        systemImage: "icloud.slash",
                        description: Text(isFiltering ? "Passe Suche, Tags oder Bewertung an." : "Die Rezeptdatenbank hat noch keine Einträge geladen.")
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    List {
                        ForEach(filteredFBRecipes) { r in
                            NavigationLink(
                            destination: TabsFBView(recipeFB: r),
                            label: {
                                
                                HStack(spacing: 12.0) {
                                    
                                    // See RecipeListView: at the accessibility
                                    // text sizes the decorative thumbnail's
                                    // 50 pt are worth more to the recipe name,
                                    // which otherwise breaks mid-word.
                                    if !dynamicTypeSize.isAccessibilitySize {
                                        let uiImage = GlobalVariables.recipesImage[r.id ?? ""] ?? UIImage(systemName: "photo") ?? UIImage()
                                        Image(uiImage: uiImage)
                                            .resizable()
                                            .scaledToFill()
                                            .frame(width: 50, height: 50, alignment: .center)
                                            .clipped()
                                            .cornerRadius(8)
                                    }

                                    VStack (alignment: .leading, spacing: 3) {
                                        HStack(spacing: 5) {
                                            // Marks a recipe only its author can see.
                                            if r.visibility == .authorOnly {
                                                Image(systemName: "lock.fill")
                                                    .font(Theme.bodyFont(12))
                                                    .foregroundColor(Theme.subtitle)
                                            }

                                            Text(r.name)
                                                .font(Theme.brandFont(16))
                                                .foregroundColor(Theme.cardTitle)
                                                .multilineTextAlignment(.leading)
                                        }

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
                                // because a bare number says nothing. The lock
                                // symbol is only decorative, so its meaning has
                                // to be spelled out here as well.
                                .accessibilityLabel(r.visibility == .authorOnly
                                                    ? Text("\(r.name), privates Rezept, Bewertung \(r.rating) von 5 Sternen")
                                                    : Text("\(r.name), Bewertung \(r.rating) von 5 Sternen"))
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
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Menu {
                        Picker("Auswahl", selection: $ownership) {
                            ForEach(OwnershipFilter.allCases) { filter in
                                Text(filter.title).tag(filter)
                            }
                        }
                    } label: {
                        Image(systemName: ownership == .mine ? "person.crop.circle.fill" : "line.3.horizontal.decrease.circle")
                    }
                    .accessibilityLabel("Rezepte filtern")
                }
            }
            .searchable(text: $filterBy, prompt: "Rezept suchen")
            .searchScopes($nameOrTag) {
                Text("Name").tag(1)
                Text("Tags").tag(2)
            }
            .autocorrectionDisabled()
        }
    }
}
