//
//  TimedFoldExpansionTests.swift
//  BackPlanerTests
//

import Testing
@testable import BackPlaner

@Suite("Repeated stretch-and-folds expand into one step per fold")
struct TimedFoldExpansionTests {

    private func step(_ text: String, minutes: Int = 0, step: Double = 1) -> InstructionFB {
        let instruction = InstructionFB()
        instruction.instruction = text
        instruction.duration = minutes
        instruction.step = step
        return instruction
    }

    @Test("A fold line that states its own rest expands in place, keeping the rest step")
    func selfDescribingRestExpandsInPlace() {
        var instructions = [
            step("3 Stunden bei 24 °C ruhen lassen. Dabei nach 30 und 60 Minuten dehnen und falten.")
        ]
        TimedFoldExpansion.expand(&instructions)

        #expect(instructions.map(\.step) == [1, 1.1, 1.2])
        #expect(instructions[1].instruction == "Teig dehnen und falten (nach 30 Minuten).")
        #expect(instructions[1].duration == 150)
        #expect(instructions[2].instruction == "Teig dehnen und falten (nach 60 Minuten).")
        #expect(instructions[2].duration == 120)
    }

    @Test("An explicit list of more than two offsets is fully recognised")
    func explicitListOfThreeOffsets() {
        var instructions = [
            step("12 Stunden bei 20 °C reifen lassen.", minutes: 720, step: 1),
            step("Teig nach 30, 60 und 90 Minuten dehnen und falten.", step: 2)
        ]
        TimedFoldExpansion.expand(&instructions)

        #expect(instructions.map(\.step) == [1, 1.1, 1.2, 1.3])
        #expect(instructions.map(\.duration) == [720, 690, 660, 630])
    }

    @Test("Offsets beyond the rest's own duration are dropped")
    func offsetsBeyondTheDurationAreDropped() {
        var instructions = [
            step("Den Teig mehrere Stunden ruhen lassen.", minutes: 70, step: 1),
            step("Teig nach 30, 60 und 90 Minuten dehnen und falten.", step: 2)
        ]
        TimedFoldExpansion.expand(&instructions)

        #expect(instructions.map(\.step) == [1, 1.1, 1.2])
        #expect(instructions.map(\.duration) == [70, 40, 10])
    }

    @Test("An interval without an explicit count repeats for the rest's whole duration")
    func intervalWithoutCountFillsTheDuration() {
        var instructions = [
            step("Den Teig mehrere Stunden ruhen lassen.", minutes: 90, step: 1),
            step("Alle 30 Minuten dehnen und falten.", step: 2)
        ]
        TimedFoldExpansion.expand(&instructions)

        #expect(instructions.map(\.step) == [1, 1.1, 1.2, 1.3])
        #expect(instructions.map(\.duration) == [90, 60, 30, 0])
    }

    @Test("An explicit repeat count overrules how much of the duration it would otherwise fill")
    func explicitCountOverrulesTheDuration() {
        var instructions = [
            step("3 Stunden ruhen lassen.", minutes: 180, step: 1),
            step("Alle 30 Minuten dehnen und falten, insgesamt 4x.", step: 2)
        ]
        TimedFoldExpansion.expand(&instructions)

        #expect(instructions.map(\.step) == [1, 1.1, 1.2, 1.3, 1.4])
        #expect(instructions.map(\.duration) == [180, 150, 120, 90, 60])
    }

    @Test("A single explicit offset is left alone — one repeated fold time is an interval, not a list")
    func singleExplicitOffsetIsNotExpanded() {
        var instructions = [
            step("2 Stunden ruhen lassen.", minutes: 120, step: 1),
            step("Teig nach 30 Minuten dehnen und falten.", step: 2)
        ]
        let before = instructions.map(\.instruction)
        TimedFoldExpansion.expand(&instructions)

        #expect(instructions.map(\.instruction) == before)
    }

    @Test("A plain step without fold wording is left untouched")
    func unrelatedStepIsUntouched() {
        var instructions = [
            step("Den Teigling rundwirken.", minutes: 5, step: 1)
        ]
        let before = instructions.map(\.instruction)
        TimedFoldExpansion.expand(&instructions)

        #expect(instructions.map(\.instruction) == before)
    }
}
