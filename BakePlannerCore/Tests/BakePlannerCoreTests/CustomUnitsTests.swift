//
//  CustomUnitsTests.swift
//  BakePlannerCoreTests
//

import Foundation
import Testing
@testable import BakePlannerCore

@Suite("Units the user adds to the ones the app ships with")
struct CustomUnitsTests {

    @Test("A cup of 250 ml is a valid unit, trimmed")
    func validUnit() throws {
        let unit = try CustomUnits.validated(name: " Becher ", abbreviation: "Be", factor: 250, base: .milliliter, existing: [])
        #expect(unit.name == "Becher")
        #expect(unit.abbreviation == "Be")
        #expect(unit.factor == 250)
        #expect(unit.base == .milliliter)
    }

    @Test("A counted unit needs no factor; it is one")
    func countedUnit() throws {
        let unit = try CustomUnits.validated(name: "Würfel", abbreviation: "Wf", factor: nil, base: .piece, existing: [])
        #expect(unit.factor == 1)
    }

    @Test("Name, abbreviation and a factor above zero are required")
    func rejectsIncomplete() {
        #expect(throws: CustomUnitError.missingName) {
            try CustomUnits.validated(name: " ", abbreviation: "Be", factor: 250, base: .milliliter, existing: [])
        }
        #expect(throws: CustomUnitError.missingAbbreviation) {
            try CustomUnits.validated(name: "Becher", abbreviation: "", factor: 250, base: .milliliter, existing: [])
        }
        #expect(throws: CustomUnitError.factorNotPositive) {
            try CustomUnits.validated(name: "Becher", abbreviation: "Be", factor: 0, base: .gram, existing: [])
        }
    }

    @Test("A bundled unit or an own one must not be taken twice, whatever the case")
    func rejectsTaken() {
        let cup = CustomUnit(name: "Becher", abbreviation: "Be", factor: 250, baseUnit: "ml")
        // The bundled units come from the app bundle, which a package test
        // run on the Mac does not have; where they are there, "g" is taken.
        if !GlobalVariables.bundledUnitSets.isEmpty {
            #expect(CustomUnits.isTaken("g", among: []))
            #expect(CustomUnits.isTaken("GRAMM", among: []))
        }
        #expect(CustomUnits.isTaken("becher", among: [cup]))
        #expect(!CustomUnits.isTaken("Schale", among: [cup]))
        #expect(throws: CustomUnitError.abbreviationTaken("be")) {
            try CustomUnits.validated(name: "Schale", abbreviation: "be", factor: 100, base: .milliliter, existing: [cup])
        }
    }

    @Test("The units join the unit table and survive the round trip through JSON")
    func unitSetsAndCoding() throws {
        let cup = CustomUnit(name: "Becher", abbreviation: "Be", factor: 250, baseUnit: "ml")
        let sets = CustomUnits.unitSets([cup])
        #expect(sets.count == 1)
        #expect(sets[0].abbreviation == "Be")
        #expect(sets[0].factor == 250)
        #expect(sets[0].baseUnit == "ml")

        let data = try #require(CustomUnits.encode([cup]))
        #expect(CustomUnits.decode(data) == [cup])
        #expect(CustomUnits.decode(Data("nonsense".utf8)).isEmpty)
    }
}
