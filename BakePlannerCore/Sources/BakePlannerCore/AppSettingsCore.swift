//
//  AppSettingsCore.swift
//  BakePlannerCore
//
//  The settings the calculation logic reads — language, generated texts,
//  planning values — kept in UserDefaults and needing nothing but
//  Foundation. AppSettings.swift adds the parts tied to SwiftUI and the app
//  (titles for the pickers, moderation, the user's own units).
//

import Foundation

public struct AppSettingsKeys {
    public static let selectedLanguage = "settings.selectedLanguage"
    public static let defaultRecipeStorage = "settings.defaultRecipeStorage"
    public static let defaultServingSize = "settings.defaultServingSize"
    public static let useDetailView = "settings.useDetailView"
    public static let preheatTime = "settings.preheatTime"
    public static let bakePause = "settings.bakePause"
    public static let ovenCount = "settings.ovenCount"
    public static let dayStart = "settings.dayStart"
    public static let dayEnd = "settings.dayEnd"
    public static let cloudRecipeAnalysisConsent = "settings.cloudRecipeAnalysisConsent"
    public static let recipeImageAnalysisMode = "settings.recipeImageAnalysisMode"
    public static let speechInBakeMode = "settings.speechInBakeMode"
    public static let liveActivity = "settings.liveActivity"
    public static let bakersPercentages = "settings.bakersPercentages"
    public static let bakeHistoryLayout = "settings.bakeHistoryLayout"
    public static let starterDoughYield = "settings.starterDoughYield"
    public static let lievitoMadreDoughYield = "settings.lievitoMadreDoughYield"
    public static let starterDoughYieldPresets = "settings.starterDoughYieldPresets"
    public static let automaticTranslation = "settings.automaticTranslation"
    public static let doughFrictionFactor = "settings.doughFrictionFactor"
    public static let showLocalRecipes = "settings.recipeList.showLocal"
    public static let showOwnPublishedRecipes = "settings.recipeList.showOwnPublished"
    public static let showPublicCloudRecipes = "settings.recipeList.showPublicCloud"
}

public enum AppLanguage: String, CaseIterable, Identifiable {
    case system = ""
    case german = "de"
    case english = "en"
    case french = "fr"

    public var id: String { rawValue }
}

/// Where a newly entered recipe is stored. The raw values are persisted in
/// UserDefaults, so the cases keep their original names. A stored value of
/// the retired "privateCloudRecipe" no longer parses and falls back to the
/// device, which is the safe choice.
public enum RecipeStoragePreference: String, CaseIterable, Identifiable {
    /// Core Data only. Syncs with the user's own iCloud, never with the recipe database.
    case privateRecipe
    /// Recipe database, readable by every user.
    case publicRecipe

    public var id: String { rawValue }

    /// The choice as the "Veröffentlichen" toggle sees it.
    public init(publishes: Bool) {
        self = publishes ? .publicRecipe : .privateRecipe
    }

    public var publishes: Bool { self == .publicRecipe }

    /// Icon shown on the save button for this choice.
    public var symbolName: String {
        switch self {
        case .privateRecipe: return "iphone"
        case .publicRecipe:  return "tray.and.arrow.up"
        }
    }
}

public struct AppSettings {
    public static let defaultRecipeStorage = RecipeStoragePreference.privateRecipe.rawValue
    public static let defaultServingSize = 2
    public static let defaultUseDetailView = true
    /// Whether the bake mode offers to read a step aloud.
    public static let defaultSpeechInBakeMode = true
    /// Whether a running plan shows a Live Activity on the lock screen.
    public static let defaultLiveActivity = true
    /// Whether the component columns add baker's percentages to each weight.
    public static let defaultBakersPercentages = false
    /// Whether a public recipe is machine-translated into the app's language
    /// automatically, and the globe menu offers to pick a language at all.
    public static let defaultAutomaticTranslation = true
    /// Whether the combined recipe list shows local recipes, the user's own
    /// published ones and the other users' public ones — each independently,
    /// so the three can be toggled on their own rather than as a single
    /// "mine or everyone's" choice.
    public static let defaultShowLocalRecipes = true
    public static let defaultShowOwnPublishedRecipes = true
    public static let defaultShowPublicCloudRecipes = true
    /// Dough yield of the user's sourdough starter (Anstellgut), used to split
    /// an amount of starter into flour and water when the recipe does not
    /// state its TA. 200 is the usual soft starter of equal parts.
    public static let defaultStarterDoughYield = 200
    /// Dough yield of the user's lievito madre; the firm Italian starter is
    /// kept at TA 150 by convention.
    public static let defaultLievitoMadreDoughYield = 150
    public static let minimumStarterDoughYield = 120
    public static let maximumStarterDoughYield = 300
    /// The warming a dough picks up from kneading, on top of its ingredients'
    /// own temperatures. Calibrated per mixer/kneading style by comparing a
    /// predicted dough temperature against the one actually measured after
    /// mixing — the dough-temperature calculator lets it be adjusted there.
    public static let defaultFrictionFactor = 1
    public static let minimumFrictionFactor = 0
    public static let maximumFrictionFactor = 10

    public static var storedStarterDoughYield: Int {
        storedInt(forKey: AppSettingsKeys.starterDoughYield, defaultValue: defaultStarterDoughYield)
    }

    public static var storedLievitoMadreDoughYield: Int {
        storedInt(forKey: AppSettingsKeys.lievitoMadreDoughYield, defaultValue: defaultLievitoMadreDoughYield)
    }

