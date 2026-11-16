//
//  RecipeBackup.swift
//  BakePlannerCore
//
//  Reading a backup or shared recipe file into a RecipeStore, and writing
//  recipes of a store into one — the way recipes move between devices and
//  between iOS and Android. Where the file comes from or goes to (share
//  sheet, file picker) is the app's business.
//

import Foundation

/// What an import brought in.
public struct RecipeImportResult: Equatable, Sendable {
    public var recipes: Int
    /// Pantry items added; those the pantry already had by name are not counted.
    public var pantryItems: Int
    /// Bakes and feedings added to recipes the store already had — a
    /// restore merging into what is there.
    public var bakeEntries: Int

    public init(recipes: Int, pantryItems: Int = 0, bakeEntries: Int = 0) {
        self.recipes = recipes
        self.bakeEntries = bakeEntries
        self.pantryItems = pantryItems
    }
}

extension RecipeImport {
    /// Reads the recipe file `data` into `store`, every recipe as a new one,
    /// and the bake history and feedings it carries into `bakeHistory` and
    /// `starterFeedings`, attached to the new recipes. Returns how many
    /// recipes were read. Nothing is kept when the file cannot be read or
    /// was written by a newer version. The pantry of the file is left out;
    /// an app with a pantry calls the variant below.
    public static func importFile(_ data: Data, into store: RecipeStore, bakeHistory: BakeHistoryStore,
                                  starterFeedings: StarterFeedingLogStore) throws -> Int {
        try importFile(data, into: store, bakeHistory: bakeHistory, starterFeedings: starterFeedings, pantry: nil).recipes
    }

    /// As above, and the pantry of the file into `pantry`: an item whose
    /// name the pantry already has is left alone — reading the same backup
    /// twice must not double the stock — the others are added as they were.
    public static func importFile(_ data: Data, into store: RecipeStore, bakeHistory: BakeHistoryStore,
                                  starterFeedings: StarterFeedingLogStore, pantry: PantryStore?) throws -> RecipeImportResult {
        let file = try decodeFile(data)
        let pantryItems = try addPantry(file, to: pantry)
        let added = try addRecipes(file.recipes, into: store, bakeHistory: bakeHistory, starterFeedings: starterFeedings)
        return RecipeImportResult(recipes: added.count, pantryItems: pantryItems)
    }

    /// Reads a full backup back onto a device that may already have part
    /// of it: a recipe whose name the store already has is not added again;
    /// instead the bakes and feedings the file carries for it and the store
    /// lacks (by their date) are attached to the existing recipe. Recipes
    /// the store does not know come in as `importFile` adds them, the
    /// pantry as there. The result counts the recipes added and, in
    /// `bakeEntries`, the bakes and feedings merged into existing recipes.
    public static func restoreBackup(_ data: Data, into store: RecipeStore, bakeHistory: BakeHistoryStore,
                                     starterFeedings: StarterFeedingLogStore, pantry: PantryStore?) throws -> RecipeImportResult {
        let file = try decodeFile(data)
        let pantryItems = try addPantry(file, to: pantry)

        let existing = try store.recipes(includingImages: false)
        var byName: [String: StoredRecipe] = [:]
        for recipe in existing {
            byName[IngredientNameNormalizer.foldedName(recipe.content.name)] = recipe
        }
        var newContents: [RecipeExportData] = []
        var merged = 0
        for content in file.recipes {
            guard let known = byName[IngredientNameNormalizer.foldedName(content.name)] else {
                newContents.append(content)
                continue
            }
            let haveBakes = Set(try bakeHistory.entries(ofRecipe: known.id, includingImages: false).map { Self.second($0.date) })
            for entry in (content.bakeHistory ?? []).reversed() where !haveBakes.contains(Self.second(entry.date)) {
                _ = try bakeHistory.add(toRecipe: known.id, date: entry.date, comment: entry.comment,
                                        images: entry.images, facts: entry.facts)
                merged += 1
            }
            let haveFeedings = Set(try starterFeedings.feedings(ofRecipe: known.id).map { Self.second($0.date) })
            for feeding in (content.starterFeedings ?? []).reversed() where !haveFeedings.contains(Self.second(feeding.date)) {
                _ = try starterFeedings.add(toRecipe: known.id, date: feeding.date, facts: feeding.facts)
                merged += 1
            }
        }
        let added = try addRecipes(newContents, into: store, bakeHistory: bakeHistory, starterFeedings: starterFeedings)
        return RecipeImportResult(recipes: added.count, pantryItems: pantryItems, bakeEntries: merged)
    }

    /// A date to the second: two stores may keep fractions differently.
    private static func second(_ date: Date) -> Int {
        Int(date.timeIntervalSinceReferenceDate.rounded())
    }

