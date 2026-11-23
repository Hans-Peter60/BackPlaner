//
//  PlanPDF.swift
//  CookPlanner
//
//  A dish's plan on paper (A4 PDF, to share or print): the header with the
//  verdict and — when a start time is given — start and finish; the
//  timeline as a chart, one row per component, every bar carrying its step
//  number; the steps as a table with their full text, minutes, station and
//  ingredients; and the ingredients by component. The words come from
//  KitchenPlanSheet in the package; this is the drawing, in the manner of
//  BakePlanner's recipe PDF.
//

import BakePlannerCore
import SwiftUI
import UIKit
import UniformTypeIdentifiers

/// What the share sheet gets; the PDF is drawn only when it asks.
struct PlanPDFExport: Transferable {
    let plan: DishPlan
    let start: Date?

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(exportedContentType: .pdf) { export in
            SentTransferredFile(try export.writeFile())
        }
        .suggestedFileName { "\(PlanPDFRenderer.fileName(for: $0.plan.dish.name)).pdf" }
    }

    func writeFile() throws -> URL {
        let folder = URL.temporaryDirectory.appendingPathComponent("Plan-" + UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let url = folder.appendingPathComponent(PlanPDFRenderer.fileName(for: plan.dish.name)).appendingPathExtension("pdf")
        try PlanPDFRenderer.render(plan, start: start).write(to: url, options: .atomic)
        return url
    }
}

enum PlanPDFRenderer {

    static let pageSize = CGSize(width: 595.2, height: 841.8)
    static let margin: CGFloat = 40
    static let ink = UIColor(red: 0.25, green: 0.15, blue: 0.06, alpha: 1)
    static let accent = UIColor(red: 0.58, green: 0.355, blue: 0.16, alpha: 1)
    static let muted = UIColor(red: 0.45, green: 0.30, blue: 0.16, alpha: 1)
    static let line = UIColor(red: 0.85, green: 0.78, blue: 0.68, alpha: 1)

    static func fileName(for title: String) -> String {
        let name = title.components(separatedBy: CharacterSet(charactersIn: "/\\:?*\"<>|")).joined(separator: "-")
        return name.isEmpty ? String(localized: "Ablaufplan") : String(name.prefix(80))
    }

    static func laneColor(_ index: Int, alpha: CGFloat = 1) -> UIColor {
        let rgb = PlanTimelineView.palette[index % PlanTimelineView.palette.count]
        return UIColor(red: rgb.red, green: rgb.green, blue: rgb.blue, alpha: alpha)
    }

    static func render(_ plan: DishPlan, start: Date?) -> Data {
        let sheet = KitchenPlanSheet(dish: plan.dish, schedule: plan.schedule, start: start)
        let layout = KitchenTimelineLayout(schedule: plan.schedule, components: plan.dish.components)
        let laneIndex = Dictionary(uniqueKeysWithValues: layout.lanes.enumerated().map { ($1.component, $0) })
        let format = UIGraphicsPDFRendererFormat()
        format.documentInfo = [kCGPDFContextTitle as String: sheet.title, kCGPDFContextCreator as String: "CookPlanner"]
        let renderer = UIGraphicsPDFRenderer(bounds: CGRect(origin: .zero, size: pageSize), format: format)
        return renderer.pdfData { context in
            var page = Page(context: context)
            page.begin()
            header(sheet, plan: plan, on: &page)
            timeline(layout, sheet: sheet, start: start, on: &page)
            steps(sheet, laneIndex: laneIndex, on: &page)
            ingredients(sheet, on: &page)
            page.finishFooter()
        }
    }

    // MARK: Header

    private static func header(_ sheet: KitchenPlanSheet, plan: DishPlan, on page: inout Page) {
        page.text(String(localized: "Ablaufplan"), font: .systemFont(ofSize: 11, weight: .semibold), color: accent)
        page.text(sheet.title, font: .systemFont(ofSize: 20, weight: .bold), color: ink)
        var facts: [String] = []
        if plan.fits {
            facts.append(String(localized: "Passt in \(plan.schedule.budget ?? plan.schedule.makespan) Minuten"))
        } else {
            facts.append(String(localized: "Fehlen \(plan.schedule.shortfall) Minuten"))
        }
        if let startText = sheet.startText, let finishText = sheet.finishText {
            facts.append(String(localized: "Start \(startText) · fertig \(finishText)"))
        } else {
            facts.append(String(localized: "Dauer \(sheet.minutes) Min., Zeiten ab Minute 0"))
        }
        if let servings = sheet.servings { facts.append(String(localized: "Für \(servings) Personen")) }
        page.text(facts.joined(separator: " · "), font: .systemFont(ofSize: 11), color: muted)
        page.y += 10
    }

