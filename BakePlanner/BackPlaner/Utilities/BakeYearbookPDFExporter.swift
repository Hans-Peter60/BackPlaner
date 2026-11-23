//
//  BakeYearbookPDFExporter.swift
//  BackPlaner
//
//  "Mein Backjahr": a year of the bake history as a PDF book — cover, the
//  year in figures, every month with its photos, the favourite recipes as
//  recipe pages, what the facts taught, the starter's year, and a page for
//  next year's resolutions. The sums are BakeYearbook in the package; the
//  pages reuse the recipe PDF's layout.
//

import BakePlannerCore
import CoreData
import SwiftUI
import UIKit
import UniformTypeIdentifiers

/// Everything the renderer needs, gathered from Core Data before the share
/// sheet asks for the file.
struct BakeYearbookDocument {
    let book: BakeYearbook
    /// The name on the cover; empty for none.
    let bakerName: String
    /// The first photo of every bake with one, by the entry's photo key,
    /// already made small for print.
    let photos: [String: Data]
    /// The favourite recipes as print data, by name.
    let recipes: [String: RecipePrintData]
    /// The recipes' own pictures, by name — the cover and a favourite
    /// without a bake photo fall back to them.
    let recipePictures: [String: Data]

    static let photoPixels = 900

    var title: String {
        String(format: RecipePDFRenderer.localized("Mein Backjahr %@"), String(book.year))
    }

    /// Reads the year's bakes and feedings from `context`.
    static func load(year: Int, bakerName: String, in context: NSManagedObjectContext) -> BakeYearbookDocument {
        let calendar = Calendar.current
        let start = calendar.date(from: DateComponents(year: year, month: 1, day: 1)) ?? Date()
        let end = calendar.date(from: DateComponents(year: year + 1, month: 1, day: 1)) ?? Date()

        let request = BakeHistory.fetchRequest()
        request.predicate = NSPredicate(format: "recipe != nil AND date >= %@ AND date < %@", start as NSDate, end as NSDate)
        request.sortDescriptors = [NSSortDescriptor(key: "date", ascending: true)]
        let histories = (try? context.fetch(request)) ?? []

        var entries: [BakeYearbook.Entry] = []
        var photos: [String: Data] = [:]
        var contents: [String: RecipeExportData] = [:]
        var pictures: [String: Data] = [:]
        for history in histories {
            guard let recipe = history.recipe else { continue }
            let content: RecipeExportData
            if let known = contents[recipe.name] {
                content = known
            } else {
                content = RecipeExportData(recipe: recipe, includingImage: false)
                contents[recipe.name] = content
                if !recipe.image.isEmpty, let small = RecipeThumbnails.downsampled(recipe.image, maxPixelSize: photoPixels)?.jpegData(compressionQuality: 0.8) {
                    pictures[recipe.name] = small
                }
            }
            let key = history.objectID.uriRepresentation().absoluteString
            let images = history.images ?? []
            if let first = images.first,
               let small = RecipeThumbnails.downsampled(first, maxPixelSize: photoPixels)?.jpegData(compressionQuality: 0.8) {
                photos[key] = small
            }
            let flour = DoughComposition.compute(DoughComposition.components(of: content))?.flour ?? 0
            entries.append(BakeYearbook.Entry(
                recipeName: recipe.name, date: history.date, facts: history.facts, comment: history.comment,
                photoCount: images.count, photoKey: key, flourGrams: flour, doughGrams: content.totalWeight,
                durationMinutes: RecurringBakePlanner.planDuration(of: content)))
        }

        let feedingRequest = StarterFeedingLog.fetchRequest()
        feedingRequest.predicate = NSPredicate(format: "recipe != nil AND date >= %@ AND date < %@", start as NSDate, end as NSDate)
        let feedings = ((try? context.fetch(feedingRequest)) ?? []).compactMap { log -> BakeYearbook.Feeding? in
            guard let recipe = log.recipe else { return nil }
            return BakeYearbook.Feeding(starterName: recipe.name, date: log.date, peakMinutes: log.peakMinutes?.intValue)
        }

        let book = BakeYearbook.compute(year: year, entries: entries, feedings: feedings)
        var recipes: [String: RecipePrintData] = [:]
        for favourite in book.favourites {
            if let content = contents[favourite.name] {
                recipes[favourite.name] = RecipePrintData(data: content, scale: 1)
            }
        }
        return BakeYearbookDocument(book: book, bakerName: bakerName.trimmingCharacters(in: .whitespacesAndNewlines),
                                    photos: photos, recipes: recipes, recipePictures: pictures)
    }

