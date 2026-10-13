//
//  BakingGlossaryTests.swift
//  BackPlanerTests
//
//  The glossary itself and the plan that carries its terms through a round
//  of machine translation. The translator is simulated: the tests hand the
//  plan whatever "translation" the round is supposed to have produced.
//

import Testing
@testable import BackPlaner

@Suite("Baking glossary: finding terms")
struct BakingGlossaryMatchingTests {

    @Test("A term is found as a whole word, whatever its case or accents", arguments: [
        "Das Brühstück abkühlen lassen",
        "das BRÜHSTÜCK abkühlen lassen",
        "Das Bruhstuck abkühlen lassen",
        "Brühstück",
        "(Brühstück)"
    ])
    func findsWholeWord(text: String) {
        let found = BakingGlossary.matches(in: text, language: "de")
        #expect(found.count == 1)
        #expect(found.first.map { BakingGlossary.rendering(of: $0, in: "en", capitalized: false) } == "scald")
    }

    @Test("Other compounds are left to the translator", arguments: ["Brühstückzutaten", "Hauptteigmenge", "Sauerteigbrot"])
    func ignoresCompounds(text: String) {
        #expect(BakingGlossary.matches(in: text, language: "de").isEmpty)
    }

    @Test("Grain compounds are glossary terms of their own", arguments: [
        ("Weizenanstellgut",   "wheat sourdough starter", "levain chef de blé"),
        ("Weizen-Anstellgut",  "wheat sourdough starter", "levain chef de blé"),
        ("Roggenanstellgut",   "rye sourdough starter",   "levain chef de seigle"),
        ("Roggensauerteig",    "rye sourdough",           "levain de seigle"),
        ("Dinkelsauerteig",    "spelt sourdough",         "levain d'épeautre"),
        ("Vollkornsauerteig",  "wholegrain sourdough",    "levain complet"),
        ("Weizenvorteig",      "wheat preferment",        "pré-ferment de blé"),
        ("Sauerteigstufe",     "sourdough stage",         "étape de levain")
    ])
    func grainCompounds(text: String, english: String, french: String) throws {
        let found = try #require(BakingGlossary.matches(in: text, language: "de").first)
        #expect(BakingGlossary.rendering(of: found, in: "en", capitalized: false) == english)
        #expect(BakingGlossary.rendering(of: found, in: "fr", capitalized: false) == french)
    }

    @Test("The compound reads back from English into the German word")
    func grainCompoundFromEnglish() throws {
        let found = try #require(BakingGlossary.matches(in: "Feed the wheat sourdough starter", language: "en").first)
        #expect(BakingGlossary.rendering(of: found, in: "de", capitalized: false) == "Weizenanstellgut")
        #expect(BakingGlossary.matches(in: "Feed the wheat sourdough starter", language: "en").count == 1)
    }

    @Test("A cached 'wheat animal feed' is stale and a lone one is repaired")
    func animalFeed() {
        #expect(!BakingGlossary.translationHonoursGlossary(sourceText: "Weizenanstellgut", translation: "wheat animal feed", from: "de", into: "en"))
        #expect(GlossaryTranslationPlan.termTranslation(of: "Weizenanstellgut", from: "de", into: "en") == "Wheat sourdough starter")
    }

    @Test("The longer form wins: a sourdough starter is not a sourdough plus a word")
    func longestFormWins() {
        let found = BakingGlossary.matches(in: "Feed the sourdough starter", language: "en")
        #expect(found.count == 1)
        #expect(found.first.map { BakingGlossary.rendering(of: $0, in: "de", capitalized: false) } == "Anstellgut")
    }

    @Test("Terms are reported left to right")
    func ordered() {
        let found = BakingGlossary.matches(in: "Hauptteig aus Brühstück und Sauerteig", language: "de")
        #expect(found.map { BakingGlossary.rendering(of: $0, in: "en", capitalized: false) } == ["main dough", "scald", "sourdough"])
    }

    @Test("A plural form is written in the plural")
    func plural() {
        let found = BakingGlossary.matches(in: "Teiglinge", language: "de")
        #expect(found.first.map { BakingGlossary.rendering(of: $0, in: "en", capitalized: true) } == "Dough pieces")
        #expect(found.first.map { BakingGlossary.rendering(of: $0, in: "fr", capitalized: false) } == "pâtons")
    }

    @Test("A translation is checked for the glossary's words", arguments: [
        ("Brühstück", "Scald", true),
        ("Brühstück", "Breakfast", false),
        ("Das Brühstück mit dem Hauptteig vermischen", "Mix the scald with the main dough", true),
        ("Das Brühstück mit dem Hauptteig vermischen", "Mix the breakfast with the main dough", false),
        ("Saaten-Brühstück", "Seed scald", true),
        ("Wasser", "Anything at all", true),
        ("", "", true)
    ])
    func honoursGlossary(source: String, translation: String, expected: Bool) {
        #expect(BakingGlossary.translationHonoursGlossary(sourceText: source, translation: translation, from: "de", into: "en") == expected)
    }

