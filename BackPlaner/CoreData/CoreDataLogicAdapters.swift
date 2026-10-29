//
//  CoreDataLogicAdapters.swift
//  BackPlaner
//
//  The bridge from the Core Data objects to the plain structs the logic
//  works on. Keeping it here leaves DoughComposition, Rational,
//  BakeHistoryFacts and StarterFeedingFacts free of Core Data, so they can
//  later move into a platform-neutral package unchanged.
//

import Foundation
import CoreData

extension DoughComposition {
    static func components(of recipe: Recipe) -> [Component] {
        recipe.componentsArray.map { component in
            Component(name: component.name, ingredients: component.ingredientsArray.map { ingredient in
                Ingredient(name: ingredient.name,
                           grams: ingredient.normWeight > 0 ? ingredient.normWeight : ingredient.weight,
                           weight: ingredient.weight,
                           numerator: ingredient.num,
                           denominator: ingredient.denom)
            })
        }
    }
}

extension Rational.ComponentDependency {
    static func from(_ components: [Component]) -> [Rational.ComponentDependency] {
        let names = components.map { $0.name }
        return components.map { component in
            Rational.ComponentDependency(
                name: component.name,
                requires: requirements(
                    of: component.ingredientsArray.filter { $0.weight == 0 }.map { $0.name },
                    componentNames: names,
                    excluding: component.name
                )
            )
        }
    }
}

// MARK: - Recipe content

extension StarterFeedingRatio {
    static func ratio(for recipe: Recipe) -> Ratio? {
        ratio(for: RecipeExportData(recipe: recipe, includingImage: false))
    }
}

extension StarterRecipe {
    static func isStarterFeeding(_ recipe: Recipe) -> Bool {
        isStarterFeeding(RecipeExportData(recipe: recipe, includingImage: false))
    }
}

extension ScheduledStepComponent {
    static func column(for recipe: Recipe, step: Double?, instructionText: String) -> ComponentColumn? {
        column(for: RecipeExportData(recipe: recipe, includingImage: false), step: step,
               instructionText: instructionText)
    }
}

// MARK: - Component columns

extension ComponentColumn {
    /// The components of one of the user's own recipes.
    static func columns(of components: [Component]) -> [ComponentColumn] {
        components
            .sorted { $0.number < $1.number }
            .map { component in
                ComponentColumn(
                    id: component.objectID.uriRepresentation().absoluteString,
                    name: component.name,
                    // Already sorted by number by the accessor itself.
                    ingredients: component.ingredientsArray.map {
                        TotalIngredientData(name: $0.name,
                                            unit: $0.unit ?? "",
                                            weight: $0.weight,
                                            numerator: $0.num,
                                            denominator: $0.denom)
                    }
                )
            }
    }
}

// MARK: - Bake history

extension BakeHistory {

    /// The structured part of the entry. Empty texts are stored as `nil`, so
    /// an untouched field never counts as recorded.
    var facts: BakeHistoryFacts {
        get {
            BakeHistoryFacts(roomTemperature: roomTemperature?.doubleValue,
                             doughTemperature: doughTemperature?.doubleValue,
                             bulkProofMinutes: bulkProofMinutes?.intValue,
                             finalProofMinutes: finalProofMinutes?.intValue,
                             flour: flour ?? "",
                             outcome: outcome ?? "")
        }
        set {
            roomTemperature   = newValue.roomTemperature.map { NSNumber(value: $0) }
            doughTemperature  = newValue.doughTemperature.map { NSNumber(value: $0) }
            bulkProofMinutes  = newValue.bulkProofMinutes.flatMap { $0 > 0 ? NSNumber(value: $0) : nil }
            finalProofMinutes = newValue.finalProofMinutes.flatMap { $0 > 0 ? NSNumber(value: $0) : nil }
            let flour = newValue.flour.trimmingCharacters(in: .whitespacesAndNewlines)
            self.flour = flour.isEmpty ? nil : flour
            let outcome = newValue.outcome.trimmingCharacters(in: .whitespacesAndNewlines)
            self.outcome = outcome.isEmpty ? nil : outcome
        }
    }

    /// Whether the entry holds anything worth reading: a fact, a real
    /// comment or a photo.
    var hasNotes: Bool {
        !facts.isEmpty
            || !BakeHistoryFacts.isPlaceholderComment(comment)
            || !(images ?? []).isEmpty
    }
}

extension Recipe {

