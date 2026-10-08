//
//  BakePlanValidator.swift
//  BackPlaner
//
//  Checks a generated baking plan against the planning settings: the day
//  window (Tagesbeginn/Tagesende), the oven phases of plans that are already
//  scheduled against the number of ovens (Backöfen), and the minimum pause
//  between two bakes in the same oven (Backpause).
//

import Foundation
import CoreData

/// How serious a finding of ``BakePlanValidator`` is.
enum BakePlanIssueSeverity {
    /// The plan must not be scheduled this way — more bakes would run at the
    /// same time than there are ovens.
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
    ///   - ovenCount: how many bakes may run at the same time; defaults to
    ///     the setting. Overridable so the rules can be tested.
    ///   - bakePause: the minimum gap in minutes between two bakes that share
    ///     an oven; defaults to the setting.
    static func issues(
        for steps: [PlannedStep],
        bakeWindow: BakeWindow?,
        existingWindows: [BakeWindow],
        ovenCount: Int = GlobalVariables.ovenCount,
        bakePause: Int = GlobalVariables.bakePause
    ) -> [BakePlanIssue] {

        var errors = [BakePlanIssue]()
        var hints  = dayWindowIssues(for: steps)

        if let bakeWindow {
            for issue in bakeWindowIssues(
                for: bakeWindow,
                existingWindows: existingWindows,
                ovenCount: ovenCount,
                bakePause: bakePause
            ) {
                switch issue.severity {
                case .error: errors.append(issue)
                case .hint:  hints.append(issue)
                }
            }
        }

        AppLog.planning.debug(
            "Plan checked: \(steps.count) steps, day window \(dayWindow().start)–\(dayWindow().end) h, \(ovenCount) ovens, bake pause \(bakePause) min, \(errors.count) errors, \(hints.count) hints"
        )

        return errors + hints
    }

    /// The day window in hours. A stored end at or before the start would switch
    /// the check off unnoticed, so such a setting falls back to the defaults.
    static func dayWindow() -> (start: Int, end: Int) {

        let dayStart = GlobalVariables.dayStart
        let dayEnd   = GlobalVariables.dayEnd

        guard dayEnd > dayStart else {
            return (AppSettings.defaultDayStart, AppSettings.defaultDayEnd)
        }

        return (dayStart, dayEnd)
    }

    /// Minutes since midnight at which `date` falls.
    private static func minuteOfDay(_ date: Date, calendar: Calendar) -> Int {
        let components = calendar.dateComponents([.hour, .minute], from: date)
        return (components.hour ?? 0) * 60 + (components.minute ?? 0)
    }

    /// Whether a step beginning at `date` lies before `dayStart` or after
    /// `dayEnd` (both in hours). The same rule as the day-window hints, for
    /// BakePlanAdvisor to look for a plan without them.
    static func isOutsideDay(_ date: Date, dayStart: Int, dayEnd: Int, calendar: Calendar = .current) -> Bool {
        let minute = minuteOfDay(date, calendar: calendar)
        return minute < dayStart * 60 || minute > dayEnd * 60
    }

    /// Hints for steps that fall before `Tagesbeginn` or after `Tagesende`.
    private static func dayWindowIssues(for steps: [PlannedStep]) -> [BakePlanIssue] {

        let (dayStart, dayEnd) = dayWindow()

        let calendar     = Calendar.current
        let startMinutes = dayStart * 60
        let endMinutes   = dayEnd * 60

        return steps.compactMap { step in

            let stepMinutes = minuteOfDay(step.date, calendar: calendar)

            if stepMinutes < startMinutes {
                return BakePlanIssue(
                    severity: .hint,
                    message: String(
                        localized: "„\(step.instruction)“ beginnt am \(dateTimeText(step.date)) und damit vor dem Tagesbeginn (\(hourText(dayStart)) Uhr).",
                        bundle: AppSettings.localizationBundle, locale: AppSettings.locale
                    )
                )
            }

            if stepMinutes > endMinutes {
                return BakePlanIssue(
                    severity: .hint,
                    message: String(
                        localized: "„\(step.instruction)“ beginnt am \(dateTimeText(step.date)) und damit nach dem Tagesende (\(hourText(dayEnd)) Uhr).",
                        bundle: AppSettings.localizationBundle, locale: AppSettings.locale
                    )
                )
            }

            return nil
        }
    }

