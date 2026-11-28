import BakePlannerCore
import BakePlannerMedia
import CookPlannerMedia
import Foundation
import SwiftUI

/// The plan and the yearbook as PDF, the iPhone's pages in text and
/// pictures: the blocks are put together here from the package's data
/// (KitchenPlanSheet, KitchenYearbook), drawn by CookPlannerMedia
/// (Android's PdfDocument) and handed to the share sheet through
/// BakePlannerMedia's ContentFile.
@MainActor
enum PrintedPages {

    // MARK: Plan

    /// The plan with clock times from `start`, or minutes from 0 without one.
    static func sharePlan(_ plan: DishPlan, start: Date?) -> Bool {
        let sheet = KitchenPlanSheet(dish: plan.dish, schedule: plan.schedule, start: start, locale: AppSettings.locale)
        var blocks: [[String: Any]] = []
        blocks.append(["kind": "caption", "text": String(localized: "Ablaufplan", bundle: .module)])
        blocks.append(["kind": "title", "text": sheet.title])
        var facts = [plan.verdict]
        if let startText = sheet.startText, let finishText = sheet.finishText {
            facts.append(String(localized: "Start \(startText /*%@*/) · fertig \(finishText /*%@*/)", bundle: .module))
        } else {
            facts.append(String(localized: "Dauer \(sheet.minutes) Min., Zeiten ab Minute 0", bundle: .module))
        }
        if let servings = sheet.servings {
            facts.append(String(localized: "Für \(servings) Personen", bundle: .module))
        }
        blocks.append(["kind": "meta", "text": facts.joined(separator: " · ")])
        blocks.append(["kind": "heading", "text": String(localized: "Zeitachse", bundle: .module)])
        blocks.append(timelineBlock(plan, sheet: sheet, start: start))
        blocks.append(["kind": "heading", "text": String(localized: "Ablauf", bundle: .module)])
        for step in sheet.steps {
            var details: [String] = []
            if !step.component.isEmpty { details.append(step.component) }
            if step.handsMinutes > 0 { details.append(String(localized: "\(step.handsMinutes) Min. Hände", bundle: .module)) }
            if step.unattendedMinutes > 0 { details.append(String(localized: "\(step.unattendedMinutes) Min. allein", bundle: .module)) }
            if let temperature = step.ovenTemperature {
                details.append(String(localized: "Ofen \(temperature) °C", bundle: .module))
            } else if step.station == .burner {
                details.append(String(localized: "Herd", bundle: .module))
            } else if step.station == .oven {
                details.append(String(localized: "Ofen", bundle: .module))
            }
            let joined = step.ingredients.joined(separator: " · ")
            blocks.append(["kind": "step", "number": String(step.number), "time": step.startText + "–" + step.endText,
                           "text": step.name, "details": details.joined(separator: " · "),
                           "ingredients": step.ingredients.isEmpty ? "" : String(localized: "Zutaten: \(joined /*%@*/)", bundle: .module)])
        }
        if !sheet.ingredients.isEmpty {
            blocks.append(["kind": "heading", "text": String(localized: "Zutaten", bundle: .module)])
            for group in sheet.ingredients {
                blocks.append(["kind": "text", "text": group.component.isEmpty ? String(localized: "Ohne Komponente", bundle: .module) : group.component])
                for line in group.lines {
                    blocks.append(["kind": "text", "text": "– " + line, "indent": 1])
                }
                blocks.append(["kind": "space", "height": 4])
            }
        }
        return share(blocks: blocks, fileName: sheet.title)
    }

    // MARK: Yearbook

