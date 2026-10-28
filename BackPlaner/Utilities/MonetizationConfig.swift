//
//  MonetizationConfig.swift
//  BackPlaner
//
//  The remote switches of the Pro purchase. Everything about Pro is built
//  into the app, but nothing of it shows or locks until the Firestore
//  document `config/monetization` says so. That document is written only
//  from the Firebase console (the rules refuse every client write), so one
//  edit there turns the purchase on for every installation — and one edit
//  turns it off again, without a new app version.
//
//  Fail open, always: a missing document, a failed read or a document that
//  was never loaded all mean "free". A network problem can therefore never
//  lock a feature by accident; the only way to lock one is the console.
//

import Foundation
import FirebaseAuth
import FirebaseFirestore
import Observation
import os

/// The document `config/monetization`, field by field. Every field has the
/// "free" value as its default, so a document that leaves a field out keeps
/// that part of the app open.
struct MonetizationConfig: Codable, Equatable, Sendable {

    /// Whether the Pro features are locked for everyone who has not bought
    /// Pro (and is not covered by `grandfatherBeforeBuild`). While false the
    /// purchase exists in the code but locks nothing.
    var proRequired = false

    /// Whether the settings show the Pro section and the features offer the
    /// paywall. Lets the store be shown — for the App Review, for a first
    /// round of purchases — before anything is locked. Someone who bought
    /// Pro sees the section regardless, so the purchase is never invisible.
    var storeVisible = false

    /// Cloud imports (photo and web page analysis) a month without Pro.
    /// 0 means no monthly limit; the hourly limit in the Functions applies
    /// either way. The server reads this same document, so the app and the
    /// Functions switch together.
    var freeImportsPerMonth = 0

    /// The build number (CFBundleVersion) before which an installation
    /// counts as Pro without a purchase — the people who had the shopping
    /// list and the PDF export before they became Pro features keep them.
    /// Compared against `AppTransaction.originalAppVersion`, which on iOS
    /// carries the build number of the version first downloaded. nil means
    /// nobody is grandfathered.
    var grandfatherBeforeBuild: String?

    /// Nothing shown, nothing locked, no monthly limit.
    static let free = MonetizationConfig()

    init(proRequired: Bool = false, storeVisible: Bool = false,
         freeImportsPerMonth: Int = 0, grandfatherBeforeBuild: String? = nil) {
        self.proRequired = proRequired
        self.storeVisible = storeVisible
        self.freeImportsPerMonth = freeImportsPerMonth
        self.grandfatherBeforeBuild = grandfatherBeforeBuild
    }

    /// Reads the Firestore document's fields, tolerating a missing or
    /// mistyped field by keeping its free default: a typo in the console
    /// must not lock the app.
    init(firestoreData data: [String: Any]) {
        proRequired = data["proRequired"] as? Bool ?? false
        storeVisible = data["storeVisible"] as? Bool ?? false
        if let number = data["freeImportsPerMonth"] as? NSNumber {
            freeImportsPerMonth = max(0, number.intValue)
        }
        if let build = data["grandfatherBeforeBuild"] as? String, !build.isEmpty {
            grandfatherBeforeBuild = build
        } else if let build = data["grandfatherBeforeBuild"] as? NSNumber {
            grandfatherBeforeBuild = build.stringValue
        }
    }

    /// Whether an installation first downloaded as `originalAppVersion`
    /// (a build number, see `grandfatherBeforeBuild`) counts as Pro.
    /// Numeric comparison, so build "9" stays before build "10".
    func grandfathers(originalAppVersion: String?) -> Bool {
        guard let threshold = grandfatherBeforeBuild, let original = originalAppVersion else { return false }
        return original.compare(threshold, options: .numeric) == .orderedAscending
    }
}

/// Loads `config/monetization` and keeps it current while the app runs.
///
/// The last document read is cached in the App Group, so the next launch
/// starts from it before Firestore answers, and the widget extension can
/// read the resolved state (see `Entitlements`). The first read waits for
/// the anonymous sign-in: the rules let only signed-in users read the
/// document.
@Observable
@MainActor
final class MonetizationConfigStore {

    static let shared = MonetizationConfigStore()

    static let documentPath = "config/monetization"
    private static let cacheKey = "monetization.config"

    /// The configuration in force: the UI-test override, else the last
    /// document read, else the cache, else free.
    private(set) var config: MonetizationConfig

    /// Whether a document (or its absence) has been read in this run.
    private(set) var hasLoaded = false

    private let defaults: UserDefaults?
    private var listener: ListenerRegistration?
    private var authListener: AuthStateDidChangeListenerHandle?

    init(defaults: UserDefaults? = UserDefaults(suiteName: PlanSnapshot.appGroupIdentifier)) {
        self.defaults = defaults
        if let override = UITestSupport.monetizationOverride {
            config = override.config
            hasLoaded = true
        } else if let data = defaults?.data(forKey: Self.cacheKey),
                  let cached = try? JSONDecoder().decode(MonetizationConfig.self, from: data) {
            config = cached
        } else {
            config = .free
        }
    }

    /// Starts following the document. Called once at launch; harmless to
    /// call again. Does nothing under a UI-test override, which fixes the
    /// configuration for the test.
    func start() {
        guard listener == nil, authListener == nil, UITestSupport.monetizationOverride == nil else { return }
        authListener = Auth.auth().addStateDidChangeListener { [weak self] _, user in
            Task { @MainActor in
                guard let self else { return }
                if user != nil {
                    self.listen()
                } else {
                    self.listener?.remove()
                    self.listener = nil
                }
            }
        }
    }

    private func listen() {
        guard listener == nil else { return }
        listener = Firestore.firestore().document(Self.documentPath)
            .addSnapshotListener { [weak self] snapshot, error in
                Task { @MainActor in
                    guard let self else { return }
                    if let error {
                        // Keep what we have: the cache, or free. Never lock
                        // anything because of a failed read.
                        AppLog.firebase.error("Monetization config could not be read: \(error.localizedDescription)")
                        return
                    }
                    guard let snapshot else { return }
                    let loaded = snapshot.exists
                        ? MonetizationConfig(firestoreData: snapshot.data() ?? [:])
                        : .free
                    self.apply(loaded)
                }
            }
    }

    /// Takes a configuration as read (or decided) and remembers it for the
    /// next launch.
    func apply(_ loaded: MonetizationConfig) {
        hasLoaded = true
        guard loaded != config else { return }
        config = loaded
        if let data = try? JSONEncoder().encode(loaded) {
            defaults?.set(data, forKey: Self.cacheKey)
        }
        AppLog.firebase.info("Monetization config: proRequired=\(loaded.proRequired) storeVisible=\(loaded.storeVisible) freeImportsPerMonth=\(loaded.freeImportsPerMonth)")
    }
}
