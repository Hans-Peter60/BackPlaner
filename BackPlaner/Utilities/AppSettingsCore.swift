//
//  AppSettingsCore.swift
//  BackPlaner
//
//  The settings the calculation logic reads — language, generated texts,
//  planning values — kept in UserDefaults and needing nothing but
//  Foundation. AppSettings.swift adds the parts tied to SwiftUI and the app
//  (titles for the pickers, moderation, the user's own units).
//

import Foundation

struct AppSettingsKeys {
    static let selectedLanguage = "settings.selectedLanguage"
    static let defaultRecipeStorage = "settings.defaultRecipeStorage"
    static let defaultServingSize = "settings.defaultServingSize"
    static let useDetailView = "settings.useDetailView"
    static let preheatTime = "settings.preheatTime"
    static let bakePause = "settings.bakePause"
    static let ovenCount = "settings.ovenCount"
    static let dayStart = "settings.dayStart"
    static let dayEnd = "settings.dayEnd"
    static let cloudRecipeAnalysisConsent = "settings.cloudRecipeAnalysisConsent"
    static let recipeImageAnalysisMode = "settings.recipeImageAnalysisMode"
    static let speechInBakeMode = "settings.speechInBakeMode"
    static let liveActivity = "settings.liveActivity"
    static let bakersPercentages = "settings.bakersPercentages"
    static let bakeHistoryLayout = "settings.bakeHistoryLayout"
    static let starterDoughYield = "settings.starterDoughYield"
    static let lievitoMadreDoughYield = "settings.lievitoMadreDoughYield"
    static let starterDoughYieldPresets = "settings.starterDoughYieldPresets"
    static let automaticTranslation = "settings.automaticTranslation"
    static let doughFrictionFactor = "settings.doughFrictionFactor"
    static let showLocalRecipes = "settings.recipeList.showLocal"
    static let showOwnPublishedRecipes = "settings.recipeList.showOwnPublished"
    static let showPublicCloudRecipes = "settings.recipeList.showPublicCloud"
}

enum AppLanguage: String, CaseIterable, Identifiable {
    case system = ""
    case german = "de"
    case english = "en"
    case french = "fr"

    var id: String { rawValue }
}

/// Where a newly entered recipe is stored. The raw values are persisted in
/// UserDefaults, so the cases keep their original names. A stored value of
/// the retired "privateCloudRecipe" no longer parses and falls back to the
/// device, which is the safe choice.
enum RecipeStoragePreference: String, CaseIterable, Identifiable {
    /// Core Data only. Syncs with the user's own iCloud, never with the recipe database.
    case privateRecipe
    /// Recipe database, readable by every user.
    case publicRecipe

    var id: String { rawValue }

    /// The choice as the "Veröffentlichen" toggle sees it.
    init(publishes: Bool) {
        self = publishes ? .publicRecipe : .privateRecipe
    }

    var publishes: Bool { self == .publicRecipe }

    /// Icon shown on the save button for this choice.
    var symbolName: String {
        switch self {
        case .privateRecipe: return "iphone"
        case .publicRecipe:  return "tray.and.arrow.up"
        }
    }
}

struct AppSettings {
    static let defaultRecipeStorage = RecipeStoragePreference.privateRecipe.rawValue
    static let defaultServingSize = 2
    static let defaultUseDetailView = true
    /// Whether the bake mode offers to read a step aloud.
    static let defaultSpeechInBakeMode = true
    /// Whether a running plan shows a Live Activity on the lock screen.
    static let defaultLiveActivity = true
    /// Whether the component columns add baker's percentages to each weight.
    static let defaultBakersPercentages = false
    /// Whether a public recipe is machine-translated into the app's language
    /// automatically, and the globe menu offers to pick a language at all.
    static let defaultAutomaticTranslation = true
    /// Whether the combined recipe list shows local recipes, the user's own
    /// published ones and the other users' public ones — each independently,
    /// so the three can be toggled on their own rather than as a single
    /// "mine or everyone's" choice.
    static let defaultShowLocalRecipes = true
    static let defaultShowOwnPublishedRecipes = true
    static let defaultShowPublicCloudRecipes = true
    /// Dough yield of the user's sourdough starter (Anstellgut), used to split
    /// an amount of starter into flour and water when the recipe does not
    /// state its TA. 200 is the usual soft starter of equal parts.
    static let defaultStarterDoughYield = 200
    /// Dough yield of the user's lievito madre; the firm Italian starter is
    /// kept at TA 150 by convention.
    static let defaultLievitoMadreDoughYield = 150
    static let minimumStarterDoughYield = 120
    static let maximumStarterDoughYield = 300
    /// The warming a dough picks up from kneading, on top of its ingredients'
    /// own temperatures. Calibrated per mixer/kneading style by comparing a
    /// predicted dough temperature against the one actually measured after
    /// mixing — the dough-temperature calculator lets it be adjusted there.
    static let defaultFrictionFactor = 1
    static let minimumFrictionFactor = 0
    static let maximumFrictionFactor = 10

