//
//  RecipePersistenceTests.swift
//  BackPlanerTests
//
//  How own recipes are written into Core Data today: the backup file in
//  both directions, a public recipe taken over as an own one, an adjusted
//  copy written over a recipe, and fold steps added to a stored recipe.
//  These record the current behaviour, so moving the storage behind a
//  repository later can be checked against them.
//

import BakePlannerCore
import CoreData
import Foundation
import Testing
import UIKit
@testable import BackPlaner

// On the main actor: the context is the view context, a main-queue context.
@Suite("Own recipes in Core Data")
@MainActor
struct RecipePersistenceTests {

    private func makeContext() -> NSManagedObjectContext {
        PersistenceController(inMemory: true).container.viewContext
    }

    private func count<T: NSManagedObject>(_ type: T.Type, in context: NSManagedObjectContext) throws -> Int {
        try context.count(for: NSFetchRequest<T>(entityName: String(describing: type)))
    }

    /// A recipe with every field of the backup format set, in display order:
    /// components and ingredients by number, steps by step.
    private func sampleData() -> RecipeExportData {
        RecipeExportData(
            name: "Landbrot",
            summary: "Kräftiges Mischbrot",
            urlLink: "https://example.com/landbrot",
            prepTime: 900,
            totalWeight: 1_010,
            tags: ["Sauerteig", "Roggen"],
            rating: 4,
            recurrenceIntervalDays: 7,
            image: Data([0x01, 0x02, 0x03]),
            components: [
                RecipeExportComponent(name: "Sauerteig", number: 1, ingredients: [
                    RecipeExportIngredient(name: "Roggenmehl 1150", number: 1, unit: "g",
                                           weight: 200, normWeight: 200, num: 0, denom: 0),
                    RecipeExportIngredient(name: "Wasser", number: 2, unit: "g",
                                           weight: 200, normWeight: 200, num: 0, denom: 0),
                ]),
                RecipeExportComponent(name: "Hauptteig", number: 2, ingredients: [
                    RecipeExportIngredient(name: "Weizenmehl 550", number: 1, unit: "g",
                                           weight: 400, normWeight: 400, num: 0, denom: 0),
                    RecipeExportIngredient(name: "Hefe", number: 2, unit: nil,
                                           weight: 0, normWeight: 0, num: 1, denom: 4),
                ]),
            ],
            instructions: [
                RecipeExportInstruction(instruction: "Sauerteig ansetzen", step: 1, duration: 720,
                                        startTime: 0, bakeFlag: false, componentName: "Sauerteig"),
                RecipeExportInstruction(instruction: "Hauptteig kneten", step: 2, duration: 15,
                                        startTime: 720, bakeFlag: false, componentName: "Hauptteig"),
                RecipeExportInstruction(instruction: "Bei 250 °C backen", step: 3, duration: 50,
                                        startTime: 735, bakeFlag: true, componentName: nil),
            ]
        )
    }

    // MARK: - Backup file

    @Test("A recipe written from the backup format reads back unchanged")
    func backupRoundTrip() throws {
        let context = makeContext()
        let data = sampleData()

        let recipe = data.makeRecipe(in: context)
        try context.save()

        #expect(recipe.id != nil)
        #expect(RecipeExportData(recipe: recipe) == data)
    }

    @Test("Importing a backup file adds its recipes as new ones, every time")
    func importAddsNewRecipes() throws {
        let context = makeContext()
        var second = sampleData()
        second.name = "Kuchen"
        let file = RecipeExportFile(recipes: [sampleData(), second])
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("RecipePersistenceTests-\(UUID().uuidString).json")
        try JSONEncoder().encode(file).write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }

        #expect(try RecipeImport.importRecipes(from: url, into: context) == 2)
        #expect(try RecipeImport.importRecipes(from: url, into: context) == 2)

