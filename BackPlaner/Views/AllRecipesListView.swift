//
//  AllRecipesListView.swift
//  BackPlaner
//
//  The combined recipe browser reached from the main menu: local recipes,
//  private cloud recipes and public cloud recipes in one alphabetical list,
//  each of the three independently shown or hidden by a persisted toggle.
//  Replaces the former separate "Rezept-Datenbank" (RecipeFBListView) and
//  "Eigene Rezepte" (RecipeListView) menu entries; RecipeListView itself
//  stays in place for the other screens that specifically need a
//  local-only picker (the empty states of the shopping list and the bake
//  history).
//

import SwiftUI
import CoreData
import Translation

struct AllRecipesListView: View {

    @Environment(\.managedObjectContext) private var viewContext
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @EnvironmentObject var model: RecipeModel
    @EnvironmentObject var modelFB: RecipeFBModel
    @ObservedObject private var moderation = ModerationStore.shared

    @AppStorage(AppSettingsKeys.showLocalRecipes) private var showLocalRecipes = AppSettings.defaultShowLocalRecipes
    @AppStorage(AppSettingsKeys.showPrivateCloudRecipes) private var showPrivateCloudRecipes = AppSettings.defaultShowPrivateCloudRecipes
    @AppStorage(AppSettingsKeys.showPublicCloudRecipes) private var showPublicCloudRecipes = AppSettings.defaultShowPublicCloudRecipes

    // Settings → Übersetzung: off, the list is left in its recipes' own
    // languages instead of being translated ahead of time.
    @AppStorage(AppSettingsKeys.automaticTranslation) private var automaticTranslation = AppSettings.defaultAutomaticTranslation

    @FetchRequest(sortDescriptors: [NSSortDescriptor(key: "name", ascending: true)])
    private var recipes: FetchedResults<Recipe>

    @State private var filterBy  = ""
    @State private var nameOrTag = 1
    @State private var rating    = 0

    @State private var confirmationShown = false
    @State private var recipeToDelete: Recipe?
    @State private var deleteHaptic = false

    // Admin moderation: the public recipe a swipe asked to delete, pending
    // confirmation — nil while no dialog is up.
    @State private var adminDeleteCandidate: RecipeFB?
    // Error message shown when that delete fails (e.g. the rules deny it), so
    // the row does not silently stay as if nothing had been tried.
    @State private var deleteErrorMessage: String?

    // The list reads in the app's language: names, summaries and tags of
    // cloud recipes written in another language are translated on the
    // device, one source language at a time (a session translates from one
    // language). Local recipes need none of this.
    @State private var listTranslationConfig: TranslationSession.Configuration?
    @State private var listTranslationQueue: [String] = []
    @State private var listTranslationTarget = ""
    /// Source languages already attempted for the current target, so a
    /// declined download or a failure is not retried on every appearance.
    @State private var attemptedListSources: Set<String> = []

    var recipeId: NSManagedObjectID?

    /// One row of the combined list, whichever store it came from.
    private enum Row: Identifiable {
        case local(Recipe)
        case cloud(RecipeFB)

        var id: String {
            switch self {
            case .local(let recipe):   return "local-\(recipe.objectID.uriRepresentation().absoluteString)"
            case .cloud(let recipeFB): return "cloud-\(recipeFB.id ?? recipeFB.firestoreId ?? recipeFB.name)"
            }
        }

        var name: String {
            switch self {
            case .local(let recipe):   return recipe.name
            case .cloud(let recipeFB): return recipeFB.name
            }
        }

        var tags: [String] {
            switch self {
            case .local(let recipe):   return recipe.tags
            case .cloud(let recipeFB): return recipeFB.tags
            }
        }

        var rating: Int {
            switch self {
            case .local(let recipe):   return recipe.rating
            case .cloud(let recipeFB): return recipeFB.rating
            }
        }
    }

    /// Every row the three toggles currently allow, regardless of search or
    /// rating — used to tell "nothing exists" apart from "nothing matches".
    private var toggledRows: [Row] {
        var rows: [Row] = []
        if showLocalRecipes {
            rows += recipes.map(Row.local)
        }
        if showPrivateCloudRecipes || showPublicCloudRecipes {
            let visible = modelFB.recipesFB
                .filter { !moderation.shouldHide(authorId: $0.authorId, recipeId: $0.id) }
                .filter { $0.visibility == .authorOnly ? showPrivateCloudRecipes : showPublicCloudRecipes }
            rows += visible.map(Row.cloud)
        }
        return rows
    }

