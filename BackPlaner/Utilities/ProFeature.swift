//
//  ProFeature.swift
//  BackPlaner
//
//  The titles, descriptions and symbols of the Pro features. Which
//  features exist, and the build each one appeared in, is the package's
//  (BakePlannerCore/ProAccess.swift), shared with Android; the words are
//  this app's, which has SwiftUI and the string catalog.
//

import BakePlannerCore
import SwiftUI

extension ProFeature {
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
        case .collections:    return "Sammlungen und Fertig bis"
        case .statistics:     return "Backstatistik"
        case .bakersFormula:  return "Rezept nach Bäckerprozent"
        case .yearbook:       return "Backjahr-Buch"
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
        case .collections:    return "Eigene Filter-Kombinationen als Chip sichern und mit „Fertig bis“ nur die Rezepte sehen, die bis dahin noch zu schaffen sind."
        case .statistics:     return "Die Backhistorie als Zahlen und Diagramme: wie oft, was am meisten, wie bewertet."
        case .bakersFormula:  return "Ein neues Rezept aus Anteilen vom Mehl: Bäckerprozente eingeben, die App rechnet die Gramm."
        case .yearbook:       return "Dein Backjahr als PDF-Buch: die Zahlen des Jahres, jeder Monat mit seinen Fotos, die Lieblingsrezepte und was Deine Messwerte gelehrt haben – zum Drucken und Verschenken."
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
        case .collections:    return "bookmark"
        case .statistics:     return "chart.bar"
        case .bakersFormula:  return "percent"
        case .yearbook:       return "book.closed"
        }
    }
}
