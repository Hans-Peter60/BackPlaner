//
//  RecipeWebPageLoaderTests.swift
//  BackPlanerTests
//

import Foundation
import Testing
@testable import BackPlaner

@Suite("Recipe web page loader")
struct RecipeWebPageLoaderTests {

    private let pageURL = URL(string: "https://example.com/rezepte/landbrot")!

    // MARK: - Address handling

    @Test("Typed addresses are completed to https and checked for a domain",
          arguments: [
            ("ploetzblog.de/rezept", "https://ploetzblog.de/rezept"),
            ("http://www.chefkoch.de/rezepte/1", "https://www.chefkoch.de/rezepte/1"),
            ("  https://example.com/a?b=c  ", "https://example.com/a?b=c")
          ])
    func normalizesAddresses(input: String, expected: String) {
        #expect(RecipeWebPageLoader.normalizedURL(from: input)?.absoluteString == expected)
    }

    @Test("Text that is not an address is rejected",
          arguments: ["", "Landbrot", "ein rezept mit leerzeichen", "ftp://example.com/x"])
    func rejectsNonAddresses(input: String) {
        #expect(RecipeWebPageLoader.normalizedURL(from: input) == nil)
    }

    // MARK: - JSON-LD

    @Test("A plain schema.org recipe is read with all its parts")
    func readsPlainJSONLD() throws {
        let html = """
        <html lang="de"><head><title>Landbrot | Beispiel</title>
        <meta property="og:image" content="/bilder/og.jpg">
        <script type="application/ld+json">
        {"@context":"https://schema.org","@type":"Recipe","name":"Rustikales Landbrot",
         "description":"Ein kr&auml;ftiges Brot.","inLanguage":"de-DE",
         "image":["https://example.com/bilder/landbrot.jpg"],
         "prepTime":"PT30M","cookTime":"PT50M","totalTime":"P0DT1H20M",
         "recipeYield":"1 Laib","keywords":"Brot, Sauerteig",
         "recipeIngredient":["Für den Sauerteig:","100 g Roggenmehl 1150","100 g Wasser","Für den Hauptteig:","400 g Weizenmehl 550","1 ½ TL Salz","Wasser 280 ml"],
         "recipeInstructions":[
           {"@type":"HowToStep","text":"Sauerteig ansetzen und 12 Stunden reifen lassen."},
           {"@type":"HowToStep","text":"Ofen auf 250 °C vorheizen."},
           {"@type":"HowToStep","text":"Bei 230 °C 45 Minuten backen."}]}
        </script></head><body><main><article>\(String(repeating: "Lorem ipsum dolor sit amet. ", count: 40))</article></main></body></html>
        """
        let page = RecipeWebPageLoader.parse(html: html, url: pageURL)
        let recipe = try #require(page.structuredRecipe)

        #expect(recipe.name == "Rustikales Landbrot")
        #expect(recipe.summary == "Ein kräftiges Brot.")
        #expect(recipe.language == "de")
        #expect(recipe.imageURL?.absoluteString == "https://example.com/bilder/landbrot.jpg")
        #expect(recipe.prepMinutes == 30)
        #expect(recipe.cookMinutes == 50)
        #expect(recipe.totalMinutes == 80)
        #expect(recipe.yield == "1 Laib")
        #expect(recipe.keywords == ["Brot", "Sauerteig"])
        #expect(recipe.ingredientLines.count == 7)
        #expect(recipe.instructionSections.flatMap(\.steps).count == 3)
        #expect(page.title == "Rustikales Landbrot")
        #expect(page.language == "de")
    }

    @Test("A recipe nested in @graph with HowToSections is found too")
    func readsGraphWithSections() throws {
        let html = """
        <html><head>
        <script type="application/ld+json">
        {"@context":"https://schema.org","@graph":[
          {"@type":"WebPage","name":"Seite"},
          {"@type":["Recipe","Thing"],"name":"Baguette",
           "image":{"@type":"ImageObject","url":"https://example.com/b.jpg"},
           "recipeIngredient":["500 g farine T65","10 g sel","2 c. à s. d'huile"],
           "recipeInstructions":[
             {"@type":"HowToSection","name":"Poolish","itemListElement":[
               {"@type":"HowToStep","text":"Mélanger et laisser reposer 12 heures."}]},
             {"@type":"HowToSection","name":"Pâte","itemListElement":[
               {"@type":"HowToStep","text":"Pétrir 10 minutes."},
               {"@type":"HowToStep","text":"Cuire au four 25 minutes."}]}]}]}
        </script></head><body></body></html>
        """
        let page = RecipeWebPageLoader.parse(html: html, url: pageURL)
        let recipe = try #require(page.structuredRecipe)

        #expect(recipe.name == "Baguette")
        #expect(recipe.imageURL?.absoluteString == "https://example.com/b.jpg")
        #expect(recipe.instructionSections.map(\.name) == ["Poolish", "Pâte"])
        #expect(recipe.instructionSections.map(\.steps.count) == [1, 2])
    }

