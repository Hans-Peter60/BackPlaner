//
//  ProAccessTests.swift
//  BakePlannerCoreTests
//
//  "May this Pro feature be used?" in every combination of remote
//  configuration, purchase and grandfathering, and the reading of the
//  Firestore document that feeds it. Shared by both apps.
//

import Foundation
import Testing
@testable import BakePlannerCore

@Suite("Pro access: the shared decision")
struct ProAccessTests {

    @Test("Without a configuration everything is free")
    func freeConfigUnlocksEverything() {
        let resolution = ProAccess.resolve(config: .free, purchased: false, originalAppVersion: nil)
        #expect(resolution.unlocksEverything)
        #expect(!resolution.isPro)
        #expect(!resolution.storeVisible)
        #expect(!resolution.proRequired)
    }

    @Test("proRequired locks an installation without Pro")
    func proRequiredLocks() {
        let config = MonetizationConfig(proRequired: true, storeVisible: true)
        let resolution = ProAccess.resolve(config: config, purchased: false, originalAppVersion: "12")
        #expect(!resolution.unlocked(.shoppingList))
        #expect(resolution.storeVisible)
    }

    @Test("A purchase unlocks, and shows the store even while it is hidden")
    func purchaseUnlocks() {
        let config = MonetizationConfig(proRequired: true, storeVisible: false)
        let resolution = ProAccess.resolve(config: config, purchased: true, originalAppVersion: nil)
        #expect(resolution.unlocksEverything)
        #expect(resolution.isPro)
        #expect(resolution.storeVisible)
        #expect(!resolution.isGrandfathered)
    }

    @Test("storeVisible shows the store without locking anything")
    func storeVisibleAlone() {
        let config = MonetizationConfig(proRequired: false, storeVisible: true)
        let resolution = ProAccess.resolve(config: config, purchased: false, originalAppVersion: nil)
        #expect(resolution.unlocksEverything)
        #expect(resolution.storeVisible)
        #expect(!resolution.isPro)
    }

    @Test("An installation from before the threshold build is grandfathered")
    func grandfathered() {
        let config = MonetizationConfig(proRequired: true, grandfatherBeforeBuild: "10")
        let old = ProAccess.resolve(config: config, purchased: false, originalAppVersion: "8")
        #expect(old.isGrandfathered && old.isPro && old.unlocked(.shoppingList))
        let atThreshold = ProAccess.resolve(config: config, purchased: false, originalAppVersion: "10")
        #expect(!atThreshold.isGrandfathered && !atThreshold.unlocked(.shoppingList))
    }

    @Test("A grandfathered installation keeps the features it had on its day; what came later needs the purchase")
    func grandfatheredPerFeature() {
        let config = MonetizationConfig(proRequired: true, grandfatherBeforeBuild: "30")
        // Downloaded with 2.3 (20): the shopping list was there, the pantry was not.
        let fromTwoThree = ProAccess.resolve(config: config, purchased: false, originalAppVersion: "20")
        #expect(fromTwoThree.unlocked(.shoppingList) && fromTwoThree.unlocked(.widgets) && fromTwoThree.unlocked(.pdfExport))
        #expect(!fromTwoThree.unlocked(.pantry) && !fromTwoThree.unlocked(.bakingDay))
        #expect(!fromTwoThree.unlocked(.collections) && !fromTwoThree.unlocked(.statistics) && !fromTwoThree.unlocked(.bakersFormula))
        #expect(!fromTwoThree.unlocksEverything)
        #expect(fromTwoThree.isPro) // the cloud imports were free then too
        // Downloaded with 2.4 (21), still before Pro: everything of 2.4 stays.
        let fromTwoFour = ProAccess.resolve(config: config, purchased: false, originalAppVersion: "21")
        #expect(fromTwoFour.unlocked(.pantry) && fromTwoFour.unlocked(.collections))
        #expect(fromTwoFour.unlocksEverything)
        // "21.0" reads as 21; a purchase opens everything regardless.
        #expect(ProAccess.buildNumber("21.0") == 21 && ProAccess.buildNumber("abc") == nil)
        #expect(ProAccess.resolve(config: config, purchased: true, originalAppVersion: "8").unlocksEverything)
        // Without the requirement everything is open, grandfathered or not.
        #expect(ProAccess.resolve(config: .free, purchased: false, originalAppVersion: "8").unlocksEverything)
    }

    @Test("Every Pro feature names the build it appeared in; the newer ones came with 2.4 (21)")
    func introducedBuilds() {
        for feature in ProFeature.allCases {
            #expect(feature.introducedBuild >= 1)
        }
        #expect(ProFeature.pantry.introducedBuild == 21 && ProFeature.shoppingList.introducedBuild == 1)
        #expect(ProFeature.allCases.count == 11)
    }

    @Test("Builds compare as numbers, not as text")
    func grandfatheringIsNumeric() {
        let config = MonetizationConfig(grandfatherBeforeBuild: "10")
        #expect(config.grandfathers(originalAppVersion: "9"))
        #expect(!config.grandfathers(originalAppVersion: "100"))
        // The sandbox always reports "1.0".
        #expect(config.grandfathers(originalAppVersion: "1.0"))
    }

    @Test("Nobody is grandfathered without a threshold or without a receipt")
    func grandfatheringNeedsBothSides() {
        #expect(!MonetizationConfig().grandfathers(originalAppVersion: "1"))
        #expect(!MonetizationConfig(grandfatherBeforeBuild: "10").grandfathers(originalAppVersion: nil))
        #expect(!MonetizationConfig(grandfatherBeforeBuild: "soon").grandfathers(originalAppVersion: "1"))
    }

    @Test("A complete document is read field by field")
    func firestoreDocument() {
        let config = MonetizationConfig(firestoreData: [
            "proRequired": true,
            "storeVisible": true,
            "freeImportsPerMonth": 3,
            "grandfatherBeforeBuild": "9",
        ])
        #expect(config == MonetizationConfig(proRequired: true, storeVisible: true,
                                             freeImportsPerMonth: 3, grandfatherBeforeBuild: "9"))
    }

    @Test("Missing or mistyped fields keep their free value")
    func firestoreDocumentTolerance() {
        let config = MonetizationConfig(firestoreData: [
            "proRequired": "yes",
            "freeImportsPerMonth": -2,
            "grandfatherBeforeBuild": "",
        ])
        #expect(config == .free)
        // A build typed as a number in the console still works, as does a count typed as a decimal.
        let numeric = MonetizationConfig(firestoreData: ["grandfatherBeforeBuild": 9, "freeImportsPerMonth": 5.0])
        #expect(numeric.grandfatherBeforeBuild == "9" && numeric.freeImportsPerMonth == 5)
    }

    @Test("An empty document is free")
    func emptyDocument() {
        #expect(MonetizationConfig(firestoreData: [:]) == .free)
    }

    @Test("The configuration survives JSON for the cache")
    func codableRoundTrip() throws {
        let config = MonetizationConfig(proRequired: true, storeVisible: true, freeImportsPerMonth: 3, grandfatherBeforeBuild: "22")
        let data = try JSONEncoder().encode(config)
        #expect(try JSONDecoder().decode(MonetizationConfig.self, from: data) == config)
    }
}
