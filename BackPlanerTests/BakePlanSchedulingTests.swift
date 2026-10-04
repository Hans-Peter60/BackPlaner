//
//  BakePlanSchedulingTests.swift
//  BackPlanerTests
//

import Foundation
import Testing
@testable import BackPlaner

@Suite("Laying a bake plan on the timeline")
@MainActor
struct BakePlanSchedulingTests {

    private let start = Date(timeIntervalSince1970: 0)

    private func component(_ name: String, uses: [String] = []) -> ComponentFB {
        let component = ComponentFB()
        component.name = name
        component.ingredients = uses.map { used in
            let ingredient = IngredientFB()
            ingredient.name = "gesamter \(used)"
            ingredient.weight = 0
            return ingredient
        }
        let flour = IngredientFB()
        flour.name = "Mehl"
        flour.weight = 100
        component.ingredients.append(flour)
        return component
    }

    private func step(_ number: Double, _ component: String?, minutes: Int) -> InstructionFB {
        let instruction = InstructionFB()
        instruction.step = number
        instruction.instruction = component.map { "\($0) herstellen" } ?? "Teig bearbeiten"
        instruction.componentName = component
        instruction.duration = minutes
        return instruction
    }

    @Test("Independent preparations in one group start five minutes apart, in step order")
    func independentPreparationsAreStaggered() {
        let components = [
            component("Roggensauerteig"), component("Vorteig A"), component("Vorteig B"), component("Quellstück"),
            component("Hauptteig", uses: ["Roggensauerteig", "Vorteig A", "Vorteig B", "Quellstück"])
        ]
        let steps = [
            step(1.1, "Roggensauerteig", minutes: 735),
            step(1.2, "Vorteig A", minutes: 730),
            step(1.3, "Vorteig B", minutes: 725),
            step(1.4, "Quellstück", minutes: 720),
            step(2, "Hauptteig", minutes: 10)
        ]
        let planned = Rational.calculateStartTimes(
            steps, start, dependencies: Rational.ComponentDependency.from(components)
        )

        #expect(planned.map(\.startTime) == [0, 5, 10, 15, 735])
    }

    @Test("A preparation that uses another one waits for it instead of being staggered")
    func dependentPreparationWaitsForItsPrerequisite() {
        let components = [
            component("Sauerteig Stufe 1"),
            component("Sauerteig Stufe 2", uses: ["Sauerteig Stufe 1"]),
            component("Brühstück"),
            component("Hauptteig", uses: ["Sauerteig Stufe 2", "Brühstück"])
        ]
        let steps = [
            step(1.1, "Sauerteig Stufe 1", minutes: 600),
            step(1.2, "Sauerteig Stufe 2", minutes: 180),
            step(1.3, "Brühstück", minutes: 120),
            step(2, "Hauptteig", minutes: 10)
        ]
        let planned = Rational.calculateStartTimes(
            steps, start, dependencies: Rational.ComponentDependency.from(components)
        )

        #expect(planned.map(\.startTime) == [0, 600, 5, 780])
    }

    @Test("Parallel steps that prepare nothing still end together with their group")
    func plainParallelStepsEndTogether() {
        let steps = [
            step(2.1, nil, minutes: 180),
            step(2.2, nil, minutes: 5),
            step(3, nil, minutes: 40)
        ]
        let planned = Rational.calculateStartTimes(steps, start, dependencies: [])

        #expect(planned.map(\.startTime) == [0, 175, 180])
    }

    @Test("A lone preparation starts at the beginning of its group")
    func singlePreparationIsNotShifted() {
        let components = [component("Vorteig"), component("Hauptteig", uses: ["Vorteig"])]
        let steps = [step(1, "Vorteig", minutes: 720), step(2, "Hauptteig", minutes: 10)]
        let planned = Rational.calculateStartTimes(
            steps, start, dependencies: Rational.ComponentDependency.from(components)
        )

        #expect(planned.map(\.startTime) == [0, 720])
    }
}