    @Test("Instructions given as one string are split into steps")
    func splitsInstructionString() throws {
        let html = """
        <script type="application/ld+json">{"@type":"Recipe","name":"Test",
        "recipeIngredient":["1 Ei"],
        "recipeInstructions":"1. Alles mischen.\\n2. Ruhen lassen.\\nSchritt 3: Backen."}</script>
        """
        let recipe = try #require(RecipeWebPageLoader.parse(html: html, url: pageURL).structuredRecipe)
        #expect(recipe.instructionSections.flatMap(\.steps) == ["Alles mischen.", "Ruhen lassen.", "Backen."])
    }

    @Test("ISO 8601 durations are converted to minutes",
          arguments: [("PT1H30M", 90), ("PT45M", 45), ("P0DT12H", 720), ("PT0M", 0), ("", 0), ("90", 0)])
    func convertsISODurations(value: String, minutes: Int) {
        #expect(RecipeWebPageLoader.isoMinutes(value) == minutes)
    }

    // MARK: - Page text

    @Test("The readable text keeps the article and drops scripts, navigation and footers")
    func extractsReadableText() {
        // Long enough for the article to count as the main content (2,000+
        // characters); a shorter one is taken for a teaser.
        let filler = String(repeating: "Dieses Brot gelingt immer. ", count: 90)
        let html = """
        <html><body>
        <nav><a href="/">Start</a><a href="/rezepte">Rezepte</a></nav>
        <header><h1>Blog</h1></header>
        <article>
        <h1>Landbrot</h1>
        <script>var x = 1;</script>
        <style>.a{color:red}</style>
        <p>\(filler)</p>
        <h2>Zutaten</h2>
        <ul><li>500&nbsp;g Mehl</li><li>10 g Salz &amp; Hefe</li></ul>
        <p>Den Teig 30&#160;Minuten ruhen lassen.</p>
        </article>
        <article class="comment">Tolles Rezept!</article>
        <footer>Impressum · Datenschutz</footer>
        </body></html>
        """
        let text = RecipeWebPageLoader.readableText(from: html)

        #expect(text.contains("Landbrot"))
        #expect(text.contains("- 500 g Mehl"))
        #expect(text.contains("10 g Salz & Hefe"))
        #expect(text.contains("Den Teig 30 Minuten ruhen lassen."))
        #expect(!text.contains("var x"))
        #expect(!text.contains("color:red"))
        #expect(!text.contains("Impressum"))
        #expect(!text.contains("Tolles Rezept"))
        #expect(!text.contains("Start"))
    }

    @Test("HTML entities are decoded, unknown ones are left alone")
    func decodesEntities() {
        #expect(RecipeWebPageLoader.decodingEntities("Br&ouml;tchen &amp; &frac12; TL &#8211; &#x00E9;") == "Brötchen & ½ TL – é")
        #expect(RecipeWebPageLoader.decodingEntities("&unknownthing; bleibt") == "&unknownthing; bleibt")
    }

    @Test("The analysis text puts the structured data before the page text")
    func composesAnalysisText() throws {
        let html = """
        <script type="application/ld+json">{"@type":"Recipe","name":"Test","recipeIngredient":["1 Ei"],
        "recipeInstructions":"Backen."}</script><body><article>\(String(repeating: "Seitentext. ", count: 60))</article></body>
        """
        let page = RecipeWebPageLoader.parse(html: html, url: pageURL)
        let text = page.analysisText
        let structuredRange = try #require(text.range(of: "STRUKTURIERTE REZEPTDATEN"))
        let pageRange = try #require(text.range(of: "SEITENTEXT:"))
        #expect(structuredRange.lowerBound < pageRange.lowerBound)
        #expect(text.contains("- 1 Ei"))
    }

    // MARK: - Rule-based recipe

    @Test("Ingredient lines are split into amount, unit and name",
          arguments: [
            ("500 g Weizenmehl 550", 500.0, "g", "Weizenmehl 550"),
            ("1 ½ TL Salz", 1.5, "TL", "Salz"),
            ("2-3 EL Olivenöl", 2.5, "EL", "Olivenöl"),
            ("Wasser 280 ml", 280.0, "ml", "Wasser"),
            ("1/2 Würfel Hefe", 0.5, "Würfel", "Hefe"),
            ("2 cups bread flour", 2.0, "cups", "bread flour"),
            ("10 gr. Salz", 10.0, "g", "Salz"),
            ("etwas Mehl zum Bestäuben", 0.0, "", "etwas Mehl zum Bestäuben"),
            ("- 3 Eier", 3.0, "", "Eier")
          ])
    func parsesIngredientLines(line: String, amount: Double, unit: String, name: String) {
        let parsed = StructuredWebRecipe.parseIngredientLine(line)
        #expect(parsed.amount == amount)
        #expect(parsed.unit == unit)
        #expect(parsed.name == name)
    }

