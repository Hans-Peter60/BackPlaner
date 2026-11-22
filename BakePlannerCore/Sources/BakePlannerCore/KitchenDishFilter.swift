//
//  KitchenDishFilter.swift
//  BakePlannerCore
//
//  CookPlanner's dish list narrowed the way BakePlanner narrows its recipes
//  (RecipeFacetFilter): what a dish is (KitchenDishFacets, read from the
//  dish, its plan for the current kitchen and its cooking history), one
//  choice per facet combined with "and" (KitchenDishFilter), ready-made
//  collections (KitchenDishCollection) and collections the cook saves
//  (SavedKitchenDishCollection). Shared with a later Android app; titles
//  and symbols stay with the apps.
//

import Foundation

public struct KitchenDishFacets: Equatable, Sendable {

    /// How long the plan takes with the current kitchen.
    public enum Duration: String, CaseIterable, Codable, Identifiable, Sendable {
        /// Up to 30 minutes.
        case quick
        /// 31 to 45 minutes.
        case medium
        /// 46 to 60 minutes.
        case long
        /// Over an hour.
        case longer
        public var id: Self { self }

        public static func of(minutes: Int) -> Duration {
            switch minutes {
            case ...30: return .quick
            case ...45: return .medium
            case ...60: return .long
            default: return .longer
            }
        }
    }

    /// The heat the dish needs.
    public enum Equipment: String, CaseIterable, Codable, Identifiable, Sendable {
        case oven
        /// Burners, no oven.
        case stoveOnly
        /// Neither: salads, tartare, desserts from the fridge.
        case noHeat
        public var id: Self { self }
    }

    public enum Origin: String, CaseIterable, Codable, Identifiable, Sendable {
        /// Typed in, or taken as a template.
        case own
        /// Read from a text, photos or a web page.
        case imported
        case example
        public var id: Self { self }
    }

    public let duration: Duration
    public let minutes: Int
    public let fitsBudget: Bool
    public let equipment: Equipment
    /// The hands' share of the plan, 0…1.
    public let handsShare: Double
    public let origin: Origin

    public init(dish: KitchenDish, schedule: KitchenSchedule) {
        minutes = schedule.makespan
        duration = .of(minutes: schedule.makespan)
        fitsBudget = schedule.fits
        if dish.tasks.contains(where: { $0.station == .oven }) {
            equipment = .oven
        } else if dish.tasks.contains(where: { $0.station == .burner }) {
            equipment = .stoveOnly
        } else {
            equipment = .noHeat
        }
        handsShare = schedule.makespan > 0 ? min(1, Double(schedule.handsMinutes) / Double(schedule.makespan)) : 0
        switch dish.source {
        case .sample: origin = .example
        case .manual: origin = .own
        case .text, .photo, .web: origin = .imported
        }
    }
}

public struct KitchenDishFilter: Equatable, Codable, Sendable {

    public enum HistoryChoice: String, CaseIterable, Codable, Identifiable, Sendable {
        /// Never cooked on the stopwatch.
        case never
        /// Not cooked for `longAgoDays`, or never.
        case longAgo
        /// Rated `favouriteRating` stars or more on average.
        case favourites
        public var id: Self { self }
    }

    /// What the cooking records say about one dish.
    public struct History: Equatable, Sendable {
        public let count: Int
        public let lastDate: Date?
        /// The average of the given ratings, 0 without any.
        public let rating: Double

        public init(count: Int, lastDate: Date?, rating: Double = 0) {
            self.count = count
            self.lastDate = lastDate
            self.rating = rating
        }

        /// The history of one dish from all records.
        public init(dishID: String, runs: [KitchenCookRun]) {
            let own = runs.filter { $0.dishID == dishID }
            let ratings = own.compactMap(\.rating)
            self.init(count: own.count, lastDate: own.map(\.startedAt).max(),
                      rating: ratings.isEmpty ? 0 : Double(ratings.reduce(0, +)) / Double(ratings.count))
        }

        public static let none = History(count: 0, lastDate: nil)
    }

    public static let longAgoDays = 60
    public static let favouriteRating = 4.0
    /// "Wenig Handarbeit": the hands busy for at most this share of the plan.
    public static let lowWorkShare = 0.6

