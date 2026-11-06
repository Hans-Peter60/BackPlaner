//
//  DoughPlausibility.swift
//  BakePlannerCore
//
//  What looks off in a recipe's composition, in baker's percentages:
//  salt far from the usual two percent of the flour, more yeast than a
//  long fermentation needs. After an import these catch a misread amount
//  ("12 g" read as "120 g"); in a recipe of one's own they are a nudge,
//  nothing more. The texts are the package's, so both apps say the same.
//

import Foundation

public enum DoughPlausibility {

    /// Salt as a share of the flour: what bakers usually use, and where
    /// a hint starts.
    public static let usualSaltRange = 1.8...2.2
    public static let lowSalt = 1.5
    public static let highSalt = 2.5
    /// Fresh yeast beyond this share of the flour is a lot; long
    /// fermentations manage with far less.
    public static let muchFreshYeast = 2.0
    public static let muchDryYeast = 1.0

    public enum Kind: String, CaseIterable, Sendable {
        case lowSalt
        case highSalt
        case muchFreshYeast
        case muchDryYeast
    }

    public struct Hint: Equatable, Identifiable {
        public let kind: Kind
        public let text: String

        public var id: String { kind.rawValue }
    }

    /// The hints for `result`, in the order they are shown; none for a
    /// recipe without salt or yeast, which may well be meant that way.
    public static func hints(for result: DoughComposition.Result,
                             locale: Locale = AppSettings.locale,
                             bundle: Bundle = AppSettings.localizationBundle) -> [Hint] {
        guard result.flour > 0 else { return [] }
        var hints: [Hint] = []

        let salt = result.saltShare
        let usual = "\(percentText(usualSaltRange.lowerBound, locale: locale, unit: false))–\(percentText(usualSaltRange.upperBound, locale: locale))"
        if result.salt > 0, salt < lowSalt {
            hints.append(Hint(kind: .lowSalt,
                              text: String(localized: "Wenig Salz: \(percentText(salt, locale: locale)) des Mehls, üblich sind \(usual).", bundle: bundle)))
        } else if salt > highSalt {
            hints.append(Hint(kind: .highSalt,
                              text: String(localized: "Viel Salz: \(percentText(salt, locale: locale)) des Mehls, üblich sind \(usual).", bundle: bundle)))
        }

        if result.freshYeastShare > muchFreshYeast {
            hints.append(Hint(kind: .muchFreshYeast,
                              text: String(localized: "Viel Frischhefe: \(percentText(result.freshYeastShare, locale: locale)) des Mehls; bei langer Führung reichen \(percentText(1, locale: locale)) und weniger.", bundle: bundle)))
        }
        if result.dryYeastShare > muchDryYeast {
            hints.append(Hint(kind: .muchDryYeast,
                              text: String(localized: "Viel Trockenhefe: \(percentText(result.dryYeastShare, locale: locale)) des Mehls; bei langer Führung reichen \(percentText(0.5, locale: locale)) und weniger.", bundle: bundle)))
        }
        return hints
    }

    /// "1,2 %" in the app's language; without the unit for the lower end
    /// of a range.
    public static func percentText(_ percent: Double, locale: Locale = AppSettings.locale, unit: Bool = true) -> String {
        let number = percent.formatted(.number.precision(.fractionLength(0...1)).locale(locale))
        return unit ? number + "\u{00A0}%" : number
    }
}
