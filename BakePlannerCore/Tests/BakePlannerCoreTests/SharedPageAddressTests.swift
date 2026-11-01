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
}
