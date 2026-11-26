//
//  KeyboardCommands.swift
//  CookPlanner
//
//  The keyboard shortcuts of the iPad with a keyboard (and of the Mac):
//  ⌘1/⌘2 for the tabs, ⌘N for a new dish, ⇧⌘N for a menu, ⇧⌘F for the
//  search (⌘F is the system's Find), ⌘, for the settings, ⌘⏎ to start
//  cooking the dish on screen. They are App commands, so the iPad lists
//  them when ⌘ is held; they reach the window that has the focus through
//  a focused scene value, and the screens pick them up from AppRequests.
//

import SwiftUI

/// What a window does when a command arrives.
struct CommandTarget {
    var showTab: (CookTab) -> Void
    var request: (AppRequests.Command) -> Void
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

struct CookPlannerCommands: Commands {
    @FocusedValue(\.commandTarget) private var target

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("Neues Gericht") { target?.request(.newDish) }
                .keyboardShortcut("n", modifiers: .command)
                .disabled(target == nil)
            Button("Menü zusammenstellen") { target?.request(.newMenu) }
                .keyboardShortcut("n", modifiers: [.command, .shift])
                .disabled(target == nil)
        }
        CommandGroup(replacing: .appSettings) {
            Button("Einstellungen") { target?.request(.settings) }
                .keyboardShortcut(",", modifiers: .command)
                .disabled(target == nil)
        }
        CommandGroup(after: .textEditing) {
            Button("Gericht suchen") { target?.request(.focusSearch) }
                .keyboardShortcut("f", modifiers: [.command, .shift])
                .disabled(target == nil)
        }
        CommandMenu("Kochen") {
            Button("Kochen starten") { target?.request(.startCooking) }
                .keyboardShortcut(.return, modifiers: .command)
                .disabled(target == nil)
        }
        CommandMenu("Ansicht") {
            Button("Gerichte") { target?.showTab(.dishes) }
                .keyboardShortcut("1", modifiers: .command)
                .disabled(target == nil)
            Button("Gekocht") { target?.showTab(.cooked) }
                .keyboardShortcut("2", modifiers: .command)
                .disabled(target == nil)
        }
    }
}