    /// The years with records, newest first.
    @MainActor
    /// The chart of the plan for BlockPDF: lanes per component in the
    /// timeline's colours, bars with their step numbers, minute lines every
    /// five minutes (ten for long plans) labelled with the clock time from
    /// `start` or the minute.
    private static func timelineBlock(_ plan: DishPlan, sheet: KitchenPlanSheet, start: Date?) -> [String: Any] {
        let layout = KitchenTimelineLayout(schedule: plan.schedule, components: plan.dish.components)
        let numbers = sheet.numbers
        let every = layout.makespan > 60 ? 10 : 5
        let ticks: [[String: Any]] = layout.ticks(every: every).map { minute in
            let label = start.map {
                $0.addingTimeInterval(TimeInterval(minute * 60)).formatted(.dateTime.hour().minute().locale(AppSettings.locale))
            } ?? "\(minute)′"
            return ["minute": minute, "label": label, "strong": minute % 15 == 0 ? 1 : 0]
        }
        var lanes: [[String: Any]] = []
        for (index, lane) in layout.lanes.enumerated() {
            let rgb = PlanTimelineView.palette[index % PlanTimelineView.palette.count]
            let bars: [[String: Any]] = lane.bars.map { bar in
                ["start": bar.placement.start, "handsEnd": bar.placement.handsEnd, "end": bar.placement.end,
                 "track": bar.track, "number": numbers[bar.placement.id].map { String($0) } ?? ""]
            }
            lanes.append(["name": lane.component.isEmpty ? String(localized: "Ohne Komponente", bundle: .module) : lane.component,
                          "color": [Int(rgb.red * 255), Int(rgb.green * 255), Int(rgb.blue * 255)],
                          "tracks": lane.bars.map(\.tracks).max() ?? 1,
                          "bars": bars])
        }
        return ["kind": "timeline", "minutes": layout.makespan, "ticks": ticks, "lanes": lanes,
                "legend": [String(localized: "Hände", bundle: .module), String(localized: "läuft allein", bundle: .module),
                           String(localized: "Zahl = Schritt im Ablauf", bundle: .module)]]
    }

    static func yearbookYears() -> [Int] {
        KitchenYearbook.years(of: CookRunLog.shared.runs)
    }

