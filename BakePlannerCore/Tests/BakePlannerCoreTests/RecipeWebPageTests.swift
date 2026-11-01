//
//  RecipeWebPageTests.swift
//  BakePlannerCoreTests
//
//  Reading a recipe page in the package, as the Android app does. The
//  detailed cases stay in the app's RecipeWebPageLoaderTests.
//

import Foundation
import Testing
@testable import BakePlannerCore

@Suite("Recipe pages read in the package")
struct RecipeWebPageTests {

    private let url = URL(string: "https://example.com/rezepte/landbrot")!

    private let html = """
    <html lang="de"><head><title>Landbrot – Blog</title>
    <meta property="og:image" content="/bilder/landbrot.jpg">
    <script type="application/ld+json">
    {"@context":"https://schema.org","@graph":[{"@type":"WebPage"},{"@type":"Recipe",
     "name":"Landbrot","description":"Kr&auml;ftig","inLanguage":"de-DE",
     "recipeIngredient":["500 g Weizenmehl 550","350 g Wasser","10 g Salz"],
     "recipeInstructions":[{"@type":"HowToStep","text":"Alles mischen."},{"@type":"HowToStep","text":"45 Minuten backen."}],
     "totalTime":"PT3H30M","keywords":"Brot, Weizen"}]}
    </script></head><body><article><p>Text</p></article></body></html>
    """

    @Test("The structured recipe, title, language and picture are found")
    func parsesPage() throws {
        let page = RecipeWebPageLoader.parse(html: html, url: url)
        let recipe = try #require(page.structuredRecipe)
        #expect(page.title == "Landbrot")
        #expect(page.language == "de")
        #expect(page.imageURL?.absoluteString == "https://example.com/bilder/landbrot.jpg")
        #expect(recipe.summary == "Kräftig")
        #expect(recipe.ingredientLines.count == 3)
        #expect(recipe.instructionSections.first?.steps == ["Alles mischen.", "45 Minuten backen."])
        #expect(recipe.totalMinutes == 210)
        #expect(recipe.keywords == ["Brot", "Weizen"])
    }

    @MainActor
    @Test("A recipe is built from the structured data alone")
    func makesRecipe() throws {
        let structured = try #require(RecipeWebPageLoader.parse(html: html, url: url).structuredRecipe)
        let recipe = structured.makeRecipe()
        #expect(recipe.name == "Landbrot")
        #expect(recipe.prepTime == 210)
        #expect(recipe.components.count == 1)
        #expect(recipe.components.first?.ingredients.map(\.name) == ["Weizenmehl 550", "Wasser", "Salz"])
        #expect(recipe.components.first?.ingredients.map(\.weight) == [500, 350, 10])
        #expect(recipe.instructions.map(\.duration) == [0, 45])
        #expect(recipe.totalWeight == 860)
    }

    @Test("Addresses are completed to https")
    func addresses() {
        #expect(RecipeWebPageLoader.normalizedURL(from: "ploetzblog.de/rezept")?.absoluteString
                == "https://ploetzblog.de/rezept")
        #expect(RecipeWebPageLoader.normalizedURL(from: "Landbrot") == nil)
    }
}
