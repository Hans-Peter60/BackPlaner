//
//  CookYearbook.swift
//  CookPlanner
//
//  "Mein Kochjahr": a year of the cooking history as a PDF book — cover,
//  the year in figures, every month with its photos, the dishes cooked
//  most, what the clock taught, and a page for next year's resolutions.
//  The sums are KitchenYearbook in the package; the pages draw with the
//  plan PDF's page helpers. The sheet behind "Kochjahr-Buch" in the history
//  picks the year, puts a name on the cover and shares the file.
//

import BakePlannerCore
import CoreTransferable
import SwiftUI
import UIKit
import UniformTypeIdentifiers

/// Everything the renderer needs, gathered before the share sheet asks.
struct CookYearbookDocument {
    let book: KitchenYearbook
    /// The name on the cover; empty for none.
    let cookName: String
    /// The photos by run id, already made small for print.
    let photos: [String: Data]

    static let photoPixels: CGFloat = 900

    var title: String { String(localized: "Mein Kochjahr \(String(book.year))") }

    @MainActor
    static func load(year: Int, cookName: String, log: CookRunLog = .shared) -> CookYearbookDocument {
        let book = KitchenYearbook.compute(year: year, runs: log.runs)
        var photos = [String: Data]()
        for month in book.months {
            for run in month.runs where run.photoFileName != nil {
                guard let url = log.photoURL(of: run), let data = try? Data(contentsOf: url),
                      let small = CookRunLog.downsampled(data, maxPixels: photoPixels),
                      let jpeg = small.jpegData(compressionQuality: 0.8) else { continue }
                photos[run.id] = jpeg
            }
        }
        return CookYearbookDocument(book: book, cookName: cookName.trimmingCharacters(in: .whitespacesAndNewlines), photos: photos)
    }
}

/// What the share sheet gets; rendered only when the file is asked for.
struct CookYearbookPDFExport: Transferable {
    let document: CookYearbookDocument

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(exportedContentType: .pdf) { export in
            SentTransferredFile(try export.writeFile())
        }
        .suggestedFileName { "\(PlanPDFRenderer.fileName(for: $0.document.title)).pdf" }
    }

    func writeFile() throws -> URL {
        let folder = try TemporaryExports.folder(prefix: "Yearbook-")
        let url = folder.appendingPathComponent(PlanPDFRenderer.fileName(for: document.title)).appendingPathExtension("pdf")
        try CookYearbookRenderer.render(document).write(to: url, options: .atomic)
        return url
    }
}

enum CookYearbookRenderer {

    private typealias Page = PlanPDFRenderer.Page
    private static var pageSize: CGSize { PlanPDFRenderer.pageSize }
    private static var margin: CGFloat { PlanPDFRenderer.margin }
    private static var ink: UIColor { PlanPDFRenderer.ink }
    private static var accent: UIColor { PlanPDFRenderer.accent }
    private static var muted: UIColor { PlanPDFRenderer.muted }
    private static var line: UIColor { PlanPDFRenderer.line }

