//
//  RecipeModel.swift
//  BackPlaner
//
//  Created by Hans-Peter Müller on 04.11.21.
//

import Foundation
import UIKit
import Firebase
import FirebaseStorage
import CoreData

class RecipeModel: ObservableObject {
    
    // Reference to the managed object context
    let managedObjectContext = PersistenceController.shared.container.viewContext
    
    @Published var recipes = [Recipe]()
    @Published var nextSteps = [NextSteps]()
    
    init() {
        
        // Check if we have preloaded the data into core data
        checkLoadedData()
    }
    
    func deleteAllCoreDataRecords() {
        
        let deleteFetch = NSFetchRequest<NSFetchRequestResult>(entityName: "Recipe")
        let deleteRequest = NSBatchDeleteRequest(fetchRequest: deleteFetch)
        
        do {
            try managedObjectContext.execute(deleteRequest)
            try managedObjectContext.save()
        } catch {
            print ("There was an error")
        }
    }
    
    func checkLoadedData() {
        
        // Check local storage for the flag
        //let status = UserDefaults.standard.bool(forKey: GlobalVariables.isDataPreloaded)
        
        // If it's false, then we should parse the local json and preload into Core Data
//        if status == false {
            deleteAllCoreDataRecords()
//            preloadLocalData()
//        }
    }
    
    func preloadLocalData() {
        
        // Parse the local JSON file
        let localRecipes = DataService.getLocalData()
        
        // Create firebase collections
        for r in localRecipes {
            uploadRecipeIntoCoreData(recipeFB: r)
//            uploadRecipeToFirestore(r: r)
        }
    }
    
    func uploadRecipeIntoCoreData(recipeFB: RecipeFB) {
        
        let r = Recipe(context: managedObjectContext)
        
        r.id = UUID()
        r.name = recipeFB.name
        r.summary = recipeFB.summary
        r.image = UIImage(named: recipeFB.image)?.jpegData(compressionQuality: 1.0) ?? Data()
        r.urlLink = recipeFB.urlLink
        r.featured = true
        r.servings = recipeFB.servings
        r.tags = recipeFB.tags

        // Set the instructions
        recipeFB.instructions = Rational.calculateStartTimes(recipeFB.instructions, Date())
        r.prepTime = GlobalVariables.totalDuration
        
        for iFB in recipeFB.instructions {
            let i = Instruction(context: managedObjectContext)
            
            i.id = UUID()
            i.instruction = iFB.instruction
            i.step = iFB.step
            i.duration = iFB.duration
            i.startTime = iFB.startTime ?? 0
            
            r.addToInstructions(i)
        }

        // Set the components
        for cFB in recipeFB.components {
            let c = Component(context: managedObjectContext)
            
            c.id = UUID()
            c.name = cFB.name
            
            for iFB in cFB.ingredients {
                let i = Ingredient(context: managedObjectContext)
                
                // Set the ingredient
                i.id = UUID()
                i.name = iFB.name
                i.unit = iFB.unit ?? ""
                i.weight = iFB.weight ?? 0
                i.num = iFB.num ?? 1
                i.denom = iFB.denom ?? 1
                
                c.addToIngredients(i)
            }
            
            r.addToComponents(c)
        }
        
        for bH in recipeFB.bakeHistories {
            let h = BakeHistory(context: managedObjectContext)
            
            h.id      = UUID()
            h.date    = bH.date
            h.comment = bH.comment
            
            for i in bH.images ?? [""] {
                
                let bHI = UIImage(named: i)?.jpegData(compressionQuality: 1.0) ?? Data()
                h.images.append(bHI)
            }
            r.addToBakeHistories(h)
        }
        
        // Save to core data
        do {
            // Save the recipe to core data
            try managedObjectContext.save()
            
            // Switch the view to list view
        }
        catch {
            // Couldn't save the recipe
        }

    }
    
    static func getPortion(ingredient:Ingredient, recipeServings:Int, targetServings:Int) -> String {
        
        var portion = ""
        var numerator = ingredient.num
        var denominator = ingredient.denom
        var wholePortions = 0
        
        if (ingredient.weight == nil || ingredient.weight == 0) && (ingredient.num == 0 || (ingredient.num == ingredient.denom)) {
            return "" }
        else {
            if ingredient.weight == nil || ingredient.weight == 0 {
                // Get a single serving size by multiplying denominator by the recipe servings
                denominator *= recipeServings
                
                // Get target portion by multiplying numerator by target servings
                numerator *= targetServings
                
                // Reduce fraction by greatest common divisor
                let divisor = Rational.greatestCommonDivisor(numerator, denominator)
                numerator /= divisor
                denominator /= divisor
                
                // Get the whole portion if numerator > denominator
                if numerator >= denominator {
                    
                    // Calculated whole portions
                    wholePortions = numerator / denominator
                    
                    // Calculate the remainder
                    numerator = numerator % denominator
                    
                    // Assign to portion string
                    portion += String(wholePortions)
                }
                
                // Express the remainder as a fraction
                if numerator > 0 {
                    
                    // Assign remainder as fraction to the portion string
                    portion += wholePortions > 0 ? " " : ""
                    portion += "\(numerator)/\(denominator)"
                }
            } else {
                portion = String(Double(ingredient.weight / Double(recipeServings * targetServings)))
            }
            
            if var unit = ingredient.unit {
                
                // If we need to pluralize
                if wholePortions > 1 {
                    
                    // Calculate appropriate suffix
                    if unit.suffix(2) == "ch" {
                        unit += "es"
                    }
                    else if unit.suffix(1) == "f" {
                        unit = String(unit.dropLast())
                        unit += "ves"
                    }
                    else {
                        unit += "s"
                    }
                }
                
                portion += ingredient.num == nil && ingredient.denom == nil ? "" : " "
                
                return portion + unit
            }
            
            return portion
        }
    }
}

