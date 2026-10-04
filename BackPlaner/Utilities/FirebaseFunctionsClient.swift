import Foundation
@preconcurrency import FirebaseFunctions
import UIKit

struct ProtectedConnectionStatus: Sendable {
    let isAuthenticated: Bool
    let isAppCheckVerified: Bool
}

struct CloudRecipeAnalysis: Decodable, Sendable {
    let recipe: CloudRecipe
    let model: String
}

struct CloudRecipe: Decodable, Sendable {
    let title: String
    let summary: String
    let sourceLanguage: String
    let preparationMinutes: Int
    let components: [CloudRecipeComponent]
    let instructions: [CloudRecipeInstruction]
    let warnings: [String]

    @MainActor
    func makeRecipe() -> RecipeFB {
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

struct CloudRecipeComponent: Decodable, Sendable {
    let name: String
    let ingredients: [CloudRecipeIngredient]
}

struct CloudRecipeIngredient: Decodable, Sendable {
    let name: String
    let amount: Double
    let unit: String
}

struct CloudRecipeInstruction: Decodable, Sendable {
    let text: String
    let durationMinutes: Int
    let componentName: String
    let isBaking: Bool
}

final class FirebaseFunctionsClient: @unchecked Sendable {
    static let shared = FirebaseFunctionsClient()

    private let functions: Functions

    private init() {
        functions = Functions.functions(region: "europe-west1")
    }

    func verifyProtectedConnection() async throws -> ProtectedConnectionStatus {
        let result = try await functions
            .httpsCallable("verifyProtectedConnection")
            .call()

        guard let payload = result.data as? [String: Any],
              payload["ok"] as? Bool == true else {
            throw FirebaseFunctionsClientError.invalidResponse
        }

        return ProtectedConnectionStatus(
            isAuthenticated: payload["authenticated"] as? Bool == true,
            isAppCheckVerified: payload["appCheckVerified"] as? Bool == true
        )
    }

    @MainActor
    func analyzeRecipeImages(_ images: [UIImage]) async throws -> CloudRecipeAnalysis {
        let encodedImages = try images.map { image in
            let data = try image.recipeAnalysisJPEGData()
            return [
                "data": data.base64EncodedString(),
                "mimeType": "image/jpeg"
            ]
        }

        let callable = functions.httpsCallable("analyzeRecipeImages")
        callable.timeoutInterval = 250
        let result = try await callable.call(["images": encodedImages])

        guard let payload = result.data as? [String: Any],
              JSONSerialization.isValidJSONObject(payload) else {
            throw FirebaseFunctionsClientError.invalidResponse
        }

        let data = try JSONSerialization.data(withJSONObject: payload)
        return try JSONDecoder().decode(CloudRecipeAnalysis.self, from: data)
    }

    /// Structures the text of a recipe web page. The page is fetched by the
    /// app; only the extracted text and the address leave the device.
    func analyzeRecipeText(_ text: String, sourceURL: URL?) async throws -> CloudRecipeAnalysis {
        var payload: [String: Any] = ["text": text]
        if let sourceURL {
            payload["sourceURL"] = sourceURL.absoluteString
        }

        let callable = functions.httpsCallable("analyzeRecipeText")
        callable.timeoutInterval = 250
        let result = try await callable.call(payload)

        guard let response = result.data as? [String: Any],
              JSONSerialization.isValidJSONObject(response) else {
            throw FirebaseFunctionsClientError.invalidResponse
        }

        let data = try JSONSerialization.data(withJSONObject: response)
        return try JSONDecoder().decode(CloudRecipeAnalysis.self, from: data)
    }
}

enum FirebaseFunctionsClientError: LocalizedError {
    case imageEncodingFailed
    case imageTooLarge
    case invalidResponse

    var errorDescription: String? {
        switch self {
        case .imageEncodingFailed:
            return "Ein Rezeptbild konnte nicht vorbereitet werden."
        case .imageTooLarge:
            return "Ein Rezeptbild ist auch nach der Verkleinerung zu groß."
        case .invalidResponse:
            return "Der Server hat eine ungültige Antwort geliefert."
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

private extension UIImage {
    @MainActor
    func recipeAnalysisJPEGData() throws -> Data {
        let maximumDimension: CGFloat = 2_000
        let largestDimension = max(size.width, size.height)
        let scale = min(1, maximumDimension / largestDimension)
        let targetSize = CGSize(
            width: max(1, size.width * scale),
            height: max(1, size.height * scale)
        )

        let renderer = UIGraphicsImageRenderer(size: targetSize)
        let preparedImage = renderer.image { _ in
            draw(in: CGRect(origin: .zero, size: targetSize))
        }
        guard let data = preparedImage.jpegData(compressionQuality: 0.72) else {
            throw FirebaseFunctionsClientError.imageEncodingFailed
        }
        guard data.count <= 3 * 1_024 * 1_024 else {
            throw FirebaseFunctionsClientError.imageTooLarge
        }
        return data
    }
}
