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

    // Admin moderation: the public recipe a swipe asked to delete, pending
    // confirmation — nil while no dialog is up.
    @State private var adminDeleteCandidate: RecipeFB?
    // Error message shown when that delete fails (e.g. the rules deny it), so
    // the row does not silently stay as if nothing had been tried.
    @State private var deleteErrorMessage: String?

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
                            // The link is invisible and the card draws its own
                            // chevron: the List would otherwise place the
                            // disclosure indicator outside the white card, in
                            // the row's trailing inset.
                            ZStack {
                                NavigationLink(destination: TabsFBView(recipeFB: r)) { EmptyView() }
                                    .opacity(0)
                                    .accessibilityHidden(true)

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
                                // because a bare number says nothing. The lock
                                // symbol is only decorative, so its meaning has
                                // to be spelled out here as well.
                                .accessibilityLabel(r.visibility == .authorOnly
                                                    ? Text("\(r.name), privates Rezept, Bewertung \(r.rating) von 5 Sternen")
                                                    : Text("\(r.name), Bewertung \(r.rating) von 5 Sternen"))
                            }
                            // Admins may remove any public recipe straight from
                            // the list. No full swipe: the action is final, so it
                            // always goes through the confirmation below.
                            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                if modelFB.isAdmin && r.visibility == .everyone {
                                    Button(role: .destructive) {
                                        adminDeleteCandidate = r
                                    } label: {
                                        Label("Löschen", systemImage: "trash")
                                    }
                                    .accessibilityLabel("Rezept löschen (Admin)")
                                }
                            }
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
                .confirmationDialog("Öffentliches Rezept löschen?",
                                    isPresented: Binding(get: { adminDeleteCandidate != nil },
                                                         set: { if !$0 { adminDeleteCandidate = nil } }),
                                    titleVisibility: .visible,
                                    presenting: adminDeleteCandidate) { recipe in
                    Button("Löschen", role: .destructive) {
                        modelFB.deleteRecipeAsAdmin(recipe) { result in
                            if case .failure(let error) = result {
                                deleteErrorMessage = error.localizedDescription
                            }
                        }
                    }
                    Button("Abbrechen", role: .cancel) { }
                } message: { recipe in
                    // Names the recipe: unlike on its own screen, the list gives
                    // no other clue which one is about to go.
                    Text("„\(recipe.name)“ wird als Administrator endgültig aus der öffentlichen Datenbank entfernt.")
                }
                .alert("Löschen fehlgeschlagen",
                       isPresented: Binding(get: { deleteErrorMessage != nil },
                                            set: { if !$0 { deleteErrorMessage = nil } })) {
                    Button("OK", role: .cancel) { deleteErrorMessage = nil }
                } message: {
                    Text(deleteErrorMessage ?? "")
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
