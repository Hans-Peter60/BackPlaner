//
//  DoughTemperatureCalculatorTests.swift
//  BakePlannerCoreTests
//

import Testing
@testable import BakePlannerCore

@Suite("The water temperature needed to hit a target dough temperature")
struct DoughTemperatureCalculatorTests {

    @Test("A straight dough sums three temperatures, weighted by three")
    func straightDoughUsesTheThreeMultiplier() {
        let water = DoughTemperatureCalculator.waterTemperature(
            targetDoughTemperature: 24,
            roomTemperature: 21,
            flourTemperature: 21,
            frictionFactor: 1,
            prefermentTemperature: nil
        )
        #expect(water == 24 * 3 - (21 + 21 + 1))
    }

    @Test("A dough with a preferment sums four temperatures, weighted by four")
    func doughWithPrefermentUsesTheFourMultiplier() {
        let water = DoughTemperatureCalculator.waterTemperature(
            targetDoughTemperature: 24,
            roomTemperature: 21,
            flourTemperature: 21,
            frictionFactor: 1,
            prefermentTemperature: 21
        )
        #expect(water == 24 * 4 - (21 + 21 + 1 + 21))
    }

    @Test("A higher friction factor lowers the water temperature by the same amount")
    func frictionFactorOffsetsTheWaterTemperature() {
        let lowFriction = DoughTemperatureCalculator.waterTemperature(
            targetDoughTemperature: 24, roomTemperature: 21, flourTemperature: 21,
            frictionFactor: 1, prefermentTemperature: nil
        )
        let highFriction = DoughTemperatureCalculator.waterTemperature(
            targetDoughTemperature: 24, roomTemperature: 21, flourTemperature: 21,
            frictionFactor: 4, prefermentTemperature: nil
        )
        #expect(lowFriction - highFriction == 3)
    }

    @Test("A water temperature within the normal range is feasible")
    func normalRangeIsFeasible() {
        #expect(DoughTemperatureCalculator.feasibility(ofWaterTemperature: 25) == .ok)
        #expect(DoughTemperatureCalculator.feasibility(ofWaterTemperature: DoughTemperatureCalculator.minimumFeasibleWaterTemperature) == .ok)
        #expect(DoughTemperatureCalculator.feasibility(ofWaterTemperature: DoughTemperatureCalculator.maximumFeasibleWaterTemperature) == .ok)
    }

    @Test("Below the minimum reads as needing colder-than-ice water")
    func belowMinimumIsTooCold() {
        #expect(DoughTemperatureCalculator.feasibility(ofWaterTemperature: 0) == .tooCold)
        #expect(DoughTemperatureCalculator.feasibility(ofWaterTemperature: -10) == .tooCold)
    }

    @Test("Above the maximum reads as needing unreasonably hot water")
    func aboveMaximumIsTooHot() {
        #expect(DoughTemperatureCalculator.feasibility(ofWaterTemperature: 51) == .tooHot)
        #expect(DoughTemperatureCalculator.feasibility(ofWaterTemperature: 90) == .tooHot)
    }
}