        let recipes = try context.fetch(Recipe.fetchRequest())
        #expect(recipes.count == 4)
        #expect(recipes.filter { $0.name == "Landbrot" }.count == 2)
        #expect(Set(recipes.compactMap(\.id)).count == 4)
    }

    @Test("A backup file from a newer format version is refused")
    func importRefusesNewerFormat() throws {
        let context = makeContext()
        var file = RecipeExportFile(recipes: [sampleData()])
        file.formatVersion = RecipeExportFile.currentFormatVersion + 1
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("RecipePersistenceTests-\(UUID().uuidString).json")
        try JSONEncoder().encode(file).write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }

        #expect(throws: RecipeImportError.self) {
            try RecipeImport.importRecipes(from: url, into: context)
        }
        #expect(try count(Recipe.self, in: context) == 0)
    }

    // MARK: - Adjusted copy

    @Test("An adjustment replaces name, weight and components and keeps the rest")
    func adjustmentReplacesComponents() throws {
        let context = makeContext()
        let original = sampleData()
        let recipe = original.makeRecipe(in: context)
        try context.save()

        var adjusted = original
        adjusted.name = "Landbrot – Dinkelmehl 630 (14.10.2026)"
        adjusted.totalWeight = 990
        adjusted.components = [
            RecipeExportComponent(name: "Teig", number: 1, ingredients: [
                RecipeExportIngredient(name: "Dinkelmehl 630", number: 1, unit: "g",
                                       weight: 600, normWeight: 600, num: 0, denom: 0),
                RecipeExportIngredient(name: "Wasser", number: 2, unit: "g",
                                       weight: 390, normWeight: 390, num: 0, denom: 0),
            ]),
        ]
        adjusted.update(recipe, in: context)
        try context.save()

        var expected = adjusted
        expected.summary = original.summary
        expected.instructions = original.instructions
        #expect(RecipeExportData(recipe: recipe) == expected)
        // The replaced components and their ingredients are gone.
        #expect(try count(Component.self, in: context) == 1)
        #expect(try count(Ingredient.self, in: context) == 2)
        #expect(try count(Instruction.self, in: context) == 3)
    }

    // MARK: - Fold steps

    private func instructionFB(_ text: String, minutes: Int, step: Double) -> InstructionFB {
        let instruction = InstructionFB()
        instruction.instruction = text
        instruction.duration = minutes
        instruction.step = step
        return instruction
    }

    /// Expands the same steps once as a plain array and once in a stored
    /// recipe; the stored recipe must end up with the array's steps.
    private func expectStoredExpansionMatchesArray(_ steps: [(text: String, minutes: Int, step: Double)]) throws {
        var array = steps.map { instructionFB($0.text, minutes: $0.minutes, step: $0.step) }
        let arrayChanged = TimedFoldExpansion.expand(&array)
        #expect(arrayChanged)

        let context = makeContext()
        var data = sampleData()
        data.instructions = steps.map {
            RecipeExportInstruction(instruction: $0.text, step: $0.step, duration: $0.minutes,
                                    startTime: 0, bakeFlag: false, componentName: nil)
        }
        let recipe = data.makeRecipe(in: context)
        try context.save()

        let storedChanged = TimedFoldExpansion.expand(in: recipe, context: context)
        #expect(storedChanged)
        try context.save()

        let stored = recipe.instructionsArray
        #expect(stored.map(\.step) == array.map(\.step))
        #expect(stored.map(\.instruction) == array.map(\.instruction))
        #expect(stored.map(\.duration) == array.map(\.duration))
        #expect(try count(Instruction.self, in: context) == array.count)

        // A second pass finds the folds already there and adds nothing.
        let changedAgain = TimedFoldExpansion.expand(in: recipe, context: context)
        #expect(!changedAgain)
        #expect(recipe.instructionsArray.count == array.count)
    }

    @Test("A rest that states its own folds gains one stored step per fold")
    func foldsInsideTheRest() throws {
        try expectStoredExpansionMatchesArray([
            ("3 Stunden bei 24 °C ruhen lassen. Dabei nach 30 und 60 Minuten dehnen und falten.", 0, 1),
        ])
    }

    @Test("A separate fold line becomes fold steps under the rest and is removed")
    func separateFoldLine() throws {
        try expectStoredExpansionMatchesArray([
            ("12 Stunden bei 20 °C reifen lassen.", 720, 1),
            ("Teig nach 30, 60 und 90 Minuten dehnen und falten.", 0, 2),
            ("Bei 250 °C backen", 50, 3),
        ])
    }

    // MARK: - Public recipe taken over

    private func publicRecipe(id: String, name: String, flour: Double) -> RecipeFB {
        let recipe = RecipeFB()
        recipe.id = id
        recipe.name = name
        recipe.summary = "Aus den öffentlichen Rezepten"
        recipe.urlLink = "https://example.com/brot"
        recipe.rating = 5
        recipe.tags = ["Weizen"]

        let component = ComponentFB()
        component.name = "Hauptteig"
        component.number = 1
        component.ingredients = [("Weizenmehl 550", flour), ("Wasser", 300.0)].enumerated().map { index, line in
            let ingredient = IngredientFB()
            ingredient.name = line.0
            ingredient.number = index + 1
            ingredient.unit = "g"
            ingredient.weight = line.1
            return ingredient
        }
        recipe.components = [component]

        recipe.instructions = [("Teig kneten", 15.0), ("Bei 250 °C backen", 50.0)].enumerated().map { index, line in
            let instruction = InstructionFB()
            instruction.instruction = line.0
            instruction.step = Double(index + 1)
            instruction.duration = Int(line.1)
            return instruction
        }
        return recipe
    }

    @Test("A public recipe becomes an own recipe with its content and Firestore id")
    func publicRecipeTakenOver() throws {
        let context = makeContext()

        let recipe = try RecipeModel().uploadRecipeIntoCoreData(
            recipeId: nil, recipeFB: publicRecipe(id: "fs-landbrot", name: "Weizenbrot", flour: 500),
            context: context, recipeImage: UIImage())

        #expect(recipe.id != nil)
        #expect(recipe.firestoreId == "fs-landbrot")
        #expect(recipe.name == "Weizenbrot")
        #expect(recipe.summary == "Aus den öffentlichen Rezepten")
        #expect(recipe.urlLink == "https://example.com/brot")
        #expect(recipe.rating == 5)
        #expect(recipe.tags == ["Weizen"])
        #expect(recipe.componentsArray.map(\.name) == ["Hauptteig"])
        #expect(recipe.componentsArray.first?.ingredientsArray.map(\.name) == ["Weizenmehl 550", "Wasser"])
        // Gram lines are taken as they are, and the total is their sum.
        #expect(recipe.componentsArray.first?.ingredientsArray.map(\.normWeight) == [500, 300])
        #expect(recipe.totalWeight == 800)
        #expect(recipe.instructionsArray.map(\.instruction) == ["Teig kneten", "Bei 250 °C backen"])
    }

    @Test("Taking over the same public recipe again leaves the own copy as it is")
    func publicRecipeTakenOverTwice() throws {
        let context = makeContext()
        let model = RecipeModel()

        let first = try model.uploadRecipeIntoCoreData(
            recipeId: nil, recipeFB: publicRecipe(id: "fs-landbrot", name: "Weizenbrot", flour: 500),
            context: context, recipeImage: UIImage())
        first.name = "Weizenbrot mit Dinkel"
        try context.save()

        let second = try model.uploadRecipeIntoCoreData(
            recipeId: nil, recipeFB: publicRecipe(id: "fs-landbrot", name: "Weizenbrot hell", flour: 600),
            context: context, recipeImage: UIImage())

        #expect(first.objectID == second.objectID)
        #expect(try count(Recipe.self, in: context) == 1)
        #expect(second.name == "Weizenbrot mit Dinkel")
        #expect(second.totalWeight == 800)
        #expect(second.componentsArray.first?.ingredientsArray.map(\.weight) == [500, 300])
        #expect(try count(Component.self, in: context) == 1)
        #expect(try count(Ingredient.self, in: context) == 2)
        #expect(try count(Instruction.self, in: context) == 2)
    }

    // MARK: - Bake history of a planned public recipe

    @Test("Planning a public recipe for the first time takes it over with one bake-history entry")
    func firstPlannedBakeTakesTheRecipeOver() throws {
        let context = makeContext()
        let bakeDate = Date(timeIntervalSince1970: 1_800_000_000)

        let recipe = try RecipeModel().recordPlannedBake(
            of: publicRecipe(id: "fs-landbrot", name: "Weizenbrot", flour: 500), on: bakeDate, context: context)

        #expect(recipe.firestoreId == "fs-landbrot")
        #expect(recipe.bakeHistoryFlag)
        #expect(recipe.bakeHistoriesArray.map(\.date) == [bakeDate])
        #expect(try count(Recipe.self, in: context) == 1)
    }

    @Test("Planning a public recipe again keeps the earlier entries and their notes")
    func plannedBakesKeepTheHistory() throws {
        let context = makeContext()
        let model = RecipeModel()
        let firstDate = Date(timeIntervalSince1970: 1_800_000_000)
        let secondDate = firstDate.addingTimeInterval(7 * 24 * 60 * 60)

        let recipe = try model.recordPlannedBake(
            of: publicRecipe(id: "fs-landbrot", name: "Weizenbrot", flour: 500), on: firstDate, context: context)
        let firstEntry = try #require(recipe.bakeHistoriesArray.first)
        firstEntry.comment = "Krume schön offen"
        try context.save()

        // A new session: the public recipe is loaded afresh and knows nothing
        // of the earlier plan.
        let again = try model.recordPlannedBake(
            of: publicRecipe(id: "fs-landbrot", name: "Weizenbrot", flour: 500), on: secondDate, context: context)

        #expect(again.objectID == recipe.objectID)
        #expect(try count(BakeHistory.self, in: context) == 2)
        #expect(Set(again.bakeHistoriesArray.map(\.date)) == [firstDate, secondDate])
        #expect(again.bakeHistoriesArray.contains { $0.comment == "Krume schön offen" })
    }

    /// A public starter refreshed 1:5:5 — mixed and left to ripen, no oven.
    private func publicStarter() -> RecipeFB {
        let recipe = RecipeFB()
        recipe.id = "fs-roggensauer"
        recipe.name = "Roggensauer"
        let component = ComponentFB()
        component.name = "Roggensauer"
        component.number = 1
        component.ingredients = [("Anstellgut", 20.0), ("Roggenmehl 1150", 100.0), ("Wasser", 100.0)]
            .enumerated().map { index, line in
                let ingredient = IngredientFB()
                ingredient.name = line.0
                ingredient.number = index + 1
                ingredient.unit = "g"
                ingredient.weight = line.1
                return ingredient
            }
        recipe.components = [component]
        recipe.instructions = [("Zutaten mischen", 5.0), ("Bei 26 °C 12 Stunden reifen lassen", 720.0)]
            .enumerated().map { index, line in
                let instruction = InstructionFB()
                instruction.instruction = line.0
                instruction.step = Double(index + 1)
                instruction.duration = Int(line.1)
                return instruction
            }
        return recipe
    }

    @Test("Planning a public starter takes it over without a bake-history entry: a starter is fed, not baked")
    func plannedStarterHasNoBakeHistory() throws {
        let context = makeContext()
        let recipe = try RecipeModel().recordPlannedBake(
            of: publicStarter(), on: Date(timeIntervalSince1970: 1_800_000_000), context: context)

        #expect(StarterRecipe.isStarterFeeding(recipe))
        #expect(recipe.firestoreId == "fs-roggensauer")
        #expect(recipe.bakeHistoriesArray.isEmpty)
        #expect(!recipe.bakeHistoryFlag)
        #expect(try count(BakeHistory.self, in: context) == 0)
    }
}
