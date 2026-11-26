//
//  KitchenProAccess.swift
//  BakePlannerCore
//
//  CookPlanner Pro: which features belong to it and whether one may be
//  used. The switches are BakePlanner's (`MonetizationConfig`), read from
//  CookPlanner's own Firestore document `config/cookplannerMonetization`,
//  so either app's purchase can be switched on without the other.
//
//  CookPlanner starts with Pro from its first store build, so there is no
//  grandfathering: a feature is open while the configuration does not
//  require Pro, or once Pro is bought. Fail open, as in BakePlanner:
//  without a configuration everything is free.
//

import Foundation

/// The features of CookPlanner Pro. Everything needed to plan a dish and
/// cook it against the clock stays free: dishes by hand, from photos or web
/// pages, the plan with its timeline and verdict, the cook mode in all three
/// clock modes, notifications, alarms and the Live Activity (they keep the
/// food from burning), the shopping list, the history, iCloud sync, the
/// backup and Siri's "how long" and "step done". The cloud analysis is
/// limited by the Functions, not here: a monthly allowance without Pro.
public enum KitchenProFeature: String, CaseIterable, Identifiable, Sendable {
    /// Several dishes composed into one menu with gaps between the courses.
    case menu
    /// Read aloud and voice commands in the cook mode.
    case handsFree
    /// The year of cooking as a PDF book.
    case yearbook
    /// The statistics view of the cooking history.
    case statistics
    /// Saved collections of filters; search, filters and the preset chips
    /// stay free.
    case collections
    /// The plan printed or shared as a PDF.
    case planPDF
    /// Taking the measured times of earlier runs into the dish; the
    /// measuring itself stays free.
    case learnedTimes

    public var id: String { rawValue }
}

public enum KitchenProAccess {

    /// The Firestore document with CookPlanner's switches.
    public static let configDocument = "config/cookplannerMonetization"

    /// Whether `feature` may be used: open unless Pro is required and not
    /// bought.
    public static func unlocked(_ feature: KitchenProFeature, config: MonetizationConfig, purchased: Bool) -> Bool {
        !config.proRequired || purchased
    }

    /// Whether the Pro section and the paywall are shown: when the store is
    /// switched visible, when Pro is required (a lock must offer its key),
    /// or after a purchase, so the purchase is never invisible.
    public static func storeVisible(config: MonetizationConfig, purchased: Bool) -> Bool {
        config.storeVisible || config.proRequired || purchased
    }
}

extension MonetizationConfig {

    /// Reads the `fields` of a document as Firestore's REST interface
    /// returns it — every value wrapped in its type, integers as strings:
    /// `{"proRequired": {"booleanValue": true}, "freeImportsPerMonth":
    /// {"integerValue": "5"}}`. Unknown or mistyped values keep their free
    /// default, as in `init(firestoreData:)`.
    public init(firestoreRESTFields fields: [String: Any]) {
        var plain = [String: Any]()
        for (name, wrapped) in fields {
            guard let wrapped = wrapped as? [String: Any] else { continue }
            if let value = wrapped["booleanValue"] as? Bool {
                plain[name] = value
            } else if let text = wrapped["integerValue"] as? String, let value = Int(text) {
                plain[name] = value
            } else if let value = wrapped["integerValue"] as? Int {
                plain[name] = value
            } else if let value = wrapped["doubleValue"] as? Double {
                plain[name] = value
            } else if let value = wrapped["stringValue"] as? String {
                plain[name] = value
            }
        }
        self.init(firestoreData: plain)
    }
}
