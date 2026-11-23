//
//  StarterChartView.swift
//  BackPlaner
//
//  The starter's diagram, from the "+ Fütterung" tab of a starter recipe:
//  the ripening curve over the room temperature with the diary's feedings
//  beside it, the feeding under way with its predicted peak and a
//  reminder for it, the feedings over time brought to one temperature,
//  the rhythm, and the diary as CSV. A BakePlanner Pro feature.
//

import BakePlannerCore
import Charts
import CoreData
import SwiftUI
import UniformTypeIdentifiers
import UserNotifications

struct StarterChartView: View {

    let recipeId: NSManagedObjectID

    @Environment(\.managedObjectContext) private var viewContext
    @EnvironmentObject var model: RecipeModel

    @State private var recipeName = ""
    @State private var feedings: [StarterDiagram.Feeding] = []
    @State private var nextFeeding: Date?
    /// Today's room temperature for the prediction; starts at the last
    /// one noted in the diary.
    @State private var todayTemperature = 22
    /// When the reminder for the feeding under way was set for.
    @State private var reminderSetFor: Date?
    @State private var reminderDenied = false

    private let locale = AppSettings.locale

    private var estimate: StarterRipeness.Estimate? {
        StarterRipeness.estimate(from: StarterDiagram.observations(feedings), at: Double(todayTemperature))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if let estimate {
                    curveCard(estimate)
                    progressCard(estimate)
                    trendCard(q10: estimate.q10)
                } else {
                    card("Reifekurve") {
                        Text("Trage bei Deinen Fütterungen Reifezeit und Raumtemperatur ein, dann zeichnet die App die Reifekurve Deines Anstellguts und sagt voraus, wann es reif ist.")
                            .font(Theme.bodyFont(14))
                            .foregroundColor(Theme.subtitle)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                rhythmCard
            }
            .padding()
        }
        .warmBackground()
        .navigationTitle("Anstellgut-Diagramm")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                FileShareLink(item: StarterDiaryCSVExport(name: recipeName, feedings: feedings),
                              preview: SharePreview(recipeName, image: Image(systemName: "tablecells"))) {
                    Label("Tagebuch als CSV teilen", systemImage: "square.and.arrow.up")
                }
                .disabled(feedings.isEmpty)
                .accessibilityIdentifier("starterChart.share")
            }
        }
        .onAppear(perform: load)
    }

    // MARK: Cards

    private func card<Content: View>(_ title: LocalizedStringKey, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(Theme.brandFont(17))
                .foregroundColor(Theme.title)
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardStyle()
    }

    private var hoursLabel: String { String(localized: "Stunden") }
    private var temperatureLabel: String { String(localized: "Raumtemperatur") }

    /// The model's curve over the temperature, the measured feedings as
    /// points, today's temperature as a line with the prediction on it.
    private func curveCard(_ estimate: StarterRipeness.Estimate) -> some View {
        let curve = StarterDiagram.curve(for: estimate)
        let points = StarterDiagram.observations(feedings)
        return card("Reifekurve") {
            Chart {
                ForEach(curve) { point in
                    LineMark(x: .value(temperatureLabel, point.temperature),
                             y: .value(hoursLabel, Double(point.minutes) / 60))
                        .foregroundStyle(Theme.accentTop)
                        .interpolationMethod(.catmullRom)
                }
                ForEach(Array(points.enumerated()), id: \.offset) { _, observation in
                    PointMark(x: .value(temperatureLabel, observation.temperature),
                              y: .value(hoursLabel, Double(observation.peakMinutes) / 60))
                        .foregroundStyle(Theme.subtitle)
                        .symbolSize(60)
                }
                RuleMark(x: .value(temperatureLabel, Double(todayTemperature)))
                    .foregroundStyle(Theme.warning.opacity(0.7))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))
                    .annotation(position: .top, alignment: .center, spacing: 4,
                                overflowResolution: .init(x: .fit(to: .plot), y: .disabled)) {
                        Text(BakeHistoryFacts.durationText(estimate.minutes))
                            .font(Theme.bodyFont(12))
                            .foregroundColor(Theme.warning)
                    }
            }
            .chartXScale(domain: curveDomain)
            .chartXAxisLabel(temperatureLabel + " °C")
            .chartYAxisLabel(String(localized: "Reifezeit") + " · " + hoursLabel)
            .chartYAxis { AxisMarks(position: .leading, values: .automatic(desiredCount: 5)) }
            .frame(height: 210)
            .accessibilityLabel(Text("Reifekurve"))
            .accessibilityValue(Text("Bei \(BakeHistoryFacts.temperatureText(Double(todayTemperature), locale: locale)) reif nach etwa \(BakeHistoryFacts.durationText(estimate.minutes))"))

            Text("Bei \(BakeHistoryFacts.temperatureText(Double(todayTemperature), locale: locale)) reif nach etwa \(BakeHistoryFacts.durationText(estimate.minutes))")
                .font(Theme.bodyFont(16))
                .foregroundColor(Theme.cardTitle)
                .fixedSize(horizontal: false, vertical: true)
            Stepper(value: $todayTemperature, in: 10...35) {
                LabeledContent("Raumtemperatur heute", value: "\(todayTemperature) °C")
                    .font(Theme.bodyFont(15))
            }
            Text(modelNote(estimate))
                .font(Theme.bodyFont(12))
                .foregroundColor(Theme.subtitle)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var curveDomain: ClosedRange<Double> {
        let low = min(StarterDiagram.curveTemperatures.first ?? 15, Double(todayTemperature))
        let high = max(StarterDiagram.curveTemperatures.last ?? 32, Double(todayTemperature))
        return low...high
    }

    private func trendDomain(_ trend: [StarterDiagram.TrendPoint]) -> ClosedRange<Date> {
        let first = (trend.first?.date ?? Date()).addingTimeInterval(-12 * 3600)
        let last = (trend.last?.date ?? Date()).addingTimeInterval(12 * 3600)
        return first...last
    }

    /// "Faktor 2,8 je 10 °C aus 6 Fütterungen", or the default's wording.
    private func modelNote(_ estimate: StarterRipeness.Estimate) -> String {
        let factor = estimate.q10.formatted(.number.precision(.fractionLength(1)).locale(locale))
        let feedings = String(localized: "aus \(estimate.observations) Fütterungen")
        if estimate.fitted {
            return String(localized: "Linie: Reifezeit nach dem Tagebuch, Faktor \(factor) je 10 °C, \(feedings). Punkte: gemessene Fütterungen.")
        }
        return String(localized: "Linie: Reifezeit mit dem üblichen Faktor \(factor) je 10 °C, \(feedings). Ab drei Fütterungen über 4 °C Spanne lernt die App den Faktor Deines Anstellguts. Punkte: gemessene Fütterungen.")
    }

    /// The feeding without a result yet: how far along it is, when the
    /// peak is expected, and a reminder for it. Predicted at the
    /// temperature noted with that feeding when there is one, so the
    /// stepper above does not move a feeding that is already running.
    @ViewBuilder
    private func progressCard(_ estimate: StarterRipeness.Estimate) -> some View {
        if let feeding = StarterDiagram.underWay(feedings, now: Date()) {
            let temperature = feeding.facts.roomTemperature ?? Double(todayTemperature)
            let own = StarterRipeness.estimate(from: StarterDiagram.observations(feedings), at: temperature) ?? estimate
            let progress = StarterDiagram.Progress(fedAt: feeding.date, readyAt: own.readyDate(fedAt: feeding.date))
            card("Laufende Fütterung") {
                TimelineView(.periodic(from: .now, by: 60)) { context in
                    VStack(alignment: .leading, spacing: 8) {
                        ProgressView(value: min(1, progress.fraction(at: context.date)))
                            .tint(progress.isRipe(at: context.date) ? Theme.warning : Theme.accentTop)
                        if progress.isRipe(at: context.date) {
                            Text("Gefüttert \(dayTime(progress.fedAt)) – vermutlich seit \(dayTime(progress.readyAt)) am Höhepunkt. Trage das Ergebnis im Tagebuch ein.")
                        } else {
                            Text("Gefüttert \(dayTime(progress.fedAt)) – reif gegen \(dayTime(progress.readyAt)) bei \(BakeHistoryFacts.temperatureText(temperature, locale: locale)).")
                        }
                    }
                    .font(Theme.bodyFont(15))
                    .foregroundColor(Theme.cardTitle)
                    .fixedSize(horizontal: false, vertical: true)
                }
                if !progress.isRipe(at: Date()) {
                    if let reminderSetFor {
                        Label("Erinnerung \(dayTime(reminderSetFor)) gesetzt.", systemImage: "bell.fill")
                            .font(Theme.bodyFont(14))
                            .foregroundColor(Theme.subtitle)
                    } else if reminderDenied {
                        Label("Mitteilungen sind für BakePlanner nicht erlaubt.", systemImage: "bell.slash")
                            .font(Theme.bodyFont(14))
                            .foregroundColor(Theme.subtitle)
                    } else {
                        Button {
                            scheduleRipeReminder(progress)
                        } label: {
                            Label("Erinnern, wenn reif", systemImage: "bell")
                        }
                        .buttonStyle(.bordered)
                        .tint(Theme.accentText)
                        .accessibilityIdentifier("starterChart.remind")
                    }
                }
            }
        }
    }

    /// The feedings over time: the measured peak as points, the peak as it
    /// would have run at 22 °C as a line — the starter's form regardless of
    /// the kitchen's weather.
    @ViewBuilder
    private func trendCard(q10: Double) -> some View {
        let trend = StarterDiagram.trend(feedings, q10: q10)
        if trend.count >= 2 {
            card("Verlauf") {
                Chart {
                    ForEach(trend) { point in
                        LineMark(x: .value(String(localized: "Datum"), point.date),
                                 y: .value(hoursLabel, Double(point.atReferenceMinutes) / 60))
                            .foregroundStyle(Theme.accentTop)
                        PointMark(x: .value(String(localized: "Datum"), point.date),
                                  y: .value(hoursLabel, Double(point.peakMinutes) / 60))
                            .foregroundStyle(point.floatTestPassed == false ? Theme.warning : Theme.subtitle)
                            .symbol(point.floatTestPassed == false ? .cross : .circle)
                            .symbolSize(50)
                    }
                }
                // A tick per feeding while they are few; the plot keeps half
                // a day of air on both sides so the first and last points do
                // not sit on the axes.
                .chartXAxis {
                    if trend.count <= 6 {
                        AxisMarks(values: trend.map(\.date)) { _ in
                            AxisGridLine()
                            AxisValueLabel(format: .dateTime.day().month(.abbreviated).locale(locale), collisionResolution: .greedy)
                        }
                    } else {
                        AxisMarks(values: .automatic(desiredCount: 4)) { _ in
                            AxisGridLine()
                            AxisValueLabel(format: .dateTime.day().month(.abbreviated).locale(locale))
                        }
                    }
                }
                .chartXScale(domain: trendDomain(trend))
                .chartYAxisLabel(String(localized: "Reifezeit") + " · " + hoursLabel)
                .chartYAxis { AxisMarks(position: .leading, values: .automatic(desiredCount: 5)) }
                .frame(height: 190)
                .accessibilityLabel(Text("Verlauf"))
                Text("Linie: Reifezeit umgerechnet auf 22 °C – steigt sie, wird das Anstellgut träger. Punkte: wie gemessen; ein Kreuz ist eine Fütterung, bei der der Schwimmtest misslang.")
                    .font(Theme.bodyFont(12))
                    .foregroundColor(Theme.subtitle)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var rhythmCard: some View {
        let rhythm = StarterDiagram.rhythm(feedings, now: Date())
        return card("Rhythmus") {
            VStack(alignment: .leading, spacing: 6) {
                LabeledContent("Fütterungen in 30 Tagen", value: rhythm.lastMonthCount.formatted(.number.locale(locale)))
                if let interval = rhythm.averageIntervalDays {
                    LabeledContent("Mittlerer Abstand", value: String(localized: "\(interval.formatted(.number.precision(.fractionLength(1)).locale(locale))) Tage"))
                }
                if let days = rhythm.daysSinceLast {
                    LabeledContent("Letzte Fütterung", value: days == 0 ? String(localized: "heute") : String(localized: "vor \(days) Tagen"))
                }
                if let nextFeeding {
                    LabeledContent("Nächste Fütterung", value: nextFeeding.formatted(Date.FormatStyle(date: .abbreviated, time: .shortened).locale(locale)))
                }
            }
            .font(Theme.bodyFont(15))
            .foregroundColor(Theme.cardTitle)
        }
    }

    // MARK: Helpers

    /// "heute 15:40", "morgen 08:10", else the short date with the time.
    private func dayTime(_ date: Date) -> String {
        let calendar = Calendar.current
        let time = date.formatted(Date.FormatStyle(date: .omitted, time: .shortened).locale(locale))
        if calendar.isDateInToday(date) { return String(localized: "heute \(time)") }
        if calendar.isDateInTomorrow(date) { return String(localized: "morgen \(time)") }
        if calendar.isDateInYesterday(date) { return String(localized: "gestern \(time)") }
        return date.formatted(Date.FormatStyle(date: .numeric, time: .shortened).locale(locale))
    }

    private func load() {
        guard let recipe = model.fetchRecipe(for: recipeId, context: viewContext) else { return }
        recipeName = recipe.name
        feedings = recipe.starterFeedingLogsArray.map { StarterDiagram.Feeding(date: $0.date, facts: $0.facts) }
        nextFeeding = RecurringBakePlanner.nextStart(for: recipe)
        if let lastNoted = recipe.starterFeedingLogsArray.compactMap(\.facts.roomTemperature).first {
            todayTemperature = Int(lastNoted.rounded())
        }
    }

    /// One notification at the predicted peak; the identifier is stable
    /// per recipe, so a second tap replaces the first reminder.
    private func scheduleRipeReminder(_ progress: StarterDiagram.Progress) {
        let center = UNUserNotificationCenter.current()
        let name = recipeName
        let fedAt = dayTime(progress.fedAt)
        Task {
            let granted = (try? await center.requestAuthorization(options: [.alert, .sound])) ?? false
            guard granted else {
                reminderDenied = true
                return
            }
            let content = UNMutableNotificationContent()
            content.title = String(localized: "Anstellgut reif", locale: locale)
            content.body = String(localized: "„\(name)“ ist vermutlich am Höhepunkt – gefüttert \(fedAt).", locale: locale)
            content.sound = .default
            let components = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: progress.readyAt)
            let request = UNNotificationRequest(identifier: "starter-ripe-\(recipeId.uriRepresentation().absoluteString)",
                                                content: content,
                                                trigger: UNCalendarNotificationTrigger(dateMatching: components, repeats: false))
            try? await center.add(request)
            reminderSetFor = progress.readyAt
        }
    }
}

/// The diary as a CSV file for the share sheet.
struct StarterDiaryCSVExport: FileExport {
    let name: String
    let feedings: [StarterDiagram.Feeding]

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(exportedContentType: .commaSeparatedText) { export in
            SentTransferredFile(try export.writeFile())
        }
        .suggestedFileName { "\(RecipePDFRenderer.fileName(for: $0.name)).csv" }
    }

    func writeFile() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(RecipePDFRenderer.fileName(for: name))
            .appendingPathExtension("csv")
        try StarterDiagram.csv(feedings).write(to: url, atomically: true, encoding: .utf8)
        return url
    }
}