    /// The entry of the recipe's last bake that has already taken place, if
    /// there is one — what "last time" refers to when the recipe is planned
    /// again.
    func lastCompletedBakeHistory(now: Date = Date()) -> BakeHistory? {
        BakeHistoryFacts.lastCompleted(bakeHistoriesArray, date: \.date, now: now)
    }
}

// MARK: - Starter feeding log

extension StarterFeedingLog {

    /// Empty texts are stored as `nil`, so an untouched note never counts as
    /// written.
    var facts: StarterFeedingFacts {
        get {
            StarterFeedingFacts(peakMinutes: peakMinutes?.intValue,
                                 floatTestPassed: floatTestPassed?.boolValue,
                                 note: note ?? "")
        }
        set {
            peakMinutes = newValue.peakMinutes.flatMap { $0 > 0 ? NSNumber(value: $0) : nil }
            floatTestPassed = newValue.floatTestPassed.map { NSNumber(value: $0) }
            let note = newValue.note.trimmingCharacters(in: .whitespacesAndNewlines)
            self.note = note.isEmpty ? nil : note
        }
    }
}

// MARK: - Adjusted copies

/// The copy an adjustment sheet has just written, for the recipe screen to
/// open it.
struct AdjustedRecipeCopy: Identifiable, Hashable {
    let id: NSManagedObjectID
}

extension RecipeExportData {

    /// Writes this data over an existing recipe: name, total weight and the
    /// components with their ingredients. Everything else — steps, bake
    /// history, feeding log, shopping lists — stays, because an adjustment
    /// changes amounts and ingredient names and nothing more.
    ///
    /// The components are replaced rather than matched up: an adjustment
    /// may rename a line, and nothing else refers to a component object.
    func update(_ recipe: Recipe, in context: NSManagedObjectContext) {
        recipe.name        = name
        recipe.totalWeight = totalWeight

        for case let component as Component in recipe.components {
            recipe.removeFromComponents(component)
            context.delete(component)
        }

        for componentData in components {
            let component    = Component(context: context)
            component.id     = UUID()
            component.name   = componentData.name
            component.number = componentData.number

            for ingredientData in componentData.ingredients {
                let ingredient        = Ingredient(context: context)
                ingredient.id         = UUID()
                ingredient.name       = ingredientData.name
                ingredient.number     = ingredientData.number
                ingredient.unit       = ingredientData.unit
                ingredient.weight     = ingredientData.weight
                ingredient.normWeight = ingredientData.normWeight
                ingredient.num        = ingredientData.num
                ingredient.denom      = ingredientData.denom
                component.addToIngredients(ingredient)
            }

            recipe.addToComponents(component)
        }
    }
}

// MARK: - Fold steps

extension TimedFoldExpansion {
    /// Expands the fold instructions of a stored recipe, adding, renumbering
    /// and removing its `Instruction` objects as the array form does. Returns
    /// whether anything changed; the caller saves the context.
    @discardableResult
    static func expand(in recipe: Recipe, context: NSManagedObjectContext) -> Bool {
        let stored = recipe.instructionsArray
        var working = [InstructionFB]()
        var origin = [ObjectIdentifier: Instruction]()
        for instruction in stored {
            let instructionFB = InstructionFB()
            instructionFB.id = instruction.id?.uuidString ?? UUID().uuidString
            instructionFB.instruction = instruction.instruction
            instructionFB.step = instruction.step
            instructionFB.duration = instruction.duration
            instructionFB.startTime = instruction.startTime
            instructionFB.componentName = instruction.componentName
            working.append(instructionFB)
            origin[ObjectIdentifier(instructionFB)] = instruction
        }

        guard expand(&working) else { return false }

        var kept = Set<ObjectID>()
        for instructionFB in working {
            if let instruction = origin[ObjectIdentifier(instructionFB)] {
                instruction.step = instructionFB.step
                instruction.duration = instructionFB.duration
                kept.insert(instruction.objectID)
            } else {
                let instruction = Instruction(context: context)
                instruction.id = UUID()
                instruction.instruction = instructionFB.instruction
                instruction.step = instructionFB.step
                instruction.duration = instructionFB.duration
                instruction.componentName = instructionFB.componentName
                recipe.addToInstructions(instruction)
            }
        }
        for instruction in stored where !kept.contains(instruction.objectID) {
            recipe.removeFromInstructions(instruction)
            context.delete(instruction)
        }
        return true
    }

    private typealias ObjectID = NSManagedObjectID
}
