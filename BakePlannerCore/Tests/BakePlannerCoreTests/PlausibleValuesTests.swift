//
//  PlausibleValuesTests.swift
//  BakePlannerCoreTests
//
//  Absurd numbers — NaN, infinity, twenty digits, Int.max — from every way
//  a number gets into the app. Each of these used to stop the app when the
//  value was turned into an Int; now each is held to a plausible range or
//  refused.
//

import Foundation
import Testing
@testable import BakePlannerCore

@Suite("Absurd numbers are held to plausible ranges instead of crashing")
struct PlausibleValuesTests {

    @Test("The ranges and the conversion that never traps")
    func ranges() {
        #expect(Plausible.minutes(Double.nan) == 0)
        #expect(Plausible.minutes(Double.infinity) == 0)
        #expect(Plausible.minutes(-5.0) == 0)
        #expect(Plausible.minutes(90.4) == 90)
        #expect(Plausible.minutes(Int.max) == Plausible.maxMinutes)
        #expect(Plausible.grams(1e300) == Plausible.maxGrams)
        #expect(Plausible.grams(-.infinity) == 0)
        #expect(Plausible.grams(512.5) == 512.5)
        #expect(Plausible.temperature(.nan) == nil)
        #expect(Plausible.temperature(1e20) == 900)
        #expect(Plausible.fractionPart(Int.min) == 0)
        #expect(Plausible.roundedInt(.nan) == 0)
        #expect(Plausible.roundedInt(1e300) == 1_000_000_000_000_000)
        #expect(Plausible.roundedInt(-2.6) == -3)
    }

    @Test("A web page's durations: ISO and in the text",
          arguments: ["PT99999999999999999999M", "P99999999999999999D", "PT1e400H"])
    func webDurations(_ iso: String) {
        #expect(RecipeWebPageLoader.isoMinutes(iso) <= Plausible.maxMinutes)
        #expect(RecipeWebPageLoader.isoMinutes("PT1H30M") == 90)
        #expect(StructuredWebRecipe.explicitMinutes(in: "99999999999999999999 Minuten gehen lassen") == Plausible.maxMinutes)
        #expect(StructuredWebRecipe.explicitMinutes(in: "2 Stunden gehen lassen") == 120)
    }

