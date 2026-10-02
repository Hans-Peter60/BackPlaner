//
//  RecipePDFExporter.swift
//  BackPlaner
//
//  Turns a recipe into a printable PDF — picture, components with their
//  ingredients, the summed ingredients, and the processing steps — for the
//  system share sheet. The same page comes out of the user's own recipes
//  and of public ones, at the serving size currently shown.
//

import SwiftUI
import UIKit
import UniformTypeIdentifiers

// MARK: - What goes on the page

/// A recipe flattened to strings, so the renderer knows neither Core Data
/// nor Firebase and the export can travel across threads.
struct RecipePrintData: Sendable {

    struct Component: Sendable {
        let name: String
        let lines: [String]
    }

    struct Step: Sendable {
        let number: String
        let text: String
        let duration: String
    }

    let name: String
    let summary: String
    let imageData: Data?
    let totalWeight: Int
    let prepTime: String
    let urlLink: String?
    let totalLines: [String]
    let components: [Component]
    let steps: [Step]

    /// One of the user's own recipes.
    init(recipe: Recipe, scale: Double) {
        name = recipe.name
        summary = recipe.summary
        imageData = recipe.image.isEmpty ? nil : recipe.image
        totalWeight = Int((recipe.totalWeight * scale).rounded())
        prepTime = Rational.displayHoursMinutes(recipe.prepTime)
        urlLink = recipe.urlLink.flatMap { $0.isEmpty ? nil : $0 }

        let columns = ComponentColumn.columns(of: recipe.componentsArray)
        components = Self.components(from: columns, scale: scale)
        totalLines = TotalIngredientsView.aggregatedLines(
            ingredients: columns.flatMap(\.ingredients),
            componentNames: columns.map(\.name),
            scale: scale
        )
        steps = recipe.instructionsArray.map {
            Step(number: Rational.decimalPlace($0.step, 10),
                 text: $0.instruction,
                 duration: Rational.displayHoursMinutes($0.duration))
        }
    }

    /// A recipe from the public database.
    init(recipeFB: RecipeFB, image: UIImage?, scale: Double) {
        name = recipeFB.name
        summary = recipeFB.summary
        imageData = image?.jpegData(compressionQuality: 0.8)
        totalWeight = Int((recipeFB.totalWeight * scale).rounded())
        prepTime = Rational.displayHoursMinutes(recipeFB.prepTime)
        urlLink = recipeFB.urlLink.isEmpty ? nil : recipeFB.urlLink

        let columns = ComponentColumn.columns(of: recipeFB.components)
        components = Self.components(from: columns, scale: scale)
        totalLines = TotalIngredientsView.aggregatedLines(
            ingredients: columns.flatMap(\.ingredients),
            componentNames: columns.map(\.name),
            scale: scale
        )
        steps = recipeFB.instructions
            .sorted { $0.step < $1.step }
            .map {
                Step(number: Rational.decimalPlace($0.step, 10),
                     text: $0.instruction,
                     duration: Rational.displayHoursMinutes($0.duration))
            }
    }

    private static func components(from columns: [ComponentColumn], scale: Double) -> [Component] {
        columns.map { column in
            Component(
                name: column.name,
                lines: column.ingredients.map { ingredient in
                    "• " + Rational.getPortion(unit: ingredient.unit,
                                               weight: ingredient.weight,
                                               num: ingredient.numerator,
                                               denom: ingredient.denominator,
                                               scale: scale)
                        + ingredient.name.trimmingCharacters(in: .whitespaces)
                }
            )
        }
    }
}

// MARK: - Share item

/// What `ShareLink` hands to the share sheet. The PDF is only rendered when
/// the user actually shares, not when the recipe screen appears.
struct RecipePDFExport: Transferable {

    let data: RecipePrintData

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(exportedContentType: .pdf) { export in
            SentTransferredFile(try RecipePDFRenderer.writePDF(for: export.data))
        }
    }
}

// MARK: - Rendering

enum RecipePDFRenderer {

    // A4 in points.
    private static let pageSize = CGSize(width: 595.2, height: 841.8)
    private static let margin: CGFloat = 44
    private static let imageSide: CGFloat = 130

