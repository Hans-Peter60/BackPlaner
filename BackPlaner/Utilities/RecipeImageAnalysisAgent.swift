import Foundation
import UIKit
@preconcurrency import Vision

final class RecipeImageAnalysisAgent {

    /// Baking terms that language correction otherwise garbles in the small type
    /// of ingredient tables — "Roggenvollkornmehl" came back as
    /// "Roggenvol kornmeh", "Anstellgut" as "Anstel gut".
    static let bakingVocabulary = [
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
                case .specialTwoColumn:
                    result = try readSpecialRecipe(from: pages, firstImage: images.first)
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
    /// it directly, the two-column layout states a piece count and a weight
    /// per piece.
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

    /// Analyzes common recipe layouts without applying the column and planning
    /// rules of the two-column template.
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
            recipeImage: extractRecipePhoto(from: firstImage, pages: pages),
            warnings: parsed.warnings,
            layout: .general,
            titleOptions: titleRegions(in: pages, chosen: parsed.recipe.name)
        )
    }

    /// Cuts the picture of the bake out of a recipe page.
    ///
    /// Saliency was the obvious tool for this and does not work: on a page that
    /// consists mostly of text, Vision reports no salient object at all —
    /// neither in the simulator nor on the device. What does locate the picture
    /// is the text itself. The recognition tells us where every line sits, so
    /// the picture is the largest rectangle of the page that holds no line, and
    /// whether that rectangle is a picture or just empty paper is decided by
    /// how much its brightness varies.
    private func extractRecipePhoto(
        from image: UIImage?,
        pages: RecognizedPages
    ) -> UIImage? {

        guard let image,
              let firstPage = pages.classicLines.map(\.page).min() else { return nil }
        let textBoxes = pages.classicLines
            .filter { $0.page == firstPage }
            .map(\.boundingBox)
        guard !textBoxes.isEmpty else { return nil }

        // The page is measured on a grid, because a rectangle is only free of
        // text down to the resolution the lines are known at anyway.
        let resolution = 64
        let cell = 1.0 / CGFloat(resolution)
        var occupied = [[Bool]](
            repeating: [Bool](repeating: false, count: resolution),
            count: resolution
        )
        for box in textBoxes {
            // Vision counts from the bottom, the grid from the top. The box is
            // widened by one cell so the rectangle keeps its distance from the
            // type instead of touching it.
            let top = max(0, Int(((1 - box.maxY) / cell).rounded(.down)) - 1)
            let bottom = min(resolution - 1, Int(((1 - box.minY) / cell).rounded(.up)) + 1)
            let left = max(0, Int((box.minX / cell).rounded(.down)) - 1)
            let right = min(resolution - 1, Int((box.maxX / cell).rounded(.up)) + 1)
            guard top <= bottom, left <= right else { continue }
            for row in top...bottom {
                for column in left...right {
                    occupied[row][column] = true
                }
            }
        }

        guard let free = largestFreeRectangle(in: occupied),
              free.width * free.height >= Int(0.06 * Double(resolution * resolution)),
              let cgImage = uprightImage(image).cgImage else {
            return nil
        }

        let width = CGFloat(cgImage.width)
        let height = CGFloat(cgImage.height)
        let inset = cell * 0.4
        let cropRect = CGRect(
            x: (CGFloat(free.x) * cell + inset) * width,
            y: (CGFloat(free.y) * cell + inset) * height,
            width: (CGFloat(free.width) * cell - 2 * inset) * width,
            height: (CGFloat(free.height) * cell - 2 * inset) * height
        ).integral

        let aspect = cropRect.width / max(1, cropRect.height)
        guard cropRect.width >= 220,
              cropRect.height >= 220,
              aspect >= 0.3, aspect <= 3.5,
              let croppedImage = cgImage.cropping(to: cropRect),
              hasPictureContent(croppedImage) else {
            return nil
        }

        // The free rectangle reaches into the white paper around the picture,
        // because paper carries no text either.
        guard let content = contentBounds(of: croppedImage),
              let trimmedImage = croppedImage.cropping(to: CGRect(
                  x: content.minX * cropRect.width,
                  y: content.minY * cropRect.height,
                  width: content.width * cropRect.width,
                  height: content.height * cropRect.height
              ).integral),
              trimmedImage.width >= 220,
              trimmedImage.height >= 220 else {
            return UIImage(cgImage: croppedImage, scale: image.scale, orientation: .up)
        }
        return UIImage(cgImage: trimmedImage, scale: image.scale, orientation: .up)
    }

    /// The part of a cut-out region that carries the picture, as a fraction of
    /// it: the rows and columns at its edges whose brightness barely varies are
    /// the paper around the photo.
    private func contentBounds(of cgImage: CGImage) -> CGRect? {
        let side = 48
        var pixels = [UInt8](repeating: 0, count: side * side)
        let drawn = pixels.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(
                data: buffer.baseAddress,
                width: side,
                height: side,
                bitsPerComponent: 8,
                bytesPerRow: side,
                space: CGColorSpaceCreateDeviceGray(),
                bitmapInfo: CGImageAlphaInfo.none.rawValue
            ) else {
                return false
            }
            context.draw(cgImage, in: CGRect(x: 0, y: 0, width: side, height: side))
            return true
        }
        guard drawn else { return nil }

        func deviation(_ values: [Double]) -> Double {
            guard !values.isEmpty else { return 0 }
            let mean = values.reduce(0, +) / Double(values.count)
            let variance = values.reduce(0) { $0 + ($1 - mean) * ($1 - mean) }
                / Double(values.count)
            return variance.squareRoot()
        }

        let rowDeviations = (0..<side).map { row in
            deviation((0..<side).map { Double(pixels[row * side + $0]) / 255 })
        }
        let columnDeviations = (0..<side).map { column in
            deviation((0..<side).map { Double(pixels[$0 * side + column]) / 255 })
        }
        let rowLimit = max(0.02, (rowDeviations.max() ?? 0) * 0.25)
        let columnLimit = max(0.02, (columnDeviations.max() ?? 0) * 0.25)

        guard let firstRow = rowDeviations.firstIndex(where: { $0 >= rowLimit }),
              let lastRow = rowDeviations.lastIndex(where: { $0 >= rowLimit }),
              let firstColumn = columnDeviations.firstIndex(where: { $0 >= columnLimit }),
              let lastColumn = columnDeviations.lastIndex(where: { $0 >= columnLimit }) else {
            return nil
        }

        // Both the bitmap buffer and a cropping rectangle start at the top row,
        // so the rows map over directly.
        let cell = 1.0 / CGFloat(side)
        return CGRect(
            x: CGFloat(firstColumn) * cell,
            y: CGFloat(firstRow) * cell,
            width: CGFloat(lastColumn - firstColumn + 1) * cell,
            height: CGFloat(lastRow - firstRow + 1) * cell
        )
    }

    /// The largest rectangle of the grid that holds no marked cell, found per
    /// row as the largest rectangle in the histogram of free cells above it.
    private func largestFreeRectangle(
        in occupied: [[Bool]]
    ) -> (x: Int, y: Int, width: Int, height: Int)? {

        guard let columns = occupied.first?.count, columns > 0 else { return nil }
        var heights = [Int](repeating: 0, count: columns)
        var best: (x: Int, y: Int, width: Int, height: Int)?
        var bestArea = 0

        for (rowIndex, row) in occupied.enumerated() {
            for column in 0..<columns {
                heights[column] = row[column] ? 0 : heights[column] + 1
            }

            var stack: [(column: Int, height: Int)] = []
            for column in 0...columns {
                let height = column < columns ? heights[column] : 0
                var start = column
                while let last = stack.last, last.height >= height {
                    let area = last.height * (column - last.column)
                    if area > bestArea {
                        bestArea = area
                        best = (
                            x: last.column,
                            y: rowIndex - last.height + 1,
                            width: column - last.column,
                            height: last.height
                        )
                    }
                    start = last.column
                    stack.removeLast()
                }
                if height > 0 {
                    stack.append((column: start, height: height))
                }
            }
        }
        return bestArea > 0 ? best : nil
    }

    /// Whether a cut-out region carries a picture rather than empty paper,
    /// measured as the spread of its brightness.
    private func hasPictureContent(_ cgImage: CGImage) -> Bool {
        let side = 24
        var pixels = [UInt8](repeating: 0, count: side * side)
        let drawn = pixels.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(
                data: buffer.baseAddress,
                width: side,
                height: side,
                bitsPerComponent: 8,
                bytesPerRow: side,
                space: CGColorSpaceCreateDeviceGray(),
                bitmapInfo: CGImageAlphaInfo.none.rawValue
            ) else {
                return false
            }
            context.draw(cgImage, in: CGRect(x: 0, y: 0, width: side, height: side))
            return true
        }
        guard drawn else { return false }

        let values = pixels.map { Double($0) / 255 }
        let mean = values.reduce(0, +) / Double(values.count)
        let variance = values.reduce(0) { $0 + ($1 - mean) * ($1 - mean) } / Double(values.count)
        return variance.squareRoot() >= 0.08
    }

    /// The image with its orientation applied, so that the recognized text
    /// boxes and the pixels are measured in the same frame.
    private func uprightImage(_ image: UIImage) -> UIImage {
        guard image.imageOrientation != .up else { return image }
        // The renderer would otherwise draw at the screen's scale and multiply
        // the pixel count, which the crop rectangle is measured in.
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = image.scale
        format.opaque = true
        return UIGraphicsImageRenderer(size: image.size, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: image.size))
        }
    }

    func analyzeSpecialRecipe(
        images: [UIImage],
        progress: @escaping @MainActor (Int, Int) -> Void = { _, _ in }
    ) async throws -> RecipeImageAnalysisResult {
        let pages = try await recognizePages(images: images, progress: progress)
        return try readSpecialRecipe(from: pages, firstImage: images.first)
    }

    /// Reads a recipe from recognized pages with the two-column rules: a
    /// planning example, ingredients left of the gutter and numbered work
    /// steps to its right.
    private func readSpecialRecipe(
        from pages: RecognizedPages,
        firstImage: UIImage?
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
            // The picture of the bake sits on the first page of this layout as
            // well, so it is worth cutting out here too — otherwise the import
            // offers the whole page as the recipe's image.
            recipeImage: extractRecipePhoto(from: firstImage, pages: pages),
            layout: .specialTwoColumn,
            titleOptions: titleRegions(in: pages, chosen: recipe.name)
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

    /// Every recognized line, with where it sits, so the import can let the user
    /// point at the recipe's name.
    ///
    /// Deliberately unfiltered, by position and by content alike. Any rule that
    /// narrows this repeats the very guess the picker exists to override: a
    /// title can sit below a photo, halfway down a book page or on the second
    /// sheet, and `isPageFurnitureLine` — right for the automatic choice —
    /// throws away every line carrying a web address, which on a printout from
    /// quiche-lorraine.com is the heading itself. Ranking still puts the likely
    /// headings first, but nothing printed is withheld.
    private func titleRegions(
        in pages: RecognizedPages,
        chosen: String
    ) -> [RecipeTextRegion] {
        // Both recognitions contribute: the document request joins wrapped
        // headings, classic recognition catches lines it dropped.
        let candidates = (pages.documentLines + pages.classicLines).filter { line in
            let trimmed = line.text.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.count >= 2 && trimmed.count <= 120
        }
        guard !candidates.isEmpty else { return [] }

        let chosenValue = chosen.trimmingCharacters(in: .whitespacesAndNewlines)
        let ordered = candidates.sorted { left, right in
            if left.text == chosenValue { return true }
            if right.text == chosenValue { return false }
            if left.page != right.page { return left.page < right.page }
            if abs(left.boundingBox.height - right.boundingBox.height) > 0.002 {
                return left.boundingBox.height > right.boundingBox.height
            }
            return left.boundingBox.midY > right.boundingBox.midY
        }

        var seen = Set<String>()
        var regions = ordered.compactMap { line -> RecipeTextRegion? in
            guard seen.insert("\(line.page)|\(line.text)").inserted else { return nil }
            return RecipeTextRegion(
                page: line.page,
                text: line.text,
                boundingBox: line.boundingBox
            )
        }

        // A heading that wraps arrives as one line per printed row, so the name
        // the reading assembled matches none of them. Offered as fragments the
        // picker could only ever shorten a correct title, so the assembled name
        // is put back over the rows it came from.
        if !chosenValue.isEmpty, !regions.contains(where: { $0.text == chosenValue }),
           let page = candidates.first(where: { chosenValue.contains($0.text) })?.page {
            let parts = candidates.filter { $0.page == page && chosenValue.contains($0.text) }
            let box = parts.reduce(CGRect.null) { $0.union($1.boundingBox) }
            if !box.isNull {
                regions.insert(
                    RecipeTextRegion(page: page, text: chosenValue, boundingBox: box),
                    at: 0
                )
            }
        }

        return regions
    }

    private func recognizePages(
        images: [UIImage],
        progress: @escaping @MainActor (Int, Int) -> Void
    ) async throws -> RecognizedPages {

        var pages = RecognizedPages()

        for (index, image) in images.enumerated() {
            try Task.checkCancellation()
            await progress(index + 1, images.count)

            // What the picker actually handed over. With iCloud Photos set to
            // optimise storage, the copy on the device is smaller than the
            // original, and small print stops being legible to the OCR.
            AppLog.recipeImport.debug("""
                Bild \(index + 1): \
                \(Int(image.size.width * image.scale))×\(Int(image.size.height * image.scale)) px \
                (scale \(image.scale), Ausrichtung \(image.imageOrientation.rawValue))
                """)

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

            // Worth keeping: text recognition returns markedly fewer lines on a
            // device than in the simulator for the same file, and more
            // paragraphs than lines is the sign of it. Neither a second pass at
            // twice the size nor one without the language model recovered any
            // of them, so when this shows up the text is simply not there.
            AppLog.recipeImport.debug("""
                Seite \(index + 1): zeilen=\(classicLines.count) \
                absätze=\(structure?.paragraphs.count ?? -1) \
                tabellen=\(structure?.tables.count ?? -1)
                """)

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
        // across printed line breaks. They complement the classic OCR and must
        // not remove its lines, because Vision sometimes assigns a compact
        // component paragraph a broader or neighbouring layout region.
        //
        // Every paragraph is kept, not only those carrying a baking verb. The
        // two recognitions do not agree on what they read: on one device the
        // printed line "Zuerst die Hefe im lauwarmen Wasser auflösen…" was not
        // returned at all — Vision read the step's number badge on that
        // baseline instead — so the paragraph was the only copy of the text,
        // and a keyword filter threw it away. Duplicates are cheap; the
        // readers deduplicate paragraphs against their lines anyway.
        filteredLines.append(contentsOf: structure.paragraphs.compactMap { paragraph in
            guard paragraph.text.count >= 20,
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
