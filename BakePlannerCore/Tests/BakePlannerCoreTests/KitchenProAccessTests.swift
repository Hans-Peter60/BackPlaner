//
//  KitchenProAccessTests.swift
//  BakePlannerCoreTests
//
//  CookPlanner Pro: the decision per feature and the reading of the
//  switches from Firestore's REST answer.
//

import Foundation
import Testing
@testable import BakePlannerCore

@Suite("CookPlanner Pro access")
struct KitchenProAccessTests {

    @Test("Without a configuration every feature is open and no store shows")
    func freeConfig() {
        for feature in KitchenProFeature.allCases {
            #expect(KitchenProAccess.unlocked(feature, config: .free, purchased: false))
        }
        #expect(!KitchenProAccess.storeVisible(config: .free, purchased: false))
    }

    @Test("Required Pro locks every feature until it is bought")
    func requiredLocks() {
        let config = MonetizationConfig(proRequired: true)
        for feature in KitchenProFeature.allCases {
            #expect(!KitchenProAccess.unlocked(feature, config: config, purchased: false))
            #expect(KitchenProAccess.unlocked(feature, config: config, purchased: true))
        }
    }

    @Test("A grandfathering build in the document changes nothing for CookPlanner")
    func noGrandfathering() {
        let config = MonetizationConfig(proRequired: true, grandfatherBeforeBuild: "999")
        #expect(!KitchenProAccess.unlocked(.menu, config: config, purchased: false))
    }

    @Test("The store shows when switched visible, when Pro is required, or after a purchase")
    func storeVisibility() {
        #expect(KitchenProAccess.storeVisible(config: MonetizationConfig(storeVisible: true), purchased: false))
        #expect(KitchenProAccess.storeVisible(config: MonetizationConfig(proRequired: true), purchased: false))
        #expect(KitchenProAccess.storeVisible(config: .free, purchased: true))
    }

    @Test("Firestore's REST fields are unwrapped by type")
    func restFields() {
        let fields: [String: Any] = [
            "proRequired": ["booleanValue": true],
            "storeVisible": ["booleanValue": false],
            "freeImportsPerMonth": ["integerValue": "5"],
            "ignored": ["mapValue": ["fields": [:]]],
        ]
        let config = MonetizationConfig(firestoreRESTFields: fields)
        #expect(config.proRequired)
        #expect(!config.storeVisible)
        #expect(config.freeImportsPerMonth == 5)
    }

    @Test("Mistyped REST fields keep the free defaults")
    func mistypedRestFields() {
        let fields: [String: Any] = [
            "proRequired": ["stringValue": "true"],
            "freeImportsPerMonth": ["integerValue": "viele"],
            "storeVisible": "true",
        ]
        #expect(MonetizationConfig(firestoreRESTFields: fields) == .free)
    }
}
