//
//  RecipeTextImportTests.swift
//  BakePlannerCoreTests
//
//  Pasted recipe text read by rules: the headings a recipe is printed
//  with, components, steps, and the texts that are no recipe.
//

import Foundation
import Testing
@testable import BakePlannerCore

@Suite("Pasted recipe text")
struct RecipeTextImportTests {

    /// A blog recipe as it comes out of "select all, copy" on a page that
    /// renders its recipe with JavaScript.
    private let germanBlogText = """
    Roggenmischbrot 70/30

    Ein kräftiges Alltagsbrot mit Sauerteig. Reicht für einen Laib von 1 kg.

    Zutaten

    Sauerteig
    140 g Roggenmehl 1150
    140 g Wasser (50 °C)
    14 g Anstellgut

    Hauptteig
    gesamter Sauerteig
    210 g Roggenmehl 1150
    150 g Weizenmehl 1050
    200 g Wasser (60 °C)
    10 g Salz
    5 g Frischhefe

    Zubereitung

    1. Die Sauerteigzutaten mischen und 16 Stunden bei Raumtemperatur reifen lassen.
    2. Alle Zutaten 5 Minuten auf niedrigster Stufe mischen und 5 Minuten auf zweiter Stufe kneten.
    3. 30 Minuten Teigruhe bei 24 °C.
    4. Den Teig rund wirken und mit Schluss nach oben im Gärkorb 60 Minuten
    bei 24 °C reifen lassen.
    5. Bei 250 °C fallend auf 220 °C 50 Minuten mit Dampf backen.

    Tipps
    Das Brot hält sich eine Woche frisch.
    """

