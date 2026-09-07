import Foundation
import UIKit
@preconcurrency import Vision

struct RecipeImageAnalysisResult {
    let recipe: RecipeFB
    let recognizedText: String

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

    var errorDescription: String? {
        switch self {
        case .invalidImage:
            return String(localized: "Mindestens eines der ausgewählten Bilder konnte nicht gelesen werden.")
        case .noTextRecognized:
            return String(localized: "Auf den Bildern wurde kein ausreichend lesbarer Text erkannt.")
        case .unsupportedLayout:
            return String(localized: "Das erwartete zweispaltige Rezeptlayout mit Planungsbeispiel wurde nicht erkannt.")
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
    func analyze(
        images: [UIImage],
        progress: @escaping @MainActor (Int, Int) -> Void = { _, _ in }
    ) async throws -> RecipeImageAnalysisResult {
        var allLines: [RecognizedRecipeLine] = []

        for (index, image) in images.enumerated() {
            try Task.checkCancellation()
            await progress(index + 1, images.count)
            var pageLines = try await recognizeLines(in: image, page: index)
            if pageLines.contains(where: { $0.text.localizedCaseInsensitiveContains("PLANUNGSBEISPIEL") }) {
                let planningLines = try await recognizePlanningLines(in: image, page: index)
                pageLines.removeAll { $0.x >= 0.48 && $0.y >= 0.70 }
                pageLines.append(contentsOf: planningLines)
            }
            allLines.append(contentsOf: pageLines)
        }

        guard !allLines.isEmpty else {
            throw RecipeImageAnalysisError.noTextRecognized
        }

        let parser = TwoColumnRecipeParser(lines: allLines)
        let recipe = try parser.parse()
        let recognizedText = allLines
            .sorted(by: Self.readingOrder)
            .map { "[Seite \($0.page + 1), x:\(format($0.x)), y:\(format($0.y))] \($0.text)" }
            .joined(separator: "\n")

        return RecipeImageAnalysisResult(recipe: recipe, recognizedText: recognizedText)
    }

    private func recognizeLines(in image: UIImage, page: Int) async throws -> [RecognizedRecipeLine] {
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
            request.recognitionLanguages = ["de-DE", "en-US"]

            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    try VNImageRequestHandler(cgImage: cgImage).perform([request])
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
            request.recognitionLanguages = ["de-DE", "en-US"]

            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    try VNImageRequestHandler(cgImage: croppedImage).perform([request])
                } catch {
                    continuation.resume(throwing: error)
                }
            }
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

    func parse() throws -> RecipeFB {
        let componentHeadings = findComponentHeadings()
        guard !componentHeadings.isEmpty,
              let planningHeading = lines.first(where: {
                  normalized($0.text).contains("planungsbeispiel")
              }) else {
            throw RecipeImageAnalysisError.unsupportedLayout
        }

        let recipe = RecipeFB()
        recipe.name = recipeName() ?? "Importiertes Rezept"
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

        let firstComponentOnPlanningPage = componentHeadings
            .filter { $0.page == planningHeading.page }
            .max(by: { $0.y < $1.y })
        let planningLines = lines.filter { line in
            line.page == planningHeading.page
                && line.x >= 0.48
                && line.y < planningHeading.y
                && line.y > (firstComponentOnPlanningPage?.y ?? 0)
        }
        let planningSteps = parsePlanningSteps(from: planningLines)
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
        component.name = name ?? "Komponente \(number)"
        component.number = number

        let ingredientRows = groupedRows(lines.filter { $0.x < 0.48 })
        component.ingredients = ingredientRows.compactMap(parseIngredientRow)
            .enumerated().map { index, parsed in
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
        return planningSteps.indices.compactMap { index in
            let step = planningSteps[index]
            guard !step.isEndMarker,
                  !isGeneratedOvenStartStep(step.action),
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

    private func isGeneratedOvenStartStep(_ action: String) -> Bool {
        let text = normalized(action)
        return containsAny(text, [
            "backofen anstellen", "ofen anstellen",
            "backofen einschalten", "ofen einschalten",
            "backofen vorheizen", "ofen vorheizen"
        ])
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
