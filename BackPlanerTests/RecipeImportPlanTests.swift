//
//  RecipeImportPlanTests.swift
//  BackPlanerTests
//

import Testing
@testable import BackPlaner

@Suite("Imported steps are laid out for the planner")
@MainActor
struct RecipeImportPlanTests {

    private func component(_ name: String, ingredients: [(String, Double)]) -> ComponentFB {
        let component = ComponentFB()
        component.name = name
        component.ingredients = ingredients.map { name, weight in
            let ingredient = IngredientFB()
            ingredient.name = name
            ingredient.weight = weight
            return ingredient
        }
        return component
    }

    private func step(_ text: String, _ component: String?, minutes: Int, bakes: Bool = false) -> InstructionFB {
        let instruction = InstructionFB()
        instruction.instruction = component.map { "\($0): \(text)" } ?? text
        instruction.componentName = component
        instruction.duration = minutes
        instruction.bakeFlag = bakes
        return instruction
    }

    /// The Graham loaf: four components that all go into the main dough,
    /// each listed with the same four sentences.
    private func grahamLoaf() -> RecipeFB {
        let recipe = RecipeFB()
        recipe.components = [
            component("Roggensauerteig", ingredients: [("Roggenschrot", 99), ("Wasser", 99)]),
            component("Vorteig A", ingredients: [("Weizenschrot", 49), ("Wasser", 49)]),
            component("Vorteig B", ingredients: [("Dinkelschrot", 49), ("Wasser", 49)]),
            component("Quellstück", ingredients: [("Leinmehl", 16), ("Wasser", 82)]),
            component("Hauptteig", ingredients: [
                ("gesamtes Quellstück", 0), ("Wasser", 321), ("Graham Dinkelvollkornmehl", 395),
                ("gesamter Roggensauerteig", 0), ("gesamter Vorteig A", 0), ("gesamter Vorteig B", 0)
            ])
        ]
        var steps: [InstructionFB] = []
        for name in ["Roggensauerteig", "Vorteig A", "Vorteig B", "Quellstück"] {
            steps.append(step("Die Zutaten in eine Schüssel wiegen.", name, minutes: 0))
            steps.append(step("Mischen, bis sich die Zutaten verbunden haben.", name, minutes: 0))
            steps.append(step("12 Stunden bei 20 °C reifen lassen.", name, minutes: 720))
        }
        steps.append(step("Die Zutaten in die Schüssel wiegen.", "Hauptteig", minutes: 0))
        steps.append(step("Kneten, bis der Teig glatt ist.", "Hauptteig", minutes: 10))
        steps.append(step("1 Stunde bei 20 °C reifen lassen.", "Hauptteig", minutes: 60))
        steps.append(step("Den Teigling rundwirken.", "Hauptteig", minutes: 5))
        steps.append(step("70 Minuten ausbacken.", "Hauptteig", minutes: 70, bakes: true))
        recipe.instructions = steps
        return recipe
    }

    @Test("Components the main dough uses up become one parallel step each")
    func preparationsBecomeParallelSteps() {
        let recipe = grahamLoaf()
        RecipeImportPlan.groupComponentPreparations(in: recipe)

        #expect(recipe.instructions.map(\.step) == [1.1, 1.2, 1.3, 1.4, 2, 3, 4, 5, 6])
        #expect(recipe.instructions.prefix(4).map(\.componentName) == ["Roggensauerteig", "Vorteig A", "Vorteig B", "Quellstück"])
        #expect(recipe.instructions[0].instruction == "Roggensauerteig: Die Zutaten in eine Schüssel wiegen. Mischen, bis sich die Zutaten verbunden haben. 12 Stunden bei 20 °C reifen lassen.")
    }

    @Test("A merged preparation adds its durations up, earlier ones get the handling time of the later ones")
    func mergedDurationsAreSummedAndStaggered() {
        let recipe = grahamLoaf()
        RecipeImportPlan.groupComponentPreparations(in: recipe)

        #expect(recipe.instructions.prefix(4).map(\.duration) == [735, 730, 725, 720])
    }

