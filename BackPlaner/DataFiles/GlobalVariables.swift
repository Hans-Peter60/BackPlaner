//
//  GlobalVariables.swift
//  PetersBackPlaner
//
//  Created by Hans-Peter Müller on 05.11.21.
//

import Foundation
import SwiftUI
import os

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
}

struct GlobalVariables {
    
    static var isDataPreloaded = "isDataPreloaded"
    
    static var recipesImage = [String : UIImage]()

    static var tabSelection = 0
    
    static var bakeListTab  = 0
    static var listTab      = 1
    static var historyTab   = 2
    static var addRecipeTab = 3

    static var unitSets     = DataService.getUnitSets()
    
    static var noImage      = "no-image-icon-23494"
    static var detailView: Bool { AppSettings.storedUseDetailView }
    
    static var step         = 1
    static var preheatTime: Int { AppSettings.storedPreheatTime }
    static var startHeating: String { AppSettings.storedStartHeatingText }
    static var bakeEnd: String { AppSettings.storedBakeEndText }
    static var dayStart: Int { AppSettings.storedDayStart }
    static var dayEnd: Int { AppSettings.storedDayEnd }
    static var bakePause: Int { AppSettings.storedBakePause }
    
    static var totalDuration  = 0
    static var dateTimePicker = Date()
    static var dateComponents = Calendar.current.dateComponents(in: .current, from: Date())
    static var year           = dateComponents.year
    static var month          = dateComponents.month
    static var day            = dateComponents.day
    
    static var specialWeights = ["mehl":0.66, "wasser":1.0, "öl":0.8, "oel":0.8, "honig":1.3, "kakao":0.6, "konfitüre":1.33, "konfituere":1.33, "stärke":0.6, "staerke":0.6, "zucker":1.0, "puderzucker":0.6, "nüsse":0.5, "nuesse":0.5, "mandeln":0.5, "saft":1.0, "milch":1.0, "butter":1.0, "griess":0.5 ]

    static var ingredientNames = [ "Weizenmehl 405", "Weizenmehl 550", "Weizenmehl 812", "Weizenmehl 812", "Weizenvollkronmehl", "Weizenschrot",
                                   "Roggenmehl 815", "Roggenmehl 997", "Roggenmehl 1150", "Roggenmehl 1370", "Roggenvollkornmehl", "Roggenmehlschrot",
                                   "Dinkelmehl 630", "Dinkelmehl 815", "Dinkelmehl 1050", "Dinkelvollkornmehl", "Dinkelschrot",
                                   "Emmervollkornmehl" ]
    
    // These three are computed, not stored: `scaledLayoutValue` reads the
    // current text size, and a stored `static var` would freeze whatever it
    // was on first access and never grow with the user's setting.
    static var gridItemLayoutInstructions: [GridItem] { [GridItem(scaledColumnSize(60), alignment: .leading), GridItem(.flexible(minimum: 100), alignment: .leading), GridItem(scaledColumnSize(100), alignment: .trailing), GridItem(scaledColumnSize(120), alignment: .trailing)] }

    static var gridItemLayoutComponents: [GridItem] { [GridItem(.flexible(minimum: 100), alignment: .leading), GridItem(.flexible(minimum: 10), alignment: .leading), GridItem(.flexible(minimum: 100), alignment: .leading)] }

    static var gridItemLayoutIngredients: [GridItem] { [GridItem(scaledColumnSize(40),  alignment: .leading),  GridItem(scaledColumnSize(80), alignment: .trailing),
                          GridItem(scaledColumnSize(80), alignment: .leading),  GridItem(.flexible(minimum: 200), alignment: .leading),
                          GridItem(scaledColumnSize(40),  alignment: .leading), GridItem(scaledColumnSize(10),              alignment: .trailing),
                          GridItem(scaledColumnSize(40),  alignment: .leading), GridItem(scaledColumnSize(80),              alignment: .trailing)] }
 
    static let formatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        return formatter
    }()
}




