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

extension RecipeImport {
    /// Reads the recipe file `data` into `store`, every recipe as a new one,
    /// and the bake history it carries into `bakeHistory`, attached to the
    /// new recipes. Returns how many recipes were read. Nothing is kept
    /// when the file cannot be read or was written by a newer version.
    public static func importFile(_ data: Data, into store: RecipeStore,
                                  bakeHistory: BakeHistoryStore) throws -> Int {
        let file = try decodeFile(data)
        let added = try store.add(contentsOf: file.recipes.map { recipe in
            var recipe = recipe
            recipe.bakeHistory = nil
            return recipe
        })
        for (recipe, content) in zip(added, file.recipes) {
            // Oldest first, so a store that keeps the order of adding has
            // them as the device they came from did.
            for entry in (content.bakeHistory ?? []).reversed() {
                _ = try bakeHistory.add(toRecipe: recipe.id, date: entry.date, comment: entry.comment,
                                        images: entry.images, facts: entry.facts)
            }
        }
        return added.count
    }
}

extension RecipeExportFile {
    /// The recipes `ids` of `store` as a file, in that order, pictures
    /// included, without bake history — what is shared with someone else.
    /// Keys the store no longer has are left out.
    public init(recipeIDs ids: [String], from store: RecipeStore) throws {
        self.init(recipes: try ids.compactMap { try store.recipe(id: $0)?.content })
    }

    /// The full backup: the recipes `ids` of `store` with their bake
    /// history from `bakeHistory`, photos passed through `shrinkPhoto`
    /// (each app makes them as small as still looks good on its largest
    /// screen). Format version 2 when any recipe has been baked.
    public init(recipeIDs ids: [String], from store: RecipeStore, bakeHistory: BakeHistoryStore,
                shrinkPhoto: (Data) -> Data = { $0 }) throws {
        var recipes: [RecipeExportData] = []
        for id in ids {
            guard var content = try store.recipe(id: id)?.content else { continue }
            let entries = try bakeHistory.entries(ofRecipe: id, includingImages: true)
            if !entries.isEmpty {
                content.bakeHistory = entries.map { entry in
                    RecipeExportBakeEntry(date: entry.date, comment: entry.comment,
                                          images: entry.images.map(shrinkPhoto), facts: entry.facts)
                }
            }
            recipes.append(content)
        }
        self.init(recipes: recipes)
    }
}
