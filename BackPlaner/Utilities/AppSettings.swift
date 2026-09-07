import SwiftUI
import UIKit
import FirebaseAuth

struct AppSettingsKeys {
    static let selectedLanguage = "settings.selectedLanguage"
    static let defaultRecipeStorage = "settings.defaultRecipeStorage"
    static let defaultServingSize = "settings.defaultServingSize"
    static let useDetailView = "settings.useDetailView"
    static let preheatTime = "settings.preheatTime"
    static let bakePause = "settings.bakePause"
    static let dayStart = "settings.dayStart"
    static let dayEnd = "settings.dayEnd"
}

enum AppLanguage: String, CaseIterable, Identifiable {
    case system = ""
    case german = "de"
    case english = "en"
    case french = "fr"

    var id: String { rawValue }

    var title: LocalizedStringKey {
        switch self {
        case .system: return "Systemsprache"
        case .german: return "Deutsch"
        case .english: return "Englisch"
        case .french: return "Französisch"
        }
    }
}

enum RecipeStoragePreference: String, CaseIterable, Identifiable {
    case privateRecipe
    case publicRecipe

    var id: String { rawValue }

    var title: LocalizedStringKey {
        switch self {
        case .privateRecipe: return "Privat"
        case .publicRecipe: return "Öffentlich"
        }
    }

    var savePublic: Bool { self == .publicRecipe }
}

struct AppSettings {
    static let defaultRecipeStorage = RecipeStoragePreference.privateRecipe.rawValue
    static let defaultServingSize = 2
    static let defaultUseDetailView = true
    static let defaultPreheatTime = 15
    static let defaultBakePause = 10
    static let defaultDayStart = 6
    static let defaultDayEnd = 23
    static var defaultStartHeatingText: String {
        generatedStepTexts(languageCode: locale.identifier).startHeating
    }
    static var defaultBakeEndText: String {
        generatedStepTexts(languageCode: locale.identifier).bakeEnd
    }

    static func generatedStepTexts(languageCode: String) -> (startHeating: String, bakeEnd: String) {
        let baseLanguage = languageCode
            .replacingOccurrences(of: "-", with: "_")
            .split(separator: "_")
            .first
            .map(String.init) ?? "de"

        switch baseLanguage {
        case "en":
            return ("Turn on the oven", "Baking is finished")
        case "fr":
            return ("Allumer le four", "La cuisson est terminée")
        default:
            return ("Backofen anstellen", "Backvorgang ist beendet")
        }
    }

    static func localeIdentifier(for selectedLanguage: String = storedLanguage) -> String {
        selectedLanguage.isEmpty ? Locale.autoupdatingCurrent.identifier : selectedLanguage
    }

    static var locale: Locale {
        Locale(identifier: localeIdentifier())
    }

    static var storedLanguage: String {
        UserDefaults.standard.string(forKey: AppSettingsKeys.selectedLanguage) ?? AppLanguage.system.rawValue
    }

    static var defaultSavePublic: Bool {
        let rawValue = UserDefaults.standard.string(forKey: AppSettingsKeys.defaultRecipeStorage) ?? defaultRecipeStorage
        return RecipeStoragePreference(rawValue: rawValue)?.savePublic ?? false
    }

    static var storedServingSize: Int {
        let value = UserDefaults.standard.integer(forKey: AppSettingsKeys.defaultServingSize)
        return value == 0 ? defaultServingSize : value
    }

    static var storedUseDetailView: Bool {
        if UserDefaults.standard.object(forKey: AppSettingsKeys.useDetailView) == nil {
            return defaultUseDetailView
        }
        return UserDefaults.standard.bool(forKey: AppSettingsKeys.useDetailView)
    }

    static var storedPreheatTime: Int {
        storedInt(forKey: AppSettingsKeys.preheatTime, defaultValue: defaultPreheatTime)
    }

    static var storedBakePause: Int {
        storedInt(forKey: AppSettingsKeys.bakePause, defaultValue: defaultBakePause)
    }

    static var storedDayStart: Int {
        storedInt(forKey: AppSettingsKeys.dayStart, defaultValue: defaultDayStart)
    }

    static var storedDayEnd: Int {
        storedInt(forKey: AppSettingsKeys.dayEnd, defaultValue: defaultDayEnd)
    }

    static var storedStartHeatingText: String { defaultStartHeatingText }

    static var storedBakeEndText: String { defaultBakeEndText }

    private static func storedInt(forKey key: String, defaultValue: Int) -> Int {
        if UserDefaults.standard.object(forKey: key) == nil {
            return defaultValue
        }
        return UserDefaults.standard.integer(forKey: key)
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

    func acceptEULA() {
        guard !hasAcceptedEULA else { return }
        hasAcceptedEULA = true
        defaults.set(true, forKey: Keys.eulaAccepted)
    }
}
