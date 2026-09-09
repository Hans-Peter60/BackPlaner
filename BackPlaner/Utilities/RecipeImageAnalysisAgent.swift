import Foundation
import UIKit
@preconcurrency import Vision

/// A way of reading a recipe from photographed pages. The import tries all of
/// them and keeps the best result, so a new template only needs a new case here
/// and a reader for it.
enum RecipeLayout: String, CaseIterable, Sendable {
    /// Two columns with a planning example and numbered work steps, as printed
    /// by ploetzblog.
    case ploetzblogTwoColumn
    /// Cookbooks, magazines, printouts: headings, ingredient blocks and prose.
    case general

    var title: LocalizedStringResource {
        switch self {
        case .ploetzblogTwoColumn: "Ploetzblog (zweispaltig)"
        case .general: "Allgemeine Rezeptvorlage"
        }
    }
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

    init(
        recipe: RecipeFB,
        recognizedText: String,
        recipeImage: UIImage? = nil,
        warnings: [String] = [],
        layout: RecipeLayout = .general
    ) {
        self.recipe = recipe
        self.recognizedText = recognizedText
        self.recipeImage = recipeImage
        self.warnings = warnings
        self.layout = layout
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
            return String(localized: "Mindestens eines der ausgewählten Bilder konnte nicht gelesen werden.")
        case .noTextRecognized:
            return String(localized: "Auf den Bildern wurde kein ausreichend lesbarer Text erkannt.")
        case .unsupportedLayout:
            return String(localized: "Das erwartete zweispaltige Rezeptlayout mit Planungsbeispiel wurde nicht erkannt.")
        case .insufficientRecipeData:
            return String(localized: "Es konnten keine eindeutigen Zutaten oder Zubereitungsschritte erkannt werden. Bitte verwende ein gerades, gut lesbares Bild.")
        }
    }
}

private struct RecognizedRecipeLine: Sendable {
    let page: Int
    let text: String
    let boundingBox: CGRect

    var x: CGFloat { boundingBox.minX }
    var y: CGFloat { boundingBox.midY }
}

/// What the document request understood about a page beyond its plain lines: the
/// tables it laid out, which lines continue on the next one, and the heading it
/// considers the page title. Reading a recipe from these is independent of where
/// on the page a block happens to sit.
private struct RecognizedPageStructure {

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

private struct ParsedPlanningStep {
    let day: Int
    let hour: Int
    let minute: Int
    let action: String
    let isEndMarker: Bool

    var absoluteMinutes: Int { day * 1_440 + hour * 60 + minute }
}

private struct ParsedDetailedInstruction {
    let componentName: String
    let sourceNumber: Int
    let text: String
}

private enum RecipeWorkPhase {
    case componentPreparation
    case mainDough
    case portioning
    case preShaping
    case lamination
    case shaping
    case cutting
    case baking
}

final class RecipeImageAnalysisAgent {

    /// Baking terms that language correction otherwise garbles in the small type
    /// of ingredient tables — "Roggenvollkornmehl" came back as
    /// "Roggenvol kornmeh", "Anstellgut" as "Anstel gut".
    fileprivate static let bakingVocabulary = [
        "Roggenvollkornmehl", "Weizenvollkornmehl", "Dinkelvollkornmehl",
        "Roggenmehl", "Weizenmehl", "Dinkelmehl", "Ruchmehl", "Vollkornmehl",
        "Anstellgut", "Sauerteig", "Sauerteigstufe", "Quellstück", "Brühstück",
        "Kochstück", "Vorteig", "Hauptteig", "Poolish", "Lievito Madre",
        "Stückgare", "Stockgare", "Autolyse", "Gärkorb", "Teigling",
        "Backmalz", "Trockenhefe", "Frischhefe", "Backpapier", "Walnüsse",
        "Feigen", "Planungsbeispiel"
    ]

    /// Reads the pages with every known layout and returns the best result.
    ///
    /// The decision is made on the readings, not on guesses about the template:
    /// a page states its own dough weight or total preparation time, and a
    /// reading that contradicts those — or that repeats ingredients because it
    /// mistook a summary list for a component — scores lower. That way a new
    /// template needs no switch in the interface, only a reader.
    func analyze(
        images: [UIImage],
        progress: @escaping @MainActor (Int, Int) -> Void = { _, _ in }
    ) async throws -> RecipeImageAnalysisResult {

        // Text recognition is by far the most expensive part, so it runs once
        // and every reader works from the same recognized pages.
        let pages = try await recognizePages(images: images, progress: progress)

        var readings: [(result: RecipeImageAnalysisResult, quality: Double)] = []
        var failure: Error?

        for layout in RecipeLayout.allCases {
            do {
                let result: RecipeImageAnalysisResult
                switch layout {
                case .ploetzblogTwoColumn:
                    result = try readPloetzblogRecipe(from: pages)
                case .general:
                    result = try readGeneralRecipe(from: pages, firstImage: images.first)
                }
                readings.append((result, readingQuality(of: result)))
            } catch {
                failure = failure ?? error
            }
        }

        guard let best = readings.max(by: { $0.quality < $1.quality })?.result else {
            throw failure ?? RecipeImageAnalysisError.unsupportedLayout
        }

        AppLog.data.debug(
            "Recipe import: chose \(best.layout.rawValue) out of \(readings.count) readings"
        )
        return best
    }

    /// How well a reading fits the pages it came from. Only measurable
    /// properties count: values the page declares itself, and whether the
    /// reading is internally consistent.
    private func readingQuality(of result: RecipeImageAnalysisResult) -> Double {

        let ingredients = result.recipe.components.flatMap { $0.ingredients }
        guard !ingredients.isEmpty, !result.recipe.instructions.isEmpty else { return 0 }

        var score = 1.0
        let weighed = ingredients.filter { $0.weight > 0 }
        let sum = weighed.reduce(0) { $0 + $1.weight }

        // The page's own dough weight is the strongest evidence: it depends on
        // every single amount.
        if let declared = declaredDoughWeight(in: result.recognizedText), declared > 0, sum > 0 {
            let deviation = abs(sum - declared) / declared
            score += deviation <= 0.03 ? 4 : (deviation >= 0.25 ? -4 : 0)
        }

        // A declared total preparation time checks the step durations the same way.
        let durations = result.recipe.instructions.reduce(0) { $0 + $1.duration }
        if let declared = declaredTotalMinutes(in: result.recognizedText), declared > 0, durations > 0 {
            let deviation = abs(Double(durations - declared)) / Double(declared)
            score += deviation <= 0.05 ? 2 : (deviation >= 0.5 ? -2 : 0)
        }

        // A summary list read as a component shows up as the same ingredient
        // appearing twice inside one component.
        for component in result.recipe.components {
            let names = component.ingredients.map { normalizedName($0.name) }
            score -= 0.5 * Double(names.count - Set(names).count)
            if component.ingredients.isEmpty { score -= 1 }
        }

        // Names that begin with a digit or carry a percentage are leftovers of a
        // mis-read row.
        score -= 0.5 * Double(ingredients.count { ingredient in
            ingredient.name.contains("%") || (ingredient.name.first?.isNumber ?? false)
        })

        score -= 0.5 * Double(result.warnings.count)
        return score
    }

