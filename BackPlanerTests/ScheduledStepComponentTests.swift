//
//  ScheduledStepComponentTests.swift
//  BackPlanerTests
//

import Testing
@testable import BackPlaner

@Suite("Component of a planned step")
struct ScheduledStepComponentTests {

    private let ciabatta = ["Vorteig A", "Vorteig B", "Weizensauerteig", "Hauptteig"]

    @Test("A stored component name wins over the wording")
    func storedNameWins() {
        #expect(ScheduledStepComponent.componentName(
            stored: "Hauptteig",
            instructionText: "Vorteig A herstellen",
            among: ciabatta
        ) == "Hauptteig")
    }

    @Test("A stored name the recipe no longer has falls back to the wording")
    func unknownStoredNameFallsBack() {
        #expect(ScheduledStepComponent.componentName(
            stored: "Poolish",
            instructionText: "Vorteig B herstellen",
            among: ciabatta
        ) == "Vorteig B")
    }

    @Test("Hand-typed steps are matched by the component they name",
          arguments: [
            ("Vorteig A herstellen", "Vorteig A"),
            ("Vorteig B herstellen", "Vorteig B"),
            ("Hauptteig herstellen", "Hauptteig"),
            ("WEIZENSAUERTEIG ansetzen", "Weizensauerteig"),
            ("Teig falten und ruhen lassen", nil)
          ])
    func matchesByWording(text: String, expected: String?) {
        #expect(ScheduledStepComponent.componentName(
            stored: nil,
            instructionText: text,
            among: ciabatta
        ) == expected)
    }

    @Test("The component mentioned first wins, the longer name at the same spot")
    func firstMentionWins() {
        #expect(ScheduledStepComponent.componentName(
            stored: nil,
            instructionText: "Hauptteig herstellen: Vorteig A und Vorteig B zugeben",
            among: ciabatta
        ) == "Hauptteig")

        #expect(ScheduledStepComponent.componentName(
            stored: nil,
            instructionText: "Vorteig A herstellen",
            among: ["Vorteig", "Vorteig A"]
        ) == "Vorteig A")
    }

    // MARK: - Reminder text

    private let vorteigA = ComponentColumn(
        id: "vorteig-a",
        name: "Vorteig A",
        ingredients: [
            TotalIngredientData(name: "Weizenmehl 550", unit: "g", weight: 200, numerator: 0, denominator: 0),
            TotalIngredientData(name: "Wasser", unit: "g", weight: 200, numerator: 0, denominator: 0)
        ]
    )

    @Test("The ingredient list is headed by the component and lists every ingredient")
    func ingredientsTextListsEveryIngredient() throws {
        let text = try #require(ScheduledStepComponent.ingredientsText(for: vorteigA, servingSize: 2))
        let lines = text.split(separator: "\n")

        #expect(lines.count == 3)
        #expect(lines[0].contains("Vorteig A"))
        #expect(lines[1].hasPrefix("• "))
        #expect(lines[1].hasSuffix("Weizenmehl 550"))
        #expect(lines[2].hasSuffix("Wasser"))
    }

    @Test("A component without ingredients adds no text to the reminder")
    func emptyComponentHasNoText() {
        let empty = ComponentColumn(id: "empty", name: "Hauptteig", ingredients: [])
        #expect(ScheduledStepComponent.ingredientsText(for: empty, servingSize: 2) == nil)
    }

    @Test("The reminder body keeps the bare instruction when there are no details")
    func reminderBodyWithoutDetails() {
        #expect(NotificationActions.reminderBody(instruction: "Teig falten", details: nil) == "Teig falten")
        #expect(NotificationActions.reminderBody(instruction: "Teig falten", details: "") == "Teig falten")
    }

    @Test("The reminder body puts the details under the instruction")
    func reminderBodyWithDetails() {
        #expect(NotificationActions.reminderBody(instruction: "Vorteig A herstellen", details: "Zutaten:\n• 200 g Mehl")
                == "Vorteig A herstellen\n\nZutaten:\n• 200 g Mehl")
    }
}
