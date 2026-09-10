//
//  RecipeTranslatorTests.swift
//  BackPlanerTests
//
//  Covers everything around the machine translation: which language a recipe
//  counts as, how a mislabelled original is put right, and what is served from
//  the cache. The translation itself needs a live TranslationSession, which
//  only exists inside a SwiftUI view, so it is not exercised here.
//

import Testing
@testable import BackPlaner

@Suite("Recipe translator", .serialized)
@MainActor
struct RecipeTranslatorTests {

    // MARK: - Working out the source language

    @Test("A recipe from before the language was recorded is read off its own text")
    func legacyRecipeWithoutRecordedLanguage() {
        let french = RecipeFixtures.french()
        let german = RecipeFixtures.german()

        #expect(french.sourceLanguage.isEmpty)
        #expect(RecipeTranslator.sourceLanguageCode(for: french) == "fr")
        #expect(RecipeTranslator.sourceLanguageCode(for: german) == "de")
    }

    @Test("A recorded language that the text contradicts is overruled")
    func recordedLanguageIsOverruledByTheStoredText() {
        // The recipe was entered in a German-language app, so it was stamped
        // "de" although it is written in French — and its French text went into
        // the German slot.
        let recipe = RecipeFixtures.french()
        recipe.sourceLanguage = "de"
        recipe.storeLocalization(languageCode: "de")

        #expect(RecipeTranslator.sourceLanguageCode(for: recipe) == "fr")
    }

    @Test("A recorded language the text agrees with is kept")
    func recordedLanguageIsKeptWhenTheTextAgrees() {
        let recipe = RecipeFixtures.german()
        recipe.sourceLanguage = "de"
        recipe.storeLocalization(languageCode: "de")

        #expect(RecipeTranslator.sourceLanguageCode(for: recipe) == "de")
    }

    @Test("A recipe showing a translation still reports its original language")
    func translationOnScreenDoesNotChangeTheSourceLanguage() {
        let recipe = RecipeFixtures.german()
        recipe.sourceLanguage = "de"
        recipe.storeLocalization(languageCode: "de")
        RecipeFixtures.replaceLiveText(of: recipe, with: RecipeFixtures.french())
        recipe.storeLocalization(languageCode: "fr")

        #expect(RecipeTranslator.sourceLanguageCode(for: recipe) == "de")
    }

    // MARK: - Repairing a mislabelled original

