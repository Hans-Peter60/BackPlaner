//
//  ProAccess.swift
//  BakePlannerCore
//
//  The one answer to "may this Pro feature be used?", shared by both apps.
//  The remote switches come from the Firestore document config/monetization,
//  the purchase from StoreKit on the iPhone and from Play Billing on
//  Android, the installation's first build from the store's receipt.
//  Everything here is pure, so the decision reads the same on both
//  platforms and is tested once. Fail open: without a configuration
//  everything is free.
//

import Foundation

/// The features that belong to BakePlanner Pro. Everything else — recipes,
/// the plan with its reminders, the bake mode, the bake history, the
/// public recipes, the calculators, the backup — stays free: that is the
/// core that makes the app worth having, and none of it costs anything per
/// use. Titles and descriptions live in the apps, which have the UI
/// frameworks and the string catalogs.
public enum ProFeature: String, CaseIterable, Identifiable, Sendable {
    /// Sharing a recipe as a PDF at the serving size shown.
    case pdfExport
    /// Handing a single recipe to someone else as a re-importable file from
    /// its page. "Rezepte exportieren" in the list's menu stays free: it is
    /// the backup, and one's own data must always be portable.
    case recipeSharing
    /// A recipe that queues itself on a rhythm (feeding a starter every
    /// five days, say).
    case recurringPlans
    /// Shopping lists made from a recipe's ingredients.
    case shoppingList
    /// The home-screen and lock-screen widget with the next step.
    case widgets
    /// The Live Activity of the running plan on the lock screen.
    case liveActivity
    /// The pantry: flours, seeds and yeast with amounts and best-before dates.
    case pantry
    /// Several breads placed before one finish, the ovens and the pause respected.
    case bakingDay
    /// Saved collections of facets and "Fertig bis …"; the facets and the
    /// five preset chips stay free.
    case collections
    /// The statistics view of the baking history.
    case statistics
    /// A new recipe from baker's percentages.
    case bakersFormula
    /// A year of baking as a PDF book: figures, the bakes month by month
    /// with their photos, the favourite recipes, what the facts taught.
    case yearbook

    public var id: String { rawValue }

    /// The App Store build (CFBundleVersion) the feature first shipped in.
    /// A grandfathered installation keeps what it had on the day it was
    /// downloaded: every feature whose build is not newer than its own
    /// original build. The first six were there from the start.
    public var introducedBuild: Int {
        switch self {
        case .pdfExport, .recipeSharing, .recurringPlans, .shoppingList, .widgets, .liveActivity:
            return 1
        case .pantry, .bakingDay, .collections, .statistics, .bakersFormula, .yearbook:
            return 21
        }
    }
}

/// The document `config/monetization`, field by field. Every field has the
/// "free" value as its default, so a document that leaves a field out keeps
/// that part of the app open.
public struct MonetizationConfig: Codable, Equatable, Sendable {

    /// Whether the Pro features are locked for everyone who has not bought
    /// Pro (and is not covered by `grandfatherBeforeBuild`). While false the
    /// purchase exists in the code but locks nothing.
    public var proRequired = false

    /// Whether the settings show the Pro section and the features offer the
    /// paywall. Lets the store be shown — for the App Review, for a first
    /// round of purchases — before anything is locked. Someone who bought
    /// Pro sees the section regardless, so the purchase is never invisible.
    public var storeVisible = false

    /// Cloud imports (photo and web page analysis) a month without Pro.
    /// 0 means no monthly limit; the hourly limit in the Functions applies
    /// either way. The server reads this same document, so the app and the
    /// Functions switch together.
    public var freeImportsPerMonth = 0

    /// The build number before which an installation is grandfathered: it
    /// keeps the Pro features it had when it was first downloaded (see
    /// `ProFeature.introducedBuild`). Compared against the build of the
    /// first download — `AppTransaction.originalAppVersion` on iOS. nil
    /// means nobody is grandfathered.
    public var grandfatherBeforeBuild: String?

    /// Nothing shown, nothing locked, no monthly limit.
    public static let free = MonetizationConfig()

