//
//  RecipeFirestoreMapping.swift
//  BakePlannerCore
//
//  How a public recipe is laid out in Firestore: the fields of the recipe
//  document and of its components, ingredients and instructions, read into
//  RecipeFB and written back. Pure functions over the documents' data, so
//  the iPhone (Firebase iOS SDK) and Android (skip-firebase) read and write
//  the same shape.
//

import Foundation

public enum RecipeFirestoreMapping {

    /// The subcollections of a recipe document; ingredients sit below each
    /// component.
    public static let componentsCollection = "components"
    public static let ingredientsCollection = "ingredients"
    public static let instructionsCollection = "instructions"

    // MARK: Reading

    /// The recipe document as listed: its own fields and translations,
    /// without components and instructions (they are subcollections). The
    /// caller applies the language to show.
    public static func recipe(id: String, data: [String: Any]) -> RecipeFB {
        let recipe = RecipeFB()
        recipe.id             = id
        recipe.hidden         = bool(data["hidden"]) ?? false
        recipe.authorId       = data["authorId"]       as? String ?? ""
        recipe.name           = data["name"]           as? String ?? ""
        recipe.image          = data["image"]          as? String ?? ""
        recipe.summary        = data["summary"]        as? String ?? ""
        recipe.urlLink        = data["urlLink"]        as? String ?? ""
        recipe.prepTime       = int(data["prepTime"])        ?? 0
        recipe.totalWeight    = double(data["totalWeight"])  ?? 0
        recipe.tags           = data["tags"]           as? [String] ?? [String]()
        recipe.sourceLanguage = data["sourceLanguage"] as? String ?? ""
        if let translations = data["translations"] as? [String: Any] {
            recipe.translations = translations.mapValues { RecipeTextFB(firestoreData: $0) }
        }
        return recipe
    }

    /// A component document, without its ingredients (a subcollection).
    public static func component(id: String, data: [String: Any]) -> ComponentFB {
        let component = ComponentFB()
        component.id     = id
        component.name   = data["name"] as? String ?? ""
        component.number = int(data["number"]) ?? 0
        if let translations = data["translations"] as? [String: Any] {
            component.translations = translations.mapValues { NamedTextFB(firestoreData: $0) }
        }
        return component
    }

    public static func ingredient(id: String, data: [String: Any]) -> IngredientFB {
        let ingredient = IngredientFB()
        ingredient.id         = id
        ingredient.name       = data["name"] as? String ?? ""
        ingredient.number     = int(data["number"]) ?? 0
        ingredient.unit       = data["unit"] as? String ?? ""
        ingredient.weight     = double(data["weight"]) ?? 0
        // Documents written before the normalised weight existed fall back
        // to the weight as entered.
        ingredient.normWeight = double(data["normWeight"]) ?? ingredient.weight
        ingredient.num        = int(data["num"]) ?? 0
        ingredient.denom      = int(data["denom"]) ?? 0
        if let translations = data["translations"] as? [String: Any] {
            ingredient.translations = translations.mapValues { IngredientTextFB(firestoreData: $0) }
        }
        return ingredient
    }

    public static func instruction(id: String, data: [String: Any]) -> InstructionFB {
        let instruction = InstructionFB()
        instruction.id            = id
        instruction.instruction   = data["instruction"] as? String ?? ""
        instruction.duration      = int(data["duration"]) ?? 0
        instruction.startTime     = int(data["startTime"]) ?? 0
        instruction.step          = double(data["step"]) ?? 1
        instruction.componentName = data["componentName"] as? String
        if let translations = data["translations"] as? [String: Any] {
            instruction.translations = translations.mapValues { InstructionTextFB(firestoreData: $0) }
        }
        return instruction
    }

    // MARK: Writing

    /// The document of a newly published recipe. `hidden` is false from the
    /// start: the list asks for `hidden == false`, Firestore never matches a
    /// missing field, and the rules refuse a new recipe without it.
    public static func newRecipeData(of recipe: RecipeFB, prepTime: Int, authorId: String) -> [String: Any] {
        var data: [String: Any] = [
            "name":           recipe.name,
            "prepTime":       prepTime,
            "totalWeight":    recipe.totalWeight,
            "summary":        recipe.summary,
            "urlLink":        recipe.urlLink,
            "image":          recipe.image,
            "tags":           recipe.tags,
            "authorId":       authorId,
            "sourceLanguage": recipe.sourceLanguage,
            "hidden":         false
        ]
        let translations = recipe.firestoreTranslationsData
        if !translations.isEmpty {
            data["translations"] = translations
        }
        return data
    }

    /// The fields an edit of a published recipe changes. `authorId` and
    /// `hidden` are left alone on purpose: the rules refuse an author who
    /// changes them.
    public static func editedRecipeData(of recipe: RecipeFB) -> [String: Any] {
        [
            "name":           recipe.name,
            "summary":        recipe.summary,
            "urlLink":        recipe.urlLink,
            "image":          recipe.image,
            "tags":           recipe.tags,
            "prepTime":       recipe.prepTime,
            "totalWeight":    recipe.totalWeight,
            "sourceLanguage": recipe.sourceLanguage,
            "translations":   recipe.firestoreTranslationsData
        ]
    }