    /// Checks the oven phase of the plan against the ovens available.
    ///
    /// Every oven takes one bake at a time, so the plan is an error as soon as
    /// it would need one oven more than there is: with a single oven that is
    /// any overlap, with two ovens only the moment a third bake joins in. An
    /// overlap that still fits into a spare oven is reported as a hint, so the
    /// user knows the second oven is spoken for.
    ///
    /// The pause works the same way, per oven: a bake that follows another one
    /// closer than `Backpause` only matters when no other oven is free for it,
    /// otherwise it simply goes into the cold one.
    private static func bakeWindowIssues(
        for window: BakeWindow,
        existingWindows: [BakeWindow],
        ovenCount: Int,
        bakePause: Int
    ) -> [BakePlanIssue] {

        let ovens = max(1, ovenCount)
        let pause = TimeInterval(max(0, bakePause) * 60)

        let others      = existingWindows.filter { $0.recipeName != window.recipeName }
        let overlapping = others.filter { overlaps($0, window) }
        // Bakes that do not overlap, but end or start within the pause.
        let neighbours  = pause > 0
            ? others.filter { !overlaps($0, window) && gap(between: $0, and: window) < pause }
            : []

        var issues = [BakePlanIssue]()

        // Peak number of ovens the scheduled bakes occupy at one moment of this bake.
        let busyOvens = peakConcurrency(of: overlapping, within: window, padding: 0)

        if busyOvens + 1 > ovens {
            if ovens == 1 {
                for other in overlapping {
                    issues.append(
                        BakePlanIssue(
                            severity: .error,
                            message: String(
                                localized: "Die Backzeit (\(rangeText(window))) überschneidet sich mit der Backzeit von „\(other.recipeName)“ (\(rangeText(other))).",
                                bundle: AppSettings.localizationBundle, locale: AppSettings.locale
                            )
                        )
                    )
                }
            } else {
                issues.append(
                    BakePlanIssue(
                        severity: .error,
                        message: String(
                            localized: "Die Backzeit (\(rangeText(window))) überschneidet sich mit \(namesText(of: overlapping)). Zusammen wären das mehr Backvorgänge, als Du Backöfen hast (\(ovens)).",
                            bundle: AppSettings.localizationBundle, locale: AppSettings.locale
                        )
                    )
                )
            }
        } else if ovens > 1 {
            for other in overlapping {
                issues.append(
                    BakePlanIssue(
                        severity: .hint,
                        message: String(
                            localized: "Die Backzeit (\(rangeText(window))) überschneidet sich mit der Backzeit von „\(other.recipeName)“ (\(rangeText(other))) und braucht deshalb einen weiteren Backofen.",
                            bundle: AppSettings.localizationBundle, locale: AppSettings.locale
                        )
                    )
                )
            }
        }

        guard !neighbours.isEmpty else { return issues }

        // Widening every scheduled bake by the pause turns "too close" into
        // "overlapping"; a pause hint is due only when that leaves no oven free.
        let busyOvensWithPause = peakConcurrency(of: overlapping + neighbours, within: window, padding: pause)
        guard busyOvensWithPause + 1 > ovens else { return issues }

        for other in neighbours {
            if window.start >= other.end {
                let gap = window.start.timeIntervalSince(other.end)
                issues.append(
                    BakePlanIssue(
                        severity: .hint,
                        message: String(
                            localized: "Der Backbeginn (\(dateTimeText(window.start))) liegt nur \(minutes(gap)) Minuten nach dem Backende von „\(other.recipeName)“. Die Backpause beträgt \(bakePause) Minuten.",
                            bundle: AppSettings.localizationBundle, locale: AppSettings.locale
                        )
                    )
                )
            }
            else {
                let gap = other.start.timeIntervalSince(window.end)
                issues.append(
                    BakePlanIssue(
                        severity: .hint,
                        message: String(
                            localized: "Das Backende (\(dateTimeText(window.end))) liegt nur \(minutes(gap)) Minuten vor dem Backbeginn von „\(other.recipeName)“. Die Backpause beträgt \(bakePause) Minuten.",
                            bundle: AppSettings.localizationBundle, locale: AppSettings.locale
                        )
                    )
                )
            }
        }

        return issues
    }

    /// Whether `window` would need more ovens than there are, given the bakes
    /// already scheduled: the condition of the overlap error above, without
    /// its message.
    static func needsMoreOvens(
        _ window: BakeWindow,
        existingWindows: [BakeWindow],
        ovenCount: Int = GlobalVariables.ovenCount
    ) -> Bool {
        let overlapping = existingWindows.filter { $0.recipeName != window.recipeName && overlaps($0, window) }
        return peakConcurrency(of: overlapping, within: window, padding: 0) + 1 > max(1, ovenCount)
    }

