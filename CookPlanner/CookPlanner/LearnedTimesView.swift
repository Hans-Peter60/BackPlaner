//
//  LearnedTimesView.swift
//  CookPlanner
//
//  What the stopwatch records say the steps really take, next to what
//  the dish has, to take over in one tap. An example is not the cook's
//  to change; its learned times go into a copy among the own dishes.
//

import BakePlannerCore
import SwiftUI

struct LearnedTimesView: View {

    let dish: KitchenDish
    let suggestions: [KitchenTimeLearning.Suggestion]
    /// Called with the dish carrying the new minutes.
    let onApply: (KitchenDish) -> Void

    @Environment(\.dismiss) private var dismiss

    private var isExample: Bool { dish.source == .sample }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(suggestions, id: \.taskID) { suggestion in
                        VStack(alignment: .leading, spacing: 3) {
                            Text(verbatim: suggestion.name)
                                .fixedSize(horizontal: false, vertical: true)
                            HStack(spacing: 6) {
                                Text(verbatim: minutesText(suggestion.handsBefore, suggestion.unattendedBefore))
                                    .foregroundColor(.secondary)
                                Image(systemName: "arrow.right")
                                    .foregroundColor(.secondary)
                                    .accessibilityHidden(true)
                                Text(verbatim: minutesText(suggestion.hands, suggestion.unattended))
                                    .foregroundColor(Theme.accentText)
                                Spacer()
                                Text("aus \(suggestion.runs) Durchgängen")
                                    .foregroundColor(.secondary)
                            }
                            .font(.footnote.monospacedDigit())
                        }
                    }
                } footer: {
                    Text("Der Mittelwert (Median) der abgehakten Zeiten aus den letzten bis zu fünf Durchgängen. Bei Töpfen und Ofenschritten bleibt die Handarbeit, die Zeit allein passt sich an.")
                }
            }
            .navigationTitle("Gemessene Zeiten")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Abbrechen") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isExample ? "Als eigenes Gericht" : "Übernehmen") {
                        let learned = KitchenTimeLearning.applying(suggestions, to: dish)
                        onApply(isExample ? learned.duplicate() : learned)
                        dismiss()
                    }
                }
            }
        }
    }

    /// "4 Min." or "1 + 13 Min." for hands and unattended minutes.
    private func minutesText(_ hands: Int, _ unattended: Int) -> String {
        unattended > 0
            ? String(localized: "\(hands) + \(unattended) Min.")
            : String(localized: "\(hands) Min.")
    }
}
