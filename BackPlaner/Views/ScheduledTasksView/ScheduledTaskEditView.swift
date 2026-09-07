//
//  ScheduledTaskDetailView.swift
//  PetersBackPlaner
//
//  Created by Hans-Peter Müller on 05.06.22.
//

import SwiftUI
import CoreData

struct ScheduledTaskDetailView: View {

    var index: Int

    @FetchRequest(sortDescriptors: [NSSortDescriptor(key: "date", ascending: true)])
    private var nextSteps: FetchedResults<NextStep>

    var body: some View {
        Group {
            if nextSteps.indices.contains(index) {
                let nextStep = nextSteps[index]

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