    @Test("Repair re-files the whole cache under the language the recipe is written in")
    func repairMovesTheEntireCache() {
        let recipe = RecipeFixtures.french()
        recipe.sourceLanguage = "de"
        recipe.storeLocalization(languageCode: "de")

        #expect(RecipeTranslator.repairSourceLanguage(of: recipe))

        #expect(recipe.sourceLanguage == "fr")
        #expect(recipe.hasCachedTranslation(languageCode: "fr"))
        #expect(!recipe.hasCachedTranslation(languageCode: "de"))

        // The move has to reach every level, not just the recipe itself —
        // a leftover "de" entry on a step would still read as a translation.
        #expect(recipe.translations["de"] == nil)
        #expect(recipe.instructions[0].translations["de"] == nil)
        #expect(recipe.components[0].translations["de"] == nil)
        #expect(recipe.components[0].ingredients[0].translations["de"] == nil)

        #expect(recipe.instructions[0].translations["fr"]?.instruction
                == "Mélanger tous les ingrédients et laisser reposer trente minutes.")
        #expect(recipe.components[0].translations["fr"]?.name == "Pâte principale")
        #expect(recipe.components[0].ingredients[0].translations["fr"]?.name == "Farine de blé")
    }

    @Test("Repairing an already correct recipe changes nothing")
    func repairLeavesACorrectRecipeAlone() {
        let recipe = RecipeFixtures.german()
        recipe.sourceLanguage = "de"
        recipe.storeLocalization(languageCode: "de")

        #expect(RecipeTranslator.repairSourceLanguage(of: recipe) == false)
        #expect(recipe.sourceLanguage == "de")
        #expect(recipe.hasCachedTranslation(languageCode: "de"))
    }

    @Test("Repair can be run repeatedly")
    func repairIsIdempotent() {
        let recipe = RecipeFixtures.french()
        recipe.sourceLanguage = "de"
        recipe.storeLocalization(languageCode: "de")

        #expect(RecipeTranslator.repairSourceLanguage(of: recipe))
        #expect(RecipeTranslator.repairSourceLanguage(of: recipe) == false)
        #expect(RecipeTranslator.repairSourceLanguage(of: recipe) == false)
        #expect(recipe.sourceLanguage == "fr")
    }

    @Test("A recipe that has been translated is not re-filed")
    func repairDoesNotDisturbATranslatedRecipe() {
        let recipe = RecipeFixtures.german()
        recipe.sourceLanguage = "de"
        recipe.storeLocalization(languageCode: "de")
        RecipeFixtures.replaceLiveText(of: recipe, with: RecipeFixtures.french())
        recipe.storeLocalization(languageCode: "fr")

        #expect(RecipeTranslator.repairSourceLanguage(of: recipe) == false)
        #expect(recipe.sourceLanguage == "de")
        #expect(recipe.hasCachedTranslation(languageCode: "de"))
        #expect(recipe.hasCachedTranslation(languageCode: "fr"))
    }

    // MARK: - Serving from the cache

    @Test("Switching back to the original restores its text")
    func cachedOriginalIsRestored() {
        let recipe = RecipeFixtures.german()
        recipe.sourceLanguage = "de"
        recipe.storeLocalization(languageCode: "de")
        RecipeFixtures.replaceLiveText(of: recipe, with: RecipeFixtures.french())
        recipe.storeLocalization(languageCode: "fr")

        #expect(RecipeTranslator.showCachedIfAvailable(recipe, languageCode: "de"))
        #expect(recipe.name == "Landbrot")
        #expect(recipe.components[0].ingredients[0].name == "Weizenmehl")
        #expect(recipe.instructions[0].instruction
                == "Alle Zutaten zu einem Teig verkneten und dreißig Minuten ruhen lassen.")
    }

    @Test("Switching to a cached translation needs no machine translation")
    func cachedTranslationIsServedFromTheCache() {
        let recipe = RecipeFixtures.german()
        recipe.sourceLanguage = "de"
        recipe.storeLocalization(languageCode: "de")
        RecipeFixtures.replaceLiveText(of: recipe, with: RecipeFixtures.french())
        recipe.storeLocalization(languageCode: "fr")
        RecipeTranslator.showCachedIfAvailable(recipe, languageCode: "de")

        #expect(RecipeTranslator.showCachedIfAvailable(recipe, languageCode: "fr"))
        #expect(recipe.name == "Pain de campagne")
        #expect(recipe.components[0].ingredients[0].name == "Farine de blé")
    }

    @Test("An uncached language reports that it has to be translated")
    func uncachedLanguageIsReportedAsMissing() {
        let recipe = RecipeFixtures.german()
        recipe.sourceLanguage = "de"
        recipe.storeLocalization(languageCode: "de")

        #expect(RecipeTranslator.showCachedIfAvailable(recipe, languageCode: "en") == false)
        // Nothing may be applied when the answer is "not cached" — the recipe
        // has to stay readable in the language it was showing.
        #expect(recipe.name == "Landbrot")
    }

    @Test("The source language is available even before anything was cached")
    func sourceLanguageNeedsNoCache() {
        let recipe = RecipeFixtures.german()

        #expect(RecipeTranslator.showCachedIfAvailable(recipe, languageCode: "de"))
        #expect(recipe.name == "Landbrot")
    }

    @Test("Asking for the cache puts a mislabelled original right on the way through")
    func showCachedRepairsAMislabelledOriginal() {
        // This is the path the detail view takes, so the repair has to happen
        // here rather than needing a separate call.
        let recipe = RecipeFixtures.french()
        recipe.sourceLanguage = "de"
        recipe.storeLocalization(languageCode: "de")

        // "Translate into German" must not be answered out of the French cache.
        #expect(RecipeTranslator.showCachedIfAvailable(recipe, languageCode: "de") == false)
        #expect(recipe.sourceLanguage == "fr")
        #expect(recipe.name == "Pain de campagne")

        // French is now the original and needs no translation.
        #expect(RecipeTranslator.showCachedIfAvailable(recipe, languageCode: "fr"))
    }

    // MARK: - The menu

    @Test("The translation menu offers exactly the languages the detector knows")
    func supportedLanguagesMatchTheDetector() {
        let offered = RecipeTranslator.supportedLanguages.map(\.code).sorted()

        #expect(offered == RecipeLanguageDetector.supportedCodes.sorted())
    }
}
