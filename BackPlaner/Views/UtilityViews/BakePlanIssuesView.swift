import SwiftUI

/// Shows the findings of ``BakePlanValidator`` for the plan currently set up in
/// the scheduling controls: errors (overlapping bakes) in red, hints (steps
/// outside the day window, a too short baking pause) in orange.
struct BakePlanIssuesView: View {

    let issues: [BakePlanIssue]

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
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .cardStyle()
        }
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
