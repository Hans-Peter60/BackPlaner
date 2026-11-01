import BakePlannerCore
import SkipKit
import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

struct ContentView: View {
    @State var model = AppModel()
    /// The device's language (or the one chosen for the app in Android's
    /// settings). The app speaks it when BakePlanner has it, else English
    /// (AppSettings.appLocale): all views get that locale, and so does the
    /// package — Swift's Locale.current does not follow the device on
    /// Android — for generated plan steps, plan hints and dates.
    @Environment(\.locale) var locale
    @Environment(\.scenePhase) var scenePhase

    var body: some View {
        TabView {
            NavigationStack {
                RecipeListView(model: model)
            }
            .tabItem {
                Label("Rezepte", systemImage: "list.bullet")
            }

            NavigationStack {
                ShoppingListsView(model: model)
            }
            .tabItem {
                Label("Einkaufslisten", systemImage: "cart")
            }

            NavigationStack {
                BakeHistoryView(model: model)
            }
            .tabItem {
                // Skip has no clock symbol (it drew a warning triangle).
                Label("Backhistorie", systemImage: "checkmark.circle")
            }

            NavigationStack {
                PlanTimelineView(model: model)
            }
            .tabItem {
                Label("Zeitleiste", systemImage: "calendar")
            }
        }
        // Skip looks every text up in the environment's locale.
        .environment(\.locale, AppSettings.appLocale(forDevice: locale))
        .compactTextFields()
        // Coming to the foreground plans what is due on a rhythm, as on the
        // iPhone.
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                Task { await model.scheduleDueOccurrences() }
            }
        }
        .onChange(of: locale) { _, newLocale in
            let appLocale = AppSettings.appLocale(forDevice: newLocale)
            AppSettings.systemLocale = { appLocale }
            // Public recipes show the translation of the app's language.
            Task { await model.loadPublicRecipes() }
        }
        .task {
            let appLocale = AppSettings.appLocale(forDevice: locale)
            AppSettings.systemLocale = { appLocale }
            model.load()
            model.loadShoppingLists()
            model.loadBakeHistory()
            model.loadScheduledSteps()
            await model.scheduleDueOccurrences()
            await model.loadPublicRecipes()
        }
    }
}

/// The user's recipes by name, searchable, with the import of a backup file.
struct RecipeListView: View {
    let model: AppModel
    @State var searchText = ""
    /// Whether the search looks at the tags instead of the names, as the
    /// iPhone's search scopes "Name"/"Tags" do. SkipUI has no search scopes,
    /// so the choice sits in a row above the list.
    @State var searchesTags = false
    /// Only recipes rated this or better are listed; 0 lists all.
    @State var minimumRating = 0
    @State var showsPicker = false
    @State var pickedURL: URL?
    @State var pickedName: String?
    @State var pickedType: String?
    /// The recipe waiting for the user to confirm its removal. Kept apart
    /// from the dialog's visibility: closing the dialog — which Android does
    /// before running the chosen button — must not forget which recipe.
    @State var recipeToDelete: StoredRecipe?
    @State var confirmsDeletion = false
    @State var createsRecipe = false
    @State var importsFromWeb = false
    @State var importsFromPhotos = false
    /// A recipe read from a web page or from photos, waiting for the editor. Kept apart
    /// from the editor's visibility, as the dialogs' data is.
    @State var importedRecipe: RecipeExportData?
    @State var importNotice: Text?
    @State var editsImportedRecipe = false
    @State var recipesToExport: [String]?
    @State var showsSettings = false
    /// The calculator to show; kept apart from the sheet's visibility, as
    /// the dialogs' data is.
    @State var calculator = Calculator.doughTemperature
    @State var showsCalculator = false
    @Environment(\.colorScheme) var colorScheme

