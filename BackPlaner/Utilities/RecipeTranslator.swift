//
//  RecipeTranslator.swift
//  BackPlaner
//
//  Machine-translates a public recipe (RecipeFB) into another language using Apple's
//  on-device Translation framework, caching the result in the recipe's `translations`.
//

import BakePlannerCore
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
            repairGlossaryTerms(of: recipe, languageCode: languageCode)
            // A cache from before the glossary is due for a new round.
            guard cachedTranslationHonoursGlossary(recipe, languageCode: languageCode, complete: false) else { return false }
            recipe.showLocalization(languageCode: languageCode)
            return true
        }

        return false
    }

    /// Whether the cached translation uses the glossary's words wherever its
    /// source text has a term. A translation made before the glossary
    /// existed ("Breakfast") fails this and is translated afresh, which
    /// then goes through the glossary and is saved over the old cache.
    /// `complete` includes components, ingredients and steps; otherwise only
    /// the recipe's own text is checked, as the recipe list shows nothing else.
    static func cachedTranslationHonoursGlossary(_ recipe: RecipeFB, languageCode: String, complete: Bool) -> Bool {
        let source = sourceLanguageCode(for: recipe)
        guard languageCode != source else { return true }

        func honours(_ sourceText: String?, _ translation: String?) -> Bool {
            guard let sourceText, let translation else { return true }
            return BakingGlossary.translationHonoursGlossary(sourceText: sourceText, translation: translation,
                                                             from: source, into: languageCode)
        }

        let original = recipe.translations[source]
        let cached = recipe.translations[languageCode]
        guard honours(original?.name, cached?.name), honours(original?.summary, cached?.summary) else { return false }
        let cachedTags = cached?.tags ?? []
        for (index, tag) in (original?.tags ?? []).enumerated() where index < cachedTags.count {
            guard honours(tag, cachedTags[index]) else { return false }
        }

        guard complete else { return true }

        for component in recipe.components {
            guard honours(component.translations[source]?.name, component.translations[languageCode]?.name) else { return false }
            for ingredient in component.ingredients {
                guard honours(ingredient.translations[source]?.name, ingredient.translations[languageCode]?.name) else { return false }
            }
        }
        for instruction in recipe.instructions {
            guard honours(instruction.translations[source]?.instruction, instruction.translations[languageCode]?.instruction) else { return false }
        }
        return true
    }

    /// Puts cached translations right where a baker's term had been
    /// translated by the machine before the glossary existed — "Brühstück"
    /// came back as "Breakfast" and was cached that way, on every device.
    ///
    /// Only a text that is a term by itself (a component or ingredient name)
    /// can be corrected without a new translation round; a sentence keeps
    /// its cached wording until it is translated again. Returns whether
    /// anything changed.
    @discardableResult
    static func repairGlossaryTerms(of recipe: RecipeFB, languageCode: String) -> Bool {
        let source = sourceLanguageCode(for: recipe)
        guard languageCode != source, recipe.hasCachedTranslation(languageCode: languageCode) else { return false }

        var changed = false

        /// The glossary's word for `sourceText`, when the cached text differs from it.
        func correction(for sourceText: String?, cached: String?) -> String? {
            guard let sourceText, let cached,
                  let word = GlossaryTranslationPlan.termTranslation(of: sourceText, from: source, into: languageCode),
                  word != cached
            else { return nil }
            return word
        }

        if let word = correction(for: recipe.translations[source]?.name, cached: recipe.translations[languageCode]?.name) {
            recipe.translations[languageCode]?.name = word
            changed = true
        }

        for component in recipe.components {
            if let word = correction(for: component.translations[source]?.name, cached: component.translations[languageCode]?.name) {
                component.translations[languageCode]?.name = word
                changed = true
            }
            for ingredient in component.ingredients {
                if let word = correction(for: ingredient.translations[source]?.name, cached: ingredient.translations[languageCode]?.name) {
                    ingredient.translations[languageCode]?.name = word
                    changed = true
                }
            }
        }

        for instruction in recipe.instructions {
            if let word = correction(for: instruction.translations[source]?.instruction, cached: instruction.translations[languageCode]?.instruction) {
                instruction.translations[languageCode]?.instruction = word
                changed = true
            }
        }

        return changed
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
            repairGlossaryTerms(of: recipe, languageCode: languageCode)
            // A cache from before the glossary is due for a new round, which
            // the caller then starts; the new translation replaces it.
            guard cachedTranslationHonoursGlossary(recipe, languageCode: languageCode, complete: true) else { return false }
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

        var sourceTexts = [String]()
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
                sourceTexts.append(text)
                fields.append((index, field))
            }
            add(recipe.name, .name)
            add(recipe.summary, .summary)
            for (tagIndex, tag) in recipe.tags.enumerated() {
                add(tag, .tag(tagIndex))
            }
        }

        guard let firstRecipe = recipes.first, !fields.isEmpty else { return }

        // All recipes of the batch share the session's source language; the
        // glossary (BakingGlossary) keeps the baker's terms out of the round.
        let plan = GlossaryTranslationPlan(texts: sourceTexts,
                                           from: sourceLanguageCode(for: firstRecipe),
                                           into: languageCode)
        let translated = try await translate(plan.sourceTexts, using: session)
        let results = plan.results(translated: translated)

        var texts = recipes.map { RecipeTextFB(name: $0.name, summary: $0.summary, tags: $0.tags) }
        for (resultIndex, result) in results.enumerated() where resultIndex < fields.count {
            let target = fields[resultIndex]
            switch target.field {
            case .name:             texts[target.recipe].name = result
            case .summary:          texts[target.recipe].summary = result
            case .tag(let tagIndex): texts[target.recipe].tags?[tagIndex] = result
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
        guard allSlots.contains(where: { !$0.sourceText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) else { return }

        // Baker's terms are kept out of the translator's hands, see
        // BakingGlossary: "Brühstück" used to come back as "Breakfast".
        let plan = GlossaryTranslationPlan(texts: allSlots.map(\.sourceText), from: source, into: languageCode)
        let translated = try await translate(plan.sourceTexts, using: session)
        let results = plan.results(translated: translated)

        for (index, slot) in allSlots.enumerated() where index < results.count {
            slot.apply(results[index])
        }

        // Cache the translated live values under the target language.
        recipe.storeLocalization(languageCode: languageCode)
    }

    /// The texts translated in order. Responses return in the same order as
    /// the requests.
    private static func translate(_ texts: [String], using session: TranslationSession) async throws -> [String] {
        guard !texts.isEmpty else { return [] }

        let requests = texts.enumerated().map { index, text in
            TranslationSession.Request(sourceText: text, clientIdentifier: "\(index)")
        }
        return try await session.translations(from: requests).map(\.targetText)
    }
}