    static func render(_ document: CookYearbookDocument) -> Data {
        let format = UIGraphicsPDFRendererFormat()
        format.documentInfo = [kCGPDFContextTitle as String: document.title, kCGPDFContextCreator as String: "CookPlanner"]
        let renderer = UIGraphicsPDFRenderer(bounds: CGRect(origin: .zero, size: pageSize), format: format)
        let book = document.book
        let locale = Locale.current
        return renderer.pdfData { context in
            var page = Page(context: context)

            // Cover.
            page.begin()
            cover(document, on: &page)

            // The year in figures.
            page.begin()
            page.draw(String(localized: "Das Jahr in Zahlen"), at: CGPoint(x: margin, y: page.y), width: page.contentWidth,
                      font: .systemFont(ofSize: 24, weight: .bold), color: ink)
            page.y += 44
            var tiles: [(String, String)] = [
                (String(localized: "Gekocht"), String(book.sessions)),
                (String(localized: "Kochtage"), String(book.cookingDays)),
                (String(localized: "Gerichte"), String(book.dishes)),
                (String(localized: "Stunden am Herd"), book.hoursOnTheClock.formatted(.number.precision(.fractionLength(1)).locale(locale))),
            ]
            if let average = book.averageRating {
                tiles.append((String(localized: "Ø Bewertung"), average.formatted(.number.precision(.fractionLength(1)).locale(locale)) + " ★"))
            }
            if book.timedRuns > 0 {
                tiles.append((String(localized: "Im Plan geblieben"), "\(book.withinPlan) / \(book.timedRuns)"))
            }
            if book.relaxedRuns > 0 {
                tiles.append((String(localized: "Entspannt gekocht"), String(book.relaxedRuns)))
            }
            if let longest = book.longestSession {
                // The minutes are the figure; the dish goes into the caption, cut
                // short rather than wrapped over the tile.
                let name = longest.name.count > 36 ? String(longest.name.prefix(35)).trimmingCharacters(in: .whitespaces) + "…" : longest.name
                tiles.append((String(localized: "Längste Session") + ": " + name, String(localized: "\(longest.minutes) Min.")))
            }
            drawTiles(tiles, on: &page)
            page.y += 18
            page.heading(String(localized: "Gekocht je Monat"))
            drawMonthBars(book.monthCounts, year: book.year, on: &page, locale: locale)

            // Month by month, with the photos.
            for month in book.months {
                page.begin()
                let title = month.start.formatted(Date.FormatStyle().month(.wide).year().locale(locale))
                page.draw(title, at: CGPoint(x: margin, y: page.y), width: page.contentWidth,
                          font: .systemFont(ofSize: 24, weight: .bold), color: ink)
                page.y += 32
                page.text(String(localized: "\(month.runs.count) Mal gekocht"), font: .systemFont(ofSize: 11), color: muted)
                page.y += 10
                drawRuns(month.runs, document: document, on: &page, locale: locale)
            }

            // The favourites.
            if !book.favourites.isEmpty {
                page.begin()
                page.draw(String(localized: "Lieblingsgerichte"), at: CGPoint(x: margin, y: page.y), width: page.contentWidth,
                          font: .systemFont(ofSize: 24, weight: .bold), color: ink)
                page.y += 44
                for favourite in book.favourites {
                    var facts = [String(localized: "\(favourite.count)× gekocht")]
                    if let rating = favourite.averageRating {
                        facts.append(rating.formatted(.number.precision(.fractionLength(1)).locale(locale)) + " ★")
                    }
                    if let best = favourite.bestMinutes {
                        facts.append(String(localized: "Bestzeit \(best) Min."))
                        if let planned = favourite.plannedMinutes { facts.append(String(localized: "Plan \(planned) Min.")) }
                    }
                    drawFavourite(favourite, facts: facts.joined(separator: " · "), document: document, on: &page)
                }
            }

            // What the clock taught.
            if !book.lessons.isEmpty {
                page.begin()
                page.draw(String(localized: "Was die Uhr lehrte"), at: CGPoint(x: margin, y: page.y), width: page.contentWidth,
                          font: .systemFont(ofSize: 24, weight: .bold), color: ink)
                page.y += 44
                for lesson in book.lessons {
                    let text = lesson.savedMinutes > 0
                        ? String(localized: "\(lesson.name): von \(lesson.firstMinutes) auf \(lesson.latestMinutes) Minuten – \(lesson.savedMinutes) Minuten schneller.")
                        : String(localized: "\(lesson.name): von \(lesson.firstMinutes) auf \(lesson.latestMinutes) Minuten – mehr Zeit gelassen.")
                    page.text(text, font: .systemFont(ofSize: 12), color: ink)
                    page.y += 4
                }
            }

            // Resolutions.
            page.begin()
            page.draw(String(localized: "Vorsätze für \(String(book.year + 1))"), at: CGPoint(x: margin, y: page.y),
                      width: page.contentWidth, font: .systemFont(ofSize: 24, weight: .bold), color: ink)
            page.y += 54
            let cg = page.context.cgContext
            cg.setStrokeColor(muted.withAlphaComponent(0.35).cgColor)
            cg.setLineWidth(0.6)
            var lineY = page.y
            while lineY < pageSize.height - margin - 40 {
                cg.move(to: CGPoint(x: margin, y: lineY))
                cg.addLine(to: CGPoint(x: pageSize.width - margin, y: lineY))
                cg.strokePath()
                lineY += 28
            }
            page.finishFooter()
        }
    }

