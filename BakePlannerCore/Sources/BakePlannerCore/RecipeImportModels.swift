//
//  RecipeImportModels.swift
//  BakePlannerCore
//
//  The pieces of a recognized page that the recipe import passes to the
//  template readers (TwoColumnRecipeParser, GeneralRecipeParser), and the
//  errors they report. The recognition itself (Vision) and the result with
//  its picture stay in the app (RecipeImageAnalysisAgent,
//  RecipeImageAnalysisModels).
//

import CoreGraphics
import Foundation

/// Text knowledge the recognition and the readers share.
public enum RecipeImportText {
    /// Baking terms that language correction otherwise garbles in the small type
    /// of ingredient tables — "Roggenvollkornmehl" came back as
    /// "Roggenvol kornmeh", "Anstellgut" as "Anstel gut".
    public static let bakingVocabulary = [
        "Roggenvollkornmehl", "Weizenvollkornmehl", "Dinkelvollkornmehl",
        "Roggenmehl", "Weizenmehl", "Dinkelmehl", "Ruchmehl", "Vollkornmehl",
        "Anstellgut", "Sauerteig", "Sauerteigstufe", "Quellstück", "Brühstück",
        "Kochstück", "Vorteig", "Hauptteig", "Poolish", "Lievito Madre",
        "Stückgare", "Stockgare", "Autolyse", "Gärkorb", "Teigling",
        "Backmalz", "Trockenhefe", "Frischhefe", "Backpapier", "Walnüsse",
        "Feigen", "Planungsbeispiel"
    ]

    /// A clock time written in the text, "6:30" or "18.45".
    public static func clockTime(in text: String) -> (hour: Int, minute: Int)? {
        guard let expression = try? NSRegularExpression(pattern: #"\b(\d{1,2})[:.](\d{2})\b"#),
              let match = expression.firstMatch(
                  in: text,
                  range: NSRange(text.startIndex..., in: text)
              ),
              let hourRange = Range(match.range(at: 1), in: text),
              let minuteRange = Range(match.range(at: 2), in: text),
              let hour = Int(text[hourRange]),
              let minute = Int(text[minuteRange]),
              hour < 24, minute < 60 else {
            return nil
        }
        return (hour, minute)
    }
}

public enum RecipeImageAnalysisError: LocalizedError {
    case invalidImage
    case noTextRecognized
    case unsupportedLayout
    case insufficientRecipeData

    public var errorDescription: String? {
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

public struct RecognizedRecipeLine: Sendable {
    public let page: Int
    public let text: String
    public let boundingBox: CGRect

    public var x: CGFloat { boundingBox.minX }
    public var y: CGFloat { boundingBox.midY }

    public init(page: Int, text: String, boundingBox: CGRect) {
        self.page = page
        self.text = text
        self.boundingBox = boundingBox
    }
}

/// Whether a line belongs to the page rather than to the recipe: a browser's
/// print header, a page count, or a piece of a logo.
///
/// The name is otherwise taken from the topmost heading-like line, and these sit
/// above the real heading — so a "750 grammes" logo caught in the frame became
/// the recipe's name, while the same recipe photographed a little wider read
/// correctly. This judges a whole line; `withoutPageFurniture` strips such
/// fragments out of a line that is otherwise wanted.
public func isPageFurnitureLine(_ line: String) -> Bool {
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
public struct RecognizedPageStructure {

    public struct Table {
        public let rows: [[String]]
        /// The rectangle of each row, in the same order as ``rows``.
        public let rowBoxes: [CGRect]
        public let boundingBox: CGRect

        public var transcript: String {
            rows.flatMap { $0 }.joined(separator: " ")
        }

        public init(rows: [[String]], rowBoxes: [CGRect], boundingBox: CGRect) {
            self.rows = rows
            self.rowBoxes = rowBoxes
            self.boundingBox = boundingBox
        }
    }

    /// A number the data detector resolved to a physical quantity, at the place
    /// it was printed. Grams and degrees are told apart here rather than in the
    /// text, because the OCR loses a unit far more often than a digit.
    public struct DetectedAmount {
        public let value: Double
        public let isMass: Bool
        public let isTemperature: Bool
        public let boundingBox: CGRect

        public init(value: Double, isMass: Bool, isTemperature: Bool, boundingBox: CGRect) {
            self.value = value
            self.isMass = isMass
            self.isTemperature = isTemperature
            self.boundingBox = boundingBox
        }
    }

    /// A block of prose the document request kept together, even where the
    /// print breaks it across several lines.
    public struct Paragraph {
        public let text: String
        public let boundingBox: CGRect

        public init(text: String, boundingBox: CGRect) {
            self.text = text
            self.boundingBox = boundingBox
        }
    }

    public let page: Int
    public let tables: [Table]
    public let paragraphs: [Paragraph]
    public let amounts: [DetectedAmount]
    /// Transcripts of lines whose text continues on the following line.
    public let wrappingLines: Set<String>
    public let title: String?

    public init(page: Int, tables: [Table], paragraphs: [Paragraph], amounts: [DetectedAmount], wrappingLines: Set<String>, title: String?) {
        self.page = page
        self.tables = tables
        self.paragraphs = paragraphs
        self.amounts = amounts
        self.wrappingLines = wrappingLines
        self.title = title
    }
}

public struct ParsedPlanningStep {
    public let day: Int
    public let hour: Int
    public let minute: Int
    public let action: String
    public let isEndMarker: Bool

    public var absoluteMinutes: Int { day * 1_440 + hour * 60 + minute }

    public init(day: Int, hour: Int, minute: Int, action: String, isEndMarker: Bool) {
        self.day = day
        self.hour = hour
        self.minute = minute
        self.action = action
        self.isEndMarker = isEndMarker
    }
}

public struct ParsedDetailedInstruction {
    public let componentName: String
    public let sourceNumber: Int
    public let text: String

    public init(componentName: String, sourceNumber: Int, text: String) {
        self.componentName = componentName
        self.sourceNumber = sourceNumber
        self.text = text
    }
}

public enum RecipeWorkPhase {
    case componentPreparation
    case mainDough
    case portioning
    case preShaping
    case lamination
    case shaping
    case cutting
    case baking
}
