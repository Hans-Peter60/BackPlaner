//
//  RecipeModel.swift
//  BackPlaner
//
//  Created by Hans-Peter Müller on 04.11.21.
//

import CoreData
import SwiftUI
import Foundation
import Firebase
import FirebaseStorage

class RecipeModel: ObservableObject {
    
    // Reference to the managed object context
    let managedObjectContext = PersistenceController.shared.container.viewContext
    
    @Published var recipes   = [Recipe]()
    @Published var recipesFB = [RecipeFB]()
    @Published var nextSteps = [NextSteps]()
    
    var calcWeight:CalcIngredientWeight = CalcIngredientWeight()
    
    init() {
        
        // Check if we have preloaded the data into core data
        checkLoadedData()
    }
    
    func fetchRecipe(for objectId: NSManagedObjectID, context: NSManagedObjectContext) -> Recipe? {
      guard let recipe = context.object(with: objectId) as? Recipe else {
        return nil
      }
      return recipe
    }

    func fetchComponent(for objectId: NSManagedObjectID, context: NSManagedObjectContext) -> Component? {
      guard let component = context.object(with: objectId) as? Component else {
        return nil
      }
      return component
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
        
        let deleteFetch2 = NSFetchRequest<NSFetchRequestResult>(entityName: "BakeHistory")
        let deleteRequest2 = NSBatchDeleteRequest(fetchRequest: deleteFetch2)
        
        do {
            try managedObjectContext.execute(deleteRequest2)
            try managedObjectContext.save()
        } catch {
            print ("There was an error")
        }

        let deleteFetch3 = NSFetchRequest<NSFetchRequestResult>(entityName: "NextSteps")
        let deleteRequest3 = NSBatchDeleteRequest(fetchRequest: deleteFetch3)
        
        do {
            try managedObjectContext.execute(deleteRequest3)
            try managedObjectContext.save()
        } catch {
            print ("There was an error")
        }

        let deleteFetch4 = NSFetchRequest<NSFetchRequestResult>(entityName: "Instruction")
        let deleteRequest4 = NSBatchDeleteRequest(fetchRequest: deleteFetch4)
        
        do {
            try managedObjectContext.execute(deleteRequest4)
            try managedObjectContext.save()
        } catch {
            print ("There was an error")
        }

        let deleteFetch5 = NSFetchRequest<NSFetchRequestResult>(entityName: "Ingredient")
        let deleteRequest5 = NSBatchDeleteRequest(fetchRequest: deleteFetch5)
        
        do {
            try managedObjectContext.execute(deleteRequest5)
            try managedObjectContext.save()
        } catch {
            print ("There was an error")
        }
        
        let deleteFetch6 = NSFetchRequest<NSFetchRequestResult>(entityName: "Component")
        let deleteRequest6 = NSBatchDeleteRequest(fetchRequest: deleteFetch6)
        
        do {
            try managedObjectContext.execute(deleteRequest6)
            try managedObjectContext.save()
        } catch {
            print ("There was an error")
        }
  }
    
    func checkLoadedData() {
        
        // Check local storage for the flag
        let status = UserDefaults.standard.bool(forKey: GlobalVariables.isDataPreloaded)
        
        // If it's false, then we should parse the local json and preload into Core Data
        if status == false {
//            deleteAllCoreDataRecords()
            preloadLocalData()
        }
    }
    
    func preloadLocalData() {
        
        // Parse the local JSON file
        let localRecipes = DataService.getLocalData()
        
        // Create firebase collections
        for r in localRecipes {
            uploadRecipeIntoCoreData(recipeId: NSManagedObjectID(), recipeFB: r, context: managedObjectContext, recipeImage: UIImage())
//            uploadRecipeToFirestore(r: r, i: UIImage(named: r.image))
        }
    }
    
    func uploadRecipeIntoCoreData(
        recipeId:    NSManagedObjectID?,
        recipeFB:    RecipeFB,
        context:     NSManagedObjectContext,
        recipeImage: UIImage
    ) {
        let r: Recipe
        if let objectId = recipeId,
           let fetchedRecipe = fetchRecipe(for: objectId, context: context) {
            r = fetchedRecipe
        } else {
            r = Recipe(context: context)
        }
    
        print("uploadRecipeIntoCoreData: recipeFB.id:", recipeFB.id)
  
        // MARK: Image
        if let objectId = recipeId {
            r.image       = recipeImage.jpegData(compressionQuality: 1.0) ?? Data()
        }
        else {
            if recipeFB.id ?? "" > "" {
                let image     = GlobalVariables.recipesImage[recipeFB.id ?? ""]
                r.image       = image!.jpegData(compressionQuality: 1.0) ?? Data()
            }
            else {
                r.image       = recipeImage.jpegData(compressionQuality: 1.0) ?? Data()
            }
        }

        r.id              = UUID()
        r.firestoreId     = recipeFB.id
        r.name            = recipeFB.name
        r.summary         = recipeFB.summary
        r.urlLink         = recipeFB.urlLink
        r.rating          = recipeFB.rating
        r.totalWeight     = 0                       // Berechnung erfolgt bei den Ingredients
        r.bakeHistoryFlag = recipeFB.bakeHistoryFlag
        r.tags            = recipeFB.tags

        // Set the instructions
        recipeFB.instructions = Rational.calculateStartTimes(recipeFB.instructions, Date())
        r.prepTime = GlobalVariables.totalDuration

        for iFB in recipeFB.instructions {
            
            if iFB.instruction != GlobalVariables.startHeating && iFB.instruction != GlobalVariables.bakeEnd {
                
                let i = Instruction(context: context)

                i.id          = UUID()
                i.instruction = iFB.instruction
                i.step        = iFB.step
                i.duration    = iFB.duration
                i.startTime   = iFB.startTime ?? 0
                
                r.addToInstructions(i)
            }
        }

        // Set the components
        for cFB in recipeFB.components {
            
            let c    = Component(context: context)
            c.id     = UUID()
            c.name   = cFB.name
            c.number = cFB.number

            // Set the ingredient
            for iFB in cFB.ingredients {
                
                let i         = Ingredient(context: context)
                
                i.id          = UUID()
                i.name        = iFB.name
                i.number      = iFB.number
                i.unit        = iFB.unit
                i.weight      = iFB.weight
                i.normWeight  = iFB.normWeight
                i.num         = iFB.num
                i.denom       = iFB.denom
                
                if i.unit == "g" || i.unit == "Gramm" {
                    i.normWeight = i.weight
                }
                else {
                    i.normWeight = calcWeight.calcIngredientWeight(weight: i.weight, unit: i.unit ?? "", name: i.name, num: i.num, denom: i.denom)
                }
                r.totalWeight += i.normWeight
                
                c.addToIngredients(i)
            }
            
            r.addToComponents(c)
        }
        
        for bH in recipeFB.bakeHistories {
            let h = BakeHistory(context: context)
            
            h.id      = UUID()
            h.date    = bH.date
            h.comment = bH.comment
            
            if bH.images.count == 1 && bH.images[0] == GlobalVariables.noImage {
                // do nothing
            }
            else {
                h.images = [Data]()
                for i in bH.images {
                    
                    let bHI = UIImage(named: i)?.jpegData(compressionQuality: 1.0) ?? Data()
                    h.images!.append(bHI)
                }
            }
            r.addToBakeHistories(h)
        }
        
        // Save to core data
        do {
            // Save the recipe to core data
            try context.save()
            
            // Switch the view to list view
        }
        catch {
            // Couldn't save the recipe
            print("Couldn't save the recipe")
        }
    }
}
