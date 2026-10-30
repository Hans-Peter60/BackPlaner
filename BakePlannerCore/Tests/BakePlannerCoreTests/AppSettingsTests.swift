//
//  AppSettingsTests.swift
//  BakePlannerCoreTests
//
//  The settings' parts that do not read UserDefaults: the stored raw
//  values, the starter presets typed in the settings, and the texts the
//  app writes into a plan or recipe in the chosen language.
//

import Foundation
import Testing
@testable import BakePlannerCore

@Suite("Settings")
struct AppSettingsTests {

    @Test("Stored raw values keep their spelling")
    func rawValues() {
        #expect(AppLanguage.allCases.map(\.rawValue) == ["", "de", "en", "fr"])
        #expect(RecipeStoragePreference.privateRecipe.rawValue == "privateRecipe")
        #expect(RecipeStoragePreference.publicRecipe.rawValue == "publicRecipe")
        #expect(RecipeStoragePreference(rawValue: "privateCloudRecipe") == nil)
        #expect(AppSettings.defaultRecipeStorage == "privateRecipe")
    }

    @Test("The publish switch picks the storage")
    func storageFromSwitch() {
        #expect(RecipeStoragePreference(publishes: true) == .publicRecipe)
        #expect(RecipeStoragePreference(publishes: false) == .privateRecipe)
        #expect(RecipeStoragePreference.publicRecipe.publishes)
        #expect(!RecipeStoragePreference.privateRecipe.publishes)
    }

    @Test("Starter presets are read from free text")
    func starterPresets() {
        #expect(AppSettings.starterDoughYieldPresets(from: "190, 210,220") == [190, 210, 220])
        #expect(AppSettings.starterDoughYieldPresets(from: "220; 190 abc 50 210 210") == [190, 210, 220])
        #expect(AppSettings.starterDoughYieldPresets(from: "TA 190 / TA 210") == [190, 210])
        #expect(AppSettings.starterDoughYieldPresets(from: "") == [150, 180, 200, 220])
    }

    @Test("Generated plan steps follow the language, regional variants included")
    func generatedStepTexts() {
        #expect(AppSettings.generatedStepTexts(languageCode: "de").startHeating == "Backofen anstellen")
        #expect(AppSettings.generatedStepTexts(languageCode: "en_US").startHeating == "Turn on the oven")
        #expect(AppSettings.generatedStepTexts(languageCode: "fr-CA").bakeEnd == "La cuisson est terminée")
        #expect(AppSettings.generatedStepTexts(languageCode: "it").startHeating == "Backofen anstellen")
    }

    @Test("Generated recipe texts follow the language")
    func generatedRecipeTexts() {
        #expect(AppSettings.generatedRecipeTexts(languageCode: "de").importedRecipe == "Importiertes Rezept")
        #expect(AppSettings.generatedRecipeTexts(languageCode: "en").componentFormat == "Component %lld")
        #expect(AppSettings.generatedRecipeTexts(languageCode: "fr").missingComment == "aucun commentaire")
    }

    @Test("A chosen language is used as the locale, none means the system's")
    func localeIdentifier() {
        #expect(AppSettings.localeIdentifier(for: "fr") == "fr")
        #expect(AppSettings.localeIdentifier(for: "") == Locale.autoupdatingCurrent.identifier)
    }
}
