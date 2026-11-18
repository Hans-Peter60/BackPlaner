//
//  PlausibleValues.swift
//  BakePlannerCore
//
//  The ranges a recipe's numbers can sensibly take, and conversions that
//  never trap. Swift stops the app when a Double that is NaN, infinite or
//  beyond Int's range is turned into an Int, and when Int arithmetic
//  overflows — on Android too, which runs the same native code. Numbers
//  come from typing, web pages, photos, backups and public recipes, any of
//  which can hold "99999999999999999999 Minuten" or NaN; stored once, such
//  a value crashed the recipe every time it was opened. Every number that
//  enters the app is brought into these ranges where it is read.
//

import Foundation

public enum Plausible {

    /// Sixty days: the stollen ripens three weeks, nothing in a bakery
    /// takes longer.
    public static let maxMinutes = 60 * 24 * 60

    /// A tonne of dough, far beyond any home or bakery batch.
    public static let maxGrams = 1_000_000.0

    /// Oven, room and dough temperatures in °C or °F; a freezer at -50,
    /// a pizza oven in Fahrenheit at 900.
    public static let temperatureRange = -50.0...900.0

    /// Numerator or denominator of an amount such as "1/2 TL".
    public static let maxFractionPart = 1_000

    /// Minutes within 0...maxMinutes; NaN and negative are 0.
    public static func minutes(_ value: Double) -> Int {
        guard value.isFinite, value > 0 else { return 0 }
        return Int(min(value, Double(maxMinutes)).rounded())
    }

    public static func minutes(_ value: Int) -> Int {
        min(max(value, 0), maxMinutes)
    }

    /// Grams within 0...maxGrams; NaN and negative are 0.
    public static func grams(_ value: Double) -> Double {
        guard value.isFinite, value > 0 else { return 0 }
        return min(value, maxGrams)
    }

    /// A temperature within `temperatureRange`, nil when it is not a number.
    public static func temperature(_ value: Double) -> Double? {
        guard value.isFinite else { return nil }
        return min(max(value, temperatureRange.lowerBound), temperatureRange.upperBound)
    }

    /// A part of a fraction within 0...maxFractionPart.
    public static func fractionPart(_ value: Int) -> Int {
        min(max(value, 0), maxFractionPart)
    }

    /// A step number as a recipe means it: to the hundredth, within 0…999,
    /// 1 when it is not a number. Moving fold steps up by one turned 5.2
    /// into 4.199999999999999, which the step table cut to "4.1" — beside a
    /// real 4.1. Hundredths, not tenths: a cloud import numbers more than
    /// nine preferments 1.01, 1.02 ….
    public static func stepNumber(_ value: Double) -> Double {
        guard value.isFinite else { return 1 }
        return (min(max(value, 0), 999) * 100).rounded() / 100
    }

    /// The nearest Int to any Double: NaN is 0, values beyond ±10¹⁵ are
    /// held there. For showing a number, where trapping is never right.
    public static func roundedInt(_ value: Double) -> Int {
        guard value.isFinite else { return 0 }
        return Int(min(max(value, -1e15), 1e15).rounded())
    }
}

// MARK: - Files

extension RecipeExportFile {

    /// The file with every number of its recipes and pantry in a plausible
    /// range: a backup or shared file is read as it comes, and a weight of
    /// 10²⁰ g or a step of Int.max minutes, once stored and synced to
    /// iCloud, crashed the recipe on every device each time it was opened.
    /// Bakes and feedings are brought into range by their facts'
    /// `normalized`, as every store keeps them. The format is unchanged.
    public var sanitized: RecipeExportFile {
        var file = self
        file.recipes = recipes.map(\.sanitized)
        file.pantry = pantry?.map { item in
            var item = item
            item.amount = Plausible.grams(item.amount)
            return item
        }
        return file
    }
}

extension RecipeExportData {

    public var sanitized: RecipeExportData {
        var recipe = self
        recipe.prepTime = Plausible.minutes(prepTime)
        recipe.totalWeight = Plausible.grams(totalWeight)
        recipe.rating = min(max(rating, 0), 5)
        recipe.recurrenceIntervalDays = min(max(recurrenceIntervalDays, 0), 366)
        recipe.components = components.map { component in
            var component = component
            component.ingredients = component.ingredients.map { ingredient in
                var ingredient = ingredient
                ingredient.weight = Plausible.grams(ingredient.weight)
                ingredient.normWeight = Plausible.grams(ingredient.normWeight)
                ingredient.num = Plausible.fractionPart(ingredient.num)
                ingredient.denom = Plausible.fractionPart(ingredient.denom)
                return ingredient
            }
            return component
        }
        recipe.instructions = instructions.map { instruction in
            var instruction = instruction
            instruction.step = Plausible.stepNumber(instruction.step)
            instruction.duration = Plausible.minutes(instruction.duration)
            instruction.startTime = Plausible.minutes(instruction.startTime)
            instruction.minDuration = instruction.minDuration.map(Plausible.minutes)
            instruction.maxDuration = instruction.maxDuration.map(Plausible.minutes)
            instruction.ovenTemperature = instruction.ovenTemperature.flatMap { Plausible.temperature(Double($0)).map(Int.init) }
            instruction.ovenFallingTemperature = instruction.ovenFallingTemperature.flatMap { Plausible.temperature(Double($0)).map(Int.init) }
            return instruction
        }
        return recipe
    }
}