    @Test("Headings among the ingredient lines are recognised",
          arguments: [
            ("Für den Sauerteig:", "Sauerteig"),
            ("Hauptteig", nil),
            ("For the poolish", "Poolish"),
            ("Pour la pâte :", "Pâte"),
            ("100 g Mehl", nil)
          ])
    func recognisesComponentHeadings(line: String, heading: String?) {
        #expect(StructuredWebRecipe.componentHeading(in: line) == heading)
    }

    @Test("Explicit durations are taken from step text",
          arguments: [
            ("12 Stunden reifen lassen", 720),
            ("Bei 230 °C 45 Minuten backen", 45),
            ("Let rest for 1 to 2 hours", 90),
            ("Pétrir 10 min, puis laisser reposer 1 h 30 min", 60),
            ("Ofen auf 250 °C vorheizen", 0)
          ])
    func readsExplicitDurations(text: String, minutes: Int) {
        #expect(StructuredWebRecipe.explicitMinutes(in: text) == minutes)
    }

    @Test("A step names its component once the recipe has several, unless it already does",
          arguments: [
            ("12 Stunden reifen lassen.", "Roggensauerteig", true, "Roggensauerteig: 12 Stunden reifen lassen."),
            ("Den gesamten Roggensauerteig zugeben.", "Roggensauerteig", true, "Den gesamten Roggensauerteig zugeben."),
            ("12 Stunden reifen lassen.", "Roggensauerteig", false, "12 Stunden reifen lassen."),
            ("12 Stunden reifen lassen.", "", true, "12 Stunden reifen lassen.")
          ])
    func namesTheComponentInTheStep(text: String, component: String, multi: Bool, expected: String) {
        #expect(RecipeImportStepText.text(text, naming: component, inMultiComponentRecipe: multi) == expected)
    }

    @Test("A step without a stated duration gets one minute, stated ones are kept")
    @MainActor
    func defaultsMissingDurationsToOneMinute() {
        let steps = [0, 45, -3].map { minutes -> InstructionFB in
            let instruction = InstructionFB()
            instruction.duration = minutes
            return instruction
        }
        RecipeImportStepText.applyDefaultDuration(to: steps)
        #expect(steps.map(\.duration) == [1, 45, 1])
    }

    @Test("Steps of named sections carry the section name when there are several")
    @MainActor
    func sectionNamesReachTheSteps() {
        var structured = StructuredWebRecipe()
        structured.name = "Baguette"
        structured.ingredientLines = ["500 g Mehl"]
        structured.instructionSections = [
            StructuredInstructionSection(name: "Poolish", steps: ["12 Stunden reifen lassen."]),
            StructuredInstructionSection(name: "Hauptteig", steps: ["Poolish und Mehl mischen.", "Backen."])
        ]
        let recipe = structured.makeRecipe()
        #expect(recipe.instructions.map(\.instruction) == [
            "Poolish: 12 Stunden reifen lassen.",
            "Hauptteig: Poolish und Mehl mischen.",
            "Hauptteig: Backen."
        ])
        #expect(recipe.instructions.map(\.componentName) == ["Poolish", "Hauptteig", "Hauptteig"])
    }

    @Test("The rule-based recipe keeps the components the ingredient list implies")
    @MainActor
    func buildsRecipeFromStructuredData() {
        var structured = StructuredWebRecipe()
        structured.name = "Landbrot"
        structured.ingredientLines = [
            "Für den Sauerteig:", "100 g Roggenmehl", "100 g Wasser",
            "Für den Hauptteig:", "400 g Weizenmehl", "10 g Salz"
        ]
        structured.instructionSections = [
            StructuredInstructionSection(name: "", steps: [
                "Sauerteig ansetzen und 12 Stunden reifen lassen.",
                "Ofen auf 250 °C vorheizen.",
                "45 Minuten backen."
            ])
        ]
        let recipe = structured.makeRecipe()

        #expect(recipe.name == "Landbrot")
        #expect(recipe.components.map(\.name) == ["Sauerteig", "Hauptteig"])
        #expect(recipe.components.map(\.ingredients.count) == [2, 2])
        #expect(recipe.totalWeight == 610)
        #expect(recipe.instructions.map(\.duration) == [720, GlobalVariables.preheatTime, 45])
        #expect(recipe.instructions.map(\.bakeFlag) == [false, false, true])
    }
}
