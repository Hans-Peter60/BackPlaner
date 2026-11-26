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
            lastError = error.localizedDescription
            logger.error("could not read the dishes: \(error)")
        }
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

    /// The plan for the current kitchen and budget, nil when none comes out.
    func plan(for dish: KitchenDish) -> DishPlan? {
        DishPlan(dish: dish, budget: budget, burners: burners, ovens: ovens)
    }

    /// Why no plan comes out, in the cook's words.
    func failure(for dish: KitchenDish) -> String? {
        DishPlan.failure(dish: dish, budget: budget, burners: burners, ovens: ovens)
    }
}