    /// The year of cooking as a book: cover, the year in figures, every
    /// month with its photos, the favourite dishes, what the clock taught,
    /// a page for resolutions.
    @MainActor
    static func shareYearbook(year: Int, cookName: String) -> Bool {
        let log = CookRunLog.shared
        let book = KitchenYearbook.compute(year: year, runs: log.runs)
        guard !book.isEmpty else { return false }
        let folder = URL.cachesDirectory.appendingPathComponent("yearbook-photos", isDirectory: true)
        try? FileManager.default.removeItem(at: folder)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        /// A run's photo as a small JPEG file, for the renderer.
        func photoPath(_ runID: String?) -> String? {
            // The page shows a photo at a few centimetres; 600 pixels
            // suffice, and a year of 2048-pixel bitmaps would not fit in memory.
            guard let runID, let run = log.run(id: runID), let data = log.photoData(of: run),
                  let small = PhotoShrinker.thumbnail(data, edge: 600) else { return nil }
            let url = folder.appendingPathComponent(runID + ".jpg")
            guard (try? small.write(to: url)) != nil else { return nil }
            return url.path
        }
        let title = String(localized: "Mein Kochjahr \(String(book.year) /*%@*/)", bundle: .module)
        var blocks: [[String: Any]] = []
        blocks.append(["kind": "space", "height": 120])
        blocks.append(["kind": "title", "text": title])
        let name = cookName.trimmingCharacters(in: .whitespacesAndNewlines)
        if !name.isEmpty { blocks.append(["kind": "meta", "text": name]) }
        blocks.append(["kind": "meta", "text": String(localized: "\(book.sessions) Mal gekocht an \(book.cookingDays) Tagen, \(book.dishes) Gerichte", bundle: .module)])
        if let cover = photoPath(book.coverPhotoRunID) {
            blocks.append(["kind": "photos", "paths": [cover], "captions": [""]])
        }
        blocks.append(["kind": "page"])

        blocks.append(["kind": "heading", "text": String(localized: "Das Jahr in Zahlen", bundle: .module)])
        let hours = IngredientDraft.text(for: (book.hoursOnTheClock * 10).rounded() / 10)
        var figures: [String] = [
            String(localized: "Gekocht", bundle: .module) + ": \(book.sessions)",
            String(localized: "Kochtage", bundle: .module) + ": \(book.cookingDays)",
            String(localized: "Gerichte", bundle: .module) + ": \(book.dishes)",
            String(localized: "Stunden am Herd", bundle: .module) + ": " + hours,
        ]
        if let rating = book.averageRating {
            figures.append(String(localized: "Ø Bewertung", bundle: .module) + ": " + IngredientDraft.text(for: (rating * 10).rounded() / 10))
        }
        if book.timedRuns > 0 {
            figures.append(String(localized: "Im Plan geblieben", bundle: .module) + ": \(book.withinPlan) / \(book.timedRuns)")
        }
        if book.relaxedRuns > 0 {
            figures.append(String(localized: "Entspannt gekocht", bundle: .module) + ": \(book.relaxedRuns)")
        }
        if let longest = book.longestSession {
            figures.append(String(localized: "Längste Session", bundle: .module) + ": " + longest.name + " · "
                           + String(localized: "\(longest.minutes) Min.", bundle: .module))
        }
        for figure in figures { blocks.append(["kind": "text", "text": figure]) }

        for month in book.months where !month.runs.isEmpty {
            blocks.append(["kind": "heading", "text": month.start.formatted(.dateTime.month(.wide).year().locale(AppSettings.locale))])
            blocks.append(["kind": "small", "text": String(localized: "\(month.runs.count) Mal gekocht", bundle: .module)])
            var paths: [String] = []
            var captions: [String] = []
            for run in month.runs {
                let date = run.startedAt.formatted(.dateTime.day().month(.abbreviated).locale(AppSettings.locale))
                let line = [date, run.dishName, run.rating.map(starsText) ?? ""].filter { !$0.isEmpty }.joined(separator: " · ")
                if let path = photoPath(run.id) {
                    paths.append(path)
                    captions.append(run.dishName)
                    if paths.count == 3 {
                        blocks.append(["kind": "photos", "paths": paths, "captions": captions])
                        paths = []
                        captions = []
                    }
                }
                blocks.append(["kind": "text", "text": line, "indent": 1])
            }
            if !paths.isEmpty { blocks.append(["kind": "photos", "paths": paths, "captions": captions]) }
        }

        if !book.favourites.isEmpty {
            blocks.append(["kind": "heading", "text": String(localized: "Lieblingsgerichte", bundle: .module)])
            for favourite in book.favourites {
                var parts = [String(localized: "\(favourite.count)× gekocht", bundle: .module)]
                if let rating = favourite.averageRating { parts.append(starsText(Int(rating.rounded()))) }
                if let best = favourite.bestMinutes { parts.append(String(localized: "Bestzeit \(best) Min.", bundle: .module)) }
                if let planned = favourite.plannedMinutes { parts.append(String(localized: "Plan \(planned) Min.", bundle: .module)) }
                blocks.append(["kind": "text", "text": favourite.name])
                blocks.append(["kind": "small", "text": parts.joined(separator: " · "), "indent": 1])
                if let path = photoPath(favourite.photoRunID) {
                    blocks.append(["kind": "photos", "paths": [path], "captions": [""]])
                }
            }
        }
        if !book.lessons.isEmpty {
            blocks.append(["kind": "heading", "text": String(localized: "Was die Uhr lehrte", bundle: .module)])
            for lesson in book.lessons {
                let first = lesson.firstMinutes
                let latest = lesson.latestMinutes
                let saved = lesson.savedMinutes
                blocks.append(["kind": "text", "text": saved > 0
                    ? String(localized: "\(lesson.name /*%@*/): von \(first) auf \(latest) Minuten – \(saved) Minuten schneller.", bundle: .module)
                    : String(localized: "\(lesson.name /*%@*/): von \(first) auf \(latest) Minuten – mehr Zeit gelassen.", bundle: .module)])
            }
        }
        blocks.append(["kind": "page"])
        let next = String(book.year + 1)
        blocks.append(["kind": "heading", "text": String(localized: "Vorsätze für \(next /*%@*/)", bundle: .module)])
        blocks.append(["kind": "lines", "count": 14])
        return share(blocks: blocks, fileName: title)
    }

    // MARK: Drawing

