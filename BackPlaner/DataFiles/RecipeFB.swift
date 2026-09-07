//
//  Recipe.swift
//  PetersBackPlaner
//
//  Created by Hans-Peter Müller on 03.11.21.
//

import Foundation
import SwiftUI
import Observation

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
        case id, firestoreId, authorId, name, image, summary, urlLink, prepTime, totalWeight
        case tags, bakeHistoryFlag, rating, sourceLanguage, translations, components, instructions, bakeHistories
    }

    required init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id              = try c.decodeIfPresent(String.self,           forKey: .id)
        firestoreId     = try c.decodeIfPresent(String.self,           forKey: .firestoreId)
        authorId        = try c.decodeIfPresent(String.self,           forKey: .authorId)
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
    var translations: [String: InstructionTextFB] = [:]

    init() {}

    private enum CodingKeys: String, CodingKey {
        case id, step, instruction, duration, startTime, date, bakeFlag, translations
    }

    required init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id           = try c.decodeIfPresent(String.self, forKey: .id)
        step         = try c.decodeIfPresent(Double.self, forKey: .step) ?? 0
        instruction  = try c.decodeIfPresent(String.self, forKey: .instruction) ?? ""
        duration     = try c.decodeIfPresent(Int.self, forKey: .duration) ?? 0
        startTime    = try c.decodeIfPresent(Int.self, forKey: .startTime)
        date         = try c.decodeIfPresent(Date.self, forKey: .date)
        bakeFlag     = try c.decodeIfPresent(Bool.self, forKey: .bakeFlag)
        translations = try c.decodeIfPresent([String: InstructionTextFB].self, forKey: .translations) ?? [:]
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
