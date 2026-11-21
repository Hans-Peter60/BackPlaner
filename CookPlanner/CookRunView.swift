//
//  CookRunView.swift
//  CookPlanner
//
//  One stopwatch record: the total against the plan, then each step with
//  the moment it was done, how long it took and the difference to the
//  plan.
//

import BakePlannerCore
import SwiftUI

struct CookRunView: View {

    let run: KitchenCookRun
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    LabeledContent("Gebraucht") {
                        Text(verbatim: KitchenCookRun.clockText(run.totalSeconds))
                            .monospacedDigit()
                    }
                    LabeledContent("Geplant") {
                        Text(verbatim: KitchenCookRun.clockText(run.plannedMinutes * 60))
                            .monospacedDigit()
                    }
                    if run.isComplete {
                        LabeledContent("Unterschied") {
                            let difference = run.totalSeconds - run.plannedMinutes * 60
                            Text(verbatim: KitchenCookRun.differenceText(difference))
                                .monospacedDigit()
                                .foregroundColor(difference > 0 ? Theme.warning : Theme.good)
                        }
                    } else if let total = run.totalSteps {
                        Text("Vorzeitig beendet: \(run.steps.count) von \(total) Schritten erledigt.")
                            .foregroundColor(Theme.warning)
                    }
                } header: {
                    Text(verbatim: run.startedAt.formatted(date: .abbreviated, time: .shortened))
                }

                Section {
                    ForEach(run.steps, id: \.taskID) { step in
                        VStack(alignment: .leading, spacing: 3) {
                            Text(verbatim: step.name)
                                .fixedSize(horizontal: false, vertical: true)
                            HStack(alignment: .firstTextBaseline, spacing: 6) {
                                Image(systemName: step.tickedByCook ? "checkmark.circle" : "timer")
                                Text("erledigt \(KitchenCookRun.clockText(step.doneSecond)) · gebraucht \(KitchenCookRun.clockText(step.actualSeconds)) · geplant \(step.plannedMinutes) Min.")
                                    .fixedSize(horizontal: false, vertical: true)
                                Spacer(minLength: 8)
                                Text(verbatim: KitchenCookRun.differenceText(step.differenceSeconds))
                                    .foregroundColor(step.differenceSeconds > 60 ? Theme.warning
                                                     : step.differenceSeconds < -60 ? Theme.good : .secondary)
                            }
                            .font(.footnote.monospacedDigit())
                            .foregroundColor(.secondary)
                            if !step.component.isEmpty {
                                Text(verbatim: step.component)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                } header: {
                    Text("Schritte")
                } footer: {
                    Text("Ein Handschritt zählt ab dem vorigen Abhaken – oder ab der Minute, für die der Plan ihn vorsah, wenn die später lag – bis zu seinem eigenen. Schritte mit Uhr-Symbol liefen von allein und endeten nach Plan.")
                }
            }
            .navigationTitle("Protokoll")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Fertig") { dismiss() }
                }
            }
        }
    }
}
