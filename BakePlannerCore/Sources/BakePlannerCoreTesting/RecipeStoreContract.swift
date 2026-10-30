//
//  RecipeStoreContract.swift
//  BakePlannerCoreTesting
//
//  What every RecipeStore must do, written once and checked against each
//  store: in memory, Core Data, SQLite. Each check takes a new, empty store
//  and throws ContractViolation when the store behaves differently.
//

import BakePlannerCore
import Foundation

public struct ContractViolation: Error, CustomStringConvertible {
    public let description: String
}

public enum RecipeStoreContract {

    /// Every check by name, for running them one by one.
    public static let checks: [(name: String, run: (RecipeStore) throws -> Void)] = [
        ("an empty store has nothing", emptyStore),
        ("a recipe comes back as it was added", addAndRead),
        ("lists are ordered by name and leave pictures out unless asked", listsByName),
        ("content comes back in number and step order", contentOrder),
        ("an update changes everything but the picture", update),
        ("the picture is replaced and removed on its own", image),
        ("a removed recipe is gone, the others stay", delete),
        ("adding the same content twice keeps two recipes", noMerging),
        ("unknown keys are reported, not ignored", unknownKeys),
    ]

    // MARK: Checks

    public static func emptyStore(_ store: RecipeStore) throws {
        try expect(store.recipes(includingImages: true).isEmpty, "an empty store lists recipes")
        try expect(store.recipe(id: "none") == nil, "an empty store finds a recipe by key")
        try expect(store.recipe(firestoreId: "none") == nil, "an empty store finds a recipe by public id")
    }

    public static func addAndRead(_ store: RecipeStore) throws {
        let adjusted = Date(timeIntervalSince1970: 1_800_000_000)
        let added = try store.add(bread(), firestoreId: "public-1", adjustedOn: adjusted, bakeHistoryFlag: true)

        try expect(!added.id.isEmpty, "the new recipe has no key")
        try expect(added.content == bread(), "add returns other content than it was given")
        try expect(added.firestoreId == "public-1" && added.adjustedOn == adjusted && added.bakeHistoryFlag,
                   "add returns other details than it was given")
        try expect(store.recipe(id: added.id) == added, "the recipe read by key differs from the one added")
        try expect(store.recipe(firestoreId: "public-1") == added, "the recipe read by public id differs")
        try expect(store.recipe(firestoreId: "public-2") == nil, "another public id finds the recipe")
    }

    public static func listsByName(_ store: RecipeStore) throws {
        var zopf = bread()
        zopf.name = "Zopf"
        var apfel = bread()
        apfel.name = "Äpfelbrot"
        _ = try store.add(zopf, firestoreId: nil, adjustedOn: nil, bakeHistoryFlag: false)
        _ = try store.add(bread(), firestoreId: nil, adjustedOn: nil, bakeHistoryFlag: false)
        _ = try store.add(apfel, firestoreId: nil, adjustedOn: nil, bakeHistoryFlag: false)

        let withImages = try store.recipes(includingImages: true)
        try expect(withImages.map(\.content.name) == ["Äpfelbrot", "Landbrot", "Zopf"],
                   "the list is not ordered by name: \(withImages.map(\.content.name))")
        try expect(withImages.allSatisfy { $0.content.image == bread().image }, "the list with pictures lacks them")
        let withoutImages = try store.recipes(includingImages: false)
        try expect(withoutImages.allSatisfy { $0.content.image == nil }, "the list without pictures has them")
        try expect(withoutImages.map(\.id) == withImages.map(\.id), "the two lists hold different recipes")
    }

    public static func contentOrder(_ store: RecipeStore) throws {
        var shuffled = bread()
        shuffled.components.reverse()
        shuffled.components[0].ingredients.reverse()
        shuffled.instructions.reverse()
        let added = try store.add(shuffled, firestoreId: nil, adjustedOn: nil, bakeHistoryFlag: false)

        try expect(added.content == bread(), "add does not return the content in order")
        try expect(store.recipe(id: added.id)?.content == bread(), "the stored content is not in order")
    }

    public static func update(_ store: RecipeStore) throws {
        let added = try store.add(bread(), firestoreId: nil, adjustedOn: nil, bakeHistoryFlag: false)

        var changed = added
        changed.content.name = "Landbrot – Dinkelmehl 630 (14.10.2026)"
        changed.content.summary = ""
        changed.content.urlLink = nil
        changed.content.tags = []
        changed.content.rating = 5
        changed.content.components[1].ingredients.removeLast()
        changed.content.components[0].ingredients[0].name = "Dinkelmehl 630"
        changed.content.instructions.append(RecipeExportInstruction(
            instruction: "Abkühlen lassen", step: 4, duration: 60, startTime: 950, bakeFlag: false, componentName: nil))
        changed.content.image = nil
        changed.firestoreId = "public-9"
        changed.adjustedOn = Date(timeIntervalSince1970: 1_800_000_000)
        changed.bakeHistoryFlag = true
        try store.update(changed)

        var expected = changed
        expected.content.image = bread().image
        try expect(store.recipe(id: added.id) == expected, "the updated recipe differs from the update")
        try expect(store.recipes(includingImages: false).count == 1, "the update added a recipe")
    }

