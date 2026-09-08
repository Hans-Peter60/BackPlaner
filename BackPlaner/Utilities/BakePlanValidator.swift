//
//  BakePlanValidator.swift
//  BackPlaner
//
//  Checks a generated baking plan against the planning settings: the day
//  window (Tagesbeginn/Tagesende), the oven phases of plans that are already
//  scheduled, and the minimum pause between two bakes (Backpause).
//

import Foundation
import CoreData

/// How serious a finding of ``BakePlanValidator`` is.
enum BakePlanIssueSeverity {
    /// The plan must not be scheduled this way — two bakes would overlap.
    case error
    /// The plan works, but the user should know about it.
    case hint
}

/// A single finding for a generated baking plan.
struct BakePlanIssue: Identifiable {
    let id = UUID()
    let severity: BakePlanIssueSeverity
    let message: String
}

/// One step of a baking plan, reduced to the values validation needs.
struct PlannedStep {
    let instruction: String
    var step: Double = 0
    let date: Date
}

/// The oven phase of a plan: it begins with the last processing step (the step
/// that puts the dough into the oven) and ends when the plan is finished.
struct BakeWindow {
    let recipeName: String
    let start: Date
    let end: Date
}

enum BakePlanValidator {

    /// The generated finish step ("Backvorgang ist beendet") always carries
    /// step number 99, see the reminder generation in the instruction views.
    private static let finishStepNumber: Double = 99

    // MARK: - Validation

    /// Validates a plan. Errors are returned before hints so the most important
    /// finding is shown first.
    ///
    /// - Parameters:
    ///   - steps: every step the plan generates, including the two steps the app
    ///     adds itself (switching the oven on and the end of the bake).
    ///   - bakeWindow: the oven phase of the plan, or `nil` if the recipe has no
    ///     processing steps yet.
    ///   - existingWindows: the oven phases of the plans already scheduled.
    static func issues(
        for steps: [PlannedStep],
        bakeWindow: BakeWindow?,
        existingWindows: [BakeWindow]
    ) -> [BakePlanIssue] {

        var errors = [BakePlanIssue]()
        var hints  = dayWindowIssues(for: steps)

        if let bakeWindow {
            for issue in bakeWindowIssues(for: bakeWindow, existingWindows: existingWindows) {
                switch issue.severity {
                case .error: errors.append(issue)
                case .hint:  hints.append(issue)
                }
            }
        }

        AppLog.planning.debug(
            "Plan checked: \(steps.count) steps, day window \(dayWindow().start)–\(dayWindow().end) h, bake pause \(GlobalVariables.bakePause) min, \(errors.count) errors, \(hints.count) hints"
        )

        return errors + hints
    }

    /// The day window in hours. A stored end at or before the start would switch
    /// the check off unnoticed, so such a setting falls back to the defaults.
    private static func dayWindow() -> (start: Int, end: Int) {

        let dayStart = GlobalVariables.dayStart
        let dayEnd   = GlobalVariables.dayEnd

        guard dayEnd > dayStart else {
            return (AppSettings.defaultDayStart, AppSettings.defaultDayEnd)
        }

        return (dayStart, dayEnd)
    }

    /// Hints for steps that fall before `Tagesbeginn` or after `Tagesende`.
    private static func dayWindowIssues(for steps: [PlannedStep]) -> [BakePlanIssue] {

        let (dayStart, dayEnd) = dayWindow()

        let calendar     = Calendar.current
        let startMinutes = dayStart * 60
        let endMinutes   = dayEnd * 60

        return steps.compactMap { step in

            let components  = calendar.dateComponents([.hour, .minute], from: step.date)
            let stepMinutes = (components.hour ?? 0) * 60 + (components.minute ?? 0)

            if stepMinutes < startMinutes {
                return BakePlanIssue(
                    severity: .hint,
                    message: String(
                        localized: "„\(step.instruction)“ beginnt am \(dateTimeText(step.date)) und damit vor dem Tagesbeginn (\(hourText(dayStart)) Uhr).",
                        locale: AppSettings.locale
                    )
                )
            }

            if stepMinutes > endMinutes {
                return BakePlanIssue(
                    severity: .hint,
                    message: String(
                        localized: "„\(step.instruction)“ beginnt am \(dateTimeText(step.date)) und damit nach dem Tagesende (\(hourText(dayEnd)) Uhr).",
                        locale: AppSettings.locale
                    )
                )
            }

            return nil
        }
    }

