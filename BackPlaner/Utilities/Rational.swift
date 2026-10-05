//
//  Rational.swift
//  PetersBackPlaner
//
//  Created by Hans-Peter Müller on 05.11.21.
//

import Foundation
import SwiftUI


struct CalcIngredientWeight {
    
    // MARK: CalcIngredientsWeight
    func calcIngredientWeight(weight:Double, unit:String, name:String, num:Int, denom:Int) -> Double {
        // "tsp" or "c. à s." from an imported recipe count as the bundled
        // TL and EL; they used to fall through and be read as grams.
        let knownUnit = UnitLocalizer.canonicalAbbreviation(for: unit) ?? unit
        let normalizedUnit = knownUnit.trimmingCharacters(in: .whitespacesAndNewlines).localizedLowercase
        let normalizedName = name.localizedLowercase
        let amount: Double

        if weight > 0 {
            amount = weight
        } else if denom != 0 {
            amount = Double(num) / Double(denom)
        } else {
            amount = 0
        }

        guard !normalizedUnit.isEmpty else {
            return amount
        }

        for unitSet in GlobalVariables.unitSets {
            let unitName = unitSet.name.localizedLowercase
            let abbreviation = unitSet.abbreviation.localizedLowercase

            if normalizedUnit.contains(unitName) || normalizedUnit == abbreviation {
                var calcWeight = amount * unitSet.factor

                if unitSet.baseUnit == "ml" {
                    for (ingredient, factor) in GlobalVariables.specialWeights {
                        if normalizedName.contains(ingredient) {
                            calcWeight *= factor
                            break
                        }
                    }
                }

                return calcWeight
            }
        }

        return amount
    }
}

class Rational {

    // MARK: GetPortion
    /// The amount at a serving size given in half steps (2 = the recipe as
    /// stored). Kept for the callers that still think in those steps.
    static func getPortion(unit:String, weight: Double, num:Int, denom:Int, targetServings:Int,
                           unitStyle: UnitLocalizer.Style = .abbreviation) -> String {
        getPortion(unit: unit, weight: weight, num: num, denom: denom, scale: Double(targetServings) / 2,
                   unitStyle: unitStyle)
    }

    /// The amount at a free scale factor — 1.0 is the recipe as stored, 1.37
    /// is what a target dough weight of 1,370 g on a 1,000 g recipe yields.
    ///
    /// Weights simply multiply. A fraction ("1/2 Würfel") keeps its fraction
    /// arithmetic as long as the scale is a half step, since "3/4 Würfel"
    /// reads better than "0.75 Würfel"; at any other scale it becomes a
    /// decimal, because "1 13/50 Würfel" helps nobody.
    ///
    /// The unit appears in the app's language (see UnitLocalizer); `.name`
    /// spells it out, for reading aloud.
    static func getPortion(unit:String, weight: Double, num:Int, denom:Int, scale: Double,
                           unitStyle: UnitLocalizer.Style = .abbreviation) -> String {

        var portion            = ""
        var numerator          = num
        var denominator        = denom
        var wholePortions      = 0
        let compTargetServings = scale
        let recipeServings     = 1
        let halfSteps          = scale * 2
        let isHalfStep         = abs(halfSteps.rounded() - halfSteps) < 0.0001
        let targetServings     = Int(halfSteps.rounded())

        if weight == 0 && (num == 0 || num == denom) {
            return "" }
        else {
            if weight == 0 && !isHalfStep && denom != 0 {
                portion = Rational.formattedAmount(Double(num) / Double(denom) * scale)
            } else if weight == 0 {
                // Get a single serving size by multiplying denominator by the recipe servings
                denominator *= (recipeServings * 2)
                
                // Get target portion by multiplying numerator by target servings
                numerator *= targetServings
                
                // Reduce fraction by greatest common divisor
                let divisor = Rational.greatestCommonDivisor(numerator, denominator)
                numerator /= divisor
                denominator /= divisor
                
                // Get the whole portion if numerator > denominator
                if numerator >= denominator {
                    
                    // Calculated whole portions
                    wholePortions = numerator / denominator
                    
                    // Calculate the remainder
                    numerator = numerator % denominator
                    
                    // Assign to portion string
                    portion += String(wholePortions)
                }
                
                // Express the remainder as a fraction
                if numerator > 0 {
                    
                    // Assign remainder as fraction to the portion string
                    portion += wholePortions > 0 ? " " : ""
                    portion += "\(numerator)/\(denominator)"
                }
            } else {
                portion = Rational.formattedAmount(Double(weight) / Double(recipeServings) * compTargetServings)
            }
            
            if unit > "" {

                let shownAmount = weight > 0 ? weight * scale
                    : (denom != 0 ? Double(num) / Double(denom) * scale : 0)
                var u = UnitLocalizer.display(unit, amount: shownAmount, style: unitStyle)

                // Older recipes store the German name ("Tasse"), which German
                // shows unchanged; it still needs its plural.
                if u == unit && wholePortions > 1 {
                    
                    // Calculate appropriate suffix
                    if u == "Tasse" || u == "Messerspitze" || u == "Prise" || u == "Scheibe" { u += "n" }
                }
                return portion + " " + u + " "
            }
            return portion + " "
        }
    }

