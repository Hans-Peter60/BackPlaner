//
//  HelpLinksTests.swift
//  BakePlannerCoreTests
//

import Foundation
import Testing
@testable import BakePlannerCore

@Suite("The website's pages in the app's language")
struct HelpLinksTests {

    @Test("German and French keep their language, everything else gets English")
    func languageCodes() {
        #expect(HelpLinks.languageCode(for: Locale(identifier: "de_DE")) == "de")
        #expect(HelpLinks.languageCode(for: Locale(identifier: "fr_CH")) == "fr")
        #expect(HelpLinks.languageCode(for: Locale(identifier: "en_GB")) == "en")
        #expect(HelpLinks.languageCode(for: Locale(identifier: "es_ES")) == "en")
    }

    @Test("The pages sit on the site, with the language in the address")
    func addresses() {
        #expect(HelpLinks.manual.absoluteString.hasPrefix(HelpLinks.site + "manual-"))
        #expect(HelpLinks.privacy.absoluteString.hasPrefix(HelpLinks.site + "privacy.html#"))
        #expect(HelpLinks.imprint.absoluteString.hasPrefix(HelpLinks.site + "impressum.html#"))
        #expect(HelpLinks.support.absoluteString.hasPrefix(HelpLinks.site + "index.html#"))
    }
}
