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
    /// and returns how many were read. Nothing is kept when the file cannot
    /// be read or was written by a newer version.
    public static func importFile(_ data: Data, into store: RecipeStore) throws -> Int {
        let file = try decodeFile(data)
        return try store.add(contentsOf: file.recipes).count
    }
}

extension RecipeExportFile {
    /// The recipes `ids` of `store` as a file, in that order, pictures
    /// included. Keys the store no longer has are left out.
    public init(recipeIDs ids: [String], from store: RecipeStore) throws {
        self.init(recipes: try ids.compactMap { try store.recipe(id: $0)?.content })
    }
}