    @Test("Every term is written in all three languages")
    func complete() {
        for term in BakingGlossary.terms {
            for language in ["de", "en", "fr"] {
                #expect(term.forms[language]?.singular.first != nil, "\(term.forms) lacks \(language)")
            }
        }
    }
}

@Suite("Baking glossary: the translation plan")
struct GlossaryTranslationPlanTests {

    @Test("A text that is a term is answered by the glossary and not sent")
    func termOnly() {
        let plan = GlossaryTranslationPlan(texts: ["Brühstück"], from: "de", into: "en")
        #expect(plan.sourceTexts.isEmpty)
        #expect(plan.results(translated: []) == ["Scald"])

        let french = GlossaryTranslationPlan(texts: ["Brühstück"], from: "de", into: "fr")
        #expect(french.results(translated: []) == ["Échaudage"])
    }

    @Test("A text without terms goes through unchanged")
    func direct() {
        let plan = GlossaryTranslationPlan(texts: ["Weizenmehl 550"], from: "de", into: "en")
        #expect(plan.sourceTexts == ["Weizenmehl 550"])
        #expect(plan.results(translated: ["Wheat flour 550"]) == ["Wheat flour 550"])
    }

    @Test("Empty texts are neither sent nor changed")
    func empty() {
        let plan = GlossaryTranslationPlan(texts: ["", "  "], from: "de", into: "en")
        #expect(plan.sourceTexts.isEmpty)
        #expect(plan.results(translated: []) == ["", "  "])
    }

    @Test("Terms in a sentence travel as placeholders and come back as words")
    func placeholders() {
        let plan = GlossaryTranslationPlan(texts: ["Das Brühstück mit dem Hauptteig vermischen."], from: "de", into: "en")

        #expect(plan.sourceTexts.first == "Das [[1]] mit dem [[2]] vermischen.")
        // The pieces for the fallback travel in the same round; a piece keeps
        // its punctuation, which the translator needs for the sentence end.
        #expect(plan.sourceTexts.dropFirst().elementsEqual(["Das", "mit dem", "vermischen."]))

        let results = plan.results(translated: ["Mix the [[1]] with the [[2]].", "The", "with the", "mix"])
        #expect(results == ["Mix the scald with the main dough."])
    }

    @Test("A placeholder the translator moved to the front starts the sentence")
    func capitalizedAtStart() {
        let plan = GlossaryTranslationPlan(texts: ["Lass das Brühstück abkühlen"], from: "de", into: "en")
        let results = plan.results(translated: ["[[1]] should cool down", "Lass das", "cool down"])
        #expect(results == ["Scald should cool down"])
    }

    @Test("Brackets the translator doubled or spaced are still recognised")
    func tolerantPlaceholders() {
        let plan = GlossaryTranslationPlan(texts: ["Das Brühstück abkühlen lassen"], from: "de", into: "en")
        let results = plan.results(translated: ["Let the [ [1] ] cool down", "Let the", "cool down"])
        #expect(results == ["Let the scald cool down"])
    }

    @Test("A lost placeholder falls back to the pieces around the glossary's word")
    func fallback() {
        let plan = GlossaryTranslationPlan(texts: ["Das Brühstück mit dem Hauptteig vermischen"], from: "de", into: "en")
        let results = plan.results(translated: ["Mix the breakfast with the main dough", "The", "with the", "mix"])
        #expect(results == ["The scald with the main dough mix"])
    }

    @Test("Punctuation between terms needs no translating")
    func punctuationOnly() {
        let plan = GlossaryTranslationPlan(texts: ["Brühstück, Hauptteig"], from: "de", into: "fr")
        #expect(plan.sourceTexts == ["[[1]], [[2]]"])
        #expect(plan.results(translated: ["[[1]], [[2]]"]) == ["Échaudage, pâte principale"])
        // Even a round that lost both placeholders has nothing to translate.
        #expect(plan.results(translated: ["breakfast, main dough"]) == ["Échaudage, pâte principale"])
    }

    @Test("The round works in the other direction as well")
    func englishToGerman() {
        let plan = GlossaryTranslationPlan(texts: ["Mix the scald with the main dough"], from: "en", into: "de")
        #expect(plan.sourceTexts.first == "Mix the [[1]] with the [[2]]")
        let results = plan.results(translated: ["Das [[1]] mit dem [[2]] vermischen", "Mischen", "mit dem", ""])
        #expect(results == ["Das Brühstück mit dem Hauptteig vermischen"])
    }

    @Test("Results keep the order of the texts, whatever route each one took")
    func mixedOrder() {
        let plan = GlossaryTranslationPlan(texts: ["", "Brühstück", "Wasser", "gesamtes Brühstück"], from: "de", into: "en")
        #expect(plan.sourceTexts == ["Wasser", "gesamtes [[1]]", "gesamtes"])
        #expect(plan.results(translated: ["Water", "entire [[1]]", "entire"]) == ["", "Scald", "Water", "entire scald"])
    }

    @Test("A short round leaves the texts beyond it as they were")
    func shortRound() {
        let plan = GlossaryTranslationPlan(texts: ["Wasser", "Salz"], from: "de", into: "en")
        #expect(plan.results(translated: ["Water"]) == ["Water", "Salz"])
    }
}
