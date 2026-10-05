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
        self.recipe = recipe
        self.recognizedText = recognizedText
        self.recipeImage = recipeImage
        self.warnings = warnings
        self.layout = layout
        self.titleOptions = titleOptions
        self.analysisSource = analysisSource
    }

    var componentCount: Int { recipe.components.count }
    var ingredientCount: Int {
        recipe.components.reduce(0) { $0 + $1.ingredients.count }
    }
    var instructionCount: Int { recipe.instructions.count }
}

enum RecipeImageAnalysisError: LocalizedError {
    case invalidImage
    case noTextRecognized
    case unsupportedLayout
    case insufficientRecipeData

    var errorDescription: String? {
        switch self {
        case .invalidImage:
            return String(localized: "Mindestens eines der ausgewählten Bilder konnte nicht gelesen werden.", bundle: AppSettings.localizationBundle)
        case .noTextRecognized:
            return String(localized: "Auf den Bildern wurde kein ausreichend lesbarer Text erkannt.", bundle: AppSettings.localizationBundle)
        case .unsupportedLayout:
            return String(localized: "Das erwartete zweispaltige Rezeptlayout mit Planungsbeispiel wurde nicht erkannt.", bundle: AppSettings.localizationBundle)
        case .insufficientRecipeData:
            return String(localized: "Es konnten keine eindeutigen Zutaten oder Zubereitungsschritte erkannt werden. Bitte verwende ein gerades, gut lesbares Bild.", bundle: AppSettings.localizationBundle)
        }
    }
}

struct RecognizedRecipeLine: Sendable {
    let page: Int
    let text: String
    let boundingBox: CGRect

    var x: CGFloat { boundingBox.minX }
    var y: CGFloat { boundingBox.midY }
}

/// Whether a line belongs to the page rather than to the recipe: a browser's
/// print header, a page count, or a piece of a logo.
///
/// The name is otherwise taken from the topmost heading-like line, and these sit
/// above the real heading — so a "750 grammes" logo caught in the frame became
/// the recipe's name, while the same recipe photographed a little wider read
/// correctly. This judges a whole line; `withoutPageFurniture` strips such
/// fragments out of a line that is otherwise wanted.
func isPageFurnitureLine(_ line: String) -> Bool {
    let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
    let patterns = [
        // A web address, with or without a scheme: "quiche-lorraine.com …".
        #"[\p{L}\d][\p{L}\d\-]*\.(?:com|de|fr|net|org|eu|ch|at|be|it|es)\b"#,
        // "Seite 1 von 2", "Page 1 sur 2", "Page 1 of 2".
        #"^\s*(?:seite|page)\s+\d+\s*(?:von|sur|of|/)?\s*\d*\s*$"#,
        // What is left of a logo: "~ 750", "750 g", "grammes".
        #"^\s*[~¥≈\-–—]?\s*\d+(?:[.,]\d+)?\s*(?:g|gr|kg|ml|cl|dl|l)?\.?\s*$"#,
        #"^\s*(?:gramm|gramme|grammes|gramms|gr)\.?\s*$"#
    ]
    return patterns.contains {
        trimmed.range(of: $0, options: [.regularExpression, .caseInsensitive]) != nil
    }
}

/// What the document request understood about a page beyond its plain lines: the
/// tables it laid out, which lines continue on the next one, and the heading it
/// considers the page title. Reading a recipe from these is independent of where
/// on the page a block happens to sit.
struct RecognizedPageStructure {

    struct Table {
        let rows: [[String]]
        /// The rectangle of each row, in the same order as ``rows``.
        let rowBoxes: [CGRect]
        let boundingBox: CGRect

        var transcript: String {
            rows.flatMap { $0 }.joined(separator: " ")
        }
    }

    /// A number the data detector resolved to a physical quantity, at the place
    /// it was printed. Grams and degrees are told apart here rather than in the
    /// text, because the OCR loses a unit far more often than a digit.
    struct DetectedAmount {
        let value: Double
        let isMass: Bool
        let isTemperature: Bool
        let boundingBox: CGRect
    }

    /// A block of prose the document request kept together, even where the
    /// print breaks it across several lines.
    struct Paragraph {
        let text: String
        let boundingBox: CGRect
    }

    let page: Int
    let tables: [Table]
    let paragraphs: [Paragraph]
    let amounts: [DetectedAmount]
    /// Transcripts of lines whose text continues on the following line.
    let wrappingLines: Set<String>
    let title: String?
}

struct ParsedPlanningStep {
    let day: Int
    let hour: Int
    let minute: Int
    let action: String
    let isEndMarker: Bool

    var absoluteMinutes: Int { day * 1_440 + hour * 60 + minute }
}

struct ParsedDetailedInstruction {
    let componentName: String
    let sourceNumber: Int
    let text: String
}

enum RecipeWorkPhase {
    case componentPreparation
    case mainDough
    case portioning
    case preShaping
    case lamination
    case shaping
    case cutting
    case baking
}
