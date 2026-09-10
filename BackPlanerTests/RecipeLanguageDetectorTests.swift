//
//  RecipeLanguageDetectorTests.swift
//  BackPlanerTests
//

import Testing
@testable import BackPlaner

@Suite("Recipe language detection")
struct RecipeLanguageDetectorTests {

    // MARK: - Plain text

    @Test("Recipe prose is attributed to the language it is written in",
          arguments: [
            ("de", "Mehl, Wasser und Salz in einer Schüssel vermengen. Den Teig dreißig Minuten ruhen lassen und anschließend gründlich kneten."),
            ("de", "Den Sauerteig am Vorabend ansetzen. Am nächsten Morgen alle Zutaten zu einem Teig verarbeiten und zwei Stunden gehen lassen."),
            ("en", "Mix the flour, water and salt in a bowl. Let the dough rest for thirty minutes, then knead it thoroughly."),
            ("en", "Start the sourdough the evening before. The next morning work all the ingredients into a dough and let it rise for two hours."),
            ("fr", "Mélanger la farine, l'eau et le sel dans un saladier. Laisser reposer la pâte trente minutes, puis la pétrir soigneusement."),
            ("fr", "Préparer le levain la veille au soir. Le lendemain matin, travailler tous les ingrédients en une pâte et laisser lever deux heures.")
          ])
    func detectsTheLanguageOfRecipeProse(expected: String, text: String) {
        #expect(RecipeLanguageDetector.detectedLanguage(in: text) == expected)
    }

    @Test("Text shorter than the minimum sample is left undecided",
          arguments: ["Landbrot", "Baguette", "Pain", "Brot", ""])
    func returnsNilForTooLittleText(text: String) {
        // A recipe name on its own says too little — and is often a proper noun
        // that reads as French or German regardless of the recipe's language.
        #expect(RecipeLanguageDetector.detectedLanguage(in: text) == nil)
    }

    @Test("A recipe in an unsupported language never overrules a recorded one",
          arguments: [
            "Meng de bloem, het water en het zout in een kom en laat het deeg dertig minuten rusten voordat je het kneedt.",
            "Mescolare la farina, l'acqua e il sale in una ciotola e lasciare riposare l'impasto per trenta minuti.",
            "Mezclar la harina, el agua y la sal en un bol y dejar reposar la masa durante treinta minutos.",
            "Bland melet, vandet og saltet i en skål, og lad dejen hvile i tredive minutter."
          ])
    func unsupportedLanguagesStayBelowTheOverrulingThreshold(text: String) {
        // The recognizer is constrained to de/en/fr, so Dutch, Italian, Spanish
        // and Danish are all forced into one of those three — Dutch comes back
        // as German. That is tolerable as a fallback, but it must never be
        // confident enough to rewrite a recipe's recorded source language.
        #expect(RecipeLanguageDetector.detectedLanguage(in: text, minimumConfidence: 0.85) == nil)
    }

    @Test("Anything reported is a language the app can actually display")
    func onlyEverReportsASupportedLanguage() {
        let text = "Meng de bloem, het water en het zout in een kom en laat het deeg dertig minuten rusten."

        if let detected = RecipeLanguageDetector.detectedLanguage(in: text) {
            #expect(RecipeLanguageDetector.supportedCodes.contains(detected))
        }
    }

    // MARK: - Cases that must not overrule a recorded language

    @Test("Loan words do not flip the detected language",
          arguments: [
            ("de", "Baguette mit Poolish. Das Poolish am Vorabend ansetzen, den Croissant-Teig kühl stellen und die Brioche anschließend formen."),
            ("de", "Pain de Campagne. Den Teig falten und über Nacht im Kühlschrank reifen lassen, am Morgen bei 250 Grad mit Dampf backen."),
            ("fr", "Pain complet au levain façon Landbrot. Mélanger la farine et l'eau, puis laisser fermenter la nuit au frais avant de cuire.")
          ])
    func loanWordsDoNotFlipTheResult(expected: String, text: String) {
        // These run at the confidence the repair path uses, because a wrong
        // answer here would rewrite the recipe's recorded source language.
        #expect(RecipeLanguageDetector.detectedLanguage(in: text, minimumConfidence: 0.85) == expected)
    }

    @Test("A half-translated cache still resolves to its majority language")
    func mixedLanguageTextResolvesToTheMajority() {
        let mixed = "Den Teig kneten und ruhen lassen. Laisser reposer la pâte. Anschließend bei 230 Grad backen."

        #expect(RecipeLanguageDetector.detectedLanguage(in: mixed, minimumConfidence: 0.85) == "de")
    }

    @Test("Ingredient names alone are still attributed correctly",
          arguments: [
            ("de", "Weizenmehl. Roggenmehl. Wasser. Salz. Frischhefe. Sauerteig. Butter. Zucker."),
            ("fr", "Farine de blé. Farine de seigle. Eau. Sel. Levure fraîche. Levain. Beurre. Sucre."),
            ("en", "Wheat flour. Rye flour. Water. Salt. Fresh yeast. Sourdough. Butter. Sugar.")
          ])
    func detectsLanguageFromIngredientNames(expected: String, text: String) {
        #expect(RecipeLanguageDetector.detectedLanguage(in: text, minimumConfidence: 0.85) == expected)
    }

    // MARK: - Reading the cache rather than the live values

    @Test("The language of a cached slot is read from the cache, not from what is on screen")
    func readsTheCachedTextRatherThanTheLiveValues() {
        // A German recipe that has been translated and is currently showing the
        // French text. Judging by the live values would call the original French.
        let recipe = RecipeFixtures.german()
        recipe.storeLocalization(languageCode: "de")
        RecipeFixtures.replaceLiveText(of: recipe, with: RecipeFixtures.french())
        recipe.storeLocalization(languageCode: "fr")

        #expect(RecipeLanguageDetector.detectedLanguage(of: recipe, storedUnder: "de", minimumConfidence: 0.85) == "de")
        #expect(RecipeLanguageDetector.detectedLanguage(of: recipe, storedUnder: "fr", minimumConfidence: 0.85) == "fr")
    }

    @Test("An empty cache slot falls back to the live values")
    func fallsBackToLiveValuesWhenNothingIsCached() {
        let recipe = RecipeFixtures.french()

        #expect(RecipeLanguageDetector.detectedLanguage(of: recipe, storedUnder: "de", minimumConfidence: 0.85) == "fr")
    }
}
