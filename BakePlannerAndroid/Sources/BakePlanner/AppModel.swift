import BakePlannerCore
import BakePlannerStorage
import Foundation
import Observation
import SkipFuse

/// What the app shows, and where it keeps the user's recipes, shopping lists
/// and bake history: one SQLite database in the app's own storage.
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

    /// The shopping lists, oldest first.
    var shoppingLists: [StoredShoppingList] = []

    /// Where a recipe's ingredients go.
    enum ShoppingListTarget {
        /// The list of that day — a new one when the day has none yet, as
        /// on the iPhone.
        case newList(Date)
        case existingList(String)
    }

    enum ShoppingListOutcome: Equatable {
        case added
        /// The recipe has nothing that is bought (only water, salt, starter).
        case nothingToBuy
        case failed
    }

    /// The bake history of every recipe, newest first, without photos.
    var bakeHistory: [StoredBakeHistory] = []

    private var store: SQLiteRecipeStore?
    private var listStore: SQLiteShoppingListStore?
    private var historyStore: SQLiteBakeHistoryStore?
    private var feedingStore: SQLiteStarterFeedingLogStore?

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

    /// Keeps the changed recipe (everything but its picture) and refreshes
    /// the list. Whether it worked.
    @discardableResult
    func save(_ recipe: StoredRecipe) -> Bool {
        do {
            try openedStore().update(recipe)
            load()
            return true
        } catch {
            logger.error("could not save recipe \(recipe.id): \(error)")
            return false
        }
    }

    /// Keeps a new recipe and refreshes the list. Whether it worked.
    @discardableResult
    func add(_ content: RecipeExportData) -> Bool {
        do {
            _ = try openedStore().add(content, firestoreId: nil, adjustedOn: nil, bakeHistoryFlag: false)
            load()
            return true
        } catch {
            logger.error("could not add a recipe: \(error)")
            return false
        }
    }

    /// Gives the recipe a new picture, or none for `nil`. Whether it worked.
    @discardableResult
    func setImage(_ image: Data?, forRecipe id: String) -> Bool {
        do {
            try openedStore().setImage(image, forRecipe: id)
            return true
        } catch {
            logger.error("could not change the picture of recipe \(id): \(error)")
            return false
        }
    }

    /// Removes the recipe and refreshes the list. Its ingredients stay on
    /// the shopping lists; the recipe's name goes from them.
    func delete(id: String) {
        do {
            try openedStore().delete(id: id)
        } catch {
            logger.error("could not delete recipe \(id): \(error)")
        }
        load()
        loadShoppingLists()
        loadBakeHistory()
    }

    // MARK: Bake history

    func loadBakeHistory() {
        do {
            bakeHistory = try openedHistoryStore().entries(includingImages: false)
        } catch {
            logger.error("could not read the bake history: \(error)")
        }
    }

    /// One entry with its photos, read afresh.
    func bakeEntry(id: String) -> StoredBakeHistory? {
        do {
            return try openedHistoryStore().entry(id: id)
        } catch {
            logger.error("could not read bake history entry \(id): \(error)")
            return nil
        }
    }

    /// Keeps a new entry for the recipe, which then counts as baked. Whether
    /// it worked.
    @discardableResult
    func addBakeEntry(toRecipe recipeID: String, date: Date, comment: String, images: [Data],
                      facts: BakeHistoryFacts) -> Bool {
        do {
            _ = try openedHistoryStore().add(toRecipe: recipeID, date: date, comment: comment, images: images,
                                             facts: facts)
            loadBakeHistory()
            load()
            return true
        } catch {
            logger.error("could not add a bake history entry to recipe \(recipeID): \(error)")
            return false
        }
    }

    /// Keeps a changed entry. Whether it worked.
    @discardableResult
    func updateBakeEntry(_ entry: StoredBakeHistory) -> Bool {
        do {
            try openedHistoryStore().update(entry)
            loadBakeHistory()
            return true
        } catch {
            logger.error("could not change bake history entry \(entry.id): \(error)")
            return false
        }
    }

    func deleteBakeEntry(id: String) {
        do {
            try openedHistoryStore().delete(id: id)
        } catch {
            logger.error("could not delete bake history entry \(id): \(error)")
        }
        loadBakeHistory()
    }

    /// The recipe's name for an entry; empty when the list has not caught up.
    func recipeName(id: String) -> String {
        recipes.first { $0.id == id }?.content.name ?? ""
    }

    // MARK: Starter feeding diary

    /// The feedings of a starter's recipe, newest first.
    func feedings(ofRecipe recipeID: String) -> [StoredStarterFeeding] {
        do {
            return try openedFeedingStore().feedings(ofRecipe: recipeID)
        } catch {
            logger.error("could not read the feedings of recipe \(recipeID): \(error)")
            return []
        }
    }

    /// Keeps a new feeding. Whether it worked.
    @discardableResult
    func addFeeding(toRecipe recipeID: String, date: Date, facts: StarterFeedingFacts) -> Bool {
        do {
            _ = try openedFeedingStore().add(toRecipe: recipeID, date: date, facts: facts)
            return true
        } catch {
            logger.error("could not add a feeding to recipe \(recipeID): \(error)")
            return false
        }
    }

    func deleteFeeding(id: String) {
        do {
            try openedFeedingStore().delete(id: id)
        } catch {
            logger.error("could not delete feeding \(id): \(error)")
        }
    }

    // MARK: Shopping lists

    func loadShoppingLists() {
        do {
            shoppingLists = try openedListStore().lists()
        } catch {
            logger.error("could not read the shopping lists: \(error)")
        }
    }

    /// Puts the ingredients of recipe `recipeID`, at `scale` (1 is the
    /// recipe as stored), on a shopping list — sifted, converted and merged
    /// as on the iPhone (ShoppingListBuilder).
    func addToShoppingList(recipeID: String, scale: Double, target: ShoppingListTarget) -> ShoppingListOutcome {
        do {
            guard let recipe = try openedStore().recipe(id: recipeID) else { return .failed }
            let entries = ShoppingListBuilder.entriesToBuy(ShoppingListBuilder.entries(of: recipe.content), scale: scale)
            guard !entries.isEmpty else { return .nothingToBuy }

            let lists = try openedListStore()
            let listID: String
            switch target {
            case .newList(let date):
                listID = try lists.list(onSameDayAs: date)?.id ?? lists.addList(on: date).id
            case .existingList(let id):
                listID = id
            }
            try lists.add(entries, from: .own(id: recipeID), toList: listID)
            loadShoppingLists()
            return .added
        } catch {
            logger.error("could not put recipe \(recipeID) on a shopping list: \(error)")
            loadShoppingLists()
            return .failed
        }
    }

    /// Keeps a changed line of a shopping list.
    func update(_ item: StoredShoppingListItem) {
        do {
            try openedListStore().update(item)
        } catch {
            logger.error("could not change shopping list line \(item.id): \(error)")
        }
        loadShoppingLists()
    }

    /// Takes one line off its shopping list.
    func deleteShoppingListItem(id: String) {
        do {
            try openedListStore().deleteItem(id: id)
        } catch {
            logger.error("could not remove shopping list line \(id): \(error)")
        }
        loadShoppingLists()
    }

    /// Removes a shopping list with its lines; the recipes stay.
    func deleteShoppingList(id: String) {
        do {
            try openedListStore().delete(id: id)
        } catch {
            logger.error("could not delete shopping list \(id): \(error)")
        }
        loadShoppingLists()
    }

    /// Writes the recipes `ids` into a backup file, as the iPhone app reads
    /// it, and returns where it lies — in the app's cache, ready to be
    /// handed to the system's "save as". The full backup carries the bake
    /// history and the feeding diary along; a single recipe saved to pass
    /// on does not.
    func exportFile(recipeIDs ids: [String], named name: String, includingBakeHistory: Bool) -> URL? {
        do {
            let file: RecipeExportFile
            if includingBakeHistory {
                file = try RecipeExportFile(recipeIDs: ids, from: openedStore(), bakeHistory: openedHistoryStore(),
                                            starterFeedings: openedFeedingStore())
            } else {
                file = try RecipeExportFile(recipeIDs: ids, from: openedStore())
            }
            let folder = URL.cachesDirectory.appendingPathComponent("Export", isDirectory: true)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let safeName = name.components(separatedBy: CharacterSet(charactersIn: "/\\:?*\"<>|")).joined(separator: "-")
            let url = folder.appendingPathComponent(safeName.isEmpty ? "Rezept" : safeName).appendingPathExtension("json")
            try file.encoded().write(to: url, options: .atomic)
            return url
        } catch {
            logger.error("could not write a backup file: \(error)")
            return nil
        }
    }

    /// "BakePlanner-Rezepte-2026-10-31", as the iPhone app names its backups.
    static var backupFileName: String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return "BakePlanner-Rezepte-\(formatter.string(from: Date()))"
    }

    /// Reads a backup or recipe file — as the iPhone app writes it — into
    /// the database, every recipe as a new one, with the bake history the
    /// file carries.
    func importFile(at url: URL) {
        #if !os(Android)
        // On iOS the picked file is only readable while its access lasts;
        // on Android the picker hands over a copy in the app's cache.
        let accessing = url.startAccessingSecurityScopedResource()
        defer { if accessing { url.stopAccessingSecurityScopedResource() } }
        #endif
        do {
            let data = try Data(contentsOf: url)
            let count = try RecipeImport.importFile(data, into: openedStore(), bakeHistory: openedHistoryStore(),
                                                    starterFeedings: openedFeedingStore())
            importOutcome = .imported(count)
        } catch {
            logger.error("could not import \(url.lastPathComponent): \(error)")
            importOutcome = .failed(error.localizedDescription)
        }
        load()
        loadBakeHistory()
    }

    private func openedStore() throws -> SQLiteRecipeStore {
        if let store { return store }
        let folder = URL.applicationSupportDirectory
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let opened = try SQLiteRecipeStore(path: folder.appendingPathComponent("recipes.sqlite").path)
        store = opened
        return opened
    }

    /// The starter feeding diary, in the same database file as the recipes.
    private func openedFeedingStore() throws -> SQLiteStarterFeedingLogStore {
        if let feedingStore { return feedingStore }
        let opened = SQLiteStarterFeedingLogStore(file: try openedStore().file)
        feedingStore = opened
        return opened
    }

    /// The bake history, in the same database file as the recipes.
    private func openedHistoryStore() throws -> SQLiteBakeHistoryStore {
        if let historyStore { return historyStore }
        let opened = SQLiteBakeHistoryStore(file: try openedStore().file)
        historyStore = opened
        return opened
    }

    /// The shopping lists, in the same database file as the recipes.
    private func openedListStore() throws -> SQLiteShoppingListStore {
        if let listStore { return listStore }
        let opened = SQLiteShoppingListStore(file: try openedStore().file)
        listStore = opened
        return opened
    }
}
