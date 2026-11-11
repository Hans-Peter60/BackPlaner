//
//  CloudRecipeImport.swift
//  BakePlannerCore
//
//  What the cloud AI answers when it reads a recipe (Cloud Functions
//  analyzeRecipeImages and analyzeRecipeText), the recipe built from it,
//  and the last pass over an imported recipe. Moved from the app
//  (FirebaseFunctionsClient.swift, HybridRecipeImageAnalysisAgent.swift) so
//  the Android app reads the same answers the same way.
//

import Foundation

public struct CloudRecipeAnalysis: Decodable, Sendable {
    public let recipe: CloudRecipe
    public let model: String
    /// The month's free cloud imports, counting this one — sent only while
    /// a monthly allowance applies to this installation (no Pro, limit set).
    public let freeImports: FreeImports?

    /// How many free cloud imports the month allows and how many are used.
    public struct FreeImports: Decodable, Sendable, Equatable {
        public let used: Int
        public let limit: Int

        public init(used: Int, limit: Int) {
            self.used = used
            self.limit = limit
        }

        public var remaining: Int { max(0, limit - used) }

        /// What to tell the person after an import, so the end of the
        /// allowance does not come as a surprise: nothing while plenty are
        /// left, a count for the last two, and the plain fact for the last.
        public func notice(bundle: Bundle = AppSettings.localizationBundle, locale: Locale = AppSettings.locale) -> String? {
            switch remaining {
            case 0:
                return String(localized: "Das war der letzte kostenlose Cloud-Import dieses Monats. Bis zum Monatsende liest die App weitere Rezepte auf dem Gerät; mit BakePlanner Pro gibt es kein Monatslimit.",
                              bundle: bundle, locale: locale)
            case 1:
                return String(localized: "Noch ein kostenloser Cloud-Import in diesem Monat.", bundle: bundle, locale: locale)
            case 2:
                return String(format: String(localized: "Noch %lld kostenlose Cloud-Importe in diesem Monat.", bundle: bundle, locale: locale),
                              locale: locale, remaining)
            default:
                return nil
            }
        }
    }

    public init(recipe: CloudRecipe, model: String, freeImports: FreeImports? = nil) {
        self.recipe = recipe
        self.model = model
        self.freeImports = freeImports
    }

    /// The function's answer as the Android SDK hands it out: dictionaries,
    /// arrays and numbers as Long or Double. Read field by field, the way
    /// the JSON decoding on the iPhone reads them; nil when it is no recipe.
    public init?(response: Any) {
        guard let dictionary = response as? [String: Any],
              let recipe = (dictionary["recipe"] as? [String: Any]).flatMap(CloudRecipe.init(response:)) else {
            return nil
        }
        var freeImports: FreeImports?
        if let allowance = dictionary["freeImports"] as? [String: Any],
           let used = RecipeFirestoreMapping.int(allowance["used"]),
           let limit = RecipeFirestoreMapping.int(allowance["limit"]), limit > 0 {
            freeImports = FreeImports(used: used, limit: limit)
        }
        self.init(recipe: recipe, model: dictionary["model"] as? String ?? "", freeImports: freeImports)
    }
}

public struct CloudRecipe: Decodable, Sendable {
    public let title: String
    public let summary: String
    public let sourceLanguage: String
    public let preparationMinutes: Int
    public let components: [CloudRecipeComponent]
    public let instructions: [CloudRecipeInstruction]
    public let warnings: [String]

    public init(title: String, summary: String, sourceLanguage: String, preparationMinutes: Int,
                components: [CloudRecipeComponent], instructions: [CloudRecipeInstruction], warnings: [String]) {
        self.title = title
        self.summary = summary
        self.sourceLanguage = sourceLanguage
        self.preparationMinutes = preparationMinutes
        self.components = components
        self.instructions = instructions
        self.warnings = warnings
    }