    private static let ink = UIColor(red: 0.25, green: 0.15, blue: 0.06, alpha: 1)
    private static let accent = UIColor(red: 0.58, green: 0.355, blue: 0.16, alpha: 1)
    private static let muted = UIColor(red: 0.45, green: 0.30, blue: 0.16, alpha: 1)

    /// Renders the PDF into the temporary directory and returns its URL; the
    /// file is named after the recipe.
    static func writePDF(for data: RecipePrintData) throws -> URL {
        let pdf = render(data)
        let fileName = data.name
            .components(separatedBy: CharacterSet(charactersIn: "/\\:?*\"<>|"))
            .joined(separator: "-")
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(fileName.isEmpty ? "Rezept" : fileName)
            .appendingPathExtension("pdf")
        try pdf.write(to: url, options: .atomic)
        return url
    }

    static func render(_ data: RecipePrintData) -> Data {
        let format = UIGraphicsPDFRendererFormat()
        format.documentInfo = [
            kCGPDFContextTitle as String: data.name,
            kCGPDFContextCreator as String: "BakePlanner"
        ]
        let renderer = UIGraphicsPDFRenderer(bounds: CGRect(origin: .zero, size: pageSize), format: format)

        return renderer.pdfData { context in
            var page = Page(context: context)
            page.begin()

            // Header: picture on the right, name and summary on the left.
            let textWidth = pageSize.width - 2 * margin - (data.imageData == nil ? 0 : imageSide + 16)
            if let imageData = data.imageData, let image = UIImage(data: imageData) {
                let rect = CGRect(x: pageSize.width - margin - imageSide, y: page.y, width: imageSide, height: imageSide)
                drawAspectFill(image, in: rect, cornerRadius: 10)
            }
            let headerStart = page.y
            page.draw(data.name, font: .systemFont(ofSize: 24, weight: .bold), color: ink, width: textWidth)
            page.y += 6
            if !data.summary.isEmpty {
                page.draw(data.summary, font: .systemFont(ofSize: 12), color: muted, width: textWidth)
                page.y += 6
            }
            let weight = data.totalWeight.formatted(.number.locale(AppSettings.locale))
            var facts = [String(format: localized("Gesamtgewicht: %@ g"), weight)]
            if !data.prepTime.isEmpty {
                facts.append(String(format: localized("Bearbeitungsdauer: %@"), data.prepTime))
            }
            page.draw(facts.joined(separator: "   ·   "), font: .systemFont(ofSize: 11, weight: .semibold), color: accent, width: textWidth)
            if let urlLink = data.urlLink {
                page.y += 4
                page.draw(urlLink, font: .systemFont(ofSize: 10), color: muted, width: textWidth)
            }
            if data.imageData != nil {
                page.y = max(page.y, headerStart + imageSide)
            }
            page.y += 18

            // Components, each as its own block.
            if !data.components.isEmpty {
                page.heading(localized("Komponenten:"))
                for component in data.components {
                    page.ensureRoom(for: 40)
                    page.draw(component.name, font: .systemFont(ofSize: 13, weight: .semibold), color: ink, width: page.contentWidth)
                    page.y += 2
                    for line in component.lines {
                        page.draw(line, font: .systemFont(ofSize: 11), color: ink, width: page.contentWidth, indent: 8)
                    }
                    page.y += 10
                }
            }

            // Summed ingredients.
            if !data.totalLines.isEmpty {
                page.heading(localized("Gesamtzutaten:"))
                for line in data.totalLines {
                    page.draw(line, font: .systemFont(ofSize: 11), color: ink, width: page.contentWidth, indent: 8)
                }
                page.y += 10
            }

            // Steps as a three-column table.
            if !data.steps.isEmpty {
                page.heading(localized("Verarbeitungsschritte:"))
                let numberWidth: CGFloat = 40
                let durationWidth: CGFloat = 60
                let textWidth = page.contentWidth - numberWidth - durationWidth - 16
                for step in data.steps {
                    let height = Page.height(of: step.text, font: .systemFont(ofSize: 11), width: textWidth)
                    page.ensureRoom(for: height + 6)
                    let rowY = page.y
                    page.drawAt(step.number, x: margin, y: rowY, font: .systemFont(ofSize: 11, weight: .semibold), color: accent, width: numberWidth)
                    page.drawAt(step.text, x: margin + numberWidth + 8, y: rowY, font: .systemFont(ofSize: 11), color: ink, width: textWidth)
                    page.drawAt(step.duration, x: pageSize.width - margin - durationWidth, y: rowY, font: .systemFont(ofSize: 11), color: muted, width: durationWidth, alignment: .right)
                    page.y = rowY + height + 6
                }
            }

            page.finishFooter()
        }
    }