    @Test("The main dough keeps its steps in order and names its component only once")
    func mainDoughStepsFollow() {
        let recipe = grahamLoaf()
        RecipeImportPlan.groupComponentPreparations(in: recipe)

        let main = Array(recipe.instructions.dropFirst(4))
        #expect(main.map(\.duration) == [0, 10, 60, 5, 70])
        #expect(main.map(\.componentName) == ["Hauptteig", nil, nil, nil, nil])
        #expect(main.last?.bakeFlag == true)
    }

    @Test("A preparation whose 'gesamte …' row went missing is still laid out in parallel")
    func preparationWithoutUsageRowStaysParallel() {
        let recipe = grahamLoaf()
        let mainDough = recipe.components[4]
        mainDough.ingredients.removeAll { $0.name == "gesamtes Quellstück" }
        RecipeImportPlan.groupComponentPreparations(in: recipe)

        #expect(recipe.instructions.map(\.step) == [1.1, 1.2, 1.3, 1.4, 2, 3, 4, 5, 6])
        #expect(recipe.instructions[3].componentName == "Quellstück")
    }

    @Test("A step named only in its text still counts for its component")
    func leadInNamesTheComponent() {
        let recipe = grahamLoaf()
        for instruction in recipe.instructions where instruction.componentName == "Quellstück" {
            instruction.componentName = nil
        }
        RecipeImportPlan.groupComponentPreparations(in: recipe)

        #expect(recipe.instructions.map(\.step) == [1.1, 1.2, 1.3, 1.4, 2, 3, 4, 5, 6])
        #expect(recipe.instructions[3].instruction.hasPrefix("Quellstück: "))
    }

    @Test("A component listed after the final dough keeps its place in the sequence")
    func componentAfterTheFinalDoughStaysSequential() {
        let recipe = RecipeFB()
        recipe.components = [
            component("Vorteig", ingredients: [("Mehl", 100)]),
            component("Hauptteig", ingredients: [("gesamter Vorteig", 0), ("Mehl", 400)]),
            component("Glasur", ingredients: [("Puderzucker", 50)])
        ]
        recipe.instructions = [
            step("12 Stunden reifen lassen.", "Vorteig", minutes: 720),
            step("Kneten.", "Hauptteig", minutes: 10),
            step("Backen.", "Hauptteig", minutes: 40, bakes: true),
            step("Anrühren und auftragen.", "Glasur", minutes: 5)
        ]
        RecipeImportPlan.groupComponentPreparations(in: recipe)

        #expect(recipe.instructions.map(\.step) == [1, 2, 3, 4])
        #expect(recipe.instructions.last?.componentName == "Glasur")
    }

    @Test("Without 'gesamte …' rows every component but the last is a preparation")
    func fallsBackToAllButTheLastComponent() {
        let recipe = RecipeFB()
        recipe.components = [
            component("Poolish", ingredients: [("Mehl", 100)]),
            component("Teig", ingredients: [("Mehl", 400)])
        ]
        recipe.instructions = [
            step("Mischen.", "Poolish", minutes: 5),
            step("12 Stunden reifen lassen.", "Poolish", minutes: 720),
            step("Kneten.", "Teig", minutes: 10),
            step("Backen.", "Teig", minutes: 40, bakes: true)
        ]
        RecipeImportPlan.groupComponentPreparations(in: recipe)

        #expect(recipe.instructions.map(\.step) == [1, 2, 3])
        #expect(recipe.instructions[0].duration == 725)
        #expect(recipe.instructions[0].instruction == "Poolish: Mischen. 12 Stunden reifen lassen.")
    }

    @Test("A single-component recipe is left alone")
    func singleComponentIsUntouched() {
        let recipe = RecipeFB()
        recipe.components = [component("Hauptteig", ingredients: [("Mehl", 500)])]
        recipe.instructions = [
            step("Kneten.", "Hauptteig", minutes: 10),
            step("Backen.", "Hauptteig", minutes: 40, bakes: true)
        ]
        recipe.instructions.enumerated().forEach { $1.step = Double($0 + 1) }
        RecipeImportPlan.groupComponentPreparations(in: recipe)

        #expect(recipe.instructions.map(\.step) == [1, 2])
        #expect(recipe.instructions.map(\.componentName) == ["Hauptteig", "Hauptteig"])
    }
}