    public static func image(_ store: RecipeStore) throws {
        let added = try store.add(bread(), firestoreId: nil, adjustedOn: nil, bakeHistoryFlag: false)
        let picture = Data([0x0A, 0x0B, 0x0C])

        try store.setImage(picture, forRecipe: added.id)
        try expect(store.recipe(id: added.id)?.content.image == picture, "the new picture was not kept")
        var unchanged = added
        unchanged.content.image = picture
        try expect(store.recipe(id: added.id) == unchanged, "setting the picture changed more than the picture")

        try store.setImage(nil, forRecipe: added.id)
        try expect(store.recipe(id: added.id)?.content.image == nil, "the picture was not removed")
    }

    public static func delete(_ store: RecipeStore) throws {
        let first = try store.add(bread(), firestoreId: "public-1", adjustedOn: nil, bakeHistoryFlag: false)
        let second = try store.add(bread(), firestoreId: nil, adjustedOn: nil, bakeHistoryFlag: false)

        try store.delete(id: first.id)
        try expect(store.recipe(id: first.id) == nil, "the removed recipe is still there")
        try expect(store.recipe(firestoreId: "public-1") == nil, "the removed recipe is found by public id")
        try expect(store.recipes(includingImages: false).map(\.id) == [second.id], "the other recipe went too")
        try store.delete(id: first.id)
    }

    public static func noMerging(_ store: RecipeStore) throws {
        let first = try store.add(bread(), firestoreId: nil, adjustedOn: nil, bakeHistoryFlag: false)
        let second = try store.add(bread(), firestoreId: nil, adjustedOn: nil, bakeHistoryFlag: false)
        try expect(first.id != second.id, "two recipes share a key")
        try expect(store.recipes(includingImages: false).count == 2, "the same content was kept once")
    }

    public static func unknownKeys(_ store: RecipeStore) throws {
        let ghost = StoredRecipe(id: "none", content: bread())
        do {
            try store.update(ghost)
            throw ContractViolation(description: "updating an unknown recipe did not fail")
        } catch RecipeStoreError.unknownRecipe {}
        do {
            try store.setImage(Data([1]), forRecipe: "none")
            throw ContractViolation(description: "setting the picture of an unknown recipe did not fail")
        } catch RecipeStoreError.unknownRecipe {}
        try expect(store.recipes(includingImages: false).isEmpty, "an unknown key created a recipe")
    }

    // MARK: Helpers

    private static func expect(_ condition: Bool, _ message: @autoclosure () -> String) throws {
        if !condition { throw ContractViolation(description: message()) }
    }

    /// A bread with everything a recipe can carry: two components, a step
    /// naming its component, a whole-product row, a fraction, optional
    /// fields both set and empty, a picture, text beyond ASCII.
    public static func bread() -> RecipeExportData {
        RecipeExportData(
            name: "Landbrot", summary: "Kräftig, mit „Roggen“ – 2 Laibe", urlLink: "https://example.com/landbrot",
            prepTime: 950, totalWeight: 1_010.5, tags: ["Roggen", "Sauerteig"], rating: 4,
            recurrenceIntervalDays: 7, image: Data([0x01, 0x02, 0x03]),
            components: [
                RecipeExportComponent(name: "Sauerteig", number: 1, ingredients: [
                    RecipeExportIngredient(name: "Roggenmehl 1150", number: 1, unit: "g", weight: 200, normWeight: 200, num: 0, denom: 0),
                    RecipeExportIngredient(name: "Wasser", number: 2, unit: "g", weight: 200, normWeight: 200, num: 0, denom: 0),
                    RecipeExportIngredient(name: "Anstellgut", number: 3, unit: "g", weight: 20, normWeight: 20, num: 0, denom: 0),
                ]),
                RecipeExportComponent(name: "Hauptteig", number: 2, ingredients: [
                    RecipeExportIngredient(name: "gesamter Sauerteig", number: 1, unit: nil, weight: 0, normWeight: 0, num: 1, denom: 1),
                    RecipeExportIngredient(name: "Weizenmehl 550", number: 2, unit: "g", weight: 400, normWeight: 400, num: 0, denom: 0),
                    RecipeExportIngredient(name: "Hefe", number: 3, unit: "Würfel", weight: 0, normWeight: 10.5, num: 1, denom: 4),
                ]),
            ],
            instructions: [
                RecipeExportInstruction(instruction: "Sauerteig ansetzen und reifen lassen", step: 1, duration: 720,
                                        startTime: 0, bakeFlag: false, componentName: nil),
                RecipeExportInstruction(instruction: "Alle Zutaten kneten", step: 2, duration: 15,
                                        startTime: 720, bakeFlag: false, componentName: "Hauptteig"),
                RecipeExportInstruction(instruction: "Falten", step: 2.1, duration: 0,
                                        startTime: 735, bakeFlag: false, componentName: nil),
                RecipeExportInstruction(instruction: "Bei 250 °C 50 Minuten backen", step: 3, duration: 50,
                                        startTime: 900, bakeFlag: true, componentName: nil),
            ])
    }
}
