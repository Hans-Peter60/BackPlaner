//
//  DataService.swift
//  PetersBackPlaner
//
//  Created by Hans-Peter Müller on 05.11.21.
//

import Foundation
import os

class DataService {
    
    static func getUnitSets() -> [UnitSetFB] {
        
        // Parse local json file

        // Get a url path to the json file
        let pathString = Bundle.main.path(forResource: "UnitSets", ofType: "json")

        // Check if pathString is not nil, otherwise...
        guard pathString != nil else {
            return [UnitSetFB]()
        }

        // Create a url object
        let url = URL(fileURLWithPath: pathString!)

        do {
            // Create a data object
            let data = try Data(contentsOf: url)

            // Decode the data with a JSON decoder
            let decoder = JSONDecoder()

            do {

                let unitSetsData = try decoder.decode([UnitSetFB].self, from: data)

                // Add the unique IDs
                for unitSet in unitSetsData {
                    unitSet.id = UUID().uuidString
                }
                // Return the recipes
                return unitSetsData
            }
            catch {
                // error with parsing json
                #if DEBUG
                AppLog.data.error("\(error)")
                #endif
            }
        }
        catch {
            // error with getting data
            #if DEBUG
            AppLog.data.error("\(error)")
            #endif
        }
        return [UnitSetFB]()
    }
}
