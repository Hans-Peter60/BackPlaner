//
//  DataService.swift
//  BakePlannerCore
//
//  Created by Hans-Peter Müller on 05.11.21.
//

import Foundation
#if canImport(os)
import os
#endif

public class DataService {
    
    public static func getUnitSets() -> [UnitSetFB] {
        #if !canImport(Darwin)
        // No app bundle to read from: the same file, generated into the
        // package (scripts/generate-package-data.py).
        return unitSets(from: Data(BundledUnitSetsData.json.utf8))
        #else
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
        #endif
    }

    /// The units in a UnitSets.json, each with an id of its own.
    static func unitSets(from data: Data) -> [UnitSetFB] {
        guard let unitSets = try? JSONDecoder().decode([UnitSetFB].self, from: data) else { return [] }
        for unitSet in unitSets {
            unitSet.id = UUID().uuidString
        }
        return unitSets
    }
}
