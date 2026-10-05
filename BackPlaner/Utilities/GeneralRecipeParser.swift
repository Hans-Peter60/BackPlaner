import Foundation
import CoreGraphics

struct GeneralRecipeParser {
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
        // The recognition contributes both the printed lines and the paragraphs
        // Vision joined from them, so every sentence of a prose recipe arrives
        // twice. Reading it once is what keeps one printed sentence from
        // becoming two steps — and its amounts from becoming two ingredients.
        let equipment = equipmentColumnLines()
        let textLines = deduplicatedParagraphs(
            lines.filter { !equipment.contains($0.text) }
                .map(\.text)
                .map(withoutPageFurniture)
                .filter { !$0.isEmpty }
        )

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
            instructionRows = spatialSections.instructions.filter {
                isUsefulInstruction($0)
                    || recipeComponentHeading($0) != nil
                    || isStepNumberMarker($0)
            }
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
                    } else if isActionInstruction(line) {
                        // The method begins where the ingredient list ends, even
                        // on a page that prints no heading above it. Without
                        // this the steps were collected from the whole page
                        // afterwards, introduction included, and lost their
                        // order.
                        section = .instructions
                        instructionRows.append(line)
                    }
                case .instructions:
                    if isUsefulInstruction(line)
                        || recipeComponentHeading(line) != nil
                        || isStepNumberMarker(line) {
                        instructionRows.append(line)
                    }
                }
            }
        }

        // A sentence that reached the steps both as a printed line and as the
        // paragraph containing it would otherwise be scheduled twice, no matter
        // which reading above produced it.
        instructionRows = deduplicatedParagraphs(instructionRows)

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
        recipe.name = wholeHeading(structureTitle(), detectedMultilineTitle())
            ?? titleCandidates.first
            ?? AppSettings.generatedRecipeTexts().importedRecipe
        recipe.summary = usedSpatialComponentAssignment
            ? (detectedDescriptionUnderTitle(title: recipe.name) ?? detectedSummary(in: textLines))
            : (subtitleUnderTitle(recipe.name) ?? detectedSummary(in: textLines))
        recipe.sourceLanguage = detectedLanguage(in: textLines)
        recipe.tags = inferredGeneralTags(from: recipe.name)

        componentRows = componentRows.filter { !isMetadataRow($0.1) }

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

        let numbered = analyzedNumberedSteps(instructionRows)
        let component = numbered == nil ? analyzedComponentSteps(instructionRows) : nil
        let grouped = (numbered ?? component) == nil
            ? paragraphGroupedInstructions(instructionRows)
            : nil
        AppLog.recipeImport.debug("""
            Reader-Pfad: nummeriert=\(numbered?.count ?? -1) \
            komponenten=\(component?.count ?? -1) \
            absätze=\(grouped?.count ?? -1) \
            zeilen=\(self.lines.count) rows=\(instructionRows.count)
            """)

        if let analyzedSteps = numbered ?? component ?? grouped {
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
        // The total weight is the sum of ALL ingredients. The dough weight a
        // page prints is not: it leaves out what is worked in later — the
        // butter of a brioche, the butter a croissant is laminated with — so it
        // only serves as the plausibility check at the end of this method.
        recipe.totalWeight = normalisedIngredientWeight(of: recipe)

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

    /// Sum of every ingredient, converted to grams the same way the two save
    /// paths do, so an imported recipe already carries the weight it will be
    /// stored with instead of a figure taken off the page.
    private func normalisedIngredientWeight(of recipe: RecipeFB) -> Double {
        let calculator = CalcIngredientWeight()

        return recipe.components.flatMap { $0.ingredients }.reduce(0.0) { total, ingredient in
            if ingredient.unit == "g" || ingredient.unit == "Gramm" {
                return total + ingredient.weight
            }
            return total + calculator.calcIngredientWeight(
                weight: ingredient.weight,
                unit: ingredient.unit,
                name: ingredient.name,
                num: ingredient.num,
                denom: ingredient.denom
            )
        }
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
                bundle: AppSettings.localizationBundle, locale: AppSettings.locale
            ))
        }

        if let printed = box.doughYield,
           let computed = computedDoughYield(of: recipe),
           abs(computed - printed) > 4 {
            warnings.append(String(
                localized: "Die berechnete Teigausbeute (\(Int(computed))) weicht von der angegebenen (\(Int(printed))) ab.",
                bundle: AppSettings.localizationBundle, locale: AppSettings.locale
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

    /// Whether a row read as an ingredient is really the page's own metadata.
    ///
    /// A star rating, a portion box and a time box are each a number beside a
    /// word, so they parse exactly like "350 g Wasser" — a web recipe yielded
    /// "45 Kommentare", "4 Portionen" and "240 °C" among its ingredients, and
    /// from there they travel to the shopping list.
    private func isMetadataRow(_ ingredient: ParsedIngredient) -> Bool {
        let name = ingredient.name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return true }

        // "(62)" beside the stars: a name without a single letter.
        guard name.contains(where: \.isLetter) else { return true }

        let patterns = [
            // A bare temperature or duration: "°C", "240 °C", "1 Std", "25 Min".
            #"^\d*\s*°?\s*[cf]$"#,
            #"^\d*\s*(std|stdn|stunden?|min|minuten?|h|sek|sekunden?)\.?$"#,
            // Ratings and counts.
            #"^\d*\s*(kommentare?|bewertungen?|stimmen?|votes?|avis)$"#,
            // Yield, which is a heading rather than something to buy.
            #"^(für\s+)?\d*\s*(portionen?|personen?|stück\s+zu)$"#,
            // The labels of a time box.
            #"^(gesamtzeit|arbeitszeit|ruhezeit|backzeit|kochzeit|koch-?/?backzeit|zubereitungszeit)$"#
        ]
        return patterns.contains {
            name.range(of: $0, options: [.regularExpression, .caseInsensitive]) != nil
        }
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
            // The next label's match consumes the full stop that ended this
            // component's last sentence. Without it, baking the base and
            // blending the filling were read as one step.
            let isSentenceEnd = [".", "!", "?", ":"].contains { body.hasSuffix($0) }
            components.append(
                ProseComponent(name: name, text: isSentenceEnd ? body : body + ".")
            )
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

    /// Strips the furniture a printed web page carries: the page counter, the
    /// URL and the date of the print. Only the furniture is removed, not the
    /// whole line — Vision merges the counter of a page onto its first
    /// sentence, and dropping the line would cost that step. A line that
    /// carried nothing else comes back empty and is discarded by the caller.
    private func withoutPageFurniture(_ text: String) -> String {
        let patterns: [String] = [
            #"https?://\S+"#,
            #"\bwww\.\S+"#,
            #"\b(?:seite|page)\s+\d+\s+(?:von|of|sur|de)\s+\d+\b"#,
            #"\b\d{1,2}[./]\d{1,2}[./]\d{2,4}\b"#,
            #"^\s*\d{2}[./]\d{4}\b"#
        ]
        var value = text
        for pattern in patterns {
            value = value.replacingOccurrences(
                of: pattern,
                with: " ",
                options: [.regularExpression, .caseInsensitive]
            )
        }
        return cleanedLine(value)
    }

    /// The lines of an equipment column, which a printed recipe likes to set
    /// beside its ingredient list. Its rows are formed exactly like an
    /// ingredient — "1 moule à tarte", "1 Saladier" — so nothing in the text
    /// tells them apart; only the heading above them does. Left in, the tart
    /// tin and the whisk end up in the shopping list. The column ends at the
    /// first vertical gap, so the method printed below it is kept.
    private func equipmentColumnLines() -> Set<String> {
        let headingNames = [
            "material", "materiel", "utensilien", "zubehor", "werkzeug",
            "equipment", "ustensiles", "geratschaften"
        ]
        let headings = lines.filter { headingNames.contains(normalized($0.text)) }
        guard !headings.isEmpty else { return [] }

        var masked: Set<String> = []
        for heading in headings {
            masked.insert(heading.text)
            let column = lines.filter {
                $0.page == heading.page
                    && $0.x >= heading.x - 0.03
                    && $0.y < heading.y - 0.005
            }.sorted { $0.y > $1.y }

            var previousY = heading.y
            for line in column {
                guard previousY - line.y <= 0.045 else { break }
                masked.insert(line.text)
                previousY = line.y
            }
        }
        return masked
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
        let listed = splitOutsideParentheses(separated).compactMap { phrase in
            parseProseIngredient(phrase)
        }

        // A prose recipe does not necessarily name all of its ingredients
        // before the first action: "mit 420 g geräuchertem Lachs verrühren und
        // 3 frische Frühlingszwiebeln unterheben" carries two more.
        let remainder = ingredientPrefix.count < text.count
            ? String(text.dropFirst(ingredientPrefix.count))
            : ""
        var known = Set(listed.map { normalized($0.name) })
        return listed + trailingProseIngredients(remainder).filter { ingredient in
            known.insert(normalized(ingredient.name)).inserted
        }
    }

    /// The amounts a component still names after its first action verb. Only a
    /// mass or volume unit, or a name that a recipe counts by the piece,
    /// qualifies — that is what keeps "30 Min." and "200 Grad" out of the
    /// ingredient list, since they are printed exactly like an amount.
    private func trailingProseIngredients(_ text: String) -> [ParsedIngredient] {
        let pattern = #"(?:^|[\s(])(\d+(?:[.,]\d+)?|[½¼¾⅓⅔])\s*(kg|g|mg|l|dl|cl|ml|EL|TL|Prise|Bund|Päckchen|Packung)?\s+((?:[\p{Ll}][\p{L}]*,?\s+){0,3}[\p{Lu}][\p{L}]*(?:-[\p{L}]+)*)"#
        guard let expression = try? NSRegularExpression(pattern: pattern) else { return [] }

        return expression.matches(
            in: text,
            range: NSRange(text.startIndex..., in: text)
        ).compactMap { match in
            let parts = (1...3).map { index -> String in
                guard let range = Range(match.range(at: index), in: text) else { return "" }
                return String(text[range])
            }
            guard let ingredient = parseProseIngredient(
                parts.joined(separator: " ")
            ) else {
                return nil
            }
            let isCounted = isCountedIngredient(ingredient.name)
                || ["ei", "eier", "oeuf", "oeufs"].contains(normalized(ingredient.name))
            guard !ingredient.unit.isEmpty || isCounted else { return nil }
            return ingredient
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
        let quantifiedPattern = #"(?:^|\s)(\d+(?:[.,]\d+)?|[½¼¾⅓⅔])\s*(kg|grammes?|g|mg|l|Liter|dl|cl|ml|EL|TL|cuillère à café|cuillère à soupe|cs|c\.?\s*à\.?\s*c\.?|c\.?\s*à\.?\s*s\.?|Teelöffel|Esslöffel|Stück|Stk\.?|Würfel|Prise|pinc[eé]e|Bund|Päckchen|Packung|sachet|Tasse|Rolle)?\s+(.+?)\s*$"#
        if let values = captures(quantifiedPattern, in: value), values.count == 3 {
            let rawName = cleanedIngredientName(proseIngredientName(values[2]))
            let unit: String
            let name: String
            let headWord = normalized(rawName).split(separator: " ").last.map(String.init) ?? ""
            if values[1].isEmpty, ["eier", "ei", "oeufs", "oeuf"].contains(headWord) {
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
        return ParsedIngredient(
            amount: 1,
            unit: canonicalUnit(values[0]),
            name: cleanedIngredientName(proseIngredientName(values[1]))
        )
    }

    /// Where a German ingredient phrase stops being the ingredient: "eine Prise
    /// Salz miteinander" names Salz, "3 leicht geschlagene Eier in einen Mixer"
    /// names the eggs. German capitalizes its nouns, so the phrase ends with the
    /// first run of capitalized words — together with the grade number or the
    /// parenthesis that may follow it — while the method behind it is dropped.
    /// The qualifiers in front of the noun are kept, because "brauner Zucker" is
    /// a different ingredient from Zucker. A phrase with no capitalized word, as
    /// in French, is left as it is.
    private func proseIngredientName(_ phrase: String) -> String {
        // The temperature is kept even where the OCR lost the opening
        // parenthesis of "Wasser (40 °C)", because the bare "Wasser 40" would
        // read as a second amount.
        let pattern = #"[\p{Lu}][\p{L}]*(?:-[\p{L}]+)*(?:\s+[\p{Lu}][\p{L}]*(?:-[\p{L}]+)*)*(?:\s+\d+(?:\s*°\s*[CF]\)?)?)?(?:\s*\([^)]*\))?"#
        guard let range = phrase.range(of: pattern, options: .regularExpression) else {
            return phrase
        }
        return String(phrase[..<range.upperBound])
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

    /// The recipe's own introduction: what a book page prints between its title
    /// and its first table.
    ///
    /// The boundary is taken from the title that has already been read, not from
    /// the size of the type. Measuring type size cannot work here, because the
    /// recognition contributes whole paragraphs alongside the printed lines, and
    /// a paragraph's box is as tall as the block it covers — the tallest thing
    /// on the page was a step of the method, so the search for the heading came
    /// up empty and every book page kept the placeholder description.
    /// The subtitle a web recipe prints under its heading — "Mischbrot, bleibt
    /// einige Tage frisch".
    ///
    /// Only a short line counts. On a page that sets its method directly under
    /// the heading everything below qualifies as "under the title", and the
    /// summary would swallow the whole recipe; the yield line `detectedSummary`
    /// settles for is the lesser evil there.
    private func subtitleUnderTitle(_ title: String) -> String? {
        guard let description = detectedDescriptionUnderTitle(title: title),
              description.count <= 120 else {
            return nil
        }
        return description
    }

    private func detectedDescriptionUnderTitle(title: String) -> String? {
        guard let firstPage = lines.map(\.page).min() else { return nil }
        let pageLines = lines.filter { $0.page == firstPage }

        let titleValue = normalized(title)
        guard !titleValue.isEmpty,
              let titleBottomY = pageLines.filter({ line in
                  let value = normalized(line.text)
                  return value.count >= 4 && titleValue.contains(value)
              }).map(\.boundingBox.minY).min() else {
            return nil
        }

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
                && !containsClockTime(line.text)
                // A baker's percentage belongs to a table row, but a sentence
                // may well carry one: "Ein Dinkelmischbrot mit 30 %
                // Kartoffelanteil" is the description, not an ingredient.
                && parseIngredient(line.text) == nil
                && !isPercentageOnly(line.text)
                // "1 / 32 DolceVita4456" is printed on the photo, and "5/5" is
                // a rating — both sit under the heading like a subtitle does.
                && line.text.range(
                    of: #"^\s*\d+\s*/\s*\d+\b"#,
                    options: .regularExpression
                ) == nil
        }.sorted {
            if abs($0.y - $1.y) > 0.008 { return $0.y > $1.y }
            return $0.x < $1.x
        }.map(\.text)

        // The printed lines and the paragraph made of them both arrive here, so
        // the description would otherwise carry every sentence twice.
        let description = deduplicatedParagraphs(descriptionLines)
            .joined(separator: " ")
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
    /// The complete heading, given what the document structure named as the
    /// page title and what joining the large lines at its top produced.
    ///
    /// The structure is trusted first — it knows a heading from a caption — but
    /// for a heading printed over two rows it reports only the first of them,
    /// so "Knusprige und saftige Bauernkruste" arrived as "Knusprige und
    /// saftige". A joined reading that begins with the structure's answer is
    /// therefore the same heading, seen whole.
    private func wholeHeading(_ structure: String?, _ multiline: String?) -> String? {
        guard let structure else { return multiline }
        guard let multiline,
              multiline.count > structure.count,
              normalized(multiline).hasPrefix(normalized(structure)) else {
            return structure
        }
        return multiline
    }

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

        // The recognition contributes each printed row and the paragraph block
        // it belongs to, so a one-row heading arrives twice and joining would
        // write "Knusprige und saftige Knusprige und saftige Bauernkruste".
        var seen = Set<String>()
        let title = titleLines
            .map(\.text)
            .filter { seen.insert(normalized($0)).inserted }
            .joined(separator: " ")
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

            // A short paragraph consists of a single printed line and shares its
            // baseline, so the two arrive as one sentence twice. Only the longer
            // wording is kept — merging them wrote "Backofen auf Stein backen."
            // into the same step twice. Numbers are exempt: an amount is a
            // substring of the percentage printed beside it.
            let lastValue = normalized(last.text)
            let lineValue = normalized(line.text)
            if last.text.count >= 12, line.text.count >= 12,
               lastValue.contains(lineValue) || lineValue.contains(lastValue) {
                if line.text.count > last.text.count {
                    rows[rows.count - 1] = line
                }
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
            // The dotted rule that leads from the amount column to the name is
            // read as a period stuck to the unit — "127 g. Roggenvollkornmehl".
            // Left there, it hides the unit and becomes part of the name.
            .replacingOccurrences(
                of: #"^(\d+(?:[.,]\d+)?\s*(?:kg|g|mg|l|dl|cl|ml|EL|TL))\.+"#,
                with: "$1 ",
                options: [.regularExpression, .caseInsensitive]
            )
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

                if let dependencyName = referencedComponentName(
                    from: line.text,
                    within: heading.name,
                    among: headings.map(\.name)
                ) {
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
                // A German compound carries its head last, and only the head
                // identifies the ingredient: matching any word of "3 leicht
                // geschlagene Eier" put the eggs of the filling into the dough,
                // whose prose happens to say "leicht" as well.
                let headWord = ingredientName.split(separator: " ")
                    .map(String.init)
                    .last { $0.count >= 4 } ?? ingredientName
                let containsName = blockText.contains(headWord)
                let amountText = row.1.amount.formatted(
                    .number.locale(Locale(identifier: "de_DE"))
                        .precision(.fractionLength(0...2))
                )
                // The amount has to stand on its own. Searched as a substring,
                // the 80 g of the filling was found inside the "180 Grad" of
                // the dough and moved with it.
                let containsAmount = blockText.range(
                    of: #"(?<!\d)"#
                        + NSRegularExpression.escapedPattern(for: normalized(amountText))
                        + #"(?!\d)"#,
                    options: .regularExpression
                ) != nil

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

    /// The component a "gesamte …" row refers to. Its small print is often cut
    /// short — Vision returned "gesamte Sauerte" for "gesamte Sauerteigstufe 1"
    /// — and the remaining letters cannot tell the two sourdough stages apart.
    /// The fragment is therefore resolved against the component headings the
    /// page actually has, excluding the component the row stands in; only an
    /// unambiguous match counts. Without it the second stage looked independent
    /// and the plan started both stages at the same time.
    private func referencedComponentName(
        from line: String,
        within component: String,
        among componentNames: [String]
    ) -> String? {
        if let name = componentDependencyName(from: line) {
            return name
        }

        let value = normalized(line)
        guard let prefixRange = value.range(
            of: #"^gesamte[rs]?\s+"#,
            options: .regularExpression
        ) else {
            return nil
        }
        let fragment = String(value[prefixRange.upperBound...])
        guard fragment.count >= 5 else { return nil }

        let candidates = componentNames.filter { candidate in
            normalized(candidate) != normalized(component)
                && normalized(candidate).hasPrefix(fragment)
        }
        guard candidates.count == 1 else { return nil }
        return "gesamte " + candidates[0]
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

        let pattern = #"^\s*[•·\-–—]?\s*(\d+(?:[.,]\d+)?|[½¼¾⅓⅔])\s*(kg|grammes?|gr\.?|g|mg|l|Liter|dl|cl|ml|EL|TL|cuillère à café|cuillère à soupe|cs|c\.?\s*à\.?\s*[cs]\.?|Teelöffel|Esslöffel|Stück|Stk\.?|Würfel|Prise|pinc[eé]e|Bund|Päckchen|Packung|sachet|Tasse|Tassen)?\s+(.+?)\s*$"#
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

        let eggWords = ["eier", "ei", "oeufs", "oeuf", "œufs", "œuf"]
        if unit.isEmpty, normalizedName.split(separator: " ").contains(where: {
            eggWords.contains(String($0))
        }) {
            // "3 œufs entiers" counts eggs just as "3 Eier" does.
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

    /// The work steps as they are printed, grouped by the space between them.
    ///
    /// A web recipe sets its step numbers as pale badges beside the text, and
    /// Vision does not read those digits at all — so `analyzedNumberedSteps`
    /// finds nothing to group by, and splitting the remaining prose by sentence
    /// turned five printed steps into sixteen. What does survive the photograph
    /// is the typography: on such a page the gap between two steps is about
    /// half again the line spacing inside one, which is enough to put the
    /// paragraphs back together.
    private func paragraphGroupedInstructions(_ source: [String]) -> [AnalyzedRecipeStep]? {
        let wanted = source.map(normalized).filter { $0.count >= 12 }
        guard wanted.count >= 4 else { return nil }

        // Only the printed lines that carry a work step. Measuring the whole
        // page instead put the gap between the heading and the body into the
        // threshold, after which nothing inside the body separated any more.
        //
        // The rows arrive already joined into paragraphs, so a printed line is
        // a fragment of one rather than equal to it.
        var stepLines = lines.filter { line in
            let value = normalized(line.text)
            guard value.count >= 8 else { return false }
            return wanted.contains { $0.contains(value) }
        }
        // The paragraph blocks match their own text and would sit on top of the
        // lines they are made of, closing every gap between them.
        let heights = stepLines.map(\.boundingBox.height).sorted()
        guard !heights.isEmpty else { return nil }
        let medianHeight = heights[heights.count / 2]
        stepLines = stepLines.filter { $0.boundingBox.height < medianHeight * 1.8 }
        guard stepLines.count >= 4 else { return nil }

        var paragraphs: [(page: Int, y: CGFloat, text: String)] = []

        for page in Set(stepLines.map(\.page)).sorted() {
            let printed = stepLines
                .filter { $0.page == page }
                .sorted { $0.boundingBox.midY > $1.boundingBox.midY }
            guard printed.count >= 2 else { continue }

            let gaps = zip(printed, printed.dropFirst()).map {
                $0.boundingBox.minY - $1.boundingBox.maxY
            }
            let sorted = gaps.sorted()
            let medianGap = sorted[sorted.count / 2]
            // Evenly spaced lines carry no paragraph break to find, and any
            // threshold would then cut the text at an arbitrary place.
            // A multiple of the typical spacing, not the midpoint to the widest
            // gap: one outlier — a figure, a page break — otherwise lifts the
            // threshold above every real paragraph break.
            guard let widest = sorted.last, widest > medianGap * 1.8, medianGap > 0 else { continue }
            let breakAt = medianGap * 2

            var current: [RecognizedRecipeLine] = []
            func flush() {
                guard let first = current.first else { return }
                // A paragraph block and the lines it is made of both land in
                // the same group, so each sentence would otherwise be written
                // into the step twice.
                let text = cleanedLine(
                    deduplicatedParagraphs(current.map(\.text)).joined(separator: " ")
                )
                if !text.isEmpty { paragraphs.append((page, first.boundingBox.midY, text)) }
                current = []
            }
            for (index, line) in printed.enumerated() {
                if index > 0, gaps[index - 1] > breakAt { flush() }
                current.append(line)
            }
            flush()
        }

        // The time box above the steps is grouped like any other paragraph.
        paragraphs = paragraphs.filter { isUsefulInstruction($0.text) }

        // Fewer paragraphs than lines means the grouping actually joined
        // something; the same count means every line stayed on its own and the
        // sentence split does the job just as well.
        guard paragraphs.count >= 3, paragraphs.count < stepLines.count else { return nil }

        // On a magazine page, where a text box sits over a photograph, the
        // spacing carries no paragraph structure at all: grouping by it cut
        // the method into pieces and put them in the wrong order. A step that
        // begins in the middle of a word is the giveaway — every printed one
        // starts with a capital or a number.
        let startsCleanly = paragraphs.allSatisfy { paragraph in
            guard let first = paragraph.text.first else { return false }
            return first.isUppercase || first.isNumber
        }
        guard startsCleanly else { return nil }

        let groupedLength = paragraphs.reduce(0) { $0 + $1.text.count }
        let printedLength = Set(wanted).reduce(0) { $0 + $1.count }
        guard Double(groupedLength) >= Double(printedLength) * 0.8 else { return nil }

        var steps: [AnalyzedRecipeStep] = []
        for paragraph in paragraphs {
            let text = condensedIngredientLists(in: removingListMarker(from: paragraph.text))
            // Baking under a lid and browning without it are one printed step
            // but two waits, and read together the shorter of the two wins —
            // an hour in the oven came out as twelve minutes.
            if normalized(text).contains("deckel abnehmen"),
               let lidRange = text.range(of: "Dann den Deckel", options: .caseInsensitive) {
                let covered = String(text[..<lidRange.lowerBound])
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                let uncovered = String(text[lidRange.lowerBound...])
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                steps.append(AnalyzedRecipeStep(
                    step: Double(steps.count + 1),
                    text: covered,
                    duration: estimatedDuration(in: covered)
                ))
                steps.append(AnalyzedRecipeStep(
                    step: Double(steps.count + 1),
                    text: uncovered,
                    duration: averageMinuteRange(in: uncovered) ?? duration(in: uncovered)
                ))
                continue
            }
            steps.append(AnalyzedRecipeStep(
                step: Double(steps.count + 1),
                text: text,
                duration: estimatedDuration(in: paragraph.text)
            ))
        }
        return steps
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

        // The numbers have to run 1, 2, 3 … without a hole. A page whose step
        // badges are set in pale grey is read unevenly — one device returned
        // 1, 2, 4, 5 and, with the missing badge, the text of two steps landed
        // under one number. Grouping by an incomplete numbering is worse than
        // not grouping by number at all.
        let numbers = groupedSteps.map(\.number)
        guard numbers.first == 1,
              numbers == Array(1...numbers.count) else {
            return nil
        }

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

    /// Splits prose into sentences. The abbreviations a recipe abbreviates with
    /// are excluded, because "20 Min. kaltstellen" and "bei 180 Grad ca. 15 Min.
    /// backen" would otherwise each become two steps — and the one carrying the
    /// duration would lose the action it belongs to.
    private func sentenceParts(_ text: String) -> [String] {
        let abbreviations: [String] = [
            "min", "mín", "std", "stdn", "ca", "bzw", "evtl", "ggf", "usw",
            "z", "b", "el", "tl", "pck", "gr", "kl", "abb", "nr", "vgl"
        ]
        var pattern = #"(?<=[.!?])"#
        for abbreviation in abbreviations {
            pattern += #"(?<!\b"# + abbreviation + #"\.)"#
        }
        pattern += #"\s+"#
        let expression = try? NSRegularExpression(
            pattern: pattern,
            options: [.caseInsensitive]
        )
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

    /// Whether a line is the heading of an ingredient list. The article in front
    /// of it is ignored: a page printing "Les ingrédients :" means the same
    /// section as one printing the bare word, and without this the whole page
    /// fell through to the last reading, which collects amounts from every
    /// sentence — the page count "Seite 1 von 2" among them.
    private func isIngredientHeading(_ value: String) -> Bool {
        let articles = ["les", "la", "le", "die", "der", "das"]
        var words = value.split(separator: " ").map(String.init)
        if let first = words.first, articles.contains(first) {
            words.removeFirst()
        }
        let heading = words.joined(separator: " ")
        return ["zutaten", "zutatenliste", "ingredients", "ingredienten"].contains(heading)
            || heading.hasPrefix("zutaten fur ")
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
            && !isPageFurnitureLine(line)
            // "Zutaten" and "Zubereitung" are set as large as the recipe's name
            // on a two-column web page, and on one that is cropped below its
            // heading they would become the name.
            && !isIngredientHeading(value)
            && !isInstructionHeading(value)
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
        // "1 Std. 25 Min." separates its two values with nothing but a space,
        // so the separator has to be optional — otherwise a time box reads as
        // a work step. "Sta." is not a typo: that is how the OCR returns the
        // abbreviation on a screenshot often enough to matter.
        let isOnlyTimeValue = line.range(
            of: #"^\s*\d+(?:[.,]\d+)?\s*(?:Std\.?|Sta\.?|Stunden?|Min(?:ute)?n?\.?|h)(?:\s*[,/]?\s*\d+\s*Min(?:ute)?n?\.?)?\s*$"#,
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
        case "gramme", "grammes", "gr": return "g"
        default: return unit
        }
    }

    private func cleanedIngredientName(_ text: String) -> String {
        // A written-out article has to end at a word boundary: "de la" also
        // matches the first letters of "de lardons fumés", and stripping it
        // left "rdons". The elided "d'" is the exception — it is written
        // against its noun, as in "d'emmental râpé".
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(
                of: #"^(?:(?:de la|du|des|de)(?![\p{L}])\s*|d['’]\s*)"#,
                with: "",
                options: [.regularExpression, .caseInsensitive]
            )

        // A closing parenthesis whose opening one the OCR lost — "Wasser 40 °C)"
        // for "Wasser (40 °C)" — only adds a stray character to the name.
        let closed = value.filter { $0 == ")" }.count
        let opened = value.filter { $0 == "(" }.count
        if closed > opened, value.hasSuffix(")") {
            return String(value.dropLast()).trimmingCharacters(in: .whitespaces)
        }

        // A parenthesis that never closes means its remainder wrapped onto a
        // line the OCR returned separately. The bare name reads better than a
        // dangling fragment such as "Walnüsse (geröstet".
        guard opened > closed,
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
