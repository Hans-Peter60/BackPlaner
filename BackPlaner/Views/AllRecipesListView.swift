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

import BakePlannerCore
import SwiftUI
import CoreData
import Translation

struct AllRecipesListView: View {

    /// Changes with every ⌘F; the search field takes the focus each time.
    var searchFocusRequest = 0
    @FocusState private var searchIsFocused: Bool
    /// On the iPad the title bar holds the tab bar as well; the search
    /// field then moves under the bar, so that the three buttons – rating
    /// filter, "Mehr", "+" – stand beside the tabs as on the iPhone. Only
    /// where the window is too narrow for that – an iPad up to 11 inches
    /// held upright, 834 pt and less, where the system folded "Mehr" and
    /// "+" into an overflow – the filter lives in the "Mehr" menu instead.
    /// The 13-inch iPad upright (1032 pt) and every landscape keep the
    /// three buttons.
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @State private var windowWidth: CGFloat = 1024
    private var searchFieldUnderBar: Bool { horizontalSizeClass == .regular }
    private var filterInMenu: Bool { horizontalSizeClass == .regular && windowWidth < 900 }

    @Environment(\.managedObjectContext) private var viewContext
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @EnvironmentObject var model: RecipeModel
    @EnvironmentObject var modelFB: RecipeFBModel
    @ObservedObject private var moderation = ModerationStore.shared

    @AppStorage(AppSettingsKeys.showLocalRecipes) private var showLocalRecipes = AppSettings.defaultShowLocalRecipes
    @AppStorage(AppSettingsKeys.showOwnPublishedRecipes) private var showOwnPublishedRecipes = AppSettings.defaultShowOwnPublishedRecipes
    @AppStorage(AppSettingsKeys.showPublicCloudRecipes) private var showPublicCloudRecipes = AppSettings.defaultShowPublicCloudRecipes
    /// Off, the list shows only recipes of their own; their variants are
    /// reached from the recipe's page.
    @AppStorage(AppSettingsKeys.showVariantRecipes) private var showVariantRecipes = true

    // Settings → Übersetzung: off, the list is left in its recipes' own
    // languages instead of being translated ahead of time.
    @AppStorage(AppSettingsKeys.automaticTranslation) private var automaticTranslation = AppSettings.defaultAutomaticTranslation

    @FetchRequest(sortDescriptors: [NSSortDescriptor(key: "name", ascending: true)])
    private var pantryItems: FetchedResults<PantryItem>
    @FetchRequest(sortDescriptors: [])
    private var pantryReservations: FetchedResults<PantryReservation>

    /// The stock less what open plans have reserved.
    private var availablePantry: [StoredPantryItem] {
        PantryLedger.available(pantryItems.map(CoreDataPantryStore.stored),
                               reservations: pantryReservations.compactMap(CoreDataPantryReservationStore.stored))
    }

    @FetchRequest(sortDescriptors: [NSSortDescriptor(key: "name", ascending: true)])
    private var recipes: FetchedResults<Recipe>

