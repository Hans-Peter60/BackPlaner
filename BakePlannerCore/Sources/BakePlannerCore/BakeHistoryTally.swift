//
//  BakeHistoryTally.swift
//  BakePlannerCore
//
//  The baking history summed up per recipe — what the hit list and the
//  photo cloud of "Backhistorie" show: how often a recipe was baked, when
//  last, with which photos. And the circle packing the cloud is laid out
//  with: one circle per recipe, its size following the count, the most
//  baked recipe in the middle and the others wound around it without
//  overlapping. Plain values, tested without Core Data or a view.
//

import CoreGraphics
import Foundation

public enum BakeHistoryTally {

    /// One bake, as the history records it.
    public struct Entry {
        public let recipeID: AnyHashable
        public let recipeName: String
        public let rating: Int
        public let date: Date
        public let photos: [Data]

        public init(recipeID: AnyHashable, recipeName: String, rating: Int, date: Date, photos: [Data]) {
            self.recipeID = recipeID
            self.recipeName = recipeName
            self.rating = rating
            self.date = date
            self.photos = photos
        }
    }

    /// One recipe's bakes summed up.
    public struct Recipe: Identifiable, Equatable {
        public let id: AnyHashable
        public let name: String
        public let rating: Int
        public let count: Int
        public let lastDate: Date
        /// Newest bake's photos first.
        public let photos: [Data]
    }

    /// The recipes of the entries, most baked first; equally often baked
    /// recipes by their last bake, newest first, then by name.
    public static func recipes(from entries: [Entry]) -> [Recipe] {
        var order: [AnyHashable] = []
        var grouped: [AnyHashable: [Entry]] = [:]
        for entry in entries {
            if grouped[entry.recipeID] == nil { order.append(entry.recipeID) }
            grouped[entry.recipeID, default: []].append(entry)
        }
        let recipes = order.compactMap { id -> Recipe? in
            guard let bakes = grouped[id], let first = bakes.first else { return nil }
            let newestFirst = bakes.sorted { $0.date > $1.date }
            return Recipe(id: id,
                          name: first.recipeName,
                          rating: first.rating,
                          count: bakes.count,
                          lastDate: newestFirst[0].date,
                          photos: newestFirst.flatMap(\.photos))
        }
        return recipes.sorted { a, b in
            if a.count != b.count { return a.count > b.count }
            if a.lastDate != b.lastDate { return a.lastDate > b.lastDate }
            return a.name.localizedStandardCompare(b.name) == .orderedAscending
        }
    }
}

/// Circles laid out as a round cloud: the first at the centre, every
/// further one at the first free spot along a spiral outwards. Given in the
/// order of the radii, so the biggest circle — the most baked recipe —
/// belongs first.
public struct CirclePacking: Equatable {

    public struct Placement: Equatable {
        public let center: CGPoint
        public let radius: CGFloat
    }

    public let placements: [Placement]
    /// The smallest rectangle around all circles.
    public let bounds: CGRect

    public init(radii: [CGFloat], spacing: CGFloat = 4) {
        var placements: [Placement] = []
        for radius in radii {
            if placements.isEmpty {
                placements.append(Placement(center: .zero, radius: radius))
                continue
            }
            // An Archimedean spiral from the centre; the step along it is a
            // fraction of the circle's size, so small circles find small
            // gaps and big ones do not take forever to walk out.
            let step = max(2, radius / 6)
            var angle: CGFloat = 0
            var placed = false
            while !placed, angle < 400 * .pi {
                let distance = 3 * angle
                let candidate = CGPoint(x: distance * cos(angle), y: distance * sin(angle))
                let free = placements.allSatisfy { other in
                    hypot(candidate.x - other.center.x, candidate.y - other.center.y) >= radius + other.radius + spacing
                }
                if free {
                    placements.append(Placement(center: candidate, radius: radius))
                    placed = true
                } else {
                    angle += step / max(distance, 1)
                }
            }
            if !placed {
                // Beyond the spiral's reach: next to the farthest circle.
                let farthest = placements.max { hypot($0.center.x, $0.center.y) < hypot($1.center.x, $1.center.y) }!
                let reach = hypot(farthest.center.x, farthest.center.y) + farthest.radius + spacing + radius
                placements.append(Placement(center: CGPoint(x: reach, y: 0), radius: radius))
            }
        }
        self.placements = placements
        bounds = placements.reduce(CGRect.null) { rect, placement in
            rect.union(CGRect(x: placement.center.x - placement.radius, y: placement.center.y - placement.radius,
                              width: 2 * placement.radius, height: 2 * placement.radius))
        }
    }

    /// A circle's radius for a count: its area grows with the count, so
    /// a recipe baked four times as often gets a circle twice as wide, and
    /// the least baked still has `minimum`.
    public static func radius(count: Int, maxCount: Int, minimum: CGFloat, maximum: CGFloat) -> CGFloat {
        guard maxCount > 0, count > 0 else { return minimum }
        let share = sqrt(CGFloat(count) / CGFloat(maxCount))
        return minimum + (maximum - minimum) * share
    }
}
