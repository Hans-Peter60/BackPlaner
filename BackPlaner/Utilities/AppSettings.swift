import BakePlannerCore
import SwiftUI
import UIKit
import FirebaseAuth

extension AppLanguage {
    var title: LocalizedStringKey {
        switch self {
        case .system: return "Systemsprache"
        case .german: return "Deutsch"
        case .english: return "Englisch"
        case .french: return "Französisch"
        }
    }
}

extension RecipeStoragePreference {
    var title: LocalizedStringKey {
        switch self {
        case .privateRecipe: return "Nur auf dem Gerät"
        case .publicRecipe:  return "Öffentlich für alle"
        }
    }

    /// Short form for the save buttons in the recipe forms.
    var shortTitle: LocalizedStringKey {
        switch self {
        case .privateRecipe: return "Lokal"
        case .publicRecipe:  return "Öffentlich"
        }
    }

    /// Explains the consequences of the choice below the toggle.
    var explanation: LocalizedStringKey {
        switch self {
        case .privateRecipe:
            return "Das Rezept bleibt auf dem Gerät und wird über Deine iCloud gesichert."
        case .publicRecipe:
            return "Das Rezept wird für alle Nutzer sichtbar. Veröffentliche nur Rezepte, die keine Urheberrechte verletzen."
        }
    }
}

/// Handles user-generated-content moderation state for the public recipe
/// database (App Store Guideline 1.2): a stable anonymous author id, locally
/// blocked authors, locally hidden (reported) recipes, and EULA acceptance.
/// State is persisted in UserDefaults and published so lists refresh instantly.
final class ModerationStore: ObservableObject {

    static let shared = ModerationStore()

    private let defaults = UserDefaults.standard

    private enum Keys {
        static let authorId       = "ugc.authorId"
        static let blockedAuthors = "ugc.blockedAuthors"
        static let hiddenRecipes  = "ugc.hiddenRecipes"
        static let eulaAccepted   = "ugc.eulaAccepted"
    }

    /// Device-local fallback id, used only until Firebase anonymous auth has
    /// provided a uid on the very first launch.
    private let fallbackAuthorId: String

    /// Stable anonymous id attached to content this device uploads, so other
    /// users can block this author. Prefers the Firebase auth uid (which the
    /// security rules can verify); falls back to a device id before sign-in.
    var authorId: String {
        Auth.auth().currentUser?.uid ?? fallbackAuthorId
    }

    @Published private(set) var blockedAuthors: Set<String>
    @Published private(set) var hiddenRecipes:  Set<String>
    @Published private(set) var hasAcceptedEULA: Bool

    private init() {
        blockedAuthors  = Set(defaults.stringArray(forKey: Keys.blockedAuthors) ?? [])
        hiddenRecipes   = Set(defaults.stringArray(forKey: Keys.hiddenRecipes) ?? [])
        hasAcceptedEULA = defaults.bool(forKey: Keys.eulaAccepted)

        if let existing = defaults.string(forKey: Keys.authorId) {
            fallbackAuthorId = existing
        } else {
            let generated = UIDevice.current.identifierForVendor?.uuidString ?? UUID().uuidString
            defaults.set(generated, forKey: Keys.authorId)
            fallbackAuthorId = generated
        }
    }

    func isBlocked(author: String?) -> Bool {
        guard let author, !author.isEmpty else { return false }
        return blockedAuthors.contains(author)
    }

    func isHidden(recipeId: String?) -> Bool {
        guard let recipeId, !recipeId.isEmpty else { return false }
        return hiddenRecipes.contains(recipeId)
    }

    /// True when a recipe should be removed from the public list on this device.
    func shouldHide(authorId: String?, recipeId: String?) -> Bool {
        isBlocked(author: authorId) || isHidden(recipeId: recipeId)
    }

    func block(author: String?) {
        guard let author, !author.isEmpty else { return }
        blockedAuthors.insert(author)
        defaults.set(Array(blockedAuthors), forKey: Keys.blockedAuthors)
    }

    func hide(recipeId: String?) {
        guard let recipeId, !recipeId.isEmpty else { return }
        hiddenRecipes.insert(recipeId)
        defaults.set(Array(hiddenRecipes), forKey: Keys.hiddenRecipes)
    }

    /// Takes back every block made on this device. Blocking is purely local, so
    /// this makes the author's recipes appear in the public list again at once.
    func unblockAllAuthors() {
        guard !blockedAuthors.isEmpty else { return }
        blockedAuthors.removeAll()
        defaults.removeObject(forKey: Keys.blockedAuthors)
    }

    /// Forgets this device's own hiding of recipes it reported.
    ///
    /// Unlike a block this is only half the story: `reportRecipe` also sets
    /// `hidden` on the Firestore document, and `getRecipesFB` withholds such a
    /// document from everyone but admins. So a reported recipe stays invisible
    /// until a moderator releases it — this reset only matters after that has
    /// happened, when the device would otherwise keep hiding it forever.
    func unhideAllRecipes() {
        guard !hiddenRecipes.isEmpty else { return }
        hiddenRecipes.removeAll()
        defaults.removeObject(forKey: Keys.hiddenRecipes)
    }

    func acceptEULA() {
        guard !hasAcceptedEULA else { return }
        hasAcceptedEULA = true
        defaults.set(true, forKey: Keys.eulaAccepted)
    }
}

