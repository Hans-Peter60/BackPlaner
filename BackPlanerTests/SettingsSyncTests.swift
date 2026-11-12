//
//  SettingsSyncTests.swift
//  BackPlanerTests
//
//  The mirror between the defaults and iCloud's key-value store, with a
//  store in memory: what travels, what stays, and that nothing echoes.
//

import BakePlannerCore
import Foundation
import Testing
@testable import BackPlaner

@Suite("Settings mirror to iCloud's key-value store")
struct SettingsSyncTests {

    private func freshDefaults() -> UserDefaults {
        let name = "SettingsSyncTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        return defaults
    }

    @Test("Settings, the tin calculator, saved collections and custom units travel; language, consent and list filters stay")
    func trackedKeys() {
        #expect(SettingsSync.isTracked(AppSettingsKeys.ovenCount))
        #expect(SettingsSync.isTracked(AppSettingsKeys.starterDoughYieldPresets))
        #expect(SettingsSync.isTracked(AppSettingsKeys.tinLengthCm))
        #expect(SettingsSync.isTracked("savedRecipeCollections"))
        #expect(SettingsSync.isTracked("units.custom"))
        #expect(SettingsSync.isTracked("shoppingList.deductsPantry"))
        #expect(!SettingsSync.isTracked(AppSettingsKeys.selectedLanguage))
        #expect(!SettingsSync.isTracked(AppSettingsKeys.cloudRecipeAnalysisConsent))
        #expect(!SettingsSync.isTracked(AppSettingsKeys.showLocalRecipes))
        #expect(!SettingsSync.isTracked(AppSettingsKeys.bakeHistoryLayout))
        #expect(!SettingsSync.isTracked("ugc.blockedAuthors"))
        #expect(!SettingsSync.isTracked("pantryBookings"))
    }

    @Test("Local values go into the store, the store's values come into the defaults, untracked keys stay home")
    func bothDirections() {
        let defaults = freshDefaults()
        let store = InMemorySettingsKeyValueStore()
        defaults.set(2, forKey: AppSettingsKeys.ovenCount)
        defaults.set("de", forKey: AppSettingsKeys.selectedLanguage)
        store.set(45, forKey: AppSettingsKeys.preheatTime)
        store.set(Data([1, 2, 3]), forKey: "savedRecipeCollections")
        store.set("en", forKey: AppSettingsKeys.selectedLanguage)

        let sync = SettingsSync(defaults: defaults, store: store)
        sync.applyRemote(keys: nil)
        sync.pushLocal()

        #expect(defaults.integer(forKey: AppSettingsKeys.preheatTime) == 45)
        #expect(defaults.data(forKey: "savedRecipeCollections") == Data([1, 2, 3]))
        #expect(defaults.string(forKey: AppSettingsKeys.selectedLanguage) == "de")
        #expect(store.object(forKey: AppSettingsKeys.ovenCount) as? Int == 2)
        #expect(store.object(forKey: AppSettingsKeys.selectedLanguage) as? String == "en")
    }

    @Test("A change from another device replaces the local value, a removal removes it; nothing is pushed back")
    func remoteChange() {
        let defaults = freshDefaults()
        let store = InMemorySettingsKeyValueStore()
        defaults.set(10, forKey: AppSettingsKeys.bakePause)
        defaults.set(true, forKey: "shoppingList.deductsPantry")
        let sync = SettingsSync(defaults: defaults, store: store)
        sync.pushLocal()
        #expect(store.object(forKey: AppSettingsKeys.bakePause) as? Int == 10)

        store.set(20, forKey: AppSettingsKeys.bakePause)
        store.removeObject(forKey: "shoppingList.deductsPantry")
        sync.applyRemote(keys: [AppSettingsKeys.bakePause, "shoppingList.deductsPantry"])
        #expect(defaults.integer(forKey: AppSettingsKeys.bakePause) == 20)
        #expect(defaults.object(forKey: "shoppingList.deductsPantry") == nil)
        // The full pass afterwards changes nothing and pushes nothing back.
        sync.pushLocal()
        #expect(store.object(forKey: "shoppingList.deductsPantry") == nil)
        #expect(store.object(forKey: AppSettingsKeys.bakePause) as? Int == 20)
    }
}