    private static func share(blocks: [[String: Any]], fileName: String) -> Bool {
        let document: [String: Any] = ["footer": String(localized: "Erstellt mit CookPlanner", bundle: .module), "blocks": blocks]
        guard let data = try? JSONSerialization.data(withJSONObject: document) else { return false }
        let cleaned = fileName.components(separatedBy: CharacterSet(charactersIn: "/\\:?*\"<>|")).joined(separator: "-")
        let path = ContentFile.sharedFilePath(named: (cleaned.isEmpty ? "CookPlanner" : cleaned) + ".pdf")
        guard BlockPDF.write(json: String(decoding: data, as: UTF8.self), toPath: path) else { return false }
        return ContentFile.share(filePath: path, mimeType: "application/pdf")
    }
}

/// Printing the plan: with clock times from a start, or in minutes.
struct PlanPDFSheet: View {
    let plan: DishPlan
    @State var withTimes = true
    @State var start = Date()
    @State var failed = false
    @Environment(\.dismiss) var dismiss
    @Environment(\.colorScheme) var colorScheme

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Toggle(String(localized: "Mit Uhrzeit", bundle: .module), isOn: $withTimes)
                    if withTimes {
                        DatePicker(String(localized: "Start", bundle: .module), selection: $start,
                                   displayedComponents: [.hourAndMinute])
                    }
                } footer: {
                    Text(String(localized: "Ein PDF im A4-Format – zum Drucken, Binden oder Verschicken.", bundle: .module))
                }
                Section {
                    Button(String(localized: "Ablaufplan teilen", bundle: .module)) {
                        if PrintedPages.sharePlan(plan, start: withTimes ? start : nil) {
                            dismiss()
                        } else {
                            failed = true
                        }
                    }
                    if failed {
                        Text(String(localized: "Das PDF ließ sich nicht erstellen.", bundle: .module))
                            .foregroundStyle(Palette.danger(colorScheme))
                    }
                }
            }
            .navigationTitle(String(localized: "Ablaufplan als PDF", bundle: .module))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(String(localized: "Abbrechen", bundle: .module)) { dismiss() }
                }
            }
        }
        .tint(Palette.accent(colorScheme))
    }
}

/// The yearbook: the year, the name on the cover, share.
struct CookYearbookSheet: View {
    @State var year = PrintedPages.yearbookYears().first ?? Calendar.current.component(.year, from: Date())
    @State var cookName = SettingsFile.text("yearbook.cookName") ?? ""
    @State var failed = false
    @Environment(\.dismiss) var dismiss
    @Environment(\.colorScheme) var colorScheme

    var body: some View {
        NavigationStack {
            Form {
                if PrintedPages.yearbookYears().isEmpty {
                    Section {
                        Text(String(localized: "Noch nichts gekocht – das Buch entsteht aus der Kochhistorie.", bundle: .module))
                    }
                } else {
                    Section {
                        Picker(String(localized: "Jahr", bundle: .module), selection: $year) {
                            ForEach(PrintedPages.yearbookYears(), id: \.self) { year in
                                Text(verbatim: String(year)).tag(year)
                            }
                        }
                        TextField(String(localized: "Name auf dem Titelblatt", bundle: .module), text: $cookName)
                    } footer: {
                        Text(String(localized: "Das Buch nimmt alle Kochvorgänge des Jahres mit ihren Fotos, die Lieblingsgerichte und was die Uhr gelehrt hat.", bundle: .module))
                    }
                    Section {
                        Button(String(localized: "Kochjahr-Buch teilen", bundle: .module)) {
                            SettingsFile.set(cookName, forKey: "yearbook.cookName")
                            if PrintedPages.shareYearbook(year: year, cookName: cookName) {
                                dismiss()
                            } else {
                                failed = true
                            }
                        }
                        if failed {
                            Text(String(localized: "Das PDF ließ sich nicht erstellen.", bundle: .module))
                                .foregroundStyle(Palette.danger(colorScheme))
                        }
                    } footer: {
                        Text(String(localized: "Ein PDF im A4-Format – zum Drucken, Binden oder Verschicken.", bundle: .module))
                    }
                }
            }
            .navigationTitle(String(localized: "Kochjahr-Buch", bundle: .module))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(String(localized: "Abbrechen", bundle: .module)) { dismiss() }
                }
            }
        }
        .tint(Palette.accent(colorScheme))
    }
}
