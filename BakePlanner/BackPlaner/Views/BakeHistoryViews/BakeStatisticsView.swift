//
//  BakeStatisticsView.swift
//  BackPlaner
//
//  The fifth view of the bake history: what the entries add up to. Four
//  figures at the top, then the bakes per month, the recipes baked most,
//  the stars, the final proofs against the room temperature, and the words
//  used for crumb and oven spring. The sums come from BakeStatistics in the
//  package; this is the drawing.
//

import BakePlannerCore
import Charts
import SwiftUI

struct BakeStatisticsView: View {

    let statistics: BakeStatistics

    @Environment(\.locale) private var locale

    var body: some View {
        if statistics.isEmpty {
            ContentUnavailableView(
                "Noch kein abgeschlossenes Backen",
                systemImage: "chart.bar",
                description: Text("Die Statistik entsteht aus der Backhistorie, sobald ein geplantes Backen vorbei ist.")
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollView {
                VStack(spacing: 12) {
                    summary
                    monthsCard
                    recipesCard
                    if statistics.averageRating != nil {
                        ratingsCard
                    }
                    if statistics.finalProofs.count >= 2 {
                        proofCard
                    }
                    if !statistics.outcomes.isEmpty {
                        outcomesCard
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
            }
            .accessibilityIdentifier("history.statistics")
        }
    }

    // MARK: Figures

    private var summary: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
            tile("Brote gesamt", value: statistics.total.formatted(.number.locale(locale)))
            tile("Dieses Jahr", value: statistics.thisYear.formatted(.number.locale(locale)))
            tile("Pro Monat", value: statistics.perMonth.formatted(.number.precision(.fractionLength(1)).locale(locale)))
            if let average = statistics.averageRating {
                tile("Ø Bewertung", value: average.formatted(.number.precision(.fractionLength(1)).locale(locale)) + " ★")
            }
        }
    }

    private func tile(_ title: LocalizedStringKey, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(Theme.bodyFont(12))
                .foregroundColor(Theme.subtitle)
            Text(value)
                .font(Theme.brandFont(24))
                .foregroundColor(Theme.cardTitle)
                .monospacedDigit()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .cardStyle(cornerRadius: 14)
        .accessibilityElement(children: .combine)
    }

    private func card<Content: View>(_ title: LocalizedStringKey, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(Theme.brandFont(15))
                .foregroundColor(Theme.cardTitle)
            content()
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardStyle(cornerRadius: 14)
    }

    // The axis names the charts use; plain strings, as Charts wants them.
    private var monthLabel: String { String(localized: "Monat") }
    private var loavesLabel: String { String(localized: "Brote") }
    private var recipeLabel: String { String(localized: "Rezept") }
    private var starsLabel: String { String(localized: "Sterne") }
    private var minutesLabel: String { String(localized: "Minuten") }

    // MARK: Charts

    /// The last twelve months, a bar each; quiet months stay empty.
    private var monthsCard: some View {
        card("Brote je Monat") {
            Chart(statistics.months) { month in
                BarMark(x: .value(monthLabel, month.month, unit: .month),
                        y: .value(loavesLabel, month.count))
                    .foregroundStyle(Theme.accentTop)
                    .cornerRadius(3)
            }
            .chartXAxis {
                AxisMarks(values: .stride(by: .month)) { _ in
                    AxisValueLabel(format: .dateTime.month(.narrow).locale(locale), centered: true)
                }
            }
            .chartYAxis {
                AxisMarks(position: .leading, values: .automatic(desiredCount: 4))
            }
            .frame(height: 160)
        }
    }

    /// The seven recipes baked most, as rows: the name on its own line, the
    /// bar and the count below it. Plain rows rather than a bar chart with
    /// the names on its axis — Swift Charts laid long names across the
    /// bars once they no longer fitted beside them.
    private var recipesCard: some View {
        let top = Array(statistics.recipes.prefix(7))
        let most = max(1, top.map(\.count).max() ?? 1)
        return card("Meistgebacken") {
            VStack(alignment: .leading, spacing: 10) {
                ForEach(top) { recipe in
                    VStack(alignment: .leading, spacing: 3) {
                        Text(recipe.name)
                            .font(Theme.bodyFont(13))
                            .foregroundColor(Theme.cardTitle)
                            .lineLimit(1)
                        HStack(spacing: 8) {
                            GeometryReader { geometry in
                                RoundedRectangle(cornerRadius: 3)
                                    .fill(Theme.accentTop)
                                    .frame(width: max(6, geometry.size.width * CGFloat(recipe.count) / CGFloat(most)))
                            }
                            .frame(height: 12)
                            Text(recipe.count.formatted(.number.locale(locale)))
                                .font(Theme.bodyFont(12))
                                .foregroundColor(Theme.cardTitle)
                                .frame(minWidth: 18, alignment: .leading)
                        }
                    }
                    .accessibilityElement(children: .combine)
                }
            }
        }
    }

    /// How many bakes got how many stars.
    private var ratingsCard: some View {
        let labels = (1...BakeHistoryFacts.maximumRating).map { String(repeating: "★", count: $0) }
        return card("Bewertungen") {
            Chart(Array(1...BakeHistoryFacts.maximumRating), id: \.self) { stars in
                BarMark(x: .value(starsLabel, labels[stars - 1]),
                        y: .value(loavesLabel, statistics.ratingCounts[stars]))
                    .foregroundStyle(Theme.accentTop)
                    .cornerRadius(3)
            }
            .chartXScale(domain: labels)
            .chartYAxis {
                AxisMarks(position: .leading, values: .automatic(desiredCount: 3))
            }
            .frame(height: 140)
        }
    }

    /// Every bake with a room temperature and a measured final proof, as a
    /// point — warm kitchens to the right, long proofs at the top.
    private var proofCard: some View {
        card("Stückgare und Raumtemperatur") {
            Chart(statistics.finalProofs) { point in
                PointMark(x: .value(String(localized: "Raumtemperatur"), point.temperature),
                          y: .value(minutesLabel, point.minutes))
                    .foregroundStyle(Theme.accentTop)
                    .symbolSize(70)
            }
            .chartXAxisLabel(String(localized: "Raumtemperatur") + " °C")
            .chartYAxisLabel(String(localized: "Stückgare") + " · " + minutesLabel)
            .frame(height: 190)
            Text("Jeder Punkt ist ein Backen mit Raumtemperatur und gemessener Stückgare.")
                .font(Theme.bodyFont(12))
                .foregroundColor(Theme.subtitle)
        }
    }

    /// The crumb and oven-spring words, most frequent first.
    private var outcomesCard: some View {
        card("Krume und Ofentrieb") {
            VStack(spacing: 6) {
                ForEach(statistics.outcomes.prefix(8)) { outcome in
                    HStack {
                        Text(outcome.keyword)
                            .font(Theme.bodyFont(14))
                            .foregroundColor(Theme.cardTitle)
                        Spacer()
                        Text(verbatim: "\(outcome.count.formatted(.number.locale(locale))) ×")
                            .font(Theme.bodyFont(14))
                            .foregroundColor(Theme.subtitle)
                            .monospacedDigit()
                    }
                    .accessibilityElement(children: .combine)
                }
            }
        }
    }
}