    @State private var filterBy  = ""
    @State private var nameOrTag = 1
    @State private var rating    = 0
    /// What the recipe itself is like — duration, day flow, leavening, grain,
    /// dough yield, equipment, work — and what the history says about it.
    @State private var facetFilter = RecipeFacetFilter()
    /// The collections the person saved from the facets; chips after the presets.
    @State private var savedCollections = SavedRecipeCollectionStore()
    /// "Als Sammlung sichern" asks for a name; "Umbenennen" on a saved chip too.
    @State private var isNamingCollection = false
    @State private var collectionName = ""
    @State private var renamingCollection: SavedRecipeCollection?
    /// "Fertig bis …": only recipes that can still be made by then, each
    /// with the start it needs, earliest start first.
    @State private var finishBy: Date?
    /// The sheets over the list, one at a time: the "Fertig bis" picker and
    /// the paywall a locked menu entry asked for. One `.sheet(item:)` for
    /// both: two sheet modifiers on the same view fire unreliably when a
    /// menu is on its way out.
    enum ListSheet: Identifiable {
        case finishPicker
        case paywall(ProFeature)
        var id: String {
            switch self {
            case .finishPicker: return "finish"
            case .paywall(let feature): return "paywall.\(feature.rawValue)"
            }
        }
    }
    @State private var listSheet: ListSheet?
    @State private var finishDraft = Date()
    /// Facets read once per recipe; a recipe's facets change only when it is
    /// edited, and the list is rebuilt then anyway.
    @State private var facetCache: [Row.ID: RecipeFacets] = [:]

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
            rows += recipes
                .filter { showVariantRecipes || $0.origin == nil }
                .map(Row.local)
        }
        if showOwnPublishedRecipes || showPublicCloudRecipes {
            let visible = modelFB.recipesFB
                .filter { !moderation.shouldHide(authorId: $0.authorId, recipeId: $0.id) }
                .filter { isOwnPublished($0) ? showOwnPublishedRecipes : showPublicCloudRecipes }
            rows += visible.map(Row.cloud)
        }
        return rows
    }

    /// True for a public recipe this identity published. Empty author ids
    /// (legacy recipes) never match.
    private func isOwnPublished(_ recipe: RecipeFB) -> Bool {
        guard let author = recipe.authorId, !author.isEmpty else { return false }
        return author == moderation.authorId
    }

    private var filteredRows: [Row] {
        let search = filterBy.trimmingCharacters(in: .whitespacesAndNewlines)
        var base = toggledRows.filter { $0.rating >= rating }
        if facetFilter.isActive {
            base = base.filter { row in facetFilter.matches(facets(of: row), history: history(of: row)) }
        }
        if facetFilter.pantryOnly {
            // The pantry at the recipe as stored; the facet filter itself
            // knows no pantry.
            let pantry = availablePantry
            base = base.filter { row in PantryMatcher.check(content(of: row), scale: 1, pantry: pantry).isComplete }
        }
        if facetFilter.useUpOnly {
            base = base.filter { row in !useUp(of: row).isEmpty }
        }
        if finishBy != nil {
            base = base.filter { finishOutcome(of: $0) != nil }
        }

        let matched: [Row]
        if search.isEmpty {
            matched = base
        } else if nameOrTag == 1 {
            matched = base.filter { $0.name.localizedCaseInsensitiveContains(search) }
        } else {
            matched = base.filter { row in row.tags.contains { $0.localizedCaseInsensitiveContains(search) } }
        }

        // Under "Vorrat aufbrauchen" the recipe that uses most of what runs
        // out soon comes first.
        if facetFilter.useUpOnly {
            return matched.sorted { a, b in
                let scoreA = PantryMatcher.useUpScore(useUp(of: a))
                let scoreB = PantryMatcher.useUpScore(useUp(of: b))
                if scoreA != scoreB { return scoreA > scoreB }
                return a.name.localizedStandardCompare(b.name) == .orderedAscending
            }
        }
        // Under "Fertig bis" the recipe that must start first comes first.
        if finishBy != nil {
            return matched.sorted { a, b in
                let startA = finishOutcome(of: a)?.start ?? .distantFuture
                let startB = finishOutcome(of: b)?.start ?? .distantFuture
                if startA != startB { return startA < startB }
                return a.name.localizedStandardCompare(b.name) == .orderedAscending
            }
        }
        return matched.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    /// What of the soon-expiring pantry the row's recipe uses, most first.
    private func useUp(of row: Row) -> [PantryUse] {
        PantryMatcher.useUp(content(of: row), scale: 1, pantry: availablePantry)
    }

    /// The line under a row's name under "Vorrat aufbrauchen": the item it
    /// uses most of, with its best-before date.
    @ViewBuilder private func useUpLine(for row: Row) -> some View {
        if facetFilter.useUpOnly, let use = useUp(of: row).first {
            let amount = PantryMatcher.baseText(use.usedBase, counted: use.item.isCounted, locale: AppSettings.locale)
            let day = (use.item.bestBefore ?? Date()).formatted(Date.FormatStyle(date: .numeric, time: .omitted).locale(AppSettings.locale))
            Label {
                Text("Verbraucht \(amount) \(use.item.name), haltbar bis \(day)")
            } icon: {
                Image(systemName: "clock.badge.exclamationmark")
            }
            .font(Theme.bodyFont(12))
            .foregroundColor(Theme.warning)
        }
    }

    /// Whether the row's recipe can still be finished by `finishBy`, and
    /// when it would have to start. Nil without "Fertig bis".
    private func finishOutcome(of row: Row) -> FinishByOutcome? {
        guard let finishBy else { return nil }
        let content: RecipeExportData
        switch row {
        case .local(let recipe): content = RecipeExportData(recipe: recipe, includingImage: false)
        case .cloud(let recipe): content = RecipeExportData(recipeFB: recipe, imageData: nil)
        }
        return FinishByPlanner.outcome(for: content, finishBy: finishBy, now: Date(),
                                       languageCode: AppSettings.locale.identifier)
    }

    /// "Start heute 17:45", "Start morgen 06:10", "Start Fr., 14. Nov., 18:00".
    private func startText(for outcome: FinishByOutcome) -> Text {
        let locale = AppSettings.locale
        // The same formatter as the plan sheet, so both read alike.
        let time = TimeCalculation().calculateTime(t: outcome.start)
        if Calendar.current.isDateInToday(outcome.start) {
            return Text("Start heute \(time)")
        }
        if Calendar.current.isDateInTomorrow(outcome.start) {
            return Text("Start morgen \(time)")
        }
        let day = outcome.start.formatted(Date.FormatStyle(date: .abbreviated, time: .omitted).weekday(.abbreviated).locale(locale))
        return Text("Start \(day), \(time)")
    }

    /// The line under a row's name under "Fertig bis": the start, and a
    /// moon when a step falls into the night.
    @ViewBuilder private func startLine(for row: Row) -> some View {
        if let outcome = finishOutcome(of: row) {
            HStack(spacing: 4) {
                Image(systemName: "flag.checkered")
                    .accessibilityHidden(true)
                startText(for: outcome)
                if outcome.hasNightSteps {
                    Image(systemName: "moon.zzz")
                        .accessibilityLabel("Schritte in der Nacht")
                }
            }
            .font(Theme.bodyFont(12))
            .foregroundColor(Theme.accentText)
        }
    }

    /// The chosen finish as the chip and the sheet show it.
    private func finishText(_ date: Date) -> String {
        let locale = AppSettings.locale
        if Calendar.current.isDateInToday(date) || Calendar.current.isDateInTomorrow(date) {
            let time = TimeCalculation().calculateTime(t: date)
            let day = Calendar.current.isDateInToday(date)
                ? String(localized: "heute", locale: locale)
                : String(localized: "morgen", locale: locale)
            return "\(day) \(time)"
        }
        return date.formatted(Date.FormatStyle(date: .abbreviated, time: .shortened).weekday(.abbreviated).locale(locale))
    }

    private var isFiltering: Bool {
        !filterBy.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || rating > 0 || facetFilter.isActive || finishBy != nil
            || !showLocalRecipes || !showOwnPublishedRecipes || !showPublicCloudRecipes || !showVariantRecipes
    }

    /// The row's recipe as plain content, for the package's readings.
    private func content(of row: Row) -> RecipeExportData {
        switch row {
        case .local(let recipe): return RecipeExportData(recipe: recipe, includingImage: false)
        case .cloud(let recipe): return RecipeExportData(recipeFB: recipe, imageData: nil)
        }
    }

    /// The row's facets, read from the recipe once and kept.
    private func facets(of row: Row) -> RecipeFacets {
        if let known = facetCache[row.id] { return known }
        let facets = RecipeFacets.compute(content(of: row))
        DispatchQueue.main.async { facetCache[row.id] = facets }
        return facets
    }

    /// How often and when the recipe was baked — own recipes only; a public
    /// recipe has no history here.
    private func history(of row: Row) -> RecipeFacetFilter.History {
        guard case .local(let recipe) = row else { return .init(count: 0, lastDate: nil, rating: row.rating) }
        let completed = recipe.bakeHistoriesArray.filter { $0.date <= Date() }
        return .init(count: completed.count, lastDate: completed.first?.date, rating: recipe.rating)
    }

    /// What "+" or the "Mehr" menu opened, pushed onto the tab's stack.
    @State private var pushedDestination: MenuDestination?
    /// "Rezepte exportieren" from the "Mehr" menu, a sheet over the list.
    @State private var exportsRecipes = false
    /// "Rezepte importieren" from the "Mehr" menu: the file picker and its outcome.
    @State private var isImportingRecipes = false
    @State private var importResult: RecipeImportResult?
    @State private var importErrorMessage: String?

    var body: some View {

            VStack(alignment: .leading, spacing: 0) {

                filterChips
                collectionChips

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
            .navigationTitle("Rezepte")
            .navigationBarTitleDisplayMode(.inline)
            .navigationDestination(item: $pushedDestination) { destination in
                MenuDestinationView(destination: destination)
            }
            .sheet(isPresented: $exportsRecipes) {
                NavigationStack {
                    RecipeExportSelectionView()
                }
            }
            .fileImporter(isPresented: $isImportingRecipes, allowedContentTypes: [.json]) { result in
                // The picker is still on its way out when this runs; an alert
                // raised right now is dropped, so the outcome is shown once the
                // picker has gone.
                var count: RecipeImportResult?
                var failure: String?
                switch result {
                case .success(let url):
                    do {
                        count = try RecipeImport.importRecipes(from: url, into: viewContext)
                    } catch {
                        failure = error.localizedDescription
                    }
                case .failure(let error):
                    failure = error.localizedDescription
                }
                Task { @MainActor in
                    try? await Task.sleep(for: .milliseconds(600))
                    importResult = count
                    importErrorMessage = failure
                }
            }
            .alert("Import abgeschlossen", isPresented: Binding(
                get: { importResult != nil },
                set: { if !$0 { importResult = nil } }
            ), presenting: importResult) { _ in
                Button("OK", role: .cancel) { }
            } message: { result in
                if result.pantryItems > 0 {
                    // Two localized lines; `Text +` is deprecated.
                    Text(verbatim: String(localized: "\(result.recipes) Rezepte importiert") + "\n"
                         + String(localized: "\(result.pantryItems) Posten im Vorrat ergänzt"))
                } else {
                    Text("\(result.recipes) Rezepte importiert")
                }
            }
            .alert("Import fehlgeschlagen", isPresented: Binding(
                get: { importErrorMessage != nil },
                set: { if !$0 { importErrorMessage = nil } }
            )) {
                Button("OK", role: .cancel) { importErrorMessage = nil }
            } message: {
                Text(importErrorMessage ?? "")
            }
            .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { windowWidth = $0 }
            .toolbar {
                if !filterInMenu {
                    ToolbarItem(placement: .topBarTrailing) {
                        Menu {
                            filterItems
                        } label: {
                            // Rating, variants, facets and "Fertig bis" — no
                            // longer the rating alone.
                            Label("Rezepte filtern",
                                  systemImage: rating > 0 || !showVariantRecipes || facetFilter.isActive || finishBy != nil ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle")
                        }
                        .accessibilityIdentifier("menu.ratingFilter")
                    }
                }

                // The calculators and the settings: used now and then, so
                // behind one menu rather than taking a tab each. Stable
                // identifiers for the UI tests, which would otherwise depend
                // on the language.
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        if filterInMenu {
                            filterItems
                            Divider()
                        }
                        Button {
                            pushedDestination = .settings
                        } label: {
                            Label("Einstellungen", systemImage: "gearshape.fill")
                        }
                        .accessibilityIdentifier("menu.settings")
                        // Reading and writing backups, as on Android: the
                        // settings hold settings only. "Rezepte exportieren"
                        // with every recipe ticked is the full backup.
                        Button {
                            isImportingRecipes = true
                        } label: {
                            Label("Rezepte importieren", systemImage: "arrow.up.doc")
                        }
                        .accessibilityIdentifier("menu.importRecipes")
                        Button {
                            exportsRecipes = true
                        } label: {
                            Label("Rezepte exportieren", systemImage: "doc.badge.arrow.up")
                        }
                        .accessibilityIdentifier("menu.exportRecipes")
                        Divider()
                        Button {
                            pushedDestination = .pantry
                        } label: {
                            Label("Vorrat", systemImage: "shippingbox")
                        }
                        .accessibilityIdentifier("menu.pantry")
                        Button {
                            pushedDestination = .bakingDay
                        } label: {
                            Label("Backtag planen", systemImage: "calendar.badge.clock")
                        }
                        .accessibilityIdentifier("menu.bakingDay")
                        Divider()
                        Button {
                            pushedDestination = .doughTemperature
                        } label: {
                            Label("Teigtemperatur", systemImage: "thermometer.medium")
                        }
                        .accessibilityIdentifier("menu.doughTemperature")
                        Button {
                            pushedDestination = .flourSubstitution
                        } label: {
                            Label("Mehl ersetzen", systemImage: "arrow.left.arrow.right.circle")
                        }
                        .accessibilityIdentifier("menu.flourSubstitution")
                        Button {
                            pushedDestination = .starterYield
                        } label: {
                            Label("Anstellgut-TA", systemImage: "drop.circle")
                        }
                        .accessibilityIdentifier("menu.starterYield")
                        Button {
                            pushedDestination = .doughWeightFromTin
                        } label: {
                            Label("Teigeinlage", systemImage: "scalemass")
                        }
                        .accessibilityIdentifier("menu.doughWeightFromTin")
                    } label: {
                        Label("Mehr", systemImage: "ellipsis.circle")
                    }
                    .accessibilityIdentifier("menu.more")
                }

                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        pushedDestination = .newRecipe
                    } label: {
                        Label("Neues Rezept anlegen", systemImage: "plus")
                    }
                    .accessibilityIdentifier("menu.newRecipe")
                }
            }
            // On the iPad the search field sits under the title bar, the
            // full width of the list: beside the tab bar it took the room
            // of the buttons, and "+" fell into an overflow menu.
            .searchable(text: $filterBy,
                        placement: searchFieldUnderBar ? .navigationBarDrawer(displayMode: .always) : .automatic,
                        prompt: "Rezept suchen")
            .searchFocused($searchIsFocused)
            .onChange(of: searchFocusRequest) { _, _ in
                searchIsFocused = true
            }
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

    // MARK: - Rating filter

    /// The least rating listed and whether variants are listed; a menu of
    /// its own on the iPhone, part of "Mehr" on the iPad.
    @ViewBuilder private var filterItems: some View {
        // A submenu like the facets below, so the menu stays short.
        Picker("Mindestbewertung", selection: $rating) {
            Text("Alle Bewertungen").tag(0)
            ForEach(1...5, id: \.self) { stars in
                Text("\(stars) Sterne und mehr").tag(stars)
            }
        }
        .pickerStyle(.menu)
        Toggle("Varianten anzeigen", isOn: $showVariantRecipes)
        Divider()
        facetItems
    }

    /// The facets, each a submenu with "Alle" first; a second divider and
    /// "Filter zurücksetzen" once anything is set.
    @ViewBuilder private var facetItems: some View {
        // First, while anything is set: the reset and saving — at the top,
        // because the menu grew past the screen on an iPhone and the reset
        // at its end could only be reached by scrolling the menu.
        if facetFilter.isActive || finishBy != nil {
            Button("Filter zurücksetzen", role: .destructive) {
                facetFilter = RecipeFacetFilter()
                finishBy = nil
            }
            // Offered unless these facets are already a saved collection.
            // A plain button, not a ProGate: a menu flattens its items to
            // title and image, so a nested button loses its action and a
            // sheet inside the menu never shows. Locked, the title says so
            // and the tap opens the paywall from the list.
            if facetFilter.isActive, savedCollections.collection(matching: facetFilter) == nil {
                if Entitlements.shared.isUnlocked(.collections) {
                    Button("Sammlung sichern", systemImage: "bookmark") {
                        collectionName = ""
                        isNamingCollection = true
                    }
                } else {
                    Button("Sammlung sichern (Pro)", systemImage: "bookmark") {
                        listSheet = .paywall(.collections)
                    }
                }
            }
            Divider()
        }
        Picker("Dauer", selection: $facetFilter.duration) {
            Text("Alle").tag(RecipeFacets.Duration?.none)
            Text("Unter 4 Stunden").tag(RecipeFacets.Duration?.some(.short))
            Text("4 bis 12 Stunden").tag(RecipeFacets.Duration?.some(.halfDay))
            Text("Über Nacht").tag(RecipeFacets.Duration?.some(.overnight))
            Text("Mehrtägig").tag(RecipeFacets.Duration?.some(.multiDay))
        }
        .pickerStyle(.menu)
        Picker("Tagesablauf", selection: $facetFilter.dayFlow) {
            Text("Alle").tag(RecipeFacets.DayFlow?.none)
            Text("Abends ansetzen, morgens backen").tag(RecipeFacets.DayFlow?.some(.eveningToMorning))
            Text("Morgens ansetzen, abends backen").tag(RecipeFacets.DayFlow?.some(.sameDay))
            Text("Fertig in 2 Stunden").tag(RecipeFacets.DayFlow?.some(.quick))
        }
        .pickerStyle(.menu)
        Picker("Triebmittel", selection: $facetFilter.leavening) {
            Text("Alle").tag(RecipeFacets.Leavening?.none)
            Text("Reiner Sauerteig").tag(RecipeFacets.Leavening?.some(.sourdough))
            Text("Lievito Madre").tag(RecipeFacets.Leavening?.some(.lievitoMadre))
            Text("Hefe").tag(RecipeFacets.Leavening?.some(.yeast))
            Text("Sauerteig und Hefe").tag(RecipeFacets.Leavening?.some(.mixed))
        }
        .pickerStyle(.menu)
        Picker("Mehl", selection: $facetFilter.grain) {
            Text("Alle").tag(RecipeFacetFilter.Grain?.none)
            Text("Überwiegend Weizen").tag(RecipeFacetFilter.Grain?.some(.wheat))
            Text("Überwiegend Roggen").tag(RecipeFacetFilter.Grain?.some(.rye))
            Text("Überwiegend Dinkel").tag(RecipeFacetFilter.Grain?.some(.spelt))
            Text("Überwiegend Vollkorn").tag(RecipeFacetFilter.Grain?.some(.wholeGrain))
        }
        .pickerStyle(.menu)
        Picker("Teigausbeute", selection: $facetFilter.doughYield) {
            Text("Alle").tag(RecipeFacets.DoughYieldBand?.none)
            Text("Fest, unter TA 165").tag(RecipeFacets.DoughYieldBand?.some(.firm))
            Text("Mittel, TA 165 bis 180").tag(RecipeFacets.DoughYieldBand?.some(.medium))
            Text("Weich, ab TA 180").tag(RecipeFacets.DoughYieldBand?.some(.soft))
        }
        .pickerStyle(.menu)
        Picker("Ausstattung", selection: $facetFilter.equipment) {
            Text("Alle").tag(RecipeFacets.Equipment?.none)
            Text("Backstein").tag(RecipeFacets.Equipment?.some(.bakingStone))
            Text("Kastenform").tag(RecipeFacets.Equipment?.some(.loafTin))
            Text("Gärkörbchen").tag(RecipeFacets.Equipment?.some(.proofingBasket))
            Text("Topf").tag(RecipeFacets.Equipment?.some(.dutchOven))
        }
        .pickerStyle(.menu)
        Picker("Backhistorie", selection: $facetFilter.history) {
            Text("Alle").tag(RecipeFacetFilter.HistoryChoice?.none)
            Text("Nie gebacken").tag(RecipeFacetFilter.HistoryChoice?.some(.never))
            Text("Lange nicht gebacken").tag(RecipeFacetFilter.HistoryChoice?.some(.longAgo))
            Text("Lieblinge").tag(RecipeFacetFilter.HistoryChoice?.some(.favourites))
        }
        .pickerStyle(.menu)
        Toggle("Wenig Arbeit", isOn: $facetFilter.lowWorkOnly)
        // "Fertig bis …" stands before the pantry toggles: the menu is
        // taller than an iPhone screen and scrolls, and as the last entry
        // behind the toggles it sat on the second page, where a tap at its
        // nominal spot only closed the menu.
        if Entitlements.shared.isUnlocked(.collections) {
            Button("Fertig bis …", systemImage: "flag.checkered") {
                finishDraft = finishBy ?? FinishByPlanner.morningFinish(after: Date())
                listSheet = .finishPicker
            }
        } else {
            Button("Fertig bis … (Pro)", systemImage: "flag.checkered") {
                listSheet = .paywall(.collections)
            }
        }
        if Entitlements.shared.isUnlocked(.pantry) {
            Divider()
            Toggle("Aus dem Vorrat", isOn: $facetFilter.pantryOnly)
            Toggle("Vorrat aufbrauchen", isOn: $facetFilter.useUpOnly)
        }
    }

    /// The sheet behind "Fertig bis …": date and time, taken over or lifted.
    private var finishPicker: some View {
        NavigationStack {
            Form {
                DatePicker("Fertig bis", selection: $finishDraft, in: Date()..., displayedComponents: [.date, .hourAndMinute])
                Text("Die Liste zeigt nur Rezepte, die bis dahin fertig werden, und bei jedem, wann Du anfangen musst. Vorheizzeit, Tagesbeginn und Tagesende kommen aus den Einstellungen.")
                    .font(Theme.bodyFont(13))
                    .foregroundColor(Theme.subtitle)
                if finishBy != nil {
                    Button("Aufheben", role: .destructive) {
                        finishBy = nil
                        listSheet = nil
                    }
                }
            }
            .navigationTitle("Fertig bis")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Abbrechen") { listSheet = nil }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Übernehmen") {
                        finishBy = finishDraft
                        listSheet = nil
                    }
                }
            }
        }
        .presentationDetents([.medium])
    }

    /// The preset collections as chips: each sets the facets that make it
    /// and clears the rest; the active one is tinted, a second tap clears.
    private var collectionChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                // The chosen finish, when there is one; a tap changes it.
                // "Für morgen früh" sets a finish for everyone; changing it
                // to another time is part of the Pro collections.
                if let finishBy {
                    ProGate(.collections) {
                        Button {
                            finishDraft = finishBy
                            listSheet = .finishPicker
                        } label: {
                            collectionChipLabel(Text("Fertig bis \(finishText(finishBy))"), systemImage: "flag.checkered", isOn: true)
                        }
                        .buttonStyle(.plain)
                    } label: {
                        collectionChipLabel(Text("Fertig bis \(finishText(finishBy))"), systemImage: "flag.checkered", isOn: true)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("collection.finishBy")
                }
                ForEach(RecipeCollection.allCases.filter { !RecipeCollection.pantryCollections.contains($0) || Entitlements.shared.isUnlocked(.pantry) }) { collection in
                    let isOn = facetFilter == collection.filter
                    Button {
                        if isOn {
                            facetFilter = RecipeFacetFilter()
                            if collection == .morning { finishBy = nil }
                        } else {
                            facetFilter = collection.filter
                            // "Für morgen früh" is a time as well: tomorrow
                            // morning, so the list shows when to start tonight.
                            if collection == .morning { finishBy = FinishByPlanner.morningFinish(after: Date()) }
                        }
                    } label: {
                        collectionChipLabel(Text(collection.title), systemImage: collection.systemImage, isOn: isOn)
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(isOn ? [.isButton, .isSelected] : [.isButton])
                    .accessibilityIdentifier("collection.\(collection.rawValue)")
                }
                // The person's own collections, after the presets; a long
                // press renames or removes one. Pro: locked, the chips of
                // an earlier free period stay stored but out of sight.
                ForEach(Entitlements.shared.isUnlocked(.collections) ? savedCollections.collections : []) { saved in
                    let isOn = facetFilter == saved.filter
                    Button {
                        facetFilter = isOn ? RecipeFacetFilter() : saved.filter
                    } label: {
                        collectionChipLabel(Text(saved.name), systemImage: "bookmark", isOn: isOn)
                    }
                    .buttonStyle(.plain)
                    .contextMenu {
                        Button("Umbenennen", systemImage: "pencil") {
                            collectionName = saved.name
                            renamingCollection = saved
                        }
                        Button("Löschen", systemImage: "trash", role: .destructive) {
                            if isOn { facetFilter = RecipeFacetFilter() }
                            savedCollections.remove(saved.id)
                        }
                    }
                    .accessibilityAddTraits(isOn ? [.isButton, .isSelected] : [.isButton])
                    .accessibilityIdentifier("collection.saved")
                }
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 8)
        }
        .sheet(item: $listSheet) { sheet in
            switch sheet {
            case .finishPicker: finishPicker
            case .paywall(let feature): ProPaywallView(highlighted: feature)
            }
        }
        .alert("Sammlung sichern", isPresented: $isNamingCollection) {
            TextField("Name der Sammlung", text: $collectionName)
            Button("Sichern") {
                savedCollections.add(name: collectionName, filter: facetFilter)
            }
            Button("Abbrechen", role: .cancel) {}
        } message: {
            Text("Die gesetzten Facetten erscheinen unter diesem Namen als Chip über der Liste.")
        }
        .alert("Sammlung umbenennen", isPresented: Binding(
            get: { renamingCollection != nil },
            set: { if !$0 { renamingCollection = nil } }
        )) {
            TextField("Name der Sammlung", text: $collectionName)
            Button("Sichern") {
                if let renaming = renamingCollection {
                    savedCollections.rename(renaming.id, to: collectionName)
                }
            }
            Button("Abbrechen", role: .cancel) {}
        }
    }

    /// The look every collection chip shares.
    private func collectionChipLabel(_ title: Text, systemImage: String, isOn: Bool) -> some View {
        Label { title } icon: { Image(systemName: systemImage) }
            .font(Theme.bodyFont(14))
            .lineLimit(1)
            .foregroundColor(isOn ? .white : Theme.subtitle)
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(Capsule().fill(isOn ? AnyShapeStyle(Theme.accent) : AnyShapeStyle(Theme.card)))
    }

    // MARK: - Filter chips

    /// Three independent toggles, one per recipe source — deliberately not a
    /// single-select picker like the old "Alle/Nur meine" one: a sourdough
    /// baker may want the local recipes and the ones published from this
    /// account but not the whole public database cluttering the list, or any
    /// other combination. A public recipe belongs to exactly one of the two
    /// cloud chips, depending on who published it.
    private var filterChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                filterChip("Lokal", systemImage: "iphone", isOn: $showLocalRecipes)
                filterChip("Von mir veröffentlicht", systemImage: "person.crop.circle", isOn: $showOwnPublishedRecipes)
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
        let row = Row.local(r)
        return ZStack {
            NavigationLink(destination: RecipePageView(recipe: r)) { EmptyView() }
                .opacity(0)
                .accessibilityHidden(true)

            HStack(spacing: 12.0) {
                if !dynamicTypeSize.isAccessibilitySize {
                    Image(uiImage: RecipeThumbnails.shared.image(for: r) ?? UIImage())
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

                    if let origin = r.origin, !origin.isDeleted {
                        Text("Variante von „\(origin.name)“")
                            .font(Theme.bodyFont(12))
                            .foregroundColor(Theme.subtitle)
                            .multilineTextAlignment(.leading)
                    }

                    RecipeTagsView(tags: r.tags)
                        .font(Theme.bodyFont(12))
                        .foregroundColor(Theme.subtitle)
                        .multilineTextAlignment(.leading)

                    startLine(for: row)
                    useUpLine(for: row)
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
            // The database id when the recipe is a copy of a public one, so
            // the UI tests can tell that copy from the public row of the same
            // name (its displayed name may be a translation by then).
            .accessibilityIdentifier("localRecipe.row.\(r.firestoreId.flatMap { $0.isEmpty ? nil : $0 } ?? r.reminderId)")
            .accessibilityLabel(Text("\(r.name), lokales Rezept, Bewertung \(r.rating) von 5 Sternen"))
            .contextMenu {
                // Under "Fertig bis": the plan sheet opens with the start the row names.
                if let outcome = finishOutcome(of: row) {
                    Button {
                        GlobalVariables.dateTimePicker = outcome.start
                        pushedDestination = .planRecipe(id: r.reminderId)
                    } label: {
                        Label { startText(for: outcome) } icon: { Image(systemName: "calendar.badge.clock") }
                    }
                }
            }
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
        let row = Row.cloud(r)
        return ZStack {
            NavigationLink(destination: PublicRecipePageView(recipeFB: r)) { EmptyView() }
                .opacity(0)
                .accessibilityHidden(true)

            HStack(spacing: 12.0) {
                if !dynamicTypeSize.isAccessibilitySize {
                    let uiImage = PublicRecipeImages.shared.images[r.id ?? ""] ?? UIImage(systemName: "photo") ?? UIImage()
                    Image(uiImage: uiImage)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 50, height: 50, alignment: .center)
                        .clipped()
                        .cornerRadius(8)
                }

                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 5) {
                        // The same symbols as the chips, so a row shows
                        // which chip it answers to.
                        Image(systemName: isOwnPublished(r) ? "person.crop.circle" : "globe")
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

                    startLine(for: row)
                    useUpLine(for: row)
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
            .accessibilityLabel(isOwnPublished(r)
                                ? Text("\(r.name), von Dir veröffentlicht, Bewertung \(r.rating) von 5 Sternen")
                                : Text("\(r.name), Bewertung \(r.rating) von 5 Sternen"))
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            if modelFB.isAdmin {
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
