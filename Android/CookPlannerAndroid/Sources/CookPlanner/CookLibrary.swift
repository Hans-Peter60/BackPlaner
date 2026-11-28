import BakePlannerCore
import CookPlannerStorage
import Foundation
import Observation
import SkipFuse

/// The cook's dishes and kitchen on Android: the own dishes from the SQLite
/// file (CookPlannerStorage, the iPhone's store), the three examples from
/// the package, and the budget, burners and ovens the plans are made for.
@Observable
@MainActor
final class CookLibrary {

    static let budgetKey = "settings.budgetMinutes"
    static let burnersKey = "settings.burners"
    static let ovensKey = "settings.ovens"

    private(set) var dishes: [KitchenDish] = []
    var lastError: String?

    var budget: Int { didSet { SettingsFile.set(budget, forKey: Self.budgetKey) } }
    var burners: Int { didSet { SettingsFile.set(burners, forKey: Self.burnersKey) } }
    var ovens: Int { didSet { SettingsFile.set(ovens, forKey: Self.ovensKey) } }

    private var store: SQLiteKitchenDishStore?

    init() {
        budget = SettingsFile.integer(Self.budgetKey, default: KitchenSampleDishes.budget)
        burners = SettingsFile.integer(Self.burnersKey, default: 4)
        ovens = SettingsFile.integer(Self.ovensKey, default: 1)
    }

    /// Opens the database and reads the dishes; harmless to call again.
    func load() {
        do {
            if store == nil {
                let folder = URL.applicationSupportDirectory
                try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
                store = try SQLiteKitchenDishStore(path: folder.appendingPathComponent("dishes.sqlite").path)
            }
            dishes = try store?.dishes() ?? []
        } catch {
            lastError = Self.describe(error)
            logger.error("could not read the dishes: \(error)")
        }
    }

    /// The database's refusal in the app's words; other errors as they are.
    private static func describe(_ error: Error) -> String {
        if case CookPlannerDatabaseError.newerSchema = error {
            return String(localized: "Die Gerichte auf diesem Gerät stammen aus einer neueren Version von CookPlanner. Bitte die App aktualisieren.", bundle: .module)
        }
        return "\(error)"
    }

    /// Keeps a dish; false (with `lastError`) when the database refuses.
    @discardableResult
    func save(_ dish: KitchenDish) -> Bool {
        // Without an open database nothing is kept: say so rather than
        // pretend (the editor closed, the import counted, nothing stayed).
        guard let store else {
            if lastError == nil {
                lastError = String(localized: "Die Gerichte-Datenbank lässt sich nicht öffnen; Änderungen werden nicht gespeichert.", bundle: .module)
            }
            return false
        }
        do {
            var own = dish
            if own.source == .sample { own.source = .manual }
            try store.save(own)
            dishes = try store.dishes()
            return true
        } catch {
            lastError = Self.describe(error)
            return false
        }
    }

    func delete(id: String) {
        do {
            try store?.delete(id: id)
            dishes = try store?.dishes() ?? dishes
        } catch {
            lastError = error.localizedDescription
        }
    }

    /// A copy of an example (or any dish) to change as one's own.
    func template(from dish: KitchenDish) -> KitchenDish {
        var copy = dish
        copy.id = UUID().uuidString
        copy.source = .manual
        copy.createdAt = Date()
        return copy
    }

    /// The file of `dishes` in the cache folder, for the system's "save
    /// as"; nil when it cannot be written. The format is the iPhone's
    /// (KitchenDishFile), so the file moves dishes between the platforms.
    func exportFile(of dishes: [KitchenDish], includesRecords: Bool = false) async -> URL? {
        let runs = includesRecords ? CookRunLog.shared.runs : []
        let rawPhotos = includesRecords ? CookRunLog.shared.backupPhotos() : [:]
        let fileName = KitchenDishTransfer.fileName(for: includesRecords ? [] : dishes)
        // The photos made small (the iPhone's backup size), the file
        // encoded and written away from the main thread: a hundred photos
        // held the screen for many seconds.
        return await Task.detached { () -> URL? in
            do {
                let photos = rawPhotos.mapValues { PhotoShrinker.backupPhoto($0) }
                let file = includesRecords
                    ? KitchenDishFile(dishes: dishes, runs: runs, photos: photos)
                    : KitchenDishFile(dishes: dishes)
                let data = try file.encoded()
                let folder = URL.cachesDirectory.appendingPathComponent("exports", isDirectory: true)
                try? FileManager.default.removeItem(at: folder)
                try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
                // A backup is named by its date ("CookPlanner 2026-11-26"), even
                // with one dish; a shared dish by its name.
                let url = folder.appendingPathComponent(fileName)
                try data.write(to: url)
                return url
            } catch {
                logger.error("could not write the dish file: \(error)")
                return nil
            }
        }.value
    }