    /// The years with a finished bake, newest first.
    static func availableYears(in context: NSManagedObjectContext) -> [Int] {
        let request = BakeHistory.fetchRequest()
        request.predicate = NSPredicate(format: "recipe != nil")
        let dates = ((try? context.fetch(request)) ?? []).map(\.date)
        return BakeYearbook.years(of: dates)
    }
}

/// What the share sheet gets; rendered only when the file is asked for.
struct BakeYearbookPDFExport: FileExport {
    let document: BakeYearbookDocument

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(exportedContentType: .pdf) { export in
            SentTransferredFile(try export.writeFile())
        }
        .suggestedFileName { "\(RecipePDFRenderer.fileName(for: $0.document.title)).pdf" }
    }

    func writeFile() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(RecipePDFRenderer.fileName(for: document.title))
            .appendingPathExtension("pdf")
        try RecipePDFRenderer.render(document).write(to: url, options: .atomic)
        return url
    }
}

extension RecipePDFRenderer {

    static func render(_ document: BakeYearbookDocument) -> Data {
        let format = UIGraphicsPDFRendererFormat()
        format.documentInfo = [
            kCGPDFContextTitle as String: document.title,
            kCGPDFContextCreator as String: "BakePlanner"
        ]
        let renderer = UIGraphicsPDFRenderer(bounds: CGRect(origin: .zero, size: pageSize), format: format)
        let book = document.book
        let locale = AppSettings.locale

        return renderer.pdfData { context in
            var page = Page(context: context)

            // Cover.
            page.begin()
            drawCover(document, on: &page)

            // The year in figures.
            page.begin()
            page.draw(localized("Das Jahr in Zahlen"), font: .systemFont(ofSize: 24, weight: .bold), color: ink, width: page.contentWidth)
            page.y += 14
            var tiles: [(String, String)] = [
                (localized("Brote"), String(book.bakes)),
                (localized("Backtage"), String(book.bakingDays)),
                (localized("Mehl verbacken"), kilograms(book.flourKilograms, locale: locale)),
                (localized("Teig geknetet"), kilograms(book.doughKilograms, locale: locale)),
            ]
            if let average = book.averageRating {
                tiles.append((localized("Ø Bewertung"), average.formatted(.number.precision(.fractionLength(1)).locale(locale)) + " ★"))
            }
            if let flour = book.favouriteFlour {
                tiles.append((localized("Lieblingsmehl"), flour))
            }
            if let longest = book.longestBake {
                tiles.append((localized("Längstes Brot"), longest.name + " · " + Rational.displayHoursMinutes(longest.minutes)))
            }
            drawTiles(tiles, on: &page)
            page.y += 18
            page.heading(localized("Brote je Monat"))
            drawMonthBars(book.monthCounts, year: book.year, on: &page, locale: locale)

            // Month by month.
            for month in book.months {
                page.begin()
                let title = month.start.formatted(Date.FormatStyle().month(.wide).year().locale(locale))
                page.draw(title, font: .systemFont(ofSize: 24, weight: .bold), color: ink, width: page.contentWidth)
                page.draw(String(format: localized("%@ Brote"), String(month.entries.count)),
                          font: .systemFont(ofSize: 11), color: muted, width: page.contentWidth)
                page.y += 12
                drawBakes(month.entries, document: document, on: &page, locale: locale)
            }

            // The favourites, as recipe pages.
            for favourite in book.favourites {
                guard let recipe = document.recipes[favourite.name] else { continue }
                page.begin()
                var facts: [String] = [String(format: localized("%@× gebacken"), String(favourite.count))]
                if let rating = favourite.averageRating {
                    facts.append(rating.formatted(.number.precision(.fractionLength(1)).locale(locale)) + " ★")
                }
                if let room = favourite.averageRoomTemperature {
                    facts.append(String(format: localized("Ø Raumtemperatur %@ °C"), room.formatted(.number.precision(.fractionLength(0...1)).locale(locale))))
                }
                if let proof = favourite.averageFinalProofMinutes {
                    facts.append(String(format: localized("Ø Stückgare %@"), Rational.displayHoursMinutes(proof)))
                }
                page.draw(localized("Lieblingsrezept") + " · " + facts.joined(separator: " · "),
                          font: .systemFont(ofSize: 10, weight: .semibold), color: accent, width: page.contentWidth)
                page.y += 8
                // The best bake photo of the year instead of the recipe's picture, when there is one.
                var data = recipe
                if let key = favourite.photoKey, let photo = document.photos[key] {
                    data = RecipePrintData(copying: recipe, imageData: photo)
                } else if data.imageData == nil, let picture = document.recipePictures[favourite.name] {
                    data = RecipePrintData(copying: recipe, imageData: picture)
                }
                draw(data, on: &page)
            }

            // What the facts taught.
            if !book.outcomes.isEmpty || !book.proofLessons.isEmpty {
                page.begin()
                page.draw(localized("Gelernt"), font: .systemFont(ofSize: 24, weight: .bold), color: ink, width: page.contentWidth)
                page.y += 14
                if !book.proofLessons.isEmpty {
                    page.heading(localized("Stückgare und Raumtemperatur"))
                    for lesson in book.proofLessons {
                        page.draw(String(format: localized("Bei %@ bis %@ °C: Stückgare im Mittel %@ (%@ Backvorgänge)"),
                                         String(lesson.lowerTemperature), String(lesson.upperTemperature),
                                         Rational.displayHoursMinutes(lesson.medianFinalProofMinutes), String(lesson.bakes)),
                                  font: .systemFont(ofSize: 12), color: ink, width: page.contentWidth)
                    }
                    page.y += 14
                }
                if !book.outcomes.isEmpty {
                    page.heading(localized("Krume und Ofentrieb"))
                    let most = max(1, book.outcomes.map(\.count).max() ?? 1)
                    for outcome in book.outcomes {
                        drawBarRow(label: outcome.keyword, value: outcome.count, maximum: most, on: &page)
                    }
                }
            }

            // The starter's year.
            if let starter = book.starter {
                page.ensureRoom(for: 140)
                page.y += 10
                page.heading(localized("Anstellgut"))
                var lines = [String(format: localized("%@ Fütterungen von %@ Anstellgut"), String(starter.feedings), String(starter.starters))]
                if let pause = starter.longestPauseDays {
                    lines.append(String(format: localized("Längste Pause: %@ Tage"), String(pause)))
                }
                if let winter = starter.averagePeakMinutesWinter {
                    lines.append(String(format: localized("Reifezeit im Winterhalbjahr: %@"), Rational.displayHoursMinutes(winter)))
                }
                if let summer = starter.averagePeakMinutesSummer {
                    lines.append(String(format: localized("Reifezeit im Sommer: %@"), Rational.displayHoursMinutes(summer)))
                }
                for line in lines {
                    page.draw(line, font: .systemFont(ofSize: 12), color: ink, width: page.contentWidth)
                }
            }

            // Resolutions.
            page.begin()
            page.draw(String(format: localized("Vorsätze für %@"), String(book.year + 1)),
                      font: .systemFont(ofSize: 24, weight: .bold), color: ink, width: page.contentWidth)
            page.y += 24
            guard let cg = UIGraphicsGetCurrentContext() else { return }
            cg.setStrokeColor(muted.withAlphaComponent(0.35).cgColor)
            cg.setLineWidth(0.6)
            var lineY = page.y + 20
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

    private static func drawCover(_ document: BakeYearbookDocument, on page: inout Page) {
        guard let cg = UIGraphicsGetCurrentContext() else { return }
        cg.setFillColor(paper.cgColor)
        cg.fill(CGRect(origin: .zero, size: pageSize))

        let photo = document.book.coverPhotoKey.flatMap { document.photos[$0] }
            ?? document.book.favourites.first.flatMap { document.recipePictures[$0.name] }
        let photoRect = CGRect(x: margin, y: margin + 150, width: pageSize.width - 2 * margin, height: 360)
        if let photo, let image = UIImage(data: photo) {
            drawAspectFill(image, in: photoRect, cornerRadius: 18)
        } else {
            cg.setFillColor(accent.withAlphaComponent(0.12).cgColor)
            UIBezierPath(roundedRect: photoRect, cornerRadius: 18).fill()
        }

        page.y = margin + 30
        page.draw(document.title, font: .systemFont(ofSize: 36, weight: .bold), color: ink, width: page.contentWidth)
        page.y += 4
        let book = document.book
        let subtitle = String(format: localized("%@ Brote an %@ Backtagen"), String(book.bakes), String(book.bakingDays))
        page.draw(subtitle, font: .systemFont(ofSize: 14), color: accent, width: page.contentWidth)

        page.y = photoRect.maxY + 24
        if !document.bakerName.isEmpty {
            page.draw(document.bakerName, font: .systemFont(ofSize: 18, weight: .semibold), color: ink, width: page.contentWidth)
        }
        if let favourite = book.favourites.first {
            page.draw(String(format: localized("Meistgebacken: %@"), favourite.name),
                      font: .systemFont(ofSize: 12), color: muted, width: page.contentWidth)
        }
        page.finishFooter()
    }

    /// Two tiles a row: the label small above the figure.
    private static func drawTiles(_ tiles: [(String, String)], on page: inout Page) {
        let gap: CGFloat = 12
        let width = (page.contentWidth - gap) / 2
        let height: CGFloat = 64
        guard let cg = UIGraphicsGetCurrentContext() else { return }
        for (index, tile) in tiles.enumerated() {
            if index % 2 == 0 { page.ensureRoom(for: height + gap) }
            let x = margin + CGFloat(index % 2) * (width + gap)
            let rect = CGRect(x: x, y: page.y, width: width, height: height)
            cg.setFillColor(paper.cgColor)
            UIBezierPath(roundedRect: rect, cornerRadius: 12).fill()
            page.drawAt(tile.0, x: rect.minX + 12, y: rect.minY + 10, font: .systemFont(ofSize: 10), color: muted, width: width - 24)
            page.drawAt(tile.1, x: rect.minX + 12, y: rect.minY + 28, font: .systemFont(ofSize: 20, weight: .bold), color: ink, width: width - 24)
            if index % 2 == 1 || index == tiles.count - 1 {
                page.y += height + gap
            }
        }
    }

    /// Twelve bars, January first, the count above and the month letter below.
    private static func drawMonthBars(_ counts: [Int], year: Int, on page: inout Page, locale: Locale) {
        guard let cg = UIGraphicsGetCurrentContext() else { return }
        let height: CGFloat = 120
        let labelRoom: CGFloat = 16
        page.ensureRoom(for: height + labelRoom + 40)
        let most = max(1, counts.max() ?? 1)
        let gap: CGFloat = 8
        let barWidth = (page.contentWidth - 11 * gap) / 12
        let baseline = page.y + labelRoom + height
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.setLocalizedDateFormatFromTemplate("MMMMM")
        for (index, count) in counts.enumerated() {
            let x = margin + CGFloat(index) * (barWidth + gap)
            let barHeight = max(3, height * CGFloat(count) / CGFloat(most))
            cg.setFillColor((count > 0 ? accent : paper).cgColor)
            UIBezierPath(roundedRect: CGRect(x: x, y: baseline - barHeight, width: barWidth, height: barHeight), cornerRadius: 3).fill()
            if count > 0 {
                page.drawAt(String(count), x: x, y: baseline - barHeight - 14, font: .systemFont(ofSize: 9), color: muted, width: barWidth, alignment: .center)
            }
            if let month = Calendar.current.date(from: DateComponents(year: year, month: index + 1, day: 1)) {
                page.drawAt(formatter.string(from: month), x: x, y: baseline + 4, font: .systemFont(ofSize: 9), color: muted, width: barWidth, alignment: .center)
            }
        }
        page.y = baseline + 24
    }

    /// The bakes of a month: photos three to a row with a caption, the
    /// bakes without a photo as lines below.
    private static func drawBakes(_ entries: [BakeYearbook.Entry], document: BakeYearbookDocument, on page: inout Page, locale: Locale) {
        let gap: CGFloat = 10
        let side = (page.contentWidth - 2 * gap) / 3
        let captionHeight: CGFloat = 34
        let withPhoto = entries.filter { document.photos[$0.photoKey] != nil }
        let withoutPhoto = entries.filter { document.photos[$0.photoKey] == nil }

        var column = 0
        for entry in withPhoto {
            if column == 0 { page.ensureRoom(for: side + captionHeight + gap) }
            let x = margin + CGFloat(column) * (side + gap)
            if let data = document.photos[entry.photoKey], let image = UIImage(data: data) {
                drawAspectFill(image, in: CGRect(x: x, y: page.y, width: side, height: side), cornerRadius: 10)
            }
            page.drawAt(caption(entry, locale: locale), x: x, y: page.y + side + 3, font: .systemFont(ofSize: 9), color: ink, width: side)
            column += 1
            if column == 3 {
                column = 0
                page.y += side + captionHeight + gap
            }
        }
        if column > 0 { page.y += side + captionHeight + gap }

        for entry in withoutPhoto {
            page.draw(caption(entry, locale: locale), font: .systemFont(ofSize: 11), color: ink, width: page.contentWidth)
        }
    }

    /// "12.01. · Landbrot · ★★★★ · offen" and the comment's first line.
    private static func caption(_ entry: BakeYearbook.Entry, locale: Locale) -> String {
        var parts = [entry.date.formatted(Date.FormatStyle().day().month(.twoDigits).locale(locale)), entry.recipeName]
        if let rating = entry.facts.rating, rating > 0 {
            parts.append(String(repeating: "★", count: min(rating, BakeHistoryFacts.maximumRating)))
        }
        if !entry.facts.outcome.isEmpty { parts.append(entry.facts.outcome) }
        var text = parts.joined(separator: " · ")
        let comment = entry.comment.trimmingCharacters(in: .whitespacesAndNewlines)
        if !comment.isEmpty, !BakeHistoryFacts.isPlaceholderComment(comment) {
            text += "\n" + comment.split(separator: "\n").first.map(String.init)!
        }
        return text
    }

    private static func drawBarRow(label: String, value: Int, maximum: Int, on page: inout Page) {
        guard let cg = UIGraphicsGetCurrentContext() else { return }
        page.ensureRoom(for: 22)
        let labelWidth: CGFloat = 150
        page.drawAt(label, x: margin, y: page.y, font: .systemFont(ofSize: 11), color: ink, width: labelWidth)
        let barMax = page.contentWidth - labelWidth - 40
        let barWidth = max(6, barMax * CGFloat(value) / CGFloat(maximum))
        cg.setFillColor(accent.cgColor)
        UIBezierPath(roundedRect: CGRect(x: margin + labelWidth, y: page.y + 2, width: barWidth, height: 10), cornerRadius: 3).fill()
        page.drawAt(String(value), x: margin + labelWidth + barWidth + 6, y: page.y, font: .systemFont(ofSize: 11), color: muted, width: 30)
        page.y += 20
    }

    private static func kilograms(_ value: Double, locale: Locale) -> String {
        value.formatted(.number.precision(.fractionLength(0...1)).locale(locale)) + " kg"
    }
}
