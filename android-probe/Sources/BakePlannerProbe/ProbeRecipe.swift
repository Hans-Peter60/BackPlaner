//
//  ProbeRecipe.swift
//  BakePlannerProbe
//
//  An @Observable model the way the app's public recipes are built
//  (RecipeFB, ComponentFB): plain classes whose changes the views follow.
//  Checks that Observation works on Android as on iOS.
//

import Foundation
import Observation
// Needed for an @Observable to drive the Android UI.
import SkipFuse

@Observable
final class ProbeRecipe {
    var name: String
    var ingredients: [String]
    var targetDoughTemperature = 24
    var roomTemperature = 21
    var flourTemperature = 20
    var frictionFactor = 1
    var usesPreferment = false
    var prefermentTemperature = 22

    init(name: String, ingredients: [String]) {
        self.name = name
        self.ingredients = ingredients
    }

    var waterTemperature: Int {
        DoughTemperatureCalculator.waterTemperature(
            targetDoughTemperature: targetDoughTemperature,
            roomTemperature: roomTemperature,
            flourTemperature: flourTemperature,
            frictionFactor: frictionFactor,
            prefermentTemperature: usesPreferment ? prefermentTemperature : nil
        )
    }

    static let sample = ProbeRecipe(
        name: "Landbrot",
        ingredients: ["Wasser (lauwarm, 30 °C)", "Weizenmehl 550", "Roggenmehl 1150", "Salz", "Hefe, zimmerwarm"]
    )

    /// A backup file as the iOS app writes it, read on this platform.
    static let sampleBackup = """
    {
      "formatVersion" : 1,
      "recipes" : [
        {
          "components" : [
            {
              "ingredients" : [
                { "denom" : 0, "name" : "Weizenmehl 550", "normWeight" : 500, "num" : 0, "number" : 1, "unit" : "g", "weight" : 500 },
                { "denom" : 4, "name" : "Hefe", "normWeight" : 0, "num" : 1, "number" : 2, "weight" : 0 }
              ],
              "name" : "Teig",
              "number" : 1
            }
          ],
          "image" : "AQID",
          "instructions" : [
            { "bakeFlag" : false, "componentName" : "Teig", "duration" : 10, "instruction" : "Kneten", "startTime" : 0, "step" : 1 },
            { "bakeFlag" : true, "duration" : 40, "instruction" : "Bei 250 °C backen", "startTime" : 70, "step" : 3 }
          ],
          "name" : "Weißbrot",
          "prepTime" : 110,
          "rating" : 4,
          "recurrenceIntervalDays" : 0,
          "summary" : "Einfach",
          "tags" : [ "Weizen" ],
          "totalWeight" : 830.5
        }
      ]
    }
    """
}