    // MARK: FormattedAmount
    /// A scaled amount as a baker reads it off the scale: whole grams from
    /// 10 upwards, one decimal below that ("1,5 EL", "2,5 g Hefe"), with the
    /// decimal separator of the app's language. Scaling used to produce
    /// "82.582 g", which nobody can weigh and which wrapped the columns.
    static func formattedAmount(_ value: Double) -> String {
        let rounded = value >= 10 ? value.rounded() : (value * 10).rounded() / 10
        return rounded.formatted(
            .number
                .precision(.fractionLength(0...1))
                .grouping(.never)
                .locale(AppSettings.locale)
        )
    }

    // MARK: DecimalPlace
    static func decimalPlace(_ nDouble:Double, _ decimalPlace:Int) -> String {
        
        var numberString = ""
        var numberDouble = nDouble
        var numberInt    = 1
        let factor       = Double(decimalPlace)

        numberDouble *= factor
        numberInt     = Int(numberDouble)
        numberDouble  = Double(numberInt) / factor
        numberString  = String(numberDouble)
        numberInt     = Int(numberDouble)

        if Double(numberInt) == numberDouble {
            
            numberString = String(numberInt)
        }
        if numberString == "0" {
            
            numberString = ""
        }
        
        return numberString
    }
    
    // MARK: GreatestCommonDivisor
    static func greatestCommonDivisor(_ a: Int, _ b: Int) -> Int {
        
        // GCD(0, b) = b
        if a == 0 { return b }
        
        // GCD(a, 0) = a
        if b == 0 { return a }
        
        // Otherwise, GCD(a, b) = GCD(b, remainder)
        return greatestCommonDivisor(b, a % b)
    }
    
    // MARK: DisplayHoursMinutes
    static func displayHoursMinutes(_ d:Int) -> String {
        var m = d
        if m == 0 {
            return("")
        } else {
            if m < 60 {
                return("\(d)m")
            } else {
                let h = Int(m/60)
                m -= h*60
                if m > 0 {
                    return("\(h)h \(m)m")
                } else {
                    return("\(h)h 00m")
                }
            }
        }
    }
    
    // MARK: ComponentDependency
    /// A component and the components it uses up, as far as the scheduling of
    /// parallel preparation steps needs to know. A row without a weight whose
    /// name begins with "gesamte" ("gesamte Sauerteigstufe 1") is such a use.
    struct ComponentDependency {
        let name: String
        let requires: [String]

        private static func requirements(
            of ingredientNames: [String],
            componentNames: [String],
            excluding ownName: String
        ) -> [String] {
            ingredientNames.compactMap { ingredientName in
                let value = ingredientName.folding(
                    options: [.caseInsensitive, .diacriticInsensitive],
                    locale: Locale(identifier: "de_DE")
                )
                guard value.hasPrefix("gesamte") else { return nil }
                return componentNames.first { candidate in
                    candidate != ownName && value.contains(candidate.folding(
                        options: [.caseInsensitive, .diacriticInsensitive],
                        locale: Locale(identifier: "de_DE")
                    ))
                }
            }
        }

        static func from(_ components: [ComponentFB]) -> [ComponentDependency] {
            let names = components.map { $0.name }
            return components.map { component in
                ComponentDependency(
                    name: component.name,
                    requires: requirements(
                        of: component.ingredients.filter { $0.weight == 0 }.map { $0.name },
                        componentNames: names,
                        excluding: component.name
                    )
                )
            }
        }

        static func from(_ components: [Component]) -> [ComponentDependency] {
            let names = components.map { $0.name }
            return components.map { component in
                ComponentDependency(
                    name: component.name,
                    requires: requirements(
                        of: component.ingredientsArray.filter { $0.weight == 0 }.map { $0.name },
                        componentNames: names,
                        excluding: component.name
                    )
                )
            }
        }
    }

