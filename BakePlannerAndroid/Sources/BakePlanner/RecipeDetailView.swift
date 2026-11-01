import BakePlannerCore
import SkipKit
import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

/// One recipe: its picture, the dough yield, the components with their
/// ingredients, the total ingredients and the steps — at the amount chosen
/// here. The lines come from RecipePrintData, the same preparation the iOS
/// app prints from, so units and fractions read alike on both platforms.
struct RecipeDetailView: View {
    let model: AppModel
    let recipeID: String
    @State var recipe: StoredRecipe?
    /// The factor on the recipe as stored: 1 is the recipe, 2 twice as much.
    @State var scale = 1.0
    @State var isEditing = false
    @State var picksImage = false
    @State var recipeToExport: [String]?
    @State var pickedImageURL: URL?
    @State var pickedImageName: String?
    @State var pickedImageType: String?
    @State var addsToShoppingList = false
    @State var plans = false
    @Environment(\.colorScheme) var colorScheme

    var body: some View {
        ZStack {
            LinearGradient(colors: [Palette.backgroundTop(colorScheme), Palette.backgroundBottom(colorScheme)],
                           startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()

            if let recipe {
                content(of: recipe)
            } else {
                ProgressView()
            }
        }
        .navigationTitle(recipe?.content.name ?? "")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Bearbeiten") {
                    isEditing = true
                }
                .disabled(recipe == nil)
            }
            ToolbarItem(placement: .primaryAction) {
                Button {
                    recipeToExport = [recipeID]
                } label: {
                    Label("Rezept sichern", systemImage: "square.and.arrow.up")
                }
                .disabled(recipe == nil)
            }
        }
        .recipeFileExporter(model: model, recipeIDs: $recipeToExport, fileName: recipe?.content.name ?? "Rezept",
                            includesBakeHistory: false)
        .appSheet(isPresented: $isEditing) {
            if let recipe {
                NavigationStack {
                    RecipeEditor(original: recipe) { _, content in
                        var edited = recipe
                        edited.content = content
                        if model.save(edited) {
                            self.recipe = model.recipe(id: recipeID)
                        }
                    }
                }
            }
        }
        .appSheet(isPresented: $plans) {
            if let recipe {
                NavigationStack {
                    PlanView(model: model, recipe: recipe, scale: scale)
                }
            }
        }
        .appSheet(isPresented: $addsToShoppingList) {
            NavigationStack {
                AddToShoppingListView(model: model, source: .own(recipeID), scale: scale)
            }
        }
        .withDocumentPicker(isPresented: $picksImage,
                            allowedContentTypes: [.image],
                            selectedDocumentURL: $pickedImageURL,
                            selectedFilename: $pickedImageName,
                            selectedFileMimeType: $pickedImageType)
        .onChange(of: pickedImageURL) { _, url in
            guard let url else { return }
            pickedImageURL = nil
            // A file that is no picture leaves the recipe's picture as it is.
            guard let data = Self.pictureData(at: url) else { return }
            changeImage(to: data)
        }
        .task {
            recipe = model.recipe(id: recipeID)
        }
    }

    private func content(of recipe: StoredRecipe) -> some View {
        let page = RecipePrintData(data: recipe.content, scale: scale)
        return ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                RecipePicture(data: recipe.content.image)

                HStack(spacing: 16) {
                    Button(recipe.content.image == nil ? LocalizedStringKey("Bild hinzufügen") : LocalizedStringKey("Bild ändern")) {
                        picksImage = true
                    }
                    if recipe.content.image != nil {
                        Button("Bild entfernen", role: .destructive) {
                            changeImage(to: nil)
                        }
                    }
                }
                .font(.subheadline)

                if !page.summary.isEmpty {
                    Text(verbatim: page.summary)
                }
                RecipeLinkRow(urlLink: recipe.content.urlLink)

                VStack(alignment: .leading, spacing: 6) {
                    Stepper(value: $scale, in: 0.5...10, step: 0.5) {
                        HStack {
                            Text("Menge")
                            Text(verbatim: "× " + Self.factorText(scale))
                                .bold()
                        }
                    }
                    Text("Gesamtgewicht: \(String(page.totalWeight)) g")
                    if !page.prepTime.isEmpty {
                        Text("Bearbeitungsdauer: \(page.prepTime)")
                    }
                    DoughYieldRow(content: recipe.content)
                    if recipe.content.recurrenceIntervalDays > 0 {
                        Self.nextRhythmText(date: model.nextRhythmStart(of: recipe),
                                            isStarter: StarterRecipe.isStarterFeeding(recipe.content))
                            .foregroundStyle(Palette.accent(colorScheme))
                    }
                }
                .font(.subheadline)

                // At the amount chosen above, as on the iPhone.
                Button {
                    plans = true
                } label: {
                    Label("Planen", systemImage: "calendar")
                }
                .buttonStyle(.bordered)
                .tint(Palette.accent(colorScheme))

                Button {
                    addsToShoppingList = true
                } label: {
                    Label("Rezept zur Einkaufsliste hinzufügen", systemImage: "cart")
                }
                .buttonStyle(.bordered)
                .tint(Palette.accent(colorScheme))

                RecipeLineSections(page: page)

                // A starter is fed, not baked: it keeps a feeding diary and
                // no bake history; every other recipe the other way round.
                if StarterRecipe.isStarterFeeding(recipe.content) {
                    StarterFeedingSection(model: model, recipeID: recipeID,
                                          ratio: StarterFeedingRatio.ratio(for: recipe.content))
                } else {
                    RecipeBakeHistorySection(model: model, recipeID: recipeID)
                }
            }
            .padding()
        }
    }

    private func changeImage(to data: Data?) {
        if model.setImage(data, forRecipe: recipeID) {
            recipe = model.recipe(id: recipeID)
        }
    }

    /// The picked picture as JPEG, the way the iOS app keeps pictures; nil
    /// when the file is no picture.
    static func pictureData(at url: URL) -> Data? {
        #if !os(Android)
        // On iOS the picked file is only readable while its access lasts;
        // on Android the picker hands over a copy in the app's cache.
        let accessing = url.startAccessingSecurityScopedResource()
        defer { if accessing { url.stopAccessingSecurityScopedResource() } }
        #endif
        guard let data = try? Data(contentsOf: url) else { return nil }
        // JPEG, and no larger than looks sharp on screen (PhotoShrinker).
        return PhotoShrinker.pickedPhoto(data)
    }

    /// "Nächste Fütterung: Mi., 4.11. 08:00", as on the iPhone; before the
    /// first bake or feeding, when that will be.
    static func nextRhythmText(date: Date?, isStarter: Bool) -> Text {
        switch (isStarter, date) {
        case (true, let date?):
            return Text("Nächste Fütterung: \(PlanText.day(date)) \(PlanText.time(date))")
        case (true, nil):
            return Text("Nächste Fütterung: nach der ersten Fütterung")
        case (false, let date?):
            return Text("Nächster Backtermin: \(PlanText.day(date)) \(PlanText.time(date))")
        case (false, nil):
            return Text("Nächster Backtermin: nach dem ersten Backen")
        }
    }

    /// "1", "1,5" in the device's language.
    static func factorText(_ scale: Double) -> String {
        scale.formatted(.number.precision(.fractionLength(0...1)))
    }
}
