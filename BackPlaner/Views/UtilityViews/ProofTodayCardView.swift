//
//  ProofTodayCardView.swift
//  BackPlaner
//
//  "Gare heute": a bread's fermentation steps at today's room temperature,
//  on the baking views of own and public recipes above the step table.
//  The durations come from ProofTiming — scaled from the recipe, or
//  estimated from the bakes that measured the proof. "Gare an heutige
//  Temperatur anpassen" changes this plan only; the recipe keeps its
//  durations, which are read as written for the reference temperature.
//  The bakes can also say what the recipe's durations should be; that
//  second button does change the recipe.
//

import BakePlannerCore
import SwiftUI

struct ProofTodayCardView: View {

    /// Today's room temperature in °C.
    @Binding var temperature: Int
    /// The phases found in the recipe, each with its duration today.
    let adjustments: [ProofTiming.Adjustment]
    /// Whether the plan already uses an adjustment's durations.
    let isApplied: (ProofTiming.Adjustment) -> Bool
    /// Whether the plan's durations differ from the recipe's at all.
    let isAdjusted: Bool
    /// What the bakes say the recipe's durations should be; empty for a
    /// public recipe, or without a bake that measured the proof.
    let recipeDurations: [ProofTiming.RecipeDurations]
    let onApplyToday: () -> Void
    let onReset: () -> Void
    let onApplyHistory: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Gare heute")
                .font(Theme.bodyFont(14).weight(.semibold))
                .foregroundColor(Theme.cardTitle)

            Stepper(value: $temperature, in: ProofTiming.temperatureRange) {
                LabeledContent("Raumtemperatur heute", value: "\(temperature) °C")
                    .font(Theme.bodyFont(14))
            }

            ForEach(adjustments, id: \.phase) { adjustment in
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(adjustment.phase.title()): geplant \(BakeHistoryFacts.durationText(adjustment.plannedMinutes)) · heute etwa \(BakeHistoryFacts.durationText(adjustment.minutes))")
                        .font(Theme.bodyFont(14))
                        .foregroundColor(Theme.cardTitle)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(adjustment.sourceText())
                        .font(Theme.bodyFont(13))
                        .foregroundColor(Theme.subtitle)
                }
            }

            if adjustments.contains(where: { !isApplied($0) }) {
                Button(action: onApplyToday) {
                    Label("Gare an heutige Temperatur anpassen", systemImage: "thermometer.medium")
                        .font(Theme.bodyFont(14).weight(.semibold))
                }
                .accessibilityIdentifier("plan.applyProofToday")
            }

            if isAdjusted {
                Text("Für diesen Plan angepasst; das Rezept bleibt unverändert.")
                    .font(Theme.bodyFont(13))
                    .foregroundColor(Theme.subtitle)
                    .fixedSize(horizontal: false, vertical: true)
                Button(action: onReset) {
                    Label("Dauern des Rezepts verwenden", systemImage: "arrow.uturn.backward")
                        .font(Theme.bodyFont(14))
                }
                .accessibilityIdentifier("plan.resetProof")
            }

            if !recipeDurations.isEmpty {
                Divider()
                ForEach(recipeDurations, id: \.phase) { durations in
                    Text("\(durations.phase.title()): \(BakeHistoryFacts.durationText(durations.minutes)) bei \(BakeHistoryFacts.temperatureText(durations.referenceTemperature, locale: AppSettings.locale)) \(ProofTiming.bakesText(durations.bakes)), im Rezept \(BakeHistoryFacts.durationText(durations.plannedMinutes))")
                        .font(Theme.bodyFont(14))
                        .foregroundColor(Theme.cardTitle)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Button(action: onApplyHistory) {
                    Label("Dauern aus den Backvorgängen ins Rezept übernehmen", systemImage: "square.and.pencil")
                        .font(Theme.bodyFont(14).weight(.semibold))
                }
                .accessibilityIdentifier("plan.applyProofHistory")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardStyle()
    }
}

#Preview("Gare heute") {
    @Previewable @State var temperature = 18
    let steps = [ProofTiming.Step(index: 0, phase: .preferment, minutes: 600),
                 ProofTiming.Step(index: 2, phase: .bulk, minutes: 180, statedTemperature: 24),
                 ProofTiming.Step(index: 4, phase: .final, minutes: 60)]
    let history = [BakeHistoryFacts(roomTemperature: 21, bulkProofMinutes: 230)]
    ScrollView {
        ProofTodayCardView(temperature: $temperature,
                           adjustments: ProofTiming.adjustments(steps: steps, history: history, at: Double(temperature)),
                           isApplied: { _ in false },
                           isAdjusted: false,
                           recipeDurations: ProofTiming.recipeDurations(steps: steps, history: history),
                           onApplyToday: { },
                           onReset: { },
                           onApplyHistory: { })
        .padding()
    }
    .warmBackground()
}
