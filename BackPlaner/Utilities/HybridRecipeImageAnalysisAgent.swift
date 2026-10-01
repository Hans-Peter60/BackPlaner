import Foundation
import FoundationModels
import UIKit

/// Adds semantic, schema-constrained recipe extraction to the existing Vision
/// reader. The original reader remains the source of OCR data and the fallback
/// whenever Apple Intelligence is unavailable or produces an implausible result.
@MainActor
final class HybridRecipeImageAnalysisAgent {

    private let localAgent = RecipeImageAnalysisAgent()

    func analyze(
        images: [UIImage],
        progress: @escaping @MainActor (Int, Int) -> Void = { _, _ in }
    ) async throws -> RecipeImageAnalysisResult {
        do {
            let cloudResult = try await FirebaseFunctionsClient.shared
                .analyzeRecipeImages(images)
            let recipe = cloudResult.recipe.makeRecipe()
            try validateCloudRecipe(recipe)
            AppLog.data.debug(
                "Recipe import: cloud AI result accepted (\(cloudResult.model))"
            )
            return RecipeImageAnalysisResult(
                recipe: recipe,
                recognizedText: "",
                recipeImage: images.first,
                warnings: cloudResult.recipe.warnings,
                analysisSource: .cloudAI
            )
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            AppLog.data.warning(
                "Recipe import: cloud AI unavailable or rejected; using local analysis: \(error.localizedDescription)"
            )
        }

        return try await analyzeLocally(images: images, progress: progress)
    }

    /// Analyzes the images without contacting Firebase, Vertex AI, or another
    /// server. Apple Intelligence is used when it is available; otherwise the
    /// deterministic Vision-based reader remains the fallback.
    func analyzeLocally(
        images: [UIImage],
        progress: @escaping @MainActor (Int, Int) -> Void = { _, _ in }
    ) async throws -> RecipeImageAnalysisResult {
        let localResult = try await localAgent.analyze(images: images, progress: progress)

        guard SystemLanguageModel.default.isAvailable else {
            return localResult
        }

        do {
            let aiResult = try await analyzeWithOnDeviceModel(localResult)
            AppLog.data.debug("Recipe import: on-device AI result accepted")
            return aiResult
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            AppLog.data.warning(
                "Recipe import: on-device AI unavailable or rejected; using local result: \(error.localizedDescription)"
            )
            return localResult
        }
    }

    func analyzeGeneralRecipe(
        images: [UIImage],
        progress: @escaping @MainActor (Int, Int) -> Void = { _, _ in }
    ) async throws -> RecipeImageAnalysisResult {
        try await localAgent.analyzeGeneralRecipe(images: images, progress: progress)
    }

    func analyzeSpecialRecipe(
        images: [UIImage],
        progress: @escaping @MainActor (Int, Int) -> Void = { _, _ in }
    ) async throws -> RecipeImageAnalysisResult {
        try await localAgent.analyzeSpecialRecipe(images: images, progress: progress)
    }

    private func analyzeWithOnDeviceModel(
        _ localResult: RecipeImageAnalysisResult
    ) async throws -> RecipeImageAnalysisResult {
        let session = LanguageModelSession(instructions: """
            Du extrahierst Backrezepte aus OCR-Text. Übernimm ausschließlich Angaben,
            die im Text stehen. Erfinde keine Zutaten, Mengen, Zeiten, Temperaturen
            oder Arbeitsschritte. Bewahre die Originalsprache. Trenne Vorteige,
            Sauerteige, Brühstücke und Hauptteig in eigene Komponenten. Verwende eine
            leere Zeichenfolge oder 0, wenn eine Angabe fehlt. Schreibe jede
            Unsicherheit in warnings.
            """)

        let source = String(localResult.recognizedText.prefix(10_000))
        let prompt = """
            Strukturiere den folgenden OCR-Text als vollständiges Backrezept.
            Einheiten bleiben so erhalten, wie sie gedruckt sind. durationMinutes
            enthält nur ausdrücklich genannte Dauern in Minuten. componentName
            bezeichnet bei einem Vorbereitungsschritt die betroffene Komponente.

            OCR-TEXT:
            \(source)
            """

        let response = try await session.respond(
            to: prompt,
            generating: GeneratedRecipe.self
        )
        let generated = response.content
        let recipe = generated.makeRecipe()
        try validate(recipe: recipe, comparedWith: localResult.recipe)

        let modelWarnings = generated.warnings
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        let warnings = Array(Set(localResult.warnings + modelWarnings)).sorted()

        return RecipeImageAnalysisResult(
            recipe: recipe,
            recognizedText: localResult.recognizedText,
            recipeImage: localResult.recipeImage,
            warnings: warnings,
            layout: localResult.layout,
            titleOptions: localResult.titleOptions,
            analysisSource: .onDeviceAI
        )
    }