    // MARK: CalculateStartTimes
    /// Minutes between the starts of parallel component preparations that do
    /// not wait for one another: the handling time for mixing one pre-dough
    /// before the next.
    static let preparationStaggerMinutes = 5

    /// Places every step on the timeline and returns the instructions with their
    /// `startTime` in minutes after `startDate`.
    ///
    /// Steps that share a main step number run in parallel. Two kinds of them
    /// are scheduled differently:
    ///
    /// - A **component preparation** ("… die Komponente Sauerteigstufe 2 …")
    ///   begins as early as it can — at the start of its group, or, when it uses
    ///   up another component, the moment that component is finished. So the
    ///   first step starts exactly at the chosen start, a second sourdough stage
    ///   waits for the first one, and a soaker is always ready before the main
    ///   dough needs it. Preparations that wait for nothing are mixed one after
    ///   the other, `preparationStaggerMinutes` apart in step order: nobody
    ///   weighs four pre-doughs at the same minute, and their reminders should
    ///   not arrive at the same minute either.
    /// - Every other parallel step keeps ending together with its group, which
    ///   is what a folding intervention inside a resting step needs.
    ///
    /// Passing no `dependencies` keeps the previous behaviour for every step.
    static func calculateStartTimes(
        _ instructions: [InstructionFB],
        _ startDate: Date,
        dependencies: [ComponentDependency] = []
    ) -> [InstructionFB] {

        let groups = Dictionary(grouping: instructions) { Int($0.step) }
        var calcDauer = 0

        for stepNumber in groups.keys.sorted() {
            let group = (groups[stepNumber] ?? []).sorted { $0.step < $1.step }
            let groupStart = calcDauer

            // Which of these steps prepares a component, and in which order can
            // they run? A preparation step names its component itself, so the
            // plan does not depend on the step's wording — and stays correct
            // when the app language differs from the one it was imported in.
            var preparations: [(instruction: InstructionFB, dependency: ComponentDependency)] = []
            var parallel: [InstructionFB] = []
            for instruction in group {
                if let name = instruction.componentName,
                   let dependency = dependencies.first(where: { $0.name == name }) {
                    preparations.append((instruction, dependency))
                } else {
                    parallel.append(instruction)
                }
            }

            var endByComponent: [String: Int] = [:]
            let preparedNames = Set(preparations.map { $0.dependency.name })
            var pending = preparations
            var independentPreparations = 0
            while !pending.isEmpty {
                var deferred: [(instruction: InstructionFB, dependency: ComponentDependency)] = []
                for entry in pending {
                    // Only components prepared in this group can be waited for.
                    let required = entry.dependency.requires.filter { preparedNames.contains($0) }
                    guard required.allSatisfy({ endByComponent[$0] != nil }) else {
                        deferred.append(entry)
                        continue
                    }
                    let start: Int
                    if let prerequisiteEnd = required.compactMap({ endByComponent[$0] }).max() {
                        start = prerequisiteEnd
                    } else {
                        start = groupStart + independentPreparations * preparationStaggerMinutes
                        independentPreparations += 1
                    }
                    entry.instruction.startTime = start
                    endByComponent[entry.dependency.name] = start + entry.instruction.duration
                }
                // A circular reference must not stall the plan.
                if deferred.count == pending.count {
                    for entry in deferred {
                        entry.instruction.startTime = groupStart
                        endByComponent[entry.dependency.name] = groupStart + entry.instruction.duration
                    }
                    break
                }
                pending = deferred
            }

            let preparationEnd = endByComponent.values.max() ?? groupStart
            let parallelEnd = groupStart + (parallel.map { $0.duration }.max() ?? 0)
            let groupEnd = max(preparationEnd, parallelEnd)

            for instruction in parallel {
                instruction.startTime = groupEnd - instruction.duration
            }

            calcDauer = groupEnd
        }

        for instruction in instructions {
            instruction.date = Calendar.current.date(
                byAdding: .minute,
                value: instruction.startTime ?? 0,
                to: startDate
            ) ?? startDate
        }

        GlobalVariables.totalDuration = calcDauer

        return instructions
    }
}

// MARK: DateFormat
struct DateFormat {
    
    let formatter = DateFormatter()
    
    func calculateDate(dT: Date) -> String {
        
        formatter.dateStyle = .short
        formatter.timeStyle = .none
        formatter.locale = AppSettings.locale
        return formatter.string(from: dT)
    }
}