    static var storedStarterDoughYield: Int {
        storedInt(forKey: AppSettingsKeys.starterDoughYield, defaultValue: defaultStarterDoughYield)
    }

    static var storedLievitoMadreDoughYield: Int {
        storedInt(forKey: AppSettingsKeys.lievitoMadreDoughYield, defaultValue: defaultLievitoMadreDoughYield)
    }

    /// The dough yields the user keeps starters at, as quick picks when a
    /// recipe's starter is exchanged for one's own (StarterYieldAdjustment).
    /// Kept as the text typed into the settings, "190, 210, 220".
    static let defaultStarterDoughYieldPresets = "150, 180, 200, 220"

    static var storedStarterDoughYieldPresets: [Int] {
        starterDoughYieldPresets(from: UserDefaults.standard.string(forKey: AppSettingsKeys.starterDoughYieldPresets) ?? defaultStarterDoughYieldPresets)
    }

    /// The numbers in a free-form list, within the range a starter can have,
    /// without duplicates and in ascending order. "TA 190 / TA 210" reads
    /// as well as "190, 210". Nothing usable falls back to the defaults.
    static func starterDoughYieldPresets(from text: String) -> [Int] {
        let numbers = text
            .split(whereSeparator: { !$0.isNumber })
            .compactMap { Int($0) }
            .filter { (minimumStarterDoughYield...maximumStarterDoughYield).contains($0) }
        let presets = Array(Set(numbers)).sorted()
        if presets.isEmpty, text != defaultStarterDoughYieldPresets {
            return starterDoughYieldPresets(from: defaultStarterDoughYieldPresets)
        }
        return presets
    }

    static var storedFrictionFactor: Int {
        storedInt(forKey: AppSettingsKeys.doughFrictionFactor, defaultValue: defaultFrictionFactor)
    }

    static var isLiveActivityEnabled: Bool {
        UserDefaults.standard.object(forKey: AppSettingsKeys.liveActivity) as? Bool ?? defaultLiveActivity
    }

    static let defaultPreheatTime = 15
    static let defaultBakePause = 10
    /// How many ovens the user can run at the same time. The plan check
    /// allows as many overlapping bakes as there are ovens.
    static let defaultOvenCount = 1
    static let maximumOvenCount = 6
    static let defaultDayStart = 6
    static let defaultDayEnd = 23
    static var defaultStartHeatingText: String {
        generatedStepTexts(languageCode: locale.identifier).startHeating
    }
    static var defaultBakeEndText: String {
        generatedStepTexts(languageCode: locale.identifier).bakeEnd
    }

    /// The steps the plan adds to a recipe. `turnDown` and `turnDownWithSteam`
    /// are formats taking the lower temperature ("220 °C") of a bake whose
    /// heat falls.
    static func generatedStepTexts(languageCode: String) -> (startHeating: String, bakeEnd: String,
                                                              turnDown: String, turnDownWithSteam: String) {
        switch baseLanguage(of: languageCode) {
        case "en":
            return ("Turn on the oven", "Baking is finished",
                    "Turn the oven down to %@", "Turn the oven down to %@, release the steam")
        case "fr":
            return ("Allumer le four", "La cuisson est terminée",
                    "Baisser le four à %@", "Baisser le four à %@, évacuer la buée")
        default:
            return ("Backofen anstellen", "Backvorgang ist beendet",
                    "Backofen auf %@ zurückdrehen", "Backofen auf %@ zurückdrehen, Dampf ablassen")
        }
    }

