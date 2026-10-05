//
//  UITestSupport.swift
//  BackPlaner
//

import CoreData
import UIKit

/// Launch switches for the UI tests in BackPlanerUITests. They only exist in
/// DEBUG builds, so the shipped app ignores them whatever it is started with.
///
/// `-UITesting` runs the app on an empty in-memory store, so a test neither
/// sees nor changes the recipes on the simulator, and every launch starts from
/// the same state. `-UITestingSeedRecipe` adds one known recipe to that store:
/// saving a recipe through the form requires a photo, and the photo picker
/// cannot be driven reliably from a UI test.
enum UITestSupport {

    static let seededRecipeName = "UI-Test-Brot"

    static var isActive: Bool {
        #if DEBUG
        ProcessInfo.processInfo.arguments.contains("-UITesting")
        #else
        false
        #endif
    }

    static var seedsRecipe: Bool {
        isActive && ProcessInfo.processInfo.arguments.contains("-UITestingSeedRecipe")
    }

    /// Stores a small recipe whose steps the plan test can find again in
    /// "Geplante Schritte".
    static func seedRecipe(into context: NSManagedObjectContext) {
        let recipe = RecipeFB()
        recipe.name = seededRecipeName
        recipe.summary = "Rezept für die UI-Tests."

        let mainDough = ComponentFB()
        mainDough.name = "Hauptteig"
        mainDough.number = 1
        mainDough.ingredients = [("Weizenmehl 550", 500.0), ("Wasser", 350.0), ("Salz", 10.0)]
            .enumerated()
            .map { index, entry in
                let ingredient = IngredientFB()
                ingredient.number = index + 1
                ingredient.name = entry.0
                ingredient.weight = entry.1
                ingredient.unit = "g"
                return ingredient
            }
        recipe.components = [mainDough]

        recipe.instructions = [(1.0, "Teig kneten", 10), (2.0, "Teig gehen lassen", 60), (3.0, "Bei 250 °C backen", 40)]
            .map { step, text, minutes in
                let instruction = InstructionFB()
                instruction.id = UUID().uuidString
                instruction.step = step
                instruction.instruction = text
                instruction.duration = minutes
                return instruction
            }

        let image = UIGraphicsImageRenderer(size: CGSize(width: 64, height: 64)).image { canvas in
            UIColor.brown.setFill()
            canvas.fill(CGRect(x: 0, y: 0, width: 64, height: 64))
        }

        do {
            _ = try RecipeModel().uploadRecipeIntoCoreData(recipeId: nil,
                                                           recipeFB: recipe,
                                                           context: context,
                                                           recipeImage: image)
        } catch {
            AppLog.data.error("UI test recipe could not be seeded: \(error.localizedDescription)")
        }
    }
}