    /// Reads a .cookplanner file and keeps the dishes that are new; the
    /// sentence the alert shows. What is there already stays as it is.
    func importFile(at url: URL) async -> String {
        let file: KitchenDishFile
        do {
            // Read and decoded away from the main thread (the photos).
            file = try await Task.detached { try KitchenDishFile.decode(try Data(contentsOf: url)) }.value
        } catch KitchenDishFileError.unsupportedVersion {
            return String(localized: "Die Datei stammt aus einer neueren Version von CookPlanner. Bitte die App aktualisieren.", bundle: .module)
        } catch {
            return String(localized: "Die Datei ist keine CookPlanner-Datei oder beschädigt.", bundle: .module)
        }
        let result = KitchenDishTransfer.merge(file.kitchenDishes, into: dishes)
        var kept = 0
        // Tidied first (duplicate step ids, dangling dependencies), as the
        // editor does; the database would refuse them.
        for dish in result.added where save(dish.consistent()) { kept += 1 }
        var sentence: String
        if kept == 0 && result.alreadyThere > 0 {
            sentence = String(localized: "Alle \(result.alreadyThere) Gerichte waren schon da.", bundle: .module)
        } else if result.alreadyThere > 0 {
            sentence = String(localized: "\(kept) Gerichte übernommen, \(result.alreadyThere) waren schon da.", bundle: .module)
        } else {
            sentence = String(localized: "\(kept) Gerichte übernommen.", bundle: .module)
        }
        // A backup brings the cooking records and their photos along.
        if let runs = file.runs, !runs.isEmpty {
            let records = CookRunLog.shared.importRuns(runs, photos: file.photos ?? [:])
            if records.added == 0 {
                sentence += " " + String(localized: "Alle \(records.alreadyThere) Protokolle waren schon da.", bundle: .module)
            } else if records.alreadyThere > 0 {
                sentence += " " + String(localized: "\(records.added) Protokolle übernommen, \(records.alreadyThere) waren schon da.", bundle: .module)
            } else {
                sentence += " " + String(localized: "\(records.added) Protokolle übernommen.", bundle: .module)
            }
        }
        return sentence
    }

    /// The cook's own dishes, newest first.
    var ownDishes: [KitchenDish] {
        dishes.filter { $0.source != .sample }
            .sorted { ($0.createdAt ?? .distantPast) > ($1.createdAt ?? .distantPast) }
    }

    var samples: [KitchenDish] { KitchenSampleDishes.all }

    func dish(id: String) -> KitchenDish? {
        dishes.first { $0.id == id } ?? samples.first { $0.id == id }
    }

    /// The plan for the current kitchen and budget, nil when none comes
    /// out; the ingredients at the portions chosen for the dish (the steps
    /// keep their minutes).
    func plan(for dish: KitchenDish) -> DishPlan? {
        DishPlan(dish: dish.scaled(by: portionFactor(for: dish.id)), budget: budget, burners: burners, ovens: ovens)
    }

    /// Bumped when a portion factor changes, so the screens read it again.
    private(set) var portionsRevision = 0

    /// The portion factor chosen for a dish, 1 when none was chosen (the
    /// iPhone's key, "portions.<id>").
    func portionFactor(for dishID: String) -> Double {
        _ = portionsRevision
        let factor = SettingsFile.number("portions." + dishID) ?? 1
        return factor > 0 ? factor : 1
    }

    func setPortionFactor(_ factor: Double, for dishID: String) {
        SettingsFile.set(factor == 1 ? nil : factor, forKey: "portions." + dishID)
        portionsRevision += 1
    }

    /// Why no plan comes out, in the cook's words.
    func failure(for dish: KitchenDish) -> String? {
        DishPlan.failure(dish: dish, budget: budget, burners: burners, ovens: ovens)
    }
}
