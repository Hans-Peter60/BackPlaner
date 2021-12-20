//
//  RecipeFBModel.swift
//  BackPlaner
//
//  Created by Hans-Peter Müller on 22.11.21.
//

import Foundation
import Firebase
import FirebaseStorage

class RecipeFBModel: ObservableObject {
    
    let db = Firestore.firestore()
    let storage = Storage.storage()
    
    @Published var recipesFB    = [RecipeFB]()
    @Published var storedID     = ""
    
    init() {
        // Check if we have preloaded the data into core data
        getRecipesFB()
    }
    
    func uploadRecipeToFirestore(r: RecipeFB, i: UIImage) {
        
        let cloudRecipes = db.collection("Recipe")
 
        r.image = UUID().uuidString
        
        // MARK: Upload image into cloud storage
        let storageRef = storage.reference()
        let data       = i.jpegData(compressionQuality: 0.5) ?? Data()
        let filePath   = "images/" + (r.image) + ".jpg"
        
        let imageRef   = storageRef.child(filePath)
        
        let uploadTask = imageRef.putData(data, metadata: nil) { (metadata, error) in guard let metadata = metadata else  {
            // Uh-oh, an error occurred!
            return
        }
            // You can also access to download URL after upload.
            imageRef.downloadURL { (url, error) in
                guard let downloadURL = url else {
                    // Uh-oh, an error occurred!
                    return
                }
            }
        }

        let calculatedInstructions = Rational.calculateStartTimes(r.instructions, Date())

        // Create a Firebase document
        let cloudRecipe = cloudRecipes.addDocument(data: [
            "name":     r.name,
            "prepTime": GlobalVariables.totalDuration,
            "servings": r.servings,
            "summary":  r.summary,
            "urlLink":  r.urlLink,
            "image":    r.image,
            "tags":     r.tags
        ])
        
        
        for i in calculatedInstructions {
            
            let cloudComponent = cloudRecipe.collection("instructions").addDocument(data: [
                "instruction": i.instruction,
                "step":        i.step,
                "duration":    i.duration,
                "startTime":   i.startTime ?? 0,
                "date":        i.date ?? 0
            ])
        }
        
        // Set the components
        for c in r.components {
            
            let cloudComponent = cloudRecipe.collection("components").addDocument(data: ["name": c.name])
            
            for i in c.ingredients {
                
                // Create a ingredient document
                let cloudIngredient = cloudComponent.collection("ingredients").addDocument(data: [
                    "name": i.name,
                    "id":   i.id
                ])
                cloudIngredient.updateData([
                    "unit":      i.unit ?? "",
                    "weight":    i.weight,
                    "num":       i.num ?? 1,
                    "denom":     i.denom ?? 1,
                    "component": i.component ?? 1
                ])
            }
        }
    }
    
    func getRecipesFB() {
        
        let collection = db.collection("Recipe")
        let storageRef = storage.reference()
        
        collection.getDocuments  { snapshot, error in
            
            if error == nil && snapshot != nil {
                
                // Loop through the documents returned
                for doc in snapshot!.documents {
                    
                    let r      = RecipeFB()
                    
                    r.id       = doc.documentID
                    r.name     = doc["name"] as? String ?? ""
                    r.image    = doc["image"] as? String ?? ""
                    r.summary  = doc["summary"] as? String ?? ""
                    r.urlLink  = doc["urlLink"] as? String ?? ""
                    r.prepTime = doc["prepTime"] as? Int ?? 0
                    r.tags     = doc["tags"] as? [String] ?? [String]()
                    r.servings = doc["servings"] as? Int ?? 1
                    
                    if GlobalVariables.detailView {
                        self.getInstructionsFB(r, r.id!)
                        self.getComponentsFB(r, r.id!)
                    }
                    self.recipesFB.append(r)
                    
                    let t = "images/" + r.image + ".jpg"
                    let imageRef = storageRef.child(t)
                    
                    // Download in memory with a maximum allowed size of 1MB (1 * 1024 * 1024 bytes)
                    imageRef.getData(maxSize: 1 * 2048 * 2048) { data, error in
                        if let error = error {
                            // Uh-oh, an error occurred!
                            print("Error - no image found")
                        } else {
                            // Data is returned
                            GlobalVariables.recipesImage[r.id ?? ""] = UIImage(data: data!) ?? UIImage()
                        }
                    }
//                    print("r.name:", r.name, "t: ", t, "r.id: ", r.id, "recipesImage[r.id]", GlobalVariables.recipesImage[r.id ?? ""])
                    
                }
            }
        }
    }
    
