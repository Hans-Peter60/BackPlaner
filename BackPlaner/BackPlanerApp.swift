//
//  BackPlanerApp.swift
//  BackPlaner
//
//  Created by Hans-Peter Müller on 08.02.24.
//

import BakePlannerCore
import SwiftUI
import FirebaseCore
import FirebaseFirestore
import FirebaseStorage
import FirebaseAuth
import FirebaseAppCheck
import UserNotifications
import os

/// Supplies the App Check attestation provider. In DEBUG builds (Simulator and
/// development devices) App Attest is unavailable, so the debug provider is used —
/// it prints a debug token to the console on first launch that must be registered
/// once in the Firebase console (App Check → Apps → Manage debug tokens).
/// Release builds use App Attest, backed by real device attestation.
class BackPlanerAppCheckProviderFactory: NSObject, AppCheckProviderFactory {
    func createProvider(with app: FirebaseApp) -> AppCheckProvider? {
        #if DEBUG
        return AppCheckDebugProvider(app: app)
        #else
        return AppAttestProvider(app: app)
        #endif
    }
}

class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {

  func application(_ application: UIApplication,
                   didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey : Any]? = nil) -> Bool {
    // App Check must be configured BEFORE FirebaseApp.configure() so the first
    // Firestore/Auth request already carries a valid attestation token.
    AppCheck.setAppCheckProviderFactory(BackPlanerAppCheckProviderFactory())

    // Configured even for a unit-test run: a code path that touches Firestore
    // without a configured app crashes, and configuring is local and cheap.
    FirebaseApp.configure()

    // As the host of a unit-test run the app stops here: nothing below is
    // needed by the tests, and none of it can then delay or hang the run.
    if UITestSupport.isUnitTestHost {
      return true
    }

    // One-time store maintenance: remove objects that were orphaned while the
    // Core Data model still used Nullify delete rules.
    PersistenceController.shared.cleanUpOrphanedObjectsIfNeeded()

    if UITestSupport.seedsRecipe {
      UITestSupport.seedRecipe(into: PersistenceController.shared.container.viewContext)
    }
    if let planFinish = UITestSupport.planFinish() {
      GlobalVariables.dateTimePicker = planFinish
    } else if let planStart = UITestSupport.planStart() {
      GlobalVariables.dateTimePicker = planStart
    }

    // Mirror the planned steps into the App Group for the widget, now and
    // after every change.
    PlanSnapshotPublisher.shared.start(with: PersistenceController.shared.container)

    // Follow the Pro configuration and the App Store. Until the document
    // says otherwise every feature is free, so this never delays the start.
    Entitlements.shared.start()

    // Present reminders in the foreground and register their iPhone/Watch actions.
    UNUserNotificationCenter.current().delegate = self
    NotificationActions.registerCategories()

    // Blur the backdrop photo now, off the main thread, so the first screen
    // finds it in the cache and shows it at once instead of fading it in.
    Task.detached(priority: .userInitiated) {
      BakeryBackdropImageStore.shared.prepare(for: .light)
      BakeryBackdropImageStore.shared.prepare(for: .dark)
    }

    // Sign in anonymously so each device has a stable, server-verifiable identity
    // (auth.uid) that the Firestore security rules use to enforce author-only
    // edit/delete of public recipes. No login UI — this is invisible.
    if Auth.auth().currentUser == nil {
      Auth.auth().signInAnonymously { _, error in
        if let error {
          AppLog.firebase.error("Anonymous sign-in failed: \(error)")
        }
      }
    }
    return true
  }

  func userNotificationCenter(
    _ center: UNUserNotificationCenter,
    willPresent notification: UNNotification,
    withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
  ) {
    DispatchQueue.main.async {
      completionHandler([.banner, .list, .sound])
    }
  }

  func userNotificationCenter(
    _ center: UNUserNotificationCenter,
    didReceive response: UNNotificationResponse,
    withCompletionHandler completionHandler: @escaping () -> Void
  ) {
    NotificationActions.handle(response: response) {
      DispatchQueue.main.async {
        completionHandler()
      }
    }
  }
}

@main
struct BackPlanerApp: App {
    // register app delegate for Firebase setup
    @UIApplicationDelegateAdaptor(AppDelegate.self) var delegate
    @AppStorage(AppSettingsKeys.selectedLanguage) private var selectedLanguage = AppLanguage.system.rawValue
    @Environment(\.scenePhase) private var scenePhase

    let persistenceController = PersistenceController.shared

    init() {
        // The calculation logic knows only the bundled units on its own;
        // the ones the user added come from the settings store.
        GlobalVariables.customUnitSets = { CustomUnitStore.shared.unitSets }
    }

    var body: some Scene {
        WindowGroup {
            if UITestSupport.isUnitTestHost {
                // The host of a unit-test run shows nothing: the main menu
                // would load recipes, plans and the backdrop photo for no one.
                Color.clear
            } else {
                ContentView()
                    .environment(\.managedObjectContext, persistenceController.container.viewContext)
                    .environment(\.locale, Locale(identifier: AppSettings.localeIdentifier(for: selectedLanguage)))
            }
        }
        // Coming to the foreground is the moment a Live Activity can be
        // started; the pass also catches a plan that moved on while the app
        // was away.
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                // Recurring plans are a Pro feature: locked, no occurrence
                // is queued, and the rhythm stored on the recipe waits.
                if Entitlements.shared.isUnlocked(.recurringPlans) {
                    RecurringBakePlanner.scheduleDueOccurrences(in: persistenceController.container.viewContext)
                }
                PlanSnapshotPublisher.shared.refresh()
                // The Siri phrases name each starter ("Roggensauer gefüttert"),
                // so a starter added, renamed or given a rhythm while the app
                // was open has to reach Siri's phrase list.
                BackPlanerShortcuts.updateAppShortcutParameters()
            }
        }
    }
}
