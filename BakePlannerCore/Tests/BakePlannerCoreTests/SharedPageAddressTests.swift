//
//  SharedPageAddressTests.swift
//  BakePlannerCoreTests
//

import Foundation
import Testing
@testable import BakePlannerCore

@Suite("The page address in a shared text")
struct SharedPageAddressTests {

    @Test("The address alone, with a title in front, or with a line break after it")
    func findsTheAddress() {
        #expect(SharedPageAddress.url(in: "https://www.example.org/brot")?.absoluteString == "https://www.example.org/brot")
        #expect(SharedPageAddress.url(in: "Roggenbrot – Rezept https://www.example.org/brot?x=1")?.absoluteString == "https://www.example.org/brot?x=1")
        #expect(SharedPageAddress.url(in: "https://www.example.org/brot\nGeteilt aus Firefox")?.absoluteString == "https://www.example.org/brot")
    }

    @Test("A sentence's punctuation after the address does not belong to it")
    func stripsPunctuation() {
        #expect(SharedPageAddress.url(in: "Schau mal: https://www.example.org/brot.")?.absoluteString == "https://www.example.org/brot")
    }

    @Test("Text without an address gives nothing")
    func noAddress() {
        #expect(SharedPageAddress.url(in: "Nur ein Satz ohne Link") == nil)
        #expect(SharedPageAddress.url(in: "") == nil)
    }

    @Test("A shared text is a page address, recipe text, or nothing")
    func kinds() {
        let url = URL(string: "https://www.example.org/brot")!
        #expect(SharedRecipeText.kind(of: "Roggenbrot https://www.example.org/brot") == .page(url))
        #expect(SharedRecipeText.kind(of: "Hallo") == nil)
        let recipe = """
        Roggenbrot
        Zutaten
        500 g Roggenmehl
        400 g Wasser
        Zubereitung
        Alles mischen und 12 Stunden reifen lassen, dann 60 Minuten backen.
        """
        #expect(SharedRecipeText.kind(of: recipe) == .text(recipe))
        // A long selection with the page's link appended is still text.
        let withLink = recipe + "\n" + recipe + "\n" + url.absoluteString
        #expect(SharedRecipeText.kind(of: withLink) == .text(withLink))
    }
}