    private static func overlaps(_ a: BakeWindow, _ b: BakeWindow) -> Bool {
        a.start < b.end && b.start < a.end
    }

    /// The time between two bakes that do not overlap.
    private static func gap(between a: BakeWindow, and b: BakeWindow) -> TimeInterval {
        b.start >= a.end
            ? b.start.timeIntervalSince(a.end)
            : a.start.timeIntervalSince(b.end)
    }

    /// The largest number of `windows` that occupy an oven at the same instant
    /// during `window`. Each of them is widened by `padding` on both sides,
    /// which is how the pause between two bakes is accounted for.
    static func peakConcurrency(
        of windows: [BakeWindow],
        within window: BakeWindow,
        padding: TimeInterval
    ) -> Int {

        // +1 when a bake enters the oven, -1 when it leaves; both clipped to
        // the bake under test, which is all that matters here.
        var events = [(time: Date, delta: Int)]()

        for other in windows {
            let start = max(other.start.addingTimeInterval(-padding), window.start)
            let end   = min(other.end.addingTimeInterval(padding), window.end)
            guard start < end else { continue }
            events.append((start, 1))
            events.append((end, -1))
        }

        // At the same instant a bake leaving frees the oven for one entering.
        events.sort { $0.time == $1.time ? $0.delta < $1.delta : $0.time < $1.time }

        var current = 0
        var peak    = 0
        for event in events {
            current += event.delta
            peak = max(peak, current)
        }
        return peak
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

    /// Derives the oven phase of a plan: the step that puts the dough into the
    /// oven starts the bake, the generated finish step ends it.
    ///
    /// The oven step is recognised by its wording, not by its position. Taking
    /// the last processing step instead understates the phase for every recipe
    /// that cools down, rests or glazes afterwards — an already scheduled bake
    /// then looked shorter than it is, and a second bake placed inside its real
    /// oven time was reported as a short pause instead of an overlap.
    static func bakeWindow(recipeName: String, steps: [PlannedStep]) -> BakeWindow? {

        let processingSteps = steps.filter { $0.step < finishStepNumber }
        let ovenStep = processingSteps
            .filter { isBakingStartInstruction($0.instruction) }
            .min { $0.step < $1.step }

        guard let start = (ovenStep ?? processingSteps.max { $0.step < $1.step })?.date,
              let end = steps.first(where: { $0.step >= finishStepNumber })?.date
                        ?? steps.map(\.date).max(),
              end >= start else {
            return nil
        }

        return BakeWindow(recipeName: recipeName, start: start, end: end)
    }

    /// Whether a step puts the dough into the oven. Preheating does not count —
    /// it names a temperature as well, but the oven is still empty.
    static func isBakingStartInstruction(_ instruction: String) -> Bool {

        let text = instruction.folding(
            options: [.caseInsensitive, .diacriticInsensitive],
            locale: Locale(identifier: "de_DE")
        )

        // Neither heating the oven up nor turning it down puts dough in.
        guard !isPreheatInstruction(text), !BakePlan.isTurnDownInstruction(instruction) else { return false }

        return ["backen", "backofen", "ofen stellen", "ofen geben",
                "bake", "into the oven", "on stone",
                "cuire", "mettre au four"]
            .contains(where: text.contains)
    }

    /// Whether a step only heats the oven up. Besides an explicit preheating
    /// step of the recipe this covers the step the app generates itself
    /// ("Backofen anstellen" / "Turn on the oven" / "Allumer le four") in every
    /// language it can be stored in — it names the oven, but the dough is not
    /// in it yet.
    static func isPreheatInstruction(_ instruction: String) -> Bool {

        let text = instruction.folding(
            options: [.caseInsensitive, .diacriticInsensitive],
            locale: Locale(identifier: "de_DE")
        )

        return ["vorheiz", "preheat", "prechauff",
                "ofen anstellen", "turn on the oven", "allumer le four"]
            .contains(where: text.contains)
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

    /// The recipe names in the quotes of the app's language, joined the way
    /// that language lists things: „Brot“, „Brötchen“ und „Zopf“.
    private static func namesText(of windows: [BakeWindow]) -> String {
        windows
            .map { window in
                String(localized: "„\(window.recipeName)“",
                       bundle: AppSettings.localizationBundle, locale: AppSettings.locale)
            }
            .formatted(.list(type: .and).locale(AppSettings.locale))
    }

    /// Full minutes of a gap. Rounding up would let a gap of 9:42 read as
    /// "only 10 minutes" against a pause of 10 minutes, which contradicts
    /// itself.
    private static func minutes(_ interval: TimeInterval) -> Int {
        max(0, Int(interval / 60))
    }
}
