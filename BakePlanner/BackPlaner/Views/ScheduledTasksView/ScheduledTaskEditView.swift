//
//  ScheduledTaskDetailView.swift
//  PetersBackPlaner
//
//  Created by Hans-Peter Müller on 05.06.22.
//

import BakePlannerCore
import SwiftUI
import CoreData

struct ScheduledTaskDetailView: View {

    /// The row in the date-sorted list of planned steps — how the list
    /// opens the detail — or the step itself, how the timeline opens it.
    private let index: Int?
    private let stepID: NSManagedObjectID?

    init(index: Int) {
        self.index = index
        self.stepID = nil
    }

    init(stepID: NSManagedObjectID) {
        self.index = nil
        self.stepID = stepID
    }

    @FetchRequest(sortDescriptors: [NSSortDescriptor(key: "date", ascending: true)])
    private var nextSteps: FetchedResults<NextStep>

    // For the ingredients of a mixing step: the own recipes and, through
    // the model, the public ones.
    @FetchRequest(sortDescriptors: [NSSortDescriptor(key: "name", ascending: true)])
    private var recipes: FetchedResults<Recipe>
    @EnvironmentObject private var model: RecipeModel

    private var step: NextStep? {
        if let stepID {
            return nextSteps.first { $0.objectID == stepID }
        }
        if let index, nextSteps.indices.contains(index) {
            return nextSteps[index]
        }
        return nil
    }

    var body: some View {
        Group {
            if let nextStep = step {
                Form {
                    Section("Nächster Schritt") {
                        LabeledContent("Rezept", value: nextStep.recipeName)
                        LabeledContent("Beginn") {
                            StackedDateTime(date: nextStep.date, alignment: .trailing)
                        }
                        LabeledContent("Nummer", value: Rational.decimalPlace(nextStep.step, 10))
                        LabeledContent("Dauer", value: Rational.displayHoursMinutes(nextStep.duration))
                    }

                    Section("Beschreibung") {
                        Text(nextStep.instruction)
                    }

                    // A step that mixes a component shows what goes in, at
                    // the plan's amount — the same lines the reminder names.
                    if let ingredients = PlannedStepComponent.ingredients(for: nextStep, recipes: recipes,
                                                                          publicRecipes: model.recipesFB) {
                        Section {
                            if ingredients.lines.isEmpty {
                                Text("Keine Zutaten vorhanden")
                                    .foregroundColor(Theme.subtitle)
                            } else {
                                ForEach(Array(ingredients.lines.enumerated()), id: \.offset) { _, line in
                                    Text(line)
                                }
                            }
                        } header: {
                            Text("Zutaten für „\(ingredients.name)“")
                        }
                    }
                }
                .scrollContentBackground(.hidden)
            } else {
                ContentUnavailableView(
                    "Schritt nicht gefunden",
                    systemImage: "calendar.badge.exclamationmark",
                    description: Text("Der geplante Schritt ist nicht mehr vorhanden.")
                )
            }
        }
        .warmBackground()
        .navigationTitle("Nächster Schritt")
        .navigationBarTitleDisplayMode(.inline)
    }
}
