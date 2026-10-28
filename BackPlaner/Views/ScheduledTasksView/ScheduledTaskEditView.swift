//
//  ScheduledTaskDetailView.swift
//  PetersBackPlaner
//
//  Created by Hans-Peter Müller on 05.06.22.
//

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
                        LabeledContent("Schritt", value: Rational.decimalPlace(nextStep.step, 10))
                        LabeledContent("Dauer", value: Rational.displayHoursMinutes(nextStep.duration))
                    }

                    Section("Beschreibung") {
                        Text(nextStep.instruction)
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
