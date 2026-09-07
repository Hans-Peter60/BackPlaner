//
//  RecipeTranslator.swift
//  BackPlaner
//
//  Machine-translates a public recipe (RecipeFB) into another language using Apple's
//  on-device Translation framework, caching the result in the recipe's `translations`.
//

import Foundation
import Translation

@MainActor
enum RecipeTranslator {

    /// A language the user can switch a recipe to.
    struct Language: Identifiable {
        let code: String
        let name: String
        var id: String { code }
    }

    /// The languages offered in the detail view's translation menu.
    static let supportedLanguages: [Language] = [
        Language(code: "de", name: "Deutsch"),
        Language(code: "en", name: "English"),
        Language(code: "fr", name: "Français")
    ]

    /// A translatable field of a recipe, paired with a writer that stores the result back.
    /// Units are intentionally excluded so unit-based portion logic (`Rational`) keeps working.
    private struct Slot {
        let sourceText: String
        let apply: (String) -> Void
    }

    /// The translatable strings of a recipe, in a stable order.
    private static func slots(for recipe: RecipeFB) -> [Slot] {
        var slots = [Slot]()

        slots.append(Slot(sourceText: recipe.name)    { recipe.name = $0 })
        slots.append(Slot(sourceText: recipe.summary) { recipe.summary = $0 })

        for index in recipe.tags.indices {
            slots.append(Slot(sourceText: recipe.tags[index]) { newValue in
                if recipe.tags.indices.contains(index) { recipe.tags[index] = newValue }
            })
        }

        for component in recipe.components {
            slots.append(Slot(sourceText: component.name) { component.name = $0 })
            for ingredient in component.ingredients {
                slots.append(Slot(sourceText: ingredient.name) { ingredient.name = $0 })
            }
        }

        for instruction in recipe.instructions {
            slots.append(Slot(sourceText: instruction.instruction) { instruction.instruction = $0 })
        }

        return slots
    }

    /// The recipe's original language, falling back to German when unknown.
    nonisolated static func sourceLanguageCode(for recipe: RecipeFB) -> String {
        let source = RecipeFB.baseLanguageCode(from: recipe.sourceLanguage)
        return source.isEmpty ? "de" : source
    }

    /// Displays the recipe in `languageCode` from cached text when possible.
    /// Returns `true` when no machine translation is needed (source language or already cached).
    @discardableResult
    static func showCachedIfAvailable(_ recipe: RecipeFB, languageCode: String) -> Bool {
        let source = sourceLanguageCode(for: recipe)

        if languageCode == source {
            // Restore the original from the cache if we captured one; otherwise the live
            // values already are the source text.
            if recipe.hasCachedTranslation(languageCode: source) {
                recipe.showLocalization(languageCode: source)
            }
            return true
        }

        if recipe.hasCachedTranslation(languageCode: languageCode) {
            recipe.showLocalization(languageCode: languageCode)
            return true
        }

        return false
    }

    /// Machine-translates the recipe into `languageCode` using the provided session and caches the result.
    /// `currentLanguage` is the language currently shown, so we can capture a complete source
    /// snapshot (when the original is on screen) before overwriting anything.
    static func translate(_ recipe: RecipeFB, from currentLanguage: String, into languageCode: String, using session: TranslationSession) async throws {
        let source = sourceLanguageCode(for: recipe)

        if currentLanguage == source {
            // The original is currently on screen (with components/steps loaded), so snapshot
            // the complete source text now. This is the reliable moment to preserve the original.
            recipe.storeLocalization(languageCode: source)
        } else {
            // A translation is on screen — restore the cached original before translating.
            recipe.showLocalization(languageCode: source)
        }

        let allSlots = slots(for: recipe)
        var requests = [TranslationSession.Request]()
        var slotForRequest = [Int]()

        for (index, slot) in allSlots.enumerated() {
            guard !slot.sourceText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { continue }
            requests.append(TranslationSession.Request(sourceText: slot.sourceText,
                                                       clientIdentifier: "\(slotForRequest.count)"))
            slotForRequest.append(index)
        }

        guard !requests.isEmpty else { return }

        // Responses return in the same order as the requests.
        let responses = try await session.translations(from: requests)
        for (responseIndex, response) in responses.enumerated() {
            guard responseIndex < slotForRequest.count else { break }
            allSlots[slotForRequest[responseIndex]].apply(response.targetText)
        }

        // Cache the translated live values under the target language.
        recipe.storeLocalization(languageCode: languageCode)
    }
}
