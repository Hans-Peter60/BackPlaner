//
//  ProFeature.swift
//  BackPlaner
//
//  The features that belong to BakePlanner Pro. Everything else — recipes,
//  the plan with its reminders, the bake mode, the bake history, the public
//  recipes, the calculators — stays free: that is the core that makes the
//  app worth having, and none of it costs anything per use.
//

import SwiftUI

enum ProFeature: String, CaseIterable, Identifiable, Sendable {
    /// Sharing a recipe as a PDF at the serving size shown.
    case pdfExport
    /// Handing a single recipe to someone else as a re-importable file.
    /// The backup of *all* recipes in the settings stays free: one's own
    /// data must always be portable.
    case recipeSharing
    /// A recipe that queues itself on a rhythm (feeding a starter every
    /// five days, say).
    case recurringPlans
    /// Shopping lists made from a recipe's ingredients.
    case shoppingList
    /// The home-screen and lock-screen widget with the next step.
    case widgets
    /// The Live Activity of the running plan on the lock screen.
    case liveActivity

    var id: String { rawValue }

    var title: LocalizedStringKey {
        switch self {
        case .pdfExport:      return "Rezepte als PDF teilen"
        case .recipeSharing:  return "Rezepte weitergeben"
        case .recurringPlans: return "Wiederkehrende Backpläne"
        case .shoppingList:   return "Einkaufslisten"
        case .widgets:        return "Widgets"
        case .liveActivity:   return "Live-Aktivität auf dem Sperrbildschirm"
        }
    }

    /// One line on what the feature does, for the paywall.
    var detail: LocalizedStringKey {
        switch self {
        case .pdfExport:      return "Ein Rezept in der gezeigten Portionsgröße als PDF drucken oder verschicken."
        case .recipeSharing:  return "Ein einzelnes Rezept als Datei weitergeben, die sich wieder importieren lässt."
        case .recurringPlans: return "Ein Rezept plant sich in seinem Rhythmus von selbst, etwa das Füttern des Anstellguts."
        case .shoppingList:   return "Die Zutaten eines Rezepts auf eine Einkaufsliste setzen und abhaken."
        case .widgets:        return "Der nächste Schritt auf dem Home- und dem Sperrbildschirm."
        case .liveActivity:   return "Der laufende Plan auf dem Sperrbildschirm und in der Dynamic Island."
        }
    }

    var symbolName: String {
        switch self {
        case .pdfExport:      return "doc.richtext"
        case .recipeSharing:  return "doc.badge.arrow.up"
        case .recurringPlans: return "arrow.trianglehead.2.clockwise.rotate.90"
        case .shoppingList:   return "cart"
        case .widgets:        return "widget.small"
        case .liveActivity:   return "clock.badge"
        }
    }
}
