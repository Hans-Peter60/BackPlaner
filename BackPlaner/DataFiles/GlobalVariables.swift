//
//  GlobalVariables.swift
//  BackPlaner
//
//  Created by Hans-Peter Müller on 05.11.21.
//

import Foundation
import SwiftUI

struct GlobalVariables {
    
    static var isDataPreloaded = "isDataPreloaded"
    
    static var recipesImage = [String : UIImage]()

    static var listTab      = 2
    static var featuredTab  = 1
    static var bakeListTab  = 0
    static var addRecipeTab = 3

    static var unitSets     = DataService.getUnitSets()
    
    static var noImage      = "no-image-icon-23494"
    static var detailView   = true
    
    static var schritt      = 1
    static var vorheizZeit  = 45
    static var startHeating = "Backofen anstellen"
    static var bakeEnd      = "Backvorgang ist beendet"
    
    static var totalDuration  = 0
    static var dateTimePicker = Date()
    static var dateComponents = Calendar.current.dateComponents(in: .current, from: Date())
    static var year           = dateComponents.year
    static var month          = dateComponents.month
    static var day            = dateComponents.day
    
    static var spezWeights    = ["mehl":0.66, "wasser":1.0, "öl":0.8, "oel":0.8, "honig":1.3, "kakao":0.6, "konfitüre":1.33, "konfituere":1.33, "stärke":0.6, "staerke":0.6, "zucker":1.0, "puderzucker":0.6, "nüsse":0.5, "nuesse":0.5, "mandeln":0.5, "saft":1.0, "milch":1.0, "butter":1.0, "griess":0.5 ]

    static var ingredientNames = [ "Weizenmehl 405", "Weizenmehl 550", "Weizenmehl 812", "Weizenmehl 812", "Weizenvollkronmehl", "Weizenschrot",
                                   "Roggenmehl 815", "Roggenmehl 997", "Roggenmehl 1150", "Roggenmehl 1370", "Roggenvollkornmehl", "Roggenmehlschrot",
                                   "Dinkelmehl 630", "Dinkelmehl 815", "Dinkelmehl 1050", "Dinkelvollkornmehl", "Dinkelschrot",
                                   "Emmervollkornmehl" ]
    
    static var gridItemLayoutInstructions = [GridItem(.fixed(60), alignment: .leading), GridItem(.flexible(minimum: 100), alignment: .leading), GridItem(.fixed(100), alignment: .trailing), GridItem(.fixed(120), alignment: .trailing)]

    static var gridItemLayoutComponents = [GridItem(.flexible(minimum: 100), alignment: .leading), GridItem(.flexible(minimum: 10), alignment: .leading), GridItem(.flexible(minimum: 100), alignment: .leading)]

    static var gridItemLayoutIngredients = [GridItem(.fixed(40),  alignment: .leading),  GridItem(.fixed(80), alignment: .trailing),
                          GridItem(.fixed(80), alignment: .leading),  GridItem(.flexible(minimum: 200), alignment: .leading),
                          GridItem(.fixed(40),  alignment: .leading), GridItem(.fixed(10),              alignment: .trailing),
                          GridItem(.fixed(40),  alignment: .leading), GridItem(.fixed(80),              alignment: .trailing)]
 
    static let formatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        return formatter
    }()
}




