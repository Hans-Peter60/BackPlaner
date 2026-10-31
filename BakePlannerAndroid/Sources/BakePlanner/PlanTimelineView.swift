import BakePlannerCore
import SwiftUI

/// The planned steps of every plan, plan by plan in the order they begin:
/// each step with its time, done with a tap; a whole plan removed after
/// asking. Steps the rhythm queued ahead of time show up two days before
/// they are due, as on the iPhone.
struct PlanTimelineView: View {
    let model: AppModel
    /// The plan waiting for the user to confirm its removal. Kept apart from
    /// the dialog's visibility: Android closes the dialog before it runs
    /// the chosen button.
    @State var planToDelete: TimelinePlan?
    @State var confirmsDeletion = false
    @Environment(\.colorScheme) var colorScheme

    /// One plan: the steps of one planning run.
    struct TimelinePlan: Identifiable {
        let id: String
        let recipeName: String
        let steps: [StoredScheduledStep]
    }

    /// Which plan a step belongs to. Steps planned before plans had an id
    /// belong together by recipe.
    static func planKey(of step: StoredScheduledStep) -> String {
        step.data.planID?.uuidString ?? "recipe:" + step.data.recipeName
    }

    private var plans: [TimelinePlan] {
        let visible = model.scheduledSteps.filter { $0.data.isVisible() }
        var order: [String] = []
        var grouped: [String: [StoredScheduledStep]] = [:]
        for step in visible {
            let key = Self.planKey(of: step)
            if grouped[key] == nil { order.append(key) }
            grouped[key, default: []].append(step)
        }
        return order.compactMap { key in
            guard let steps = grouped[key], let first = steps.first else { return nil }
            return TimelinePlan(id: key, recipeName: first.data.recipeName, steps: steps)
        }
    }

    var body: some View {
        let plans = self.plans
        return ZStack {
            LinearGradient(colors: [Palette.backgroundTop(colorScheme), Palette.backgroundBottom(colorScheme)],
                           startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()

            if plans.isEmpty {
                VStack(spacing: 12) {
                    Text("Keine geplanten Schritte")
                        .font(.title2)
                        .foregroundStyle(Palette.accent(colorScheme))
                    Text("Öffne ein Rezept und tippe auf „Planen“.")
                        .multilineTextAlignment(.center)
                }
                .padding()
            } else {
                List {
                    ForEach(plans) { plan in
                        Section {
                            ForEach(plan.steps, id: \.key) { step in
                                HStack(alignment: .top, spacing: 8) {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(verbatim: PlanText.dateTime(step.data.date))
                                            .font(.caption)
                                            .foregroundStyle(step.data.date < Date() ? Color.red : Color.secondary)
                                        Text(verbatim: step.data.instruction)
                                    }
                                    Spacer()
                                    Button("Erledigt") {
                                        model.markDone(step)
                                    }
                                    .buttonStyle(.bordered)
                                }
                            }
                            Button("Geplante Schritte löschen", role: .destructive) {
                                planToDelete = plan
                                confirmsDeletion = true
                            }
                        } header: {
                            Text(verbatim: plan.recipeName)
                        }
                    }
                }
                .scrollContentBackground(.hidden)
            }
        }
        .navigationTitle("Geplante nächste Schritte")
        .task {
            model.loadScheduledSteps()
        }
        .alert("Bist Du sicher?", isPresented: $confirmsDeletion) {
            Button("Löschen", role: .destructive) {
                if let plan = planToDelete {
                    // Every step of the plan, those not shown yet included.
                    model.deletePlan(model.scheduledSteps.filter { Self.planKey(of: $0) == plan.id })
                }
                planToDelete = nil
            }
            Button("Abbrechen", role: .cancel) {
                planToDelete = nil
            }
        } message: {
            if let plan = planToDelete {
                Text(verbatim: plan.recipeName)
            }
        }
    }
}
