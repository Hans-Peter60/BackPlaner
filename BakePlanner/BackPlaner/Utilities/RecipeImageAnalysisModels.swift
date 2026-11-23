import BakePlannerCore
import Foundation
import UIKit

// The results the recipe import hands back and the pieces of a recognized page
// that RecipeImageAnalysisAgent passes to the template readers
// (TwoColumnRecipeParser, GeneralRecipeParser).

/// A way of reading a recipe from photographed pages. The import tries all of
/// them and keeps the best result, so a new template only needs a new case here
/// and a reader for it.
enum RecipeLayout: String, CaseIterable, Sendable {
    /// Two columns with a planning example and numbered work steps, as some
    /// baking blogs print them.
    case specialTwoColumn
    /// Cookbooks, magazines, printouts: headings, ingredient blocks and prose.
    case general

    var title: LocalizedStringResource {
        switch self {
        case .specialTwoColumn: "Spezial (zweispaltig)"
        case .general: "Allgemeine Rezeptvorlage"
        }
    }
}

enum RecipeAnalysisSource: Sendable {
    case localRules
    case onDeviceAI
    case cloudAI

    var title: LocalizedStringResource {
        switch self {
        case .localRules: "Lokale Analyse"
        case .onDeviceAI: "Lokale KI-Analyse"
        case .cloudAI: "Geschützte KI-Analyse"
        }
    }
}

/// A recognized line together with where it was printed, so the import can put
/// it back on the page for the user to point at.
struct RecipeTextRegion: Identifiable, Sendable {
    let id = UUID()
    /// Index into the images that were analysed.
    let page: Int
    let text: String
    /// Vision's normalized rectangle: the origin is the bottom-left corner and
    /// both axes run 0…1, so it has to be flipped for SwiftUI.
    let boundingBox: CGRect
}

struct RecipeImageAnalysisResult {
    let recipe: RecipeFB
    let recognizedText: String
    let recipeImage: UIImage?
    /// Values that the recipe contradicts, for example a dough weight that does
    /// not match the sum of the recognized ingredients.
    let warnings: [String]
    /// The layout this result was read with.
    let layout: RecipeLayout
    /// The headings the page offers as a name, best guess first. A page carries
    /// logos, print headers and column captions that read like a title, so the
    /// choice is offered rather than only guessed.
    let titleOptions: [RecipeTextRegion]
    /// How the images were converted into recipe data. Cloud and on-device AI
    /// both fall back to the rule-based reader when they are unavailable.
    let analysisSource: RecipeAnalysisSource

    init(
        recipe: RecipeFB,
        recognizedText: String,
        recipeImage: UIImage? = nil,
        warnings: [String] = [],
        layout: RecipeLayout = .general,
        titleOptions: [RecipeTextRegion] = [],
        analysisSource: RecipeAnalysisSource = .localRules
    ) {
        // Every import route ends here, so this is where "tsp", "cups" or
        // "c. à s." become the units the app calculates with.
        UnitLocalizer.normalizeUnits(in: recipe)
        self.recipe = recipe
        self.recognizedText = recognizedText
        self.recipeImage = recipeImage
        self.warnings = warnings
        self.layout = layout
        self.titleOptions = titleOptions
        self.analysisSource = analysisSource
    }

    /// The same result with one more warning, e.g. why the cloud stayed out
    /// of the analysis.
    func addingWarning(_ warning: String) -> RecipeImageAnalysisResult {
        RecipeImageAnalysisResult(
            recipe: recipe,
            recognizedText: recognizedText,
            recipeImage: recipeImage,
            warnings: warnings + [warning],
            layout: layout,
            titleOptions: titleOptions,
            analysisSource: analysisSource
        )
    }

    var componentCount: Int { recipe.components.count }
    var ingredientCount: Int {
        recipe.components.reduce(0) { $0 + $1.ingredients.count }
    }
    var instructionCount: Int { recipe.instructions.count }
}
