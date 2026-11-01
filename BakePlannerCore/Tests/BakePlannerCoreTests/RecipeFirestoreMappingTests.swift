//
//  RecipeFirestoreMappingTests.swift
//  BakePlannerCoreTests
//
//  The Firestore layout of a public recipe: documents read into RecipeFB,
//  written back, and turned into the data the recipe views take.
//

import Foundation
import Testing
@testable import BakePlannerCore

@Suite("Public recipes in Firestore")
struct RecipeFirestoreMappingTests {

    @Test("A recipe document is read with its translations")
    func readsRecipe() {
        let recipe = RecipeFirestoreMapping.recipe(id: "r1", data: [
            "name": "Roggenbrot",
            "summary": "Kräftig",
            "urlLink": "https://example.com",
            "image": "uid/abc",
            "prepTime": 1440,
            "totalWeight": 1250.5,
            "tags": ["Roggen", "Sauerteig"],
            "authorId": "uid",
            "sourceLanguage": "de",
            "hidden": false,
            "translations": [
                "de": ["name": "Roggenbrot", "summary": "Kräftig"] as [String: Any],
                "en": ["name": "Rye bread", "summary": "Hearty", "tags": ["Rye"]] as [String: Any]
            ] as [String: Any]
        ])
        #expect(recipe.id == "r1")
        #expect(recipe.name == "Roggenbrot")
        #expect(recipe.summary == "Kräftig")
        #expect(recipe.urlLink == "https://example.com")
        #expect(recipe.image == "uid/abc")
        #expect(recipe.prepTime == 1440)
        #expect(recipe.totalWeight == 1250.5)
        #expect(recipe.tags == ["Roggen", "Sauerteig"])
        #expect(recipe.authorId == "uid")
        #expect(recipe.sourceLanguage == "de")
        #expect(recipe.hidden == false)
        #expect(recipe.translations["en"]?.name == "Rye bread")
        #expect(recipe.translations["en"]?.tags == ["Rye"])

        recipe.applyLocalization(languageCode: "en")
        #expect(recipe.name == "Rye bread")
    }

    @Test("Missing fields fall back to empty values, a reported recipe is hidden")
    func readsSparseRecipe() {
        let recipe = RecipeFirestoreMapping.recipe(id: "r2", data: ["hidden": true])
        #expect(recipe.name == "")
        #expect(recipe.prepTime == 0)
        #expect(recipe.totalWeight == 0)
        #expect(recipe.tags.isEmpty)
        #expect(recipe.authorId == "")
        #expect(recipe.translations.isEmpty)
        #expect(recipe.hidden)
        #expect(RecipeFirestoreMapping.recipe(id: "r3", data: [:]).hidden == false)
    }

    @Test("Components, ingredients and instructions are read")
    func readsChildren() {
        let component = RecipeFirestoreMapping.component(id: "c1", data: [
            "name": "Sauerteig", "number": 1,
            "translations": ["en": ["name": "Sourdough"]]
        ])
        #expect(component.id == "c1")
        #expect(component.name == "Sauerteig")
        #expect(component.number == 1)
        #expect(component.translations["en"]?.name == "Sourdough")

        let ingredient = RecipeFirestoreMapping.ingredient(id: "i1", data: [
            "name": "Ei", "number": 2, "unit": "Stück", "weight": 2.0, "normWeight": 110.0,
            "num": 0, "denom": 0,
            "translations": ["en": ["name": "Egg", "unit": "piece"]]
        ])
        #expect(ingredient.id == "i1")
        #expect(ingredient.name == "Ei")
        #expect(ingredient.number == 2)
        #expect(ingredient.unit == "Stück")
        #expect(ingredient.weight == 2)
        #expect(ingredient.normWeight == 110)
        #expect(ingredient.translations["en"]?.unit == "piece")

        let instruction = RecipeFirestoreMapping.instruction(id: "s1", data: [
            "instruction": "Kneten", "step": 2.5, "duration": 10, "startTime": 30,
            "componentName": "Hauptteig"
        ])
        #expect(instruction.id == "s1")
        #expect(instruction.instruction == "Kneten")
        #expect(instruction.step == 2.5)
        #expect(instruction.duration == 10)
        #expect(instruction.startTime == 30)
        #expect(instruction.componentName == "Hauptteig")
    }

    @Test("Old documents: no normalised weight, no step, no component name")
    func readsOldChildren() {
        let ingredient = RecipeFirestoreMapping.ingredient(id: "i", data: ["name": "Mehl", "weight": 500.0])
        #expect(ingredient.normWeight == 500)
        let instruction = RecipeFirestoreMapping.instruction(id: "s", data: ["instruction": "Backen"])
        #expect(instruction.step == 1)
        #expect(instruction.startTime == 0)
        #expect(instruction.componentName == nil)
    }

