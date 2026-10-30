//
//  DoughTemperatureCalculator.swift
//  BakePlannerProbe — copy of BackPlaner/Utilities/DoughTemperatureCalculator.swift
//
//  The water temperature needed to hit a target dough temperature, by the
//  baker's standard "Desired Dough Temperature" method: the sum of every
//  ingredient's temperature, weighted by a multiplier, equals the target
//  times that same multiplier. A straight dough sums three temperatures
//  (room, flour, water); a dough that folds in a preferment sums four, the
//  preferment's own temperature joining the other three.
//

import Foundation

enum DoughTemperatureCalculator {

    /// How far outside a normal range the required water temperature falls.
    /// Below freezing needs ice water measured out specially; above a boil
    /// risks killing the yeast before the dough is even mixed.
    enum Feasibility {
        case ok
        case tooCold
        case tooHot
    }

    static let minimumFeasibleWaterTemperature = 1
    static let maximumFeasibleWaterTemperature = 50

    /// The water temperature (°C) that hits `targetDoughTemperature`, given
    /// the other ingredients' temperatures and the friction factor the mixer
    /// contributes while kneading. `prefermentTemperature` is `nil` for a
    /// straight dough, which drops the preferment term and uses the
    /// three-ingredient multiplier instead of four.
    static func waterTemperature(
        targetDoughTemperature: Int,
        roomTemperature: Int,
        flourTemperature: Int,
        frictionFactor: Int,
        prefermentTemperature: Int?
    ) -> Int {
        let multiplier = prefermentTemperature == nil ? 3 : 4
        let knownSum = roomTemperature + flourTemperature + frictionFactor + (prefermentTemperature ?? 0)
        return targetDoughTemperature * multiplier - knownSum
    }

    static func feasibility(ofWaterTemperature celsius: Int) -> Feasibility {
        if celsius < minimumFeasibleWaterTemperature { return .tooCold }
        if celsius > maximumFeasibleWaterTemperature { return .tooHot }
        return .ok
    }
}
