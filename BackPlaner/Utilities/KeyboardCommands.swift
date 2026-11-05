//
//  KeyboardCommands.swift
//  BackPlaner
//
//  The keyboard shortcuts of the iPad with a keyboard (and of the Mac):
//  ⌘1–⌘4 for the tabs, ⌘N for a new recipe, ⇧⌘F for the search (⌘F is
//  the system's own Find on the Mac and in text fields), ⌘, for
//  the settings, ⌥⌘N for a second window. They are App commands, so the
//  iPad lists them when ⌘ is held, and they reach the window that has the
//  focus through a focused scene value — with several windows open, only
//  that one switches its tab.
//

import SwiftUI

/// What a window does when a command arrives.
struct CommandTarget {
    var showTab: (AppTab) -> Void
    var newRecipe: () -> Void
    var focusSearch: () -> Void
    var settings: () -> Void
}

private struct CommandTargetKey: FocusedValueKey {
    typealias Value = CommandTarget
}

extension FocusedValues {
    /// The active window's handlers; nil while no window has the focus.
    var commandTarget: CommandTarget? {
        get { self[CommandTargetKey.self] }
        set { self[CommandTargetKey.self] = newValue }
    }
}

struct BakePlannerCommands: Commands {
    @FocusedValue(\.commandTarget) private var target
    @Environment(\.openWindow) private var openWindow

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("Neues Rezept anlegen") { target?.newRecipe() }
                .keyboardShortcut("n", modifiers: .command)
                .disabled(target == nil)
            Button("Neues Fenster") { openWindow(id: BackPlanerApp.mainWindowID) }
                .keyboardShortcut("n", modifiers: [.command, .option])
        }
        CommandGroup(replacing: .appSettings) {
            Button("Einstellungen") { target?.settings() }
                .keyboardShortcut(",", modifiers: .command)
                .disabled(target == nil)
        }
        CommandGroup(after: .textEditing) {
            Button("Rezept suchen") { target?.focusSearch() }
                .keyboardShortcut("f", modifiers: [.command, .shift])
                .disabled(target == nil)
        }
        CommandMenu("Ansicht") {
            Button("Rezepte") { target?.showTab(.recipes) }
                .keyboardShortcut("1", modifiers: .command)
                .disabled(target == nil)
            Button("Einkaufslisten") { target?.showTab(.shoppingLists) }
                .keyboardShortcut("2", modifiers: .command)
                .disabled(target == nil)
            Button("Backhistorie") { target?.showTab(.bakeHistory) }
                .keyboardShortcut("3", modifiers: .command)
                .disabled(target == nil)
            Button("Zeitleiste") { target?.showTab(.scheduledSteps) }
                .keyboardShortcut("4", modifiers: .command)
                .disabled(target == nil)
        }
    }
}
