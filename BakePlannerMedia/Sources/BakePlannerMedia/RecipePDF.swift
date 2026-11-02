// The whole file is the transpiled implementation; in the bridging build
// Skip generates the native side from it.
#if !SKIP_BRIDGE
import Foundation
#if SKIP
import android.graphics.pdf.PdfDocument
#endif

/// A recipe as a printable PDF, the iPhone's RecipePDFRenderer drawn with
/// Android's PdfDocument: picture top right, name and summary, the facts
/// line, the components with their ingredients, the summed ingredients
/// and the steps as a three-column table, a footer on every page. The
/// native app describes the page as JSON (strings only, already in the
/// app's language), because a struct does not travel across the bridge:
///
///     { "name", "summary", "facts", "urlLink",
///       "componentsHeading", "totalsHeading", "stepsHeading", "footer",
///       "components": [{ "name", "lines": [] }],
///       "totalLines": [],
///       "steps": [{ "number", "text", "duration" }] }
public final class RecipePDF {

    /// Draws the page described by `json` with the picture `imageData`
    /// (JPEG or PNG, may be nil) and writes the PDF to `path`. Whether it
    /// worked. On Apple platforms nothing is drawn (the iPhone app has its
    /// own renderer).
    public static func write(json: String, imageData: Data?, toPath path: String) -> Bool {
        #if SKIP
        guard let data = json.data(using: String.Encoding.utf8),
              let parsed = try? JSONSerialization.jsonObject(with: data),
              let page = parsed as? [String: Any] else { return false }
        let sheet = Sheet(page: page, imageData: imageData)
        do {
            try sheet.draw()
            let file = java.io.File(path)
            file.parentFile?.mkdirs()
            let stream = java.io.FileOutputStream(file)
            sheet.document.writeTo(stream)
            stream.close()
            sheet.document.close()
            return true
        } catch {
            return false
        }
        #else
        return false
        #endif
    }

    #if SKIP
    /// Cursor-based page layout: text goes down the page, and a new page
    /// begins when the next block would not fit — the iPhone's `Page`.
    private final class Sheet {
        // A4 in points.
        static let pageWidth = 595
        static let pageHeight = 842
        static let margin: Float = Float(44)
        static let imageSide: Float = Float(130)

        static let ink = android.graphics.Color.rgb(64, 38, 15)
        static let accent = android.graphics.Color.rgb(148, 91, 41)
        static let muted = android.graphics.Color.rgb(115, 77, 41)

        let page: [String: Any]
        let imageData: Data?
        let document = PdfDocument()
        var current: PdfDocument.Page? = nil
        var canvas: android.graphics.Canvas? = nil
        var y: Float = Float(0)
        var number = 0

        var contentWidth: Float { Float(Self.pageWidth) - 2 * Self.margin }
        var bottom: Float { Float(Self.pageHeight) - Self.margin - Float(20) }

        init(page: [String: Any], imageData: Data?) {
            self.page = page
            self.imageData = imageData
        }

        func string(_ key: String) -> String {
            page[key] as? String ?? ""
        }

        func draw() throws {
            begin()
            // Header: picture on the right, name and summary on the left.
            let hasImage = imageData != nil
            let textWidth = contentWidth - (hasImage ? Self.imageSide + Float(16) : Float(0))
            if let imageData {
                drawImage(imageData, left: Float(Self.pageWidth) - Self.margin - Self.imageSide, top: y)
            }
            let headerStart = y
            drawText(string("name"), size: 24, bold: true, color: Self.ink, width: textWidth)
            y += Float(6)
            let summary = string("summary")
            if !summary.isEmpty {
                drawText(summary, size: 12, bold: false, color: Self.muted, width: textWidth)
                y += Float(6)
            }
            drawText(string("facts"), size: 11, bold: true, color: Self.accent, width: textWidth)
            let urlLink = string("urlLink")
            if !urlLink.isEmpty {
                y += Float(4)
                drawText(urlLink, size: 10, bold: false, color: Self.muted, width: textWidth)
            }
            if hasImage {
                y = max(y, headerStart + Self.imageSide)
            }
            y += Float(18)

            // Components, each as its own block.
            if let components = page["components"] as? [Any], !components.isEmpty {
                heading(string("componentsHeading"))
                for item in components {
                    guard let component = item as? [String: Any] else { continue }
                    ensureRoom(Float(40))
                    drawText(component["name"] as? String ?? "", size: 13, bold: true, color: Self.ink, width: contentWidth)
                    y += Float(2)
                    for line in component["lines"] as? [Any] ?? [] {
                        drawText(line as? String ?? "", size: 11, bold: false, color: Self.ink, width: contentWidth, indent: Float(8))
                    }
                    y += Float(10)
                }
            }

            // Summed ingredients.
            if let totals = page["totalLines"] as? [Any], !totals.isEmpty {
                heading(string("totalsHeading"))
                for line in totals {
                    drawText(line as? String ?? "", size: 11, bold: false, color: Self.ink, width: contentWidth, indent: Float(8))
                }
                y += Float(10)
            }

            // Steps as a three-column table.
            if let steps = page["steps"] as? [Any], !steps.isEmpty {
                heading(string("stepsHeading"))
                let numberWidth = Float(40)
                let durationWidth = Float(60)
                let stepWidth = contentWidth - numberWidth - durationWidth - Float(16)
                for item in steps {
                    guard let step = item as? [String: Any] else { continue }
                    let text = step["text"] as? String ?? ""
                    let height = Float(layout(text, size: 11, bold: false, color: Self.ink, width: stepWidth).height)
                    ensureRoom(height + Float(6))
                    let rowY = y
                    drawAt(step["number"] as? String ?? "", x: Self.margin, y: rowY, size: 11, bold: true, color: Self.accent, width: numberWidth)
                    drawAt(text, x: Self.margin + numberWidth + Float(8), y: rowY, size: 11, bold: false, color: Self.ink, width: stepWidth)
                    drawAt(step["duration"] as? String ?? "", x: Float(Self.pageWidth) - Self.margin - durationWidth, y: rowY,
                           size: 11, bold: false, color: Self.muted, width: durationWidth, alignRight: true)
                    y = rowY + height + Float(6)
                }
            }
            finish()
        }

