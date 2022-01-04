//
//  Recipe.swift
//  Back Planer
//
//  Created by Hans-Peter Müller on 03.11.21.
//

import Foundation
import SwiftUI

//class RecipesImage: Identifiable {
//
//    // The id property is for the Identifiable protocol which we need to display these instances in a SwiftUI List
//    var id:String? = ""
//    var imageBinary:UIImage = UIImage()
//}

class RecipeFB: Identifiable, Decodable {
    
    // The id property is for the Identifiable protocol which we need to display these instances in a SwiftUI List
    var id:String? = ""
    var firestoreId: String? = ""
    
    // These properties map to the properties in the JSON file
    var name:String = ""
    var image:String = ""
    var summary:String = ""
    var urlLink:String = ""
    var prepTime:Int = 0
    var tags: [String] = [String]()
    var bakeHistoryFlag = false
    var rating:Int? = 0
    var components: [ComponentFB] = [ComponentFB]()
    var instructions: [InstructionFB] = [InstructionFB]()
    var bakeHistories: [BakeHistoryFB] = [BakeHistoryFB]()
}

class ComponentFB: Identifiable, Decodable {
    
    var id:String? = ""
    var number:Int = 0
    var name:String = ""
    var ingredients:[IngredientFB] = [IngredientFB]()
}

class IngredientFB: Identifiable, Decodable {
    
    var id:String? = ""
    var componentNr:Int = 0
    var number:Int = 0
    var name:String = ""
    var weight:Double?
    var unit:String = ""
    var num:Int?
    var denom:Int?
}

class InstructionFB: Identifiable, Decodable {
    
    var id:String? = ""
    var step:Double = 0
    var instruction:String = ""
    var duration:Int = 0
    var startTime:Int?
    var date:Date?
}

class NextStepsFB: Identifiable, Decodable {
    
    var id:String? = ""
    var date:Date?
    var recipeName:String? = ""
    var step:Double = 0
    var instruction:String = ""
    var duration:Int = 0
    var startTime:Int?
}

class BakeHistoryFB: Identifiable, Decodable {
    
    var id:String? = ""
    var date:Date = Date()
    var comment:String = ""
    var images:[String] = [String]()
}
