import BakePlannerCore
import SkipKit
import SwiftUI

struct ContentView: View {
    @State var model = AppModel()

    var body: some View {
        NavigationStack {
            RecipeListView(model: model)
        }
        .task {
            model.load()
        }
    }
}

/// The user's recipes by name, searchable, with the import of a backup file.
struct RecipeListView: View {
    let model: AppModel
    @State var searchText = ""
    @State var showsPicker = false
    @State var pickedURL: URL?
    @State var pickedName: String?
    @State var pickedType: String?
    @Environment(\.colorScheme) var colorScheme

    var body: some View {
        ZStack {
            LinearGradient(colors: [Palette.backgroundTop(colorScheme), Palette.backgroundBottom(colorScheme)],
                           startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()

            if let loadError = model.loadError {
                VStack(spacing: 12) {
                    Text("Die Rezepte konnten nicht geladen werden.")
                    Text(verbatim: loadError)
                        .font(.caption)
                }
                .padding()
            } else if model.recipes.isEmpty {
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
                    ForEach(filteredRecipes, id: \.id) { recipe in
                        NavigationLink {
                            RecipeDetailView(model: model, recipeID: recipe.id)
                        } label: {
                            RecipeRow(recipe: recipe)
                        }
                    }
                }
                .scrollContentBackground(.hidden)
                .searchable(text: $searchText)
            }
        }
        .navigationTitle("Rezepte")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Importieren") {
                    showsPicker = true
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
        .alert(importTitle, isPresented: showsImportOutcome) {
            Button(role: .cancel) {
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

    private var filteredRecipes: [StoredRecipe] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return model.recipes }
        return model.recipes.filter { $0.content.name.localizedCaseInsensitiveContains(query) }
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

/// One recipe in the list: name, rating, and its tags.
struct RecipeRow: View {
    let recipe: StoredRecipe

    var body: some View {
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