    init?(response data: [String: Any]) {
        typealias Value = RecipeFirestoreMapping
        let components = (data["components"] as? [Any] ?? []).compactMap { item -> CloudRecipeComponent? in
            guard let component = item as? [String: Any] else { return nil }
            let ingredients = (component["ingredients"] as? [Any] ?? []).compactMap { item -> CloudRecipeIngredient? in
                guard let ingredient = item as? [String: Any] else { return nil }
                return CloudRecipeIngredient(name: ingredient["name"] as? String ?? "",
                                             amount: Value.double(ingredient["amount"]) ?? 0,
                                             unit: ingredient["unit"] as? String ?? "")
            }
            return CloudRecipeComponent(name: component["name"] as? String ?? "", ingredients: ingredients)
        }
        let instructions = (data["instructions"] as? [Any] ?? []).compactMap { item -> CloudRecipeInstruction? in
            guard let instruction = item as? [String: Any] else { return nil }
            return CloudRecipeInstruction(text: instruction["text"] as? String ?? "",
                                          durationMinutes: Value.int(instruction["durationMinutes"]) ?? 0,
                                          componentName: instruction["componentName"] as? String ?? "",
                                          isBaking: instruction["isBaking"] as? Bool ?? false)
        }
        guard data["title"] != nil || !components.isEmpty || !instructions.isEmpty else { return nil }
        self.init(title: data["title"] as? String ?? "",
                  summary: data["summary"] as? String ?? "",
                  sourceLanguage: data["sourceLanguage"] as? String ?? "",
                  preparationMinutes: Value.int(data["preparationMinutes"]) ?? 0,
                  components: components,
                  instructions: instructions,
                  warnings: (data["warnings"] as? [Any] ?? []).compactMap { $0 as? String })
    }

    @MainActor
    public func makeRecipe() -> RecipeFB {
        let recipe = RecipeFB()
        recipe.name = title.trimmingCharacters(in: .whitespacesAndNewlines)
        recipe.summary = summary.trimmingCharacters(in: .whitespacesAndNewlines)
        recipe.sourceLanguage = sourceLanguage.trimmingCharacters(in: .whitespacesAndNewlines)
        recipe.prepTime = max(0, preparationMinutes)

        recipe.components = components.enumerated().compactMap { index, source in
            let ingredients = source.ingredients.enumerated().compactMap {
                ingredientIndex, source -> IngredientFB? in
                let name = source.name.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !name.isEmpty else { return nil }

                let ingredient = IngredientFB()
                ingredient.id = UUID().uuidString
                ingredient.number = ingredientIndex + 1
                ingredient.name = name
                ingredient.weight = max(0, source.amount)
                ingredient.normWeight = ingredient.weight
                ingredient.unit = source.unit.trimmingCharacters(in: .whitespacesAndNewlines)
                return ingredient
            }
            guard !ingredients.isEmpty else { return nil }

            let component = ComponentFB()
            component.id = UUID().uuidString
            component.number = index + 1
            let name = source.name.trimmingCharacters(in: .whitespacesAndNewlines)
            component.name = name.isEmpty
                ? String(localized: "Hauptteig", bundle: AppSettings.localizationBundle)
                : name
            component.ingredients = ingredients
            return component
        }

        let isMultiComponent = recipe.components.count > 1
        recipe.instructions = instructions.enumerated().compactMap { index, source in
            let text = source.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { return nil }

            let componentName = source.componentName
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let instruction = InstructionFB()
            instruction.id = UUID().uuidString
            instruction.step = Double(index + 1)
            instruction.instruction = RecipeImportStepText.text(
                text, naming: componentName, inMultiComponentRecipe: isMultiComponent
            )
            instruction.duration = max(0, source.durationMinutes)
            if instruction.duration == 0, text.describesOvenPreheating {
                instruction.duration = GlobalVariables.preheatTime(for: text)
            }
            instruction.componentName = componentName.isEmpty ? nil : componentName
            instruction.bakeFlag = source.isBaking
            return instruction
        }

        recipe.totalWeight = recipe.components
            .flatMap(\.ingredients)
            .reduce(0) { $0 + $1.weight }
        return recipe
    }
}

