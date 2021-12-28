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

//  static var featuredTab  = 0
    static var listTab      = 0
    static var featuredTab  = 1
    static var bakeListTab  = 2
    static var addRecipeTab = 3

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
    
    static var unitSets = ["Gramm":"g", "Teelöffel":"TL", "Esslöffel":"EL", "Messerspitze":"MS", "Milliliter":"ml", "Tasse":"Tasse"]
    
    static var gridItemLayoutInstructions = [GridItem(.fixed(60), alignment: .leading), GridItem(.flexible(minimum: 100), alignment: .leading), GridItem(.fixed(100), alignment: .trailing), GridItem(.fixed(120), alignment: .trailing)]

    static var gridItemLayoutComponents = [GridItem(.flexible(minimum: 100), alignment: .leading), GridItem(.flexible(minimum: 10), alignment: .leading), GridItem(.flexible(minimum: 100), alignment: .leading)]

}
