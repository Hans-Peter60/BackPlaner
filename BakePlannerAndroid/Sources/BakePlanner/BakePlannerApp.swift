import Foundation
import SkipFuse
import SwiftUI

/// A logger for the BakePlanner module.
let logger: Logger = Logger(subsystem: "de.hpm64625.bakeplanner", category: "BakePlanner")

/// The shared top-level view for the app, loaded from the platform-specific App delegates below.
///
/// The default implementation merely loads the `ContentView` for the app and logs a message.
/* SKIP @bridge */public struct BakePlannerRootView : View {
    /* SKIP @bridge */public init() {
    }

    public var body: some View {
        ContentView()
            .task {
                logger.info("Skip app logs are viewable in the Xcode console for iOS; Android logs can be viewed in Studio or using adb logcat")
            }
    }
}

/// Global application delegate functions.
///
/// These functions can update a shared observable object to communicate app state changes to interested views.
/* SKIP @bridge */public final class BakePlannerAppDelegate : Sendable {
    /* SKIP @bridge */public static let shared = BakePlannerAppDelegate()

    private init() {
    }

    /* SKIP @bridge */public func onInit() {
        logger.debug("onInit")
        PublicRecipeService.configure()
        // Before any view or the model reads a setting (SettingsFile).
        SettingsFile.restore()
        // The user's own units join the unit table before any amount is weighed.
        CustomUnitFile.install()
    }

    /* SKIP @bridge */public func onLaunch() {
        logger.debug("onLaunch")
    }

    /// A text another app shared with BakePlanner — a recipe page's address
    /// from the browser. Called by MainActivity (Main.kt) on the main thread.
    /* SKIP @bridge */public func onSharedText(_ text: String) {
        logger.debug("onSharedText")
        Task { @MainActor in
            SharedImport.shared.receive(text: text)
        }
    }

    /// An action taken on a reminder notification — "done", or "postpone"
    /// by `minutes`, alone or with the plan's later steps. Called by
    /// ReminderActionReceiver (Reminders.kt), also when the app was not
    /// running: the Application has set Swift up by then.
    /* SKIP @bridge */public func onReminderAction(_ identifier: String, action: String, minutes: Int, includeFollowing: Bool) {
        logger.debug("onReminderAction \(action)")
        Task { @MainActor in
            await ReminderActions.perform(identifier: identifier, action: action, minutes: minutes, includeFollowing: includeFollowing)
        }
    }

    /* SKIP @bridge */public func onResume() {
        logger.debug("onResume")
    }

    /* SKIP @bridge */public func onPause() {
        logger.debug("onPause")
    }

    /* SKIP @bridge */public func onStop() {
        logger.debug("onStop")
    }

    /* SKIP @bridge */public func onDestroy() {
        logger.debug("onDestroy")
    }

    /* SKIP @bridge */public func onLowMemory() {
        logger.debug("onLowMemory")
    }
}
