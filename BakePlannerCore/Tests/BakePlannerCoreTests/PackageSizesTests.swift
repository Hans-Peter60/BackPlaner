import Foundation
import Testing
@testable import BakePlannerCore

@Suite("Package sizes: what one buys for a needed amount")
struct PackageSizesTests {

    @Test("Flour comes in 500 g, 1 kg, 2 kg and 2,5 kg; the smallest covering package is bought")
    func flour() throws {
        let small = try #require(PackageSizes.package(name: "Weizenmehl 550", amount: 200, unit: .gram))
        #expect(small.amount == 500 && small.unit == .gram)
        let exact = try #require(PackageSizes.package(name: "Weizenmehl 550", amount: 500, unit: .gram))
        #expect(exact.amount == 500 && exact.unit == .gram)
        let kilo = try #require(PackageSizes.package(name: "Roggenmehl 1150", amount: 740, unit: .gram))
        #expect(kilo.amount == 1 && kilo.unit == .kilogram)
        let two = try #require(PackageSizes.package(name: "Dinkelmehl 630", amount: 1.2, unit: .kilogram))
        #expect(two.amount == 2 && two.unit == .kilogram)
        let big = try #require(PackageSizes.package(name: "Weizenmehl 1050", amount: 2_300, unit: .gram))
        #expect(big.amount == 2.5 && big.unit == .kilogram)
    }

    @Test("Above the largest package: whole large ones plus one covering the rest")
    func multiples() {
        #expect(PackageSizes.covering(3_000, sizes: [500, 1_000, 2_000, 2_500]) == 3_000)
        #expect(PackageSizes.covering(2_600, sizes: [500, 1_000, 2_000, 2_500]) == 3_000)
        #expect(PackageSizes.covering(5_000, sizes: [500, 1_000, 2_000, 2_500]) == 5_000)
        #expect(PackageSizes.covering(5_100, sizes: [500, 1_000, 2_000, 2_500]) == 5_500)
        #expect(PackageSizes.covering(100, sizes: [42]) == 126)
        #expect(PackageSizes.covering(0, sizes: [500]) == 0)
        #expect(PackageSizes.covering(100, sizes: []) == 0)
    }

    @Test("Yeast comes in cubes of 42 g, dry yeast in 7 g packets, baking powder in 15 g packets")
    func yeast() throws {
        let cube = try #require(PackageSizes.package(name: "Hefe", amount: 10, unit: .gram))
        #expect(cube.amount == 42 && cube.unit == .gram)
        let cubes = try #require(PackageSizes.package(name: "Frischhefe", amount: 50, unit: .gram))
        #expect(cubes.amount == 84)
        let dry = try #require(PackageSizes.package(name: "Trockenhefe", amount: 5, unit: .gram))
        #expect(dry.amount == 7)
        let powder = try #require(PackageSizes.package(name: "Backpulver", amount: 8, unit: .gram))
        #expect(powder.amount == 15)
    }

    @Test("Eggs are counted: 6 or 10; a weighed need for a counted package gives nothing")
    func eggs() throws {
        let six = try #require(PackageSizes.package(name: "Eier", amount: 2, unit: .piece))
        #expect(six.amount == 6 && six.unit == .piece)
        let ten = try #require(PackageSizes.package(name: "Ei", amount: 7, unit: .piece))
        #expect(ten.amount == 10)
        #expect(PackageSizes.package(name: "Eier", amount: 100, unit: .gram) == nil)
        #expect(PackageSizes.package(name: "Weizenmehl 550", amount: 2, unit: .piece) == nil)
    }

    @Test("Butter in 250 g, salt and sugar in 500 g and 1 kg, honey and malt in 250 g and 500 g, nuts and seeds from 100 g")
    func shelves() throws {
        #expect(PackageSizes.package(name: "Butter", amount: 80, unit: .gram)?.amount == 250)
        #expect(PackageSizes.package(name: "Butter", amount: 300, unit: .gram)?.amount == 500)
        #expect(PackageSizes.package(name: "Salz", amount: 20, unit: .gram)?.amount == 500)
        #expect(PackageSizes.package(name: "Zucker", amount: 600, unit: .gram)?.amount == 1)
        #expect(PackageSizes.package(name: "Honig", amount: 30, unit: .gram)?.amount == 250)
        #expect(PackageSizes.package(name: "Backmalz", amount: 15, unit: .gram)?.amount == 250)
        #expect(PackageSizes.package(name: "Sonnenblumenkerne", amount: 60, unit: .gram)?.amount == 100)
        #expect(PackageSizes.package(name: "Walnüsse", amount: 150, unit: .gram)?.amount == 200)
        #expect(PackageSizes.package(name: "Quark", amount: 300, unit: .gram)?.amount == 500)
    }

    @Test("Liquids, spices, fruit and unknown things have no standard package")
    func none() {
        #expect(PackageSizes.package(name: "Wasser", amount: 350, unit: .gram) == nil)
        #expect(PackageSizes.package(name: "Milch", amount: 250, unit: .gram) == nil)
        #expect(PackageSizes.package(name: "Sahne", amount: 100, unit: .gram) == nil)
        #expect(PackageSizes.package(name: "Olivenöl", amount: 30, unit: .gram) == nil)
        #expect(PackageSizes.package(name: "Kümmel", amount: 5, unit: .gram) == nil)
        #expect(PackageSizes.package(name: "Äpfel", amount: 3, unit: .piece) == nil)
        #expect(PackageSizes.package(name: "Sauerteig", amount: 150, unit: .gram) == nil)
        #expect(PackageSizes.package(name: "", amount: 100, unit: .gram) == nil)
        #expect(PackageSizes.package(name: "Weizenmehl 550", amount: 0, unit: .gram) == nil)
    }

    @Test("A package differs from the need unless both weigh or count the same")
    func differs() {
        #expect(PackageSizes.differs((500, .gram), from: 200, unit: .gram))
        #expect(!PackageSizes.differs((500, .gram), from: 500, unit: .gram))
        #expect(!PackageSizes.differs((1, .kilogram), from: 1_000, unit: .gram))
        #expect(PackageSizes.differs((6, .piece), from: 2, unit: .piece))
        #expect(!PackageSizes.differs((6, .piece), from: 6, unit: .piece))
    }
}
