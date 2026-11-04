//
//  WatchPlanView.swift
//  BakePlannerWatch
//
//  One planned step per page, turned with the crown: recipe, step counter,
//  the instruction in large type, when it is due and how far off that is,
//  the ingredients the step mixes, and "Erledigt". Opens on the step that
//  matters now, like the iPhone's bake mode.
//

import SwiftUI

struct WatchPlanView: View {
    @Environment(PhonePlanSession.self) private var session
    @State private var selectedID: String?

    var body: some View {
        let steps = session.steps
        Group {
            if steps.isEmpty {
                ContentUnavailableView {
                    Label("Keine geplanten Schritte", systemImage: "calendar")
                } description: {
                    Text("Setze Erinnerungen in der Backanleitung eines Rezepts auf dem iPhone.")
                }
            } else {
                TabView(selection: $selectedID) {
                    ForEach(Array(steps.enumerated()), id: \.element.id) { index, step in
                        StepPage(step: step, index: index, count: steps.count) {
                            // On to the step that follows — or back to the one
                            // before, at the end of the plan.
                            let successor = index + 1 < steps.count
                                ? steps[index + 1].id
                                : (index > 0 ? steps[index - 1].id : nil)
                            session.markDone(step.id)
                            selectedID = successor
                        }
                        .tag(Optional(step.id))
                    }
                }
                .tabViewStyle(.verticalPage)
            }
        }
        .onAppear { settle(on: steps) }
        .onChange(of: steps.map(\.id)) { _, _ in settle(on: session.steps) }
    }

    /// Opens on the step that matters now, and moves on when the step on
    /// display left the plan — marked done on the iPhone, say.
    private func settle(on steps: [PlanSnapshot.Step]) {
        if let selectedID, steps.contains(where: { $0.id == selectedID }) { return }
        selectedID = session.currentStepID(at: Date())
    }
}

private struct StepPage: View {
    let step: PlanSnapshot.Step
    let index: Int
    let count: Int
    let markDone: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 6) {
                Text(step.recipeName)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                Text("Schritt \(index + 1) von \(count)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)

                Text(step.instruction)
                    .font(.headline)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 2)

                timing

                if let lines = step.ingredientLines, !lines.isEmpty, let name = step.componentName {
                    Text("Zutaten für „\(name)“")
                        .font(.caption.weight(.semibold))
                        .padding(.top, 6)
                    ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                        Text(line)
                            .font(.caption)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                Button(action: markDone) {
                    Label("Erledigt", systemImage: "checkmark")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .padding(.top, 10)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    /// When the step is due, and how far off that is — refreshed each minute.
    private var timing: some View {
        TimelineView(.periodic(from: .now, by: 60)) { context in
            let isDue = step.date <= context.date
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Image(systemName: isDue ? "bell.fill" : "clock")
                    Self.dayLabel(for: step.date, now: context.date)
                    Text(step.date, format: .dateTime.hour().minute())
                }
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.tint)

                let distance = Self.distanceText(from: context.date, to: step.date)
                Group {
                    if isDue {
                        Text("seit \(distance)")
                    } else {
                        Text("in \(distance)")
                    }
                }
                .font(.caption2)
                .foregroundStyle(.secondary)
            }
        }
    }

    /// "17 Min.", "2 Std., 15 Min." or "1 Tag, 3 Std." — never seconds.
    private static func distanceText(from now: Date, to date: Date) -> String {
        let seconds = max(60, abs(date.timeIntervalSince(now)).rounded(.up))
        return Duration.seconds(seconds).formatted(
            .units(allowed: [.days, .hours, .minutes], width: .abbreviated, maximumUnitCount: 2)
        )
    }

    /// "Heute", "Morgen", or the short date for anything further away.
    private static func dayLabel(for date: Date, now: Date) -> Text {
        let calendar = Calendar.current
        if calendar.isDate(date, inSameDayAs: now) {
            return Text("Heute")
        }
        if let tomorrow = calendar.date(byAdding: .day, value: 1, to: now),
           calendar.isDate(date, inSameDayAs: tomorrow) {
            return Text("Morgen")
        }
        return Text(date, format: .dateTime.day().month())
    }
}
