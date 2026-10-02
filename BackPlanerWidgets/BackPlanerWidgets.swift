//
//  BackPlanerWidgets.swift
//  BackPlanerWidgets
//
//  The home-screen and lock-screen widget: the planned step that matters
//  right now, read from the plan snapshot the app writes into the App Group.
//
//  The timeline has an entry for every moment the shown step can change —
//  each step's start and the end of its "due" hour — so the widget stays
//  right without the app running. The app reloads the timeline whenever the
//  plan itself changes.
//

import WidgetKit
import SwiftUI

// MARK: - Timeline

struct NextStepEntry: TimelineEntry {
    let date: Date
    let step: PlanSnapshot.Step?
    let isDue: Bool

    static let placeholder = NextStepEntry(
        date: .now,
        step: PlanSnapshot.Step(
            id: "placeholder",
            recipeName: "Sauerteigbrot",
            instruction: "Hauptteig herstellen",
            date: .now.addingTimeInterval(42 * 60),
            duration: 15
        ),
        isDue: false
    )
}

struct NextStepProvider: TimelineProvider {

    func placeholder(in context: Context) -> NextStepEntry {
        .placeholder
    }

    func getSnapshot(in context: Context, completion: @escaping (NextStepEntry) -> Void) {
        if context.isPreview {
            completion(.placeholder)
        } else {
            completion(entry(at: .now, from: PlanSnapshot.load() ?? .empty))
        }
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<NextStepEntry>) -> Void) {
        let snapshot = PlanSnapshot.load() ?? .empty
        let now = Date()

        var entries = [entry(at: now, from: snapshot)]
        for date in snapshot.changeDates(after: now).prefix(80) {
            entries.append(entry(at: date, from: snapshot))
        }

        // Every change the plan can bring on its own is in the entries; a
        // changed plan reloads the timeline from the app.
        completion(Timeline(entries: entries, policy: .never))
    }

    private func entry(at date: Date, from snapshot: PlanSnapshot) -> NextStepEntry {
        if let current = snapshot.currentStep(at: date) {
            return NextStepEntry(date: date, step: current.step, isDue: current.isDue)
        }
        return NextStepEntry(date: date, step: nil, isDue: false)
    }
}

// MARK: - Look

/// The app's warm palette, repeated here because the widget cannot share the
/// app's Theme file (it drags in app-only types).
enum WidgetTheme {
    static let backgroundTop    = Color(light: Color(red: 0.98, green: 0.93, blue: 0.82), dark: Color(red: 0.16, green: 0.12, blue: 0.09))
    static let backgroundBottom = Color(light: Color(red: 0.93, green: 0.80, blue: 0.62), dark: Color(red: 0.09, green: 0.07, blue: 0.05))
    static let title            = Color(light: Color(red: 0.25, green: 0.15, blue: 0.06), dark: Color(red: 0.97, green: 0.92, blue: 0.84))
    static let subtitle         = Color(light: Color(red: 0.45, green: 0.30, blue: 0.16), dark: Color(red: 0.82, green: 0.72, blue: 0.60))
    static let accent           = Color(light: Color(red: 0.58, green: 0.355, blue: 0.16), dark: Color(red: 0.89, green: 0.575, blue: 0.31))

    static var background: LinearGradient {
        LinearGradient(colors: [backgroundTop, backgroundBottom], startPoint: .top, endPoint: .bottom)
    }
}

private extension Color {
    init(light: Color, dark: Color) {
        self.init(uiColor: UIColor { traits in
            traits.userInterfaceStyle == .dark ? UIColor(dark) : UIColor(light)
        })
    }
}

// MARK: - Views

struct NextStepWidgetView: View {

    @Environment(\.widgetFamily) private var family

    let entry: NextStepEntry

    var body: some View {
        Group {
            if let step = entry.step {
                switch family {
                case .systemMedium:         mediumView(step)
                case .accessoryRectangular: rectangularView(step)
                case .accessoryInline:      inlineView(step)
                default:                    smallView(step)
                }
            } else {
                emptyView
            }
        }
        .widgetURL(PlanSnapshot.scheduledStepsURL)
        .containerBackground(for: .widget) {
            if family.isAccessory {
                AccessoryWidgetBackground()
            } else {
                WidgetTheme.background
            }
        }
    }

    // MARK: Pieces

    private var eyebrow: some View {
        Text(entry.isDue ? "Jetzt fällig" : "Als Nächstes")
            .font(.caption2.weight(.semibold))
            .textCase(.uppercase)
            .foregroundStyle(WidgetTheme.accent)
    }

