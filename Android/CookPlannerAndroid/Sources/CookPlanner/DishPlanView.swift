import BakePlannerCore
import SwiftUI

/// A dish's plan: the verdict with its reason and figures, the components
/// with their hands-on time, and the steps in the order they come.
struct DishPlanView: View {
    let library: CookLibrary
    let dishID: String
    @Environment(\.colorScheme) var colorScheme

    var body: some View {
        ZStack {
            WarmBackground().ignoresSafeArea()
            if let dish = library.dish(id: dishID) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        Text(dish.name)
                            .font(.title2)
                            .fontWeight(.bold)
                            .foregroundStyle(Palette.title(colorScheme))
                        if let plan = library.plan(for: dish) {
                            verdictCard(plan)
                            componentsCard(plan)
                            stepsCard(plan)
                        } else {
                            Text(library.failure(for: dish) ?? "")
                                .foregroundStyle(Palette.danger(colorScheme))
                                .cardStyle()
                        }
                    }
                    .padding(16)
                }
            }
        }
        .navigationTitle(String(localized: "Plan", bundle: .module))
    }

    private func verdictCard(_ plan: DishPlan) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(plan.verdict)
                .font(.title2)
                .fontWeight(.bold)
                .foregroundStyle(plan.fits ? Palette.good(colorScheme) : Palette.danger(colorScheme))
            Text(plan.reason)
                .font(.subheadline)
                .foregroundStyle(Palette.subtitle(colorScheme))
            HStack(spacing: 14) {
                Text(String(localized: "\(plan.schedule.makespan) Min.", bundle: .module))
                Text(String(localized: "Kette \(plan.schedule.criticalPathMinutes) Min.", bundle: .module))
                Text(String(localized: "Hände \(plan.schedule.handsMinutes) Min.", bundle: .module))
            }
            .font(.caption)
            .foregroundStyle(Palette.subtitle(colorScheme))
        }
        .cardStyle()
    }

    /// The hands-on minutes of each component, longest first.
    private func componentsCard(_ plan: DishPlan) -> some View {
        let rows = plan.schedule.handsByComponent.map { ComponentHands(component: $0.component, minutes: $0.minutes) }
        let longest = max(1, rows.first?.minutes ?? 1)
        return VStack(alignment: .leading, spacing: 10) {
            Text(String(localized: "Handarbeit je Komponente", bundle: .module))
                .font(.headline)
            ForEach(rows) { row in
                ComponentHandsRow(row: row, longest: longest)
            }
        }
        .cardStyle()
    }

    /// Every step at its minute, in the order of the plan.
    private func stepsCard(_ plan: DishPlan) -> some View {
        let placements = plan.schedule.placements.sorted { ($0.start, $0.end) < ($1.start, $1.end) }
        return VStack(alignment: .leading, spacing: 10) {
            Text(String(localized: "Ablauf", bundle: .module))
                .font(.headline)
            ForEach(placements, id: \.id) { placement in
                HStack(alignment: .top, spacing: 10) {
                    Text(verbatim: "\(placement.start)–\(placement.end)")
                        .font(.caption)
                        .foregroundStyle(Palette.accentText(colorScheme))
                        .frame(width: 56, alignment: .leading)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(placement.task.name)
                            .font(.subheadline)
                        Text(stepDetail(placement))
                            .font(.caption)
                            .foregroundStyle(Palette.subtitle(colorScheme))
                    }
                }
            }
        }
        .cardStyle()
    }

    /// "Wirsing · Herd · 3 Min. Hände" – where and how long the hands work.
    private func stepDetail(_ placement: KitchenPlacement) -> String {
        var parts = [placement.task.component]
        switch placement.task.station {
        case .burner: parts.append(String(localized: "Herd", bundle: .module))
        case .oven: parts.append(String(localized: "Ofen", bundle: .module))
        case nil: break
        }
        if placement.task.handsMinutes > 0 {
            parts.append(String(localized: "\(placement.task.handsMinutes) Min. Hände", bundle: .module))
        }
        return parts.filter { !$0.isEmpty }.joined(separator: " · ")
    }
}

/// One component's hands-on minutes, for the bar chart of the plan.
struct ComponentHands: Identifiable {
    let component: String
    let minutes: Int
    var id: String { component }
}

struct ComponentHandsRow: View {
    let row: ComponentHands
    let longest: Int
    @Environment(\.colorScheme) var colorScheme

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(row.component.isEmpty ? String(localized: "Ohne Komponente", bundle: .module) : row.component)
                Spacer()
                Text(String(localized: "\(row.minutes) Min.", bundle: .module))
                    .foregroundStyle(Palette.subtitle(colorScheme))
            }
            .font(.subheadline)
            GeometryReader { proxy in
                Capsule()
                    .fill(Palette.accent(colorScheme))
                    .frame(width: proxy.size.width * Double(row.minutes) / Double(longest), height: 6)
            }
            .frame(height: 6)
        }
    }
}
