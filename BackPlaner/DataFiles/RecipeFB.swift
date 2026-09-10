//
//  Recipe.swift
//  PetersBackPlaner
//
//  Created by Hans-Peter Müller on 03.11.21.
//

import Foundation
import SwiftUI
import Observation

/// Who may see a recipe that is stored in the cloud.
///
/// Public recipes live in the shared `Recipe` collection and are visible to
/// every user, so they may only contain content whose copyright allows
/// publication. Author-only recipes live in a separate `PrivateRecipe`
/// collection which the security rules restrict to their owner — that gives an
/// author a cloud copy of a recipe he may not share, without putting it into
/// the shared database.
///
/// Two collections instead of one collection plus a visibility filter: a
/// Firestore query has to be provably allowed for every document it returns,
/// so a mixed collection would need the visibility field on every existing
/// document. Separate collections keep the public database untouched.
enum RecipeVisibility: String, CaseIterable {
    case everyone   = "public"
    case authorOnly = "private"

    /// Firestore root collection holding the recipes with this visibility.
    var collectionName: String {
        switch self {
        case .everyone:   return "Recipe"
        case .authorOnly: return "PrivateRecipe"
        }
    }

    /// Cloud Storage folder holding the recipe images with this visibility.
    /// The folders are separated because Storage rules cannot look into
    /// Firestore: the path itself has to carry the access decision.
    var imageFolder: String {
        switch self {
        case .everyone:   return "images"
        case .authorOnly: return "privateImages"
        }
    }
}

struct RecipeTextFB: Decodable {
    var name: String?
    var summary: String?
    var tags: [String]?

    init(name: String? = nil, summary: String? = nil, tags: [String]? = nil) {
        self.name = name
        self.summary = summary
        self.tags = tags
    }

    init(firestoreData: Any?) {
        let data = firestoreData as? [String: Any]
        name = data?["name"] as? String
        summary = data?["summary"] as? String
        tags = data?["tags"] as? [String]
    }

    var firestoreData: [String: Any] {
        var data: [String: Any] = [:]
        if let name { data["name"] = name }
        if let summary { data["summary"] = summary }
        if let tags { data["tags"] = tags }
        return data
    }
}

struct NamedTextFB: Decodable {
    var name: String?

    init(name: String? = nil) {
        self.name = name
    }

    init(firestoreData: Any?) {
        let data = firestoreData as? [String: Any]
        name = data?["name"] as? String
    }

    var firestoreData: [String: Any] {
        guard let name else { return [:] }
        return ["name": name]
    }
}

struct IngredientTextFB: Decodable {
    var name: String?
    var unit: String?

    init(name: String? = nil, unit: String? = nil) {
        self.name = name
        self.unit = unit
    }

    init(firestoreData: Any?) {
        let data = firestoreData as? [String: Any]
        name = data?["name"] as? String
        unit = data?["unit"] as? String
    }

    var firestoreData: [String: Any] {
        var data: [String: Any] = [:]
        if let name { data["name"] = name }
        if let unit { data["unit"] = unit }
        return data
    }
}

struct InstructionTextFB: Decodable {
    var instruction: String?

    init(instruction: String? = nil) {
        self.instruction = instruction
    }

    init(firestoreData: Any?) {
        let data = firestoreData as? [String: Any]
        instruction = data?["instruction"] as? String
    }

    var firestoreData: [String: Any] {
        guard let instruction else { return [:] }
        return ["instruction": instruction]
    }
}

@Observable
class RecipeFB: Identifiable, Decodable {
    
    // The id property is for the Identifiable protocol which we need to display these instances in a SwiftUI List
    var id:          String?
    var firestoreId: String?
    // Anonymous id of the device that uploaded this public recipe (UGC moderation)
    var authorId:    String?
    /// Whether this cloud recipe is shared with everyone or reserved for its
    /// author. Recipes that only exist locally keep the default, which is only
    /// read once they are uploaded.
    var visibility:  RecipeVisibility = .everyone
    // Set by the first report that comes in: the recipe is then withheld from
    // every user until an admin either deletes it or releases it again.
    var hidden:      Bool = false