    @Test("Numbers come as Int, Int64 or Double, as the Android SDK hands them out")
    func readsNumbersOfAnyKind() {
        #expect(RecipeFirestoreMapping.int(Int64(42)) == 42)
        #expect(RecipeFirestoreMapping.int(42.0) == 42)
        #expect(RecipeFirestoreMapping.int(42.5) == nil)
        #expect(RecipeFirestoreMapping.int("42") == nil)
        #expect(RecipeFirestoreMapping.int(nil) == nil)
        #expect(RecipeFirestoreMapping.double(Int64(500)) == 500)
        #expect(RecipeFirestoreMapping.double(500) == 500)
        #expect(RecipeFirestoreMapping.double(Float(0.5)) == 0.5)
        #expect(RecipeFirestoreMapping.double("500") == nil)

        let ingredient = RecipeFirestoreMapping.ingredient(id: "i", data: [
            "number": Int64(3), "weight": Int64(500), "num": Int64(1), "denom": Int64(2)
        ])
        #expect(ingredient.number == 3)
        #expect(ingredient.weight == 500)
        #expect(ingredient.normWeight == 500)
        #expect(ingredient.num == 1)
        #expect(ingredient.denom == 2)

        let instruction = RecipeFirestoreMapping.instruction(id: "s", data: ["step": Int64(3), "duration": Int64(20)])
        #expect(instruction.step == 3)
        #expect(instruction.duration == 20)
    }

    @Test("Written documents read back the same")
    func roundTrip() {
        let ingredient = IngredientFB()
        ingredient.name = "Wasser"; ingredient.number = 1; ingredient.unit = "g"
        ingredient.weight = 350; ingredient.normWeight = 350
        ingredient.translations = ["en": IngredientTextFB(name: "Water", unit: "g")]
        let readIngredient = RecipeFirestoreMapping.ingredient(
            id: "i", data: RecipeFirestoreMapping.ingredientData(of: ingredient))
        #expect(readIngredient.name == "Wasser")
        #expect(readIngredient.weight == 350)
        #expect(readIngredient.translations["en"]?.name == "Water")

        let component = ComponentFB()
        component.name = "Hauptteig"; component.number = 2
        let componentData = RecipeFirestoreMapping.componentData(of: component)
        #expect(componentData["translations"] == nil)
        #expect(RecipeFirestoreMapping.component(id: "c", data: componentData).number == 2)

        let instruction = InstructionFB()
        instruction.instruction = "Ruhen"; instruction.step = 3; instruction.duration = 60
        let instructionData = RecipeFirestoreMapping.instructionData(of: instruction)
        #expect(instructionData["componentName"] == nil)
        #expect(RecipeFirestoreMapping.int(instructionData["startTime"]) == 0)
        let readInstruction = RecipeFirestoreMapping.instruction(id: "s", data: instructionData)
        #expect(readInstruction.step == 3)
        #expect(readInstruction.duration == 60)
    }

    @Test("A new recipe is visible and carries its author; an edit leaves both alone")
    func recipeDocuments() {
        let recipe = RecipeFB()
        recipe.name = "Baguette"; recipe.totalWeight = 900; recipe.tags = ["Weizen"]
        recipe.sourceLanguage = "fr"
        let new = RecipeFirestoreMapping.newRecipeData(of: recipe, prepTime: 720, authorId: "uid")
        #expect(new["hidden"] as? Bool == false)
        #expect(new["authorId"] as? String == "uid")
        #expect(RecipeFirestoreMapping.int(new["prepTime"]) == 720)
        #expect(new["translations"] == nil)
        let read = RecipeFirestoreMapping.recipe(id: "r", data: new)
        #expect(read.name == "Baguette")
        #expect(read.totalWeight == 900)
        #expect(read.sourceLanguage == "fr")

        let edited = RecipeFirestoreMapping.editedRecipeData(of: recipe)
        #expect(edited["hidden"] == nil)
        #expect(edited["authorId"] == nil)
        #expect(edited["name"] as? String == "Baguette")
    }

    @Test("A public recipe becomes recipe data in display order")
    func exportData() {
        let recipe = RecipeFB()
        recipe.name = "Brot"; recipe.prepTime = 600; recipe.totalWeight = 1000; recipe.urlLink = ""

        let second = ComponentFB(); second.name = "Hauptteig"; second.number = 2
        let first = ComponentFB(); first.name = "Vorteig"; first.number = 1
        let salt = IngredientFB(); salt.name = "Salz"; salt.number = 2; salt.weight = 10; salt.normWeight = 10
        let flour = IngredientFB(); flour.name = "Mehl"; flour.number = 1; flour.unit = "g"
        flour.weight = 500; flour.normWeight = 500
        second.ingredients = [salt, flour]
        recipe.components = [second, first]

        let late = InstructionFB(); late.instruction = "Backen"; late.step = 2; late.duration = 45
        let early = InstructionFB(); early.instruction = "Kneten"; early.step = 1; early.startTime = 5
        recipe.instructions = [late, early]

        let data = RecipeExportData(recipeFB: recipe, imageData: Data([1, 2, 3]))
        #expect(data.name == "Brot")
        #expect(data.urlLink == nil)
        #expect(data.prepTime == 600)
        #expect(data.image == Data([1, 2, 3]))
        #expect(data.components.map(\.name) == ["Vorteig", "Hauptteig"])
        #expect(data.components[1].ingredients.map(\.name) == ["Mehl", "Salz"])
        #expect(data.components[1].ingredients[1].unit == nil)
        #expect(data.components[1].ingredients[0].unit == "g")
        #expect(data.instructions.map(\.instruction) == ["Kneten", "Backen"])
        #expect(data.instructions[0].startTime == 5)
        #expect(data.instructions[1].startTime == 0)
        #expect(data.instructions[1].bakeFlag == false)
    }
}
