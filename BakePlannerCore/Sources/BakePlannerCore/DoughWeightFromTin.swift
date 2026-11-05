//
//  DoughWeightFromTin.swift
//  BakePlannerCore
//
//  How much dough a tin or a proofing basket takes. A loaf tin is measured
//  inside and filled by a factor that depends on the dough: light wheat
//  doughs rise more and take less, rye and wholegrain doughs more. Baskets
//  have no formula; their makers rate them by the dough weight they take,
//  and those ratings are consistent enough across makers to serve as the
//  table here, read linearly between the sizes.
//
//  The figures are baker's rules of thumb, not measurements of one maker's
//  tins. The fill factor is shown and adjustable, so a baker who knows their
//  tin corrects it once.
//

import Foundation

public enum DoughWeightFromTin {

    /// What the dough is like, which decides how much of the tin it fills.
    public enum DoughType: String, CaseIterable, Identifiable, Sendable {
        /// Light wheat doughs and toast bread: they rise the most.
        case lightWheat
        /// Mixed wheat and rye breads.
        case mixed
        /// Rye, wholegrain and seeded doughs: dense, they rise the least.
        case ryeWholeGrain

        public var id: String { rawValue }

        /// Grams of dough per millilitre of tin.
        public var fillFactor: Double {
            switch self {
            case .lightWheat:    return 0.38
            case .mixed:         return 0.45
            case .ryeWholeGrain: return 0.52
            }
        }

        /// How far a basket's nominal weight moves for this dough: a basket
        /// rated for 1,000 g takes 1,200 g of rye and 900 g of airy wheat.
        public var basketFactor: Double {
            switch self {
            case .lightWheat:    return 0.9
            case .mixed:         return 1.0
            case .ryeWholeGrain: return 1.2
            }
        }
    }

    public static let minimumFillFactor = 0.30
    public static let maximumFillFactor = 0.60

    // MARK: Tins

    /// The inside volume of a loaf tin in millilitres (1 cm³ = 1 ml). With
    /// slanted walls, measure the width at half height.
    public static func volumeMilliliters(lengthCm: Double, widthCm: Double, heightCm: Double) -> Double {
        max(0, lengthCm) * max(0, widthCm) * max(0, heightCm)
    }

    /// The inside volume of a round tin in millilitres.
    public static func volumeMilliliters(diameterCm: Double, heightCm: Double) -> Double {
        let radius = max(0, diameterCm) / 2
        return Double.pi * radius * radius * max(0, heightCm)
    }

    /// The dough a tin of `volumeMilliliters` takes at `fillFactor` grams per
    /// millilitre, to the nearest 10 g.
    public static func doughGrams(volumeMilliliters: Double, fillFactor: Double) -> Int {
        guard volumeMilliliters > 0, fillFactor > 0 else { return 0 }
        return Int((volumeMilliliters * fillFactor / 10).rounded()) * 10
    }

    // MARK: Baskets

    public enum BasketShape: String, CaseIterable, Identifiable, Sendable {
        case round
        case oval

        public var id: String { rawValue }
    }

    /// One size as the makers rate it: the dough weight it is meant for, and
    /// the measure that tells it apart — the diameter of a round basket, the
    /// length of an oval one, both at the rim.
    public struct BasketSize: Equatable, Sendable {
        public let nominalGrams: Int
        public let roundDiameterCm: Double
        public let ovalLengthCm: Double
        public let ovalWidthCm: Double

        public func measureCm(for shape: BasketShape) -> Double {
            shape == .round ? roundDiameterCm : ovalLengthCm
        }
    }

    /// The usual sizes, smallest first.
    public static let basketSizes: [BasketSize] = [
        BasketSize(nominalGrams: 500,  roundDiameterCm: 18, ovalLengthCm: 22, ovalWidthCm: 14),
        BasketSize(nominalGrams: 750,  roundDiameterCm: 20, ovalLengthCm: 25, ovalWidthCm: 15),
        BasketSize(nominalGrams: 1000, roundDiameterCm: 22, ovalLengthCm: 28, ovalWidthCm: 16),
        BasketSize(nominalGrams: 1500, roundDiameterCm: 25, ovalLengthCm: 32, ovalWidthCm: 18),
        BasketSize(nominalGrams: 2000, roundDiameterCm: 28, ovalLengthCm: 35, ovalWidthCm: 19),
    ]

    /// The nominal dough weight of a basket measured `measureCm` at the rim
    /// (diameter when round, length when oval), read linearly between the
    /// usual sizes and continued beyond them, to the nearest 50 g.
    public static func basketNominalGrams(shape: BasketShape, measureCm: Double) -> Int {
        guard measureCm > 0 else { return 0 }
        let points = basketSizes.map { (measure: $0.measureCm(for: shape), grams: Double($0.nominalGrams)) }

        let (lower, upper): ((measure: Double, grams: Double), (measure: Double, grams: Double))
        if measureCm <= points[0].measure {
            (lower, upper) = (points[0], points[1])
        } else if let index = points.indices.dropFirst().first(where: { measureCm <= points[$0].measure }) {
            (lower, upper) = (points[index - 1], points[index])
        } else {
            (lower, upper) = (points[points.count - 2], points[points.count - 1])
        }

        let slope = (upper.grams - lower.grams) / (upper.measure - lower.measure)
        let grams = lower.grams + (measureCm - lower.measure) * slope
        return max(0, Int((grams / 50).rounded()) * 50)
    }

    /// What a basket of `nominalGrams` takes of a dough of `doughType`, to
    /// the nearest 10 g.
    public static func basketDoughGrams(nominalGrams: Int, doughType: DoughType) -> Int {
        Int((Double(nominalGrams) * doughType.basketFactor / 10).rounded()) * 10
    }
}
