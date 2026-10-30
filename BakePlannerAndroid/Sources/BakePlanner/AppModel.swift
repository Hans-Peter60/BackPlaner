import BakePlannerCore
import BakePlannerStorage
import Foundation
import Observation
import SkipFuse

/// What the app shows, and where it keeps the user's recipes: a SQLite
/// database in the app's own storage.
@MainActor
@Observable
final class AppModel {
    /// How many recipes the database holds.
    var recipeCount = 0
    /// Why the recipes could not be read, if they could not.
    var loadError: String?

    private var store: SQLiteRecipeStore?

    func load() {
        do {
            let store = try self.store ?? Self.openStore()
            self.store = store
            recipeCount = try store.recipes(includingImages: false).count
            loadError = nil
        } catch {
            logger.error("could not read the recipes: \(error)")
            loadError = "\(error)"
        }
    }

    private static func openStore() throws -> SQLiteRecipeStore {
        let folder = URL.applicationSupportDirectory
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return try SQLiteRecipeStore(path: folder.appendingPathComponent("recipes.sqlite").path)
    }
}