    // MARK: Timeline

    private static func timeline(_ layout: KitchenTimelineLayout, sheet: KitchenPlanSheet, start: Date?, on page: inout Page) {
        let labelWidth: CGFloat = 92
        let chartX = margin + labelWidth
        let chartWidth = page.contentWidth - labelWidth
        let minutes = max(1, layout.makespan)
        let perMinute = chartWidth / CGFloat(minutes)
        let trackHeight: CGFloat = 15
        let laneHeights = layout.lanes.map { lane in CGFloat(max(1, lane.bars.map(\.tracks).max() ?? 1)) * trackHeight + 8 }
        let total = 22 + laneHeights.reduce(0, +) + 18
        page.heading(String(localized: "Zeitachse"))
        page.ensureRoom(for: total)
        let top = page.y
        let numbers = sheet.numbers
        let cg = page.context.cgContext

        // Minute lines and labels: every 5 minutes, every 10 for long plans.
        let step = minutes > 60 ? 10 : 5
        var tickFormat = Date.FormatStyle(date: .omitted, time: .shortened, locale: AppSettings.locale)
        tickFormat.timeZone = .current
        for minute in layout.ticks(every: step) {
            let x = chartX + CGFloat(minute) * perMinute
            cg.setStrokeColor(line.cgColor)
            cg.setLineWidth(minute % 15 == 0 ? 0.8 : 0.4)
            cg.move(to: CGPoint(x: x, y: top + 16))
            cg.addLine(to: CGPoint(x: x, y: top + 22 + laneHeights.reduce(0, +)))
            cg.strokePath()
            let label = start.map { $0.addingTimeInterval(TimeInterval(minute * 60)).formatted(tickFormat) } ?? "\(minute)′"
            page.draw(label, at: CGPoint(x: x - 20, y: top), width: 40, font: .systemFont(ofSize: 7.5), color: muted, alignment: .center)
        }
        var laneTop = top + 22
        for (index, lane) in layout.lanes.enumerated() {
            let height = laneHeights[index]
            let name = lane.component.isEmpty ? String(localized: "Ohne Komponente") : lane.component
            page.draw(name, at: CGPoint(x: margin, y: laneTop + 3), width: labelWidth - 6,
                      font: .systemFont(ofSize: 8.5, weight: .semibold), color: ink)
            for bar in lane.bars {
                let placement = bar.placement
                let x = chartX + CGFloat(placement.start) * perMinute
                let handsWidth = CGFloat(placement.handsEnd - placement.start) * perMinute
                let width = max(3, CGFloat(placement.end - placement.start) * perMinute)
                let y = laneTop + 4 + CGFloat(bar.track) * trackHeight
                let rect = CGRect(x: x, y: y, width: width - 1, height: trackHeight - 3)
                let path = UIBezierPath(roundedRect: rect, cornerRadius: 2.5)
                cg.saveGState()
                path.addClip()
                // The hands-on part: filled.
                let hands = min(max(0, handsWidth), rect.width)
                if hands > 0 {
                    laneColor(index, alpha: 0.75).setFill()
                    UIRectFill(CGRect(x: rect.minX, y: rect.minY, width: hands, height: rect.height))
                }
                // The part that runs on its own: light, with stripes, only there.
                let alone = CGRect(x: rect.minX + hands, y: rect.minY, width: rect.width - hands, height: rect.height)
                if alone.width > 0.5 {
                    cg.clip(to: alone)
                    laneColor(index, alpha: 0.18).setFill()
                    UIRectFill(alone)
                    cg.setStrokeColor(laneColor(index, alpha: 0.55).cgColor)
                    cg.setLineWidth(0.7)
                    var stripe = alone.minX - alone.height
                    while stripe < alone.maxX {
                        cg.move(to: CGPoint(x: stripe, y: alone.maxY))
                        cg.addLine(to: CGPoint(x: stripe + alone.height, y: alone.minY))
                        stripe += 4
                    }
                    cg.strokePath()
                }
                cg.restoreGState()
                laneColor(index).setStroke()
                path.lineWidth = 0.6
                path.stroke()
                // Every bar carries its number; a one-minute bar in smaller type,
                // allowed to reach a little past its edges.
                if let number = numbers[placement.id] {
                    let small = rect.width < 12
                    page.draw("\(number)", at: CGPoint(x: rect.midX - 8, y: rect.minY + (small ? 2 : 1)), width: 16,
                              font: .systemFont(ofSize: small ? 6.5 : 7.5, weight: .bold), color: ink, alignment: .center)
                }
            }
            laneTop += height
        }
        // The legend under the chart.
        let legendY = laneTop + 4
        laneColor(0, alpha: 0.75).setFill()
        UIRectFill(CGRect(x: chartX, y: legendY + 2, width: 12, height: 7))
        page.draw(String(localized: "Hände"), at: CGPoint(x: chartX + 16, y: legendY), width: 80, font: .systemFont(ofSize: 7.5), color: muted)
        laneColor(0, alpha: 0.18).setFill()
        UIRectFill(CGRect(x: chartX + 80, y: legendY + 2, width: 12, height: 7))
        page.draw(String(localized: "läuft allein"), at: CGPoint(x: chartX + 96, y: legendY), width: 120, font: .systemFont(ofSize: 7.5), color: muted)
        page.draw(String(localized: "Zahl = Schritt im Ablauf"), at: CGPoint(x: chartX + 200, y: legendY), width: 200, font: .systemFont(ofSize: 7.5), color: muted)
        page.y = legendY + 22
    }

