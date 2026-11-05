//
//  DoughWeightFromTinTests.swift
//  BakePlannerCoreTests
//

import Foundation
import Testing
@testable import BakePlannerCore

@Suite("Dough weight from a tin or a basket")
struct DoughWeightFromTinTests {

    @Test("A loaf tin's volume and the dough it takes by dough type")
    func loafTin() {
        let volume = DoughWeightFromTin.volumeMilliliters(lengthCm: 30, widthCm: 11, heightCm: 8)
        #expect(volume == 2640)
        #expect(DoughWeightFromTin.doughGrams(volumeMilliliters: volume, fillFactor: DoughWeightFromTin.DoughType.mixed.fillFactor) == 1190)
        #expect(DoughWeightFromTin.doughGrams(volumeMilliliters: volume, fillFactor: DoughWeightFromTin.DoughType.lightWheat.fillFactor) == 1000)
        #expect(DoughWeightFromTin.doughGrams(volumeMilliliters: volume, fillFactor: DoughWeightFromTin.DoughType.ryeWholeGrain.fillFactor) == 1370)
        // No tin, no dough.
        #expect(DoughWeightFromTin.doughGrams(volumeMilliliters: 0, fillFactor: 0.45) == 0)
        #expect(DoughWeightFromTin.volumeMilliliters(lengthCm: -5, widthCm: 10, heightCm: 8) == 0)
    }

    @Test("A round tin by diameter and height")
    func roundTin() {
        let volume = DoughWeightFromTin.volumeMilliliters(diameterCm: 20, heightCm: 8)
        #expect(abs(volume - 2513.3) < 0.1)
        #expect(DoughWeightFromTin.doughGrams(volumeMilliliters: volume, fillFactor: 0.45) == 1130)
    }

    @Test("A basket's nominal weight: the table, in between, and beyond")
    func basketNominal() {
        #expect(DoughWeightFromTin.basketNominalGrams(shape: .round, measureCm: 22) == 1000)
        #expect(DoughWeightFromTin.basketNominalGrams(shape: .round, measureCm: 18) == 500)
        #expect(DoughWeightFromTin.basketNominalGrams(shape: .round, measureCm: 21) == 900)
        #expect(DoughWeightFromTin.basketNominalGrams(shape: .round, measureCm: 30) == 2350)
        #expect(DoughWeightFromTin.basketNominalGrams(shape: .round, measureCm: 15) == 150)
        #expect(DoughWeightFromTin.basketNominalGrams(shape: .oval, measureCm: 28) == 1000)
        #expect(DoughWeightFromTin.basketNominalGrams(shape: .oval, measureCm: 30) == 1250)
        #expect(DoughWeightFromTin.basketNominalGrams(shape: .oval, measureCm: 0) == 0)
    }

    @Test("A basket takes more rye and less airy wheat than its rating says")
    func basketByDough() {
        #expect(DoughWeightFromTin.basketDoughGrams(nominalGrams: 1000, doughType: .mixed) == 1000)
        #expect(DoughWeightFromTin.basketDoughGrams(nominalGrams: 1000, doughType: .ryeWholeGrain) == 1200)
        #expect(DoughWeightFromTin.basketDoughGrams(nominalGrams: 1000, doughType: .lightWheat) == 900)
        #expect(DoughWeightFromTin.basketDoughGrams(nominalGrams: 750, doughType: .lightWheat) == 680)
    }

    @Test("The sizes are listed smallest first in every measure")
    func sizesAreOrdered() {
        let sizes = DoughWeightFromTin.basketSizes
        #expect(sizes.map(\.nominalGrams) == sizes.map(\.nominalGrams).sorted())
        #expect(sizes.map(\.roundDiameterCm) == sizes.map(\.roundDiameterCm).sorted())
        #expect(sizes.map(\.ovalLengthCm) == sizes.map(\.ovalLengthCm).sorted())
    }
}
