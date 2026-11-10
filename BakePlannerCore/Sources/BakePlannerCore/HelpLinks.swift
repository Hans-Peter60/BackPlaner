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

    /// The manual opened at its chapter "BakePlanner auf Android", which
    /// names what differs from the iPhone. The Android app's help link.
    public static var manualAndroidChapter: URL {
        manualAndroidChapter(for: languageCode)
    }

    public static func manualAndroidChapter(for languageCode: String) -> URL {
        let anchor: String
        switch languageCode {
        case "de": anchor = "19-bakeplanner-auf-android"
        case "fr": anchor = "19-bakeplanner-sur-android"
        default: anchor = "19-bakeplanner-on-android"
        }
        return URL(string: "\(site)manual-\(languageCode).html#\(anchor)")!
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
    public static var imprint: URL {
        URL(string: "\(site)impressum.html#\(languageCode)")!
    }
}
