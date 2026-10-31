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
    /// The recipes, by name, without their pictures.
    var recipes: [StoredRecipe] = []
    /// Why the recipes could not be read, if they could not.
    var loadError: String?
    /// What the last import did, until the user has seen it.
    var importOutcome: ImportOutcome?

    enum ImportOutcome: Equatable {
        case imported(Int)
        case failed(String)
    }

    private var store: SQLiteRecipeStore?

    func load() {
        do {
            recipes = try openedStore().recipes(includingImages: false)
            loadError = nil
        } catch {
            logger.error("could not read the recipes: \(error)")
            loadError = "\(error)"
        }
    }

    /// One recipe with its picture, read afresh.
    func recipe(id: String) -> StoredRecipe? {
        do {
            return try openedStore().recipe(id: id)
        } catch {
            logger.error("could not read recipe \(id): \(error)")
            return nil
        }
    }

    /// Reads a backup or recipe file — as the iPhone app writes it — into
    /// the database, every recipe as a new one.
    func importFile(at url: URL) {
        #if !os(Android)
        // On iOS the picked file is only readable while its access lasts;
        // on Android the picker hands over a copy in the app's cache.
        let accessing = url.startAccessingSecurityScopedResource()
        defer { if accessing { url.stopAccessingSecurityScopedResource() } }
        #endif
        do {
            let data = try Data(contentsOf: url)
            let count = try RecipeImport.importFile(data, into: openedStore())
            importOutcome = .imported(count)
        } catch {
            logger.error("could not import \(url.lastPathComponent): \(error)")
            importOutcome = .failed(error.localizedDescription)
        }
        load()
    }

    private func openedStore() throws -> SQLiteRecipeStore {
        if let store { return store }
        let folder = URL.applicationSupportDirectory
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let opened = try SQLiteRecipeStore(path: folder.appendingPathComponent("recipes.sqlite").path)
        store = opened
        return opened
    }
}
