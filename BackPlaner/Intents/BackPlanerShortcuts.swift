//
//  BackPlanerShortcuts.swift
//  BackPlaner
//
//  The phrases Siri answers to without any setup. Every phrase names the
//  app (`\(.applicationName)`, "BakePlanner"), which is how Siri tells them
//  from every other app's; the ones with `\(\.$starter)` expand to one
//  phrase per starter, so "Roggensauer gefüttert" works by name.
//
//  The phrases are a contract with whoever has learnt them: new ones may be
//  added, shipped ones should stay. Their translations live in
//  AppShortcuts.xcstrings.
//

import AppIntents

struct BackPlanerShortcuts: AppShortcutsProvider {

    static let shortcutTileColor: ShortcutTileColor = .orange

    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: NextStepIntent(),
            phrases: [
                "Nächster Schritt in \(.applicationName)",
                "Was ist mein nächster Backschritt in \(.applicationName)",
                "Was steht in \(.applicationName) als Nächstes an"
            ],
            shortTitle: "Nächster Schritt",
            systemImageName: "timer"
        )
        AppShortcut(
            intent: MarkStepDoneIntent(),
            phrases: [
                "Schritt erledigt in \(.applicationName)",
                "\(.applicationName) Schritt erledigt"
            ],
            shortTitle: "Schritt erledigt",
            systemImageName: "checkmark.circle"
        )
        AppShortcut(
            intent: PostponeStepIntent(),
            // The direction expands through its titles and synonyms:
            // "… verschieben", "… nach hinten verschieben", "… vorziehen",
            // "… nach vorne verschieben", "… nach hinten", "… nach vorne".
            phrases: [
                "Nächsten Schritt in \(.applicationName) \(\.$direction)",
                "Schritt \(\.$direction) in \(.applicationName)"
            ],
            shortTitle: "Schritt verschieben",
            systemImageName: "clock.arrow.circlepath"
        )
        AppShortcut(
            intent: OvenTimeIntent(),
            phrases: [
                "Wann muss ich in \(.applicationName) in den Ofen",
                "Wann kommt das Brot in \(.applicationName) in den Ofen"
            ],
            shortTitle: "Wann in den Ofen",
            systemImageName: "oven"
        )
        AppShortcut(
            intent: LogStarterFeedingIntent(),
            phrases: [
                "\(\.$starter) in \(.applicationName) gefüttert",
                "Sauerteig gefüttert in \(.applicationName)",
                "\(.applicationName) Sauerteig gefüttert"
            ],
            shortTitle: "Sauerteig gefüttert",
            systemImageName: "fork.knife"
        )
        AppShortcut(
            intent: LogAllStarterFeedingsIntent(),
            phrases: [
                "Alle Sauerteige in \(.applicationName) gefüttert",
                "\(.applicationName) alle Sauerteige gefüttert"
            ],
            shortTitle: "Alle Sauerteige gefüttert",
            systemImageName: "checklist"
        )
        AppShortcut(
            intent: LastStarterFeedingIntent(),
            phrases: [
                "Wann habe ich \(\.$starter) in \(.applicationName) zuletzt gefüttert",
                "Letzte Fütterung in \(.applicationName)"
            ],
            shortTitle: "Letzte Fütterung",
            systemImageName: "clock"
        )
    }
}
