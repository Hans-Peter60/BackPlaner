//
//  RecipeModel.swift
//  PetersBackPlaner
//
//  Created by Hans-Peter Müller on 04.11.21.
//

import CoreData
import SwiftUI
import Foundation
import os
// import FirebaseCore
// import FirebaseStorage

class RecipeModel: ObservableObject {
    
    // Reference to the managed object context
    let managedObjectContext = PersistenceController.shared.container.viewContext
    
    @Published var recipes   = [Recipe]()
    @Published var recipesFB = [RecipeFB]()
    @Published var nextSteps = [NextStep]()
    
    var calcWeight:CalcIngredientWeight = CalcIngredientWeight()
    
    init() {
        
        // Check if we have preloaded the data into core data
        checkLoadedData()
    }
    
    // MARK: fetch functions
    func fetchRecipe(for objectId: NSManagedObjectID, context: NSManagedObjectContext) -> Recipe? {
      guard let recipe = context.object(with: objectId) as? Recipe else {
        return nil
      }
      return recipe
    }

    func fetchRecipe(firestoreId: String, context: NSManagedObjectContext) -> Recipe? {
        let request: NSFetchRequest<Recipe> = Recipe.fetchRequest()
        request.fetchLimit = 1
        request.predicate = NSPredicate(format: "firestoreId == %@", firestoreId)

        do {
            return try context.fetch(request).first
        } catch {
            AppLog.persistence.error("Couldn't fetch recipe for firestoreId \(firestoreId): \(error)")
            return nil
        }
    }

    func fetchComponent(for objectId: NSManagedObjectID, context: NSManagedObjectContext) -> Component? {
      guard let component = context.object(with: objectId) as? Component else {
        return nil
      }
      return component
    }
    
    func fetchIngredient(for objectId: NSManagedObjectID, context: NSManagedObjectContext) -> Ingredient? {
      guard let ingredient = context.object(with: objectId) as? Ingredient else {
        return nil
      }
      return ingredient
    }

    func fetchShoppingCartIngredient(for objectId: NSManagedObjectID, name: String, context: NSManagedObjectContext) -> Ingredient? {
      guard let ingredient = context.object(with: objectId) as? Ingredient else {
        return nil
      }
      return ingredient
    }

    func searchShoppingCartIngredientData(for objectId: NSManagedObjectID, name: String) -> NSManagedObjectID? {
        
        var ingredientsRequest: FetchRequest<Ingredient>
        var ingredients: FetchedResults<Ingredient> { ingredientsRequest.wrappedValue }
        
        ingredientsRequest = FetchRequest(entity: Ingredient.entity(), sortDescriptors: [], predicate: NSPredicate(format: "shoppingCarts == %@ AND name CONTAINS[c] %@", objectId, name.lowercased()))
        
        if ingredients.count > 0 {
            
            return ingredients[0].objectID
        }
        else {
            return nil
        }
    }

    func fetchShoppingCart(for objectId: NSManagedObjectID, context: NSManagedObjectContext) -> ShoppingCart? {
      guard let shoppingCart = context.object(with: objectId) as? ShoppingCart else {
        return nil
      }
      return shoppingCart
    }

    private func clearRecipeDetails(for recipe: Recipe, context: NSManagedObjectContext) {
        for instruction in recipe.instructionsArray {
            context.delete(instruction)
        }

        for component in recipe.componentsArray {
            for ingredient in component.ingredientsArray {
                context.delete(ingredient)
            }
            context.delete(component)
        }

        for bakeHistory in recipe.bakeHistoriesArray {
            context.delete(bakeHistory)
        }
    }
    
    // MARK: delete functions
    func deleteAllCoreDataRecords() {
        
        let deleteFetch = NSFetchRequest<NSFetchRequestResult>(entityName: "Recipe")
        let deleteRequest = NSBatchDeleteRequest(fetchRequest: deleteFetch)

        do {
            try managedObjectContext.execute(deleteRequest)
            try managedObjectContext.save()
        } catch {
            AppLog.persistence.error("There was an error")
        }

        let deleteFetch2 = NSFetchRequest<NSFetchRequestResult>(entityName: "BakeHistory")
        let deleteRequest2 = NSBatchDeleteRequest(fetchRequest: deleteFetch2)

        do {
            try managedObjectContext.execute(deleteRequest2)
            try managedObjectContext.save()
        } catch {
            AppLog.persistence.error("There was an error")
        }

        let deleteFetch3 = NSFetchRequest<NSFetchRequestResult>(entityName: "NextStep")
        let deleteRequest3 = NSBatchDeleteRequest(fetchRequest: deleteFetch3)

        do {
            try managedObjectContext.execute(deleteRequest3)
            try managedObjectContext.save()
        } catch {
            AppLog.persistence.error("There was an error")
        }

//        UNUserNotificationCenter.current().getPendingNotificationRequests { (notificationRequests) in
//           var identifiers: [String] = []
//           for notification:UNNotificationRequest in notificationRequests {
//               if notification.identifier.contains("Recipe-") {
//                  identifiers.append(notification.identifier)
//               }
//           }
//           UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: identifiers)
//        }

        let deleteFetch4 = NSFetchRequest<NSFetchRequestResult>(entityName: "Instruction")
        let deleteRequest4 = NSBatchDeleteRequest(fetchRequest: deleteFetch4)

        do {
            try managedObjectContext.execute(deleteRequest4)
            try managedObjectContext.save()
        } catch {
            AppLog.persistence.error("There was an error")
        }

        let deleteFetch5 = NSFetchRequest<NSFetchRequestResult>(entityName: "Ingredient")
        let deleteRequest5 = NSBatchDeleteRequest(fetchRequest: deleteFetch5)

        do {
            try managedObjectContext.execute(deleteRequest5)
            try managedObjectContext.save()
        } catch {
            AppLog.persistence.error("There was an error")
        }

        let deleteFetch6 = NSFetchRequest<NSFetchRequestResult>(entityName: "Component")
        let deleteRequest6 = NSBatchDeleteRequest(fetchRequest: deleteFetch6)

        do {
            try managedObjectContext.execute(deleteRequest6)
            try managedObjectContext.save()
        } catch {
            AppLog.persistence.error("There was an error")
        }

        let deleteFetch7 = NSFetchRequest<NSFetchRequestResult>(entityName: "ShoppingCart")
        let deleteRequest7 = NSBatchDeleteRequest(fetchRequest: deleteFetch7)

        do {
            try managedObjectContext.execute(deleteRequest7)
            try managedObjectContext.save()
        } catch {
            AppLog.persistence.error("There was an error")
        }
    }
    
