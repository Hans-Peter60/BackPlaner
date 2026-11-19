//
//  DishPlanView.swift
//  CookPlanner
//
//  One dish planned against the clock: the verdict and its reason, where
//  the hands' minutes go, the timeline, what wants keeping warm, and the
//  way into the cook mode.
//

import BakePlannerCore
import SwiftUI

struct DishPlanView: View {

    let dish: KitchenDish

    @AppStorage(CookSettings.budgetKey) private var budget = CookSettings.defaultBudget
    @AppStorage(CookSettings.burnersKey) private var burners = CookSettings.defaultBurners
    @AppStorage(CookSettings.ovensKey) private var ovens = CookSettings.defaultOvens
    @State private var cooking = false

    private var plan: DishPlan? {
        DishPlan(dish: dish, budget: budget, burners: burners, ovens: ovens)
    }

    /// The dish cut within its steps' windows, when the nominal plan does
    /// not fit and cutting is what helps.
    private func fit(for plan: DishPlan) -> KitchenFit? {
        guard !plan.fits, plan.schedule.limit != .hands,
              let fit = try? KitchenScheduler.fit(dish.tasks, kitchen: plan.schedule.kitchen, budget: budget),
              !fit.shortenings.isEmpty else { return nil }
        return fit
    }

    var body: some View {
        ScrollView {
            if let plan {
                VStack(alignment: .leading, spacing: 16) {
                    // The name is too long for the bar; it heads the content.
                    Text(verbatim: dish.name)
                        .font(Theme.brandFont(20))
                        .foregroundColor(Theme.title)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, 4)
                    verdictCard(plan)
                    if let fit = fit(for: plan) {
                        fitCard(fit, plan: plan)
                    }
                    handsCard(plan)
                    timelineCard(plan)
                    if !plan.schedule.waits(atLeast: 10).isEmpty {
                        keepWarmCard(plan)
                    }
                    Button {
                        cooking = true
                    } label: {
                        Label("Kochen starten", systemImage: "timer")
                            .font(Theme.bodyFont(17).weight(.semibold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 6)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(Theme.accentBottom)
                }
                .padding()
            }
        }
        .warmBackground()
        .navigationTitle("Plan")
        .navigationBarTitleDisplayMode(.inline)
        .fullScreenCover(isPresented: $cooking) {
            if let plan {
                CookModeView(plan: plan)
            }
        }
    }

    private func verdictCard(_ plan: DishPlan) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(plan.verdict)
                .font(Theme.brandFont(26))
                .foregroundColor(plan.fits ? Theme.good : Theme.danger)
            Text(plan.reason)
                .font(Theme.bodyFont(15))
                .foregroundColor(Theme.subtitle)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 16) {
                Label("\(plan.schedule.makespan) Min.", systemImage: "clock")
                Label("Kette \(plan.schedule.criticalPathMinutes) Min.", systemImage: "link")
                Label("Hände \(plan.schedule.handsMinutes) Min.", systemImage: "hand.raised")
            }
            .font(Theme.bodyFont(13))
            .foregroundColor(Theme.subtitle)
            .padding(.top, 4)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardStyle()
    }

    private func fitCard(_ fit: KitchenFit, plan: DishPlan) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("So passt es")
                .font(Theme.bodyFont(16).weight(.semibold))
                .foregroundColor(Theme.cardTitle)
            ForEach(fit.shortenings, id: \.task) { cut in
                if let task = plan.dish.tasks.first(where: { $0.id == cut.task }) {
                    Text("\(task.name): \(cut.to) statt \(cut.from) Minuten")
                        .font(Theme.bodyFont(14))
                        .foregroundColor(Theme.cardTitle)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            if fit.schedule.fits {
                Text("Mit diesen Garzeiten passt es in \(budget) Minuten")
                    .font(Theme.bodyFont(14))
                    .foregroundColor(Theme.good)
            } else {
                Text("Auch mit den kürzesten Garzeiten fehlen \(fit.schedule.shortfall) Minuten")
                    .font(Theme.bodyFont(14))
                    .foregroundColor(Theme.warning)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardStyle()
    }

    private func handsCard(_ plan: DishPlan) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Handarbeit je Komponente")
                .font(Theme.bodyFont(16).weight(.semibold))
                .foregroundColor(Theme.cardTitle)
            let total = max(1, plan.schedule.handsMinutes)
            ForEach(plan.schedule.handsByComponent, id: \.component) { entry in
                HStack {
                    Text(verbatim: entry.component)
                        .font(Theme.bodyFont(14))
                        .foregroundColor(Theme.cardTitle)
                    Spacer()
                    Text("\(entry.minutes) Min.")
                        .font(Theme.bodyFont(14))
                        .foregroundColor(Theme.subtitle)
                }
                GeometryReader { geometry in
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Theme.accent)
                        .frame(width: geometry.size.width * CGFloat(entry.minutes) / CGFloat(total))
                }
                .frame(height: 6)
                .accessibilityHidden(true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardStyle()
    }

    private func timelineCard(_ plan: DishPlan) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Zeitplan")
                .font(Theme.bodyFont(16).weight(.semibold))
                .foregroundColor(Theme.cardTitle)
            ForEach(plan.schedule.placements.sorted { ($0.start, $0.task.id) < ($1.start, $1.task.id) }) { placement in
                TimelineRow(placement: placement)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardStyle()
    }

    private func keepWarmCard(_ plan: DishPlan) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Warm halten")
                .font(Theme.bodyFont(16).weight(.semibold))
                .foregroundColor(Theme.cardTitle)
            ForEach(plan.schedule.waits(atLeast: 10), id: \.task) { wait in
                if let task = plan.dish.tasks.first(where: { $0.id == wait.task }) {
                    Text("\(task.name) wartet \(wait.minutes) Minuten")
                        .font(Theme.bodyFont(14))
                        .foregroundColor(Theme.subtitle)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardStyle()
    }
}

/// One step on the timeline: minutes, hands, station, name and component.
struct TimelineRow: View {
    let placement: KitchenPlacement

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(verbatim: "\(placement.start)–\(placement.end)")
                .font(Theme.bodyFont(13).monospacedDigit())
                .foregroundColor(Theme.subtitle)
                .frame(width: 52, alignment: .trailing)
            HStack(spacing: 4) {
                if placement.task.handsMinutes > 0 {
                    Image(systemName: "hand.raised.fill")
                        .accessibilityLabel("Hände")
                }
                if let symbol = placement.task.stationSymbol {
                    Image(systemName: symbol)
                        .accessibilityLabel(placement.task.station == .oven ? "Ofen" : "Platte")
                }
            }
            .font(.system(size: 12))
            .foregroundColor(Theme.accentText)
            .frame(width: 34, alignment: .leading)
            VStack(alignment: .leading, spacing: 1) {
                Text(verbatim: placement.task.name)
                    .font(Theme.bodyFont(14))
                    .foregroundColor(Theme.cardTitle)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 6) {
                    if !placement.task.component.isEmpty {
                        Text(verbatim: placement.task.component)
                    }
                    if let window = placement.task.unattendedWindow {
                        Text("\(window.lowerBound)–\(window.upperBound) Min.")
                    }
                }
                .font(Theme.bodyFont(12))
                .foregroundColor(Theme.subtitle)
            }
        }
    }
}
