import BakePlannerCore
import SwiftUI

/// Shows the findings of ``BakePlanValidator`` for the plan currently set up in
/// the scheduling controls: errors (overlapping bakes) in red, hints (steps
/// outside the day window, a too short baking pause) in orange. When steps
/// fall into the night, or the bake clashes with another one for the oven,
/// the dates ``BakePlanAdvisor`` found follow, each one a tap away.
struct BakePlanIssuesView: View {

    let issues: [BakePlanIssue]
    /// Whether a step begins outside the day window.
    var hasNightSteps = false
    var suggestions: [PlanDateSuggestion] = []
    /// Whether the bake needs an oven that is taken, or follows another
    /// bake too closely — the baking-day case.
    var hasOvenConflict = false
    var ovenSuggestions: [PlanDateSuggestion] = []
    /// How the picker reads its date, which decides the wording.
    var anchor: PlanAnchor = .startsAt
    var onApply: (Date) -> Void = { _ in }
    /// How the plan fits by stretching or shortening the steps that have
    /// a time window, the date kept — offered before moving the date.
    var windowSuggestion: PlanWindowSuggestion? = nil
    var onApplyDurations: ([Int: Int]) -> Void = { _ in }

    var body: some View {
        if !issues.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(issues) { issue in
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: symbol(for: issue.severity))
                            .foregroundColor(color(for: issue.severity))
                            .accessibilityHidden(true)

                        Text(issue.message)
                            .font(Theme.bodyFont(14))
                            .foregroundColor(Theme.cardTitle)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                if let windowSuggestion {
                    windowBlock(windowSuggestion)
                }

                if hasOvenConflict {
                    suggestionBlock(
                        heading: "So werden die Backöfen nacheinander frei:",
                        nothingFound: "Innerhalb eines Tages gibt es keinen Zeitpunkt, zu dem ein Backofen für diesen Backvorgang frei ist.",
                        suggestions: ovenSuggestions
                    )
                }

                if hasNightSteps {
                    suggestionBlock(
                        heading: "So beginnt kein Schritt in der Nacht:",
                        nothingFound: "Innerhalb eines Tages gibt es keinen Zeitpunkt, zu dem alle Schritte in Deinen Tag fallen.",
                        suggestions: suggestions
                    )
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .cardStyle()
        }
    }

