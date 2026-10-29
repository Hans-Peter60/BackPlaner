//
//  RecipeContentTests.swift
//  BackPlanerTests
//
//  The calculations that read an own recipe now work on its content as a
//  plain value (RecipeExportData). Each is checked against the public-recipe
//  version, which has its own code, and against the Core Data recipe the
//  value is made from.
//

import CoreData
import Foundation
import Testing
@testable import BackPlaner

/// A starter refreshed 1:5:5 — mixed and left to ripen, no oven.
private func starter() -> RecipeExportData {
    RecipeExportData(
        name: "Roggensauer", summary: "", urlLink: nil, prepTime: 725, totalWeight: 220,
        tags: [], rating: 0, recurrenceIntervalDays: 1, image: nil,
        components: [
            RecipeExportComponent(name: "Roggensauer", number: 1, ingredients: [
                RecipeExportIngredient(name: "Anstellgut", number: 1, unit: "g", weight: 20, normWeight: 20, num: 0, denom: 0),
                RecipeExportIngredient(name: "Roggenmehl 1150", number: 2, unit: "g", weight: 100, normWeight: 100, num: 0, denom: 0),
                RecipeExportIngredient(name: "Wasser", number: 3, unit: "g", weight: 100, normWeight: 100, num: 0, denom: 0),
            ]),
        ],
        instructions: [
            RecipeExportInstruction(instruction: "Zutaten mischen", step: 1, duration: 5,
                                    startTime: 0, bakeFlag: false, componentName: nil),
            RecipeExportInstruction(instruction: "Bei 26 °C 12 Stunden reifen lassen", step: 2, duration: 720,
                                    startTime: 5, bakeFlag: false, componentName: nil),
        ])
}

/// A bread of two components, one step naming its component, one only
/// wording it, and a bake.
private func bread() -> RecipeExportData {
    RecipeExportData(
        name: "Landbrot", summary: "Kräftig", urlLink: "https://example.com", prepTime: 900, totalWeight: 1_010,
        tags: ["Roggen"], rating: 4, recurrenceIntervalDays: 0, image: nil,
        components: [
            RecipeExportComponent(name: "Sauerteig", number: 1, ingredients: [
                RecipeExportIngredient(name: "Roggenmehl 1150", number: 1, unit: "g", weight: 200, normWeight: 200, num: 0, denom: 0),
                RecipeExportIngredient(name: "Wasser", number: 2, unit: "g", weight: 200, normWeight: 200, num: 0, denom: 0),
                RecipeExportIngredient(name: "Anstellgut", number: 3, unit: "g", weight: 20, normWeight: 20, num: 0, denom: 0),
            ]),
            RecipeExportComponent(name: "Hauptteig", number: 2, ingredients: [
                RecipeExportIngredient(name: "gesamter Sauerteig", number: 1, unit: nil, weight: 0, normWeight: 0, num: 0, denom: 0),
                RecipeExportIngredient(name: "Weizenmehl 550", number: 2, unit: "g", weight: 400, normWeight: 400, num: 0, denom: 0),
                RecipeExportIngredient(name: "Salz", number: 3, unit: "g", weight: 12, normWeight: 12, num: 0, denom: 0),
                RecipeExportIngredient(name: "Hefe", number: 4, unit: "Würfel", weight: 0, normWeight: 0, num: 1, denom: 4),
            ]),
        ],
        instructions: [
            RecipeExportInstruction(instruction: "Sauerteig ansetzen und reifen lassen", step: 1, duration: 720,
                                    startTime: 0, bakeFlag: false, componentName: nil),
            RecipeExportInstruction(instruction: "Alle Zutaten kneten", step: 2, duration: 15,
                                    startTime: 720, bakeFlag: false, componentName: "Hauptteig"),
            RecipeExportInstruction(instruction: "Bei 250 °C 50 Minuten backen", step: 3, duration: 50,
                                    startTime: 900, bakeFlag: true, componentName: nil),
        ])
}

/// The same content as a public recipe.
private func publicRecipe(_ data: RecipeExportData) -> RecipeFB {
    let recipe = RecipeFB()
    recipe.name = data.name
    recipe.summary = data.summary
    recipe.urlLink = data.urlLink ?? ""
    recipe.prepTime = data.prepTime
    recipe.totalWeight = data.totalWeight
    recipe.tags = data.tags
    recipe.components = data.components.map { component in
        let componentFB = ComponentFB()
        componentFB.name = component.name
        componentFB.number = component.number
        componentFB.ingredients = component.ingredients.map { ingredient in
            let ingredientFB = IngredientFB()
            ingredientFB.name = ingredient.name
            ingredientFB.number = ingredient.number
            ingredientFB.unit = ingredient.unit ?? ""
            ingredientFB.weight = ingredient.weight
            ingredientFB.normWeight = ingredient.normWeight
            ingredientFB.num = ingredient.num
            ingredientFB.denom = ingredient.denom
            return ingredientFB
        }
        return componentFB
    }
    recipe.instructions = data.instructions.map { instruction in
        let instructionFB = InstructionFB()
        instructionFB.instruction = instruction.instruction
        instructionFB.step = instruction.step
        instructionFB.duration = instruction.duration
        instructionFB.startTime = instruction.startTime
        instructionFB.componentName = instruction.componentName
        return instructionFB
    }
    return recipe
}