    // MARK: Steps

    private static func steps(_ sheet: KitchenPlanSheet, laneIndex: [String: Int], on page: inout Page) {
        page.heading(String(localized: "Ablauf"))
        let numberWidth: CGFloat = 22
        let timeWidth: CGFloat = 70
        let textX = margin + numberWidth + timeWidth
        let textWidth = page.contentWidth - numberWidth - timeWidth
        for step in sheet.steps {
            var details: [String] = []
            if !step.component.isEmpty { details.append(step.component) }
            if step.handsMinutes > 0 { details.append(String(localized: "\(step.handsMinutes) Min. Hände")) }
            if step.unattendedMinutes > 0 { details.append(String(localized: "\(step.unattendedMinutes) Min. allein")) }
            if let temperature = step.ovenTemperature {
                details.append(String(localized: "Ofen \(temperature) °C"))
            } else if step.station == .burner {
                details.append(String(localized: "Herd"))
            } else if step.station == .oven {
                details.append(String(localized: "Ofen"))
            }
            let nameFont = UIFont.systemFont(ofSize: 11, weight: .semibold)
            let smallFont = UIFont.systemFont(ofSize: 9)
            let ingredientsText = step.ingredients.isEmpty ? nil
                : String(localized: "Zutaten: \(step.ingredients.joined(separator: " · "))")
            let height = Page.height(of: step.name, font: nameFont, width: textWidth)
                + Page.height(of: details.joined(separator: " · "), font: smallFont, width: textWidth)
                + (ingredientsText.map { Page.height(of: $0, font: smallFont, width: textWidth) } ?? 0) + 10
            page.ensureRoom(for: height)
            let rowTop = page.y
            // The number in the component's colour, as on the chart.
            let circle = CGRect(x: margin, y: rowTop + 1, width: 16, height: 16)
            laneColor(laneIndex[step.component] ?? 0, alpha: 0.75).setFill()
            UIBezierPath(ovalIn: circle).fill()
            page.draw("\(step.number)", at: CGPoint(x: circle.minX, y: circle.minY + 3), width: 16,
                      font: .systemFont(ofSize: 8, weight: .bold), color: .white, alignment: .center)
            page.draw("\(step.startText)–\(step.endText)", at: CGPoint(x: margin + numberWidth, y: rowTop + 1),
                      width: timeWidth - 4, font: .monospacedDigitSystemFont(ofSize: 9.5, weight: .medium), color: ink)
            var y = rowTop
            y += page.draw(step.name, at: CGPoint(x: textX, y: y), width: textWidth, font: nameFont, color: ink)
            y += page.draw(details.joined(separator: " · "), at: CGPoint(x: textX, y: y), width: textWidth, font: smallFont, color: muted)
            if let ingredientsText {
                y += page.draw(ingredientsText, at: CGPoint(x: textX, y: y), width: textWidth, font: smallFont, color: ink)
            }
            page.y = y + 6
            let cg = page.context.cgContext
            cg.setStrokeColor(line.cgColor)
            cg.setLineWidth(0.4)
            cg.move(to: CGPoint(x: margin, y: page.y - 3))
            cg.addLine(to: CGPoint(x: margin + page.contentWidth, y: page.y - 3))
            cg.strokePath()
        }
        page.y += 8
    }

    // MARK: Ingredients

    private static func ingredients(_ sheet: KitchenPlanSheet, on page: inout Page) {
        guard !sheet.ingredients.isEmpty else { return }
        page.heading(String(localized: "Zutaten"))
        for group in sheet.ingredients {
            page.ensureRoom(for: 30)
            page.text(group.component.isEmpty ? String(localized: "Ohne Komponente") : group.component,
                      font: .systemFont(ofSize: 10.5, weight: .semibold), color: ink)
            for line in group.lines {
                page.text("– " + line, font: .systemFont(ofSize: 10), color: ink, indent: 10)
            }
            page.y += 4
        }
    }

