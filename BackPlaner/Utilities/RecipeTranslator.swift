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

    /// The recipe's original language.
    ///
    /// Recorded recipes state it themselves. For the older ones, which carry
    /// nothing, the language is read off their text — assuming German there put
    /// a French recipe out of reach: its French text counted as the German
    /// original, so translating it into German had nothing to do, and going via
    /// English wrote the French text into the German cache for good.
    nonisolated static func sourceLanguageCode(for recipe: RecipeFB) -> String {
        let source = RecipeFB.baseLanguageCode(from: recipe.sourceLanguage)

        guard !source.isEmpty else {
            return RecipeLanguageDetector.detectedLanguage(of: recipe) ?? "de"
        }

        // A recorded language can be wrong, too: it used to be the language the
        // app was set to rather than the recipe's own, so a French recipe
        // entered in a German app claims to be German — and its French text
        // sits in the German slot, which no amount of translating can undo.
        // Only a clear disagreement between the recorded language and the text
        // actually stored under it overrules the record.
        if let detected = RecipeLanguageDetector.detectedLanguage(
            of: recipe,
            storedUnder: source,
            minimumConfidence: 0.85
        ), detected != source {
            return detected
        }

        return source
    }

    /// Corrects a recipe that is filed under the wrong original language, by
    /// moving its text into the language it is actually written in.
    ///
    /// Returns whether anything changed. Running it repeatedly costs nothing:
    /// once the text sits under the right language, record and text agree.
    @discardableResult
    static func repairSourceLanguage(of recipe: RecipeFB) -> Bool {
        let recorded = RecipeFB.baseLanguageCode(from: recipe.sourceLanguage)
        let actual = sourceLanguageCode(for: recipe)

        guard !actual.isEmpty, actual != recorded else { return false }

        recipe.moveCachedTranslation(from: recorded, to: actual)
        recipe.sourceLanguage = actual
        return true
    }

    /// Displays the recipe in `languageCode` from cached text when possible.
    /// Returns `true` when no machine translation is needed (source language or already cached).
    @discardableResult
    static func showCachedIfAvailable(_ recipe: RecipeFB, languageCode: String) -> Bool {
        // Every path into the translation menu comes through here, so this is
        // where a mislabelled original is put right.
        repairSourceLanguage(of: recipe)

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

    /// Like `showCachedIfAvailable`, but only a translation that includes the
    /// components, ingredients and steps counts. The recipe list translates a
    /// recipe's name and summary ahead of time, and that must not pass for
    /// the whole recipe when it is opened.
    @discardableResult
    static func showCompleteIfAvailable(_ recipe: RecipeFB, languageCode: String) -> Bool {
        repairSourceLanguage(of: recipe)

        let source = sourceLanguageCode(for: recipe)

        if languageCode == source {
            if recipe.hasCachedTranslation(languageCode: source) {
                recipe.showLocalization(languageCode: source)
            }
            return true
        }

        if recipe.hasCompleteTranslation(languageCode: languageCode) {
            recipe.showLocalization(languageCode: languageCode)
            return true
        }

        return false
    }

    /// Translates what the recipe list shows — name, summary and tags — of
    /// several recipes of the same source language in one go, and caches the
    /// result under `languageCode`. Nothing below that level is touched; the
    /// recipe screen completes the translation when the recipe is opened.
    static func translateListEntries(_ recipes: [RecipeFB], into languageCode: String, using session: TranslationSession) async throws {
        enum Field {
            case name
            case summary
            case tag(Int)
        }

        var requests = [TranslationSession.Request]()
        var fields = [(recipe: Int, field: Field)]()

        for (index, recipe) in recipes.enumerated() {
            repairSourceLanguage(of: recipe)
            // The original has to be safe before anything is overwritten.
            let source = sourceLanguageCode(for: recipe)
            if !recipe.hasCachedTranslation(languageCode: source) {
                recipe.storeLocalization(languageCode: source)
            }

            func add(_ text: String, _ field: Field) {
                guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
                requests.append(TranslationSession.Request(sourceText: text, clientIdentifier: "\(requests.count)"))
                fields.append((index, field))
            }
            add(recipe.name, .name)
            add(recipe.summary, .summary)
            for (tagIndex, tag) in recipe.tags.enumerated() {
                add(tag, .tag(tagIndex))
            }
        }

        guard !requests.isEmpty else { return }

        // Responses return in the same order as the requests.
        let responses = try await session.translations(from: requests)
        var texts = recipes.map { RecipeTextFB(name: $0.name, summary: $0.summary, tags: $0.tags) }
        for (responseIndex, response) in responses.enumerated() where responseIndex < fields.count {
            let target = fields[responseIndex]
            switch target.field {
            case .name:             texts[target.recipe].name = response.targetText
            case .summary:          texts[target.recipe].summary = response.targetText
            case .tag(let tagIndex): texts[target.recipe].tags?[tagIndex] = response.targetText
            }
        }

        for (index, recipe) in recipes.enumerated() {
            recipe.translations[languageCode] = texts[index]
            recipe.showLocalization(languageCode: languageCode)
        }
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
