//
//  EntitlementsTests.swift
//  BackPlanerTests
//
//  The decision "may this Pro feature be used?" in every combination of
//  remote configuration, purchase and grandfathering, and the reading of
//  the Firestore document and the UI-test switch that feed it.
//

import BakePlannerCore
import Testing
import Foundation
@testable import BackPlaner

struct EntitlementsTests {

    // MARK: Resolution

    @Test("Without a configuration everything is free")
    func freeConfigUnlocksEverything() {
        let resolution = Entitlements.resolve(config: .free, purchased: false, originalAppVersion: nil)
        #expect(resolution.unlocksEverything)
        #expect(!resolution.isPro)
        #expect(!resolution.storeVisible)
        #expect(!resolution.proRequired)
    }

    @Test("proRequired locks an installation without Pro")
    func proRequiredLocks() {
        let config = MonetizationConfig(proRequired: true, storeVisible: true)
        let resolution = Entitlements.resolve(config: config, purchased: false, originalAppVersion: "12")
        #expect(!resolution.unlocked(.shoppingList))
        #expect(resolution.storeVisible)
    }

    @Test("A purchase unlocks, and shows the store even while it is hidden")
    func purchaseUnlocks() {
        let config = MonetizationConfig(proRequired: true, storeVisible: false)
        let resolution = Entitlements.resolve(config: config, purchased: true, originalAppVersion: nil)
        #expect(resolution.unlocksEverything)
        #expect(resolution.isPro)
        #expect(resolution.storeVisible)
        #expect(!resolution.isGrandfathered)
    }

    @Test("storeVisible shows the store without locking anything")
    func storeVisibleAlone() {
        let config = MonetizationConfig(proRequired: false, storeVisible: true)
        let resolution = Entitlements.resolve(config: config, purchased: false, originalAppVersion: nil)
        #expect(resolution.unlocksEverything)
        #expect(resolution.storeVisible)
        #expect(!resolution.isPro)
    }

    // MARK: Grandfathering

    @Test("An installation from before the threshold build is Pro")
    func grandfathered() {
        let config = MonetizationConfig(proRequired: true, grandfatherBeforeBuild: "10")
        let old = Entitlements.resolve(config: config, purchased: false, originalAppVersion: "8")
        #expect(old.isGrandfathered)
        #expect(old.isPro)
        #expect(old.unlocked(.shoppingList))

        let atThreshold = Entitlements.resolve(config: config, purchased: false, originalAppVersion: "10")
        #expect(!atThreshold.isGrandfathered)
        #expect(!atThreshold.unlocked(.shoppingList))
    }

    @Test("A grandfathered installation keeps the features it had on its day; what came later needs the purchase")
    func grandfatheredPerFeature() {
        let config = MonetizationConfig(proRequired: true, grandfatherBeforeBuild: "30")
        // Downloaded with 2.3 (20): the shopping list was there, the pantry was not.
        let fromTwoThree = Entitlements.resolve(config: config, purchased: false, originalAppVersion: "20")
        #expect(fromTwoThree.unlocked(.shoppingList) && fromTwoThree.unlocked(.widgets) && fromTwoThree.unlocked(.pdfExport))
        #expect(!fromTwoThree.unlocked(.pantry) && !fromTwoThree.unlocked(.bakingDay))
        #expect(!fromTwoThree.unlocked(.collections) && !fromTwoThree.unlocked(.statistics) && !fromTwoThree.unlocked(.bakersFormula))
        #expect(!fromTwoThree.unlocksEverything)
        #expect(fromTwoThree.isPro) // the cloud imports were free then too
        // Downloaded with 2.4 (21), still before Pro: everything of 2.4 stays.
        let fromTwoFour = Entitlements.resolve(config: config, purchased: false, originalAppVersion: "21")
        #expect(fromTwoFour.unlocked(.pantry) && fromTwoFour.unlocked(.collections))
        #expect(fromTwoFour.unlocksEverything)
        // "21.0" reads as 21; a purchase opens everything regardless.
        #expect(Entitlements.buildNumber("21.0") == 21 && Entitlements.buildNumber("abc") == nil)
        #expect(Entitlements.resolve(config: config, purchased: true, originalAppVersion: "8").unlocksEverything)
        // Without the requirement everything is open, grandfathered or not.
        #expect(Entitlements.resolve(config: .free, purchased: false, originalAppVersion: "8").unlocksEverything)
    }

    @Test("Every Pro feature names the build it appeared in; the newer ones came with 2.4 (21)")
    func introducedBuilds() {
        for feature in ProFeature.allCases {
            #expect(feature.introducedBuild >= 1)
        }
        #expect(ProFeature.pantry.introducedBuild == 21 && ProFeature.shoppingList.introducedBuild == 1)
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
    }

    // MARK: The Firestore document

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

        // A build typed as a number in the console still works.
        let numeric = MonetizationConfig(firestoreData: ["grandfatherBeforeBuild": 9])
        #expect(numeric.grandfatherBeforeBuild == "9")
    }

    @Test("An empty document is free")
    func emptyDocument() {
        #expect(MonetizationConfig(firestoreData: [:]) == .free)
    }

    @Test("The cached document survives a round trip")
    func codableRoundTrip() throws {
        let config = MonetizationConfig(proRequired: true, storeVisible: true,
                                        freeImportsPerMonth: 5, grandfatherBeforeBuild: "11")
        let data = try JSONEncoder().encode(config)
        #expect(try JSONDecoder().decode(MonetizationConfig.self, from: data) == config)
    }

    // MARK: The UI-test switch

    @Test("-UITestingMonetization flags")
    func overrideParsing() {
        let override = UITestSupport.monetizationOverride(
            from: "proRequired, storeVisible,purchased,freeImports=3,grandfatherBefore=9,originalBuild=8,unknown")
        #expect(override.config == MonetizationConfig(proRequired: true, storeVisible: true,
                                                      freeImportsPerMonth: 3, grandfatherBeforeBuild: "9"))
        #expect(override.purchased)
        #expect(override.originalAppVersion == "8")

        let free = UITestSupport.monetizationOverride(from: "free")
        #expect(free.config == .free)
        #expect(!free.purchased)
    }
}