public struct CloudRecipeComponent: Decodable, Sendable {
    public let name: String
    public let ingredients: [CloudRecipeIngredient]

    public init(name: String, ingredients: [CloudRecipeIngredient]) {
        self.name = name
        self.ingredients = ingredients
    }
}

public struct CloudRecipeIngredient: Decodable, Sendable {
    public let name: String
    public let amount: Double
    public let unit: String

    public init(name: String, amount: Double, unit: String) {
        self.name = name
        self.amount = amount
        self.unit = unit
    }
}

public struct CloudRecipeInstruction: Decodable, Sendable {
    public let text: String
    public let durationMinutes: Int
    public let componentName: String
    public let isBaking: Bool

    public init(text: String, durationMinutes: Int, componentName: String, isBaking: Bool) {
        self.text = text
        self.durationMinutes = durationMinutes
        self.componentName = componentName
        self.isBaking = isBaking
    }
}

/// Lays imported steps out the way the app plans a bake: every component
/// that goes into the final dough (sourdough, pre-dough, soaker …) becomes one
/// parallel step 1.1, 1.2, … that spans mixing and maturing, and the final
/// dough's steps follow as 2, 3, 4 …. Sources list the same four sentences
/// under every pre-dough; as separate sequential steps they would stretch a
/// 12-hour overnight recipe to two days.
public enum RecipeImportPlan {
    /// Minutes of handling for each component that is mixed after this one.
    /// The planner starts parallel preparations this far apart, so an earlier
    /// one runs correspondingly longer and all of them are ready together for
    /// the final dough.
    public static let handlingMinutesPerComponent = Rational.preparationStaggerMinutes

