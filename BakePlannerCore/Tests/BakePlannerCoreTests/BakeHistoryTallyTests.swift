//
//  BakeHistoryTallyTests.swift
//  BakePlannerCoreTests
//
//  The baking history per recipe, and the circle packing of the photo cloud.
//

import CoreGraphics
import Foundation
import Testing
@testable import BakePlannerCore

@Suite("The baking history summed up per recipe")
struct BakeHistoryTallyTests {

    private let base = Date(timeIntervalSince1970: 1_800_000_000)

    private func day(_ offset: Int) -> Date { base.addingTimeInterval(TimeInterval(offset * 86_400)) }

    private func entry(_ recipe: String, day offset: Int, rating: Int = 3, photos: [String] = []) -> BakeHistoryTally.Entry {
        BakeHistoryTally.Entry(recipeID: recipe, recipeName: recipe, rating: rating, date: day(offset),
                               photos: photos.map { Data($0.utf8) })
    }

    @Test("Counts per recipe, most baked first, ties by the last bake, then by name")
    func countsAndOrder() {
        let recipes = BakeHistoryTally.recipes(from: [
            entry("Baguette", day: 1),
            entry("Roggenbrot", day: 2),
            entry("Baguette", day: 5),
            entry("Zopf", day: 9),
            entry("Roggenbrot", day: 7),
            entry("Anstellgut", day: 3),
        ])
        #expect(recipes.map(\.name) == ["Roggenbrot", "Baguette", "Zopf", "Anstellgut"])
        #expect(recipes.map(\.count) == [2, 2, 1, 1])
        #expect(recipes[0].lastDate == day(7))
    }

    @Test("The photos come newest bake first; rating and name are the recipe's")
    func photosNewestFirst() throws {
        let recipes = BakeHistoryTally.recipes(from: [
            entry("Baguette", day: 1, rating: 4, photos: ["a", "b"]),
            entry("Baguette", day: 6, rating: 4, photos: ["c"]),
            entry("Baguette", day: 3, rating: 4),
        ])
        let baguette = try #require(recipes.first)
        #expect(baguette.count == 3)
        #expect(baguette.rating == 4)
        #expect(baguette.photos.map { String(decoding: $0, as: UTF8.self) } == ["c", "a", "b"])
        #expect(BakeHistoryTally.recipes(from: []).isEmpty)
    }
}

@Suite("The photo cloud's circle packing")
struct CirclePackingTests {

    @Test("No two circles overlap, the first sits in the middle, the bounds hold them all")
    func packsWithoutOverlap() {
        let radii: [CGFloat] = [100, 80, 60, 50, 40, 40, 36, 36, 36, 30, 30, 30, 30, 30]
        let packing = CirclePacking(radii: radii, spacing: 4)
        #expect(packing.placements.count == radii.count)
        #expect(packing.placements[0].center == .zero)
        for (i, a) in packing.placements.enumerated() {
            for b in packing.placements[(i + 1)...] {
                let distance = hypot(a.center.x - b.center.x, a.center.y - b.center.y)
                #expect(distance >= a.radius + b.radius + 4 - 0.01, "\(i)")
            }
            // A hair of tolerance: the union's far edge is a sum of floats.
            #expect(packing.bounds.insetBy(dx: -0.01, dy: -0.01)
                .contains(CGRect(x: a.center.x - a.radius, y: a.center.y - a.radius,
                                 width: 2 * a.radius, height: 2 * a.radius)))
        }
        // Packed, not strung out: the cloud is at most a few diameters wide.
        #expect(packing.bounds.width < 8 * 100)
        #expect(packing.bounds.height < 8 * 100)
    }

    @Test("The radius grows with the square root of the count, between the limits")
    func radiusFollowsTheCount() {
        #expect(CirclePacking.radius(count: 16, maxCount: 16, minimum: 30, maximum: 110) == 110)
        #expect(CirclePacking.radius(count: 4, maxCount: 16, minimum: 30, maximum: 110) == 70)
        #expect(CirclePacking.radius(count: 0, maxCount: 16, minimum: 30, maximum: 110) == 30)
        #expect(CirclePacking.radius(count: 1, maxCount: 0, minimum: 30, maximum: 110) == 30)
        #expect(CirclePacking(radii: []).placements.isEmpty)
        #expect(CirclePacking(radii: [20]).bounds == CGRect(x: -20, y: -20, width: 40, height: 40))
    }
}