    func deleteBlankRecipes() {
        let deleteFetch = NSFetchRequest<NSFetchRequestResult>(entityName: "Recipe")
        deleteFetch.predicate = NSPredicate(format: "name == %@", "")
        let deleteRequest = NSBatchDeleteRequest(fetchRequest: deleteFetch)

        do {
            try managedObjectContext.execute(deleteRequest)
            try managedObjectContext.save()
        } catch {
            AppLog.persistence.error("There was an error")
        }
    }
    
    // MARK: load functions
    func checkLoadedData() {
        
        // Check local storage for the flag
        let status = UserDefaults.standard.bool(forKey: GlobalVariables.isDataPreloaded)

        // If it's false, then we should parse the local json and preload into Core Data
        if status == false {
//            deleteAllCoreDataRecords()
//            deleteBlankRecipes()
            preloadLocalData()
        }
    }
    
    func preloadLocalData() {

        // Parse the local JSON file
        let localRecipes = DataService.getLocalData()

        // Nothing decoded – leave the flag unset so the preload is retried on the next launch
        guard !localRecipes.isEmpty else { return }

        // Import the bundled recipes into Core Data
        for r in localRecipes {
            // Bundled recipes are new (no existing object id) and carry no Firestore id, so
            // clear it to take the bundled-asset image path rather than the Firebase image cache.
            r.id = nil
            let bundledImage = UIImage(named: r.image) ?? UIImage()
            _ = uploadRecipeIntoCoreData(recipeId: nil, recipeFB: r, context: managedObjectContext, recipeImage: bundledImage)
//            uploadRecipeToFirestore(r: r, i: UIImage(named: r.image))
        }

        // Mark the preload as done so we don't re-import (and duplicate) on every launch
        UserDefaults.standard.set(true, forKey: GlobalVariables.isDataPreloaded)
    }
    
    // MARK: uploadRecipeIntoCoreData
    func uploadRecipeIntoCoreData(
        recipeId:    NSManagedObjectID?,
        recipeFB:    RecipeFB,
        context:     NSManagedObjectContext,
        recipeImage: UIImage
    ) -> Recipe {
        
        let r: Recipe
        let isUpdatingExistingRecipe: Bool
        if let objectId = recipeId,
           let fetchedRecipe = fetchRecipe(for: objectId, context: context) {
            r = fetchedRecipe
            isUpdatingExistingRecipe = true
        } else if let firestoreId = recipeFB.id,
                  !firestoreId.isEmpty,
                  let fetchedRecipe = fetchRecipe(firestoreId: firestoreId, context: context) {
            r = fetchedRecipe
            isUpdatingExistingRecipe = true
        } else {
            r = Recipe(context: context)
            isUpdatingExistingRecipe = false
        }

        if isUpdatingExistingRecipe {
            clearRecipeDetails(for: r, context: context)
        }
    
        AppLog.data.debug("uploadRecipeIntoCoreData: recipeFB.id: \(recipeFB.id ?? "")")

        recipeFB.applyPreferredLocalization()
        recipeFB.capturePreferredLocalization()
  
        if recipeId != nil {
            r.image = recipeImage.jpegData(compressionQuality: 1.0) ?? Data()
        }
        else {
            if recipeFB.id ?? "" > "" {
                // Fall back to the passed image if the download cache has no entry
                // (e.g. the recipe image failed to download) instead of force-unwrapping nil.
                let image     = GlobalVariables.recipesImage[recipeFB.id ?? ""] ?? recipeImage
                r.image       = image.jpegData(compressionQuality: 1.0) ?? Data()
            }
            else {
                r.image       = recipeImage.jpegData(compressionQuality: 1.0) ?? Data()
            }
        }

        if r.id == nil {
            r.id = UUID()
        }
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
                var historyImages = [Data]()
                for i in bH.images {

                    let bHI = UIImage(named: i)?.jpegData(compressionQuality: 1.0) ?? Data()
                    historyImages.append(bHI)
                }
                h.images = historyImages
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
            AppLog.persistence.error("Couldn't save the recipe")
        }

        return r
    }
}

extension Recipe {
    func recalculateTotalWeight() {
        let calcWeight = CalcIngredientWeight()

        totalWeight = componentsArray.filter { !$0.isDeleted }.reduce(0) { componentSum, component in
            componentSum + component.ingredientsArray.filter { !$0.isDeleted }.reduce(0) { ingredientSum, ingredient in
                ingredient.normWeight = calcWeight.calcIngredientWeight(
                    weight: ingredient.weight,
                    unit: ingredient.unit ?? "",
                    name: ingredient.name,
                    num: ingredient.num,
                    denom: ingredient.denom
                )
                return ingredientSum + ingredient.normWeight
            }
        }
    }
}
