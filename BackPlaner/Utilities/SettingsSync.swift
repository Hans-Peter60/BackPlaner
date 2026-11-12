//
//  SettingsSync.swift
//  BackPlaner
//
//  The settings, the saved collections and the custom units follow the
//  user from one device to the next through iCloud's key-value store —
//  the recipes, plans and the pantry already do through CloudKit, and a
//  new iPhone used to come up with every switch back at its default.
//
//  UserDefaults stays the single place the app reads from; this mirror
//  copies tracked keys into the key-value store when they change here and
//  back into the defaults when another device changed them. The last
//  writer wins, as with every key-value store.
//

import Foundation
import BakePlannerCore

/// What the mirror needs of a key-value store, so a test can hand in a
/// dictionary instead of iCloud.
protocol SettingsKeyValueStore: AnyObject {
    func object(forKey key: String) -> Any?
    func set(_ value: Any?, forKey key: String)
    func removeObject(forKey key: String)
    var dictionaryRepresentation: [String: Any] { get }
    @discardableResult func synchronize() -> Bool
}

extension NSUbiquitousKeyValueStore: SettingsKeyValueStore {}

/// A key-value store in memory, for the tests.
final class InMemorySettingsKeyValueStore: SettingsKeyValueStore {
    private(set) var values: [String: Any] = [:]
    func object(forKey key: String) -> Any? { values[key] }
    func set(_ value: Any?, forKey key: String) {
        if let value { values[key] = value } else { values[key] = nil }
    }
    func removeObject(forKey key: String) { values[key] = nil }
    var dictionaryRepresentation: [String: Any] { values }
    func synchronize() -> Bool { true }
}

final class SettingsSync {

    @MainActor static let shared = SettingsSync(defaults: .standard, store: NSUbiquitousKeyValueStore.default)

    /// Posted on the main queue after values from another device were
    /// written into the defaults; stores that keep a copy in memory
    /// (custom units, saved collections) reload on it.
    static let didApplyRemoteChanges = NSNotification.Name("SettingsSync.didApplyRemoteChanges")

    /// Keys that travel: the settings and the tin calculator's inputs by
    /// prefix, plus the saved collections, the custom units and the
    /// shopping list's pantry switch.
    static let trackedPrefixes = ["settings.", "calculator."]
    static let trackedKeys: Set<String> = ["savedRecipeCollections", "units.custom", "shoppingList.deductsPantry"]

    /// Settings that belong to the device, not to the person: the language
    /// (one may read German on the phone and English on the iPad), the
    /// consent to the cloud analysis (given on each device, as its dialog
    /// says), and the filters and layouts a screen was last left in.
    static let excludedKeys: Set<String> = [
        AppSettingsKeys.selectedLanguage,
        AppSettingsKeys.cloudRecipeAnalysisConsent,
        AppSettingsKeys.bakeHistoryLayout,
        AppSettingsKeys.showLocalRecipes,
        AppSettingsKeys.showOwnPublishedRecipes,
        AppSettingsKeys.showPublicCloudRecipes,
        AppSettingsKeys.showVariantRecipes,
    ]

    static func isTracked(_ key: String) -> Bool {
        guard !excludedKeys.contains(key) else { return false }
        return trackedKeys.contains(key) || trackedPrefixes.contains { key.hasPrefix($0) }
    }

    private let defaults: UserDefaults
    private let store: SettingsKeyValueStore
    private var observers: [NSObjectProtocol] = []
    /// Set while remote values are written into the defaults, so the
    /// defaults' own change notification does not push them straight back.
    private var isApplyingRemote = false

    init(defaults: UserDefaults, store: SettingsKeyValueStore) {
        self.defaults = defaults
        self.store = store
    }

    deinit {
        observers.forEach(NotificationCenter.default.removeObserver)
    }

    /// Starts mirroring: what iCloud already holds comes in, what only this
    /// device holds goes out, and from then on both directions follow the
    /// change notifications.
    func start() {
        guard observers.isEmpty else { return }
        observers.append(NotificationCenter.default.addObserver(
            forName: NSUbiquitousKeyValueStore.didChangeExternallyNotification, object: store as AnyObject,
            queue: .main) { [weak self] notification in
                let keys = notification.userInfo?[NSUbiquitousKeyValueStoreChangedKeysKey] as? [String]
                self?.applyRemote(keys: keys)
            })
        observers.append(NotificationCenter.default.addObserver(
            forName: UserDefaults.didChangeNotification, object: defaults, queue: .main) { [weak self] _ in
                self?.pushLocal()
            })
        store.synchronize()
        applyRemote(keys: nil)
        pushLocal()
    }

    /// Writes the store's values for `keys` (every tracked key when nil)
    /// into the defaults where they differ; a key the store no longer has
    /// is removed here too.
    func applyRemote(keys: [String]?) {
        let candidates = keys ?? Array(store.dictionaryRepresentation.keys)
        var changed = false
        isApplyingRemote = true
        for key in candidates where Self.isTracked(key) {
            let remote = store.object(forKey: key)
            let local = defaults.object(forKey: key)
            guard !Self.equal(remote, local) else { continue }
            if let remote {
                defaults.set(remote, forKey: key)
            } else if keys != nil {
                defaults.removeObject(forKey: key)
            } else {
                continue
            }
            changed = true
        }
        isApplyingRemote = false
        if changed {
            NotificationCenter.default.post(name: Self.didApplyRemoteChanges, object: self)
        }
    }

    /// Copies every tracked default whose value the store does not have
    /// yet, or has differently, into the store.
    func pushLocal() {
        guard !isApplyingRemote else { return }
        for (key, value) in defaults.dictionaryRepresentation() where Self.isTracked(key) {
            guard !Self.equal(value, store.object(forKey: key)) else { continue }
            store.set(value, forKey: key)
        }
    }

    private static func equal(_ a: Any?, _ b: Any?) -> Bool {
        switch (a, b) {
        case (nil, nil): return true
        case let (a?, b?): return (a as AnyObject).isEqual(b)
        default: return false
        }
    }
}