    // MARK: Page

    /// The page being drawn on; a new one begins when a block would not fit.
    struct Page {
        let context: UIGraphicsPDFRendererContext
        var y: CGFloat = 0
        var number = 0
        var contentWidth: CGFloat { pageSize.width - 2 * margin }
        private var bottom: CGFloat { pageSize.height - margin - 18 }

        init(context: UIGraphicsPDFRendererContext) { self.context = context }

        mutating func begin() {
            if number > 0 { finishFooter() }
            context.beginPage()
            number += 1
            y = margin
        }

        func finishFooter() {
            let text = String(localized: "Erstellt mit CookPlanner") + " · \(number)"
            let attributes: [NSAttributedString.Key: Any] = [.font: UIFont.systemFont(ofSize: 8), .foregroundColor: muted]
            let size = (text as NSString).size(withAttributes: attributes)
            (text as NSString).draw(at: CGPoint(x: pageSize.width - margin - size.width, y: pageSize.height - margin + 4),
                                    withAttributes: attributes)
        }

        mutating func ensureRoom(for height: CGFloat) {
            if y + height > bottom { begin() }
        }

        mutating func heading(_ text: String) {
            ensureRoom(for: 44)
            self.text(text, font: .systemFont(ofSize: 13, weight: .bold), color: accent)
            y += 4
        }

        mutating func text(_ text: String, font: UIFont, color: UIColor, indent: CGFloat = 0) {
            let height = Self.height(of: text, font: font, width: contentWidth - indent)
            ensureRoom(for: height)
            draw(text, at: CGPoint(x: margin + indent, y: y), width: contentWidth - indent, font: font, color: color)
            y += height + 2
        }

        /// Draws wrapped text and answers its height.
        @discardableResult
        func draw(_ text: String, at point: CGPoint, width: CGFloat, font: UIFont, color: UIColor,
                  alignment: NSTextAlignment = .left) -> CGFloat {
            let paragraph = NSMutableParagraphStyle()
            paragraph.alignment = alignment
            paragraph.lineBreakMode = .byWordWrapping
            let height = Self.height(of: text, font: font, width: width)
            (text as NSString).draw(with: CGRect(x: point.x, y: point.y, width: width, height: height),
                                    options: [.usesLineFragmentOrigin, .usesFontLeading],
                                    attributes: [.font: font, .foregroundColor: color, .paragraphStyle: paragraph],
                                    context: nil)
            return height + 1
        }

        static func height(of text: String, font: UIFont, width: CGFloat) -> CGFloat {
            guard !text.isEmpty else { return 0 }
            return ceil((text as NSString).boundingRect(with: CGSize(width: width, height: .greatestFiniteMagnitude),
                                                        options: [.usesLineFragmentOrigin, .usesFontLeading],
                                                        attributes: [.font: font], context: nil).height)
        }
    }
}

/// "Als PDF": with or without a start time, then the share sheet, which
/// also prints.
struct PlanPDFSheet: View {
    let plan: DishPlan
    @Environment(\.dismiss) private var dismiss
    @State private var withStart = false
    @State private var start = PlanPDFSheet.nextQuarterHour()

    static func nextQuarterHour(after date: Date = .now) -> Date {
        let calendar = Calendar.current
        let minute = calendar.component(.minute, from: date)
        let rounded = calendar.date(byAdding: .minute, value: (15 - minute % 15) % 15 + 15, to: date) ?? date
        return calendar.date(bySetting: .second, value: 0, of: rounded) ?? rounded
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Toggle("Mit Startzeit", isOn: $withStart.animation())
                    if withStart {
                        DatePicker("Start", selection: $start, displayedComponents: [.date, .hourAndMinute])
                        Text("Fertig um \(start.addingTimeInterval(TimeInterval(plan.schedule.makespan * 60)).formatted(date: .omitted, time: .shortened))")
                            .foregroundColor(.secondary)
                    }
                } footer: {
                    Text(withStart ? "Jeder Schritt steht mit seiner Uhrzeit im Plan."
                                   : "Ohne Startzeit zählen die Zeiten ab Minute 0.")
                }
                Section {
                    ShareLink(item: PlanPDFExport(plan: plan, start: withStart ? start : nil),
                              preview: SharePreview(Text(verbatim: plan.dish.name))) {
                        Label("PDF teilen oder drucken", systemImage: "printer")
                    }
                } footer: {
                    Text("Zeitachse, alle Schritte mit vollem Text und Zutaten, dazu die Zutaten je Komponente.")
                }
            }
            .navigationTitle("Ablaufplan als PDF")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Fertig") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}
