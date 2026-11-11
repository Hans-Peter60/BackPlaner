//
//  RecipeFacetFilter.swift
//  BackPlaner
//
//  The recipe list's facets as the person sets them — one choice per facet,
//  all of them combined with "and" — and the preset collections, each a
//  filter with a name. The reading of a recipe is RecipeFacets in the
//  package; this decides whether a recipe passes.
//

import BakePlannerCore
import Foundation
import SwiftUI

struct RecipeFacetFilter: Equatable, Codable {

    /// The grain a recipe is mostly made of, or mostly whole grain.
    enum Grain: String, CaseIterable, Codable, Identifiable {
        case wheat, rye, spelt, wholeGrain
        var id: Self { self }
    }

    enum HistoryChoice: String, CaseIterable, Codable, Identifiable {
        /// Never baked.
        case never
        /// Not baked for `longAgoDays`, or never.
        case longAgo
        /// Rated four stars or more and baked at least twice.
        case favourites
        var id: Self { self }
    }

    /// What the bake history says about one recipe.
    struct History: Equatable {
        let count: Int
        let lastDate: Date?
        let rating: Int

        init(count: Int, lastDate: Date?, rating: Int = 0) {
            self.count = count
            self.lastDate = lastDate
            self.rating = rating
        }
    }

    static let longAgoDays = 90
    static let favouriteRating = 4
    static let favouriteBakes = 2

    var duration: RecipeFacets.Duration?
    var dayFlow: RecipeFacets.DayFlow?
    var leavening: RecipeFacets.Leavening?
    var grain: Grain?
    var doughYield: RecipeFacets.DoughYieldBand?
    var equipment: RecipeFacets.Equipment?
    var history: HistoryChoice?
    var lowWorkOnly = false
    /// Only recipes the pantry covers completely; checked by the list
    /// against the pantry, not by `matches` (which knows no pantry).
    var pantryOnly = false

    init() {}

    // Saved collections are stored as JSON; a facet this version does not
    // know, or one missing from an older file, leaves the filter untouched
    // instead of failing the whole list of collections.
    private enum CodingKeys: String, CodingKey {
        case duration, dayFlow, leavening, grain, doughYield, equipment, history, lowWorkOnly, pantryOnly
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        duration = try? container.decodeIfPresent(RecipeFacets.Duration.self, forKey: .duration)
        dayFlow = try? container.decodeIfPresent(RecipeFacets.DayFlow.self, forKey: .dayFlow)
        leavening = try? container.decodeIfPresent(RecipeFacets.Leavening.self, forKey: .leavening)
        grain = try? container.decodeIfPresent(Grain.self, forKey: .grain)
        doughYield = try? container.decodeIfPresent(RecipeFacets.DoughYieldBand.self, forKey: .doughYield)
        equipment = try? container.decodeIfPresent(RecipeFacets.Equipment.self, forKey: .equipment)
        history = try? container.decodeIfPresent(HistoryChoice.self, forKey: .history)
        lowWorkOnly = (try? container.decodeIfPresent(Bool.self, forKey: .lowWorkOnly)) ?? false
        pantryOnly = (try? container.decodeIfPresent(Bool.self, forKey: .pantryOnly)) ?? false
    }

    var isActive: Bool {
        self != RecipeFacetFilter()
    }

    func matches(_ facets: RecipeFacets, history: History, now: Date = Date()) -> Bool {
        if let duration, facets.duration != duration { return false }
        if let dayFlow, !facets.dayFlows.contains(dayFlow) { return false }
        if let leavening, facets.leavening != leavening { return false }
        if let grain {
            switch grain {
            case .wheat: if facets.mainGrain != .wheat { return false }
            case .rye: if facets.mainGrain != .rye { return false }
            case .spelt: if facets.mainGrain != .spelt { return false }
            case .wholeGrain: if facets.wholeGrainShare < 0.5 { return false }
            }
        }
        if let doughYield, facets.doughYieldBand != doughYield { return false }
        if let equipment, !facets.equipment.contains(equipment) { return false }
        if lowWorkOnly, !facets.isLowWork { return false }
        if let choice = self.history {
            switch choice {
            case .never:
                if history.count > 0 { return false }
            case .longAgo:
                if let last = history.lastDate,
                   last > now.addingTimeInterval(-Double(Self.longAgoDays) * 86_400) { return false }
            case .favourites:
                if history.rating < Self.favouriteRating || history.count < Self.favouriteBakes { return false }
            }
        }
        return true
    }
}

/// The preset collections above the recipe list: a filter with a name.
enum RecipeCollection: String, CaseIterable, Identifiable {
    case morning, quick, sourdough, longAgo, favourites
    /// Everything the recipe needs is in the pantry (Pro).
    case pantry

    var id: Self { self }

    var title: LocalizedStringKey {
        switch self {
        case .morning:    "Für morgen früh"
        case .quick:      "Schnelles Brot"
        case .sourdough:  "Reiner Sauerteig"
        case .longAgo:    "Lange nicht gebacken"
        case .favourites: "Lieblinge"
        case .pantry:     "Aus dem Vorrat"
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
        }
    }

    var filter: RecipeFacetFilter {
        var filter = RecipeFacetFilter()
        switch self {
        case .morning:    filter.dayFlow = .eveningToMorning
        case .quick:      filter.dayFlow = .quick
        case .sourdough:  filter.leavening = .sourdough
        case .longAgo:    filter.history = .longAgo
        case .favourites: filter.history = .favourites
        case .pantry:     filter.pantryOnly = true
        }
        return filter
    }
}