    /// An error for every already scheduled bake this plan overlaps with, plus a
    /// hint whenever the gap to a neighbouring bake is shorter than `Backpause`.
    private static func bakeWindowIssues(
        for window: BakeWindow,
        existingWindows: [BakeWindow]
    ) -> [BakePlanIssue] {

        let bakePause = GlobalVariables.bakePause
        let pause     = TimeInterval(bakePause * 60)

        var issues = [BakePlanIssue]()

        for other in existingWindows where other.recipeName != window.recipeName {

            if window.start < other.end && other.start < window.end {
                issues.append(
                    BakePlanIssue(
                        severity: .error,
                        message: String(
                            localized: "Die Backzeit (\(rangeText(window))) überschneidet sich mit der Backzeit von „\(other.recipeName)“ (\(rangeText(other))).",
                            locale: AppSettings.locale
                        )
                    )
                )
                continue
            }

            guard pause > 0 else { continue }

            if window.start >= other.end {
                let gap = window.start.timeIntervalSince(other.end)
                guard gap < pause else { continue }
                issues.append(
                    BakePlanIssue(
                        severity: .hint,
                        message: String(
                            localized: "Der Backbeginn (\(dateTimeText(window.start))) liegt nur \(minutes(gap)) Minuten nach dem Backende von „\(other.recipeName)“. Die Backpause beträgt \(bakePause) Minuten.",
                            locale: AppSettings.locale
                        )
                    )
                )
            }
            else {
                let gap = other.start.timeIntervalSince(window.end)
                guard gap < pause else { continue }
                issues.append(
                    BakePlanIssue(
                        severity: .hint,
                        message: String(
                            localized: "Das Backende (\(dateTimeText(window.end))) liegt nur \(minutes(gap)) Minuten vor dem Backbeginn von „\(other.recipeName)“. Die Backpause beträgt \(bakePause) Minuten.",
                            locale: AppSettings.locale
                        )
                    )
                )
            }
        }

        return issues
    }

    // MARK: - Bake windows

    /// The oven phases of all plans that are currently scheduled, without the
    /// plan of `recipeName` (which is about to be replaced) and without bakes
    /// that are already over.
    static func scheduledBakeWindows(
        excluding recipeName: String,
        in context: NSManagedObjectContext,
        now: Date = Date()
    ) -> [BakeWindow] {

        let request = NextStep.fetchRequest()
        request.predicate = NSPredicate(format: "recipeName != %@", recipeName)

        guard let steps = try? context.fetch(request) else { return [] }

        return Dictionary(grouping: steps, by: \.recipeName)
            .compactMap { name, steps in
                bakeWindow(
                    recipeName: name,
                    steps: steps.map {
                        PlannedStep(instruction: $0.instruction, step: $0.step, date: $0.date)
                    }
                )
            }
            .filter { $0.end > now }
    }

    /// Derives the oven phase of a plan: the last processing step starts the
    /// bake, the generated finish step ends it.
    static func bakeWindow(recipeName: String, steps: [PlannedStep]) -> BakeWindow? {

        let processingSteps = steps.filter { $0.step < finishStepNumber }

        guard let start = processingSteps.max(by: { $0.step < $1.step })?.date,
              let end = steps.first(where: { $0.step >= finishStepNumber })?.date
                        ?? steps.map(\.date).max(),
              end >= start else {
            return nil
        }

        return BakeWindow(recipeName: recipeName, start: start, end: end)
    }

    // MARK: - Formatting

    private static func dateTimeText(_ date: Date) -> String {
        DateCalculation().calculateDateTime(dT: date)
    }

    private static func rangeText(_ window: BakeWindow) -> String {
        let time = TimeCalculation()
        return "\(dateTimeText(window.start)) – \(time.calculateTime(t: window.end))"
    }

    private static func hourText(_ hour: Int) -> String {
        String(format: "%02d:00", hour)
    }

    private static func minutes(_ interval: TimeInterval) -> Int {
        max(0, Int((interval / 60).rounded()))
    }
}