        // MARK: Pages

        func begin() {
            if current != nil { finish() }
            number += 1
            let info = PdfDocument.PageInfo.Builder(Self.pageWidth, Self.pageHeight, number).create()
            let page = document.startPage(info)
            current = page
            canvas = page.canvas
            y = Self.margin
        }

        /// The footer, then the page is closed.
        func finish() {
            guard let page = current else { return }
            let text = string("footer") + " · " + String(number)
            let paint = paint(size: 9, bold: false, color: Self.muted)
            let width = paint.measureText(text)
            canvas?.drawText(text, Float(Self.pageWidth) - Self.margin - width, Float(Self.pageHeight) - Self.margin + Float(12), paint)
            document.finishPage(page)
            current = nil
            canvas = nil
        }

        func ensureRoom(_ height: Float) {
            if y + height > bottom { begin() }
        }

        func heading(_ text: String) {
            ensureRoom(Float(40))
            drawText(text, size: 15, bold: true, color: Self.accent, width: contentWidth)
            y += Float(6)
        }

        // MARK: Text

        func paint(size: Int, bold: Bool, color: Int) -> android.text.TextPaint {
            let paint = android.text.TextPaint()
            paint.isAntiAlias = true
            paint.textSize = Float(size)
            paint.color = color
            paint.typeface = bold ? android.graphics.Typeface.DEFAULT_BOLD : android.graphics.Typeface.DEFAULT
            return paint
        }

        func layout(_ text: String, size: Int, bold: Bool, color: Int, width: Float, alignRight: Bool = false) -> android.text.StaticLayout {
            let alignment = alignRight ? android.text.Layout.Alignment.ALIGN_OPPOSITE : android.text.Layout.Alignment.ALIGN_NORMAL
            return android.text.StaticLayout.Builder.obtain(text, 0, text.count, paint(size: size, bold: bold, color: color), Int(max(width, Float(1))))
                .setAlignment(alignment)
                .build()
        }

        /// Draws at the cursor and moves it down.
        func drawText(_ text: String, size: Int, bold: Bool, color: Int, width: Float, indent: Float = Float(0)) {
            let height = Float(layout(text, size: size, bold: bold, color: color, width: width - indent).height)
            ensureRoom(height)
            drawAt(text, x: Self.margin + indent, y: y, size: size, bold: bold, color: color, width: width - indent)
            y += height + Float(2)
        }

        func drawAt(_ text: String, x: Float, y: Float, size: Int, bold: Bool, color: Int, width: Float, alignRight: Bool = false) {
            guard let canvas else { return }
            let layout = layout(text, size: size, bold: bold, color: color, width: width, alignRight: alignRight)
            canvas.save()
            canvas.translate(x, y)
            layout.draw(canvas)
            canvas.restore()
        }

        // MARK: Picture

        /// The picture filling a rounded square, as the iPhone draws it.
        func drawImage(_ data: Data, left: Float, top: Float) {
            guard let canvas else { return }
            let bytes = data.platformValue
            guard let bitmap = android.graphics.BitmapFactory.decodeByteArray(bytes, 0, bytes.size) else { return }
            let side = Self.imageSide
            let frame = android.graphics.RectF(left, top, left + side, top + side)
            let scale = max(side / Float(bitmap.width), side / Float(bitmap.height))
            let drawWidth = Float(bitmap.width) * scale
            let drawHeight = Float(bitmap.height) * scale
            let target = android.graphics.RectF(left + (side - drawWidth) / 2, top + (side - drawHeight) / 2,
                                                left + (side + drawWidth) / 2, top + (side + drawHeight) / 2)
            let clip = android.graphics.Path()
            clip.addRoundRect(frame, Float(10), Float(10), android.graphics.Path.Direction.CW)
            canvas.save()
            canvas.clipPath(clip)
            let paint = android.graphics.Paint()
            paint.isFilterBitmap = true
            canvas.drawBitmap(bitmap, nil, target, paint)
            canvas.restore()
        }
    }
    #endif
}
#endif
