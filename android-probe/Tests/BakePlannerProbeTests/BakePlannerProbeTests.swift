//
//  BakePlannerProbeTests.swift
//  BakePlannerProbeTests
//
//  The same expectations the app's unit tests have for this logic, run on
//  Android as well. XCTest rather than Swift Testing, which every Skip mode
//  runs on Android.
//

import Foundation
import XCTest
@testable import BakePlannerProbe

final class BakePlannerProbeTests: XCTestCase {

    // MARK: Dough temperature (DoughTemperatureCalculatorTests in the app)

    func testStraightDoughUsesTheThreeMultiplier() {
        let water = DoughTemperatureCalculator.waterTemperature(
            targetDoughTemperature: 24, roomTemperature: 21, flourTemperature: 21,
            frictionFactor: 1, prefermentTemperature: nil)
        XCTAssertEqual(water, 24 * 3 - (21 + 21 + 1))
    }

    func testDoughWithPrefermentUsesTheFourMultiplier() {
        let water = DoughTemperatureCalculator.waterTemperature(
            targetDoughTemperature: 24, roomTemperature: 21, flourTemperature: 21,
            frictionFactor: 1, prefermentTemperature: 21)
        XCTAssertEqual(water, 24 * 4 - (21 + 21 + 1 + 21))
    }

    func testFeasibility() {
        XCTAssertEqual(DoughTemperatureCalculator.feasibility(ofWaterTemperature: 25), .ok)
        XCTAssertEqual(DoughTemperatureCalculator.feasibility(ofWaterTemperature: 0), .tooCold)
        XCTAssertEqual(DoughTemperatureCalculator.feasibility(ofWaterTemperature: 51), .tooHot)
    }

    // MARK: Ingredient names — regular expressions and Unicode

    func testTemperaturesAreRemovedFromIngredientNames() {
        XCTAssertEqual(IngredientNameNormalizer.displayName("Wasser (lauwarm, 30 °C)"), "Wasser")
        XCTAssertEqual(IngredientNameNormalizer.displayName("Hefe, zimmerwarm"), "Hefe")
        XCTAssertEqual(IngredientNameNormalizer.displayName("Milch, lauwarm"), "Milch")
        XCTAssertEqual(IngredientNameNormalizer.displayName("Weizenmehl 550"), "Weizenmehl 550")
    }

    func testComparisonKeyIgnoresCaseAndAccents() {
        XCTAssertEqual(IngredientNameNormalizer.comparisonKey("Crème fraîche"),
                       IngredientNameNormalizer.comparisonKey("creme FRAICHE"))
    }

    // MARK: The step that matters now (CurrentStepRuleTests in the app)

    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func minutes(_ offset: Int) -> Date {
        now.addingTimeInterval(TimeInterval(offset * 60))
    }

    func testDueStepComesFirst() throws {
        let found = try XCTUnwrap(CurrentStepRule.currentStep(in: [minutes(-20), minutes(40)], at: now, date: { $0 }))
        XCTAssertEqual(found.step, minutes(-20))
        XCTAssertTrue(found.isDue)
    }

    func testOldDueStepIsLetGo() throws {
        let found = try XCTUnwrap(CurrentStepRule.currentStep(in: [minutes(-60), minutes(40)], at: now, date: { $0 }))
        XCTAssertEqual(found.step, minutes(40))
        XCTAssertFalse(found.isDue)
    }

    // MARK: Backup files — JSON written by the iOS app

    func testBackupFromTheIPhoneReads() throws {
        let file = try RecipeImport.decodeFile(Data(ProbeRecipe.sampleBackup.utf8))
        let recipe = try XCTUnwrap(file.recipes.first)

        XCTAssertEqual(recipe.name, "Weißbrot")
        XCTAssertEqual(recipe.image, Data([0x01, 0x02, 0x03]))
        XCTAssertEqual(recipe.totalWeight, 830.5)
        XCTAssertEqual(recipe.components.first?.ingredients.map(\.unit), ["g", nil])
        XCTAssertEqual(recipe.instructions.map(\.step), [1, 3])
        XCTAssertNil(recipe.instructions.last?.componentName)
    }

    func testBackupRoundTrip() throws {
        let file = try RecipeImport.decodeFile(Data(ProbeRecipe.sampleBackup.utf8))
        XCTAssertEqual(try RecipeImport.decodeFile(try file.encoded()), file)
    }

    func testNewerBackupIsRefused() throws {
        var file = try RecipeImport.decodeFile(Data(ProbeRecipe.sampleBackup.utf8))
        file.formatVersion = RecipeExportFile.currentFormatVersion + 1
        XCTAssertThrowsError(try RecipeImport.decodeFile(try file.encoded())) { error in
            XCTAssertEqual(error as? RecipeImportError, .unsupportedFormatVersion)
        }
    }

    // MARK: Observation

    func testObservableModelComputes() {
        let recipe = ProbeRecipe(name: "Test", ingredients: [])
        recipe.targetDoughTemperature = 26
        recipe.usesPreferment = true
        XCTAssertEqual(recipe.waterTemperature, 26 * 4 - (21 + 20 + 1 + 22))
    }
}