    // MARK: Pages

    private static func cover(_ document: CookYearbookDocument, on page: inout Page) {
        let book = document.book
        page.y = margin + 60
        page.draw(String(localized: "Mein Kochjahr"), at: CGPoint(x: margin, y: page.y), width: page.contentWidth,
                  font: .systemFont(ofSize: 18, weight: .semibold), color: accent, alignment: .center)
        page.y += 30
        page.draw(String(book.year), at: CGPoint(x: margin, y: page.y), width: page.contentWidth,
                  font: .systemFont(ofSize: 64, weight: .bold), color: ink, alignment: .center)
        page.y += 90
        if !document.cookName.isEmpty {
            page.draw(document.cookName, at: CGPoint(x: margin, y: page.y), width: page.contentWidth,
                      font: .systemFont(ofSize: 16), color: muted, alignment: .center)
            page.y += 30
        }
        page.y += 20
        if let id = book.coverPhotoRunID, let data = document.photos[id], let image = UIImage(data: data) {
            let side = min(page.contentWidth, 340)
            let rect = CGRect(x: (pageSize.width - side) / 2, y: page.y, width: side, height: side)
            drawImage(image, in: rect, cornerRadius: 16)
            page.y += side + 24
        }
        let summary = String(localized: "\(book.sessions) Mal gekocht an \(book.cookingDays) Tagen, \(book.dishes) Gerichte")
        page.draw(summary, at: CGPoint(x: margin, y: page.y), width: page.contentWidth,
                  font: .systemFont(ofSize: 12), color: muted, alignment: .center)
    }

    private static func drawTiles(_ tiles: [(String, String)], on page: inout Page) {
        let columns = 2
        let gap: CGFloat = 12
        let width = (page.contentWidth - gap) / CGFloat(columns)
        let height: CGFloat = 58
        let cg = page.context.cgContext
        for (index, tile) in tiles.enumerated() {
            if index % columns == 0 { page.ensureRoom(for: height + gap) }
            let x = margin + CGFloat(index % columns) * (width + gap)
            let rect = CGRect(x: x, y: page.y, width: width, height: height)
            cg.setFillColor(line.withAlphaComponent(0.35).cgColor)
            UIBezierPath(roundedRect: rect, cornerRadius: 10).fill()
            // One line each: a long figure shrinks, a long caption is cut.
            let valueFont = UIFont.systemFont(ofSize: tile.1.count > 14 ? 13 : 20, weight: .bold)
            drawLine(tile.1, at: CGPoint(x: x + 12, y: page.y + 8), width: width - 24, font: valueFont, color: ink)
            drawLine(tile.0, at: CGPoint(x: x + 12, y: page.y + 36), width: width - 24, font: .systemFont(ofSize: 10), color: muted)
            if index % columns == columns - 1 || index == tiles.count - 1 { page.y += height + gap }
        }
    }

