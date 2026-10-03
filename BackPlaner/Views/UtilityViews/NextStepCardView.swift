//
//  NextStepCardView.swift
//  BackPlaner
//
//  The "Als Nächstes" card at the top of the main menu: the one planned step
//  that matters right now, with a live countdown, one tap away from the full
//  plan. Whoever is in the middle of a bake sees the essential thing first;
//  without a plan the card stays away and the menu looks as before.
//

import SwiftUI
import CoreData

struct NextStepCardView: View {

    /// Every planned step, earliest first. Fetched here rather than handed in
    /// so the card keeps itself current when steps are added, shifted, marked
    /// done or deleted anywhere in the app.
    @FetchRequest(sortDescriptors: [NSSortDescriptor(key: "date", ascending: true)])
    private var steps: FetchedResults<NextStep>

    // At the accessibility text sizes the eyebrow and the countdown no
    // longer fit on one line, so they stack.
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    /// How long a step counts as "just due" before the card lets go of it. A
    /// step that is not marked done stays in the plan forever, so without this
    /// an old, finished plan would keep its last step pinned to the menu.
    private static let dueGracePeriod: TimeInterval = 60 * 60

    var body: some View {
        // Re-evaluated every minute: the fetch result does not change when
        // time merely passes, but which step is "next" does.
        TimelineView(.periodic(from: .now, by: 60)) { context in
            if let step = nextStep(at: context.date) {
                NavigationLink {
                    ScheduledTasksTabsView()
                } label: {
                    card(for: step, now: context.date)
                }
                .buttonStyle(.plain)
            }
        }
    }

    /// The step to show. A step that became due within the last hour and is
    /// not marked done yet comes first — when the reminder fires, that is the
    /// thing to do now, not the one after it. Otherwise the earliest step
    /// still ahead. A newer due step always supersedes an older one.
    private func nextStep(at now: Date) -> NextStep? {
        if let due = steps.last(where: { $0.date <= now }),
           now.timeIntervalSince(due.date) < Self.dueGracePeriod {
            return due
        }
        return steps.first(where: { $0.date > now })
    }

    /// Never seconds, which `Text(_:style: .relative)` would tick off one by
    /// one under an hour and make the card restless.
    private func distanceText(from now: Date, to date: Date) -> String {
        StepTiming.distanceText(from: now, to: date)
    }

    private func card(for step: NextStep, now: Date) -> some View {
        let isDue = step.date <= now

        return HStack(alignment: .top, spacing: 14) {

            // The badge grows with the text like every other badge in the
            // menu, but only up to the extra-large size: at the
            // accessibility sizes it reached 121 pt and left the text a
            // 161 pt column, which made the card taller than the screen.
            // It is decorative, so capping it costs nothing.
            IconBadge(systemImage: isDue ? "bell.fill" : "timer")
                .dynamicTypeSize(...DynamicTypeSize.xLarge)

            VStack(alignment: .leading, spacing: 6) {

                let eyebrowLayout = dynamicTypeSize.isAccessibilitySize
                    ? AnyLayout(VStackLayout(alignment: .leading, spacing: 2))
                    : AnyLayout(HStackLayout(alignment: .firstTextBaseline))

                eyebrowLayout {
                    Text(isDue ? "Jetzt fällig" : "Als Nächstes")
                        .font(.caption.weight(.semibold))
                        .textCase(.uppercase)
                        .foregroundColor(Theme.accentText)

                    if !dynamicTypeSize.isAccessibilitySize {
                        Spacer(minLength: 8)
                    }

                    // Countdown in minutes; the surrounding TimelineView
                    // refreshes it once a minute.
                    Group {
                        if isDue {
                            Text("seit \(distanceText(from: now, to: step.date))")
                        } else {
                            Text("in \(distanceText(from: now, to: step.date))")
                        }
                    }
                    .font(.caption.weight(.semibold))
                    .foregroundColor(Theme.accentText)
                    .fixedSize(horizontal: false, vertical: true)
                }

                // Two lines keep the card compact. At the accessibility
                // sizes two lines hold about four words, which left "Den
                // Teigling…" and cut the time off the recipe line, so there
                // the text may run as long as it needs.
                Text(step.instruction)
                    .font(.headline)
                    .foregroundColor(Theme.cardTitle)
                    .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 2)
                    .fixedSize(horizontal: false, vertical: true)

                // One running text, so a long recipe name wraps onto a second
                // line instead of being cut off next to the time. Non-breaking
                // spaces keep "· Heute 10:57" together when it wraps.
                (Text(step.recipeName)
                    + Text(verbatim: " ·\u{00A0}")
                    + dayLabel(for: step.date, now: now)
                    + Text(verbatim: "\u{00A0}")
                    + Text(step.date, format: .dateTime.hour().minute()))
                    .font(.caption)
                    .foregroundColor(Theme.subtitle)
                    .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Image(systemName: "chevron.right")
                .font(.subheadline.weight(.semibold))
                .foregroundColor(Theme.subtitle)
                .accessibilityHidden(true)
        }
        .cardStyle()
        .accessibilityElement(children: .combine)
        .accessibilityHint("Öffnet die geplanten Schritte")
    }

    private func dayLabel(for date: Date, now: Date) -> Text {
        StepTiming.dayLabel(for: date, now: now)
    }
}