    // These properties map to the properties in the JSON file
    var name:           String  = ""
    var image:          String  = ""
    var summary:        String  = ""
    var urlLink:        String  = ""
    var prepTime:       Int     = 0
    var totalWeight:    Double  = 0.0
    var tags:          [String] = [String]()
    var bakeHistoryFlag:Bool    = false
    var rating:         Int     = 0
    var sourceLanguage: String  = ""
    var translations: [String: RecipeTextFB] = [:]
    var components:    [ComponentFB]   = [ComponentFB]()
    var instructions:  [InstructionFB] = [InstructionFB]()
    var bakeHistories: [BakeHistoryFB] = [BakeHistoryFB]()

    init() {}

    // Decode resiliently: keys missing from the JSON fall back to the declared defaults
    // instead of throwing keyNotFound (e.g. bakeHistoryFlag, rating, bakeHistories).
    private enum CodingKeys: String, CodingKey {
        case id, firestoreId, authorId, visibility, hidden, name, image, summary, urlLink, prepTime, totalWeight
        case tags, bakeHistoryFlag, rating, sourceLanguage, translations, components, instructions, bakeHistories
    }

    required init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id              = try c.decodeIfPresent(String.self,           forKey: .id)
        firestoreId     = try c.decodeIfPresent(String.self,           forKey: .firestoreId)
        authorId        = try c.decodeIfPresent(String.self,           forKey: .authorId)
        visibility      = RecipeVisibility(rawValue: try c.decodeIfPresent(String.self, forKey: .visibility) ?? "") ?? .everyone
        hidden          = try c.decodeIfPresent(Bool.self,             forKey: .hidden)          ?? false
        name            = try c.decodeIfPresent(String.self,           forKey: .name)            ?? ""
        image           = try c.decodeIfPresent(String.self,           forKey: .image)           ?? ""
        summary         = try c.decodeIfPresent(String.self,           forKey: .summary)         ?? ""
        urlLink         = try c.decodeIfPresent(String.self,           forKey: .urlLink)         ?? ""
        prepTime        = try c.decodeIfPresent(Int.self,              forKey: .prepTime)        ?? 0
        totalWeight     = try c.decodeIfPresent(Double.self,           forKey: .totalWeight)     ?? 0.0
        tags            = try c.decodeIfPresent([String].self,         forKey: .tags)            ?? [String]()
        bakeHistoryFlag = try c.decodeIfPresent(Bool.self,             forKey: .bakeHistoryFlag) ?? false
        rating          = try c.decodeIfPresent(Int.self,              forKey: .rating)          ?? 0
        sourceLanguage  = try c.decodeIfPresent(String.self,           forKey: .sourceLanguage)  ?? ""
        translations    = try c.decodeIfPresent([String: RecipeTextFB].self, forKey: .translations) ?? [:]
        components      = try c.decodeIfPresent([ComponentFB].self,    forKey: .components)      ?? [ComponentFB]()
        instructions    = try c.decodeIfPresent([InstructionFB].self,  forKey: .instructions)    ?? [InstructionFB]()
        bakeHistories   = try c.decodeIfPresent([BakeHistoryFB].self,  forKey: .bakeHistories)   ?? [BakeHistoryFB]()
    }
}

@Observable
class ComponentFB: Identifiable, Decodable {

    var id:    String?
    var name:  String  = ""
    var number:Int     = 0
    var translations: [String: NamedTextFB] = [:]
    var ingredients:[IngredientFB] = [IngredientFB]()

    init() {}

    // Decode resiliently: e.g. the JSON uses "step" and omits "number".
    private enum CodingKeys: String, CodingKey {
        case id, name, number, step, translations, ingredients
    }

