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

    // The decision itself — configuration, purchase, grandfathering per
    // feature, the Firestore document — is the package's and tested in
    // BakePlannerCoreTests/ProAccessTests. Here: what the app adds.

    @Test("The app's wrapper hands the decision to the package unchanged")
    func wrapperDelegates() {
        let config = MonetizationConfig(proRequired: true, grandfatherBeforeBuild: "30")
        let viaApp = Entitlements.resolve(config: config, purchased: false, originalAppVersion: "20")
        let viaPackage = ProAccess.resolve(config: config, purchased: false, originalAppVersion: "20")
        #expect(viaApp == viaPackage)
        #expect(viaApp.unlocked(.shoppingList) && !viaApp.unlocked(.pantry))
    }

    @Test("Every Pro feature has a title, a description and a symbol in the app")
    func featureTexts() {
        for feature in ProFeature.allCases {
            #expect(!feature.symbolName.isEmpty)
            _ = feature.title
            _ = feature.detail
        }
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
