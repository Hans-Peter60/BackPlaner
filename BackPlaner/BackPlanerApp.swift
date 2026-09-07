//
//  BackPlanerApp.swift
//  BackPlaner
//
//  Created by Hans-Peter Müller on 08.02.24.
//

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

    FirebaseApp.configure()

    // One-time store maintenance: remove objects that were orphaned while the
    // Core Data model still used Nullify delete rules.
    PersistenceController.shared.cleanUpOrphanedObjectsIfNeeded()

    // Present reminders in the foreground and register their iPhone/Watch actions.
    UNUserNotificationCenter.current().delegate = self
    NotificationActions.registerCategories()

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

    let persistenceController = PersistenceController.shared

//    init() {
//        FirebaseApp.configure()
        
//        let recipeDb = Firestore.firestore()
//    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(\.managedObjectContext, persistenceController.container.viewContext)
                .environment(\.locale, Locale(identifier: AppSettings.localeIdentifier(for: selectedLanguage)))
        }
    }
}