    public var duration: KitchenDishFacets.Duration?
    public var equipment: KitchenDishFacets.Equipment?
    public var origin: KitchenDishFacets.Origin?
    public var history: HistoryChoice?
    public var fitsBudgetOnly = false
    public var lowWorkOnly = false

    public init(duration: KitchenDishFacets.Duration? = nil, equipment: KitchenDishFacets.Equipment? = nil,
                origin: KitchenDishFacets.Origin? = nil, history: HistoryChoice? = nil,
                fitsBudgetOnly: Bool = false, lowWorkOnly: Bool = false) {
        self.duration = duration
        self.equipment = equipment
        self.origin = origin
        self.history = history
        self.fitsBudgetOnly = fitsBudgetOnly
        self.lowWorkOnly = lowWorkOnly
    }

    // A facet a later version adds, or one an older file lacks, leaves the
    // filter as it is instead of failing the saved collections.
    private enum CodingKeys: String, CodingKey {
        case duration, equipment, origin, history, fitsBudgetOnly, lowWorkOnly
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        duration = try? container.decodeIfPresent(KitchenDishFacets.Duration.self, forKey: .duration)
        equipment = try? container.decodeIfPresent(KitchenDishFacets.Equipment.self, forKey: .equipment)
        origin = try? container.decodeIfPresent(KitchenDishFacets.Origin.self, forKey: .origin)
        history = try? container.decodeIfPresent(HistoryChoice.self, forKey: .history)
        fitsBudgetOnly = (try? container.decodeIfPresent(Bool.self, forKey: .fitsBudgetOnly)) ?? false
        lowWorkOnly = (try? container.decodeIfPresent(Bool.self, forKey: .lowWorkOnly)) ?? false
    }

    public var isActive: Bool { self != KitchenDishFilter() }

    public func matches(_ facets: KitchenDishFacets, history: History, now: Date = Date()) -> Bool {
        if let duration, facets.duration != duration { return false }
        if let equipment, facets.equipment != equipment { return false }
        if let origin, facets.origin != origin { return false }
        if fitsBudgetOnly && !facets.fitsBudget { return false }
        if lowWorkOnly && facets.handsShare > Self.lowWorkShare { return false }
        switch self.history {
        case nil: break
        case .never:
            if history.count > 0 { return false }
        case .longAgo:
            if let last = history.lastDate,
               now.timeIntervalSince(last) < TimeInterval(Self.longAgoDays) * 86_400 { return false }
        case .favourites:
            if history.rating < Self.favouriteRating { return false }
        }
        return true
    }

    /// Whether `text` finds the dish: in its name, a component or an
    /// ingredient, ignoring case and accents. An empty text finds all.
    public static func matches(_ dish: KitchenDish, searchText text: String, locale: Locale = .current) -> Bool {
        let needle = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !needle.isEmpty else { return true }
        let haystack = [dish.name] + dish.components + dish.ingredients.map(\.name)
        return haystack.contains { $0.range(of: needle, options: [.caseInsensitive, .diacriticInsensitive], locale: locale) != nil }
    }
}

/// The ready-made collections in the chip row.
public enum KitchenDishCollection: String, CaseIterable, Identifiable, Sendable {
    case fits, quick, noOven, favourites, never, longAgo
    public var id: Self { self }

    public var filter: KitchenDishFilter {
        switch self {
        case .fits: return KitchenDishFilter(fitsBudgetOnly: true)
        case .quick: return KitchenDishFilter(duration: .quick)
        case .noOven: return KitchenDishFilter(equipment: .stoveOnly)
        case .favourites: return KitchenDishFilter(history: .favourites)
        case .never: return KitchenDishFilter(history: .never)
        case .longAgo: return KitchenDishFilter(history: .longAgo)
        }
    }
}

public struct SavedKitchenDishCollection: Codable, Equatable, Identifiable, Sendable {
    public let id: UUID
    public var name: String
    public var filter: KitchenDishFilter

    public init(id: UUID = UUID(), name: String, filter: KitchenDishFilter) {
        self.id = id
        self.name = name
        self.filter = filter
    }

    /// The name as it is kept: trimmed; nil means nothing is saved.
    public static func cleanName(_ name: String) -> String? {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