    @ViewBuilder
    private func suggestionBlock(heading: LocalizedStringKey, nothingFound: LocalizedStringKey,
                                 suggestions: [PlanDateSuggestion]) -> some View {
        Divider()

        if suggestions.isEmpty {
            Text(nothingFound)
                .font(Theme.bodyFont(14))
                .foregroundColor(Theme.subtitle)
                .fixedSize(horizontal: false, vertical: true)
        } else {
            Text(heading)
                .font(Theme.bodyFont(14).weight(.semibold))
                .foregroundColor(Theme.cardTitle)
                .fixedSize(horizontal: false, vertical: true)

            ForEach(suggestions) { suggestion in
                Button {
                    onApply(suggestion.date)
                } label: {
                    HStack(alignment: .center, spacing: 8) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(title(for: suggestion))
                                .font(Theme.bodyFont(14).weight(.semibold))
                                .foregroundColor(Theme.cardTitle)
                            Text(detail(for: suggestion))
                                .font(Theme.bodyFont(13))
                                .foregroundColor(Theme.subtitle)
                        }
                        .fixedSize(horizontal: false, vertical: true)

                        Spacer(minLength: 8)

                        Text("Übernehmen")
                            .font(Theme.bodyFont(14).weight(.semibold))
                            .foregroundColor(Theme.accentText)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
    }

    /// The steps the advisor would stretch or shorten, each with its new
    /// duration, and the plan's span with them; one tap applies the
    /// durations to this plan.
    @ViewBuilder
    private func windowBlock(_ suggestion: PlanWindowSuggestion) -> some View {
        Divider()

        Text("So passt es mit den Zeitfenstern der Schritte:")
            .font(Theme.bodyFont(14).weight(.semibold))
            .foregroundColor(Theme.cardTitle)
            .fixedSize(horizontal: false, vertical: true)

        Button {
            onApplyDurations(suggestion.durations)
        } label: {
            HStack(alignment: .center, spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(suggestion.changes, id: \.index) { change in
                        Text("\(change.shortInstruction): \(Rational.displayHoursMinutes(change.to)) statt \(Rational.displayHoursMinutes(change.from))")
                            .font(Theme.bodyFont(14).weight(.semibold))
                            .foregroundColor(Theme.cardTitle)
                    }
                    Text(spanText(start: suggestion.start, finish: suggestion.finish))
                        .font(Theme.bodyFont(13))
                        .foregroundColor(Theme.subtitle)
                }
                .fixedSize(horizontal: false, vertical: true)

                Spacer(minLength: 8)

                Text("Übernehmen")
                    .font(Theme.bodyFont(14).weight(.semibold))
                    .foregroundColor(Theme.accentText)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("plan.applyWindows")
    }

    /// "Fertig bis Sa., 10.10., 13:45" or "Starten ab …", as the picker reads it.
    private func title(for suggestion: PlanDateSuggestion) -> String {
        let date = dateText(suggestion.date)
        switch anchor {
        case .startsAt:   return String(localized: "Starten ab \(date)", bundle: AppSettings.localizationBundle, locale: AppSettings.locale)
        case .finishesBy: return String(localized: "Fertig bis \(date)", bundle: AppSettings.localizationBundle, locale: AppSettings.locale)
        }
    }

    /// "1 Std., 45 Min. später · Beginn Fr., 9.10., 18:05 · fertig Sa., 10.10., 13:45"
    private func detail(for suggestion: PlanDateSuggestion) -> String {
        let amount = Duration.seconds(abs(suggestion.shift) * 60)
            .formatted(.units(allowed: [.hours, .minutes], width: .abbreviated).locale(AppSettings.locale))
        let shift = suggestion.shift < 0
            ? String(localized: "\(amount) früher", bundle: AppSettings.localizationBundle, locale: AppSettings.locale)
            : String(localized: "\(amount) später", bundle: AppSettings.localizationBundle, locale: AppSettings.locale)
        return "\(shift) · \(spanText(start: suggestion.start, finish: suggestion.finish))"
    }

    /// "Beginn Fr., 9.10., 18:05 · fertig Sa., 10.10., 13:45"
    private func spanText(start: Date, finish: Date) -> String {
        String(localized: "Beginn \(dateText(start)) · fertig \(dateText(finish))",
               bundle: AppSettings.localizationBundle, locale: AppSettings.locale)
    }

    private func dateText(_ date: Date) -> String {
        date.formatted(.dateTime.weekday(.abbreviated).day().month().hour().minute().locale(AppSettings.locale))
    }

    private func symbol(for severity: BakePlanIssueSeverity) -> String {
        switch severity {
        case .error: "exclamationmark.octagon.fill"
        case .hint:  "exclamationmark.triangle.fill"
        }
    }

    private func color(for severity: BakePlanIssueSeverity) -> Color {
        switch severity {
        // System .red/.orange only reach 3.6:1 and 2.2:1 on the white card.
        case .error: Theme.danger
        case .hint:  Theme.warning
        }
    }
}

#Preview("Zeitfenster") {
    let start = Calendar.current.date(bySettingHour: 17, minute: 0, second: 0, of: Date()) ?? Date()
    let finish = Calendar.current.date(byAdding: .minute, value: 970, to: start) ?? start
    ScrollView {
        BakePlanIssuesView(
            issues: [BakePlanIssue(severity: .hint, message: "„Hauptteig kneten“ beginnt am 10.10.26, 05:00 und damit vor dem Tagesbeginn (06:00 Uhr).")],
            hasNightSteps: true,
            suggestions: [PlanDateSuggestion(date: start.addingTimeInterval(3600), shift: 60, start: start.addingTimeInterval(3600), finish: finish.addingTimeInterval(3600))],
            windowSuggestion: PlanWindowSuggestion(
                durations: [0: 780],
                changes: [PlanWindowSuggestion.Change(index: 0, instruction: "Sauerteig ansetzen und 10–14 Stunden bei Raumtemperatur reifen lassen", from: 720, to: 780)],
                start: start, finish: finish)
        )
        .padding()
    }
    .warmBackground()
}
