import Foundation
import CoreGraphics

struct TwoColumnRecipeParser {
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
        // column, which is where the two-column template prints it but a book
        // page does not.
        var planningSteps = planningStepsFromTables()
        // The laid-out table is only trusted where its rows read like a
        // schedule. On a web page the document request lays out the ingredient
        // column and the planning column as one table, and since the action is
        // taken as the longest cell of a row, "Weizenmehl 550" wins against
        // "Vorformen". The geometric reading of the planning column, which
        // cannot reach the other column at all, is then the better source.
        let readsLikeSchedule = planningSteps.count { isPlanningAction($0.action) } * 2
            >= planningSteps.count
        if planningSteps.count < 2 || !readsLikeSchedule {
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

        // The steps of this layout run one after another, so the schedule ends
        // where the last one does. Without this the recipe claimed a
        // preparation time of zero, although the page states its own total.
        recipe.prepTime = recipe.instructions.reduce(0) { $0 + $1.duration }
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

    /// Whether a line of a planning example names work. The example is written
    /// in the small, fixed vocabulary of a bakery, which is what separates its
    /// rows from an ingredient row that ended up in the same laid-out table.
    private func isPlanningAction(_ text: String) -> Bool {
        let value = normalized(text)
        let terms: [String] = [
            "herstellen", "ansetzen", "mischen", "kneten", "verruhren",
            "portionieren", "vorformen", "formen", "wirken", "tourieren",
            "schneiden", "backen", "vorheizen", "reifen", "ruhen", "dehnen",
            "falten", "abstechen", "aufrollen", "teilen", "quellen",
            "einschiessen", "fertig"
        ]
        return terms.contains { value.contains($0) }
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
        // The vertical rule between the name column and the temperature column
        // is read as a pipe and would stay in the name.
        let cleanedName = name
            .trimmingCharacters(in: CharacterSet(charactersIn: "|¦ \t\n"))
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
