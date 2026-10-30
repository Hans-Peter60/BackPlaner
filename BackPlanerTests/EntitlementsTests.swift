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
        #expect(resolution.unlocked)
        #expect(!resolution.isPro)
        #expect(!resolution.storeVisible)
        #expect(!resolution.proRequired)
    }

    @Test("proRequired locks an installation without Pro")
    func proRequiredLocks() {
        let config = MonetizationConfig(proRequired: true, storeVisible: true)
        let resolution = Entitlements.resolve(config: config, purchased: false, originalAppVersion: "12")
        #expect(!resolution.unlocked)
        #expect(resolution.storeVisible)
    }

    @Test("A purchase unlocks, and shows the store even while it is hidden")
    func purchaseUnlocks() {
        let config = MonetizationConfig(proRequired: true, storeVisible: false)
        let resolution = Entitlements.resolve(config: config, purchased: true, originalAppVersion: nil)
        #expect(resolution.unlocked)
        #expect(resolution.isPro)
        #expect(resolution.storeVisible)
        #expect(!resolution.isGrandfathered)
    }

    @Test("storeVisible shows the store without locking anything")
    func storeVisibleAlone() {
        let config = MonetizationConfig(proRequired: false, storeVisible: true)
        let resolution = Entitlements.resolve(config: config, purchased: false, originalAppVersion: nil)
        #expect(resolution.unlocked)
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
        #expect(old.unlocked)

        let atThreshold = Entitlements.resolve(config: config, purchased: false, originalAppVersion: "10")
        #expect(!atThreshold.isGrandfathered)
        #expect(!atThreshold.unlocked)
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
