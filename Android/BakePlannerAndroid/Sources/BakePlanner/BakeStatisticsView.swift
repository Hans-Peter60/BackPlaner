import BakePlannerCore
import SwiftUI

/// The fifth view of the bake history: what the entries add up to. Four
/// figures at the top, then the bakes per month, the recipes baked most,
/// the stars, the final proofs against the room temperature, and the words
/// used for crumb and oven spring. The sums come from BakeStatistics in the
/// package; the drawing is plain rectangles and circles, as SkipUI has no
/// charts.
struct BakeStatisticsView: View {
    let statistics: BakeStatistics
    @Environment(\.colorScheme) var colorScheme

    var body: some View {
        if statistics.isEmpty {
            VStack(spacing: 8) {
                Text("Noch kein abgeschlossenes Backen")
                    .font(AppFont.title3)
                    .foregroundStyle(Palette.accent(colorScheme))
                Text("Die Statistik entsteht aus der Backhistorie, sobald ein geplantes Backen vorbei ist.")
                    .font(AppFont.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .padding()
        } else {
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
        }
    }

    // MARK: Figures

    private var summary: some View {
        VStack(spacing: 10) {
            HStack(spacing: 10) {
                tile("Brote gesamt", value: String(statistics.total))
                tile("Dieses Jahr", value: String(statistics.thisYear))
            }
            HStack(spacing: 10) {
                tile("Pro Monat", value: statistics.perMonth.formatted(.number.precision(.fractionLength(1)).locale(AppSettings.locale)))
                if let average = statistics.averageRating {
                    tile("Ø Bewertung", value: average.formatted(.number.precision(.fractionLength(1)).locale(AppSettings.locale)) + " ★")
                } else {
                    Spacer()
                        .frame(maxWidth: .infinity)
                }
            }
        }
    }

    private func tile(_ title: LocalizedStringKey, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(AppFont.caption)
                .foregroundStyle(Palette.subtitle(colorScheme))
            Text(verbatim: value)
                .font(AppFont.title2)
                .foregroundStyle(Palette.cardTitle(colorScheme))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardStyle()
    }

    private func card<Content: View>(_ title: LocalizedStringKey, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(AppFont.headline)
                .foregroundStyle(Palette.cardTitle(colorScheme))
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardStyle()
    }

    // MARK: Charts

    /// The last twelve months, a bar each; quiet months stay empty.
    private var monthsCard: some View {
        let most = max(1, statistics.months.map(\.count).max() ?? 1)
        let height = 120.0
        return card("Brote je Monat") {
            HStack(alignment: .bottom, spacing: 4) {
                ForEach(statistics.months, id: \.month) { month in
                    VStack(spacing: 3) {
                        if month.count > 0 {
                            Text(verbatim: String(month.count))
                                .font(AppFont.caption2)
                                .foregroundStyle(Palette.subtitle(colorScheme))
                        }
                        RoundedRectangle(cornerRadius: 3)
                            .fill(month.count > 0 ? Palette.accent(colorScheme) : Palette.card(colorScheme))
                            .frame(height: max(3, height * Double(month.count) / Double(most)))
                        Text(verbatim: BakeStatisticsText.monthLetter(month.month))
                            .font(AppFont.caption2)
                            .foregroundStyle(Palette.subtitle(colorScheme))
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            .frame(height: height + 40, alignment: .bottom)
        }
    }

    /// The seven recipes baked most, as rows: the name on its own line, the
    /// bar and the count below it.
    private var recipesCard: some View {
        let top = Array(statistics.recipes.prefix(7))
        let most = max(1, top.map(\.count).max() ?? 1)
        return card("Meistgebacken") {
            VStack(alignment: .leading, spacing: 10) {
                ForEach(top, id: \.name) { recipe in
                    VStack(alignment: .leading, spacing: 3) {
                        Text(verbatim: recipe.name)
                            .font(AppFont.subheadline)
                            .foregroundStyle(Palette.cardTitle(colorScheme))
                            .lineLimit(1)
                        HStack(spacing: 8) {
                            GeometryReader { geometry in
                                RoundedRectangle(cornerRadius: 3)
                                    .fill(Palette.accent(colorScheme))
                                    .frame(width: max(6.0, geometry.size.width * Double(recipe.count) / Double(most)))
                            }
                            .frame(height: 12)
                            Text(verbatim: String(recipe.count))
                                .font(AppFont.caption)
                                .foregroundStyle(Palette.cardTitle(colorScheme))
                                .frame(minWidth: 18, alignment: .leading)
                        }
                    }
                }
            }
        }
    }

    /// How many bakes got how many stars.
    private var ratingsCard: some View {
        let counts = statistics.ratingCounts
        let most = max(1, counts.max() ?? 1)
        let height = 100.0
        return card("Bewertungen") {
            HStack(alignment: .bottom, spacing: 8) {
                ForEach([1, 2, 3, 4, 5], id: \.self) { stars in
                    let count = stars < counts.count ? counts[stars] : 0
                    VStack(spacing: 3) {
                        if count > 0 {
                            Text(verbatim: String(count))
                                .font(AppFont.caption2)
                                .foregroundStyle(Palette.subtitle(colorScheme))
                        }
                        RoundedRectangle(cornerRadius: 3)
                            .fill(count > 0 ? Palette.accent(colorScheme) : Palette.card(colorScheme))
                            .frame(height: max(3, height * Double(count) / Double(most)))
                        Text(verbatim: String(repeating: "★", count: stars))
                            .font(AppFont.caption2)
                            .foregroundStyle(Palette.subtitle(colorScheme))
                            .lineLimit(1)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            .frame(height: height + 40, alignment: .bottom)
        }
    }

    /// Every bake with a room temperature and a measured final proof, as a
    /// point — warm kitchens to the right, long proofs at the top.
    private var proofCard: some View {
        let points = statistics.finalProofs
        let minimumTemperature = points.map(\.temperature).min() ?? 0
        let maximumTemperature = points.map(\.temperature).max() ?? 1
        let minimumMinutes = points.map(\.minutes).min() ?? 0
        let maximumMinutes = points.map(\.minutes).max() ?? 1
        let temperatureSpan = max(1, maximumTemperature - minimumTemperature)
        let minutesSpan = max(1, maximumMinutes - minimumMinutes)
        let height = 160.0
        return card("Stückgare und Raumtemperatur") {
            GeometryReader { geometry in
                ZStack(alignment: .topLeading) {
                    Rectangle()
                        .fill(Palette.card(colorScheme))
                    ForEach(points, id: \.id) { point in
                        let x = 8 + (geometry.size.width - 16) * (point.temperature - minimumTemperature) / temperatureSpan
                        let y = height - 8 - (height - 16) * Double(point.minutes - minimumMinutes) / Double(minutesSpan)
                        Circle()
                            .fill(Palette.accent(colorScheme))
                            .frame(width: 10, height: 10)
                            .position(x: x, y: y)
                    }
                }
            }
            .frame(height: height)
            HStack {
                Text(verbatim: BakeStatisticsText.temperature(minimumTemperature))
                Spacer()
                Text(verbatim: String(localized: "Raumtemperatur", bundle: .module) + " °C")
                Spacer()
                Text(verbatim: BakeStatisticsText.temperature(maximumTemperature))
            }
            .font(AppFont.caption2)
            .foregroundStyle(Palette.subtitle(colorScheme))
            Text(verbatim: String(localized: "Stückgare", bundle: .module) + " · " + String(localized: "Minuten", bundle: .module)
                 + ": \(minimumMinutes) – \(maximumMinutes)")
                .font(AppFont.caption2)
                .foregroundStyle(Palette.subtitle(colorScheme))
            Text("Jeder Punkt ist ein Backen mit Raumtemperatur und gemessener Stückgare.")
                .font(AppFont.caption)
                .foregroundStyle(Palette.subtitle(colorScheme))
        }
    }

    /// The crumb and oven-spring words, most frequent first.
    private var outcomesCard: some View {
        card("Krume und Ofentrieb") {
            VStack(spacing: 6) {
                ForEach(Array(statistics.outcomes.prefix(8)), id: \.keyword) { outcome in
                    HStack {
                        Text(verbatim: outcome.keyword)
                            .font(AppFont.body)
                            .foregroundStyle(Palette.cardTitle(colorScheme))
                        Spacer()
                        Text(verbatim: "\(outcome.count) ×")
                            .font(AppFont.body)
                            .foregroundStyle(Palette.subtitle(colorScheme))
                    }
                }
            }
        }
    }
}

enum BakeStatisticsText {
    /// The month's first letter, as the iPhone's chart axis shows it.
    static func monthLetter(_ month: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = AppSettings.locale
        formatter.setLocalizedDateFormatFromTemplate("MMMMM")
        return formatter.string(from: month)
    }

    static func temperature(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(0...1)).locale(AppSettings.locale)) + " °C"
    }
}