    private var filteredRows: [Row] {
        let search = filterBy.trimmingCharacters(in: .whitespacesAndNewlines)
        let base = toggledRows.filter { $0.rating >= rating }

        let matched: [Row]
        if search.isEmpty {
            matched = base
        } else if nameOrTag == 1 {
            matched = base.filter { $0.name.localizedCaseInsensitiveContains(search) }
        } else {
            matched = base.filter { row in row.tags.contains { $0.localizedCaseInsensitiveContains(search) } }
        }

        return matched.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    private var isFiltering: Bool {
        !filterBy.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || rating > 0
            || !showLocalRecipes || !showPrivateCloudRecipes || !showPublicCloudRecipes
    }

    var body: some View {

        NavigationStack {

            VStack(alignment: .leading, spacing: 0) {

                filterChips

                if modelFB.isLoading && toggledRows.isEmpty {
                    ProgressView("Lade Rezepte …")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if filteredRows.isEmpty {
                    if !isFiltering {
                        ContentUnavailableView {
                            Label("Noch keine Rezepte", systemImage: "book.closed")
                        } description: {
                            Text("Lege ein eigenes Rezept an – mit Komponenten, Zutaten und Schritten, aus denen die App Deinen Backplan rechnet.")
                        } actions: {
                            NavigationLink("Neues Rezept anlegen") {
                                AddNewRecipeDataView()
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(Theme.accentTop)
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else {
                        ContentUnavailableView(
                            "Keine passenden Rezepte",
                            systemImage: "line.3.horizontal.decrease.circle",
                            description: Text("Passe Suche, Tags, Bewertung oder die Filter oben an.")
                        )
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                } else {
                    List {
                        ForEach(filteredRows) { row in
                            rowView(for: row)
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
                    .confirmationDialog("Rezept löschen?", isPresented: $confirmationShown, titleVisibility: .visible, presenting: recipeToDelete) { recipe in
                        Button("Löschen", role: .destructive) {
                            delete(recipe)
                        }
                        Button("Abbrechen", role: .cancel) { }
                    } message: { recipe in
                        Text("„\(recipe.name)“ wird dauerhaft gelöscht.")
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
                        Text("„\(recipe.name)“ wird als Administrator endgültig aus der öffentlichen Datenbank entfernt.")
                    }
                    .alert("Löschen fehlgeschlagen",
                           isPresented: Binding(get: { deleteErrorMessage != nil },
                                                set: { if !$0 { deleteErrorMessage = nil } })) {
                        Button("OK", role: .cancel) { deleteErrorMessage = nil }
                    } message: {
                        Text(deleteErrorMessage ?? "")
                    }
                    .sensoryFeedback(.success, trigger: deleteHaptic)
                }
            }
            .warmBackground()
            .navigationTitle("Rezept-Datenbank")
            .navigationBarTitleDisplayMode(.inline)
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
            .searchable(text: $filterBy, prompt: "Rezept suchen")
            .searchScopes($nameOrTag) {
                Text("Name").tag(1)
                Text("Tags").tag(2)
            }
            .autocorrectionDisabled()
            .onAppear { scheduleListTranslation() }
            // The list is refetched on launch, on pull-to-refresh and when
            // the identity changes; each time it may bring untranslated rows.
            .onChange(of: modelFB.isLoading) { _, isLoading in
                if !isLoading { scheduleListTranslation() }
            }
            .translationTask(listTranslationConfig) { session in
                await translateListEntries(using: session)
            }
        }
    }

    // MARK: - Filter chips

    /// Three independent toggles, one per recipe source — deliberately not a
    /// single-select picker like the old "Alle/Nur meine" one: a sourdough
    /// baker may want local and private cloud recipes but not the whole
    /// public database cluttering the list, or any other combination.
    private var filterChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                filterChip("Lokal", systemImage: "iphone", isOn: $showLocalRecipes)
                filterChip("Eigene", systemImage: "lock.icloud", isOn: $showPrivateCloudRecipes)
                filterChip("Öffentlich", systemImage: "globe", isOn: $showPublicCloudRecipes)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
    }

    private func filterChip(_ title: LocalizedStringKey, systemImage: String, isOn: Binding<Bool>) -> some View {
        Button {
            isOn.wrappedValue.toggle()
        } label: {
            Label(title, systemImage: systemImage)
                .font(Theme.bodyFont(14))
                .lineLimit(1)
                .foregroundColor(isOn.wrappedValue ? .white : Theme.subtitle)
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background(
                    Capsule().fill(isOn.wrappedValue ? AnyShapeStyle(Theme.accent) : AnyShapeStyle(Theme.card))
                )
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isOn.wrappedValue ? [.isButton, .isSelected] : [.isButton])
    }

    // MARK: - Rows

    @ViewBuilder
    private func rowView(for row: Row) -> some View {
        switch row {
        case .local(let recipe):
            localRow(recipe)
        case .cloud(let recipeFB):
            cloudRow(recipeFB)
        }
    }

    private func localRow(_ r: Recipe) -> some View {
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

                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 5) {
                        Image(systemName: "iphone")
                            .font(Theme.bodyFont(12))
                            .foregroundColor(Theme.subtitle)

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
            .accessibilityLabel(Text("\(r.name), lokales Rezept, Bewertung \(r.rating) von 5 Sternen"))
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            Button(role: .destructive) {
                recipeToDelete = r
                confirmationShown = true
            } label: {
                Label("Löschen", systemImage: "trash")
            }
        }
    }

    private func cloudRow(_ r: RecipeFB) -> some View {
        ZStack {
            NavigationLink(destination: TabsFBView(recipeFB: r)) { EmptyView() }
                .opacity(0)
                .accessibilityHidden(true)

            HStack(spacing: 12.0) {
                if !dynamicTypeSize.isAccessibilitySize {
                    let uiImage = GlobalVariables.recipesImage[r.id ?? ""] ?? UIImage(systemName: "photo") ?? UIImage()
                    Image(uiImage: uiImage)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 50, height: 50, alignment: .center)
                        .clipped()
                        .cornerRadius(8)
                }

                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 5) {
                        // Marks a recipe only its author can see.
                        if r.visibility == .authorOnly {
                            Image(systemName: "lock.fill")
                                .font(Theme.bodyFont(12))
                                .foregroundColor(Theme.subtitle)
                        } else {
                            Image(systemName: "globe")
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
            // Carries the recipe's own id, not just a shared marker: its
            // displayed name may already be a cached translation by the
            // time a UI test looks for a specific recipe.
            .accessibilityIdentifier("publicRecipe.row.\(r.id ?? "")")
            .accessibilityLabel(r.visibility == .authorOnly
                                ? Text("\(r.name), privates Rezept, Bewertung \(r.rating) von 5 Sternen")
                                : Text("\(r.name), Bewertung \(r.rating) von 5 Sternen"))
        }
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

    private func delete(_ recipe: Recipe) {
        viewContext.delete(recipe)
        do {
            try viewContext.save()
            deleteHaptic.toggle()
        } catch {
            AppLog.persistence.error("Could not delete recipe: \(error)")
        }
    }

    // MARK: - Translating the list

    /// Lines up the cloud recipes whose list text is not yet cached in the
    /// app's language, grouped by the language they are written in, and
    /// starts with the first group. Does nothing while a group is being
    /// translated, or while automatic translation is off in the settings.
    private func scheduleListTranslation() {
        guard automaticTranslation else { return }
        guard listTranslationConfig == nil || listTranslationQueue.isEmpty else { return }

        let target = RecipeFB.preferredLanguageCode
        guard RecipeTranslator.supportedLanguages.contains(where: { $0.code == target }) else { return }
        if target != listTranslationTarget {
            listTranslationTarget = target
            attemptedListSources = []
        }

        let pendingSources = Set(modelFB.recipesFB.lazy
            .filter { !$0.hasCachedTranslation(languageCode: target) }
            .map { RecipeTranslator.sourceLanguageCode(for: $0) }
            .filter { $0 != target && !attemptedListSources.contains($0) })

        listTranslationQueue = pendingSources.sorted()
        startNextListTranslation()
    }

    private func startNextListTranslation() {
        guard let source = listTranslationQueue.first else {
            listTranslationConfig = nil
            return
        }
        attemptedListSources.insert(source)
        listTranslationConfig = TranslationSession.Configuration(
            source: Locale.Language(identifier: source),
            target: Locale.Language(identifier: listTranslationTarget)
        )
    }

    /// Translates the group the current session is for, saves what the rules
    /// allow (own recipes, or everything for an admin), and moves on to the
    /// next source language. A failure is logged, not shown: nobody asked.
    private func translateListEntries(using session: TranslationSession) async {
        guard let source = listTranslationQueue.first else { return }
        let target = listTranslationTarget

        let recipesToTranslate = modelFB.recipesFB.filter {
            !$0.hasCachedTranslation(languageCode: target)
                && RecipeTranslator.sourceLanguageCode(for: $0) == source
        }

        do {
            try await RecipeTranslator.translateListEntries(recipesToTranslate, into: target, using: session)
            recipesToTranslate.forEach { modelFB.saveTranslations($0) }
        } catch {
            AppLog.firebase.error("Translating the recipe list from \(source) into \(target) failed: \(error.localizedDescription)")
        }

        listTranslationQueue.removeFirst()
        startNextListTranslation()
    }
}