    /// "in 41:59" / "seit 5:12". A running timer, which WidgetKit keeps
    /// current without timeline entries. The `.relative` style would spell
    /// out "41 min, 59 secs" and change wording every second.
    private func countdown(for step: PlanSnapshot.Step) -> Text {
        entry.isDue
            ? Text("seit \(Text(step.date, style: .timer))")
            : Text("in \(Text(step.date, style: .timer))")
    }

    private func dayAndTime(for step: PlanSnapshot.Step) -> Text {
        let calendar = Calendar.current
        let day: Text
        if calendar.isDate(step.date, inSameDayAs: entry.date) {
            day = Text("Heute")
        } else if let tomorrow = calendar.date(byAdding: .day, value: 1, to: entry.date),
                  calendar.isDate(step.date, inSameDayAs: tomorrow) {
            day = Text("Morgen")
        } else {
            day = Text(step.date, format: .dateTime.day().month())
        }
        return day + Text(verbatim: " ") + Text(step.date, format: .dateTime.hour().minute())
    }

    // MARK: Families

    private func smallView(_ step: PlanSnapshot.Step) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            eyebrow
            Text(step.instruction)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(WidgetTheme.title)
                .lineLimit(3)
            Spacer(minLength: 0)
            dayAndTime(for: step)
                .font(.caption.weight(.semibold))
                .foregroundStyle(WidgetTheme.accent)
            countdown(for: step)
                .font(.caption2)
                .foregroundStyle(WidgetTheme.subtitle)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    /// Two rows rather than two columns: the recipe name gets the whole
    /// width, and the timer text — which reserves room for its widest value
    /// — sits alone at the end of the last row where that costs nothing.
    private func mediumView(_ step: PlanSnapshot.Step) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    eyebrow
                    // Larger than in the small size: the medium widget has
                    // the room, and a one-line step otherwise leaves it
                    // half empty.
                    Text(step.instruction)
                        .font(.headline)
                        .foregroundStyle(WidgetTheme.title)
                        .lineLimit(2)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Image(systemName: entry.isDue ? "bell.fill" : "timer")
                    .font(.title3)
                    .foregroundStyle(WidgetTheme.accent)
            }

            Spacer(minLength: 0)

            Text(step.recipeName)
                .font(.caption)
                .foregroundStyle(WidgetTheme.subtitle)
                .lineLimit(1)

            HStack(alignment: .firstTextBaseline) {
                dayAndTime(for: step)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(WidgetTheme.accent)
                    .lineLimit(1)
                    .fixedSize()
                Spacer(minLength: 8)
                countdown(for: step)
                    .font(.caption2)
                    .foregroundStyle(WidgetTheme.subtitle)
                    .lineLimit(1)
                    .multilineTextAlignment(.trailing)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func rectangularView(_ step: PlanSnapshot.Step) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 4) {
                Image(systemName: entry.isDue ? "bell.fill" : "timer")
                Text(entry.isDue ? "Jetzt fällig" : "Als Nächstes")
                    .textCase(.uppercase)
            }
            .font(.caption2.weight(.semibold))
            Text(step.instruction)
                .font(.headline)
                .lineLimit(2)
            countdown(for: step)
                .font(.caption2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func inlineView(_ step: PlanSnapshot.Step) -> some View {
        Text(step.date, format: .dateTime.hour().minute()) + Text(verbatim: " ") + Text(step.instruction)
    }

    private var emptyView: some View {
        VStack(alignment: .leading, spacing: 4) {
            Image(systemName: "calendar")
                .font(.title3)
                .foregroundStyle(WidgetTheme.accent)
            Text("Kein Schritt geplant")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(WidgetTheme.title)
            if !family.isAccessory {
                Text("Setze einen Reminder in der Backanleitung eines Rezepts.")
                    .font(.caption2)
                    .foregroundStyle(WidgetTheme.subtitle)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

private extension WidgetFamily {
    var isAccessory: Bool {
        switch self {
        case .accessoryCircular, .accessoryRectangular, .accessoryInline: return true
        default: return false
        }
    }
}

// MARK: - Widget

struct BackPlanerWidgets: Widget {
    let kind: String = "NextStepWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: NextStepProvider()) { entry in
            NextStepWidgetView(entry: entry)
        }
        .configurationDisplayName("Nächster Backschritt")
        .description("Zeigt den nächsten geplanten Schritt deines Backplans.")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryRectangular, .accessoryInline])
    }
}

#Preview(as: .systemSmall) {
    BackPlanerWidgets()
} timeline: {
    NextStepEntry.placeholder
    NextStepEntry(date: .now, step: nil, isDue: false)
}

#Preview(as: .systemMedium) {
    BackPlanerWidgets()
} timeline: {
    NextStepEntry.placeholder
}
