//
//  RecipeFacetFilter.swift
//  BackPlaner
//
//  The preset collections' titles and symbols on the iPhone. The filter
//  itself, the presets and the saved collection are RecipeFacetFilter,
//  RecipeCollection and SavedRecipeCollection in the package, shared with
//  Android.
//

import BakePlannerCore
import SwiftUI

extension RecipeCollection {
    var title: LocalizedStringKey {
        switch self {
        case .morning:    "Für morgen früh"
        case .quick:      "Schnelles Brot"
        case .sourdough:  "Reiner Sauerteig"
        case .longAgo:    "Lange nicht gebacken"
        case .favourites: "Lieblinge"
        case .pantry:     "Aus dem Vorrat"
        case .useUp:      "Vorrat aufbrauchen"
        }
    }

    var systemImage: String {
        switch self {
        case .morning:    "sunrise"
        case .quick:      "hare"
        case .sourdough:  "drop"
        case .longAgo:    "clock.arrow.circlepath"
        case .favourites: "heart"
        case .pantry:     "shippingbox"
        case .useUp:      "clock.badge.exclamationmark"
        }
    }
}