    var body: some View {
        ZStack {
            // Not ignoring the safe area here: the search field sits in the
            // area above the list, and a gradient reaching into it covered
            // the field (taps still went through, so one typed unseen).
            LinearGradient(colors: [Palette.backgroundTop(colorScheme), Palette.backgroundBottom(colorScheme)],
                           startPoint: .top, endPoint: .bottom)

            if let loadError = model.loadError {
                VStack(spacing: 12) {
                    Text("Die Rezepte konnten nicht geladen werden.")
                    Text(verbatim: loadError)
                        .font(.caption)
                }
                .padding()
            } else if model.recipes.isEmpty && model.publicRecipes.isEmpty {
                VStack(spacing: 12) {
                    Text("Noch keine Rezepte")
                        .font(.title2)
                        .foregroundStyle(Palette.accent(colorScheme))
                    Text("Importiere eine Sicherungsdatei, die Du auf dem iPhone in den Einstellungen exportiert hast.")
                        .multilineTextAlignment(.center)
                    Button("Importieren") {
                        showsPicker = true
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(Palette.accent(colorScheme))
                }
                .padding()
            } else {
                List {
                    if model.showsPublicRecipes, model.publicRecipesError != nil {
                        Text("Die öffentlichen Rezepte konnten nicht geladen werden. Zum erneuten Versuch die Liste herunterziehen.")
                            .font(.caption)
                            .foregroundStyle(Color.red)
                    }
                    filterRow
                    let rows = filteredRows
                    if rows.isEmpty {
                        Text("Keine passenden Rezepte")
                            .foregroundStyle(.secondary)
                    }
                    ForEach(rows) { row in
                        NavigationLink {
                            RecipeListDestination(model: model, row: row)
                        } label: {
                            RecipeListLabel(model: model, row: row)
                        }
                        // Only the own recipes can be deleted here.
                        .deleteDisabled(!row.isLocal)
                    }
                    .onDelete { offsets in
                        if let index = offsets.first, case .local(let recipe) = rows[index] {
                            recipeToDelete = recipe
                        } else {
                            recipeToDelete = nil
                        }
                        confirmsDeletion = recipeToDelete != nil
                    }
                }
                .scrollContentBackground(.hidden)
                .searchable(text: $searchText, prompt: Text("Rezept suchen"))
                .refreshable {
                    model.load()
                    await model.loadPublicRecipes()
                }
            }
        }
        .navigationTitle("Rezepte")
        .toolbar {
            // Android shows two items of the bar and drops further ones, so
            // reading and writing backups and the settings share one menu.
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Button("Einstellungen") {
                        showsSettings = true
                    }
                    Button("Importieren") {
                        showsPicker = true
                    }
                    Button("Alle eigenen Rezepte sichern") {
                        recipesToExport = model.recipes.map(\.id)
                    }
                    .disabled(model.recipes.isEmpty)
                    // The iPhone's three calculators from its main menu.
                    Button("Teigtemperatur") {
                        openCalculator(.doughTemperature)
                    }
                    Button("Mehl ersetzen") {
                        openCalculator(.flourSubstitution)
                    }
                    Button("Anstellgut-TA") {
                        openCalculator(.starterYield)
                    }
                } label: {
                    Text("Mehr")
                }
            }
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Button("Von Hand") {
                        createsRecipe = true
                    }
                    Button("Von einer Internetseite") {
                        importsFromWeb = true
                    }
                    Button("Aus Fotos") {
                        importsFromPhotos = true
                    }
                } label: {
                    Label("Neues Rezept", systemImage: "plus")
                }
            }
        }
        .recipeFileExporter(model: model, recipeIDs: $recipesToExport, fileName: AppModel.backupFileName,
                            includesBakeHistory: true)
        .appSheet(isPresented: $showsSettings) {
            NavigationStack {
                SettingsView(model: model)
            }
        }
        .appSheet(isPresented: $showsCalculator) {
            NavigationStack {
                CalculatorSheet(calculator: calculator)
            }
        }
        .appSheet(isPresented: $importsFromWeb) {
            NavigationStack {
                WebRecipeImportView(model: model, onImport: receiveImport)
            }
        }
        .appSheet(isPresented: $importsFromPhotos) {
            NavigationStack {
                PhotoRecipeImportView(model: model, onImport: receiveImport)
            }
        }
        .appSheet(isPresented: $editsImportedRecipe) {
            if let importedRecipe {
                NavigationStack {
                    RecipeEditor(original: nil, template: importedRecipe, notice: importNotice) { _, content in
                        model.add(content)
                    }
                }
            }
        }
        .appSheet(isPresented: $createsRecipe) {
            NavigationStack {
                RecipeEditor(original: nil) { _, content in
                    model.add(content)
                }
            }
        }
        .withDocumentPicker(isPresented: $showsPicker,
                            allowedContentTypes: [.json],
                            selectedDocumentURL: $pickedURL,
                            selectedFilename: $pickedName,
                            selectedFileMimeType: $pickedType)
        .onChange(of: pickedURL) { _, url in
            guard let url else { return }
            pickedURL = nil
            model.importFile(at: url)
        }
        .alert("Rezept löschen?", isPresented: $confirmsDeletion) {
            Button("Löschen", role: .destructive) {
                if let recipe = recipeToDelete {
                    model.delete(id: recipe.id)
                }
                recipeToDelete = nil
            }
            Button("Abbrechen", role: .cancel) {
                recipeToDelete = nil
            }
        } message: {
            Text(verbatim: recipeToDelete?.content.name ?? "")
        }
        .alert(importTitle, isPresented: showsImportOutcome) {
            Button {
                model.importOutcome = nil
            } label: {
                Text(verbatim: "OK")
            }
        } message: {
            if case .failed(let reason) = model.importOutcome {
                Text(verbatim: reason)
            }
        }
    }

    private func openCalculator(_ which: Calculator) {
        calculator = which
        showsCalculator = true
    }

    /// Takes an imported recipe from the web or photo import and opens the
    /// editor with it once the import's sheet has gone.
    private func receiveImport(_ content: RecipeExportData, _ notice: Text?) {
        importedRecipe = content
        importNotice = notice
        Task {
            try? await Task.sleep(for: .milliseconds(400))
            editsImportedRecipe = true
        }
    }

    /// Where the search looks, and the least rating listed — the iPhone's
    /// search scopes and its filter menu, as one row above the recipes.
    private var filterRow: some View {
        HStack(spacing: 12) {
            Picker("Suchen in", selection: $searchesTags) {
                Text("Name").tag(false)
                Text("Tags").tag(true)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            Menu {
                Button("Alle Bewertungen") {
                    minimumRating = 0
                }
                // An array, not 1...5: Skip's ForEach over a ClosedRange hands
                // out range indices, and casting them to Int crashed the app.
                ForEach([1, 2, 3, 4, 5], id: \.self) { stars in
                    Button {
                        minimumRating = stars
                    } label: {
                        Text("\(stars) Sterne und mehr")
                    }
                }
            } label: {
                // Skip draws "star.fill" but not the outlined "star" (it would
                // show a warning triangle), nor the iPhone's filter symbol; the
                // colour says whether a filter is on.
                HStack(spacing: 2) {
                    Image(systemName: "star.fill")
                    if minimumRating > 0 {
                        Text(verbatim: "\(minimumRating)+")
                    }
                }
                .foregroundStyle(minimumRating > 0 ? Palette.accent(colorScheme) : Color.secondary)
                .accessibilityLabel(Text("Nach Bewertung filtern"))
            }
        }
    }

    /// One line of the list: an own recipe or a public one.
    enum Row: Identifiable {
        case local(StoredRecipe)
        case shared(RecipeFB)

        var id: String {
            switch self {
            case .local(let recipe): return "local:" + recipe.id
            case .shared(let recipe): return "public:" + (recipe.id ?? "")
            }
        }

        var name: String {
            switch self {
            case .local(let recipe): return recipe.content.name
            case .shared(let recipe): return recipe.name
            }
        }

        var tags: [String] {
            switch self {
            case .local(let recipe): return recipe.content.tags
            case .shared(let recipe): return recipe.tags
            }
        }

        var rating: Int {
            switch self {
            case .local(let recipe): return recipe.content.rating
            case .shared(let recipe): return recipe.rating
            }
        }

        var isLocal: Bool {
            if case .local = self { return true }
            return false
        }
    }

    /// Own and public recipes together, as the settings choose, by name —
    /// as on the iPhone.
    private var filteredRows: [Row] {
        var rows: [Row] = []
        if model.showsLocalRecipes {
            rows += model.recipes.map { Row.local($0) }
        }
        if model.showsPublicRecipes {
            rows += model.visiblePublicRecipes.map { Row.shared($0) }
        }
        if minimumRating > 0 {
            rows = rows.filter { $0.rating >= minimumRating }
        }
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !query.isEmpty {
            if searchesTags {
                rows = rows.filter { row in row.tags.contains { $0.localizedCaseInsensitiveContains(query) } }
            } else {
                rows = rows.filter { $0.name.localizedCaseInsensitiveContains(query) }
            }
        }
        return rows.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    private var showsImportOutcome: Binding<Bool> {
        Binding(get: { model.importOutcome != nil },
                set: { if !$0 { model.importOutcome = nil } })
    }

    private var importTitle: Text {
        switch model.importOutcome {
        case .imported(let count): return Text("Rezepte importiert: \(count)")
        case .failed, nil: return Text("Import fehlgeschlagen")
        }
    }
}

/// One recipe in the list: its picture small, name, rating, and its tags.
struct RecipeRow: View {
    let model: AppModel
    let recipe: StoredRecipe
    @State var thumbnail: Data?

    var body: some View {
        HStack(spacing: 12) {
            RowThumbnail(data: thumbnail)
            VStack(alignment: .leading, spacing: 4) {
                Text(verbatim: recipe.content.name)
                    .font(.headline)
                HStack(spacing: 8) {
                    if recipe.content.rating > 0 {
                        Text(verbatim: String(repeating: "★", count: min(recipe.content.rating, 5)))
                            .foregroundStyle(.orange)
                    }
                    if !recipe.content.tags.isEmpty {
                        Text(verbatim: recipe.content.tags.joined(separator: ", "))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .task(id: recipe.id) {
            thumbnail = model.thumbnail(forRecipe: recipe.id)
        }
    }
}

/// The small picture at the start of a list row, or a plain square
/// without one, so the names line up.
struct RowThumbnail: View {
    let data: Data?

    var body: some View {
        Group {
            #if canImport(UIKit) || os(Android)
            if let data, let image = UIImage(data: data) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                Color.gray.opacity(0.15)
            }
            #else
            Color.gray.opacity(0.15)
            #endif
        }
        .frame(width: 48, height: 48)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

/// The page a list entry opens. Its own view type, so the link's page is a
/// single view: Skip opened an own recipe as an empty page when the link's
/// page switched between the two kinds itself, and lost the back button
/// when the list entry switched between two links.
struct RecipeListDestination: View {
    let model: AppModel
    let row: RecipeListView.Row

    var body: some View {
        switch row {
        case .local(let recipe):
            RecipeDetailView(model: model, recipeID: recipe.id)
        case .shared(let recipe):
            PublicRecipeDetailView(model: model, recipe: recipe)
        }
    }
}

/// A list entry's line, for either kind of recipe.
struct RecipeListLabel: View {
    let model: AppModel
    let row: RecipeListView.Row

    var body: some View {
        switch row {
        case .local(let recipe):
            RecipeRow(model: model, recipe: recipe)
        case .shared(let recipe):
            PublicRecipeRow(model: model, recipe: recipe)
        }
    }
}

/// One public recipe in the list: its picture small once it was read for
/// the detail page, name, tags, and that it is public.
struct PublicRecipeRow: View {
    let model: AppModel
    let recipe: RecipeFB

    var body: some View {
        HStack(spacing: 12) {
            RowThumbnail(data: model.publicRecipeImages[recipe.id ?? ""].flatMap { PhotoShrinker.thumbnail($0) })
            VStack(alignment: .leading, spacing: 4) {
                Text(verbatim: recipe.name)
                    .font(.headline)
                HStack(spacing: 8) {
                    Text("Öffentlich")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if !recipe.tags.isEmpty {
                        Text(verbatim: recipe.tags.joined(separator: ", "))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }
}

/// The colours of BakePlanner on iOS (Theme.swift in the iOS app): warm
/// flour and crust tones, darker at night.
enum Palette {
    static func backgroundTop(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? Color(red: 0.16, green: 0.12, blue: 0.09) : Color(red: 0.98, green: 0.93, blue: 0.82)
    }

    static func backgroundBottom(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? Color(red: 0.09, green: 0.07, blue: 0.05) : Color(red: 0.93, green: 0.80, blue: 0.62)
    }

    static func accent(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? Color(red: 0.61, green: 0.41, blue: 0.22) : Color(red: 0.62, green: 0.41, blue: 0.21)
    }
}
