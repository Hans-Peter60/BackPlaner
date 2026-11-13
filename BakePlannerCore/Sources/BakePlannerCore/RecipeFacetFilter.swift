//
//  RecipeFacetFilter.swift
//  BakePlannerCore
//
//  The recipe list's facets as the person sets them — one choice per facet,
//  all of them combined with "and" — the preset collections, each a filter
//  with a name, and a saved collection. The reading of a recipe is
//  RecipeFacets; this decides whether a recipe passes. Shared by the iPhone
//  and Android; the titles and symbols of the presets stay with the apps.
//

import Foundation

public struct RecipeFacetFilter: Equatable, Codable, Sendable {

    /// The grain a recipe is mostly made of, or mostly whole grain.
    public enum Grain: String, CaseIterable, Codable, Identifiable, Sendable {
        case wheat, rye, spelt, wholeGrain
        public var id: Self { self }
    }

    public enum HistoryChoice: String, CaseIterable, Codable, Identifiable, Sendable {
        /// Never baked.
        case never
        /// Not baked for `longAgoDays`, or never.
        case longAgo
        /// Rated four stars or more and baked at least twice.
        case favourites
        public var id: Self { self }
    }

    /// What the bake history says about one recipe.
    public struct History: Equatable, Sendable {
        public let count: Int
        public let lastDate: Date?
        public let rating: Int

        public init(count: Int, lastDate: Date?, rating: Int = 0) {
            self.count = count
            self.lastDate = lastDate
            self.rating = rating
        }
    }

    public static let longAgoDays = 90
    public static let favouriteRating = 4
    public static let favouriteBakes = 2

    public var duration: RecipeFacets.Duration?
    public var dayFlow: RecipeFacets.DayFlow?
    public var leavening: RecipeFacets.Leavening?
    public var grain: Grain?
    public var doughYield: RecipeFacets.DoughYieldBand?
    public var equipment: RecipeFacets.Equipment?
    public var history: HistoryChoice?
    public var lowWorkOnly = false
    /// Only recipes the pantry covers completely; checked by the list
    /// against the pantry, not by `matches` (which knows no pantry).
    public var pantryOnly = false
    /// Only recipes that use something of the pantry that runs out soon,
    /// most first; the list works it out against the pantry.
    public var useUpOnly = false

    public init() {}

    // Saved collections are stored as JSON; a facet this version does not
    // know, or one missing from an older file, leaves the filter untouched
    // instead of failing the whole list of collections.
    private enum CodingKeys: String, CodingKey {
        case duration, dayFlow, leavening, grain, doughYield, equipment, history, lowWorkOnly, pantryOnly, useUpOnly
    }

    public init(from decoder: Decoder) throws {
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
        useUpOnly = (try? container.decodeIfPresent(Bool.self, forKey: .useUpOnly)) ?? false
    }

    public var isActive: Bool {
        self != RecipeFacetFilter()
    }

    public func matches(_ facets: RecipeFacets, history: History, now: Date = Date()) -> Bool {
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
public enum RecipeCollection: String, CaseIterable, Identifiable, Sendable {
    /// The collections that need the pantry, hidden while it is locked.
    public static let pantryCollections: Set<RecipeCollection> = [.pantry, .useUp]

    case morning, quick, sourdough, longAgo, favourites
    /// Everything the recipe needs is in the pantry (Pro).
    case pantry
    /// Uses something of the pantry that runs out soon (Pro).
    case useUp

    public var id: Self { self }

    public var filter: RecipeFacetFilter {
        var filter = RecipeFacetFilter()
        switch self {
        case .morning:    filter.dayFlow = .eveningToMorning
        case .quick:      filter.dayFlow = .quick
        case .sourdough:  filter.leavening = .sourdough
        case .longAgo:    filter.history = .longAgo
        case .favourites: filter.history = .favourites
        case .pantry:     filter.pantryOnly = true
        case .useUp:      filter.useUpOnly = true
        }
        return filter
    }
}

/// One saved collection: the facets as they were set, under a name.
public struct SavedRecipeCollection: Codable, Equatable, Identifiable, Sendable {
    public let id: UUID
    public var name: String
    public var filter: RecipeFacetFilter

    public init(id: UUID = UUID(), name: String, filter: RecipeFacetFilter) {
        self.id = id
        self.name = name
        self.filter = filter
    }

    /// The name as it is kept: trimmed; nil means "no name", nothing is saved.
    public static func cleanName(_ name: String) -> String? {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