    @Test("A page whose recipe states absurd times and amounts parses")
    func webPageParses() throws {
        let html = """
        <script type="application/ld+json">
        {"@type":"Recipe","name":"Brot","totalTime":"PT99999999999999999999M",
         "recipeIngredient":["100000000000000000000 g Mehl","1e400 g Wasser"],
         "recipeInstructions":["Teig 99999999999999999999 Minuten kneten","Bei 250 °C backen"]}
        </script>
        """
        let page = RecipeWebPageLoader.parse(html: html, url: try #require(URL(string: "https://example.org/brot")))
        #expect(page.structuredRecipe != nil)
    }

    @Test("Typed durations beyond sixty days or not finite are no duration",
          arguments: ["1e30", "inf", "99999999999999999999", "1e30 h", "99999999999999999999 min"])
    func typedDurations(_ text: String) {
        #expect(DurationInput.minutes(from: text) == nil)
    }

    @Test("Ordinary typed durations read as before")
    func ordinaryDurations() {
        #expect(DurationInput.minutes(from: "90") == 90)
        #expect(DurationInput.minutes(from: "1,5") == 90)
        #expect(DurationInput.minutes(from: "1h 30") == 90)
        #expect(DurationInput.minutes(from: "14 Std") == 840)
        #expect(DurationInput.minutes(from: "504 h") == 30_240)
    }

    @Test("A fraction without a denominator, or absurd parts, is no crash")
    func portions() {
        #expect(Rational.getPortion(unit: "TL", weight: 0, num: 3, denom: 0, scale: 1) == "")
        #expect(!Rational.getPortion(unit: "TL", weight: 0, num: Int.max, denom: 7, scale: 1.5).isEmpty)
        #expect(!Rational.getPortion(unit: "g", weight: 250, num: 0, denom: 0, scale: .infinity).isEmpty)
        #expect(Rational.getPortion(unit: "TL", weight: 0, num: 1, denom: 2, scale: 1) == "1/2 TL ")
        #expect(Rational.decimalPlace(.nan, 10) == "")
        #expect(Rational.decimalPlace(3.1, 10) == "3.1")
    }

    @Test("The editor refuses absurd amounts and shows stored ones")
    func editorAmounts() {
        #expect(IngredientAmountText.parse("1e30") == nil)
        #expect(IngredientAmountText.parse("inf") == nil)
        #expect(IngredientAmountText.parse("99999999999999999999") == nil)
        #expect(IngredientAmountText.parse("99999999999999999 1/2") == nil)
        #expect(IngredientAmountText.parse("1 1/2") == IngredientAmountText(weight: 0, numerator: 3, denominator: 2))
        #expect(IngredientAmountText.text(weight: 1e20, numerator: 0, denominator: 0, decimalSeparator: ",") == "1000000000000000")
    }

    @Test("A public recipe with NaN, infinity or Int.max is read in range")
    func firestoreNumbers() {
        let recipe = RecipeFirestoreMapping.recipe(id: "r", data: ["totalWeight": Double.nan, "prepTime": Int.max])
        #expect(recipe.totalWeight == 0)
        #expect(recipe.prepTime == Plausible.maxMinutes)
        let ingredient = RecipeFirestoreMapping.ingredient(id: "i", data: ["weight": Double.infinity, "num": 3])
        #expect(ingredient.weight == 0)
        #expect(ingredient.denom == 0)
        let instruction = RecipeFirestoreMapping.instruction(id: "s", data: ["duration": Int64.max, "step": 1e300,
                                                                            "ovenTemperature": Int.max, "minDuration": -5])
        #expect(instruction.duration == Plausible.maxMinutes)
        #expect(instruction.step == 999)
        #expect(instruction.ovenTemperature == 900)
        #expect(instruction.minDuration == 0)
    }

    @Test("A backup file with absurd numbers is read in range")
    func backupNumbers() throws {
        let json = """
        {"formatVersion": 7, "recipes": [{"name": "Brot", "summary": "", "prepTime": 9223372036854775807,
          "totalWeight": 1e300, "tags": [], "rating": 99, "recurrenceIntervalDays": -4,
          "components": [{"name": "Teig", "number": 1, "ingredients": [
            {"name": "Mehl", "number": 1, "weight": 1e20, "normWeight": -3, "num": 9223372036854775807, "denom": 0}]}],
          "instructions": [{"instruction": "Backen", "step": 1e300, "duration": 9223372036854775807,
            "startTime": -10, "bakeFlag": true, "ovenTemperature": 100000}]}]}
        """
        let file = try RecipeImport.decodeFile(Data(json.utf8))
        let recipe = try #require(file.recipes.first)
        #expect(recipe.prepTime == Plausible.maxMinutes)
        #expect(recipe.totalWeight == Plausible.maxGrams)
        #expect(recipe.rating == 5 && recipe.recurrenceIntervalDays == 0)
        let ingredient = try #require(recipe.components.first?.ingredients.first)
        #expect(ingredient.weight == Plausible.maxGrams && ingredient.normWeight == 0)
        #expect(ingredient.num == Plausible.maxFractionPart && ingredient.denom == 0)
        let instruction = try #require(recipe.instructions.first)
        #expect(instruction.step == 999 && instruction.duration == Plausible.maxMinutes && instruction.startTime == 0)
        #expect(instruction.ovenTemperature == 900)
    }

    @Test("Bake facts: absurd temperatures and proofs are refused or held")
    func bakeFacts() {
        #expect(BakeHistoryFacts.parseTemperature("99999999999999999999") == nil)
        #expect(BakeHistoryFacts.parseTemperature("24,5 °C") == 24.5)
        #expect(BakeHistoryFacts.parseMinutes("99999999999999999999") == nil)
        let facts = BakeHistoryFacts(roomTemperature: 1e20, finalProofMinutes: Int.max).normalized
        #expect(facts.roomTemperature == 900)
        #expect(facts.finalProofMinutes == Plausible.maxMinutes)
    }

    @Test("A dough weight of nineteen digits scales no further than a thousandfold")
    func servingScale() {
        #expect(ServingScale.factor(servingSize: 2, targetWeight: Int.max, baseWeight: 0.001) == 1000)
        #expect(ServingScale.factor(servingSize: 2, targetWeight: 1000, baseWeight: 500) == 2)
    }

    @Test("A photo or text recipe with twenty-digit numbers parses")
    func textRecipeParses() throws {
        let texts = ["Brot", "Zutaten", "100000000000000000000 g Mehl", "Zubereitung",
                     "Teig 99999999999999999999 Minuten kneten", "99999999999999999999-99999999999999999999 Stunden gehen lassen",
                     "Alle 1 Minuten falten, 1000000000000x", "Bei 250 °C 30 Minuten backen"]
        let lines = texts.enumerated().map { index, text in
            RecognizedRecipeLine(page: 0, text: text,
                                 boundingBox: CGRect(x: 0.1, y: 1 - Double(index) * 0.05, width: 0.8, height: 0.03))
        }
        _ = try? GeneralRecipeParser(lines: lines).parse()
    }

    @Test("A thirteenth month leaves the yearbook's twelve months alone")
    func hebrewCalendarYearbook() {
        var calendar = Calendar(identifier: .hebrew)
        calendar.timeZone = TimeZone(identifier: "Europe/Berlin")!
        let start = Date(timeIntervalSince1970: 1_788_000_000)   // autumn 2026
        let entries = (0..<400).map { offset in
            BakeYearbook.Entry(recipeName: "Brot", date: start.addingTimeInterval(Double(offset) * 86_400),
                               facts: BakeHistoryFacts(), photoCount: 0, photoKey: "p\(offset)",
                               flourGrams: 500, doughGrams: 850, durationMinutes: 600)
        }
        let year = calendar.component(.year, from: start.addingTimeInterval(200 * 86_400))
        let book = BakeYearbook.compute(year: year, entries: entries, now: start.addingTimeInterval(500 * 86_400),
                                        calendar: calendar)
        #expect(book.bakes > 0)
    }
}