/// A column as text, for comparing columns whose ids are made differently.
private func describe(_ column: ComponentColumn?) -> [String]? {
    column.map { column in
        [column.name] + column.ingredients.map {
            "\($0.weight) \($0.unit) \($0.numerator)/\($0.denominator) \($0.name)"
        }
    }
}

/// The printed page as text, everything but the picture.
private func describe(_ page: RecipePrintData) -> [String] {
    [page.name, page.summary, "\(page.totalWeight)", page.prepTime, page.urlLink ?? "-"]
        + page.totalLines
        + page.components.flatMap { [$0.name] + $0.lines }
        + page.steps.map { "\($0.number) \($0.text) \($0.duration)" }
}

@Suite("Calculations on an own recipe's content")
struct RecipeContentTests {

    @Test("A starter is recognised, with its feeding ratio, as in a public recipe")
    func starterFeeding() throws {
        let data = starter()

        #expect(StarterRecipe.isStarterFeeding(data))
        #expect(StarterRecipe.isStarterFeeding(publicRecipe(data)))
        let ratio = try #require(StarterFeedingRatio.ratio(for: data))
        #expect(ratio == StarterFeedingRatio.Ratio(starter: 1, flour: 5, water: 5))
        #expect(ratio == StarterFeedingRatio.ratio(components: DoughComposition.components(of: publicRecipe(data))))
    }

    @Test("A bread is no starter")
    func breadIsNoStarter() {
        #expect(!StarterRecipe.isStarterFeeding(bread()))
        #expect(!StarterRecipe.isStarterFeeding(publicRecipe(bread())))
    }

    @Test("A step's component comes from its stored name or its wording, as in a public recipe")
    func componentOfAStep() {
        let data = bread()
        let recipeFB = publicRecipe(data)

        for (step, text) in [(1.0, "Sauerteig ansetzen und reifen lassen"), (2.0, "Alle Zutaten kneten")] {
            let column = ScheduledStepComponent.column(for: data, step: step, instructionText: text)
            #expect(describe(column) == describe(ScheduledStepComponent.column(for: recipeFB, step: step,
                                                                               instructionText: text)))
        }
        #expect(ScheduledStepComponent.column(for: data, step: 1, instructionText: "Sauerteig ansetzen")?.name == "Sauerteig")
        #expect(ScheduledStepComponent.column(for: data, step: 2, instructionText: "Alle Zutaten kneten")?.name == "Hauptteig")
        #expect(ScheduledStepComponent.column(for: data, step: 3, instructionText: "Bei 250 °C 50 Minuten backen") == nil)
    }

    @Test("The printed page is the same as for the public recipe")
    func printedPage() {
        for data in [bread(), starter()] {
            for scale in [1.0, 1.5] {
                #expect(describe(RecipePrintData(data: data, scale: scale))
                        == describe(RecipePrintData(recipeFB: publicRecipe(data), image: nil, scale: scale)))
            }
        }
    }

    @Test("A plan lasts the stored time, or until its last step ends")
    func planDuration() {
        var data = bread()
        #expect(RecurringBakePlanner.planDuration(of: data) == 950)
        data.prepTime = 1_000
        #expect(RecurringBakePlanner.planDuration(of: data) == 1_000)
        #expect(RecurringBakePlanner.planDuration(of: publicRecipe(data)) == 1_000)
    }
}

// On the main actor: the context is the view context, a main-queue context.
@Suite("Own recipes in Core Data give the same results as their content")
@MainActor
struct RecipeContentCoreDataTests {

    private func stored(_ data: RecipeExportData) throws -> Recipe {
        let context = PersistenceController(inMemory: true).container.viewContext
        let recipe = data.makeRecipe(in: context)
        try context.save()
        return recipe
    }

    @Test("Starter recognition and feeding ratio")
    func starterRecognition() throws {
        for data in [starter(), bread()] {
            let recipe = try stored(data)
            #expect(StarterRecipe.isStarterFeeding(recipe) == StarterRecipe.isStarterFeeding(data))
            #expect(StarterFeedingRatio.ratio(for: recipe) == StarterFeedingRatio.ratio(for: data))
        }
    }

    @Test("The component of a planned step")
    func componentOfAStep() throws {
        let data = bread()
        let recipe = try stored(data)
        for instruction in data.instructions {
            #expect(describe(ScheduledStepComponent.column(for: recipe, step: instruction.step,
                                                           instructionText: instruction.instruction))
                    == describe(ScheduledStepComponent.column(for: data, step: instruction.step,
                                                              instructionText: instruction.instruction)))
        }
    }

    @Test("The printed page and the plan duration")
    func printedPageAndDuration() throws {
        let data = bread()
        let recipe = try stored(data)
        #expect(describe(RecipePrintData(recipe: recipe, scale: 1.5)) == describe(RecipePrintData(data: data, scale: 1.5)))
        #expect(RecurringBakePlanner.planDuration(of: recipe) == RecurringBakePlanner.planDuration(of: data))
    }

    @Test("Leaving the image out changes nothing else")
    func withoutImage() throws {
        var data = bread()
        data.image = Data([0x01, 0x02])
        let recipe = try stored(data)

        let full = RecipeExportData(recipe: recipe)
        var withoutImage = RecipeExportData(recipe: recipe, includingImage: false)
        #expect(full.image == data.image)
        #expect(withoutImage.image == nil)
        withoutImage.image = full.image
        #expect(withoutImage == full)
    }
}
