//
//  Recipe.swift
//  Back Planer
//
//  Created by Hans-Peter Müller on 03.11.21.
//

import Foundation
import SwiftUI

class RecipeFB: Identifiable, Decodable {
    
    // The id property is for the Identifiable protocol which we need to display these instances in a SwiftUI List
    var id:          String?
    var firestoreId: String?
    
    // These properties map to the properties in the JSON file
    var name:           String  = ""
    var image:          String  = ""
    var summary:        String  = ""
    var urlLink:        String  = ""
    var prepTime:       Int     = 0
    var totalWeight:    Double? = 0.0
    var tags:          [String] = [String]()
    var bakeHistoryFlag:Bool    = false
    var rating:         Int     = 0
    var components:    [ComponentFB]   = [ComponentFB]()
    var instructions:  [InstructionFB] = [InstructionFB]()
    var bakeHistories: [BakeHistoryFB] = [BakeHistoryFB]()
}

class ComponentFB: Identifiable, Decodable {
    
    var id:    String?
    var name:  String  = ""
    var number:Int     = 0
    var ingredients:[IngredientFB] = [IngredientFB]()
}

class IngredientFB: Identifiable, Decodable {
    
    var id:        String?
    var number:    Int    = 0
    var name:      String = ""
    var weight:    Double = 0.0
    var normWeight:Double = 0.0
    var unit:      String = ""
    var num:       Int    = 0
    var denom:     Int    = 0
}

class InstructionFB: Identifiable, Decodable {
    
    var id:         String?
    var step:       Double = 0
    var instruction:String = ""
    var duration:   Int    = 0
    var startTime:  Int?
    var date:       Date?
}

class NextStepsFB: Identifiable, Decodable {
    
    var id:         String?
    var date:       Date?
    var recipeName: String?
    var step:       Double = 0
    var instruction:String = ""
    var duration:   Int    = 0
    var startTime:  Int?
}

class BakeHistoryFB: Identifiable, Decodable {
    
    var id:     String? = ""
    var date:   Date    = Date()
    var comment:String  = ""
    var images:[String] = [String]()
}

class UnitSet: Identifiable, Decodable {
    var id:        String?
    var name:      String = ""
    var abkuerzung:String = ""
    var factor:    Double = 0.0
    var baseUnit:  String = ""
}