    @Test("A German blog recipe becomes components, ingredients and steps")
    func readsGermanBlog() throws {
        let recipe = try #require(PastedRecipeText.structuredRecipe(from: germanBlogText))
        #expect(recipe.name == "Roggenmischbrot 70/30")
        #expect(recipe.summary == "Ein kräftiges Alltagsbrot mit Sauerteig. Reicht für einen Laib von 1 kg.")
        #expect(recipe.language == "de")
        #expect(recipe.ingredientLines == [
            "Sauerteig:", "140 g Roggenmehl 1150", "140 g Wasser (50 °C)", "14 g Anstellgut",
            "Hauptteig:", "gesamter Sauerteig", "210 g Roggenmehl 1150", "150 g Weizenmehl 1050",
            "200 g Wasser (60 °C)", "10 g Salz", "5 g Frischhefe",
        ])
        let steps = recipe.instructionSections.flatMap(\.steps)
        #expect(steps.count == 5)
        #expect(steps[0] == "Die Sauerteigzutaten mischen und 16 Stunden bei Raumtemperatur reifen lassen.")
        // A step broken over two lines is one step again; the tips after
        // the method are no steps.
        #expect(steps[3] == "Den Teig rund wirken und mit Schluss nach oben im Gärkorb 60 Minuten bei 24 °C reifen lassen.")
        #expect(steps[4].hasPrefix("Bei 250 °C"))
    }

    @MainActor
    @Test("The structured text builds the same recipe shape as a web page would")
    func makesRecipe() throws {
        let structured = try #require(PastedRecipeText.structuredRecipe(from: germanBlogText))
        let recipe = structured.makeRecipe()
        #expect(recipe.components.map(\.name) == ["Sauerteig", "Hauptteig"])
        #expect(recipe.components[0].ingredients.map(\.weight) == [140, 140, 14])
        #expect(recipe.components[1].ingredients.map(\.name).first == "gesamter Sauerteig")
        #expect(recipe.instructions.count == 5)
        #expect(recipe.instructions[0].duration == 16 * 60)
        #expect(recipe.instructions[4].bakeFlag == true)
        #expect(RecipeImportCheck.hasRecipeData(recipe))
    }

    @Test("An English recipe with per-component method sections")
    func readsEnglish() throws {
        let text = """
        Overnight White Loaf

        Ingredients
        For the poolish:
        150 g bread flour
        150 g water
        1 g instant yeast
        For the dough:
        350 g bread flour
        200 g water
        10 g salt

        Method
        Poolish
        Mix the flour, water and yeast and leave for 12 hours at room temperature.
        Dough
        Mix everything with the poolish and knead for 8 minutes.
        Bake at 240 °C for 40 minutes.
        """
        let recipe = try #require(PastedRecipeText.structuredRecipe(from: text))
        #expect(recipe.name == "Overnight White Loaf")
        #expect(recipe.language == "en")
        #expect(recipe.ingredientLines.filter { $0.hasSuffix(":") } == ["Poolish:", "Dough:"])
        #expect(recipe.instructionSections.map(\.name) == ["Poolish", "Dough"])
        #expect(recipe.instructionSections[1].steps.count == 2)
    }

    @Test("Without any heading, ingredient lines and sentences are told apart by shape")
    func readsTextWithoutHeadings() throws {
        let text = """
        Schnelles Weißbrot
        500 g Weizenmehl 550
        320 g Wasser
        10 g Salz
        4 g Hefe
        Alle Zutaten zu einem glatten Teig kneten und 90 Minuten gehen lassen.
        Formen, 45 Minuten gehen lassen und 35 Minuten bei 230 °C backen.
        """
        let recipe = try #require(PastedRecipeText.structuredRecipe(from: text))
        #expect(recipe.name == "Schnelles Weißbrot")
        #expect(recipe.ingredientLines.count == 4)
        #expect(recipe.instructionSections.flatMap(\.steps).count == 2)
    }

    @Test("Steps lose their numbering, in every spelling")
    func stripsStepNumbers() {
        #expect(PastedRecipeText.stepText("1. Mehl und Wasser mischen.") == "Mehl und Wasser mischen.")
        #expect(PastedRecipeText.stepText("2) Teig falten.") == "Teig falten.")
        #expect(PastedRecipeText.stepText("Schritt 3: Backen.") == "Backen.")
        #expect(PastedRecipeText.stepText("Step 4 Bake it.") == "Bake it.")
        #expect(PastedRecipeText.stepText("- Teig ruhen lassen.") == "Teig ruhen lassen.")
    }

    @Test("Component headings are recognised with and without a colon")
    func componentHeadings() {
        #expect(PastedRecipeText.componentHeading(in: "Sauerteig") == "Sauerteig")
        #expect(PastedRecipeText.componentHeading(in: "Für den Vorteig:") == "Vorteig")
        #expect(PastedRecipeText.componentHeading(in: "Hauptteig (TA 170)") == "Hauptteig")
        #expect(PastedRecipeText.componentHeading(in: "Weizensauerteig") == "Weizensauerteig")
        #expect(PastedRecipeText.componentHeading(in: "140 g Roggenmehl 1150") == nil)
        #expect(PastedRecipeText.componentHeading(in: "Den Teig 30 Minuten ruhen lassen.") == nil)
    }

    @Test("Text that is no recipe is rejected before any analysis")
    func validation() throws {
        #expect(throws: RecipeTextImportError.tooShort) {
            try PastedRecipeText.validated("Brot backen")
        }
        #expect(throws: RecipeTextImportError.looksLikeAddress(URL(string: "https://www.ploetzblog.de/rezept")!)) {
            try PastedRecipeText.validated("  https://www.ploetzblog.de/rezept \n")
        }
        #expect(PastedRecipeText.structuredRecipe(from: "Heute war ein schöner Tag zum Backen, aber ich habe kein Rezept aufgeschrieben.") == nil)
        let cleaned = try PastedRecipeText.validated(germanBlogText)
        #expect(cleaned.hasPrefix("Roggenmischbrot"))
    }

    @Test("Cleaning unifies line breaks and blank lines and cuts long text")
    func cleaning() {
        let text = "Titel\r\n\r\n\r\n\u{00A0}Zutaten \r\n500 g Mehl   \r\n\r\n"
        #expect(PastedRecipeText.normalized(text) == "Titel\n\nZutaten\n500 g Mehl")
        let long = String(repeating: "a", count: PastedRecipeText.maximumCharacters + 100)
        #expect(PastedRecipeText.normalized(long).count == PastedRecipeText.maximumCharacters)
    }
}
