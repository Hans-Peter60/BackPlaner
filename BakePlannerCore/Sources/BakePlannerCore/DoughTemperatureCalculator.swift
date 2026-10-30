//
//  DoughTemperatureCalculator.swift
//  BakePlannerCore
//
//  The water temperature needed to hit a target dough temperature, by the
//  baker's standard "Desired Dough Temperature" method: the sum of every
//  ingredient's temperature, weighted by a multiplier, equals the target
//  times that same multiplier. A straight dough sums three temperatures
//  (room, flour, water); a dough that folds in a preferment sums four, the
//  preferment's own temperature joining the other three.
//

import Foundation

public enum DoughTemperatureCalculator {

    /// How far outside a normal range the required water temperature falls.
    /// Below freezing needs ice water measured out specially; above a boil
    /// risks killing the yeast before the dough is even mixed.
    public enum Feasibility: Sendable {
        case ok
        case tooCold
        case tooHot
    }

    public static let minimumFeasibleWaterTemperature = 1
    public static let maximumFeasibleWaterTemperature = 50

    /// The water temperature (°C) that hits `targetDoughTemperature`, given
    /// the other ingredients' temperatures and the friction factor the mixer
    /// contributes while kneading. `prefermentTemperature` is `nil` for a
    /// straight dough, which drops the preferment term and uses the
    /// three-ingredient multiplier instead of four.
    public static func waterTemperature(
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

    public static func feasibility(ofWaterTemperature celsius: Int) -> Feasibility {
        if celsius < minimumFeasibleWaterTemperature { return .tooCold }
        if celsius > maximumFeasibleWaterTemperature { return .tooHot }
        return .ok
    }
}