    required init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id           = try c.decodeIfPresent(String.self,        forKey: .id)
        name         = try c.decodeIfPresent(String.self,        forKey: .name)        ?? ""
        number       = try c.decodeIfPresent(Int.self,           forKey: .number)      ?? c.decodeIfPresent(Int.self, forKey: .step) ?? 0
        translations = try c.decodeIfPresent([String: NamedTextFB].self, forKey: .translations) ?? [:]
        ingredients  = try c.decodeIfPresent([IngredientFB].self, forKey: .ingredients) ?? [IngredientFB]()
    }
}

@Observable
class IngredientFB: Identifiable, Decodable {

    var id:        String?
    var number:    Int    = 0
    var name:      String = ""
    var weight:    Double = 0.0
    var normWeight:Double = 0.0
    var unit:      String = ""
    var num:       Int    = 0
    var denom:     Int    = 0
    var translations: [String: IngredientTextFB] = [:]

    init() {}

    // Decode resiliently: some ingredients only specify "name" (e.g. carry-over components).
    private enum CodingKeys: String, CodingKey {
        case id, number, name, weight, normWeight, unit, num, denom, translations
    }

    required init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id           = try c.decodeIfPresent(String.self, forKey: .id)
        number       = try c.decodeIfPresent(Int.self,    forKey: .number)     ?? 0
        name         = try c.decodeIfPresent(String.self, forKey: .name)       ?? ""
        weight       = try c.decodeIfPresent(Double.self, forKey: .weight)     ?? 0.0
        normWeight   = try c.decodeIfPresent(Double.self, forKey: .normWeight) ?? 0.0
        unit         = try c.decodeIfPresent(String.self, forKey: .unit)       ?? ""
        num          = try c.decodeIfPresent(Int.self,    forKey: .num)        ?? 0
        denom        = try c.decodeIfPresent(Int.self,    forKey: .denom)      ?? 0
        translations = try c.decodeIfPresent([String: IngredientTextFB].self, forKey: .translations) ?? [:]
    }
}

class InstructionFB: Identifiable, Decodable {

    var id:         String?
    var step:       Double = 0
    var instruction:String = ""
    var duration:   Int    = 0
    var startTime:  Int?
    var date:       Date?
    var bakeFlag:   Bool?
    /// The component this step prepares, for steps the recipe import generates
    /// per component. The bake plan schedules those in dependency order, and
    /// reads the dependency from here instead of from the step's wording.
    var componentName: String?
    var translations: [String: InstructionTextFB] = [:]

    init() {}

    private enum CodingKeys: String, CodingKey {
        case id, step, instruction, duration, startTime, date, bakeFlag
        case componentName, translations
    }

    required init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id            = try c.decodeIfPresent(String.self, forKey: .id)
        step          = try c.decodeIfPresent(Double.self, forKey: .step) ?? 0
        instruction   = try c.decodeIfPresent(String.self, forKey: .instruction) ?? ""
        duration      = try c.decodeIfPresent(Int.self, forKey: .duration) ?? 0
        startTime     = try c.decodeIfPresent(Int.self, forKey: .startTime)
        date          = try c.decodeIfPresent(Date.self, forKey: .date)
        bakeFlag      = try c.decodeIfPresent(Bool.self, forKey: .bakeFlag)
        componentName = try c.decodeIfPresent(String.self, forKey: .componentName)
        translations  = try c.decodeIfPresent([String: InstructionTextFB].self, forKey: .translations) ?? [:]
    }
}

class NextStepFB: Identifiable, Decodable {
    
    var id:         String?
    var date:       Date?
    var recipeName: String?
    var step:       Double = 0
    var instruction:String = ""
    var duration:   Int    = 0
    var startTime:  Int?
}

class BakeHistoryFB: Identifiable, Decodable {
    
    var id:     String? = ""
    var date:   Date    = Date()
    var comment:String  = ""
    var images:[String] = [String]()
}

