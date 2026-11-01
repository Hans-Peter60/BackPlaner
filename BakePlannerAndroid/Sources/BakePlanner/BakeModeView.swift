import BakePlannerCore
import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

/// The kitchen view of a running plan, as on the iPhone: one step at a time
/// in large type, the component's ingredients at the planned amount, big
/// buttons for back, next and done, and a screen that stays on. Opens at the
/// step that matters now (CurrentStepRule). Reading aloud follows later.
struct BakeModeView: View {
    let model: AppModel
    /// One plan only (PlanTimelineView.planKey), or every plan for nil.
    let planKey: String?
    /// The step on display. Nil until the view picks the one that matters
    /// now; afterwards the user's own choice.
    @State var currentKey: String?
    @Environment(\.dismiss) var dismiss
    @Environment(\.colorScheme) var colorScheme

    /// The steps shown: those not held back by the rhythm, of one plan or
    /// all, by date.
    private var steps: [StoredScheduledStep] {
        model.scheduledSteps.filter { step in
            step.data.isVisible() && (planKey == nil || PlanTimelineView.planKey(of: step) == planKey)
        }
    }

    private var currentIndex: Int? {
        guard let currentKey else { return nil }
        return steps.firstIndex { $0.key == currentKey }
    }

    /// The step due within the last hour, else the next one ahead, else the
    /// last of the plan — the rule of the iPhone's card, widget and bake mode.
    private func initialStep(at now: Date) -> StoredScheduledStep? {
        CurrentStepRule.currentStep(in: steps, at: now, date: { $0.data.date })?.step ?? steps.last
    }

    var body: some View {
        let steps = self.steps
        return ZStack {
            LinearGradient(colors: [Palette.backgroundTop(colorScheme), Palette.backgroundBottom(colorScheme)],
                           startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()

            if let index = currentIndex, steps.indices.contains(index) {
                stepView(steps[index], index: index, count: steps.count)
            } else {
                Text("Keine geplanten Schritte")
                    .font(.title2)
                    .foregroundStyle(Palette.accent(colorScheme))
            }
        }
        .navigationTitle("Backmodus")
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Schließen") {
                    dismiss()
                }
            }
        }
        .onAppear {
            // Baking takes longer than the screen lock; the screen stays on
            // for as long as this view is up.
            UIApplication.shared.isIdleTimerDisabled = true
            if currentKey == nil {
                currentKey = initialStep(at: Date())?.key
            }
        }
        .onDisappear {
            UIApplication.shared.isIdleTimerDisabled = false
        }
    }

    private func stepView(_ step: StoredScheduledStep, index: Int, count: Int) -> some View {
        let recipe = model.recipes.first { $0.content.name == step.data.recipeName }?.content
        let component = recipe.flatMap { BakeModeText.component(of: step.data, in: $0) }
        return VStack(spacing: 16) {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(verbatim: step.data.recipeName)
                            .font(.headline)
                            .foregroundStyle(Palette.accent(colorScheme))
                        Text("Schritt \(index + 1) von \(count)")
                            .font(.subheadline)
                        HStack(spacing: 8) {
                            Text(verbatim: PlanText.dateTime(step.data.date))
                            timing(of: step.data.date)
                        }
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    }

                    Text(verbatim: step.data.instruction)
                        .font(.title2)

                    if let component, !component.ingredients.isEmpty {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Zutaten für „\(component.name)“")
                                .font(.headline)
                            ForEach(Array(BakeModeText.ingredientLines(of: component,
                                                                       scale: step.data.effectiveServingScale).enumerated()),
                                    id: \.offset) { _, line in
                                Text(verbatim: line)
                                    .font(.title3)
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
            }

            HStack(spacing: 12) {
                Button {
                    currentKey = steps[index - 1].key
                } label: {
                    Text("Zurück")
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                }
                .buttonStyle(.bordered)
                .disabled(index == 0)

                Button {
                    currentKey = steps[index + 1].key
                } label: {
                    Text("Weiter")
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                }
                .buttonStyle(.bordered)
                .disabled(index + 1 >= count)
            }
            .padding(.horizontal)

            Button {
                markDone(step, at: index)
            } label: {
                Text("Erledigt")
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
            }
            .buttonStyle(.borderedProminent)
            .tint(Palette.accent(colorScheme))
            .padding([.horizontal, .bottom])
        }
    }

    /// "in 20m", "seit 5m": how far the step is from now.
    @ViewBuilder
    private func timing(of date: Date) -> some View {
        let minutes = Int((date.timeIntervalSinceNow / 60).rounded())
        if minutes > 0 {
            Text("in \(BakeHistoryFacts.durationText(minutes))")
        } else if minutes < 0 {
            Text("seit \(BakeHistoryFacts.durationText(-minutes))")
        } else {
            Text("Jetzt")
        }
    }

    /// The step is done: it goes, with its reminder, and the step that took
    /// its place is shown — or the last one, at the end of the plan.
    private func markDone(_ step: StoredScheduledStep, at index: Int) {
        model.markDone(step)
        let remaining = steps
        if remaining.isEmpty {
            currentKey = nil
        } else {
            currentKey = remaining[min(index, remaining.count - 1)].key
        }
    }
}