    public init(proRequired: Bool = false, storeVisible: Bool = false,
                freeImportsPerMonth: Int = 0, grandfatherBeforeBuild: String? = nil) {
        self.proRequired = proRequired
        self.storeVisible = storeVisible
        self.freeImportsPerMonth = freeImportsPerMonth
        self.grandfatherBeforeBuild = grandfatherBeforeBuild
    }

    /// Reads the Firestore document's fields, tolerating a missing or
    /// mistyped field by keeping its free default: a typo in the console
    /// must not lock the app.
    public init(firestoreData data: [String: Any]) {
        proRequired = data["proRequired"] as? Bool ?? false
        storeVisible = data["storeVisible"] as? Bool ?? false
        if let number = Self.integer(data["freeImportsPerMonth"]) {
            freeImportsPerMonth = max(0, number)
        }
        if let build = data["grandfatherBeforeBuild"] as? String, !build.isEmpty {
            grandfatherBeforeBuild = build
        } else if let build = Self.integer(data["grandfatherBeforeBuild"]) {
            grandfatherBeforeBuild = String(build)
        }
    }

    /// Whether an installation first downloaded as `originalAppVersion`
    /// (a build number, see `grandfatherBeforeBuild`) is grandfathered.
    /// Compared as numbers, so build "9" stays before build "10".
    public func grandfathers(originalAppVersion: String?) -> Bool {
        guard let threshold = ProAccess.buildNumber(grandfatherBeforeBuild),
              let original = ProAccess.buildNumber(originalAppVersion) else { return false }
        return original < threshold
    }

    /// A whole number however the document typed it.
    static func integer(_ value: Any?) -> Int? {
        if let value = value as? Int { return value }
        if let value = value as? Int64 { return Int(value) }
        if let value = value as? Double, value.rounded() == value, abs(value) < 1e15 { return Int(value) }
        return nil
    }
}

/// The decision, with the pieces it was made from.
public struct ProResolution: Equatable, Sendable {
    /// Whether the Pro features are locked for installations without Pro.
    public var proRequired: Bool
    /// Whether the Pro section and the paywall are shown.
    public var storeVisible: Bool
    /// Whether this installation has Pro, bought or grandfathered — what
    /// the Functions accept for the cloud imports, which were free before
    /// Pro existed.
    public var isPro: Bool
    public var purchased: Bool
    public var isGrandfathered: Bool
    /// The build first downloaded, for the grandfathered features.
    public var originalBuild: Int?

    public init(proRequired: Bool, storeVisible: Bool, isPro: Bool, purchased: Bool,
                isGrandfathered: Bool, originalBuild: Int?) {
        self.proRequired = proRequired
        self.storeVisible = storeVisible
        self.isPro = isPro
        self.purchased = purchased
        self.isGrandfathered = isGrandfathered
        self.originalBuild = originalBuild
    }

    /// Whether `feature` may be used.
    public func unlocked(_ feature: ProFeature) -> Bool {
        if !proRequired || purchased { return true }
        guard isGrandfathered, let originalBuild else { return false }
        return feature.introducedBuild <= originalBuild
    }

    /// Whether every Pro feature may be used.
    public var unlocksEverything: Bool {
        ProFeature.allCases.allSatisfy(unlocked)
    }
}

public enum ProAccess {
    /// The decision for one installation: open when the configuration does
    /// not require Pro, when Pro was bought, or when the installation is
    /// grandfathered and the feature was already in the app on the day it
    /// was downloaded.
    public static func resolve(config: MonetizationConfig, purchased: Bool, originalAppVersion: String?) -> ProResolution {
        let grandfathered = config.grandfathers(originalAppVersion: originalAppVersion)
        return ProResolution(proRequired: config.proRequired,
                             // A buyer sees the section regardless, so the
                             // purchase is never invisible to the person who made it.
                             storeVisible: config.storeVisible || purchased,
                             isPro: purchased || grandfathered,
                             purchased: purchased,
                             isGrandfathered: grandfathered,
                             originalBuild: buildNumber(originalAppVersion))
    }

    /// The build number in a version string ("21", or "21.0" on some
    /// systems — the sandbox reports "1.0"); nil when it is no number.
    public static func buildNumber(_ version: String?) -> Int? {
        guard let first = version?.split(separator: ".").first else { return nil }
        return Int(first)
    }
}