    public static func componentData(of component: ComponentFB) -> [String: Any] {
        var data: [String: Any] = [
            "name":   component.name,
            "number": component.number
        ]
        let translations = component.firestoreTranslationsData
        if !translations.isEmpty {
            data["translations"] = translations
        }
        return data
    }

    public static func ingredientData(of ingredient: IngredientFB) -> [String: Any] {
        var data: [String: Any] = [
            "name":       ingredient.name,
            "number":     ingredient.number,
            "unit":       ingredient.unit,
            "weight":     ingredient.weight,
            "normWeight": ingredient.normWeight,
            "num":        ingredient.num,
            "denom":      ingredient.denom
        ]
        let translations = ingredient.firestoreTranslationsData
        if !translations.isEmpty {
            data["translations"] = translations
        }
        return data
    }

    public static func instructionData(of instruction: InstructionFB) -> [String: Any] {
        var data: [String: Any] = [
            "instruction": instruction.instruction,
            "step":        instruction.step,
            "duration":    instruction.duration,
            "startTime":   instruction.startTime ?? 0,
            "date":        instruction.date ?? 0
        ]
        if let componentName = instruction.componentName {
            data["componentName"] = componentName
        }
        let translations = instruction.firestoreTranslationsData
        if !translations.isEmpty {
            data["translations"] = translations
        }
        return data
    }

    // MARK: Reports

    /// Where reports of public recipes go (App Store Guideline 1.2; Google
    /// Play asks the same for content of users).
    public static let reportsCollection = "reports"

    /// The reasons offered, stored as written here — the German text is
    /// what reviewers read in the Firebase console.
    public static let reportReasons = ["Anstößig oder beleidigend", "Spam", "Urheberrechtsverletzung", "Sonstiges"]

    /// One report per reporter and recipe: the rules allow creating it, never
    /// changing it, so a second report of the same recipe fails.
    public static func reportID(recipeId: String, reporter: String) -> String {
        "\(recipeId)_\(reporter)"
    }

    /// The report's fields, without the time it was filed: that is a server
    /// timestamp on the iPhone, which each SDK writes in its own way.
    public static func reportData(of recipe: RecipeFB, reason: String, reporter: String) -> [String: Any] {
        [
            "recipeId":   recipe.id ?? "",
            "authorId":   recipe.authorId ?? "",
            "reason":     reason,
            "reportedBy": reporter,
            "status":     "open"
        ]
    }

    /// The only change a reporter may make to the recipe (the rules check
    /// that `hidden` is the one field changed, to true): it is withheld from
    /// every user at once, until an admin has looked at it.
    public static var reportHideData: [String: Any] { ["hidden": true] }

    // MARK: Values

    // Firestore keeps every number as either a 64-bit integer or a double.
    // The iOS SDK hands both out as NSNumber, which converts either way; the
    // Android SDK hands out Long or Double, which Swift does not convert by
    // itself. These accept both, and an integer field holding a whole double.

    public static func int(_ value: Any?) -> Int? {
        if let value = value as? Int { return value }
        if let value = value as? Int64 { return Int(value) }
        if let value = value as? Int32 { return Int(value) }
        if let value = value as? Double, value.rounded() == value, abs(value) < 1e15 { return Int(value) }
        return nil
    }

    public static func double(_ value: Any?) -> Double? {
        if let value = value as? Double { return value }
        if let value = value as? Float { return Double(value) }
        if let value = value as? Int { return Double(value) }
        if let value = value as? Int64 { return Double(value) }
        if let value = value as? Int32 { return Double(value) }
        return nil
    }

    public static func bool(_ value: Any?) -> Bool? {
        value as? Bool
    }
}

extension RecipeExportData {
    /// A public recipe as the recipe views, the plan and the shopping list
    /// take it, with its picture. Components, ingredients and steps are put
    /// in their display order, so an index into `ComponentColumn.columns(of:)`
    /// lands on the same line here.
    public init(recipeFB: RecipeFB, imageData: Data?) {
        self.init(
            name: recipeFB.name,
            summary: recipeFB.summary,
            urlLink: recipeFB.urlLink.isEmpty ? nil : recipeFB.urlLink,
            prepTime: recipeFB.prepTime,
            totalWeight: recipeFB.totalWeight,
            tags: recipeFB.tags,
            rating: recipeFB.rating,
            recurrenceIntervalDays: 0,
            image: imageData,
            components: recipeFB.components
                .sorted { $0.number < $1.number }
                .map { component in
                    RecipeExportComponent(
                        name: component.name,
                        number: component.number,
                        ingredients: component.ingredients
                            .sorted { $0.number < $1.number }
                            .map { ingredient in
                                RecipeExportIngredient(
                                    name: ingredient.name,
                                    number: ingredient.number,
                                    unit: ingredient.unit.isEmpty ? nil : ingredient.unit,
                                    weight: ingredient.weight,
                                    normWeight: ingredient.normWeight,
                                    num: ingredient.num,
                                    denom: ingredient.denom
                                )
                            }
                    )
                },
            instructions: recipeFB.instructions
                .sorted { $0.step < $1.step }
                .map { instruction in
                    RecipeExportInstruction(
                        instruction: instruction.instruction,
                        step: instruction.step,
                        duration: instruction.duration,
                        startTime: instruction.startTime ?? 0,
                        bakeFlag: instruction.bakeFlag ?? false,
                        componentName: instruction.componentName
                    )
                }
        )
    }
}
