import BakePlannerCore
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
            return withDefaultDurations(RecipeImageAnalysisResult(
                recipe: recipe,
                recognizedText: "",
                recipeImage: images.first,
                warnings: cloudResult.recipe.warnings,
                analysisSource: .cloudAI
            ), groupingComponents: true)
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            AppLog.data.warning(
                "Recipe import: cloud AI unavailable or rejected; using local analysis: \(error.localizedDescription)"
            )
            // The month's free cloud imports are used up: the local result
            // says so, because otherwise the person would not know why the
            // analysis came out differently from last time.
            if case FirebaseFunctionsClientError.monthlyLimitReached = error {
                return try await analyzeLocally(images: images, progress: progress)
                    .addingWarning(error.localizedDescription)
            }
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
            return withDefaultDurations(localResult)
        }

        do {
            let aiResult = try await analyzeWithOnDeviceModel(localResult)
            AppLog.data.debug("Recipe import: on-device AI result accepted")
            return withDefaultDurations(aiResult, groupingComponents: true)
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            AppLog.data.warning(
                "Recipe import: on-device AI unavailable or rejected; using local result: \(error.localizedDescription)"
            )
            return withDefaultDurations(localResult)
        }
    }

    func analyzeGeneralRecipe(
        images: [UIImage],
        progress: @escaping @MainActor (Int, Int) -> Void = { _, _ in }
    ) async throws -> RecipeImageAnalysisResult {
        withDefaultDurations(try await localAgent.analyzeGeneralRecipe(images: images, progress: progress))
    }

    func analyzeSpecialRecipe(
        images: [UIImage],
        progress: @escaping @MainActor (Int, Int) -> Void = { _, _ in }
    ) async throws -> RecipeImageAnalysisResult {
        withDefaultDurations(try await localAgent.analyzeSpecialRecipe(images: images, progress: progress))
    }

    /// The last pass over an imported recipe. Model results are laid out the
    /// way the app plans (one parallel step per pre-dough, then the main
    /// dough), and every step gets at least the default duration, so no step
    /// collapses to zero minutes in the plan and the reminders.
    ///
    /// The rule-based image readers keep their own numbering: the two-column
    /// reader derives it from the page's planning example, the general one
    /// already groups the preparations itself.
    private func withDefaultDurations(
        _ result: RecipeImageAnalysisResult,
        groupingComponents: Bool = false
    ) -> RecipeImageAnalysisResult {
        if groupingComponents {
            RecipeImportPlan.groupComponentPreparations(in: result.recipe)
        }
        RecipeImportStepText.applyDefaultDuration(to: result.recipe.instructions)
        return result
    }

    // MARK: - Web pages

    /// Structures a recipe web page. The stages are the same as for images:
    /// cloud first when allowed, then Apple Intelligence, and finally the
    /// page's own structured data, which needs no model at all.
    func analyzeWebPage(
        _ page: RecipeWebPage,
        allowCloud: Bool,
        progress: @escaping @MainActor (String) -> Void = { _ in }
    ) async throws -> RecipeImageAnalysisResult {
        async let image = RecipeWebPageLoader.loadImage(from: page.imageURL)
        let baseline = page.structuredRecipe?.makeRecipe()
        let text = page.analysisText

        var result: RecipeImageAnalysisResult?
        // Set when the month's free cloud imports are used up, so the
        // result can say why the cloud stayed out of it.
        var cloudLimitNotice: String?
        if allowCloud {
            progress(String(localized: "Rezept wird in der Cloud analysiert …", bundle: AppSettings.localizationBundle))
            do {
                let cloudResult = try await FirebaseFunctionsClient.shared
                    .analyzeRecipeText(text, sourceURL: page.url)
                let recipe = cloudResult.recipe.makeRecipe()
                try validateCloudRecipe(recipe)
                AppLog.data.debug("Recipe web import: cloud AI result accepted (\(cloudResult.model))")
                result = RecipeImageAnalysisResult(
                    recipe: recipe,
                    recognizedText: text,
                    warnings: cloudResult.recipe.warnings,
                    analysisSource: .cloudAI
                )
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                AppLog.data.warning("Recipe web import: cloud AI unavailable or rejected; using local analysis: \(error.localizedDescription)")
                if case FirebaseFunctionsClientError.monthlyLimitReached = error {
                    cloudLimitNotice = error.localizedDescription
                }
            }
        }

        if result == nil, SystemLanguageModel.default.isAvailable {
            progress(String(localized: "Rezept wird auf dem Gerät analysiert …", bundle: AppSettings.localizationBundle))
            do {
                let (recipe, warnings) = try await generateRecipeOnDevice(
                    from: text,
                    sourceDescription: "dem Text einer Internetseite"
                )
                try validate(recipe: recipe, comparedWith: baseline)
                AppLog.data.debug("Recipe web import: on-device AI result accepted")
                result = RecipeImageAnalysisResult(
                    recipe: recipe,
                    recognizedText: text,
                    warnings: warnings,
                    analysisSource: .onDeviceAI
                )
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                AppLog.data.warning("Recipe web import: on-device AI unavailable or rejected: \(error.localizedDescription)")
            }
        }

        if result == nil {
            guard let baseline else { throw RecipeWebImportError.noRecipeFound }
            try validateCloudRecipe(baseline)
            let warning = String(localized: "Das Rezept wurde ohne KI aus den strukturierten Daten der Seite übernommen. Komponenten und Dauern bitte besonders prüfen.", bundle: AppSettings.localizationBundle)
            result = RecipeImageAnalysisResult(
                recipe: baseline,
                recognizedText: text,
                warnings: [warning],
                analysisSource: .localRules
            )
        }

        guard let result else { throw RecipeWebImportError.noRecipeFound }
        let recipe = result.recipe
        recipe.urlLink = page.url.absoluteString
        if recipe.sourceLanguage.isEmpty { recipe.sourceLanguage = page.language }
        if recipe.name.isEmpty { recipe.name = page.title }
        return withDefaultDurations(RecipeImageAnalysisResult(
            recipe: recipe,
            recognizedText: result.recognizedText,
            recipeImage: await image,
            warnings: result.warnings + (cloudLimitNotice.map { [$0] } ?? []),
            analysisSource: result.analysisSource
        ), groupingComponents: true)
    }

    // MARK: - On-device model

    private func analyzeWithOnDeviceModel(
        _ localResult: RecipeImageAnalysisResult
    ) async throws -> RecipeImageAnalysisResult {
        let (recipe, modelWarnings) = try await generateRecipeOnDevice(
            from: localResult.recognizedText,
            sourceDescription: "OCR-Text"
        )
        try validate(recipe: recipe, comparedWith: localResult.recipe)
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

    /// Asks Apple Intelligence to structure recipe text. Shared by the image
    /// import (OCR text) and the web import (page text).
    private func generateRecipeOnDevice(
        from text: String,
        sourceDescription: String
    ) async throws -> (recipe: RecipeFB, warnings: [String]) {
        let session = LanguageModelSession(instructions: """
            Du extrahierst Backrezepte aus \(sourceDescription). Übernimm ausschließlich
            Angaben, die im Text stehen. Erfinde keine Zutaten, Mengen, Zeiten,
            Temperaturen oder Arbeitsschritte. Ignoriere Navigation, Werbung und
            Kommentare. Bewahre die Originalsprache. Trenne Vorteige, Sauerteige,
            Brühstücke und Hauptteig in eigene Komponenten. Verwende eine leere
            Zeichenfolge oder 0, wenn eine Angabe fehlt. Schreibe jede Unsicherheit
            in warnings.
            """)

        let source = String(text.prefix(10_000))
        let prompt = """
            Strukturiere den folgenden Text als vollständiges Backrezept.
            Einheiten bleiben so erhalten, wie sie gedruckt sind. durationMinutes
            enthält nur ausdrücklich genannte Dauern in Minuten. componentName
            bezeichnet bei einem Vorbereitungsschritt die betroffene Komponente.
            Jeder Schritt muss für sich allein verständlich sein: Gehört er zu
            einer Komponente, beginnt sein Text mit deren Namen und Doppelpunkt,
            zum Beispiel "Sauerteig: 12 Stunden reifen lassen." Zutatenzeilen wie
            "gesamter Sauerteig" im Hauptteig bleiben als Zutat mit Menge 0
            erhalten. Für jede Komponente, die in den Hauptteig eingeht, fasse
            Herstellung und Reifung zu einem Schritt zusammen, dessen Dauer vom
            Ansetzen bis zur Verwendung reicht; die Schritte des Hauptteigs
            bleiben einzeln.

            TEXT:
            \(source)
            """

        let response = try await session.respond(
            to: prompt,
            generating: GeneratedRecipe.self
        )
        let generated = response.content
        let warnings = generated.warnings
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        return (generated.makeRecipe(), warnings)
    }

    private func validateCloudRecipe(_ recipe: RecipeFB) throws {
        guard RecipeImportCheck.hasRecipeData(recipe) else {
            throw RecipeImageAnalysisError.insufficientRecipeData
        }
    }

    /// Rejects an implausible model result. Without a local reading to compare
    /// with (a web page without structured data), only the basics are checked.
    private func validate(recipe: RecipeFB, comparedWith localRecipe: RecipeFB?) throws {
        let name = recipe.name.trimmingCharacters(in: .whitespacesAndNewlines)
        let ingredients = recipe.components.flatMap(\.ingredients)
        let instructions = recipe.instructions.filter {
            !$0.instruction.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }

        guard !name.isEmpty, !ingredients.isEmpty, !instructions.isEmpty else {
            throw RecipeImageAnalysisError.insufficientRecipeData
        }
        guard let localRecipe else { return }

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

// RecipeImportPlan lives in BakePlannerCore (CloudRecipeImport.swift).

// RecipeImportStepText lives in BakePlannerCore (RecipeWebPage.swift).

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
                instruction.duration = GlobalVariables.preheatTime
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