class UnitSetFB: Identifiable, Decodable {
    var id:        String?
    var name:      String = ""
    var abbreviation:String = ""
    var factor:    Double = 0.0
    var baseUnit:  String = ""
}

extension RecipeFB {
    func applyPreferredLocalization() {
        applyLocalization(languageCode: Self.preferredLanguageCode)
    }

    func capturePreferredLocalization() {
        captureLocalization(languageCode: Self.preferredLanguageCode)
    }

    /// Public wrapper: display the recipe using the cached translation for `languageCode`.
    func showLocalization(languageCode: String) {
        applyLocalization(languageCode: languageCode)
    }

    /// Public wrapper: snapshot the current live values into the translation cache for `languageCode`.
    func storeLocalization(languageCode: String) {
        captureLocalization(languageCode: languageCode)
    }

    /// Whether a non-empty translation is already cached for `languageCode`.
    func hasCachedTranslation(languageCode: String) -> Bool {
        !((translations[languageCode]?.name ?? "").isEmpty)
    }

    /// Re-files cached text from one language to another, throughout the recipe.
    ///
    /// Needed when a recipe turns out to be filed under the wrong language: the
    /// text in that slot is the original, not a translation of it. Left where it
    /// is, the app would keep finding an "already translated" version of the
    /// language it is asked to translate into.
    func moveCachedTranslation(from oldCode: String, to newCode: String) {
        guard !oldCode.isEmpty, !newCode.isEmpty, oldCode != newCode else { return }

        if let text = translations.removeValue(forKey: oldCode) {
            translations[newCode] = text
        }

        for component in components {
            if let text = component.translations.removeValue(forKey: oldCode) {
                component.translations[newCode] = text
            }
            for ingredient in component.ingredients {
                if let text = ingredient.translations.removeValue(forKey: oldCode) {
                    ingredient.translations[newCode] = text
                }
            }
        }

        for instruction in instructions {
            if let text = instruction.translations.removeValue(forKey: oldCode) {
                instruction.translations[newCode] = text
            }
        }
    }

    private func applyLocalization(languageCode: String) {
        guard !languageCode.isEmpty else { return }

        if let text = localizedRecipeText(for: languageCode) {
            name = text.name ?? name
            summary = text.summary ?? summary
            tags = text.tags ?? tags
        }

        for component in components {
            component.applyLocalization(languageCode: languageCode)
        }

        for instruction in instructions {
            instruction.applyLocalization(languageCode: languageCode)
        }
    }

    private func captureLocalization(languageCode: String) {
        guard !languageCode.isEmpty else { return }
        if sourceLanguage.isEmpty { sourceLanguage = languageCode }

        translations[languageCode] = RecipeTextFB(name: name, summary: summary, tags: tags)

        for component in components {
            component.captureLocalization(languageCode: languageCode)
        }

        for instruction in instructions {
            instruction.captureLocalization(languageCode: languageCode)
        }
    }

    private func localizedRecipeText(for languageCode: String) -> RecipeTextFB? {
        translations[languageCode] ?? translations[Self.baseLanguageCode(from: languageCode)]
    }

    var firestoreTranslationsData: [String: Any] {
        translations.compactMapValues { text in
            let data = text.firestoreData
            return data.isEmpty ? nil : data
        }
    }

    /// Full Cloud Storage path of the recipe image. Public and author-only
    /// images live in separate folders, so the path depends on the visibility.
    var imageStoragePath: String {
        visibility.imageFolder + "/" + image + ".jpg"
    }

