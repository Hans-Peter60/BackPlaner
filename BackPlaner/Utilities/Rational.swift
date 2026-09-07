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
        let normalizedUnit = unit.trimmingCharacters(in: .whitespacesAndNewlines).localizedLowercase
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
    static func getPortion(unit:String, weight: Double, num:Int, denom:Int, targetServings:Int) -> String {
        
        var portion            = ""
        var numerator          = num
        var denominator        = denom
        var wholePortions      = 0
        let compTargetServings = Double(targetServings) / 2
        let recipeServings     = 1
        
        if weight == 0 && (num == 0 || num == denom) {
            return "" }
        else {
            if weight == 0 {
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
                portion = Rational.decimalPlace((Double(weight) / (Double(recipeServings)) * compTargetServings), 1000)
            }
            
            if unit > "" {
                
                var u = unit
                
                // If we need to pluralize
                if wholePortions > 1 {
                    
                    // Calculate appropriate suffix
                    if u == "Tasse" || u == "Messerspitze" || u == "Prise" || u == "Scheibe" { u += "n" }
                }
                return portion + " " + u + " "
            }
            return portion + " "
        }
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
    
    // MARK: CalculateStartTimes
    static func calculateStartTimes(_ instructions: [InstructionFB], _ startDate: Date) -> [InstructionFB] {
        
        var times: [Int: Int] = [0:0]
        
        for i in instructions {
            // check if main step
            if i.step == Double(Int(i.step)) {
                times[Int(i.step)] = i.duration
            }
            else {
                if i.duration > (times[Int(i.step)] ?? 0) {
                    times[Int(i.step)] = i.duration
                }
            }
        }

        var i = 0
        var calcDauer = 0

        for instruction in instructions {
            // check for change to next main step
            if Int(instruction.step) > i {
                i += 1
                calcDauer += times[Int(instruction.step)] ?? 0
            }
            instruction.startTime = calcDauer - instruction.duration
            instruction.date = Calendar.current.date(byAdding: .minute, value: instruction.startTime ?? 0, to: startDate) ?? startDate
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
