import BakePlannerCore
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
        }
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
        .task {
            recipe = model.recipe(id: recipeID)
        }
    }

    private func content(of recipe: StoredRecipe) -> some View {
        let page = RecipePrintData(data: recipe.content, scale: scale)
        return ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                picture(of: recipe)

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