    /// The dough yields the user keeps starters at, as quick picks when a
    /// recipe's starter is exchanged for one's own (StarterYieldAdjustment).
    /// Kept as the text typed into the settings, "190, 210, 220".
    public static let defaultStarterDoughYieldPresets = "150, 180, 200, 220"

    public static var storedStarterDoughYieldPresets: [Int] {
        starterDoughYieldPresets(from: UserDefaults.standard.string(forKey: AppSettingsKeys.starterDoughYieldPresets) ?? defaultStarterDoughYieldPresets)
    }

    /// The numbers in a free-form list, within the range a starter can have,
    /// without duplicates and in ascending order. "TA 190 / TA 210" reads
    /// as well as "190, 210". Nothing usable falls back to the defaults.
    public static func starterDoughYieldPresets(from text: String) -> [Int] {
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

    public static var storedFrictionFactor: Int {
        storedInt(forKey: AppSettingsKeys.doughFrictionFactor, defaultValue: defaultFrictionFactor)
    }

    public static var isLiveActivityEnabled: Bool {
        UserDefaults.standard.object(forKey: AppSettingsKeys.liveActivity) as? Bool ?? defaultLiveActivity
    }

    public static let defaultPreheatTime = 15
    public static let defaultBakePause = 10
    /// How many ovens the user can run at the same time. The plan check
    /// allows as many overlapping bakes as there are ovens.
    public static let defaultOvenCount = 1
    public static let maximumOvenCount = 6
    public static let defaultDayStart = 6
    public static let defaultDayEnd = 23
    public static var defaultStartHeatingText: String {
        generatedStepTexts(languageCode: locale.identifier).startHeating
    }
    public static var defaultBakeEndText: String {
        generatedStepTexts(languageCode: locale.identifier).bakeEnd
    }

    /// The steps the plan adds to a recipe. `turnDown` and `turnDownWithSteam`
    /// are formats taking the lower temperature ("220 °C") of a bake whose
    /// heat falls.
    public static func generatedStepTexts(languageCode: String) -> (startHeating: String, bakeEnd: String,
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

    /// The last step of a starter's plan, which is fed, not baked. Stored
    /// with the scheduled steps, so it is produced in the plan's language,
    /// like `generatedStepTexts`.
    public static func generatedFeedingEndText(languageCode: String) -> String {
        switch baseLanguage(of: languageCode) {
        case "en": return "Feeding finished – record the result in the starter diary"
        case "fr": return "Nourrissage terminé – noter le résultat dans le journal du levain"
        default:   return "Fütterung abgeschlossen – Ergebnis im Anstellgut-Tagebuch eintragen"
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
    public static func generatedRecipeTexts(languageCode: String = locale.identifier) -> (
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

    /// The device's language and region, used where no language is picked
    /// in the app. On iOS what Foundation reports. On Android, Swift's
    /// `Locale.current` does not follow the device's settings, so the app
    /// hands in the locale SwiftUI shows its texts in.
    public static var systemLocale: () -> Locale = { Locale.autoupdatingCurrent }

    public static func localeIdentifier(for selectedLanguage: String = storedLanguage) -> String {
        selectedLanguage.isEmpty ? systemLocale().identifier : selectedLanguage
    }

    public static var locale: Locale {
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
    public static var localizationBundle: Bundle {
        let language = storedLanguage
        guard !language.isEmpty,
              let path = Bundle.main.path(forResource: language, ofType: "lproj"),
              let bundle = Bundle(path: path)
        else { return .main }
        return bundle
    }

    public static var storedLanguage: String {
        UserDefaults.standard.string(forKey: AppSettingsKeys.selectedLanguage) ?? AppLanguage.system.rawValue
    }

    public static var defaultStoragePreference: RecipeStoragePreference {
        let rawValue = UserDefaults.standard.string(forKey: AppSettingsKeys.defaultRecipeStorage) ?? defaultRecipeStorage
        return RecipeStoragePreference(rawValue: rawValue) ?? .privateRecipe
    }

    public static var storedServingSize: Int {
        let value = UserDefaults.standard.integer(forKey: AppSettingsKeys.defaultServingSize)
        return value == 0 ? defaultServingSize : value
    }

    public static var storedUseDetailView: Bool {
        if UserDefaults.standard.object(forKey: AppSettingsKeys.useDetailView) == nil {
            return defaultUseDetailView
        }
        return UserDefaults.standard.bool(forKey: AppSettingsKeys.useDetailView)
    }

    public static var storedPreheatTime: Int {
        storedInt(forKey: AppSettingsKeys.preheatTime, defaultValue: defaultPreheatTime)
    }

    public static var storedBakePause: Int {
        storedInt(forKey: AppSettingsKeys.bakePause, defaultValue: defaultBakePause)
    }

    /// Never below 1: a stored 0 would switch the overlap check off entirely.
    public static var storedOvenCount: Int {
        max(1, storedInt(forKey: AppSettingsKeys.ovenCount, defaultValue: defaultOvenCount))
    }

    public static var storedDayStart: Int {
        storedInt(forKey: AppSettingsKeys.dayStart, defaultValue: defaultDayStart)
    }

    public static var storedDayEnd: Int {
        storedInt(forKey: AppSettingsKeys.dayEnd, defaultValue: defaultDayEnd)
    }

    public static var storedStartHeatingText: String { defaultStartHeatingText }

    public static var storedBakeEndText: String { defaultBakeEndText }

    private static func storedInt(forKey key: String, defaultValue: Int) -> Int {
        if UserDefaults.standard.object(forKey: key) == nil {
            return defaultValue
        }
        return UserDefaults.standard.integer(forKey: key)
    }

}
