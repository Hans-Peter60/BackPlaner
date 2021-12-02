//
//  Rational.swift
//  BackPlaner
//
//  Created by Hans-Peter Müller on 05.11.21.
//

import Foundation

struct Rational {
    
    static func decimalPlace(_ nDouble:Double, _ decimalPlace:Int) -> String {
        
        var numberString = ""
        var numberDouble = nDouble
        var numberInt = 1
        let factor = Double(decimalPlace)

        numberDouble *= factor
        numberInt = Int(numberDouble)
        numberDouble = Double(numberInt) / factor
        numberString = String(numberDouble)
        numberInt = Int(numberDouble)

        if Double(numberInt) == numberDouble {
            numberString = String(numberInt)
        }
        return numberString
    }
    
    static func greatestCommonDivisor(_ a: Int, _ b: Int) -> Int {
        
        // GCD(0, b) = b
        if a == 0 { return b }
        
        // GCD(a, 0) = a
        if b == 0 { return a }
        
        // Otherwise, GCD(a, b) = GCD(b, remainder)
        return greatestCommonDivisor(b, a % b)
    }
    
    static func displayHoursMinutes(_ d:Int) -> String {
        var m = d
        if m == 0 {
            return("")
        } else {
            if m < 60 {
                return("\(d) m")
            } else {
                let h = Int(m/60)
                m -= h*60
                if m > 0 {
                    return("\(h)h \(m) m")
                } else {
                    return("\(h) h")
                }
            }
        }
    }
    
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
            instruction.date = Calendar.current.date(byAdding: .minute, value: instruction.startTime ?? 0, to: startDate)!
        }
        
        GlobalVariables.totalDuration = calcDauer
        
        return instructions
    }
}
