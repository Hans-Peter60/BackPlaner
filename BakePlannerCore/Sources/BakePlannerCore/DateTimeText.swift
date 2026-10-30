//
//  DateTimeText.swift
//  BakePlannerCore
//
//  A date with its time, or a time alone, the way the app writes them in
//  plan messages and reminders: short, in the in-app language.
//

import Foundation

public struct DateCalculation {
    
    public let formatter = DateFormatter()

    public init() {}
    
    public func calculateDateTime(dT: Date) -> String {
        
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        formatter.locale = AppSettings.locale
        return formatter.string(from: dT)
    }
}

public struct TimeCalculation {
    
    public let formatter = DateFormatter()

    public init() {}
    
    public func calculateTime(t: Date) -> String {
        
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        formatter.locale = AppSettings.locale
        return formatter.string(from: t)
    }
}
