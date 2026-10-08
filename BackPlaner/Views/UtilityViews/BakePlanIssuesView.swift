import SwiftUI

/// Shows the findings of ``BakePlanValidator`` for the plan currently set up in
/// the scheduling controls: errors (overlapping bakes) in red, hints (steps
/// outside the day window, a too short baking pause) in orange. When steps
/// fall into the night, the dates ``BakePlanAdvisor`` found follow, each one
/// a tap away.
struct BakePlanIssuesView: View {

    let issues: [BakePlanIssue]
    /// Whether a step begins outside the day window.
    var hasNightSteps = false
    var suggestions: [NightFreeDate] = []
    /// How the picker reads its date, which decides the wording.
    var anchor: PlanAnchor = .startsAt
    var onApply: (Date) -> Void = { _ in }

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

                if hasNightSteps {
                    nightFreeDates
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .cardStyle()
        }
    }

    @ViewBuilder
    private var nightFreeDates: some View {
        Divider()

        if suggestions.isEmpty {
            Text("Innerhalb eines Tages gibt es keinen Zeitpunkt, zu dem alle Schritte in Deinen Tag fallen.")
                .font(Theme.bodyFont(14))
                .foregroundColor(Theme.subtitle)
                .fixedSize(horizontal: false, vertical: true)
        } else {
            Text("So beginnt kein Schritt in der Nacht:")
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

    /// "Fertig bis Sa., 10.10., 13:45" or "Starten ab …", as the picker reads it.
    private func title(for suggestion: NightFreeDate) -> String {
        let date = dateText(suggestion.date)
        switch anchor {
        case .startsAt:   return String(localized: "Starten ab \(date)", bundle: AppSettings.localizationBundle, locale: AppSettings.locale)
        case .finishesBy: return String(localized: "Fertig bis \(date)", bundle: AppSettings.localizationBundle, locale: AppSettings.locale)
        }
    }

    /// "1 Std., 45 Min. später · Beginn Fr., 9.10., 18:05 · fertig Sa., 10.10., 13:45"
    private func detail(for suggestion: NightFreeDate) -> String {
        let amount = Duration.seconds(abs(suggestion.shift) * 60)
            .formatted(.units(allowed: [.hours, .minutes], width: .abbreviated).locale(AppSettings.locale))
        let shift = suggestion.shift < 0
            ? String(localized: "\(amount) früher", bundle: AppSettings.localizationBundle, locale: AppSettings.locale)
            : String(localized: "\(amount) später", bundle: AppSettings.localizationBundle, locale: AppSettings.locale)
        let span = String(localized: "Beginn \(dateText(suggestion.start)) · fertig \(dateText(suggestion.finish))",
                          bundle: AppSettings.localizationBundle, locale: AppSettings.locale)
        return "\(shift) · \(span)"
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
