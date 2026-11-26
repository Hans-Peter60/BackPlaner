//
//  CookPlannerShortcuts.swift
//  CookPlanner
//
//  The phrases Siri answers to without any setup. Every phrase names the
//  app (`\(.applicationName)`), which is how Siri tells them from every
//  other app's; the one with `\(\.$dish)` expands to one phrase per dish.
//  The phrases are a contract with whoever has learnt them: new ones may
//  be added, shipped ones should stay. Their translations live in
//  AppShortcuts.xcstrings.
//

import AppIntents

struct CookPlannerShortcuts: AppShortcutsProvider {

    static let shortcutTileColor: ShortcutTileColor = .orange

    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: CurrentStepIntent(),
            phrases: [
                "Was steht in \(.applicationName) an",
                "Nächster Schritt in \(.applicationName)",
                "\(.applicationName) was kommt jetzt"
            ],
            shortTitle: "Was steht an",
            systemImageName: "hand.raised.fill"
        )
        AppShortcut(
            intent: MarkStepDoneIntent(),
            phrases: [
                "Schritt erledigt in \(.applicationName)",
                "\(.applicationName) erledigt",
                "\(.applicationName) steht"
            ],
            shortTitle: "Schritt erledigt",
            systemImageName: "checkmark.circle.fill"
        )
        AppShortcut(
            intent: TimeLeftIntent(),
            phrases: [
                "Wie lange noch in \(.applicationName)",
                "\(.applicationName) wie lange noch"
            ],
            shortTitle: "Wie lange noch",
            systemImageName: "timer"
        )
        AppShortcut(
            intent: StartCookingIntent(),
            phrases: [
                "Koche \(\.$dish) mit \(.applicationName)",
                "\(\.$dish) in \(.applicationName) kochen",
                "Kochen starten in \(.applicationName)"
            ],
            shortTitle: "Kochen starten",
            systemImageName: "play.fill"
        )
    }
}