    private func normalizedName(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "de_DE"))
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    /// The dough weight a page states itself: the INFO column of a book prints
    /// it directly, ploetzblog states a piece count and a weight per piece.
    private func declaredDoughWeight(in text: String) -> Double? {
        if let values = Self.captures(#"(?i)Teig(?:menge|einwaage)\s*:?\s*(\d+(?:[.,]\d+)?)\s*g"#, in: text),
           let weight = Double(values[0].replacingOccurrences(of: ",", with: ".")) {
            return weight
        }
        if let values = Self.captures(#"(?i)für\s+(\d+)\s+Stück\s+zu\s*\(?je\)?\s*(?:ca\.)?\s*(\d+(?:[.,]\d+)?)\s*g"#, in: text),
           values.count == 2,
           let pieces = Double(values[0]),
           let each = Double(values[1].replacingOccurrences(of: ",", with: ".")) {
            return pieces * each
        }
        return nil
    }

    /// The total preparation time a page states itself, in minutes.
    private func declaredTotalMinutes(in text: String) -> Int? {
        if let values = Self.captures(
            #"(?i)Gesamtzubereitungszeit\s*:?\s*(?:ca\.\s*)?(\d+)\s*Stunden?(?:\s*(\d+)\s*Minuten?)?"#,
            in: text
        ), let hours = Int(values[0]) {
            return hours * 60 + (values.count > 1 ? Int(values[1]) ?? 0 : 0)
        }

        // A book's INFO column splits it into the day before and the baking day.
        let parts = Self.allCaptures(
            #"(?i)Zubereitungszeit[^:]*:\s*(?:ca\.\s*)?(\d+)\s*Std"#,
            in: text
        ).compactMap { Int($0) }
        guard !parts.isEmpty else { return nil }
        return parts.reduce(0, +) * 60
    }

    static func captures(_ pattern: String, in text: String) -> [String]? {
        guard let expression = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]),
              let match = expression.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) else {
            return nil
        }
        return (1..<match.numberOfRanges).compactMap { index in
            guard let range = Range(match.range(at: index), in: text) else { return nil }
            return String(text[range])
        }
    }

    static func allCaptures(_ pattern: String, in text: String) -> [String] {
        guard let expression = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return []
        }
        return expression.matches(in: text, range: NSRange(text.startIndex..., in: text))
            .compactMap { match in
                guard let range = Range(match.range(at: 1), in: text) else { return nil }
                return String(text[range])
            }
    }

    /// Analyzes common recipe layouts without applying the Ploetzblog-specific
    /// column and planning rules used by the existing analysis method.
    func analyzeGeneralRecipe(
        images: [UIImage],
        progress: @escaping @MainActor (Int, Int) -> Void = { _, _ in }
    ) async throws -> RecipeImageAnalysisResult {
        let pages = try await recognizePages(images: images, progress: progress)
        return try readGeneralRecipe(from: pages, firstImage: images.first)
    }

    /// Reads a recipe from recognized pages with the general rules: headings,
    /// ingredient blocks and prose.
    private func readGeneralRecipe(
        from pages: RecognizedPages,
        firstImage: UIImage?
    ) throws -> RecipeImageAnalysisResult {

        let orderedLines = pages.documentLines.sorted(by: Self.readingOrder)
        guard !orderedLines.isEmpty else {
            throw RecipeImageAnalysisError.noTextRecognized
        }

        let parsed = try GeneralRecipeParser(
            lines: orderedLines,
            structures: pages.structures
        ).parse()
        return RecipeImageAnalysisResult(
            recipe: parsed.recipe,
            recognizedText: orderedLines.map(\.text).joined(separator: "\n"),
            recipeImage: firstImage.flatMap(extractSalientRecipePhoto),
            warnings: parsed.warnings,
            layout: .general
        )
    }

    private func extractSalientRecipePhoto(from image: UIImage) -> UIImage? {
        guard let cgImage = image.cgImage else { return nil }

        let request = VNGenerateObjectnessBasedSaliencyImageRequest()
        let handler = VNImageRequestHandler(cgImage: cgImage)
        guard (try? handler.perform([request])) != nil,
              let observation = request.results?.first as? VNSaliencyImageObservation,
              let salientObject = observation.salientObjects?.max(by: {
                  $0.boundingBox.width * $0.boundingBox.height
                      < $1.boundingBox.width * $1.boundingBox.height
              }) else {
            return nil
        }

        let box = salientObject.boundingBox
        guard box.width * box.height >= 0.08 else { return nil }

        let padding: CGFloat = 0.12
        let expandedBox = CGRect(
            x: max(0, box.minX - box.width * padding),
            y: max(0, box.minY - box.height * padding),
            width: min(1, box.maxX + box.width * padding)
                - max(0, box.minX - box.width * padding),
            height: min(1, box.maxY + box.height * padding)
                - max(0, box.minY - box.height * padding)
        )
        let cropRect = CGRect(
            x: expandedBox.minX * CGFloat(cgImage.width),
            y: (1 - expandedBox.maxY) * CGFloat(cgImage.height),
            width: expandedBox.width * CGFloat(cgImage.width),
            height: expandedBox.height * CGFloat(cgImage.height)
        ).integral

        guard cropRect.width >= 300,
              cropRect.height >= 300,
              let croppedImage = cgImage.cropping(to: cropRect) else {
            return nil
        }
        return UIImage(cgImage: croppedImage, scale: image.scale, orientation: .up)
    }

    func analyzePloetzblogRecipe(
        images: [UIImage],
        progress: @escaping @MainActor (Int, Int) -> Void = { _, _ in }
    ) async throws -> RecipeImageAnalysisResult {
        let pages = try await recognizePages(images: images, progress: progress)
        return try readPloetzblogRecipe(from: pages)
    }

    /// Reads a recipe from recognized pages with the two-column rules of a
    /// ploetzblog page: a planning example, ingredients left of the gutter and
    /// numbered work steps to its right.
    private func readPloetzblogRecipe(
        from pages: RecognizedPages
    ) throws -> RecipeImageAnalysisResult {

        guard !pages.classicLines.isEmpty else {
            throw RecipeImageAnalysisError.noTextRecognized
        }

        let parser = TwoColumnRecipeParser(
            lines: pages.classicLines,
            structures: pages.structures
        )
        let recipe = try parser.parse()
        let recognizedText = pages.classicLines
            .sorted(by: Self.readingOrder)
            .map { "[Seite \($0.page + 1), x:\(format($0.x)), y:\(format($0.y))] \($0.text)" }
            .joined(separator: "\n")

        return RecipeImageAnalysisResult(
            recipe: recipe,
            recognizedText: recognizedText,
            layout: .ploetzblogTwoColumn
        )
    }

    /// Runs the document request and keeps what it understood about the page's
    /// structure. Both analysis paths use this: the layout of a table does not
    /// depend on which column of the page it was printed in.
    private func recognizeDocumentStructure(
        in image: UIImage,
        page: Int,
        orientation: CGImagePropertyOrientation
    ) async throws -> RecognizedPageStructure {

        guard let cgImage = image.cgImage else {
            throw RecipeImageAnalysisError.invalidImage
        }

        let observations = try await Self.documentRequest().perform(
            on: cgImage,
            orientation: orientation
        )
        guard let document = observations.first?.document else {
            throw RecipeImageAnalysisError.noTextRecognized
        }

        let tables = document.tables.map { table in
            RecognizedPageStructure.Table(
                rows: table.rows.map { row in
                    row.map {
                        $0.content.text.transcript
                            .trimmingCharacters(in: .whitespacesAndNewlines)
                    }
                },
                rowBoxes: table.rows.map { row in
                    row.reduce(CGRect.null) {
                        $0.union($1.content.text.boundingRegion.boundingBox.cgRect)
                    }
                },
                boundingBox: table.boundingRegion.boundingBox.cgRect
            )
        }

        let amounts = document.text.detectedData.compactMap { item -> RecognizedPageStructure.DetectedAmount? in
            guard case .measurement(let measurement) = item.match.details,
                  let range = item.match.range,
                  let region = document.text.boundingRegion(for: range) else {
                return nil
            }
            let dimension = measurement.possibleDimensions.first
            return RecognizedPageStructure.DetectedAmount(
                value: measurement.value,
                isMass: dimension is UnitMass,
                isTemperature: dimension is UnitTemperature,
                boundingBox: region.boundingBox.cgRect
            )
        }

        let lines = document.text.lines

        // The heading, joined across the lines it wraps into. The wrap flag is
        // what separates a title running over two lines — "Roggenvollkornbrot"
        // + "mit Walnuss und Feige" — from a subtitle printed underneath one
        // that ends on its own line. No font-size rule can tell those apart.
        var titleParts: [String] = []
        if let titleIndex = lines.firstIndex(where: { $0.isTitle }) {
            for line in lines[titleIndex...] {
                titleParts.append(
                    line.transcript.trimmingCharacters(in: .whitespacesAndNewlines)
                )
                guard line.shouldWrapToNextLine == true else { break }
            }
        }

        return RecognizedPageStructure(
            page: page,
            tables: tables,
            paragraphs: document.paragraphs.map {
                RecognizedPageStructure.Paragraph(
                    text: $0.transcript.trimmingCharacters(in: .whitespacesAndNewlines),
                    boundingBox: $0.boundingRegion.boundingBox.cgRect
                )
            },
            amounts: amounts,
            wrappingLines: Set(
                lines
                    .filter { $0.shouldWrapToNextLine == true }
                    .map { $0.transcript.trimmingCharacters(in: .whitespacesAndNewlines) }
            ),
            title: titleParts.isEmpty
                ? nil
                : titleParts.joined(separator: " ")
                    .trimmingCharacters(in: .whitespacesAndNewlines)
        )
    }

    /// Whether a laid-out table is a planning example: several of its rows carry
    /// a clock time. A temperature or percentage column does not match, so the
    /// ingredient tables are not mistaken for one.
    private func isPlanningTable(_ table: RecognizedPageStructure.Table) -> Bool {
        table.rows.count { row in
            Self.clockTime(in: row.joined(separator: " ")) != nil
        } >= 2
    }

    static func clockTime(in text: String) -> (hour: Int, minute: Int)? {
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

    private static func documentRequest() -> RecognizeDocumentsRequest {
        var request = RecognizeDocumentsRequest()
        request.textRecognitionOptions.recognitionLanguages = [
            Locale.Language(identifier: "de-DE"),
            Locale.Language(identifier: "en-US"),
            Locale.Language(identifier: "fr-FR")
        ]
        request.textRecognitionOptions.automaticallyDetectLanguage = true
        request.textRecognitionOptions.useLanguageCorrection = true
        request.textRecognitionOptions.customWords = bakingVocabulary
        return request
    }

    /// Everything the recognition produced for a set of pages. Both readers work
    /// from this, so an image passes through text recognition only once, no
    /// matter how many layouts are tried on it.
    private struct RecognizedPages {
        /// Classic recognition: the finest line granularity, which the
        /// individual ingredient rows and numbered work steps need.
        var classicLines: [RecognizedRecipeLine] = []
        /// The same pages with document paragraphs merged in, which keeps
        /// sentences together that the print breaks across lines.
        var documentLines: [RecognizedRecipeLine] = []
        /// What the document request understood about each page's layout.
        var structures: [RecognizedPageStructure] = []
    }

    private func recognizePages(
        images: [UIImage],
        progress: @escaping @MainActor (Int, Int) -> Void
    ) async throws -> RecognizedPages {

        var pages = RecognizedPages()

        for (index, image) in images.enumerated() {
            try Task.checkCancellation()
            await progress(index + 1, images.count)

            let orientation = Self.visionOrientation(for: image.imageOrientation)
            var classicLines = try await recognizeLines(
                in: image,
                page: index,
                orientation: orientation
            )
            let structure = try? await recognizeDocumentStructure(
                in: image,
                page: index,
                orientation: orientation
            )

            // The cropped second pass only exists to read a planning table that
            // classic recognition garbles. When the document request laid that
            // table out for us, the crop is unnecessary — and its assumption
            // about where the table sits is wrong for book pages.
            let hasPlanningTable = structure?.tables.contains(where: isPlanningTable) ?? false
            if !hasPlanningTable,
               classicLines.contains(where: { $0.text.localizedCaseInsensitiveContains("PLANUNGSBEISPIEL") }) {
                let planningLines = try await recognizePlanningLines(in: image, page: index)
                classicLines.removeAll { $0.x >= 0.48 && $0.y >= 0.70 }
                classicLines.append(contentsOf: planningLines)
            }

            pages.classicLines.append(contentsOf: classicLines)
            if let structure {
                pages.structures.append(structure)
                pages.documentLines.append(
                    contentsOf: documentLines(from: structure, classicLines: classicLines)
                )
            } else {
                // Without a document reading the classic lines are all there is.
                pages.documentLines.append(contentsOf: classicLines)
            }
        }

        guard !pages.classicLines.isEmpty else {
            throw RecipeImageAnalysisError.noTextRecognized
        }
        return pages
    }

    /// Combines a page's classic lines with what the document request
    /// understood: the planning table masks out the lines printed inside it,
    /// and whole paragraphs are added for the instruction prose.
    private func documentLines(
        from structure: RecognizedPageStructure,
        classicLines: [RecognizedRecipeLine]
    ) -> [RecognizedRecipeLine] {

        let page = structure.page
        let planningBoxes = structure.tables.filter { table in
            let value = table.transcript.folding(
                options: [.diacriticInsensitive, .caseInsensitive],
                locale: Locale(identifier: "de_DE")
            )
            return value.contains("planungsbeispiel")
                || (value.contains(" uhr") && (value.contains(" fr ") || value.contains(" sa ")))
        }.map(\.boundingBox)

        func isInsidePlanningTable(_ box: CGRect) -> Bool {
            planningBoxes.contains { tableBox in
                let intersection = tableBox.intersection(box)
                guard !intersection.isNull else { return false }
                let area = max(0.000_001, box.width * box.height)
                return intersection.width * intersection.height / area > 0.35
            }
        }

        // The document request supplies reliable structural masks. The classic
        // text request supplies finer line granularity inside those regions,
        // which is required for individual ingredients and preparation steps.
        var filteredLines = classicLines.filter { line in
            let value = line.text.folding(
                options: [.diacriticInsensitive, .caseInsensitive],
                locale: Locale(identifier: "de_DE")
            )
            let isIngredientRow = line.text.range(
                of: #"^\s*\d+(?:[.,]\d+)?\s*(?:g|kg|mg|ml|cl|dl|l|EL|TL|Pck|Stück)\b"#,
                options: [.regularExpression, .caseInsensitive]
            ) != nil
            let isComponentHeading = [
                "sauerteigstufe 1", "sauerteigstufe i", "sauerteigstufe 2",
                "sauerteigstufe ii", "sauerteig", "quellstuck", "hauptteig"
            ].contains(value.trimmingCharacters(in: .whitespacesAndNewlines))
            return value.contains("planungsbeispiel")
                || isIngredientRow
                || isComponentHeading
                || !isInsidePlanningTable(line.boundingBox)
        }

        // A document table can be recognized even when classic OCR omits its
        // small caption. Add a geometric anchor above the table so that the
        // first component block below it can still be reconstructed.
        if !planningBoxes.isEmpty,
           !filteredLines.contains(where: {
               $0.text.folding(
                   options: [.diacriticInsensitive, .caseInsensitive],
                   locale: Locale(identifier: "de_DE")
               ).contains("planungsbeispiel")
           }) {
            filteredLines.append(contentsOf: planningBoxes.map { box in
                RecognizedRecipeLine(
                    page: page,
                    text: "PLANUNGSBEISPIEL",
                    boundingBox: CGRect(
                        x: box.minX,
                        y: max(0, box.maxY - 0.005),
                        width: box.width,
                        height: 0.01
                    )
                )
            })
        }

        // Document paragraphs preserve paragraph boundaries and words split
        // across printed line breaks. Prefer them for instruction prose while
        // retaining classic OCR for the fine-grained ingredient rows.
        let actionTerms: [String] = [
            "misch", "verruhr", "knet", "reifen", "ruhen", "lassen", "back",
            "einarbeit", "zugeben", "abtrennen", "formen", "rundwirk", "quell"
        ]
        // Paragraphs complement the classic OCR. They must not remove the
        // original lines because compact component paragraphs are sometimes
        // assigned a broader or neighboring layout region by Vision.
        filteredLines.append(contentsOf: structure.paragraphs.compactMap { paragraph in
            let value = paragraph.text.folding(
                options: [.diacriticInsensitive, .caseInsensitive],
                locale: Locale(identifier: "de_DE")
            )
            guard paragraph.text.count >= 20,
                  actionTerms.contains(where: value.contains),
                  !isInsidePlanningTable(paragraph.boundingBox) else {
                return nil
            }
            return RecognizedRecipeLine(
                page: page,
                text: paragraph.text,
                boundingBox: paragraph.boundingBox
            )
        })

        return filteredLines
    }

    private func recognizeLines(
        in image: UIImage,
        page: Int,
        orientation: CGImagePropertyOrientation = .up
    ) async throws -> [RecognizedRecipeLine] {
        guard let cgImage = image.cgImage else {
            throw RecipeImageAnalysisError.invalidImage
        }

        return try await withCheckedThrowingContinuation { continuation in
            let request = VNRecognizeTextRequest { request, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }

                let observations = (request.results as? [VNRecognizedTextObservation]) ?? []
                let lines = observations.compactMap { observation -> RecognizedRecipeLine? in
                    guard let candidate = observation.topCandidates(1).first else { return nil }
                    return RecognizedRecipeLine(
                        page: page,
                        text: candidate.string,
                        boundingBox: observation.boundingBox
                    )
                }
                continuation.resume(returning: lines)
            }
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = true
            request.recognitionLanguages = ["de-DE", "en-US", "fr-FR"]
            request.customWords = Self.bakingVocabulary

            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    try VNImageRequestHandler(
                        cgImage: cgImage,
                        orientation: orientation
                    ).perform([request])
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    private func recognizePlanningLines(in image: UIImage, page: Int) async throws -> [RecognizedRecipeLine] {
        guard let cgImage = image.cgImage else {
            throw RecipeImageAnalysisError.invalidImage
        }
        let cropOriginX: CGFloat = 0.48
        let cropOriginY: CGFloat = 0.70
        let cropWidth: CGFloat = 0.52
        let cropHeight: CGFloat = 0.30
        let cropRect = CGRect(
            x: CGFloat(cgImage.width) * cropOriginX,
            y: 0,
            width: CGFloat(cgImage.width) * cropWidth,
            height: CGFloat(cgImage.height) * cropHeight
        ).integral
        guard let croppedImage = cgImage.cropping(to: cropRect) else {
            throw RecipeImageAnalysisError.invalidImage
        }

        return try await withCheckedThrowingContinuation { continuation in
            let request = VNRecognizeTextRequest { request, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                let observations = (request.results as? [VNRecognizedTextObservation]) ?? []
                let lines = observations.compactMap { observation -> RecognizedRecipeLine? in
                    guard let candidate = observation.topCandidates(1).first else { return nil }
                    let cropBox = observation.boundingBox
                    let mappedBox = CGRect(
                        x: cropOriginX + cropBox.minX * cropWidth,
                        y: cropOriginY + cropBox.minY * cropHeight,
                        width: cropBox.width * cropWidth,
                        height: cropBox.height * cropHeight
                    )
                    return RecognizedRecipeLine(
                        page: page,
                        text: candidate.string,
                        boundingBox: mappedBox
                    )
                }
                continuation.resume(returning: lines)
            }
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = true
            request.recognitionLanguages = ["de-DE", "en-US", "fr-FR"]
            request.customWords = Self.bakingVocabulary

            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    try VNImageRequestHandler(cgImage: croppedImage).perform([request])
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    private static func visionOrientation(
        for orientation: UIImage.Orientation
    ) -> CGImagePropertyOrientation {
        switch orientation {
        case .up:
            return .up
        case .upMirrored:
            return .upMirrored
        case .down:
            return .down
        case .downMirrored:
            return .downMirrored
        case .left:
            return .left
        case .leftMirrored:
            return .leftMirrored
        case .right:
            return .right
        case .rightMirrored:
            return .rightMirrored
        @unknown default:
            return .up
        }
    }

    private static func readingOrder(_ first: RecognizedRecipeLine, _ second: RecognizedRecipeLine) -> Bool {
        if first.page != second.page { return first.page < second.page }
        if abs(first.y - second.y) > 0.01 { return first.y > second.y }
        return first.x < second.x
    }

    private func format(_ value: CGFloat) -> String {
        String(format: "%.3f", value)
    }
}

private struct TwoColumnRecipeParser {
    let lines: [RecognizedRecipeLine]
    /// What the document request laid out per page. Empty when it failed, in
    /// which case every step falls back to the geometric reading.
    var structures: [RecognizedPageStructure] = []

    func parse() throws -> RecipeFB {
        let componentHeadings = findComponentHeadings()
        guard !componentHeadings.isEmpty,
              let planningHeading = lines.first(where: {
                  normalized($0.text).contains("planungsbeispiel")
              }),
              hasNumberedDetailSteps else {
            throw RecipeImageAnalysisError.unsupportedLayout
        }

        let recipe = RecipeFB()
        recipe.name = recipeName() ?? AppSettings.generatedRecipeTexts().importedRecipe
        recipe.summary = recipeSummary(title: recipe.name)
        recipe.sourceLanguage = "de"
        recipe.tags = inferredTags(from: recipe.name)

        var detailedInstructions: [ParsedDetailedInstruction] = []
        recipe.components = componentHeadings.enumerated().map { index, heading in
            let nextHeading = componentHeadings.dropFirst(index + 1).first
            let sectionLines = linesInSection(from: heading, to: nextHeading)
            let componentName = canonicalComponentName(heading.text)
            detailedInstructions.append(contentsOf: parseInstructions(
                from: sectionLines,
                componentName: componentName
            ))
            return makeComponent(
                name: componentName,
                number: index + 1,
                lines: sectionLines
            )
        }

        // Prefer the table the document request laid out: it carries the whole
        // planning example with day and time in their own cells, wherever on the
        // page it was printed. The geometric search below assumes the right-hand
        // column, which is where ploetzblog prints it but not a book page.
        var planningSteps = planningStepsFromTables()
        if planningSteps.count < 2 {
            let firstComponentOnPlanningPage = componentHeadings
                .filter { $0.page == planningHeading.page }
                .max(by: { $0.y < $1.y })
            let planningLines = lines.filter { line in
                line.page == planningHeading.page
                    && line.x >= 0.48
                    && line.y < planningHeading.y
                    && line.y > (firstComponentOnPlanningPage?.y ?? 0)
            }
            planningSteps = parsePlanningSteps(from: planningLines)
        }
        guard planningSteps.count >= 2 else {
            throw RecipeImageAnalysisError.unsupportedLayout
        }
        recipe.instructions = makeInstructions(
            planningSteps: planningSteps,
            details: detailedInstructions
        )
        return recipe
    }

    private func findComponentHeadings() -> [RecognizedRecipeLine] {
        guard let planningHeading = lines.first(where: {
            normalized($0.text).contains("planungsbeispiel")
        }) else { return [] }

        let detailPages = Set(lines.filter { line in
            guard line.x >= 0.48 else { return false }
            return captures(#"^\s*(\d{1,2})\s+(.+)$"#, in: line.text) != nil
        }.map(\.page))

        return lines.filter {
            detailPages.contains($0.page)
                && $0.x < 0.30
                && ($0.page != planningHeading.page || $0.y < planningHeading.y - 0.10)
                && isUppercaseHeading($0.text)
                && normalized($0.text) != "zutatenubersicht"
                && !normalized($0.text).hasPrefix("gesamter ")
        }
            .sorted { first, second in
                if first.page != second.page { return first.page < second.page }
                return first.y > second.y
            }
    }

    private func canonicalComponentName(_ text: String) -> String? {
        let value = normalized(text)
        if value.contains("weizensauerteig") { return "Weizensauerteig" }
        if value.contains("roggensauerteig") { return "Roggensauerteig" }
        if value.contains("hauptteig") { return "Hauptteig" }
        if value.contains("vorteig a") { return "Vorteig A" }
        if value.contains("vorteig b") { return "Vorteig B" }
        if value == "vorteig" { return "Vorteig" }
        if value.contains("bruhstuck") { return "Brühstück" }
        if value.contains("sauerteig") { return "Sauerteig" }
        let cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return cleaned.isEmpty ? nil : cleaned.localizedCapitalized
    }

    private func isUppercaseHeading(_ text: String) -> Bool {
        let letters = text.unicodeScalars.filter(CharacterSet.letters.contains)
        guard !letters.isEmpty else { return false }
        return text == text.uppercased(with: Locale(identifier: "de_DE"))
    }

    private func linesInSection(
        from heading: RecognizedRecipeLine,
        to nextHeading: RecognizedRecipeLine?
    ) -> [RecognizedRecipeLine] {
        lines.filter { line in
            guard line.page == heading.page, line.y < heading.y - 0.005 else { return false }
            if let nextHeading, nextHeading.page == heading.page {
                return line.y > nextHeading.y + 0.005
            }
            return true
        }
    }

    private func makeComponent(
        name: String?,
        number: Int,
        lines: [RecognizedRecipeLine]
    ) -> ComponentFB {
        let component = ComponentFB()
        component.id = UUID().uuidString
        component.name = name ?? String(
            format: AppSettings.generatedRecipeTexts().componentFormat,
            number
        )
        component.number = number

        let ingredientRows = groupedRows(lines.filter { $0.x < 0.48 })
        var parsedRows = ingredientRows.compactMap(parseIngredientRow)
        parsedRows.append(contentsOf: amountlessTableIngredients(
            in: lines,
            excluding: parsedRows
        ))
        component.ingredients = parsedRows.enumerated().map { index, parsed in
            let ingredient = IngredientFB()
            ingredient.id = UUID().uuidString
            ingredient.number = index + 1
            ingredient.name = parsed.name
            ingredient.weight = parsed.amount
            ingredient.unit = parsed.unit
            return ingredient
        }
        return component
    }

    /// Ingredient rows without an amount that only the laid-out table proves to
    /// be ingredients at all.
    ///
    /// "Ei (verrührt, zum Abstreichen)" belongs to the dough as much as the
    /// flour does, but it carries no weight, so by position alone it is
    /// indistinguishable from a caption. Rows that do carry an amount are left
    /// to the line path, whose finer granularity reads them better.
    private func amountlessTableIngredients(
        in sectionLines: [RecognizedRecipeLine],
        excluding parsed: [(name: String, amount: Double, unit: String)]
    ) -> [(name: String, amount: Double, unit: String)] {

        let column = sectionLines.filter { $0.x < 0.48 }
        guard let page = column.first?.page,
              let lowestY = column.map(\.y).min(),
              let highestY = column.map(\.y).max() else {
            return []
        }

        return structures.filter { $0.page == page }.flatMap { structure in
            structure.tables.filter { table in
                // The planning example is a table too, and its rows are times.
                table.rows.count { row in
                    RecipeImageAnalysisAgent.clockTime(in: row.joined(separator: " ")) != nil
                } < 2
            }.flatMap { table in
                zip(table.rows, table.rowBoxes).compactMap { row, box -> (name: String, amount: Double, unit: String)? in
                    guard !box.isNull,
                          box.midX < 0.48,
                          box.midY >= lowestY,
                          box.midY <= highestY else {
                        return nil
                    }

                    var text = row.filter { !$0.isEmpty }
                        .joined(separator: " ")
                        .replacingOccurrences(of: "\n", with: " ")
                    let temperature = capture(#"\b\d+(?:[\.,]\d+)?\s*°\s*C\b"#, in: text) ?? ""
                    if !temperature.isEmpty {
                        text = text.replacingOccurrences(
                            of: temperature,
                            with: "",
                            options: .caseInsensitive
                        )
                    }

                    let baseName = text
                        .replacingOccurrences(of: #"\s{2,}"#, with: " ", options: .regularExpression)
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                    let value = normalized(baseName)
                    guard value.count >= 4,
                          baseName.range(of: #"^\s*\d"#, options: .regularExpression) == nil,
                          isPlausibleIngredient(baseName),
                          !parsed.contains(where: { normalized($0.name).contains(value) }) else {
                        return nil
                    }
                    return (ingredientName(baseName, temperature: temperature), 0, "")
                }
            }
        }
    }

    private func parseIngredientRow(_ row: [RecognizedRecipeLine]) -> (name: String, amount: Double, unit: String)? {
        var text = row.sorted { $0.x < $1.x }.map(\.text).joined(separator: " ")
        let temperature = capture(#"\b\d+(?:[\.,]\d+)?\s*°\s*C\b"#, in: text) ?? ""
        if !temperature.isEmpty {
            text = text.replacingOccurrences(of: temperature, with: "", options: .caseInsensitive)
        }

        let amountPattern = #"^\s*(\d+(?:[\.,]\d+)?)\s*(g|kg|mg|ml|cl|l|tl|el|stück)?\s+(.+?)\s*$"#
        if let captures = captures(amountPattern, in: text), captures.count == 3 {
            let amount = Double(captures[0].replacingOccurrences(of: ",", with: ".")) ?? 0
            let unit = captures[1]
            let baseName = captures[2].trimmingCharacters(in: .whitespacesAndNewlines)
            guard isPlausibleIngredient(baseName) else { return nil }
            return (ingredientName(baseName, temperature: temperature), amount, unit)
        }

        let baseName = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard normalized(baseName).hasPrefix("gesamt")
                || normalized(baseName).contains("zum walzen") else { return nil }
        return (ingredientName(baseName, temperature: temperature), 0, "")
    }

    private func parseInstructions(
        from lines: [RecognizedRecipeLine],
        componentName: String?
    ) -> [ParsedDetailedInstruction] {
        let rows = groupedRows(lines.filter { $0.x >= 0.48 })
        var results: [ParsedDetailedInstruction] = []
        var currentNumber: Int?
        var currentText: [String] = []

        func appendCurrent() {
            guard let currentNumber, !currentText.isEmpty else { return }
            results.append(ParsedDetailedInstruction(
                componentName: componentName ?? "",
                sourceNumber: currentNumber,
                text: currentText.joined(separator: " ")
            ))
        }

        for row in rows {
            let sortedRow = row.sorted { $0.x < $1.x }
            let text = sortedRow.map(\.text).joined(separator: " ")
            if let values = captures(#"^\s*(\d{1,2})\s+(.+)$"#, in: text),
               let number = Int(values[0]),
               (1...20).contains(number),
               (sortedRow.first?.x ?? 1) < 0.54 {
                appendCurrent()
                currentNumber = number
                currentText = [values[1]]
            } else if currentNumber == 1,
                      !currentText.isEmpty,
                      text.range(of: #"^\s*\d+(?:[,.]\d+)?\s*(?:Minuten?|Stunden?)\b"#, options: [.regularExpression, .caseInsensitive]) != nil {
                // The circled step number is occasionally omitted by OCR. A duration at
                // the start of the next row is the characteristic second instruction.
                appendCurrent()
                currentNumber = 2
                currentText = [text]
            } else if currentNumber != nil {
                currentText.append(text)
            } else if !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                // In this layout every component starts with step 1. Vision sometimes
                // recognizes its text but drops the light circled numeral.
                currentNumber = 1
                currentText = [text]
            }
        }
        appendCurrent()
        return results
    }

    /// The signature of this layout: work steps numbered in the right-hand
    /// column. Everything else this parser assumes — ingredients left of the
    /// gutter, component headings in the page margin — only holds for pages
    /// built that way. A book page whose right column is running prose has to be
    /// rejected here, so the caller can offer the general reading instead of a
    /// recipe assembled from the wrong halves of the page.
    private var hasNumberedDetailSteps: Bool {
        lines.count { line in
            line.x >= 0.48
                && line.x < 0.54
                && captures(#"^\s*\d{1,2}\s+\S.*$"#, in: line.text) != nil
        } >= 3
    }

    /// Reads the planning example out of a laid-out table. Each row carries the
    /// action, the day and the time in separate cells; which cell is which is
    /// decided by content, so both column orders work.
    ///
    /// The day is given either as "Tag 1" or as a weekday abbreviation. In the
    /// latter case each new label starts the next day, which is what "FR, FR,
    /// SA, SA" means on a book page.
    private func planningStepsFromTables() -> [ParsedPlanningStep] {

        let tables = structures.flatMap { structure in
            structure.tables.filter { table in
                table.rows.count { row in
                    RecipeImageAnalysisAgent.clockTime(in: row.joined(separator: " ")) != nil
                } >= 2
            }
        }
        guard let table = tables.first else { return [] }

        var dayByLabel: [String: Int] = [:]
        var currentDay = 1
        var steps: [ParsedPlanningStep] = []

        for row in table.rows {
            let cells = row.filter { !$0.isEmpty }
            guard let timeCell = cells.first(where: {
                      RecipeImageAnalysisAgent.clockTime(in: $0) != nil
                  }),
                  let time = RecipeImageAnalysisAgent.clockTime(in: timeCell) else {
                continue
            }

            let remaining = cells.filter { $0 != timeCell }
            if let dayText = capture(#"(?i)tag\s*(\d)"#, group: 1, in: cells.joined(separator: " ")),
               let day = Int(dayText) {
                currentDay = day
            } else if let label = remaining.first(where: {
                $0.count <= 3 && $0.rangeOfCharacter(from: .letters) != nil
            }) {
                let key = normalized(label)
                if let known = dayByLabel[key] {
                    currentDay = known
                } else {
                    currentDay = (dayByLabel.values.max() ?? 0) + 1
                    dayByLabel[key] = currentDay
                }
            }

            guard let action = remaining
                .filter({ $0.count > 3 })
                .max(by: { $0.count < $1.count })?
                .replacingOccurrences(
                    of: #"(?i)^\s*tag\s*\d\s*"#,
                    with: "",
                    options: .regularExpression
                )
                .trimmingCharacters(in: .whitespacesAndNewlines),
                  !action.isEmpty else {
                continue
            }

            steps.append(ParsedPlanningStep(
                day: currentDay,
                hour: time.hour,
                minute: time.minute,
                action: action,
                isEndMarker: isGeneratedCompletionStep(action)
            ))
        }
        return steps
    }

    private func parsePlanningSteps(from lines: [RecognizedRecipeLine]) -> [ParsedPlanningStep] {
        let rows = groupedRows(lines)
        var currentDay = 1
        var steps: [ParsedPlanningStep] = []

        for row in rows {
            let rawText = row.sorted { $0.x < $1.x }.map(\.text).joined(separator: " ")
            let text = rawText.replacingOccurrences(
                of: #"(?i)(tag\s*\d)(\d{2}[:\.]\d{2})"#,
                with: "$1 $2",
                options: .regularExpression
            )
            if let dayText = capture(#"(?i)tag\s*(\d)"#, group: 1, in: text),
               let day = Int(dayText) {
                currentDay = day
            }
            guard let timeValues = captures(#"\b(\d{1,2})[:\.](\d{2})\b"#, in: text),
                  timeValues.count == 2,
                  let hour = Int(timeValues[0]),
                  let minute = Int(timeValues[1]) else { continue }

            var action = text
            if let timeRange = action.range(of: #"\b\d{1,2}[:\.]\d{2}\b"#, options: .regularExpression) {
                action = String(action[timeRange.upperBound...])
            }
            action = action.replacingOccurrences(of: #"^\s*Uhr\s*"#, with: "", options: [.regularExpression, .caseInsensitive])
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !action.isEmpty else { continue }
            steps.append(ParsedPlanningStep(
                day: currentDay,
                hour: hour,
                minute: minute,
                action: action,
                isEndMarker: isGeneratedCompletionStep(action)
            ))
        }
        return steps
    }

    private func makeInstructions(
        planningSteps: [ParsedPlanningStep],
        details: [ParsedDetailedInstruction]
    ) -> [InstructionFB] {
        // The oven-on step of the planning example is kept: it carries the
        // recipe's own preheating time, which takes precedence over the app's
        // setting. The instruction views recognise it as an explicit preheating
        // step and then generate none of their own. Only the closing "ca. fertig
        // gebacken" marker is dropped, because the app appends that itself.
        return planningSteps.indices.compactMap { index in
            let step = planningSteps[index]
            guard !step.isEndMarker,
                  index + 1 < planningSteps.count else { return nil }
            let instruction = InstructionFB()
            instruction.id = UUID().uuidString
            instruction.step = Double(index + 1)
            instruction.duration = max(
                0,
                planningSteps[index + 1].absoluteMinutes - step.absoluteMinutes
            )
            let actionKey = normalized(step.action)
            let matchingActionIndices = planningSteps.indices.filter {
                !planningSteps[$0].isEndMarker
                    && normalized(planningSteps[$0].action) == actionKey
            }
            let occurrence = matchingActionIndices.firstIndex(of: index) ?? 0
            instruction.instruction = description(
                for: step.action,
                details: details,
                occurrence: occurrence,
                occurrenceCount: matchingActionIndices.count
            )
            return instruction
        }
    }

    private func description(
        for action: String,
        details: [ParsedDetailedInstruction],
        occurrence: Int,
        occurrenceCount: Int
    ) -> String {
        let normalizedAction = normalized(action)
        let componentName: String
        let workPhase: RecipeWorkPhase?

        if normalizedAction.contains("herstellen") {
            componentName = Set(details.map(\.componentName))
                .sorted { $0.count > $1.count }
                .first(where: { normalizedAction.contains(normalized($0)) }) ?? ""
            workPhase = componentName == "Hauptteig" ? .mainDough : .componentPreparation
        } else if normalizedAction.contains("portionieren") {
            componentName = "Hauptteig"
            workPhase = .portioning
        } else if normalizedAction.contains("vorformen") {
            componentName = "Hauptteig"
            workPhase = .preShaping
        } else if normalizedAction.contains("doppeltour") || normalizedAction.contains("tourieren") {
            componentName = "Hauptteig"
            workPhase = .lamination
        } else if normalizedAction.contains("formen") {
            componentName = "Hauptteig"
            workPhase = .shaping
        } else if normalizedAction.contains("schneiden") {
            componentName = "Hauptteig"
            workPhase = .cutting
        } else if normalizedAction == "backen" {
            componentName = "Hauptteig"
            workPhase = .baking
        } else {
            return action
        }

        var matchingDetails = details.filter { detail in
            guard normalized(detail.componentName) == normalized(componentName) else { return false }
            guard componentName == "Hauptteig", let workPhase else { return true }
            let componentDetails = details.filter {
                normalized($0.componentName) == normalized(componentName)
            }
            return semanticPhase(for: detail, among: componentDetails) == workPhase
        }.sorted { $0.sourceNumber < $1.sourceNumber }
        if occurrenceCount > 1, !matchingDetails.isEmpty {
            let lowerBound = occurrence * matchingDetails.count / occurrenceCount
            let upperBound = (occurrence + 1) * matchingDetails.count / occurrenceCount
            matchingDetails = Array(matchingDetails[lowerBound..<upperBound])
        }
        guard !matchingDetails.isEmpty else { return action }
        let detailText = matchingDetails
            .map { "\($0.sourceNumber). \($0.text)" }
            .joined(separator: "\n")
        return "\(action)\n\(detailText)"
    }

    private func semanticPhase(
        for detail: ParsedDetailedInstruction,
        among details: [ParsedDetailedInstruction]
    ) -> RecipeWorkPhase {
        let ordered = details.sorted { $0.sourceNumber < $1.sourceNumber }
        let laminationStart = ordered.first {
            containsAny(normalized($0.text), ["butterplatte", "doppeltour", "tourieren"])
        }?.sourceNumber

        if let laminationStart {
            let preShapingStart = ordered.first {
                $0.sourceNumber < laminationStart
                    && normalized($0.text).contains("ausrollen")
            }?.sourceNumber
            let portioningStart = ordered.first {
                $0.sourceNumber > laminationStart
                    && containsAny(normalized($0.text), ["markierung", "dreiecke schneiden", "teig teilen"])
            }?.sourceNumber
            let shapingStart = ordered.first {
                $0.sourceNumber > (portioningStart ?? laminationStart)
                    && normalized($0.text).contains("dreiecke")
                    && normalized($0.text).contains("aufrollen")
            }?.sourceNumber
            let bakingStart = ordered.first {
                $0.sourceNumber > (shapingStart ?? laminationStart)
                    && containsAny(normalized($0.text), ["abstreichen", "vorgeheizten ofen", "ausbacken"])
            }?.sourceNumber

            if let bakingStart, detail.sourceNumber >= bakingStart { return .baking }
            if let shapingStart, detail.sourceNumber >= shapingStart { return .shaping }
            if let portioningStart, detail.sourceNumber >= portioningStart { return .portioning }
            if detail.sourceNumber >= laminationStart { return .lamination }
            if let preShapingStart, detail.sourceNumber >= preShapingStart { return .preShaping }
            return .mainDough
        }

        return semanticPhase(for: detail.text)
    }

    private func semanticPhase(for instruction: String) -> RecipeWorkPhase {
        let text = normalized(instruction)

        if containsAny(text, [
            "kippdiele", "rasierklinge", "nachschneiden", "einschneiden"
        ]) {
            return .cutting
        }

        // Baking starts with transferring the shaped pieces to baking paper or
        // the oven; it therefore also covers the final turn-out before loading.
        if containsAny(text, [
            "backpapier", "einschiesser", "ofen", "backstein", "bedampfen",
            "dampf", "herunterdrehen", "ausbacken", "backen"
        ]) {
            return .baking
        }

        if (text.contains("aufrollen") && !containsAny(text, ["langlich", "stangen"]))
            || (text.contains("schluss nach oben") && text.contains("leinen")) {
            return .preShaping
        }

        if containsAny(text, [
            "teighaut der teiglinge", "formen", "form geben", "walzen",
            "schluss nach unten", "schluss einarbeiten", "rundwirken", "rund wirken",
            "langlichen stangen", "arbeitsflache setzen", "leinen", "stuckgare"
        ]) {
            return .shaping
        }

        if containsAny(text, [
            "abstechen", "portionieren", "portionen", "teig teilen",
            "arbeitsflache geben", "arbeitsflache sturzen"
        ]) {
            return .portioning
        }

        return .mainDough
    }

    private func containsAny(_ text: String, _ terms: [String]) -> Bool {
        terms.contains(where: text.contains)
    }

    private func isGeneratedCompletionStep(_ action: String) -> Bool {
        let text = normalized(action)
        return containsAny(text, [
            "backvorgang beendet", "backen beendet",
            "fertig gebacken", "backende"
        ])
    }

    private func recipeName() -> String? {
        let excluded = ["zutatenubersicht", "planungsbeispiel", "vorteig a", "weizensauerteig", "vorteig b", "hauptteig", "sauerteig", "vorteig"]
        let pagesWithPlanning = Set(lines.filter {
            normalized($0.text).contains("planungsbeispiel")
        }.map(\.page))
        return lines.filter { line in
            !pagesWithPlanning.contains(line.page)
                && line.y > 0.82
                && line.text.count > 4
                && !excluded.contains(normalized(line.text))
        }.max(by: { $0.boundingBox.height < $1.boundingBox.height })?.text
    }

    private func recipeSummary(title: String) -> String {
        guard let titleLine = lines.first(where: { $0.text == title }) else { return "" }
        return groupedRows(lines.filter {
            $0.page == titleLine.page && $0.x > 0.38 && $0.y < titleLine.y - 0.03
        }).map { $0.sorted { $0.x < $1.x }.map(\.text).joined(separator: " ") }
            .filter { !normalized($0).hasPrefix("tipps") }
            .joined(separator: " ")
    }

    private func inferredTags(from name: String) -> [String] {
        let value = normalized(name)
        var tags: [String] = []
        if value.contains("ciabatta") { tags.append("Ciabatta") }
        if value.contains("weizen") { tags.append("Weizenbrot") }
        if value.contains("sauerteig") { tags.append("Sauerteig") }
        return tags
    }

    private func groupedRows(
        _ sourceLines: [RecognizedRecipeLine],
        tolerance: CGFloat = 0.004
    ) -> [[RecognizedRecipeLine]] {
        let sorted = sourceLines.sorted {
            if abs($0.y - $1.y) > tolerance { return $0.y > $1.y }
            return $0.x < $1.x
        }
        var rows: [[RecognizedRecipeLine]] = []
        for line in sorted {
            if let lastIndex = rows.indices.last,
               let referenceY = rows[lastIndex].first?.y,
               abs(referenceY - line.y) <= tolerance {
                rows[lastIndex].append(line)
            } else {
                rows.append([line])
            }
        }
        return rows
    }

    private func normalized(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "de_DE"))
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    private func ingredientName(_ name: String, temperature: String) -> String {
        let cleanedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanedTemperature = temperature.trimmingCharacters(in: .whitespacesAndNewlines)
        return cleanedTemperature.isEmpty ? cleanedName : "\(cleanedName) (\(cleanedTemperature))"
    }

    private func isPlausibleIngredient(_ text: String) -> Bool {
        let value = normalized(text)
        return !value.isEmpty
            && !value.contains("schritt")
            && !value.contains("stunde")
            && !value.contains("minute")
    }

    private func capture(_ pattern: String, group: Int = 0, in text: String) -> String? {
        guard let expression = try? NSRegularExpression(pattern: pattern),
              let match = expression.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              group < match.numberOfRanges,
              let range = Range(match.range(at: group), in: text) else { return nil }
        return String(text[range])
    }

    private func captures(_ pattern: String, in text: String) -> [String]? {
        guard let expression = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]),
              let match = expression.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) else {
            return nil
        }
        return (1..<match.numberOfRanges).map { index in
            guard let range = Range(match.range(at: index), in: text) else { return "" }
            return String(text[range])
        }
    }
}

private struct GeneralRecipeParser {
    private enum Section {
        case introduction
        case ingredients
        case instructions
    }

    let lines: [RecognizedRecipeLine]
    /// What the document request laid out per page. Empty when it failed, in
    /// which case every step falls back to the geometric reading.
    var structures: [RecognizedPageStructure] = []

    func parse() throws -> (recipe: RecipeFB, warnings: [String]) {
        let textLines = lines.map(\.text)
            .map(cleanedLine)
            .filter { !$0.isEmpty }

        var titleCandidates: [String] = []
        var componentRows: [(String, ParsedIngredient)] = []
        var instructionRows: [String] = []
        var usedSpatialComponentAssignment = false

        if let componentSections = spatialComponentSections() {
            usedSpatialComponentAssignment = true
            titleCandidates = componentSections.introduction.filter(isPlausibleTitle)
            componentRows = componentSections.ingredients
            instructionRows = componentSections.instructions
        } else if let proseSections = inlineProseSections(in: textLines) {
            titleCandidates = textLines.filter(isPlausibleTitle)
            componentRows = proseSections.components.flatMap { component in
                ingredientsInProse(component.text).map { (component.name, $0) }
            }
            instructionRows = proseSections.components.flatMap { component in
                [component.name] + semanticClauseParts(component.text)
            }
        } else if let spatialSections = spatialSectionLines() {
            titleCandidates = spatialSections.introduction.filter(isPlausibleTitle)
            componentRows = parseIngredientSection(spatialSections.ingredients)
            instructionRows = deduplicatedParagraphs(
                spatialSections.instructions.filter {
                    isUsefulInstruction($0)
                        || recipeComponentHeading($0) != nil
                        || isStepNumberMarker($0)
                }
            )
        } else {
            var section = Section.introduction
            var componentName = "Zutaten"

            for line in textLines {
                let value = normalized(line)
                if isIngredientHeading(value) {
                    section = .ingredients
                    continue
                }
                if isInstructionHeading(value) {
                    section = .instructions
                    continue
                }

                switch section {
                case .introduction:
                    if isPlausibleTitle(line) {
                        titleCandidates.append(line)
                    }
                case .ingredients:
                    if let ingredient = parseIngredient(line) {
                        componentRows.append((componentName, ingredient))
                    } else if isComponentHeading(line) {
                        componentName = line.trimmingCharacters(in: CharacterSet(charactersIn: ": "))
                    }
                case .instructions:
                    if isUsefulInstruction(line)
                        || recipeComponentHeading(line) != nil
                        || isStepNumberMarker(line) {
                        instructionRows.append(line)
                    }
                }
            }
            instructionRows = deduplicatedParagraphs(instructionRows)
        }

        if componentRows.isEmpty {
            componentRows = textLines.flatMap { line in
                ingredientsInProse(line).map { ("Zutaten", $0) }
            }
        }
        if instructionRows.isEmpty {
            instructionRows = deduplicatedParagraphs(textLines.filter(isActionInstruction))
        }

        var seenIngredients = Set<String>()
        componentRows = componentRows.filter { componentName, ingredient in
            let key = [
                normalized(componentName),
                String(ingredient.amount),
                normalized(ingredient.unit),
                normalized(ingredient.name)
                    .replacingOccurrences(
                        of: #"\s+\d+(?:[.,]\d+)?\s*%\s*$"#,
                        with: "",
                        options: .regularExpression
                    )
            ].joined(separator: "|")
            return seenIngredients.insert(key).inserted
        }

        guard !componentRows.isEmpty || !instructionRows.isEmpty else {
            throw RecipeImageAnalysisError.insufficientRecipeData
        }

        if !usedSpatialComponentAssignment {
            componentRows = assignIngredientsToComponents(
                componentRows,
                using: instructionRows
            )
        }

        let recipe = RecipeFB()
        recipe.name = structureTitle()
            ?? detectedMultilineTitle()
            ?? titleCandidates.first
            ?? AppSettings.generatedRecipeTexts().importedRecipe
        recipe.summary = usedSpatialComponentAssignment
            ? (detectedDescriptionUnderTitle() ?? detectedSummary(in: textLines))
            : detectedSummary(in: textLines)
        recipe.sourceLanguage = detectedLanguage(in: textLines)
        recipe.tags = inferredGeneralTags(from: recipe.name)

        let groupedComponents = Dictionary(grouping: componentRows, by: \.0)
        var seenComponentNames: [String] = []
        for (name, _) in componentRows where !seenComponentNames.contains(name) {
            seenComponentNames.append(name)
        }
        recipe.components = seenComponentNames.enumerated().map { componentIndex, name in
            let component = ComponentFB()
            component.id = UUID().uuidString
            component.name = name
            component.number = componentIndex + 1
            component.ingredients = (groupedComponents[name] ?? []).enumerated().map { index, row in
                let ingredient = IngredientFB()
                ingredient.id = UUID().uuidString
                ingredient.number = index + 1
                ingredient.name = row.1.name
                ingredient.weight = row.1.amount
                ingredient.unit = row.1.unit
                return ingredient
            }
            return component
        }

        if let analyzedSteps = analyzedNumberedSteps(instructionRows)
            ?? analyzedComponentSteps(instructionRows) {
            recipe.instructions = analyzedSteps.map { analyzed in
                let instruction = InstructionFB()
                instruction.id = UUID().uuidString
                instruction.step = analyzed.step
                instruction.instruction = condensedIngredientLists(in: analyzed.text)
                instruction.duration = analyzed.duration
                instruction.componentName = analyzed.componentName
                return instruction
            }
        } else {
            recipe.instructions = semanticInstructions(instructionRows).enumerated().map { index, text in
                let instruction = InstructionFB()
                instruction.id = UUID().uuidString
                instruction.step = Double(index + 1)
                instruction.instruction = condensedIngredientLists(
                    in: removingListMarker(from: text)
                )
                instruction.duration = estimatedDuration(in: text)
                return instruction
            }
        }
        mergeTimedContinuationSteps(&recipe.instructions)
        expandTimedFoldInterventions(&recipe.instructions)
        reconcileDeclaredPreparationTime(recipe.instructions, source: textLines)

        // The INFO column of a baking book carries the values the recipe text
        // leaves out — above all the baking temperature and time — and its
        // printed dough weight and dough yield confirm the extracted amounts.
        var warnings: [String] = []
        if let infoBox = recipeInfoBox() {
            warnings = applyInfoBox(infoBox, to: recipe)
        }

        scheduleInstructions(recipe)
        return (recipe, warnings)
    }

    private struct RecipeInfoBox {
        var bakeMinutes: Int?
        var bakeTemperature: String?
        var steam: String?
        var doughWeight: Double?
        var doughYield: Double?
    }

    /// Reads the INFO column that accompanies a recipe in baking books. Its
    /// entries are label/value pairs stacked in one narrow column, which may sit
    /// on a page of its own — the column is therefore rebuilt as text and then
    /// queried by label.
    private func recipeInfoBox() -> RecipeInfoBox? {
        guard let heading = lines.first(where: { normalized($0.text) == "info" }) else {
            return nil
        }

        let columnLines = lines
            .filter {
                $0.page == heading.page
                    && $0.y < heading.y
                    && $0.x >= heading.x - 0.03
            }
            .sorted { $0.y > $1.y }
            .map(\.text)
        guard columnLines.count >= 4 else { return nil }

        // A label can wrap across two lines ("theor. Teigaus-" / "beute: ca. 194").
        var text = ""
        for line in columnLines {
            if text.isEmpty {
                text = line
            } else if text.hasSuffix("-") {
                text.removeLast()
                text += line
            } else {
                text += "\n" + line
            }
        }

        var box = RecipeInfoBox()
        box.bakeMinutes = infoMinutes(for: "Backzeit", in: text)
        box.bakeTemperature = infoValue(for: "Backtemperatur", in: text)
        box.steam = infoValue(for: "Schwaden", in: text)
        box.doughWeight = infoValue(for: "Teigmenge", in: text)
            .flatMap { captures(#"(\d+(?:[.,]\d+)?)\s*g"#, in: $0)?.first }
            .flatMap { Double($0.replacingOccurrences(of: ",", with: ".")) }
        box.doughYield = infoValue(for: "Teigausbeute", in: text)
            .flatMap { captures(#"(\d+(?:[.,]\d+)?)"#, in: $0)?.first }
            .flatMap { Double($0.replacingOccurrences(of: ",", with: ".")) }
        return box
    }

    /// The value of an INFO entry: everything behind the label up to the label of
    /// the next entry.
    private func infoValue(for label: String, in text: String) -> String? {
        let pattern = "\(label)\\s*:\\s*((?:.|\\n)*?)(?=\\n[^\\n:]{2,30}:|\\z)"
        guard let value = captures(pattern, in: text)?.first else { return nil }
        return value
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: #"\s{2,}"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// A duration from an INFO entry: "ca. 60–65 Min." becomes 63 minutes.
    private func infoMinutes(for label: String, in text: String) -> Int? {
        guard let value = infoValue(for: label, in: text) else { return nil }

        if let range = captures(#"(\d+)\s*[-–]\s*(\d+)\s*(Min|Std)"#, in: value),
           range.count == 3,
           let minimum = Int(range[0]),
           let maximum = Int(range[1]) {
            let average = Int((Double(minimum + maximum) / 2).rounded())
            return range[2].lowercased().hasPrefix("std") ? average * 60 : average
        }

        guard let single = captures(#"(\d+)\s*(Min|Std)"#, in: value),
              single.count == 2,
              let minutes = Int(single[0]) else {
            return nil
        }
        return single[1].lowercased().hasPrefix("std") ? minutes * 60 : minutes
    }

    /// Fills what the recipe text leaves open and returns what does not add up.
    /// Values the steps already carry stay untouched — on the pages seen so far
    /// they agree with the INFO column anyway.
    private func applyInfoBox(_ box: RecipeInfoBox, to recipe: RecipeFB) -> [String] {
        if recipe.totalWeight == 0, let weight = box.doughWeight {
            recipe.totalWeight = weight
        }

        if let baking = recipe.instructions
            .filter({ isBakingInstruction($0.instruction) })
            .max(by: { $0.step < $1.step }) {

            if baking.duration == 0, let minutes = box.bakeMinutes {
                baking.duration = minutes
            }

            let texts = AppSettings.generatedRecipeTexts()
            var additions: [String] = []
            if !baking.instruction.contains("°C"), let temperature = box.bakeTemperature {
                additions.append(bakeTemperatureSentence(temperature))
            }
            if let steam = box.steam {
                additions.append(String(format: texts.steamFormat, steam))
            }
            if !additions.isEmpty {
                baking.instruction = ([baking.instruction] + additions).joined(separator: " ")
            }
        }

        return implausibilityWarnings(for: recipe, against: box)
    }

    /// The printed dough weight and dough yield depend on every single amount,
    /// so they confirm the extracted ingredients independently of the baker's
    /// percentages. A clear deviation is reported instead of silently stored.
    private func implausibilityWarnings(
        for recipe: RecipeFB,
        against box: RecipeInfoBox
    ) -> [String] {
        var warnings: [String] = []
        let sum = recipe.components.flatMap { $0.ingredients }.reduce(0) { $0 + $1.weight }

        if let printed = box.doughWeight, sum > 0, abs(sum - printed) > printed * 0.03 {
            warnings.append(String(
                localized: "Die Summe der erkannten Zutaten (\(Int(sum)) g) weicht von der angegebenen Teigmenge (\(Int(printed)) g) ab.",
                locale: AppSettings.locale
            ))
        }

        if let printed = box.doughYield,
           let computed = computedDoughYield(of: recipe),
           abs(computed - printed) > 4 {
            warnings.append(String(
                localized: "Die berechnete Teigausbeute (\(Int(computed))) weicht von der angegebenen (\(Int(printed))) ab.",
                locale: AppSettings.locale
            ))
        }
        return warnings
    }

    /// Water per flour, the baker's measure of a dough: a dough yield of 194
    /// means 94 g of water for every 100 g of flour.
    private func computedDoughYield(of recipe: RecipeFB) -> Double? {
        var flour = 0.0
        var water = 0.0

        for ingredient in recipe.components.flatMap({ $0.ingredients }) {
            let value = normalized(ingredient.name)
            if value.contains("mehl") || value.contains("schrot") || value.contains("griess") {
                flour += ingredient.weight
            } else if value.contains("wasser") || value.contains("milch") {
                water += ingredient.weight
            }
        }

        guard flour > 0, water > 0 else { return nil }
        return 100 + water / flour * 100
    }

    /// "250 °C auf 210 °C" as a step sentence, in the app's language. The higher
    /// value has to come first: the app reads the oven temperature for its
    /// preheating reminder from the first number of the baking step.
    private func bakeTemperatureSentence(_ value: String) -> String {
        let texts = AppSettings.generatedRecipeTexts()
        if let values = captures(#"(\d{2,3})\s*°\s*C\s*auf\s*(\d{2,3})\s*°\s*C"#, in: value),
           values.count == 2 {
            return String(format: texts.fallingBakeTemperatureFormat, values[0], values[1])
        }
        return String(format: texts.bakeTemperatureFormat, value)
    }

    /// Places every step on the timeline, as minutes after the start the user
    /// picks. A component's preparation begins as early as it can: right at the
    /// start of the plan, or — when the component consumes another one — the
    /// moment that component is finished. The main dough waits until every
    /// preparation is done, so a soaker is always ready before it is needed, and
    /// its own steps then follow one another.
    private func scheduleInstructions(_ recipe: RecipeFB) {
        let ordered = recipe.instructions.sorted { $0.step < $1.step }

        // A preparation step carries the component it prepares, so the plan does
        // not depend on the step's wording.
        var pending: [(instruction: InstructionFB, component: ComponentFB)] = ordered.compactMap {
            instruction in
            guard let name = instruction.componentName,
                  let component = recipe.components.first(where: { $0.name == name }) else {
                return nil
            }
            return (instruction, component)
        }
        let preparationIdentifiers = Set(pending.map { $0.instruction.id })

        var endByComponent: [String: Int] = [:]
        while !pending.isEmpty {
            var deferred: [(instruction: InstructionFB, component: ComponentFB)] = []
            for entry in pending {
                let prerequisites = dependencyNames(of: entry.component, in: recipe)
                let ends = prerequisites.map { endByComponent[$0] }
                guard !ends.contains(where: { $0 == nil }) else {
                    deferred.append(entry)
                    continue
                }
                let start = ends.compactMap { $0 }.max() ?? 0
                entry.instruction.startTime = start
                endByComponent[entry.component.name] = start + entry.instruction.duration
            }
            // A missing or circular reference must not stall the plan: place the
            // remaining preparations at the start instead of looping forever.
            if deferred.count == pending.count {
                for entry in deferred {
                    entry.instruction.startTime = 0
                    endByComponent[entry.component.name] = entry.instruction.duration
                }
                break
            }
            pending = deferred
        }

        var cursor = endByComponent.values.max() ?? 0
        for instruction in ordered where !preparationIdentifiers.contains(instruction.id) {
            instruction.startTime = cursor
            cursor += instruction.duration
        }

        recipe.prepTime = recipe.instructions
            .map { ($0.startTime ?? 0) + $0.duration }
            .max() ?? 0
    }

    /// The components a component consumes, read from its "gesamte …" rows.
    private func dependencyNames(of component: ComponentFB, in recipe: RecipeFB) -> [String] {
        component.ingredients.compactMap { ingredient -> String? in
            let value = normalized(ingredient.name)
            guard ingredient.weight == 0, value.hasPrefix("gesamte") else { return nil }
            return recipe.components.first { other in
                other.name != component.name && value.contains(normalized(other.name))
            }?.name
        }
    }

    private func mergeTimedContinuationSteps(_ instructions: inout [InstructionFB]) {
        var index = 0
        while index + 1 < instructions.count {
            let current = instructions[index]
            let next = instructions[index + 1]
            let currentText = current.instruction.trimmingCharacters(in: .whitespacesAndNewlines)
            let nextText = next.instruction.trimmingCharacters(in: .whitespacesAndNewlines)
            let normalizedCurrent = normalized(currentText)
            let normalizedNext = normalized(nextText)

            let nextStartsWithDuration = nextText.range(
                of: #"^(?:ca\.?s*)?\d+(?:[.,]\d+)?\s*(?:Minuten?|Min\.?|Stunden?|Std\.?|h)\b"#,
                options: [.regularExpression, .caseInsensitive]
            ) != nil
            let currentIsIncomplete = normalizedCurrent.hasSuffix(" ca")
                || normalizedCurrent.hasSuffix(" und")
                || currentText.hasSuffix("ca.")
            let formsThenRests = (
                normalizedCurrent.contains("garkorb")
                    || normalizedCurrent.contains("gar korb")
                    || normalizedCurrent.contains("form")
                    || normalizedCurrent.contains("setzen")
            ) && (
                normalizedNext.contains("reifen lassen")
                    || normalizedNext.contains("ruhen lassen")
                    || normalizedNext.contains("gehen lassen")
            )

            guard current.duration == 0,
                  next.duration > 0,
                  nextStartsWithDuration,
                  currentIsIncomplete || formsThenRests else {
                index += 1
                continue
            }

            current.instruction = [currentText, nextText]
                .filter { !$0.isEmpty }
                .joined(separator: " ")
            current.duration = next.duration
            let removedStep = next.step
            instructions.remove(at: index + 1)
            for instruction in instructions where instruction.step > removedStep {
                instruction.step -= 1
            }
        }
    }

    private func expandTimedFoldInterventions(_ instructions: inout [InstructionFB]) {
        guard let foldIndex = instructions.firstIndex(where: {
            let value = normalized($0.instruction)
            return value.contains("nach ")
                && (value.contains("dehnen") || value.contains("denen"))
                && value.contains("falten")
        }) else {
            return
        }

        let foldInstruction = instructions[foldIndex]
        let foldText = normalized(foldInstruction.instruction)
        guard let offsets = captures(
            #"nach\s+(\d+)\s+und\s+(\d+)\s+minuten"#,
            in: foldText
        ),
        offsets.count == 2,
        let firstOffset = Int(offsets[0]),
        let secondOffset = Int(offsets[1]),
        firstOffset > 0,
        secondOffset > firstOffset else {
            return
        }

        let parentIndex: Int
        if foldText.contains("stunden") && foldText.contains("ruhen lassen") {
            parentIndex = foldIndex
        } else {
            guard let precedingIndex = instructions[..<foldIndex].lastIndex(where: {
                let value = normalized($0.instruction)
                return value.contains("stunden")
                    && (value.contains("ruhen lassen") || value.contains("reifen lassen"))
            }) else {
                return
            }
            parentIndex = precedingIndex
        }

        let parent = instructions[parentIndex]
        let totalDuration = max(parent.duration, duration(in: parent.instruction))
        guard totalDuration >= secondOffset else { return }
        parent.duration = totalDuration

        let firstFold = InstructionFB()
        firstFold.id = UUID().uuidString
        firstFold.step = parent.step + 0.1
        firstFold.instruction = "Teig dehnen und falten (nach \(firstOffset) Minuten)."
        firstFold.duration = totalDuration - firstOffset

        let secondFold = InstructionFB()
        secondFold.id = UUID().uuidString
        secondFold.step = parent.step + 0.2
        secondFold.instruction = "Teig dehnen und falten (nach \(secondOffset) Minuten)."
        secondFold.duration = totalDuration - secondOffset

        if foldIndex == parentIndex {
            instructions.insert(contentsOf: [firstFold, secondFold], at: parentIndex + 1)
        } else {
            let removedStep = foldInstruction.step
            instructions.remove(at: foldIndex)
            instructions.insert(contentsOf: [firstFold, secondFold], at: parentIndex + 1)
            for instruction in instructions where instruction.step >= removedStep {
                instruction.step -= 1
            }
        }
    }

    private func reconcileDeclaredPreparationTime(
        _ instructions: [InstructionFB],
        source: [String]
    ) {
        let text = source.joined(separator: " ")
        guard let values = captures(
            #"(?:Vorbereitungszeit|Arbeitszeit|Préparation|Preparation)\s*:?\s*(\d+)\s*Min(?:ute)?s?"#,
            in: text
        ),
        let minutesText = values.first,
        let declaredMinutes = Int(minutesText),
        declaredMinutes > 0 else {
            return
        }

        let activeInstructions = instructions.filter { instruction in
            let value = normalized(instruction.instruction)
            let passiveTerms = [
                "back", "cuire", "four", "ofen", "ruh", "reif", "geh",
                "kuhl", "kaltstell", "refroid", "abkühl"
            ]
            return !passiveTerms.contains(where: value.contains)
        }
        guard !activeInstructions.isEmpty else { return }

        let weights = activeInstructions.map { instruction -> Int in
            let value = normalized(instruction.instruction)
            if value.contains("couper") || value.contains("schneid") { return 3 }
            if value.contains("misch") || value.contains("melange")
                || value.contains("ajout") || value.contains("knet") { return 4 }
            return 3
        }
        let totalWeight = max(1, weights.reduce(0, +))
        var assignedMinutes = 0
        for (index, instruction) in activeInstructions.enumerated() {
            let allocated: Int
            if index == activeInstructions.count - 1 {
                allocated = max(1, declaredMinutes - assignedMinutes)
            } else {
                allocated = max(1, Int((Double(declaredMinutes * weights[index]) / Double(totalWeight)).rounded()))
                assignedMinutes += allocated
            }
            instruction.duration = allocated
        }
    }

    private struct ParsedIngredient {
        let amount: Double
        let unit: String
        let name: String
    }

    private struct ProseComponent {
        let name: String
        let text: String
    }

    /// Recognizes component labels embedded in continuous recipe prose, for example
    /// "Teig: ... Füllung: ...". Labels are inferred from their position before an
    /// ingredient quantity; no recipe title or fixed ingredient list is involved.
    private func inlineProseSections(in source: [String]) -> (components: [ProseComponent], introduction: String?)? {
        let text = source.joined(separator: "\n")
        let pattern = #"(?:^|\n|[.!?)]\s+)([\p{L}][\p{L} \t-]{1,28}):[ \t]*(?=(?:\d|ein(?:e|en)?[ \t]+(?:Prise|Bund|Päckchen|Packung|Rolle)))"#
        guard let expression = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return nil
        }
        let matches = expression.matches(in: text, range: NSRange(text.startIndex..., in: text)).filter { match in
            guard let nameRange = Range(match.range(at: 1), in: text) else { return false }
            let name = normalized(String(text[nameRange]))
            return isRecipeComponentName(name)
        }
        guard !matches.isEmpty else { return nil }

        var components: [ProseComponent] = []
        for (index, match) in matches.enumerated() {
            guard let nameRange = Range(match.range(at: 1), in: text),
                  let wholeRange = Range(match.range(at: 0), in: text) else { continue }
            let start = wholeRange.upperBound
            let end: String.Index
            if index + 1 < matches.count,
               let nextRange = Range(matches[index + 1].range(at: 0), in: text) {
                end = nextRange.lowerBound
            } else {
                end = text.endIndex
            }
            let name = String(text[nameRange]).trimmingCharacters(in: .whitespacesAndNewlines)
            let body = cleanedLine(String(text[start..<end]))
            guard !body.isEmpty else { continue }
            components.append(ProseComponent(name: name, text: body))
        }
        guard !components.isEmpty else { return nil }

        let introduction: String?
        if let firstRange = Range(matches[0].range(at: 0), in: text) {
            let prefix = cleanedLine(String(text[..<firstRange.lowerBound]))
            introduction = prefix.isEmpty ? nil : prefix
        } else {
            introduction = nil
        }
        return (components, introduction)
    }

    private func isRecipeComponentName(_ normalizedName: String) -> Bool {
        let componentTerms: [String] = [
            "teig", "hauptteig", "vorteig", "sauerteig", "bruhstuck", "quellstuck",
            "kochstuck", "fullung", "belag", "glasur", "guss", "creme", "sauce",
            "pate", "levain", "garniture", "farce", "appareil"
        ]
        return componentTerms.contains { term in
            normalizedName == term || normalizedName.hasSuffix(" " + term)
        }
    }

    /// Extracts every comma-separated ingredient occurrence at the beginning of a
    /// prose component. Time and temperature values are deliberately not ingredients.
    private func ingredientsInProse(_ text: String) -> [ParsedIngredient] {
        let actionPattern = #"\b(?:alle\s+zutaten|verkneten|kneten|vermischen|mischen|verrühren|rühren|geben|pürieren|schlagen|zufügen|hinzufügen|unterheben|backen|kochen|braten|auflösen|auslegen)\b"#
        let ingredientPrefix: String
        if let actionRange = text.range(of: actionPattern, options: [.regularExpression, .caseInsensitive]) {
            ingredientPrefix = String(text[..<actionRange.lowerBound])
        } else {
            ingredientPrefix = text
        }

        let separatedConjunctions = ingredientPrefix.replacingOccurrences(
            of: #"\s+und\s+(?=\d|ein(?:e|en)?\s+(?:Prise|Bund|Päckchen|Packung|Rolle))"#,
            with: ", ",
            options: [.regularExpression, .caseInsensitive]
        )
        let separated = separatedConjunctions.replacingOccurrences(
            of: #"\s+(?=\d+(?:[.,]\d+)?\s*(?:kg|g|mg|l|dl|cl|ml|EL|TL)\b)"#,
            with: ", ",
            options: [.regularExpression, .caseInsensitive]
        )
        return splitOutsideParentheses(separated).compactMap { phrase in
            parseProseIngredient(phrase)
        }
    }

    /// Splits an ingredient list at its commas, but not at commas inside
    /// parentheses: "6 g Anstellgut (TA 200, weich)" is one ingredient, and
    /// "98 g Walnüsse (geröstet, grob gehackt)" keeps its full name.
    private func splitOutsideParentheses(_ text: String) -> [String] {
        var parts: [String] = []
        var current = ""
        var depth = 0

        for character in text {
            switch character {
            case "(", "[":
                depth += 1
                current.append(character)
            case ")", "]":
                depth = max(0, depth - 1)
                current.append(character)
            case "," where depth == 0:
                parts.append(current)
                current = ""
            default:
                current.append(character)
            }
        }
        parts.append(current)
        return parts
    }

    private func parseProseIngredient(_ phrase: String) -> ParsedIngredient? {
        guard !phrase.contains("%"), !containsClockTime(phrase) else {
            return nil
        }
        let value = phrase.trimmingCharacters(in: .whitespacesAndNewlines)
        let quantifiedPattern = #"(?:^|\s)(\d+(?:[.,]\d+)?|[½¼¾⅓⅔])\s*(kg|g|mg|l|Liter|dl|cl|ml|EL|TL|cuillère à café|cuillère à soupe|cs|c\.?\s*à\.?\s*c\.?|c\.?\s*à\.?\s*s\.?|Teelöffel|Esslöffel|Stück|Stk\.?|Würfel|Prise|pinc[eé]e|Bund|Päckchen|Packung|sachet|Tasse|Rolle)?\s+(.+?)\s*$"#
        if let values = captures(quantifiedPattern, in: value), values.count == 3 {
            let rawName = cleanedIngredientName(values[2])
            let unit: String
            let name: String
            if values[1].isEmpty, ["eier", "ei", "oeufs", "oeuf"].contains(normalized(rawName)) {
                unit = "ei"
                name = rawName
            } else if values[1].isEmpty, isCountedIngredient(rawName) {
                unit = "Stück"
                name = rawName
            } else {
                unit = canonicalUnit(values[1])
                name = rawName
            }
            guard !isNutrition(name), !isTimeOrTemperature(unit: unit, name: name) else { return nil }
            return ParsedIngredient(amount: numericAmount(values[0]), unit: unit, name: name)
        }

        let wordAmountPattern = #"(?:^|\s)(?:ein(?:e|en)?)\s+(Prise|pinc[eé]e|Bund|Päckchen|Packung|sachet|Rolle)\s+(.+?)\s*$"#
        guard let values = captures(wordAmountPattern, in: value), values.count == 2 else { return nil }
        return ParsedIngredient(amount: 1, unit: canonicalUnit(values[0]), name: cleanedIngredientName(values[1]))
    }

    private func isCountedIngredient(_ name: String) -> Bool {
        let value = normalized(name)
        let countedTerms: [String] = [
            "tomate", "zwiebel", "fruhlingszwiebel", "knoblauchzehe", "paprika",
            "apfel", "birne", "zitrone", "orange", "kartoffel", "carotte"
        ]
        return countedTerms.contains(where: value.contains)
    }

    private func isNutrition(_ name: String) -> Bool {
        let value = normalized(name)
        return ["kcal", "kj", "kalorien", "energie", "eiweiss", "protein", "fett", "kohlenhydrate"]
            .contains(where: value.hasPrefix)
    }

    private func isTimeOrTemperature(unit: String, name: String) -> Bool {
        let value = normalized(unit + " " + name)
        return value.hasPrefix("min") || value.hasPrefix("std")
            || value.hasPrefix("stunde") || value.hasPrefix("grad")
    }

    private func semanticClauseParts(_ text: String) -> [String] {
        let transitions = #"\s+(?=(?:Danach|Dann|Anschließend|Nun|Zum Schluss|Enfin|Puis|Ensuite)\b)"#
        let withBreaks = text.replacingOccurrences(
            of: transitions,
            with: "\n",
            options: [.regularExpression, .caseInsensitive]
        )
        return withBreaks.split(separator: "\n").flatMap { sentenceParts(String($0)) }
            .map(cleanedLine)
            .filter { isUsefulInstruction($0) }
    }

    private func detectedDescriptionUnderTitle() -> String? {
        guard let firstPage = lines.map(\.page).min() else { return nil }
        let pageLines = lines.filter { $0.page == firstPage }
        guard let maximumHeight = pageLines.map(\.boundingBox.height).max() else { return nil }

        let largeLines = pageLines.filter {
            $0.boundingBox.height >= maximumHeight * 0.72
                && isPlausibleTitle($0.text)
        }
        guard let titleTopY = largeLines.map(\.y).max() else { return nil }
        let titleBand = largeLines.filter { $0.y >= titleTopY - 0.10 }
        guard let titleBottomY = titleBand.map(\.boundingBox.minY).min() else { return nil }

        let componentNames: Set<String> = [
            "sauerteig", "hauptteig", "vorteig", "bruhstuck", "quellstuck",
            "kochstuck", "teig", "fullung", "belag", "glasur", "guss"
        ]
        let structureY = pageLines.filter {
            let value = normalized($0.text)
            return value.contains("planungsbeispiel") || componentNames.contains(value)
        }.map(\.boundingBox.maxY).max() ?? 0

        let descriptionLines = pageLines.filter { line in
            line.boundingBox.maxY < titleBottomY - 0.015
                && line.boundingBox.minY > structureY + 0.025
                && line.text.count > 8
                && !line.text.contains("%")
                && !containsClockTime(line.text)
        }.sorted {
            if abs($0.y - $1.y) > 0.008 { return $0.y > $1.y }
            return $0.x < $1.x
        }.map(\.text)

        let description = descriptionLines.joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return description.isEmpty ? nil : description
    }

    private func detectedSummary(in source: [String]) -> String {
        let joined = source.joined(separator: " ")
        if let values = captures(#"Introduction\s*:\s*(.+?)(?=(?:Ingrédients|Ingredients|Zutaten|Préparation|Zubereitung)\s*:|$)"#, in: joined),
           let introduction = values.first {
            return cleanedLine(introduction)
        }
        if let portionLine = source.first(where: {
            let value = normalized($0)
            return value.contains("portion") || value.contains("springform") || value.contains("form von")
        }) {
            return cleanedLine(portionLine.trimmingCharacters(in: CharacterSet(charactersIn: "()")))
        }
        if let descriptiveLine = source.first(where: {
            let value = normalized($0)
            return (value.hasPrefix("ce ") || value.hasPrefix("cette ") || value.hasPrefix("ideal "))
                && $0.count >= 20
        }) {
            return cleanedLine(descriptiveLine)
        }
        return "Aus einer Rezeptvorlage importiert"
    }

    private func detectedLanguage(in source: [String]) -> String {
        let value = normalized(source.joined(separator: " "))
        let frenchTerms = ["ingredients", "prechauffez", "melangez", "ajoutez", "cuire", "four", "oeufs"]
        let germanTerms = ["zutaten", "zubereitung", "backofen", "mischen", "kneten", "eier"]
        let frenchScore = frenchTerms.filter(value.contains).count
        let germanScore = germanTerms.filter(value.contains).count
        return frenchScore > germanScore ? "fr" : "de"
    }

    private func inferredGeneralTags(from title: String) -> [String] {
        let value = normalized(title)
        let candidates: [(terms: [String], tag: String)] = [
            (["brot", "kruste", "baguette"], "Brot"),
            (["quiche", "tarte"], "Quiche"),
            (["cake", "kuchen"], "Kuchen"),
            (["lachs", "saumon"], "Lachs"),
            (["feta"], "Feta"),
            (["krauter", "herbes"], "Kräuter")
        ]
        return candidates.compactMap { candidate in
            candidate.terms.contains(where: value.contains) ? candidate.tag : nil
        }
    }

    /// The heading the document request marked as the page title, already
    /// joined across the lines it wraps into.
    private func structureTitle() -> String? {
        guard let page = lines.map(\.page).min(),
              let title = structures.first(where: { $0.page == page })?.title,
              title.count >= 3,
              isPlausibleTitle(title) else {
            return nil
        }
        return title
    }

    private func detectedMultilineTitle() -> String? {
        guard let firstPage = lines.map(\.page).min() else { return nil }
        let pageLines = lines.filter { $0.page == firstPage }
        guard let maximumHeight = pageLines.map(\.boundingBox.height).max(),
              maximumHeight > 0 else {
            return nil
        }

        let largeTitleCandidates = pageLines.filter { line in
            line.boundingBox.height >= maximumHeight * 0.72
                && line.x < 0.75
                && isPlausibleTitle(line.text)
                && !isIngredientHeading(normalized(line.text))
                && !isInstructionHeading(normalized(line.text))
        }
        guard let titleTopY = largeTitleCandidates.map(\.y).max() else { return nil }

        // Only combine large lines in the compact band at the top of the page.
        // Ratings and later recipe paragraphs can use a similarly large font.
        let titleLines = largeTitleCandidates.filter {
            $0.y >= titleTopY - 0.10
        }.sorted {
            if abs($0.y - $1.y) > 0.01 { return $0.y > $1.y }
            return $0.x < $1.x
        }

        let title = titleLines.map(\.text).joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return title.count >= 3 ? title : nil
    }

    private func mergedSpatialRows(_ source: [RecognizedRecipeLine]) -> [RecognizedRecipeLine] {
        let ordered = source.sorted {
            if abs($0.y - $1.y) > 0.008 { return $0.y > $1.y }
            return $0.x < $1.x
        }
        var rows: [RecognizedRecipeLine] = []

        for line in ordered {
            guard let last = rows.last,
                  last.page == line.page,
                  abs(last.y - line.y) <= 0.008 else {
                rows.append(line)
                continue
            }

            let gap = line.boundingBox.minX - last.boundingBox.maxX
            guard gap < 0.08 else {
                rows.append(line)
                continue
            }

            // Merging joins the fragments of a table row ("295g" + its name).
            // A whole document paragraph shares a baseline with the OCR lines it
            // is made of, and gluing the two together duplicates its sentences
            // inside the recognized steps.
            guard last.text.count < 45, line.text.count < 45 else {
                rows.append(line)
                continue
            }

            rows[rows.count - 1] = RecognizedRecipeLine(
                page: last.page,
                text: last.text + " " + line.text,
                boundingBox: last.boundingBox.union(line.boundingBox)
            )
        }
        return rows
    }

    /// The gutter between the two text columns. Halving the distance between the
    /// outermost headings puts the divider inside the left column whenever the
    /// left headings sit in the page margin while the right one is indented into
    /// its table: the percentage column of the left table then counts as part of
    /// the right column, and its values get merged onto the right column's
    /// amounts. The body lines of the right column locate the gutter instead.
    private func detectedColumnDivider(
        in bandLines: [RecognizedRecipeLine],
        leftHeadingX: CGFloat,
        rightHeadingX: CGFloat
    ) -> CGFloat {
        let fallback = (leftHeadingX + rightHeadingX) / 2
        guard let rightEdge = bandLines
            .filter({ $0.boundingBox.minX >= rightHeadingX - 0.03 })
            .map({ $0.boundingBox.minX })
            .min() else {
            return fallback
        }
        let leftEdge = bandLines
            .filter { $0.boundingBox.maxX <= rightEdge }
            .map { $0.boundingBox.maxX }
            .max() ?? leftHeadingX
        let divider = (leftEdge + rightEdge) / 2
        return divider > leftHeadingX + 0.10 ? divider : fallback
    }

    /// Removes the sentences that `recognizeDocumentLines` delivers twice: it
    /// returns both a whole document paragraph and the classic OCR lines it is
    /// made of, and keeping both turns every sentence into a second step. A line
    /// that a longer paragraph already contains is therefore dropped.
    ///
    /// Component headings survive regardless — "Quellstück" is contained in the
    /// paragraph "Die Quellstückzutaten mischen …" without being a duplicate of
    /// it, and dropping it would take the component's steps with it.
    private func deduplicatedParagraphs(_ source: [String]) -> [String] {
        func canonical(_ value: String) -> String {
            normalized(value.replacingOccurrences(
                of: #"-\s+"#,
                with: "",
                options: .regularExpression
            ))
        }

        var seen: Set<String> = []
        let unique = source.filter { line in
            recipeComponentHeading(line) != nil || seen.insert(canonical(line)).inserted
        }
        let paragraphs = unique.filter { $0.count >= 45 }

        return unique.filter { candidate in
            guard recipeComponentHeading(candidate) == nil else { return true }
            let candidateValue = canonical(candidate)
            return !paragraphs.contains { paragraph in
                let paragraphValue = canonical(paragraph)
                return paragraphValue != candidateValue
                    && paragraphValue.count > candidateValue.count + 8
                    && paragraphValue.contains(candidateValue)
            }
        }
    }

    /// A clock time of the planning table, such as "20.00 Uhr". Testing for the
    /// substring "uhr" instead discards every German mixing instruction as well,
    /// because the diacritic-insensitive form of "verrühren" contains it — which
    /// is how "Die Zutaten verrühren und 12 Stunden bei" and with it the
    /// duration of the first component step went missing.
    private func containsClockTime(_ text: String) -> Bool {
        text.range(
            of: #"\bUhr\b"#,
            options: [.regularExpression, .caseInsensitive]
        ) != nil
            || text.range(of: #"\b\d{1,2}[.:]\d{2}\b"#, options: .regularExpression) != nil
    }

    /// A row of the percentage column of a baker's-percentage table, such as
    /// "13 %" or "60,35 %". It carries no ingredient, and left where it is it
    /// would be glued onto a neighbouring amount by ``mergedSpatialRows``.
    private func isPercentageOnly(_ text: String) -> Bool {
        text.range(
            of: #"^\s*\d+(?:[.,]\d+)?\s*%\s*$"#,
            options: .regularExpression
        ) != nil
    }

    /// Joins a wrapped parenthetical ingredient name with its continuation, for
    /// example "98 g Walnüsse (geröstet, grob" + "gehackt)". The unclosed
    /// parenthesis identifies the continuation, so an indented line that closes
    /// nothing — "gesamte Sauerteigstufe 1" — stays a row of its own.
    private func mergedContinuationRows(
        _ source: [RecognizedRecipeLine]
    ) -> [RecognizedRecipeLine] {
        var rows: [RecognizedRecipeLine] = []
        for line in source {
            let openParentheses = rows.last.map { last in
                last.text.filter { $0 == "(" }.count > last.text.filter { $0 == ")" }.count
            } ?? false
            guard let last = rows.last,
                  last.page == line.page,
                  last.y - line.y <= 0.04,
                  line.boundingBox.minX > last.boundingBox.minX + 0.02,
                  openParentheses,
                  line.text.contains(")"),
                  line.text.range(of: #"^\s*\d"#, options: .regularExpression) == nil else {
                rows.append(line)
                continue
            }
            rows[rows.count - 1] = RecognizedRecipeLine(
                page: last.page,
                text: last.text + " " + line.text,
                boundingBox: last.boundingBox.union(line.boundingBox)
            )
        }
        return rows
    }

    /// Ingredients of a component table row. Such a row begins with its amount,
    /// so an unrecognized unit is a gram value whose "g" the OCR lost — unlike a
    /// number inside a sentence, which must not become an ingredient.
    private func tableIngredients(in text: String) -> [ParsedIngredient] {
        let repaired = repairedTableRow(text)
        let startsWithAmount = repaired.range(
            of: #"^\s*\d"#,
            options: .regularExpression
        ) != nil
        return ingredientsInProse(repaired).compactMap { ingredient in
            guard !ingredient.unit.isEmpty
                    || (startsWithAmount && ingredient.name.count <= 40) else {
                return nil
            }
            return ParsedIngredient(
                amount: ingredient.amount,
                unit: ingredient.unit.isEmpty ? "g" : ingredient.unit,
                name: repairedIngredientName(ingredient.name)
            )
        }
    }

    /// Restores compound ingredient names that the OCR broke apart:
    /// "Roggenvol kornmeh" and "Anstel gut" are what Vision returns for
    /// "Roggenvollkornmehl" and "Anstellgut" in small table type — custom words
    /// do not repair them, because the glyphs themselves are lost. Matching
    /// ignores spaces, keeps any parenthetical suffix and tolerates two lost
    /// characters, so unrelated names stay untouched.
    private func repairedIngredientName(_ name: String) -> String {
        let head: String
        let tail: String
        if let parenthesis = name.firstIndex(of: "(") {
            head = String(name[..<parenthesis]).trimmingCharacters(in: .whitespaces)
            tail = " " + name[parenthesis...]
        } else {
            head = name
            tail = ""
        }

        let condensed = normalized(head).replacingOccurrences(of: " ", with: "")
        guard condensed.count >= 8 else { return name }

        for word in RecipeImageAnalysisAgent.bakingVocabulary {
            let candidate = normalized(word).replacingOccurrences(of: " ", with: "")
            guard abs(candidate.count - condensed.count) <= 2,
                  editDistance(condensed, candidate) <= 2 else {
                continue
            }
            return word + tail
        }
        return name
    }

    private func editDistance(_ first: String, _ second: String) -> Int {
        let source = Array(first)
        let target = Array(second)
        var previous = Array(0...target.count)

        for (sourceIndex, sourceCharacter) in source.enumerated() {
            var current = [sourceIndex + 1] + Array(repeating: 0, count: target.count)
            for (targetIndex, targetCharacter) in target.enumerated() {
                current[targetIndex + 1] = sourceCharacter == targetCharacter
                    ? previous[targetIndex]
                    : min(previous[targetIndex], previous[targetIndex + 1], current[targetIndex]) + 1
            }
            previous = current
        }
        return previous[target.count]
    }

    /// Cleans a component table row. The dotted rules of the table end up in the
    /// recognized text ("73g..", ".295g", "....gesamtes Quellstück") and keep the
    /// amount pattern from matching, so the row would be dropped. Where the gram
    /// sign itself was read as an 8 — "63 g" as "63 8", "73 g" as "738." — the
    /// stray 8 is restored, but only when a space or a dotted rule separates it
    /// from the amount; the amount of "48 Walnüsse" stays 48.
    private func repairedTableRow(_ text: String) -> String {
        let value = text
            .replacingOccurrences(of: #"\.{2,}"#, with: " ", options: .regularExpression)
            .replacingOccurrences(of: #"^\s*\.+"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"(?<=\s)\.(?=\S)"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"\s\.(?=\s|$)"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"\s{2,}"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespaces)

        guard value.range(
            of: #"^\d+(?:[.,]\d+)?\s*(?:kg|g|mg|l|dl|cl|ml|EL|TL)\b"#,
            options: [.regularExpression, .caseInsensitive]
        ) == nil else {
            return value
        }
        return value.replacingOccurrences(
            of: #"^(\d+)(?:\s+8\b|8\.+)"#,
            with: "$1 g",
            options: .regularExpression
        )
    }

    /// The baker's percentage printed on the same baseline as an ingredient row,
    /// in the same column.
    private func percentageValue(
        near row: RecognizedRecipeLine,
        isLeftColumn: Bool,
        columnDivider: CGFloat,
        in bandLines: [RecognizedRecipeLine]
    ) -> Double? {
        let candidates = bandLines.filter { line in
            guard isPercentageOnly(line.text) else { return false }
            let isInColumn = isLeftColumn
                ? line.x < columnDivider
                : line.x >= columnDivider
            return isInColumn && abs(line.y - row.y) <= 0.012
        }
        guard let closest = candidates.min(by: {
            abs($0.y - row.y) < abs($1.y - row.y)
        }) else {
            return nil
        }
        return Double(
            closest.text
                .replacingOccurrences(of: "%", with: "")
                .replacingOccurrences(of: ",", with: ".")
                .trimmingCharacters(in: .whitespaces)
        )
    }

    /// Baker's percentages make a mis-read amount detectable without guessing:
    /// every row of a component table shares the same amount-per-percent ratio,
    /// namely the recipe's total flour weight. "127 g" that Vision returned as
    /// "1278" breaks that ratio by a factor of ten, and dropping the trailing
    /// digit — the mis-read gram sign — restores it. Amounts whose ratio already
    /// agrees, and amounts that dropping a digit does not reconcile, stay as
    /// they are.
    /// Whether the data detector resolved a mass of this value somewhere on the
    /// row. It reads the glyphs independently of the amount pattern, so this is
    /// evidence about the amount that the text alone cannot give.
    private func detectedMass(_ value: Double, on row: RecognizedRecipeLine) -> Bool {
        structures.first { $0.page == row.page }?.amounts.contains { amount in
            amount.isMass
                && abs(amount.value - value) < 0.01
                && amount.boundingBox.midY >= row.boundingBox.minY - 0.004
                && amount.boundingBox.midY <= row.boundingBox.maxY + 0.004
        } ?? false
    }

    /// Whether the number at the start of the row is a temperature rather than
    /// an amount — "50 °C Wasser" instead of "50 g Wasser". Only the detector
    /// knows, because a degree sign lost to the OCR leaves a bare number. A
    /// temperature printed at the end of the row, as recipes usually do, is
    /// outside the leading column and does not count.
    private func isLeadingTemperature(_ value: Double, on row: RecognizedRecipeLine) -> Bool {
        guard !detectedMass(value, on: row) else { return false }
        return structures.first { $0.page == row.page }?.amounts.contains { amount in
            amount.isTemperature
                && abs(amount.value - value) < 0.01
                && amount.boundingBox.midY >= row.boundingBox.minY - 0.004
                && amount.boundingBox.midY <= row.boundingBox.maxY + 0.004
                && amount.boundingBox.minX <= row.boundingBox.minX + 0.05
        } ?? false
    }

    private func repairImplausibleAmounts(
        in rows: inout [(String, ParsedIngredient)],
        percentages: [(index: Int, percentage: Double, row: RecognizedRecipeLine)]
    ) {
        let ratios = percentages.compactMap { entry -> Double? in
            guard rows.indices.contains(entry.index), entry.percentage > 0 else { return nil }
            return rows[entry.index].1.amount / entry.percentage
        }.sorted()

        guard ratios.count >= 4 else { return }
        let reference = ratios[ratios.count / 2]
        guard reference > 0 else { return }

        for entry in percentages {
            guard rows.indices.contains(entry.index), entry.percentage > 0 else { continue }
            let ingredient = rows[entry.index].1
            // Where the detector confirms this very amount as a mass, the
            // amount is sound and it is the percentage that was mis-read.
            guard !detectedMass(ingredient.amount, on: entry.row) else { continue }
            let ratio = ingredient.amount / entry.percentage
            guard abs(ratio - reference) > reference * 0.25 else { continue }

            let digits = String(Int(ingredient.amount))
            guard digits.count > 1, let shortened = Double(digits.dropLast()) else { continue }
            guard abs(shortened / entry.percentage - reference) <= reference * 0.10 else { continue }

            rows[entry.index].1 = ParsedIngredient(
                amount: shortened,
                unit: ingredient.unit,
                name: ingredient.name
            )
        }
    }

    private func spatialComponentSections() -> (
        introduction: [String],
        ingredients: [(String, ParsedIngredient)],
        instructions: [String]
    )? {
        let standaloneNames: Set<String> = [
            "sauerteig", "sauerteigstufe", "sauerteigstufe 1", "sauerteigstufe i", "sauerteigstufe 2",
            "sauerteigstufe ii", "hauptteig", "vorteig", "bruhstuck", "quellstuck",
            "kochstuck", "teig", "fullung", "belag", "glasur", "guss"
        ]
        var headings = lines.compactMap { line -> (line: RecognizedRecipeLine, name: String)? in
            let value = normalized(line.text)
            guard standaloneNames.contains(value),
                  let name = recipeComponentHeading(line.text) else {
                return nil
            }
            return (line, name)
        }

        // If OCR misses the small first-stage heading, infer its rectangle from
        // the ingredient rows between the planning table and Sauerteigstufe 2.
        if !headings.contains(where: { $0.name == "Sauerteigstufe 1" }),
           let secondStage = headings.first(where: { $0.name == "Sauerteigstufe 2" }) {
            let candidates = lines.filter { line in
                guard line.page == secondStage.line.page,
                      line.x < 0.48,
                      line.y > secondStage.line.y + 0.02 else {
                    return false
                }
                let withoutPercentage = line.text.replacingOccurrences(
                    of: #"\s+\d+(?:[.,]\d+)?\s*%\s*$"#,
                    with: "",
                    options: .regularExpression
                )
                return !ingredientsInProse(withoutPercentage).isEmpty
            }
            if let topIngredient = candidates.max(by: { $0.y < $1.y }) {
                let inferredBox = CGRect(
                    x: secondStage.line.x,
                    y: topIngredient.boundingBox.maxY + 0.008,
                    width: max(secondStage.line.boundingBox.width, 0.20),
                    height: secondStage.line.boundingBox.height
                )
                headings.append((
                    RecognizedRecipeLine(
                        page: secondStage.line.page,
                        text: "Sauerteigstufe 1",
                        boundingBox: inferredBox
                    ),
                    "Sauerteigstufe 1"
                ))
            }
        }

        guard headings.count >= 2,
              let page = headings.first?.line.page,
              headings.allSatisfy({ $0.line.page == page }) else {
            return nil
        }

        let orderedHeadings = headings.sorted {
            if $0.name == "Hauptteig" { return false }
            if $1.name == "Hauptteig" { return true }
            if abs($0.line.y - $1.line.y) > 0.02 { return $0.line.y > $1.line.y }
            return $0.line.x < $1.line.x
        }
        let pageLines = lines.filter { $0.page == page }
        let headingPositions = headings.map { $0.line.x }.sorted()
        guard let leftHeadingX = headingPositions.first,
              let rightHeadingX = headingPositions.last,
              rightHeadingX - leftHeadingX > 0.15 else {
            return nil
        }
        let planningHeadingY = pageLines.first {
            normalized($0.text).contains("planungsbeispiel")
        }?.y
        // Only the two-column band carries the gutter; title and introduction
        // span the full page width and would mask it.
        let topHeadingY = headings.map { $0.line.y }.max() ?? 1
        let bandLines = pageLines.filter {
            $0.y < (planningHeadingY ?? topHeadingY) + 0.02
        }
        let columnDivider = detectedColumnDivider(
            in: bandLines,
            leftHeadingX: leftHeadingX,
            rightHeadingX: rightHeadingX
        )
        var ingredientRows: [(String, ParsedIngredient)] = []
        var instructionRows: [String] = []
        var rowPercentages: [(index: Int, percentage: Double, row: RecognizedRecipeLine)] = []
        let lowestLeftHeading = headings
            .filter { $0.line.x < columnDivider }
            .min { $0.line.y < $1.line.y }
        let highestRightHeading = headings
            .filter { $0.line.x >= columnDivider }
            .max { $0.line.y < $1.line.y }

        for heading in orderedHeadings {
            let isLeftColumn = heading.line.x < columnDivider
            let nextHeadingBelow = headings
                .filter { candidate in
                    let candidateIsLeft = candidate.line.x < columnDivider
                    return candidateIsLeft == isLeftColumn
                        && candidate.line.y < heading.line.y - 0.01
                }
                .max { $0.line.y < $1.line.y }
            let lowerBoundary = nextHeadingBelow.map { $0.line.y + 0.01 } ?? 0

            // Each component owns a geometric rectangle: its column, below its
            // heading, and above the next component heading in the same column.
            let columnLines = mergedContinuationRows(mergedSpatialRows(pageLines.filter { line in
                let isInColumn = isLeftColumn
                    ? line.x < columnDivider
                    : line.x >= columnDivider
                return isInColumn
                    && line.y < heading.line.y - 0.01
                    && line.y > lowerBoundary
                    && !isPercentageOnly(line.text)
            }))

            var lastIngredientY: CGFloat?
            var foundIngredient = false
            var inlineInstructions: [String] = []
            for line in columnLines {
                let ingredientText = line.text.replacingOccurrences(
                    of: #"\s+\d+(?:[.,]\d+)?\s*%\s*$"#,
                    with: "",
                    options: .regularExpression
                )
                let proseIngredients = tableIngredients(in: ingredientText).filter { ingredient in
                    !isLeadingTemperature(ingredient.amount, on: line)
                }
                if !proseIngredients.isEmpty {
                    if proseIngredients.count == 1,
                       let percentage = percentageValue(
                           near: line,
                           isLeftColumn: isLeftColumn,
                           columnDivider: columnDivider,
                           in: bandLines
                       ) {
                        rowPercentages.append((ingredientRows.count, percentage, line))
                    }
                    ingredientRows.append(contentsOf: proseIngredients.map { (heading.name, $0) })
                    lastIngredientY = line.y
                    foundIngredient = true
                    if let actionRange = line.text.range(
                        of: #"\bAlle\s+Zutaten\b"#,
                        options: [.regularExpression, .caseInsensitive]
                    ) {
                        inlineInstructions.append(String(line.text[actionRange.lowerBound...]))
                        break
                    }
                    continue
                }

                if let dependencyName = componentDependencyName(from: line.text) {
                    ingredientRows.append((
                        heading.name,
                        ParsedIngredient(amount: 0, unit: "", name: dependencyName)
                    ))
                    lastIngredientY = line.y
                    foundIngredient = true
                    continue
                }

                if foundIngredient, isActionInstruction(line.text) {
                    break
                }
            }

            guard let ingredientBottomY = lastIngredientY else { continue }
            let proseLines = columnLines.filter {
                $0.y < ingredientBottomY - 0.015
                    && !$0.text.contains("%")
                    && !containsClockTime($0.text)
            }.map(\.text)
            // Preserve short continuation lines such as “Teig kneten.”
            // and “und falten.”; dropping them merges separate paragraphs and
            // removes the action needed for timed folding interventions.
            var usefulProse = inlineInstructions + proseLines.filter { line in
                let value = normalized(line)
                return line.trimmingCharacters(in: .whitespacesAndNewlines).count >= 3
                    && recipeComponentHeading(line) == nil
                    && !isIngredientHeading(value)
                    && !isInstructionHeading(value)
            }

            // A component that starts at the bottom of the left column can
            // continue at the top of the right column before its first heading.
            if heading.line.page == lowestLeftHeading?.line.page,
               heading.line.boundingBox == lowestLeftHeading?.line.boundingBox,
               let rightHeading = highestRightHeading {
                let upperBoundary = (planningHeadingY ?? 1) + 0.025
                let overflowLines = pageLines.filter { line in
                    line.x >= rightHeading.line.x - 0.02
                        && line.y > rightHeading.line.y + 0.01
                        && line.y < upperBoundary
                        && !containsClockTime(line.text)
                        && !line.text.contains("%")
                }.sorted {
                    if abs($0.y - $1.y) > 0.008 { return $0.y > $1.y }
                    return $0.x < $1.x
                }.map(\.text)
                usefulProse.append(contentsOf: overflowLines)
            }

            if !usefulProse.isEmpty {
                instructionRows.append(heading.name)
                instructionRows.append(contentsOf: deduplicatedParagraphs(usefulProse))
            }
        }

        repairImplausibleAmounts(in: &ingredientRows, percentages: rowPercentages)

        guard !ingredientRows.isEmpty, !instructionRows.isEmpty else { return nil }
        let highestHeadingY = headings.map { $0.line.y }.max() ?? 0
        let introduction = pageLines.filter {
            $0.y > highestHeadingY + 0.02
                && !$0.text.localizedCaseInsensitiveContains("PLANUNGSBEISPIEL")
                && !containsClockTime($0.text)
        }.sorted {
            if abs($0.y - $1.y) > 0.008 { return $0.y > $1.y }
            return $0.x < $1.x
        }.map(\.text)

        return (introduction, ingredientRows, instructionRows)
    }

    private func spatialSectionLines() -> (
        introduction: [String],
        ingredients: [String],
        instructions: [String]
    )? {
        guard let ingredientHeading = lines.first(where: { isIngredientHeading(normalized($0.text)) }) else {
            return nil
        }

        let instructionHeadings = lines.filter {
            $0.page == ingredientHeading.page
                && isInstructionHeading(normalized($0.text))
        }

        // A word such as “Préparation” can occur twice: once in the metadata
        // (“Préparation: 10 minutes”) and once as the actual section heading.
        // For stacked layouts, always prefer the heading below INGREDIENTS.
        let stackedInstructionHeading = instructionHeadings
            .filter { $0.y < ingredientHeading.y - 0.04 }
            .max { $0.y < $1.y }
        let sideBySideInstructionHeading = instructionHeadings
            .filter { $0.x > ingredientHeading.x }
            .min { $0.x < $1.x }

        guard let instructionHeading = stackedInstructionHeading ?? sideBySideInstructionHeading else {
            return nil
        }

        let pageLines = lines.filter { $0.page == ingredientHeading.page }
        let nutritionHeadingY = pageLines.first(where: {
            let value = normalized($0.text)
            return value.hasPrefix("nahrwerte") || value.hasPrefix("nutrition")
        })?.y

        // Single-column pages place PREPARATION below INGREDIENTS. Vision's
        // coordinates start at the lower-left, so ingredientHeading.y is larger.
        if ingredientHeading.y > instructionHeading.y + 0.04 {
            let introduction = pageLines.filter {
                $0.y > ingredientHeading.y + 0.01
                    && !isIngredientHeading(normalized($0.text))
                    && !isInstructionHeading(normalized($0.text))
            }.sorted {
                if abs($0.y - $1.y) > 0.008 { return $0.y > $1.y }
                return $0.x < $1.x
            }.map(\.text)

            let ingredients = pageLines.filter {
                $0.y < ingredientHeading.y - 0.01
                    && $0.y > instructionHeading.y + 0.01
            }.sorted {
                if abs($0.y - $1.y) > 0.008 { return $0.y > $1.y }
                return $0.x < $1.x
            }.map(\.text)

            let instructions = pageLines.filter {
                $0.y < instructionHeading.y - 0.01
            }.sorted {
                if abs($0.y - $1.y) > 0.008 { return $0.y > $1.y }
                return $0.x < $1.x
            }.map(\.text)

            return (introduction, ingredients, instructions)
        }

        // Two-column recipe pages retain the existing left/right separation.
        guard ingredientHeading.x < instructionHeading.x else { return nil }
        let divider = (ingredientHeading.boundingBox.maxX + instructionHeading.x) / 2
        let introduction = pageLines.filter {
            $0.y > min(ingredientHeading.y, instructionHeading.y) + 0.02
                && !isIngredientHeading(normalized($0.text))
                && !isInstructionHeading(normalized($0.text))
        }.map(\.text)

        let ingredients = pageLines.filter { line in
            let isAboveNutrition = nutritionHeadingY.map { line.y > $0 + 0.01 } ?? true
            return line.y < ingredientHeading.y - 0.01
                && line.x < divider
                && isAboveNutrition
        }.sorted { $0.y > $1.y }.map(\.text)

        let instructions = pageLines.filter {
            $0.y < instructionHeading.y - 0.01
                && $0.x >= divider
        }.sorted { $0.y > $1.y }.map(\.text)

        return (introduction, ingredients, instructions)
    }

    private func parseIngredientSection(_ source: [String]) -> [(String, ParsedIngredient)] {
        var componentName = "Zutaten"
        var results: [(String, ParsedIngredient)] = []
        for line in source {
            if let ingredient = parseIngredient(line) {
                results.append((componentName, ingredient))
            } else if isComponentHeading(line) {
                componentName = line.trimmingCharacters(in: CharacterSet(charactersIn: ": "))
            }
        }
        return results
    }

    private func assignIngredientsToComponents(
        _ ingredients: [(String, ParsedIngredient)],
        using instructionLines: [String]
    ) -> [(String, ParsedIngredient)] {
        var blocks: [(name: String, text: String)] = []
        var currentName: String?

        for line in instructionLines {
            if let heading = recipeComponentHeading(line) {
                currentName = heading
                blocks.append((heading, ""))
            } else if currentName != nil, let lastIndex = blocks.indices.last {
                blocks[lastIndex].text += " " + line
            }
        }

        guard blocks.count >= 2 else { return ingredients }

        let normalizedNames = ingredients.map { normalized($0.1.name) }
        var assignedIndices = Set<Int>()
        var result: [(String, ParsedIngredient)] = []

        for block in blocks {
            let blockText = normalized(block.text)
            for (index, row) in ingredients.enumerated() where !assignedIndices.contains(index) {
                let ingredientName = normalizedNames[index]
                let sameNameCount = normalizedNames.filter { $0 == ingredientName }.count
                let nameWords = ingredientName.split(separator: " ")
                    .map(String.init)
                    .filter { $0.count >= 4 }
                let containsName = nameWords.contains(where: blockText.contains)
                let amountText = row.1.amount.formatted(
                    .number.locale(Locale(identifier: "de_DE"))
                        .precision(.fractionLength(0...2))
                )
                let containsAmount = blockText.contains(normalized(amountText))

                if containsName && (containsAmount || sameNameCount == 1) {
                    result.append((
                        block.name,
                        ingredientWithTemperature(row.1, from: block.text)
                    ))
                    assignedIndices.insert(index)
                }
            }

            if normalized(block.name) == "hauptteig" {
                for referencedComponent in ["Sauerteig", "Brühstück"] where blockText.contains(normalized(referencedComponent)) {
                    result.append((
                        block.name,
                        ParsedIngredient(amount: 0, unit: "", name: referencedComponent)
                    ))
                }
            }
        }

        for (index, row) in ingredients.enumerated() where !assignedIndices.contains(index) {
            result.append((row.0, row.1))
        }
        return result
    }

    private func ingredientWithTemperature(
        _ ingredient: ParsedIngredient,
        from componentText: String
    ) -> ParsedIngredient {
        let amount = ingredient.amount.formatted(
            .number.locale(Locale(identifier: "de_DE"))
                .precision(.fractionLength(0...2))
        )
        let escapedAmount = NSRegularExpression.escapedPattern(for: amount)
        let escapedUnit = NSRegularExpression.escapedPattern(for: ingredient.unit)
        let escapedName = NSRegularExpression.escapedPattern(for: ingredient.name)
        let pattern = #"\b"# + escapedAmount
            + #"(?:[.,]0+)?\s*"# + escapedUnit
            + #"\s+"# + escapedName
            + #"\s*\(?\s*(-?\d{1,3}(?:[.,]\d+)?)\s*(?:°\s*C|Grad(?:\s+Celsius)?)"#

        guard let values = captures(pattern, in: componentText),
              let temperature = values.first,
              !temperature.isEmpty else {
            return ingredient
        }

        return ParsedIngredient(
            amount: ingredient.amount,
            unit: ingredient.unit,
            name: "\(ingredient.name) (\(temperature.replacingOccurrences(of: ",", with: ".")) °C)"
        )
    }

    private func componentDependencyName(from line: String) -> String? {
        let value = normalized(line)
        guard value.hasPrefix("gesamte") || value.hasSuffix(" gesamt") else { return nil }

        if value.contains("sauerteigstufe 2") { return "gesamte Sauerteigstufe 2" }
        if value.contains("sauerteigstufe 1") { return "gesamte Sauerteigstufe 1" }
        if value.contains("sauerteig") { return "gesamter Sauerteig" }
        if value.contains("quellstuck") { return "gesamtes Quellstück" }
        if value.contains("bruhstuck") { return "gesamtes Brühstück" }
        if value.contains("vorteig") { return "gesamter Vorteig" }
        return nil
    }

    private func recipeComponentHeading(_ line: String) -> String? {
        let value = normalized(line)
        guard line.count <= 40, line.split(separator: " ").count <= 4 else { return nil }

        if value == "sauerteigstufe"
            || value == "sauerteigstufe 1"
            || value == "sauerteigstufe i" {
            return "Sauerteigstufe 1"
        }
        if value == "sauerteigstufe 2" || value == "sauerteigstufe ii" {
            return "Sauerteigstufe 2"
        }
        if value.contains("sauerteig") { return "Sauerteig" }
        if value.contains("bruhstuck") { return "Brühstück" }
        if value == "hauptteig" { return "Hauptteig" }
        if value == "vorteig" { return "Vorteig" }
        if value == "quellstuck" { return "Quellstück" }
        if value == "kochstück" || value == "kochstuck" { return "Kochstück" }
        if value == "teig" || value == "pate" { return "Teig" }
        if value == "fullung" || value == "farce" || value == "garniture" { return "Füllung" }
        if value == "belag" { return "Belag" }
        if value == "glasur" || value == "guss" { return line.trimmingCharacters(in: CharacterSet(charactersIn: ": ")) }
        return nil
    }

    private func parseIngredient(_ line: String) -> ParsedIngredient? {
        guard !line.contains("%"), !containsClockTime(line) else {
            return nil
        }

        let pattern = #"^\s*[•·\-–—]?\s*(\d+(?:[.,]\d+)?|[½¼¾⅓⅔])\s*(kg|g|mg|l|Liter|dl|cl|ml|EL|TL|cuillère à café|cuillère à soupe|cs|c\.?\s*à\.?\s*[cs]\.?|Teelöffel|Esslöffel|Stück|Stk\.?|Würfel|Prise|pinc[eé]e|Bund|Päckchen|Packung|sachet|Tasse|Tassen)?\s+(.+?)\s*$"#
        guard let values = captures(pattern, in: line), values.count == 3 else { return nil }
        let rawName = cleanedIngredientName(values[2])
        var unit = canonicalUnit(values[1])
        let name: String
        if ["cl", "ml", "l"].contains(unit), normalized(rawName) == "it" {
            // Common OCR loss in French ingredient lists: “lait” → “it”.
            name = "lait"
        } else {
            name = rawName
        }

        let normalizedName = normalized(name)
        guard name.count > 1, !isNutrition(name) else { return nil }

        if unit.isEmpty, ["eier", "ei", "oeufs", "oeuf"].contains(normalizedName) {
            unit = "ei"
        } else if unit.isEmpty, isCountedIngredient(name) {
            unit = "Stück"
        }
        return ParsedIngredient(
            amount: numericAmount(values[0]),
            unit: unit,
            name: name
        )
    }

    private func isStepNumberMarker(_ line: String) -> Bool {
        line.range(
            of: #"^\s*\d{1,2}[.)]?\s*$"#,
            options: .regularExpression
        ) != nil
    }

    private struct AnalyzedRecipeStep {
        let step: Double
        let text: String
        let duration: Int
        /// Set for the steps that prepare one component, so the plan can
        /// schedule them in dependency order without reading their wording.
        var componentName: String? = nil
    }

    /// Builds a dependency-aware plan from component headings. Components prepared
    /// before the final dough/dish and not referring to each other are started in
    /// parallel (1.1, 1.2, ...). The remaining actions keep their textual order.
    private func analyzedComponentSteps(_ source: [String]) -> [AnalyzedRecipeStep]? {
        var blocks: [(name: String, text: String)] = []
        for line in source {
            if let heading = recipeComponentHeading(line) {
                blocks.append((heading, ""))
            } else if let index = blocks.indices.last {
                let separator = blocks[index].text.hasSuffix("-") ? "" : " "
                blocks[index].text += separator + line
            }
        }
        guard blocks.count >= 2 else { return nil }

        let finalComponentNames = ["hauptteig", "teig", "fullung", "füllung", "zubereitung"]
        let finalIndex = blocks.lastIndex(where: { finalComponentNames.contains(normalized($0.name)) })
            ?? blocks.index(before: blocks.endIndex)
        let finalName = normalized(blocks[finalIndex].name)
        guard finalName == "hauptteig" else { return nil }
        let preparations = blocks[..<finalIndex].filter { !$0.text.isEmpty }
        let remaining = blocks[finalIndex...]
        guard normalized(blocks[finalIndex].name) == "hauptteig",
              !preparations.isEmpty else { return nil }

        var result: [AnalyzedRecipeStep] = []
        let useParallelNumbers = preparations.count > 1
        for (index, block) in preparations.enumerated() {
            let step = useParallelNumbers ? 1 + Double(index + 1) / 10 : 1
            result.append(AnalyzedRecipeStep(
                step: step,
                text: componentPreparationText(component: block.name, source: block.text),
                duration: estimatedDuration(in: block.text),
                componentName: block.name
            ))
        }

        var nextStep = 2
        for block in remaining {
            for clause in semanticClauseParts(block.text) {
                result.append(AnalyzedRecipeStep(
                    step: Double(nextStep),
                    text: bakingInstructionWithTemperatureChange(condensedIngredientLists(in: clause)),
                    duration: estimatedDuration(in: clause)
                ))
                nextStep += 1
            }
        }
        return result.count >= 2 ? result : nil
    }

    private func estimatedDuration(in text: String) -> Int {
        let value = normalized(text)
        if (value.contains("misch") || value.contains("knet")),
           let phases = captures(
               #"(\d+)\s*Minuten?.*?(\d+)\s*[-–]\s*(\d+)\s*Minuten?"#,
               in: text
           ),
           phases.count == 3,
           let firstPhase = Int(phases[0]),
           let secondMinimum = Int(phases[1]),
           let secondMaximum = Int(phases[2]) {
            let mixingDuration = firstPhase
                + Int(round(Double(secondMinimum + secondMaximum) / 2))
            return value.contains("alle zutaten") ? mixingDuration + 5 : mixingDuration
        }
        if let hours = averageHourRange(in: text) { return hours }
        if let hours = maximumHours(in: text) { return hours }
        if let minutes = averageMinuteRange(in: text) { return minutes }

        let explicitDuration = duration(in: text)
        if explicitDuration > 0 {
            let addsIngredients = value.contains("alle zutaten")
                || value.contains("zutaten zufugen")
                || value.contains("zutaten hinzufugen")
            let mixes = value.contains("misch") || value.contains("knet") || value.contains("ruhr")
            return addsIngredients && mixes ? explicitDuration + 5 : explicitDuration
        }
        if value.contains("vorheiz") || value.contains("prechauff") { return 10 }
        if value.contains("form") || value.contains("falt") || value.contains("rundwirk")
            || value.contains("auslegen") || value.contains("einfull") || value.contains("unterheb") {
            return 5
        }
        if value.contains("misch") || value.contains("knet") || value.contains("ruhr")
            || value.contains("purier") || value.contains("schlag") {
            return 5
        }
        return 0
    }

    private func analyzedNumberedSteps(_ source: [String]) -> [AnalyzedRecipeStep]? {
        var groupedSteps: [(number: Int, text: String)] = []
        var currentIndex: Int?

        for line in source {
            let values = captures(#"^\s*(\d{1,2})[.)]\s*(.*)$"#, in: line)
                ?? captures(#"^\s*(\d{1,2})\s*$"#, in: line).map { [$0[0], ""] }
            if let values,
               values.count == 2,
               let number = Int(values[0]),
               (1...20).contains(number),
               !normalized(values[1]).hasPrefix("std"),
               !normalized(values[1]).hasPrefix("min") {
                groupedSteps.append((number, values[1]))
                currentIndex = groupedSteps.indices.last
            } else if let currentIndex {
                groupedSteps[currentIndex].text += " " + line
            }
        }

        guard groupedSteps.count >= 3 else { return nil }

        var results: [AnalyzedRecipeStep] = []
        for grouped in groupedSteps {
            let text = cleanedLine(grouped.text)
            let value = normalized(text)

            if value.contains("deckel abnehmen"),
               let lidRange = text.range(of: "Dann den Deckel", options: .caseInsensitive) {
                let coveredText = String(text[..<lidRange.lowerBound])
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                let uncoveredText = String(text[lidRange.lowerBound...])
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                results.append(AnalyzedRecipeStep(
                    step: Double(grouped.number),
                    text: coveredText,
                    duration: duration(in: coveredText)
                ))
                results.append(AnalyzedRecipeStep(
                    step: Double(grouped.number + 1),
                    text: uncoveredText,
                    duration: averageMinuteRange(in: uncoveredText)
                        ?? duration(in: uncoveredText)
                ))
                continue
            }

            let plannedDuration: Int
            if grouped.number == 4,
               value.contains("form") || value.contains("falt") || value.contains("einschneid") {
                plannedDuration = 10
            } else {
                plannedDuration = duration(in: text)
            }
            results.append(AnalyzedRecipeStep(
                step: Double(grouped.number),
                text: text,
                duration: plannedDuration
            ))
        }
        return results
    }

    private func averageMinuteRange(in text: String) -> Int? {
        guard let values = captures(#"(\d+)\s*(?:[-–]|à|a)\s*(\d+)\s*(?:Minuten?|Min\.?|mn)"#, in: text),
              values.count == 2,
              let lower = Double(values[0]),
              let upper = Double(values[1]) else {
            return nil
        }
        return Int(((lower + upper) / 2).rounded())
    }

    private func bakingInstructionWithTemperatureChange(_ source: String) -> String {
        let pattern = #"(?:bei\s+)?(\d{2,3})\s*(?:°\s*C|Grad(?:\s+Celsius)?)\s+fallend\s+auf\s+(\d{2,3})\s*(?:°\s*C|Grad(?:\s+Celsius)?)\s+(\d+)\s*Minuten?"#
        guard let expression = try? NSRegularExpression(
            pattern: pattern,
            options: [.caseInsensitive]
        ),
        let match = expression.firstMatch(
            in: source,
            range: NSRange(source.startIndex..., in: source)
        ),
        let preheatRange = Range(match.range(at: 1), in: source),
        let bakingRange = Range(match.range(at: 2), in: source),
        let durationRange = Range(match.range(at: 3), in: source) else {
            return source
        }

        let replacement = "in den auf \(source[preheatRange]) °C vorgeheizten Backofen geben, zum Backbeginn auf \(source[bakingRange]) °C einstellen und \(source[durationRange]) Minuten"
        return expression.stringByReplacingMatches(
            in: source,
            range: NSRange(source.startIndex..., in: source),
            withTemplate: NSRegularExpression.escapedTemplate(for: replacement)
        )
    }

    /// The step text for preparing one component.
    ///
    /// The second form splices the recipe's own sentence at its verb and can
    /// therefore only ever produce German — it is chosen exactly when the source
    /// contains the German "verrühren". The first form only prefixes the
    /// recipe's text and is therefore built in the app's language.
    private func componentPreparationText(component: String, source: String) -> String {
        guard let verbRange = source.range(of: "verrühren", options: .caseInsensitive) else {
            return String(
                format: AppSettings.generatedRecipeTexts().componentPreparationFormat,
                component
            ) + cleanedLine(source)
        }
        return "Alle Zutaten für die Komponente \(component) " + source[verbRange.lowerBound...]
    }

    private func sentenceParts(_ text: String) -> [String] {
        let expression = try? NSRegularExpression(pattern: #"(?<=[.!?])\s+"#)
        let markedText = expression?.stringByReplacingMatches(
            in: text,
            range: NSRange(text.startIndex..., in: text),
            withTemplate: "\n"
        ) ?? text
        return markedText.components(separatedBy: "\n")
            .map(cleanedLine)
            .filter { !$0.isEmpty }
    }

    private func averageHourRange(in text: String) -> Int? {
        guard let values = captures(#"(\d+)\s*[-–]\s*(\d+)\s*Stunden?"#, in: text),
              values.count == 2,
              let lower = Int(values[0]),
              let upper = Int(values[1]) else {
            return nil
        }
        return (lower + upper) * 60 / 2
    }

    private func maximumHours(in text: String) -> Int? {
        guard let values = captures(#"bis\s+zu\s+(\d+)\s*Stunden?"#, in: text),
              let hoursText = values.first,
              let hours = Int(hoursText) else {
            return nil
        }
        return hours * 60
    }

    private func semanticInstructions(_ source: [String]) -> [String] {
        let joined = source
            .filter { recipeComponentHeading($0) == nil }
            .map(removingListMarker)
            .joined(separator: " ")
        let sentences = semanticClauseParts(joined)
        return sentences.isEmpty ? source : sentences
    }

    private func isBakingInstruction(_ text: String) -> Bool {
        let value = normalized(text)
        return value.contains("backen")
            || value.contains("backofen")
            || value.contains("cuire")
            || value.contains("four") && value.range(of: #"\b\d{2,3}\b"#, options: .regularExpression) != nil
            || value.contains("ofen") && value.range(of: #"\b\d{2,3}\b"#, options: .regularExpression) != nil
    }

    private func isIngredientHeading(_ value: String) -> Bool {
        ["zutaten", "zutatenliste", "ingredients"].contains(value)
            || value.hasPrefix("zutaten fur ")
    }

    private func isInstructionHeading(_ value: String) -> Bool {
        ["zubereitung", "anleitung", "ubereitung", "ubereitungsschritte", "methode",
         "instructions", "method", "preparation", "zubereitung und backen"].contains(value)
    }

    private func isComponentHeading(_ line: String) -> Bool {
        let value = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard value.count >= 3, value.count <= 45 else { return false }
        return value.hasSuffix(":")
            || value == value.uppercased(with: Locale(identifier: "de_DE"))
    }

    private func isPlausibleTitle(_ line: String) -> Bool {
        let value = normalized(line)
        guard line.count >= 3, line.count <= 100 else { return false }
        return !value.contains("rezept von")
            && !value.contains("portionen")
            && !value.contains("personen")
            && !value.contains("www ")
    }

    private func isActionInstruction(_ line: String) -> Bool {
        let value = normalized(line)
        let actionTerms: [String] = [
            "misch", "knet", "ruhr", "back", "schlag", "purier", "zufug",
            "unterheb", "form", "full", "koch", "brat", "kuhl", "ruh", "reif",
            "gehen lassen", "couper", "mettre", "melange", "ajout", "incorpor",
            "verse", "cuire", "prechauff", "beurr", "demoul", "refroid"
        ]
        return isUsefulInstruction(line) && actionTerms.contains(where: value.contains)
    }

    private func isUsefulInstruction(_ line: String) -> Bool {
        let value = normalized(line)
        let metadata = [
            "gesamtzeit", "arbeitszeit", "koch backzeit", "kochzeit", "backzeit",
            "vorbereitungszeit", "portionen", "fur 1 portion"
        ]
        guard line.count > 12, !metadata.contains(where: value.hasPrefix) else { return false }
        let isOnlyTimeValue = line.range(
            of: #"^\s*\d+(?:[.,]\d+)?\s*(?:Std\.?|Stunden?|Min(?:ute)?n?|h)(?:\s*[,/]\s*\d+\s*Min(?:ute)?n?\.?)?\s*$"#,
            options: [.regularExpression, .caseInsensitive]
        ) != nil
        guard !isOnlyTimeValue else { return false }
        return !isIngredientHeading(value) && !isInstructionHeading(value)
    }

    private func hasListMarker(_ line: String) -> Bool {
        line.range(of: #"^\s*(?:\d{1,2}[.):]|[•·\-–—])\s*"#, options: .regularExpression) != nil
    }

    private func removingListMarker(from line: String) -> String {
        line.replacingOccurrences(
            of: #"^\s*(?:\d{1,2}[.):]|[•·\-–—])\s*"#,
            with: "",
            options: .regularExpression
        ).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func condensedIngredientLists(in text: String) -> String {
        // Recipe pages often repeat exact quantities inside the method. Once the
        // structured ingredient list has been extracted, that duplication makes
        // reminders hard to scan and can be mistaken for additional ingredients.
        let pattern = #"\bDie\s+Zutaten\s+für\s+(den|die|das)\s+([^.(]{2,60})\s*\((?=[^)]*\d+\s*(?:g|kg|ml|l)\b)(?=[^)]*,[^)]*\d+\s*(?:g|kg|ml|l)\b)[^)]*\)"#
        guard let expression = try? NSRegularExpression(
            pattern: pattern,
            options: [.caseInsensitive]
        ) else {
            return text
        }
        return expression.stringByReplacingMatches(
            in: text,
            range: NSRange(text.startIndex..., in: text),
            withTemplate: "Alle Zutaten für $1 $2"
        )
    }

    private func duration(in text: String) -> Int {
        guard let values = captures(#"(\d+(?:[.,]\d+)?|eine?r?|einer|einem)\s*(Min(?:ute)?n?|mn|Std\.?|Stunden?|heures?|h)\b"#, in: text) else {
            return 0
        }
        let number = normalized(values[0])
        let value = ["ein", "eine", "einer", "einem"].contains(number)
            ? 1
            : Double(values[0].replacingOccurrences(of: ",", with: ".")) ?? 0
        let unit = normalized(values[1])
        return Int((unit.hasPrefix("std") || unit == "h" || unit.hasPrefix("stunde") || unit.hasPrefix("heure")) ? value * 60 : value)
    }

    private func numericAmount(_ value: String) -> Double {
        let fractions: [String: Double] = ["½": 0.5, "¼": 0.25, "¾": 0.75, "⅓": 1.0 / 3.0, "⅔": 2.0 / 3.0]
        return fractions[value] ?? Double(value.replacingOccurrences(of: ",", with: ".")) ?? 0
    }

    private func canonicalUnit(_ value: String) -> String {
        let unit = value.trimmingCharacters(in: CharacterSet(charactersIn: ". "))
        switch normalized(unit) {
        case "essloffel", "cs", "c a s", "cuillere a soupe": return "EL"
        case "teeloffel", "c a c", "cuillere a cafe": return "TL"
        case "stuck", "stk": return "Stück"
        case "prise", "pincee": return "Pr"
        case "packchen", "packung", "sachet": return "Pck"
        case "liter": return "l"
        default: return unit
        }
    }

    private func cleanedIngredientName(_ text: String) -> String {
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(
                of: #"^(?:de la|du|des|de|d['’])\s*"#,
                with: "",
                options: [.regularExpression, .caseInsensitive]
            )

        // A parenthesis that never closes means its remainder wrapped onto a
        // line the OCR returned separately. The bare name reads better than a
        // dangling fragment such as "Walnüsse (geröstet".
        guard value.filter({ $0 == "(" }).count > value.filter({ $0 == ")" }).count,
              let openIndex = value.lastIndex(of: "(") else {
            return value
        }
        let withoutFragment = value[..<openIndex].trimmingCharacters(in: .whitespacesAndNewlines)
        return withoutFragment.count >= 3 ? withoutFragment : value
    }

    private func cleanedLine(_ text: String) -> String {
        text.replacingOccurrences(
            of: #"^\s*\d+(?:[.,]\d+)?\s*%\s*"#,
            with: "",
            options: .regularExpression
        )
        .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
        .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func normalized(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "de_DE"))
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    private func captures(_ pattern: String, in text: String) -> [String]? {
        guard let expression = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]),
              let match = expression.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) else {
            return nil
        }
        return (1..<match.numberOfRanges).map { index in
            guard let range = Range(match.range(at: index), in: text) else { return "" }
            return String(text[range])
        }
    }
}
