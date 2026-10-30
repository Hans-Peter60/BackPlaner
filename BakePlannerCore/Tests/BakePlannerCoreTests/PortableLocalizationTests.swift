//
//  PortableLocalizationTests.swift
//  BakePlannerCoreTests
//
//  Filling a translated text's placeholders where Foundation cannot
//  localize (Android).
//

import Foundation
import Testing
@testable import BakePlannerCore

@Suite("Texts outside Apple platforms")
struct PortableLocalizationTests {

    @Test("Placeholders take the values in order")
    func inOrder() {
        #expect(CoreLocalization.fill("„%@“ beginnt am %@.", with: ["Brot", "01.11.26, 06:00"]) == "„Brot“ beginnt am 01.11.26, 06:00.")
        #expect(CoreLocalization.fill("nur %lld Minuten, Pause %lld", with: ["5", "10"]) == "nur 5 Minuten, Pause 10")
    }

    @Test("Numbered placeholders take the value they name, as translations reorder them")
    func numbered() {
        #expect(CoreLocalization.fill("%2$@ avant %1$@", with: ["A", "B"]) == "B avant A")
    }

    @Test("A percent sign stays, a text without placeholders is unchanged")
    func plain() {
        #expect(CoreLocalization.fill("100 %% Roggen", with: []) == "100 % Roggen")
        #expect(CoreLocalization.fill("Weizenmehl", with: []) == "Weizenmehl")
    }

    @Test("Texts and unit words come from the app's catalog, by key and language")
    func catalogTranslations() {
        #expect(CoreLocalization.translation(of: "Weizen", language: "en") == "Wheat")
        #expect(CoreLocalization.translation(of: "Weizen", language: "fr") == "Blé")
        #expect(CoreLocalization.translation(of: "unit.TL", language: "en") == "tsp")
        #expect(CoreLocalization.translation(of: "unit.TL.name", language: "fr") == "cuillère à café")
        // German texts are their own keys and have no entry of their own.
        #expect(CoreLocalization.translation(of: "Weizen", language: "de") == nil)
    }

    @Test("A translated text with values reads as the app writes it")
    func translatedTextWithValues() throws {
        let format = try #require(CoreLocalization.translation(of: "„%@“", language: "fr"))
        #expect(CoreLocalization.fill(format, with: ["Brot"]) == "« Brot »")
    }
}

@Suite("Units the package brings along")
struct BundledUnitSetsTests {

    @Test("The bundled units read as the app's UnitSets.json, each with an id")
    func bundledUnits() {
        let unitSets = DataService.unitSets(from: Data(BundledUnitSetsData.json.utf8))
        let abbreviations = Set(unitSets.map(\.abbreviation))
        #expect(abbreviations.isSuperset(of: ["g", "ml", "kg", "TL", "EL", "Tas", "Pr", "St"]))
        #expect(unitSets.allSatisfy { $0.id != nil })
        #expect(unitSets.first { $0.abbreviation == "kg" }?.factor == 1000)
    }
}
