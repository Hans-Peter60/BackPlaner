//
//  ProFeature.swift
//  BackPlaner
//
//  The features that belong to BakePlanner Pro. Everything else — recipes,
//  the plan with its reminders, the bake mode, the bake history, the public
//  recipes, the calculators — stays free: that is the core that makes the
//  app worth having, and none of it costs anything per use.
//

import BakePlannerCore
import SwiftUI

enum ProFeature: String, CaseIterable, Identifiable, Sendable {
    /// Sharing a recipe as a PDF at the serving size shown.
    case pdfExport
    /// Handing a single recipe to someone else as a re-importable file from
    /// its page. "Rezepte exportieren" in the list's menu stays free: it is
    /// the backup, and one's own data must always be portable.
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
    /// The pantry: flours, seeds and yeast with amounts and best-before dates.
    case pantry
    /// Several breads placed before one finish, the ovens and the pause respected.
    case bakingDay

    var id: String { rawValue }

    var title: LocalizedStringKey {
        switch self {
        case .pdfExport:      return "Rezepte als PDF teilen"
        case .recipeSharing:  return "Rezepte weitergeben"
        case .recurringPlans: return "Wiederkehrende Backpläne"
        case .shoppingList:   return "Einkaufslisten"
        case .widgets:        return "Widgets"
        case .liveActivity:   return "Live-Aktivität auf dem Sperrbildschirm"
        case .pantry:         return "Vorrat"
        case .bakingDay:      return "Backtag planen"
        }
    }

    /// One line on what the feature does, for the paywall.
    var detail: LocalizedStringKey {
        switch self {
        case .pdfExport:      return "Ein Rezept in der gezeigten Portionsgröße oder den Backtag-Zettel der geplanten Schritte als PDF drucken oder verschicken."
        case .recipeSharing:  return "Ein einzelnes Rezept als Datei weitergeben, die sich wieder importieren lässt."
        case .recurringPlans: return "Ein Rezept plant sich in seinem Rhythmus von selbst, etwa das Füttern des Anstellguts."
        case .shoppingList:   return "Die Zutaten eines Rezepts auf eine Einkaufsliste setzen und abhaken."
        case .widgets:        return "Der nächste Schritt auf dem Home- und dem Sperrbildschirm."
        case .liveActivity:   return "Der laufende Plan auf dem Sperrbildschirm und in der Dynamic Island."
        case .pantry:         return "Mehle, Saaten und Hefe mit Menge und Haltbarkeit führen; Gekauftes wandert aus der Einkaufsliste hinein."
        case .bakingDay:      return "Mehrere Brote für einen Backtag: Wunschzeit für das letzte, und die App legt die Startzeiten so, dass Öfen und Backpause passen."
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
        case .pantry:         return "shippingbox"
        case .bakingDay:      return "calendar.badge.clock"
        }
    }
}