/// What a unit's `factor` counts in.
///
/// This is the whole reason the unit menu offers a list instead of a text
/// field: a unit in this app is not a label but a conversion rule. "Tas" says
/// 200 ml, "Handvoll" says 25 g, and the ingredient totals, the baker's
/// percentages and the shopping list are all computed from that. A unit
/// without a factor cannot be converted — the amount would be read as grams,
/// so "2 Becher Mehl" would count as 2 g instead of roughly 500.
enum UnitBase: String, CaseIterable, Identifiable {
    /// The factor is a weight in grams.
    case gram = "g"
    /// The factor is a volume in millilitres; the ingredient's density is
    /// applied on top of it (a cup of flour weighs less than a cup of water).
    case milliliter = "ml"
    /// Counted rather than weighed, like eggs.
    case piece = "St"

    var id: String { rawValue }

    var title: LocalizedStringKey {
        switch self {
        case .gram:       return "Gramm"
        case .milliliter: return "Milliliter"
        case .piece:      return "Stück"
        }
    }

    /// Spells out what a number entered for this base actually means, so the
    /// factor field is not a riddle.
    var factorExplanation: LocalizedStringKey {
        switch self {
        case .gram:       return "Wie viel Gramm eine Einheit wiegt. Ein Pfund wären 500."
        case .milliliter: return "Wie viele Milliliter eine Einheit enthält. Ein Becher wären etwa 250. Das Gewicht rechnet die App je Zutat daraus."
        case .piece:      return "Wird gezählt, nicht gewogen. Die Umrechnung bleibt 1."
        }
    }
}

/// A unit the user defined himself, on top of the ones the app ships with.
struct CustomUnit: Codable, Identifiable, Hashable {
    var id = UUID()
    var name: String
    var abbreviation: String
    var factor: Double
    var baseUnit: String

    var base: UnitBase { UnitBase(rawValue: baseUnit) ?? .gram }
}

/// Stores the units the user added. The app ships 28 in `UnitSets.json`, which
/// is part of the bundle and therefore out of reach; anything else — "Becher",
/// or the "cups" and "oz" an English recipe brings in through the image
/// import — used to be a dead end: the unit menu would mark it as unknown and
/// offer no way to keep it.
///
/// Persisted in UserDefaults like [ModerationStore], and published so the unit
/// menu picks up a new entry without a restart.
final class CustomUnitStore: ObservableObject {

    static let shared = CustomUnitStore()

    private let defaults = UserDefaults.standard
    private static let storageKey = "units.custom"

    @Published private(set) var units: [CustomUnit] = []

    /// The same units in the shape the rest of the app reads units in. Kept
    /// ready rather than mapped on demand: `GlobalVariables.unitSets` is read
    /// once per ingredient inside the weight calculation.
    private(set) var unitSets: [UnitSetFB] = []

    private init() {
        if let data = defaults.data(forKey: Self.storageKey),
           let stored = try? JSONDecoder().decode([CustomUnit].self, from: data) {
            units = stored
        }
        rebuildUnitSets()
    }

    enum UnitError: LocalizedError {
        case missingName
        case missingAbbreviation
        case factorNotPositive
        case abbreviationTaken(String)

        var errorDescription: String? {
            switch self {
            case .missingName:
                return String(localized: "Bitte einen Namen angeben.", bundle: AppSettings.localizationBundle, locale: AppSettings.locale)
            case .missingAbbreviation:
                return String(localized: "Bitte ein Kürzel angeben.", bundle: AppSettings.localizationBundle, locale: AppSettings.locale)
            case .factorNotPositive:
                return String(localized: "Die Umrechnung muss größer als 0 sein.", bundle: AppSettings.localizationBundle, locale: AppSettings.locale)
            case .abbreviationTaken(let abbreviation):
                return String(format: String(localized: "Das Kürzel „%@“ ist schon vergeben.",
                                             bundle: AppSettings.localizationBundle, locale: AppSettings.locale),
                              abbreviation)
            }
        }
    }

    func add(name: String, abbreviation: String, factor: Double?, base: UnitBase) throws {
        let cleanName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanAbbreviation = abbreviation.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !cleanName.isEmpty else { throw UnitError.missingName }
        guard !cleanAbbreviation.isEmpty else { throw UnitError.missingAbbreviation }

        // A piece unit is counted, so its factor is fixed at 1 rather than asked for.
        let effectiveFactor = base == .piece ? 1 : (factor ?? 0)
        guard effectiveFactor > 0 else { throw UnitError.factorNotPositive }

        // Units are looked up by name OR abbreviation, so a clash on either
        // would make one of the two unreachable.
        guard !isTaken(cleanAbbreviation), !isTaken(cleanName) else {
            throw UnitError.abbreviationTaken(cleanAbbreviation)
        }

        units.append(CustomUnit(name: cleanName,
                                abbreviation: cleanAbbreviation,
                                factor: effectiveFactor,
                                baseUnit: base.rawValue))
        persist()
    }

    func delete(at offsets: IndexSet) {
        units.remove(atOffsets: offsets)
        persist()
    }

    /// True when a bundled or custom unit already answers to this text.
    func isTaken(_ text: String) -> Bool {
        let key = comparable(text)
        guard !key.isEmpty else { return false }

        return GlobalVariables.bundledUnitSets.contains {
            comparable($0.abbreviation) == key || comparable($0.name) == key
        } || units.contains {
            comparable($0.abbreviation) == key || comparable($0.name) == key
        }
    }

    private func comparable(_ value: String) -> String {
        value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .localizedLowercase
    }

    private func persist() {
        rebuildUnitSets()
        if let data = try? JSONEncoder().encode(units) {
            defaults.set(data, forKey: Self.storageKey)
        }
    }

    private func rebuildUnitSets() {
        unitSets = units.map { custom in
            let unitSet = UnitSetFB()
            unitSet.id           = custom.id.uuidString
            unitSet.name         = custom.name
            unitSet.abbreviation = custom.abbreviation
            unitSet.factor       = custom.factor
            unitSet.baseUnit     = custom.baseUnit
            return unitSet
        }
    }
}
