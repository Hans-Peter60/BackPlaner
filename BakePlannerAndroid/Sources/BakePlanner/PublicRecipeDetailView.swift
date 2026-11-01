import BakePlannerCore
import SwiftUI

/// A public recipe, read only: its picture, summary, amount, dough yield,
/// components, total ingredients and steps, as the own recipes show them.
/// Components, steps and picture are read when the recipe is first opened.
struct PublicRecipeDetailView: View {
    let model: AppModel
    let recipe: RecipeFB
    @State var content: RecipeExportData?
    @State var loadError: String?
    /// The factor on the recipe as published: 1 is the recipe, 2 twice as much.
    @State var scale = 1.0
    @Environment(\.colorScheme) var colorScheme

    var body: some View {
        ZStack {
            LinearGradient(colors: [Palette.backgroundTop(colorScheme), Palette.backgroundBottom(colorScheme)],
                           startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()

            if let content {
                page(of: content)
            } else if let loadError {
                VStack(spacing: 12) {
                    Text("Das Rezept konnte nicht geladen werden.")
                    Text(verbatim: loadError)
                        .font(.caption)
                }
                .padding()
            } else {
                ProgressView()
            }
        }
        .navigationTitle(recipe.name)
        .task {
            do {
                content = try await model.publicRecipeContent(recipe)
            } catch {
                logger.error("could not read public recipe \(recipe.id ?? ""): \(error)")
                loadError = error.localizedDescription
            }
        }
    }

    private func page(of content: RecipeExportData) -> some View {
        let page = RecipePrintData(data: content, scale: scale)
        return ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                RecipePicture(data: content.image)

                // Skip has no globe symbol; the word says it.
                Text("Öffentlich")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if !page.summary.isEmpty {
                    Text(verbatim: page.summary)
                }

                VStack(alignment: .leading, spacing: 6) {
                    Stepper(value: $scale, in: 0.5...10, step: 0.5) {
                        HStack {
                            Text("Menge")
                            Text(verbatim: "× " + RecipeDetailView.factorText(scale))
                                .bold()
                        }
                    }
                    Text("Gesamtgewicht: \(String(page.totalWeight)) g")
                    if !page.prepTime.isEmpty {
                        Text("Bearbeitungsdauer: \(page.prepTime)")
                    }
                    if let yield = RecipeDetailView.yieldText(of: content) {
                        Text(yield)
                    }
                }
                .font(.subheadline)

                RecipeLineSections(page: page)
            }
            .padding()
        }
    }
}
