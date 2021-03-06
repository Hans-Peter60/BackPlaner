//
//  DataService.swift
//  BackPlaner
//
//  Created by Hans-Peter Müller on 05.11.21.
//

import Foundation

class DataService {
    
    static func getLocalData() -> [RecipeFB] {
        
        // Parse local json file

        // Get a url path to the json file
        let pathString = Bundle.main.path(forResource: "Recipes", ofType: "json")

        // Check if pathString is not nil, otherwise...
        guard pathString != nil else {
            return [RecipeFB]()
        }

        // Create a url object
        let url = URL(fileURLWithPath: pathString!)

        do {
            // Create a data object
            let data = try Data(contentsOf: url)

            // Decode the data with a JSON decoder
            let decoder = JSONDecoder()

            do {

                let recipeData = try decoder.decode([RecipeFB].self, from: data)

                // Add the unique IDs
                for r in recipeData {
                    r.id = UUID().uuidString

                    // Add unique IDs to recipe components
                    for c in r.components {
                        c.id = UUID().uuidString
                    }
                }
                // Return the recipes
                return recipeData
            }
            catch {
                // error with parsing json
                print(error)
            }
        }
        catch {
            // error with getting data
            print(error)
        }
        return [RecipeFB]()
    }
    
    static func getUnitSets() -> [UnitSet] {
        
        // Parse local json file

        // Get a url path to the json file
        let pathString = Bundle.main.path(forResource: "UnitSets", ofType: "json")

        // Check if pathString is not nil, otherwise...
        guard pathString != nil else {
            return [UnitSet]()
        }

        // Create a url object
        let url = URL(fileURLWithPath: pathString!)

        do {
            // Create a data object
            let data = try Data(contentsOf: url)

            // Decode the data with a JSON decoder
            let decoder = JSONDecoder()

            do {

                let unitSetsData = try decoder.decode([UnitSet].self, from: data)

                // Add the unique IDs
                for unitSet in unitSetsData {
                    unitSet.id = UUID().uuidString
                }
                // Return the recipes
                return unitSetsData
            }
            catch {
                // error with parsing json
                print(error)
            }
        }
        catch {
            // error with getting data
            print(error)
        }
        return [UnitSet]()
    }
}
