//
//  GlobalVariablesCore.swift
//  BackPlaner
//
//  The app-wide values the calculation logic reads — units, planning
//  settings, the date range — and its logging, needing nothing but
//  Foundation. GlobalVariables.swift adds the parts tied to UIKit and
//  SwiftUI (the downloaded pictures, the grid layouts).
//

import Foundation
#if canImport(os)
import os
#endif

/// Central logging for the app. Replaces scattered print() calls with
/// unified os.Logger output that can be filtered by category in Console.
enum AppLog {
    private static let subsystem = Bundle.main.bundleIdentifier ?? "BackPlaner"

    static let data          = Logger(subsystem: subsystem, category: "data")
    static let firebase      = Logger(subsystem: subsystem, category: "firebase")
    static let notifications = Logger(subsystem: subsystem, category: "notifications")
    static let planning      = Logger(subsystem: subsystem, category: "planning")
    static let persistence   = Logger(subsystem: subsystem, category: "persistence")
    static let shoppingCart  = Logger(subsystem: subsystem, category: "shoppingCart")
    /// Reading recipes from photographed pages. What Vision returns differs
    /// between the simulator and a device for the same image, so a defect that
    /// only shows on the phone can only be measured through the phone's log.
    static let recipeImport  = Logger(subsystem: subsystem, category: "recipeImport")
    /// The Pro purchase: the remote configuration, StoreKit, the decision.
    static let store         = Logger(subsystem: subsystem, category: "store")
}

#if !canImport(os)
/// Where the system log does not exist, the same calls write to standard
/// output, debug messages excepted.
struct Logger {
    let subsystem: String
    let category: String

    func debug(_ message: String) {}
    func info(_ message: String) { write("info", message) }
    func notice(_ message: String) { write("notice", message) }
    func error(_ message: String) { write("error", message) }
    func fault(_ message: String) { write("fault", message) }

    private func write(_ level: String, _ message: String) {
        print("[\(category)] \(level): \(message)")
    }
}
#endif

struct GlobalVariables {
    
    static var tabSelection = 0
    
    static var bakeListTab  = 0
    static var listTab      = 1
    static var historyTab   = 2
    static var addRecipeTab = 3

    /// The units the app ships with, read once from the bundled UnitSets.json.
    static let bundledUnitSets = DataService.getUnitSets()

    /// Every unit the app knows: the bundled ones plus whatever the user added
    /// in the settings. Bundled come first on purpose — units are looked up
    /// with `first(where:)`, so this guarantees a custom entry can never take
    /// over "g" or "ml" even if it somehow got past the duplicate check.
    static var unitSets: [UnitSetFB] { bundledUnitSets + customUnitSets() }

    /// The units the user added in the settings. The app installs the source
    /// when it starts (BackPlanerApp); until then, and wherever no app is
    /// around, there are none.
    static var customUnitSets: () -> [UnitSetFB] = { [] }
    
    static var noImage      = "no-image-icon-23494"
    static var detailView: Bool { AppSettings.storedUseDetailView }
    
    static var step         = 1
    static var preheatTime: Int { AppSettings.storedPreheatTime }
    static var startHeating: String { AppSettings.storedStartHeatingText }
    static var bakeEnd: String { AppSettings.storedBakeEndText }
    static var dayStart: Int { AppSettings.storedDayStart }
    static var dayEnd: Int { AppSettings.storedDayEnd }
    static var bakePause: Int { AppSettings.storedBakePause }
    static var ovenCount: Int { AppSettings.storedOvenCount }

    static var totalDuration  = 0
    static var dateTimePicker = Date()

    /// The span a date picker offers, counted from the start of the day `now`
    /// falls on. Worked out on every call rather than from a date captured at
    /// launch, so an app left running past midnight does not keep offering
    /// yesterday. Falls back to the day itself where the calendar cannot add
    /// the offset, instead of trapping.
    nonisolated static func dateRange(from start: DateComponents = DateComponents(),
                                      to end: DateComponents,
                                      around now: Date = Date(),
                                      calendar: Calendar = .current) -> ClosedRange<Date> {
        let today = calendar.startOfDay(for: now)
        let lower = calendar.date(byAdding: start, to: today) ?? today
        let upper = calendar.date(byAdding: end, to: today) ?? today
        return min(lower, upper) ... max(lower, upper)
    }

    /// Today until the same day next year, the window for planning a bake.
    nonisolated static func planningDateRange(around now: Date = Date()) -> ClosedRange<Date> {
        dateRange(to: DateComponents(year: 1), around: now)
    }
    
    static var specialWeights = ["mehl":0.66, "wasser":1.0, "öl":0.8, "oel":0.8, "honig":1.3, "kakao":0.6, "konfitüre":1.33, "konfituere":1.33, "stärke":0.6, "staerke":0.6, "zucker":1.0, "puderzucker":0.6, "nüsse":0.5, "nuesse":0.5, "mandeln":0.5, "saft":1.0, "milch":1.0, "butter":1.0, "griess":0.5 ]

    static var ingredientNames = [ "Weizenmehl 405", "Weizenmehl 550", "Weizenmehl 812", "Weizenmehl 812", "Weizenvollkronmehl", "Weizenschrot",
                                   "Roggenmehl 815", "Roggenmehl 997", "Roggenmehl 1150", "Roggenmehl 1370", "Roggenvollkornmehl", "Roggenmehlschrot",
                                   "Dinkelmehl 630", "Dinkelmehl 815", "Dinkelmehl 1050", "Dinkelvollkornmehl", "Dinkelschrot",
                                   "Emmervollkornmehl" ]
    
    static let formatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        return formatter
    }()
}