    /// Texts the app writes into a recipe itself — a step sentence, a fallback
    /// name, a placeholder comment. They become part of the stored data, so they
    /// have to be produced in the app's language at the moment they are created;
    /// a String Catalog entry could no longer translate them afterwards, the way
    /// it does for texts that are only displayed.
    ///
    /// `bakeTemperature` and `fallingBakeTemperature` must keep the higher
    /// temperature in front of the lower one: the preheating reminder reads the
    /// oven temperature from the first number of the baking step.
    static func generatedRecipeTexts(languageCode: String = locale.identifier) -> (
        importedRecipe: String,
        componentFormat: String,
        componentPreparationFormat: String,
        bakeTemperatureFormat: String,
        fallingBakeTemperatureFormat: String,
        steamFormat: String,
        missingComment: String
    ) {
        switch baseLanguage(of: languageCode) {
        case "en":
            return (
                "Imported recipe",
                "Component %lld",
                "Prepare component %@: ",
                "Bake at %@.",
                "Bake at %1$@ °C, falling to %2$@ °C.",
                "Steam: %@.",
                "no comment recorded"
            )
        case "fr":
            return (
                "Recette importée",
                "Composant %lld",
                "Préparer le composant %@ : ",
                "Cuire à %@.",
                "Cuire à %1$@ °C en descendant à %2$@ °C.",
                "Buée : %@.",
                "aucun commentaire"
            )
        default:
            return (
                "Importiertes Rezept",
                "Komponente %lld",
                "Die Komponente %@ herstellen: ",
                "Bei %@ backen.",
                "Bei %1$@ °C fallend auf %2$@ °C backen.",
                "Schwaden: %@.",
                "kein Kommentar erfasst"
            )
        }
    }

    private static func baseLanguage(of languageCode: String) -> String {
        languageCode
            .replacingOccurrences(of: "-", with: "_")
            .split(separator: "_")
            .first
            .map(String.init) ?? "de"
    }

    static func localeIdentifier(for selectedLanguage: String = storedLanguage) -> String {
        selectedLanguage.isEmpty ? Locale.autoupdatingCurrent.identifier : selectedLanguage
    }

    static var locale: Locale {
        Locale(identifier: localeIdentifier())
    }

    /// The bundle holding the language the user picked inside the app.
    ///
    /// Needed because the in-app language is applied through
    /// `.environment(\.locale, …)` on the root view. SwiftUI honours that for
    /// `Text("…")`, but a *bundle* lookup never sees it — and the `locale:`
    /// argument of `String(localized:)` only formats the interpolated values,
    /// it does not choose which translation is used. Without this, every
    /// `String(localized:)` resolved in the **system** language: a user with a
    /// German phone who set the app to English still got German plan warnings
    /// and, worse, German reminders on the lock screen.
    ///
    /// Falls back to the main bundle for "system language" and whenever the
    /// `.lproj` for the chosen language is missing.
    static var localizationBundle: Bundle {
        let language = storedLanguage
        guard !language.isEmpty,
              let path = Bundle.main.path(forResource: language, ofType: "lproj"),
              let bundle = Bundle(path: path)
        else { return .main }
        return bundle
    }

    static var storedLanguage: String {
        UserDefaults.standard.string(forKey: AppSettingsKeys.selectedLanguage) ?? AppLanguage.system.rawValue
    }

    static var defaultStoragePreference: RecipeStoragePreference {
        let rawValue = UserDefaults.standard.string(forKey: AppSettingsKeys.defaultRecipeStorage) ?? defaultRecipeStorage
        return RecipeStoragePreference(rawValue: rawValue) ?? .privateRecipe
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

    /// Never below 1: a stored 0 would switch the overlap check off entirely.
    static var storedOvenCount: Int {
        max(1, storedInt(forKey: AppSettingsKeys.ovenCount, defaultValue: defaultOvenCount))
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