    /// The file's pantry onto `pantry`: items the pantry has by name stay.
    private static func addPantry(_ file: RecipeExportFile, to pantry: PantryStore?) throws -> Int {
        var pantryItems = 0
        if let pantry, let items = file.pantry {
            for item in items where try pantry.item(matching: item.name) == nil {
                _ = try pantry.add(name: item.name, amount: item.amount, unit: PantryUnit(stored: item.unit),
                                   bestBefore: item.bestBefore, note: item.note ?? "")
                pantryItems += 1
            }
        }
        return pantryItems
    }

    /// Every recipe in `contents` as a new one, with its bakes and feedings.
    private static func addRecipes(_ contents: [RecipeExportData], into store: RecipeStore,
                                   bakeHistory: BakeHistoryStore, starterFeedings: StarterFeedingLogStore) throws -> [StoredRecipe] {
        guard !contents.isEmpty else { return [] }
        let added = try store.add(contentsOf: contents.map { recipe in
            var recipe = recipe
            recipe.bakeHistory = nil
            recipe.starterFeedings = nil
            recipe.variantOf = nil
            recipe.variantNote = nil
            return recipe
        })
        try linkVariants(added, from: contents, in: store)
        for (recipe, content) in zip(added, contents) {
            // Oldest first, so a store that keeps the order of adding has
            // them as the device they came from did.
            for entry in (content.bakeHistory ?? []).reversed() {
                _ = try bakeHistory.add(toRecipe: recipe.id, date: entry.date, comment: entry.comment,
                                        images: entry.images, facts: entry.facts)
            }
            for feeding in (content.starterFeedings ?? []).reversed() {
                _ = try starterFeedings.add(toRecipe: recipe.id, date: feeding.date, facts: feeding.facts)
            }
        }
        return added
    }

    /// Links each variant in the file to its origin: the recipe of that
    /// name read from the same file, else one already in the store. A
    /// variant whose origin is nowhere becomes a recipe of its own, note
    /// kept.
    private static func linkVariants(_ added: [StoredRecipe], from contents: [RecipeExportData],
                                     in store: RecipeStore) throws {
        guard contents.contains(where: { $0.variantOf != nil || $0.variantNote != nil }) else { return }
        let existing = try store.recipes(includingImages: false)
        for (recipe, content) in zip(added, contents) where content.variantOf != nil || content.variantNote != nil {
            var variant = recipe
            if let originName = content.variantOf {
                let fromFile = zip(added, contents).first { $0.0.id != recipe.id && $0.1.name == originName }?.0
                let addedIDs = Set(added.map(\.id))
                let fromStore = existing.first { !addedIDs.contains($0.id) && $0.content.name == originName }
                variant.originID = (fromFile ?? fromStore)?.id
            }
            variant.variantNote = content.variantNote
            try store.update(variant)
        }
    }
}

extension RecipeExportFile {
    /// The recipes `ids` of `store` as a file, in that order, pictures
    /// included, without bake history — what is shared with someone else.
    /// Keys the store no longer has are left out.
    public init(recipeIDs ids: [String], from store: RecipeStore) throws {
        // Without origin and note either: a shared recipe stands on its own,
        // and the file stays at version 1 for older apps.
        self.init(recipes: try ids.compactMap { try store.recipe(id: $0)?.content })
    }

    /// The full backup: the recipes `ids` of `store` with their bake
    /// history from `bakeHistory`, photos passed through `shrinkPhoto`
    /// (each app makes them as small as still looks good on its largest
    /// screen), their feedings from `starterFeedings`, and — when a
    /// `pantry` is given — what is in the house. Format version 2 when any
    /// recipe has been baked or fed, 7 with a pantry.
    public init(recipeIDs ids: [String], from store: RecipeStore, bakeHistory: BakeHistoryStore,
                starterFeedings: StarterFeedingLogStore, pantry: PantryStore? = nil,
                shrinkPhoto: (Data) -> Data = { $0 }) throws {
        var recipes: [RecipeExportData] = []
        for id in ids {
            guard let recipe = try store.recipe(id: id) else { continue }
            var content = recipe.content
            // The origin by name: keys mean nothing on another device.
            if let originID = recipe.originID, let origin = try store.recipe(id: originID) {
                content.variantOf = origin.content.name
            }
            content.variantNote = recipe.variantNote
            let entries = try bakeHistory.entries(ofRecipe: id, includingImages: true)
            if !entries.isEmpty {
                content.bakeHistory = entries.map { entry in
                    RecipeExportBakeEntry(date: entry.date, comment: entry.comment,
                                          images: entry.images.map(shrinkPhoto), facts: entry.facts)
                }
            }
            let feedings = try starterFeedings.feedings(ofRecipe: id)
            if !feedings.isEmpty {
                content.starterFeedings = feedings.map { RecipeExportStarterFeeding(date: $0.date, facts: $0.facts) }
            }
            recipes.append(content)
        }
        self.init(recipes: recipes, pantry: try pantry?.items().map(RecipeExportPantryItem.init))
    }
}
