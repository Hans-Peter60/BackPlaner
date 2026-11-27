//
//  HelpLinks.swift
//  BakePlannerCore
//
//  Addresses of the manual, the support page, the privacy policy and the
//  legal notice on the BakePlanner website, in the language the app runs
//  in. Shared by both apps: a store listing has to point at the same
//  privacy policy the app opens.
//

import Foundation

public enum HelpLinks {

    public static let site = "https://hans-peter60.github.io/bakeplanner/"

    /// "de", "en" or "fr" — the pages exist in exactly these; anything else
    /// gets English.
    public static var languageCode: String {
        languageCode(for: AppSettings.locale)
    }

    public static func languageCode(for locale: Locale) -> String {
        let code = locale.language.languageCode?.identifier ?? "en"
        return ["de", "fr"].contains(code) ? code : "en"
    }

    public static var manual: URL {
        URL(string: "\(site)manual-\(languageCode).html")!
    }

    /// BakePlanner's own manual for the Android app.
    public static var androidManual: URL {
        androidManual(for: languageCode)
    }

    public static func androidManual(for languageCode: String) -> URL {
        URL(string: "\(site)android-manual-\(languageCode).html")!
    }

    public static var support: URL {
        URL(string: "\(site)index.html#\(languageCode)")!
    }

    /// The privacy policy, in the language the app runs in. Also the URL to
    /// give the app stores.
    public static var privacy: URL {
        URL(string: "\(site)privacy.html#\(languageCode)")!
    }

    /// The legal notice (Impressum) German law requires of a commercial app.
    /// The same for both apps.
    public static var imprint: URL {
        URL(string: "\(site)impressum.html#\(languageCode)")!
    }

    // MARK: CookPlanner

    /// CookPlanner's help page with its questions and the contact.
    public static var cookPlannerSupport: URL {
        cookPlannerSupport(for: languageCode)
    }

    public static func cookPlannerSupport(for languageCode: String) -> URL {
        URL(string: "\(site)cookplanner.html#\(languageCode)")!
    }

    /// CookPlanner's own privacy policy, also the address for its store
    /// listings.
    public static var cookPlannerPrivacy: URL {
        cookPlannerPrivacy(for: languageCode)
    }

    public static func cookPlannerPrivacy(for languageCode: String) -> URL {
        URL(string: "\(site)cookplanner-privacy.html#\(languageCode)")!
    }

    /// The manual of CookPlanner's iPhone and iPad app.
    public static var cookPlannerManual: URL {
        cookPlannerManual(for: languageCode)
    }

    public static func cookPlannerManual(for languageCode: String) -> URL {
        URL(string: "\(site)cookplanner-manual-\(languageCode).html")!
    }

    /// The manual of CookPlanner's Android app.
    public static var cookPlannerAndroidManual: URL {
        cookPlannerAndroidManual(for: languageCode)
    }

    public static func cookPlannerAndroidManual(for languageCode: String) -> URL {
        URL(string: "\(site)cookplanner-android-manual-\(languageCode).html")!
    }
}