    private func validateCloudRecipe(_ recipe: RecipeFB) throws {
        let name = recipe.name.trimmingCharacters(in: .whitespacesAndNewlines)
        let ingredientCount = recipe.components.reduce(0) {
            $0 + $1.ingredients.count
        }
        let instructionCount = recipe.instructions.filter {
            !$0.instruction.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }.count

        guard !name.isEmpty, ingredientCount > 0, instructionCount > 0 else {
            throw RecipeImageAnalysisError.insufficientRecipeData
        }
    }

    private func validate(recipe: RecipeFB, comparedWith localRecipe: RecipeFB) throws {
        let name = recipe.name.trimmingCharacters(in: .whitespacesAndNewlines)
        let ingredients = recipe.components.flatMap(\.ingredients)
        let instructions = recipe.instructions.filter {
            !$0.instruction.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }

        guard !name.isEmpty, !ingredients.isEmpty, !instructions.isEmpty else {
            throw RecipeImageAnalysisError.insufficientRecipeData
        }

        let localIngredientCount = localRecipe.components.reduce(0) {
            $0 + $1.ingredients.count
        }
        let localInstructionCount = localRecipe.instructions.count

        // A semantic pass may merge duplicates, but losing most of an already
        // successful local reading is a strong indication of truncated output.
        if localIngredientCount >= 4,
           ingredients.count * 2 < localIngredientCount {
            throw RecipeImageAnalysisError.insufficientRecipeData
        }
        if localInstructionCount >= 4,
           instructions.count * 2 < localInstructionCount {
            throw RecipeImageAnalysisError.insufficientRecipeData
        }
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

@Generable
private struct GeneratedRecipe {
    @Guide(description: "Der gedruckte Titel des Rezepts")
    var title: String

    @Guide(description: "Kurze Zusammenfassung; leer, wenn keine vorhanden ist")
    var summary: String

    @Guide(description: "BCP-47-Sprachcode des Rezepttexts, zum Beispiel de oder fr")
    var sourceLanguage: String

    @Guide(description: "Gesamte ausdrücklich genannte Vorbereitungszeit in Minuten; sonst 0")
    var preparationMinutes: Int

    @Guide(description: "Rezeptbestandteile mit ihren Zutaten", .maximumCount(12))
    var components: [GeneratedComponent]

    @Guide(description: "Arbeitsschritte in gedruckter Reihenfolge", .maximumCount(40))
    var instructions: [GeneratedInstruction]

    @Guide(description: "Unklare, widersprüchliche oder unvollständige Stellen", .maximumCount(12))
    var warnings: [String]

    func makeRecipe() -> RecipeFB {
        let recipe = RecipeFB()
        recipe.name = title.trimmingCharacters(in: .whitespacesAndNewlines)
        recipe.summary = summary.trimmingCharacters(in: .whitespacesAndNewlines)
        recipe.sourceLanguage = sourceLanguage.trimmingCharacters(in: .whitespacesAndNewlines)
        recipe.prepTime = max(0, preparationMinutes)

        recipe.components = components.enumerated().compactMap { index, source in
            let ingredients = source.ingredients.enumerated().compactMap {
                ingredientIndex, generated -> IngredientFB? in
                let name = generated.name.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !name.isEmpty else { return nil }

                let ingredient = IngredientFB()
                ingredient.id = UUID().uuidString
                ingredient.number = ingredientIndex + 1
                ingredient.name = name
                ingredient.weight = max(0, generated.amount)
                ingredient.normWeight = ingredient.weight
                ingredient.unit = generated.unit.trimmingCharacters(in: .whitespacesAndNewlines)
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

        recipe.instructions = instructions.enumerated().compactMap { index, source in
            let text = source.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { return nil }

            let instruction = InstructionFB()
            instruction.id = UUID().uuidString
            instruction.step = Double(index + 1)
            instruction.instruction = text
            instruction.duration = max(0, source.durationMinutes)
            if instruction.duration == 0, text.describesOvenPreheating {
                instruction.duration = GlobalVariables.preheatTime
            }
            let componentName = source.componentName
                .trimmingCharacters(in: .whitespacesAndNewlines)
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

@Generable
private struct GeneratedComponent {
    @Guide(description: "Name wie Sauerteig, Vorteig, Brühstück oder Hauptteig")
    var name: String

    @Guide(description: "Zutaten dieser Komponente", .maximumCount(40))
    var ingredients: [GeneratedIngredient]
}

@Generable
private struct GeneratedIngredient {
    @Guide(description: "Name der Zutat ohne Menge und Einheit")
    var name: String

    @Guide(description: "Gedruckte numerische Menge; 0, wenn keine Zahl angegeben ist")
    var amount: Double

    @Guide(description: "Gedruckte Einheit wie g, kg, ml, TL, EL oder Stück; sonst leer")
    var unit: String
}

@Generable
private struct GeneratedInstruction {
    @Guide(description: "Vollständiger Text des Arbeitsschritts")
    var text: String

    @Guide(description: "Ausdrücklich genannte Dauer in Minuten; sonst 0")
    var durationMinutes: Int

    @Guide(description: "Vorbereitete Komponente; leer, wenn der Schritt keiner zugeordnet ist")
    var componentName: String

    @Guide(description: "Wahr, wenn dies ein Backschritt ist")
    var isBaking: Bool
}
