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

/// The words the settings show for a unit's base (see UnitBase).
extension UnitBase {
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

// CustomUnit (a unit the user defined) lives in BakePlannerCore.

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
        reload()
        // Another device changed the units: read them again.
        NotificationCenter.default.addObserver(forName: SettingsSync.didApplyRemoteChanges, object: nil,
                                               queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.reload() }
        }
    }

    private func reload() {
        if let data = defaults.data(forKey: Self.storageKey),
           let stored = try? JSONDecoder().decode([CustomUnit].self, from: data) {
            units = stored
        } else {
            units = []
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

    /// Adds the unit the input describes; the rules are the package's
    /// (CustomUnits.validated), the wording of a refusal is this app's.
    func add(name: String, abbreviation: String, factor: Double?, base: UnitBase) throws {
        do {
            units.append(try CustomUnits.validated(name: name, abbreviation: abbreviation, factor: factor,
                                                   base: base, existing: units))
        } catch CustomUnitError.missingName {
            throw UnitError.missingName
        } catch CustomUnitError.missingAbbreviation {
            throw UnitError.missingAbbreviation
        } catch CustomUnitError.factorNotPositive {
            throw UnitError.factorNotPositive
        } catch CustomUnitError.abbreviationTaken(let abbreviation) {
            throw UnitError.abbreviationTaken(abbreviation)
        }
        persist()
    }

    func delete(at offsets: IndexSet) {
        units.remove(atOffsets: offsets)
        persist()
    }

    /// True when a bundled or custom unit already answers to this text.
    func isTaken(_ text: String) -> Bool {
        CustomUnits.isTaken(text, among: units)
    }

    private func persist() {
        rebuildUnitSets()
        if let data = try? JSONEncoder().encode(units) {
            defaults.set(data, forKey: Self.storageKey)
        }
    }

    private func rebuildUnitSets() {
        unitSets = CustomUnits.unitSets(units)
    }
}
