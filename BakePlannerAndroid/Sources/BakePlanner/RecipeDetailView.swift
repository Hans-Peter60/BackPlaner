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
        .sheet(isPresented: $isEditing) {
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
        .sheet(isPresented: $plans) {
            if let recipe {
                NavigationStack {
                    PlanView(model: model, recipe: recipe, scale: scale)
                }
            }
        }
        .sheet(isPresented: $addsToShoppingList) {
            NavigationStack {
                AddToShoppingListView(model: model, recipeID: recipeID, scale: scale)
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
                picture(of: recipe)

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
                    if let yield = Self.yieldText(of: recipe.content) {
                        Text(yield)
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

                section("Komponenten") {
                    ForEach(Array(page.components.enumerated()), id: \.offset) { _, component in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(verbatim: component.name)
                                .font(.headline)
                            ForEach(Array(component.lines.enumerated()), id: \.offset) { _, line in
                                Text(verbatim: line)
                            }
                        }
                    }
                }

                section("Gesamtzutaten:") {
                    ForEach(Array(page.totalLines.enumerated()), id: \.offset) { _, line in
                        Text(verbatim: line)
                    }
                }

                section("Verarbeitungsschritte") {
                    ForEach(Array(page.steps.enumerated()), id: \.offset) { _, step in
                        HStack(alignment: .top, spacing: 8) {
                            Text(verbatim: step.number)
                                .bold()
                                .frame(width: 36, alignment: .leading)
                            Text(verbatim: step.text)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            Text(verbatim: step.duration)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

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

    @ViewBuilder
    private func picture(of recipe: StoredRecipe) -> some View {
        #if canImport(UIKit) || os(Android)
        if let data = recipe.content.image, let image = UIImage(data: data) {
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
                .frame(maxWidth: .infinity)
                .frame(height: 220)
                .clipShape(RoundedRectangle(cornerRadius: 12))
        }
        #endif
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
        #if canImport(UIKit) || os(Android)
        // Whatever the camera wrote (HEIC, PNG, JPEG) becomes JPEG.
        guard let image = UIImage(data: data) else { return nil }
        return image.jpegData(compressionQuality: 0.8) ?? data
        #else
        return data
        #endif
    }

    private func section<Content: View>(_ title: LocalizedStringKey,
                                        @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.title3)
                .bold()
                .foregroundStyle(Palette.accent(colorScheme))
            content()
        }
    }

    /// "1", "1,5" in the device's language.
    static func factorText(_ scale: Double) -> String {
        scale.formatted(.number.precision(.fractionLength(0...1)))
    }

    /// "TA 175 · Hydration 75 %", or nil when the recipe names no flour.
    static func yieldText(of content: RecipeExportData) -> LocalizedStringKey? {
        guard let result = DoughComposition.compute(DoughComposition.components(of: content)),
              result.flour > 0 else { return nil }
        let yield = Int(result.doughYield.rounded())
        let hydration = result.hydration.formatted(.number.precision(.fractionLength(0))) + " %"
        return "TA \(yield) · Hydration \(hydration)"
    }
}