    private static func drawMonthBars(_ counts: [Int], year: Int, on page: inout Page, locale: Locale) {
        let chartHeight: CGFloat = 90
        page.ensureRoom(for: chartHeight + 30)
        let most = max(1, counts.max() ?? 1)
        let slot = page.contentWidth / 12
        let cg = page.context.cgContext
        let top = page.y
        for (index, count) in counts.enumerated() {
            let barHeight = chartHeight * CGFloat(count) / CGFloat(most)
            let rect = CGRect(x: margin + CGFloat(index) * slot + slot * 0.2, y: top + chartHeight - barHeight,
                              width: slot * 0.6, height: barHeight)
            cg.setFillColor((count > 0 ? accent : line).cgColor)
            UIBezierPath(roundedRect: rect, cornerRadius: 3).fill()
            let monthDate = Calendar.current.date(from: DateComponents(year: year, month: index + 1, day: 1)) ?? Date()
            page.draw(monthDate.formatted(Date.FormatStyle().month(.narrow).locale(locale)),
                      at: CGPoint(x: margin + CGFloat(index) * slot, y: top + chartHeight + 4), width: slot,
                      font: .systemFont(ofSize: 9), color: muted, alignment: .center)
            if count > 0 {
                page.draw(String(count), at: CGPoint(x: margin + CGFloat(index) * slot, y: rect.minY - 12), width: slot,
                          font: .systemFont(ofSize: 9, weight: .semibold), color: ink, alignment: .center)
            }
        }
        page.y = top + chartHeight + 24
    }

    /// The month's sessions: a photo grid for those with a picture, a line
    /// each for the rest.
    private static func drawRuns(_ runs: [KitchenCookRun], document: CookYearbookDocument, on page: inout Page, locale: Locale) {
        let withPhoto = runs.filter { document.photos[$0.id] != nil }
        let without = runs.filter { document.photos[$0.id] == nil }
        let columns = 3
        let gap: CGFloat = 10
        let side = (page.contentWidth - gap * CGFloat(columns - 1)) / CGFloat(columns)
        let captionHeight: CGFloat = 34
        for (index, run) in withPhoto.enumerated() {
            if index % columns == 0 { page.ensureRoom(for: side + captionHeight + gap) }
            let x = margin + CGFloat(index % columns) * (side + gap)
            if let data = document.photos[run.id], let image = UIImage(data: data) {
                drawImage(image, in: CGRect(x: x, y: page.y, width: side, height: side), cornerRadius: 8)
            }
            page.draw(run.dishName, at: CGPoint(x: x, y: page.y + side + 3), width: side,
                      font: .systemFont(ofSize: 9, weight: .semibold), color: ink)
            page.draw(caption(run, locale: locale), at: CGPoint(x: x, y: page.y + side + 21), width: side,
                      font: .systemFont(ofSize: 8), color: muted)
            if index % columns == columns - 1 || index == withPhoto.count - 1 { page.y += side + captionHeight + gap }
        }
        for run in without {
            page.text(run.dishName + " – " + caption(run, locale: locale), font: .systemFont(ofSize: 10), color: ink)
        }
    }

    private static func caption(_ run: KitchenCookRun, locale: Locale) -> String {
        var parts = [run.startedAt.formatted(Date.FormatStyle(date: .abbreviated, time: .omitted, locale: locale))]
        if let rating = run.rating { parts.append(String(repeating: "★", count: rating)) }
        if !run.isManualEntry { parts.append(String(localized: "\((run.totalSeconds + 59) / 60) Min.")) }
        if run.relaxed == true { parts.append(String(localized: "entspannt")) }
        return parts.joined(separator: " · ")
    }

    private static func drawFavourite(_ favourite: KitchenYearbook.Favourite, facts: String,
                                      document: CookYearbookDocument, on page: inout Page) {
        let side: CGFloat = 72
        page.ensureRoom(for: side + 14)
        var textX = margin
        if let id = favourite.photoRunID, let data = document.photos[id], let image = UIImage(data: data) {
            drawImage(image, in: CGRect(x: margin, y: page.y, width: side, height: side), cornerRadius: 8)
            textX = margin + side + 12
        }
        let nameHeight = page.draw(favourite.name, at: CGPoint(x: textX, y: page.y + 4), width: page.contentWidth - (textX - margin),
                                   font: .systemFont(ofSize: 14, weight: .semibold), color: ink)
        page.draw(facts, at: CGPoint(x: textX, y: page.y + 4 + nameHeight + 2), width: page.contentWidth - (textX - margin),
                  font: .systemFont(ofSize: 10), color: muted)
        page.y += side + 14
    }