    @MainActor
    public static func groupComponentPreparations(in recipe: RecipeFB) {
        let names = recipe.components.map(\.name)
        guard names.count > 1 else { return }

        // The final dough is the component that uses others up ("gesamter
        // Roggensauerteig", weight 0) without being used up itself. Every
        // component listed before it is a preparation, whether or not its own
        // "gesamte …" row survived the import; components listed after it
        // (a glaze, a filling) keep their place in the sequence. Without any
        // such rows the last component is taken for the final dough.
        let dependencies = Rational.ComponentDependency.from(recipe.components)
        let consumed = Set(dependencies.flatMap(\.requires))
        let consumers = Set(dependencies.filter { !$0.requires.isEmpty }.map(\.name))
        let finalIndex = names.firstIndex { consumers.contains($0) && !consumed.contains($0) }
            ?? names.firstIndex { consumers.contains($0) }
            ?? names.index(before: names.endIndex)
        let preparationNames = Array(names[..<finalIndex])
        AppLog.data.debug(
            "Recipe import plan: components \(names), final \(names[finalIndex]), step components \(recipe.instructions.map { $0.componentName ?? "-" })"
        )

        var remaining = recipe.instructions
        var preparations: [InstructionFB] = []
        var mergedAny = false
        for name in preparationNames {
            let own = remaining.filter { belongs($0, to: name) }
            guard !own.isEmpty else { continue }
            remaining.removeAll { step in own.contains { $0 === step } }
            if own.count > 1 { mergedAny = true }
            preparations.append(merged(own, component: name))
        }
        guard !preparations.isEmpty else { return }

        let multiple = preparations.count > 1
        for (index, step) in preparations.enumerated() {
            step.step = multiple ? 1 + Double(index + 1) / (preparations.count > 9 ? 100 : 10) : 1
            if mergedAny, multiple {
                step.duration += handlingMinutesPerComponent * (preparations.count - 1 - index)
            }
        }

        // The final dough's steps keep their order. Only its first step keeps
        // the component, so a reminder for folding or baking does not list the
        // whole ingredient table again. And only the first of a run of steps
        // on the same component names it in its text: "Hauptteig: kneten",
        // then "falten", "formen", "backen" — not "Hauptteig: …" five times
        // over, which is how the models deliver them. A change of component
        // in between (a filling, a glaze) names the next one again.
        var seenComponents = Set<String>()
        var previousComponent: String?
        for (index, step) in remaining.enumerated() {
            step.step = Double(index + 2)
            let component = step.componentName ?? names.first { belongs(step, to: $0) }
            if let component, let previousComponent,
               component.compare(previousComponent, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame {
                step.instruction = withoutLeadIn(step.instruction, component: component)
            }
            previousComponent = component
            if let name = step.componentName {
                if seenComponents.contains(name) {
                    step.componentName = nil
                } else {
                    seenComponents.insert(name)
                }
            }
        }
        recipe.instructions = preparations + remaining
    }

    /// The text without its "Hauptteig: " lead-in; unchanged when nothing
    /// else would be left.
    private static func withoutLeadIn(_ text: String, component: String) -> String {
        let prefix = "^\\s*" + NSRegularExpression.escapedPattern(for: component) + "\\s*:\\s*"
        let stripped = text
            .replacingOccurrences(of: prefix, with: "", options: [.regularExpression, .caseInsensitive])
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return stripped.isEmpty ? text : stripped
    }

    /// Whether a step prepares the component: by its stored component, or by
    /// the "Quellstück: …" lead-in when the model named it only in the text.
    @MainActor
    private static func belongs(_ step: InstructionFB, to component: String) -> Bool {
        let options: String.CompareOptions = [.caseInsensitive, .diacriticInsensitive]
        if let stored = step.componentName?.trimmingCharacters(in: .whitespacesAndNewlines),
           stored.compare(component, options: options) == .orderedSame {
            return true
        }
        let text = step.instruction.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let colon = text.firstIndex(of: ":") else { return false }
        let leadIn = text[..<colon].trimmingCharacters(in: .whitespaces)
        return leadIn.compare(component, options: options) == .orderedSame
    }

    /// One step for a component: the texts in order, named once, with the
    /// durations added up and the component's bake flag kept.
    @MainActor
    private static func merged(_ steps: [InstructionFB], component: String) -> InstructionFB {
        guard steps.count > 1, let first = steps.first else { return steps[0] }
        let prefix = "^\\s*" + NSRegularExpression.escapedPattern(for: component) + "\\s*:\\s*"
        let texts = steps.map {
            $0.instruction
                .replacingOccurrences(of: prefix, with: "", options: [.regularExpression, .caseInsensitive])
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }.filter { !$0.isEmpty }

        let instruction = InstructionFB()
        instruction.id = first.id
        instruction.instruction = "\(component): " + texts.joined(separator: " ")
        instruction.duration = steps.reduce(0) { $0 + max(0, $1.duration) }
        instruction.bakeFlag = steps.contains { $0.bakeFlag == true }
        instruction.componentName = component
        return instruction
    }
}

/// Whether an imported recipe has what makes it one: a name, an
/// ingredient and a step. A cloud answer without them is not used.
public enum RecipeImportCheck {
    @MainActor
    public static func hasRecipeData(_ recipe: RecipeFB) -> Bool {
        let name = recipe.name.trimmingCharacters(in: .whitespacesAndNewlines)
        let ingredientCount = recipe.components.reduce(0) { $0 + $1.ingredients.count }
        let instructionCount = recipe.instructions.filter {
            !$0.instruction.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }.count
        return !name.isEmpty && ingredientCount > 0 && instructionCount > 0
    }
}

private extension String {
    var describesOvenPreheating: Bool {
        let normalized = folding(
            options: [.caseInsensitive, .diacriticInsensitive],
            locale: Locale(identifier: "de_DE")
        )
        let ovenTerms = ["ofen", "backofen", "oven", "four", "forno"]
        let preheatTerms = ["vorheiz", "aufheiz", "preheat", "préchauff", "préchauffer"]
        return ovenTerms.contains(where: normalized.contains)
            && preheatTerms.contains(where: normalized.contains)
    }
}
