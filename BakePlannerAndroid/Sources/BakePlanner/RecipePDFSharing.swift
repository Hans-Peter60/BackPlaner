import BakePlannerCore
import BakePlannerMedia
import Foundation

/// A recipe as PDF for the system's share sheet, at the amount shown — the
/// iPhone's RecipePDFExport. The page's content is the package's
/// RecipePrintData, the same lines the recipe views show; the drawing is
/// done by BakePlannerMedia (Android's PdfDocument), which takes the page
/// as JSON of plain strings in the app's language.
enum RecipePDFSharing {

    /// Renders and shares; false when the PDF could not be written.
    static func share(_ data: RecipePrintData) -> Bool {
        let fileName = data.name
            .components(separatedBy: CharacterSet(charactersIn: "/\\:?*\"<>|"))
            .joined(separator: "-")
        let path = ContentFile.sharedFilePath(named: (fileName.isEmpty ? "Rezept" : fileName) + ".pdf")
        guard let json = pageJSON(for: data),
              RecipePDF.write(json: json, imageData: data.imageData, toPath: path) else { return false }
        return ContentFile.share(filePath: path, mimeType: "application/pdf")
    }

    /// The page as the renderer reads it (see RecipePDF).
    static func pageJSON(for data: RecipePrintData) -> String? {
        var facts = [String(localized: "Gesamtgewicht: \(String(data.totalWeight)) g", bundle: .module)]
        if !data.prepTime.isEmpty {
            facts.append(String(localized: "Bearbeitungsdauer: \(data.prepTime)", bundle: .module))
        }
        let page: [String: Any] = [
            "name": data.name,
            "summary": data.summary,
            "facts": facts.joined(separator: "   ·   "),
            "urlLink": data.urlLink ?? "",
            // The iPhone's keys with the colon would get the same catalog
            // symbols as the headings without it, which Xcode refuses; the
            // colon is added here.
            "componentsHeading": String(localized: "Komponenten", bundle: .module) + ":",
            "totalsHeading": String(localized: "Gesamtzutaten", bundle: .module) + ":",
            "stepsHeading": String(localized: "Verarbeitungsschritte", bundle: .module) + ":",
            "footer": String(localized: "Erstellt mit BakePlanner", bundle: .module),
            "components": data.components.map { ["name": $0.name, "lines": $0.lines] as [String: Any] },
            "totalLines": data.totalLines,
            "steps": data.steps.map { ["number": $0.number, "text": $0.text, "duration": $0.duration] },
        ]
        guard let encoded = try? JSONSerialization.data(withJSONObject: page) else { return nil }
        return String(decoding: encoded, as: UTF8.self)
    }
}
