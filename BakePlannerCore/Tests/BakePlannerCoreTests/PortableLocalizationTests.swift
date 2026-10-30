//
//  PortableLocalizationTests.swift
//  BakePlannerCoreTests
//
//  Filling a translated text's placeholders where Foundation cannot
//  localize (Android).
//

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
}