    /// One line, cut with an ellipsis where it would not fit.
    private static func drawLine(_ text: String, at point: CGPoint, width: CGFloat, font: UIFont, color: UIColor) {
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineBreakMode = .byTruncatingTail
        (text as NSString).draw(with: CGRect(x: point.x, y: point.y, width: width, height: font.lineHeight + 2),
                                options: [.usesLineFragmentOrigin],
                                attributes: [.font: font, .foregroundColor: color, .paragraphStyle: paragraph], context: nil)
    }

    /// Draws the image filling `rect`, cropped to the middle, with rounded corners.
    private static func drawImage(_ image: UIImage, in rect: CGRect, cornerRadius: CGFloat) {
        guard let cg = UIGraphicsGetCurrentContext() else { return }
        cg.saveGState()
        UIBezierPath(roundedRect: rect, cornerRadius: cornerRadius).addClip()
        let scale = max(rect.width / image.size.width, rect.height / image.size.height)
        let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        image.draw(in: CGRect(x: rect.midX - size.width / 2, y: rect.midY - size.height / 2, width: size.width, height: size.height))
        cg.restoreGState()
    }
}

/// The sheet behind "Kochjahr-Buch": year, name, what the book holds, share.
struct CookYearbookView: View {

    @Environment(\.dismiss) private var dismiss
    @AppStorage("yearbook.cookName") private var cookName = ""
    @State private var runLog = CookRunLog.shared
    @State private var years: [Int] = []
    @State private var year = Calendar.current.component(.year, from: Date())
    @State private var document: CookYearbookDocument?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    if years.isEmpty {
                        Text("Noch nichts gekocht – das Buch entsteht aus der Kochhistorie.")
                            .foregroundStyle(.secondary)
                    } else {
                        Picker("Jahr", selection: $year) {
                            ForEach(years, id: \.self) { year in
                                Text(verbatim: String(year)).tag(year)
                            }
                        }
                        .pickerStyle(.segmented)
                    }
                    TextField("Name auf dem Titelblatt", text: $cookName)
                        .textInputAutocapitalization(.words)
                } footer: {
                    Text("Das Buch nimmt alle Kochvorgänge des Jahres mit ihren Fotos, die Lieblingsgerichte und was die Uhr gelehrt hat.")
                }
                if let document, !document.book.isEmpty {
                    Section("Inhalt") {
                        LabeledContent("Gekocht", value: String(document.book.sessions))
                        LabeledContent("Kochtage", value: String(document.book.cookingDays))
                        LabeledContent("Fotos", value: String(document.photos.count))
                        LabeledContent("Lieblingsgerichte", value: String(document.book.favourites.count))
                    }
                    Section {
                        ShareLink(item: CookYearbookPDFExport(document: document),
                                  preview: SharePreview(Text(verbatim: document.title), image: Image(systemName: "book.closed"))) {
                            Label("Kochjahr-Buch teilen", systemImage: "square.and.arrow.up")
                        }
                    } footer: {
                        Text("Ein PDF im A4-Format – zum Drucken, Binden oder Verschicken.")
                    }
                }
            }
            .navigationTitle("Kochjahr-Buch")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Fertig") { dismiss() }
                }
            }
            .task {
                years = KitchenYearbook.years(of: runLog.runs)
                if let first = years.first, !years.contains(year) { year = first }
                rebuild()
            }
            .onChange(of: year) { _, _ in rebuild() }
            .onChange(of: cookName) { _, _ in rebuild() }
        }
    }

    private func rebuild() {
        guard years.contains(year) else {
            document = nil
            return
        }
        document = CookYearbookDocument.load(year: year, cookName: cookName, log: runLog)
    }
}