    /// An independent copy of the recipe, ready to be uploaded as a new document.
    ///
    /// The upload stamps the recipe it is handed with the new document id, image
    /// path and visibility. Passing the object a screen is currently showing
    /// would therefore repoint that screen — and its entry in the recipe list —
    /// at the new document, so publishing has to work on a copy.
    ///
    /// Identifiers are deliberately not carried over: the new document and its
    /// subdocuments get their own. `totalWeight` starts at zero because the
    /// upload recalculates it from the ingredients.
    func copyForUpload() -> RecipeFB {
        let copy = RecipeFB()

        copy.name            = name
        copy.summary         = summary
        copy.urlLink         = urlLink
        copy.prepTime        = prepTime
        copy.tags            = tags
        copy.rating          = rating
        copy.bakeHistoryFlag = bakeHistoryFlag
        copy.sourceLanguage  = sourceLanguage
        copy.translations    = translations

        copy.components = components.map { component in
            let componentCopy = ComponentFB()
            componentCopy.name         = component.name
            componentCopy.number       = component.number
            componentCopy.translations = component.translations
            componentCopy.ingredients  = component.ingredients.map { ingredient in
                let ingredientCopy = IngredientFB()
                ingredientCopy.name         = ingredient.name
                ingredientCopy.number       = ingredient.number
                ingredientCopy.unit         = ingredient.unit
                ingredientCopy.weight       = ingredient.weight
                ingredientCopy.normWeight   = ingredient.normWeight
                ingredientCopy.num          = ingredient.num
                ingredientCopy.denom        = ingredient.denom
                ingredientCopy.translations = ingredient.translations
                return ingredientCopy
            }
            return componentCopy
        }

        copy.instructions = instructions.map { instruction in
            let instructionCopy = InstructionFB()
            instructionCopy.instruction   = instruction.instruction
            instructionCopy.step          = instruction.step
            instructionCopy.duration      = instruction.duration
            instructionCopy.startTime     = instruction.startTime
            instructionCopy.date          = instruction.date
            instructionCopy.bakeFlag      = instruction.bakeFlag
            instructionCopy.componentName = instruction.componentName
            instructionCopy.translations   = instruction.translations
            return instructionCopy
        }

        return copy
    }

    static var preferredLanguageCode: String {
        baseLanguageCode(from: AppSettings.localeIdentifier())
    }

    static func baseLanguageCode(from identifier: String) -> String {
        identifier
            .replacingOccurrences(of: "-", with: "_")
            .split(separator: "_")
            .first
            .map(String.init) ?? ""
    }
}

extension ComponentFB {
    func applyLocalization(languageCode: String) {
        if let localizedName = translations[languageCode]?.name ?? translations[RecipeFB.baseLanguageCode(from: languageCode)]?.name {
            name = localizedName
        }

        for ingredient in ingredients {
            ingredient.applyLocalization(languageCode: languageCode)
        }
    }

    func captureLocalization(languageCode: String) {
        translations[languageCode] = NamedTextFB(name: name)

        for ingredient in ingredients {
            ingredient.captureLocalization(languageCode: languageCode)
        }
    }

    var firestoreTranslationsData: [String: Any] {
        translations.compactMapValues { text in
            let data = text.firestoreData
            return data.isEmpty ? nil : data
        }
    }
}

extension IngredientFB {
    func applyLocalization(languageCode: String) {
        if let text = translations[languageCode] ?? translations[RecipeFB.baseLanguageCode(from: languageCode)] {
            name = text.name ?? name
            unit = text.unit ?? unit
        }
    }

    func captureLocalization(languageCode: String) {
        translations[languageCode] = IngredientTextFB(name: name, unit: unit)
    }

    var firestoreTranslationsData: [String: Any] {
        translations.compactMapValues { text in
            let data = text.firestoreData
            return data.isEmpty ? nil : data
        }
    }
}

extension InstructionFB {
    func applyLocalization(languageCode: String) {
        if let localizedInstruction = translations[languageCode]?.instruction ?? translations[RecipeFB.baseLanguageCode(from: languageCode)]?.instruction {
            instruction = localizedInstruction
        }
    }

    func captureLocalization(languageCode: String) {
        translations[languageCode] = InstructionTextFB(instruction: instruction)
    }

    var firestoreTranslationsData: [String: Any] {
        translations.compactMapValues { text in
            let data = text.firestoreData
            return data.isEmpty ? nil : data
        }
    }
}