    private static func localized(_ key: String) -> String {
        String(localized: String.LocalizationValue(key), bundle: AppSettings.localizationBundle, locale: AppSettings.locale)
    }

    private static func drawAspectFill(_ image: UIImage, in rect: CGRect, cornerRadius: CGFloat) {
        guard let context = UIGraphicsGetCurrentContext() else { return }
        context.saveGState()
        UIBezierPath(roundedRect: rect, cornerRadius: cornerRadius).addClip()
        let scale = max(rect.width / image.size.width, rect.height / image.size.height)
        let drawSize = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        let origin = CGPoint(x: rect.midX - drawSize.width / 2, y: rect.midY - drawSize.height / 2)
        image.draw(in: CGRect(origin: origin, size: drawSize))
        context.restoreGState()
    }

    /// Cursor-based page layout: text goes down the page, and a new page
    /// begins when the next block would not fit.
    private struct Page {
        let context: UIGraphicsPDFRendererContext
        var y: CGFloat = 0
        var number = 0

        var contentWidth: CGFloat { pageSize.width - 2 * margin }
        private var bottom: CGFloat { pageSize.height - margin - 20 }

        init(context: UIGraphicsPDFRendererContext) {
            self.context = context
        }

        mutating func begin() {
            if number > 0 { finishFooter() }
            context.beginPage()
            number += 1
            y = margin
        }

        func finishFooter() {
            let text = String(format: "%@ · %d", localized("Erstellt mit BakePlanner"), number)
            let attributes: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 9),
                .foregroundColor: muted
            ]
            let size = (text as NSString).size(withAttributes: attributes)
            (text as NSString).draw(
                at: CGPoint(x: pageSize.width - margin - size.width, y: pageSize.height - margin + 4),
                withAttributes: attributes
            )
        }

        mutating func ensureRoom(for height: CGFloat) {
            if y + height > bottom { begin() }
        }

        mutating func heading(_ text: String) {
            ensureRoom(for: 40)
            draw(text, font: .systemFont(ofSize: 15, weight: .bold), color: accent, width: contentWidth)
            y += 6
        }

        mutating func draw(_ text: String, font: UIFont, color: UIColor, width: CGFloat, indent: CGFloat = 0) {
            let height = Self.height(of: text, font: font, width: width - indent)
            ensureRoom(for: height)
            drawAt(text, x: margin + indent, y: y, font: font, color: color, width: width - indent)
            y += height + 2
        }

        func drawAt(_ text: String, x: CGFloat, y: CGFloat, font: UIFont, color: UIColor, width: CGFloat,
                    alignment: NSTextAlignment = .left) {
            let paragraph = NSMutableParagraphStyle()
            paragraph.alignment = alignment
            paragraph.lineBreakMode = .byWordWrapping
            let attributes: [NSAttributedString.Key: Any] = [
                .font: font, .foregroundColor: color, .paragraphStyle: paragraph
            ]
            let height = Self.height(of: text, font: font, width: width)
            (text as NSString).draw(
                with: CGRect(x: x, y: y, width: width, height: height),
                options: [.usesLineFragmentOrigin, .usesFontLeading],
                attributes: attributes,
                context: nil
            )
        }

        static func height(of text: String, font: UIFont, width: CGFloat) -> CGFloat {
            let rect = (text as NSString).boundingRect(
                with: CGSize(width: width, height: .greatestFiniteMagnitude),
                options: [.usesLineFragmentOrigin, .usesFontLeading],
                attributes: [.font: font],
                context: nil
            )
            return ceil(rect.height)
        }
    }
}