    func getInstructionsFB(_ r:RecipeFB, _ recipeDocID:String) {
        
        let collection = db.collection("Recipe").document(recipeDocID).collection("instructions").order(by: "step")
        
        collection.getDocuments  { snapshot, error in
            
            if error == nil && snapshot != nil {
                
                // Loop through the documents returned
                for doc in snapshot!.documents {
                    
                    let i = InstructionFB()
                    
                    i.id          = doc.documentID
                    i.instruction = doc["instruction"] as? String ?? ""
                    i.duration    = doc["duration"] as? Int ?? 0
                    i.startTime   = doc["startTime"] as? Int ?? 0
                    i.step        = doc["step"] as? Double ?? 1

                    r.instructions.append(i)
                }
            }
        }
    }
    
    func getComponentsFB(_ r:RecipeFB, _ recipeDocID:String) {
        
        let collection = db.collection("Recipe").document(recipeDocID).collection("components")
        
        collection.getDocuments  { snapshot, error in
            
            if error == nil && snapshot != nil {
                
                // Loop through the documents returned
                for doc in snapshot!.documents {
                    
                    let c = ComponentFB()
                    
                    c.id   = doc.documentID
                    c.name = doc["name"] as? String ?? ""
                    
                    self.getIngredientsFB(c, recipeDocID, c.id!)
                    r.components.append(c)
                }
            }
        }
    }
    
    func getIngredientsFB(_ c:ComponentFB, _ recipeDocID:String, _ componentDocID:String) {
        
        let collection = db.collection("Recipe").document(recipeDocID).collection("components").document(componentDocID).collection("ingredients")
        
        collection.getDocuments  { snapshot, error in
            
            if error == nil && snapshot != nil {
                
                // Loop through the documents returned
                for doc in snapshot!.documents {
                    
                    let i = IngredientFB()
                    
                    i.id     = doc.documentID
                    i.name   = doc["name"] as? String ?? ""
                    i.unit   = doc["unit"] as? String ?? ""
                    i.weight = doc["weight"] as? Double ?? 0
                    i.num    = doc["num"] as? Int ?? 0
                    i.denom  = doc["denom"] as? Int ?? 0
                    
                    c.ingredients.append(i)
                }
            }
        }
        let collection2 = db.collection("Recipe").document(recipeDocID).collection("components").document(componentDocID).collection("incredients")
        
        collection2.getDocuments  { snapshot, error in
            
            if error == nil && snapshot != nil {
                
                // Loop through the documents returned
                for doc in snapshot!.documents {
                    
                    let i = IngredientFB()
                    
                    i.id     = doc.documentID
                    i.name   = doc["name"] as? String ?? ""
                    i.unit   = doc["unit"] as? String ?? ""
                    i.weight = doc["weight"] as? Double ?? 0
                    i.num    = doc["num"] as? Int ?? 0
                    i.denom  = doc["denom"] as? Int ?? 0
                    
                    c.ingredients.append(i)
                }
            }
        }

    }
    
    static func getPortion(ingredient:IngredientFB, recipeServings:Int, targetServings:Int) -> String {
        
        var portion            = ""
        var numerator          = ingredient.num ?? 1
        var denominator        = ingredient.denom ?? 1
        var wholePortions      = 0
        let compTargetServings = Double(targetServings) / 2
        
        if (ingredient.weight == nil || ingredient.weight == 0) && (ingredient.num == 0 || (ingredient.num == ingredient.denom)) {
            return "" }
        else {
            if ingredient.weight == nil || ingredient.weight == 0 {
                // Get a single serving size by multiplying denominator by the recipe servings
                denominator *= (recipeServings * 2)
                
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
                portion = Rational.decimalPlace((Double(ingredient.weight ?? 0) / (Double(recipeServings)) * compTargetServings), 1000)
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
