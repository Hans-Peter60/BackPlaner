//
//  RecipeTranslatorTests.swift
//  BackPlanerTests
//
//  Covers everything around the machine translation: which language a recipe
//  counts as, how a mislabelled original is put right, and what is served from
//  the cache. The translation itself needs a live TranslationSession, which
//  only exists inside a SwiftUI view, so it is not exercised here.
//

import BakePlannerCore
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

    // MARK: - The glossary and the cache

    @Test("A cached machine translation of a baker's term is corrected on the way to the screen")
    func cachedTermIsRepairedFromTheGlossary() {
        // Translated and cached before the glossary existed: the component
        // "Brühstück" came back as "Breakfast".
        let recipe = RecipeFixtures.recipe(name: "Roggenbrot",
                                           summary: "Ein Roggenbrot mit Brühstück und langer Teigführung.",
                                           steps: ["Das Brühstück am Vorabend ansetzen."],
                                           component: "Brühstück",
                                           ingredients: ["Altbrot", "Wasser"])
        recipe.sourceLanguage = "de"
        recipe.storeLocalization(languageCode: "de")

        recipe.name = "Rye bread"
        recipe.summary = "A rye bread with breakfast and a long fermentation."
        recipe.components[0].name = "Breakfast"
        recipe.components[0].ingredients[0].name = "Old bread"
        recipe.components[0].ingredients[1].name = "Water"
        recipe.instructions[0].instruction = "Prepare the breakfast the evening before."
        recipe.storeLocalization(languageCode: "en")

        // The recipe's own text has "breakfast" in its summary, so even the
        // list's cache is stale: the recipe needs a new round.
        #expect(RecipeTranslator.showCachedIfAvailable(recipe, languageCode: "en") == false)
        #expect(RecipeTranslator.showCompleteIfAvailable(recipe, languageCode: "en") == false)

        // The component name was put right on the way, in the cache.
        #expect(RecipeTranslator.repairGlossaryTerms(of: recipe, languageCode: "en") == false)
        #expect(recipe.components[0].translations["en"]?.name == "Scald")
        #expect(recipe.components[0].translations["de"]?.name == "Brühstück")
        // Already right, so left alone.
        #expect(recipe.components[0].ingredients[0].translations["en"]?.name == "Old bread")
        #expect(recipe.components[0].ingredients[1].translations["en"]?.name == "Water")
    }

    @Test("A cache with a mistranslated term in a step is stale for the recipe screen only")
    func staleStepMakesTheCompleteCacheStale() {
        let recipe = RecipeFixtures.recipe(name: "Roggenbrot",
                                           summary: "Ein Roggenbrot mit langer Teigführung.",
                                           steps: ["Für das Brühstück die Saaten mit kochendem Wasser übergießen."],
                                           component: "Saaten-Brühstück",
                                           ingredients: ["Leinsamen", "Wasser"])
        recipe.sourceLanguage = "de"
        recipe.storeLocalization(languageCode: "de")

        recipe.name = "Rye bread"
        recipe.summary = "A rye bread with a long fermentation."
        recipe.components[0].name = "Seed breakfast"
        recipe.components[0].ingredients[0].name = "Flaxseed"
        recipe.components[0].ingredients[1].name = "Water"
        recipe.instructions[0].instruction = "For the breakfast, pour boiling water over the seeds."
        recipe.storeLocalization(languageCode: "en")

        // Name and summary are fine, so the list may use its cache …
        #expect(RecipeTranslator.showCachedIfAvailable(recipe, languageCode: "en"))
        #expect(recipe.name == "Rye bread")
        // … but the recipe screen has to translate afresh.
        #expect(RecipeTranslator.showCompleteIfAvailable(recipe, languageCode: "en") == false)

        // Once the round has gone through the glossary, the cache is good.
        recipe.components[0].name = "Seed scald"
        recipe.instructions[0].instruction = "For the scald, pour boiling water over the seeds."
        recipe.storeLocalization(languageCode: "en")
        #expect(RecipeTranslator.showCompleteIfAvailable(recipe, languageCode: "en"))
    }

    @Test("Repairing a correctly cached translation changes nothing")
    func repairLeavesCorrectTermsAlone() {
        let recipe = RecipeFixtures.recipe(name: "Landbrot",
                                           summary: "Ein kräftiges Mischbrot mit Sauerteig.",
                                           steps: ["Alle Zutaten verkneten."],
                                           component: "Hauptteig",
                                           ingredients: ["Sauerteig", "Wasser"])
        recipe.sourceLanguage = "de"
        recipe.storeLocalization(languageCode: "de")

        recipe.name = "Country loaf"
        recipe.summary = "A hearty sourdough loaf."
        recipe.components[0].name = "Main dough"
        recipe.components[0].ingredients[0].name = "Sourdough"
        recipe.components[0].ingredients[1].name = "Water"
        recipe.instructions[0].instruction = "Knead all the ingredients."
        recipe.storeLocalization(languageCode: "en")

        #expect(RecipeTranslator.repairGlossaryTerms(of: recipe, languageCode: "en") == false)
        // The original is never "repaired".
        #expect(RecipeTranslator.repairGlossaryTerms(of: recipe, languageCode: "de") == false)
        #expect(recipe.components[0].translations["de"]?.name == "Hauptteig")
    }

    // MARK: - The menu

    @Test("The translation menu offers exactly the languages the detector knows")
    func supportedLanguagesMatchTheDetector() {
        let offered = RecipeTranslator.supportedLanguages.map(\.code).sorted()

        #expect(offered == RecipeLanguageDetector.supportedCodes.sorted())
    }
}
