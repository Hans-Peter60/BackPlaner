// The whole file is the transpiled implementation; in the bridging build
// Skip generates the native side from it.
#if !SKIP_BRIDGE
import Foundation
#if SKIP
import android.graphics.pdf.PdfDocument
#endif

/// A document of A4 pages drawn from a list of blocks, top to bottom, a
/// new page when the next block would not fit — the iPhone's
/// PlanPDFRenderer.Page, for the plan and the yearbook. The native app
/// describes the document as JSON of plain strings in the app's language
/// (a struct does not travel across the bridge); pictures are JPEG files
/// it has written, by path:
///
///     { "footer": "…",
///       "blocks": [
///         { "kind": "caption" | "title" | "meta" | "heading" | "text" | "small", "text": "…", "indent": 0/1 },
///         { "kind": "step", "number": "1", "time": "18:00–18:02", "text": "…", "details": "…", "ingredients": "…" },
///         { "kind": "photos", "paths": ["…", …], "captions": ["…", …] },
///         { "kind": "lines", "count": 12 },
///         { "kind": "space", "height": 12 },
///         { "kind": "page" } ] }
public final class BlockPDF {

    /// Draws the document described by `json` and writes it to `path`.
    /// Whether it worked. On Apple platforms nothing is drawn.
    public static func write(json: String, toPath path: String) -> Bool {
        #if SKIP
        guard let data = json.data(using: String.Encoding.utf8),
              let parsed = try? JSONSerialization.jsonObject(with: data),
              let document = parsed as? [String: Any] else { return false }
        let sheet = Sheet(document: document)
        do {
            try sheet.draw()
            let file = java.io.File(path)
            file.parentFile?.mkdirs()
            let stream = java.io.FileOutputStream(file)
            sheet.pdf.writeTo(stream)
            stream.close()
            sheet.pdf.close()
            return true
        } catch {
            return false
        }
        #else
        return false
        #endif
    }

    #if SKIP
    private final class Sheet {
        static let pageWidth = 595
        static let pageHeight = 842
        static let margin: Float = Float(44)

        static let ink = android.graphics.Color.rgb(64, 38, 15)
        static let accent = android.graphics.Color.rgb(148, 91, 41)
        static let muted = android.graphics.Color.rgb(115, 77, 41)
        static let rule = android.graphics.Color.rgb(222, 205, 180)

        let document: [String: Any]
        let pdf = PdfDocument()
        var current: PdfDocument.Page? = nil
        var canvas: android.graphics.Canvas? = nil
        var y: Float = Float(0)
        var number = 0

        var contentWidth: Float { Float(Self.pageWidth) - 2 * Self.margin }
        var bottom: Float { Float(Self.pageHeight) - Self.margin - Float(20) }

        init(document: [String: Any]) {
            self.document = document
        }

        func draw() throws {
            begin()
            for item in document["blocks"] as? [Any] ?? [] {
                guard let block = item as? [String: Any] else { continue }
                let kind = block["kind"] as? String ?? ""
                let text = block["text"] as? String ?? ""
                let indent = (block["indent"] as? Int ?? 0) > 0 ? Float(12) : Float(0)
                switch kind {
                case "caption": drawText(text, size: 11, bold: true, color: Self.accent, indent: indent)
                case "title":
                    drawText(text, size: 22, bold: true, color: Self.ink, indent: indent)
                    y += Float(2)
                case "meta":
                    drawText(text, size: 11, bold: false, color: Self.muted, indent: indent)
                    y += Float(8)
                case "heading":
                    ensureRoom(Float(44))
                    y += Float(6)
                    drawText(text, size: 15, bold: true, color: Self.accent, indent: indent)
                    y += Float(4)
                case "text": drawText(text, size: 11, bold: false, color: Self.ink, indent: indent)
                case "small": drawText(text, size: 9, bold: false, color: Self.muted, indent: indent)
                case "step": drawStep(block)
                case "photos": drawPhotos(block)
                case "lines": drawLines(block["count"] as? Int ?? 10)
                case "space": y += Float(block["height"] as? Int ?? 10)
                case "page": begin()
                default: break
                }
            }
            finish()
        }

        // MARK: Pages

        func begin() {
            if current != nil { finish() }
            number += 1
            let info = PdfDocument.PageInfo.Builder(Self.pageWidth, Self.pageHeight, number).create()
            let page = pdf.startPage(info)
            current = page
            canvas = page.canvas
            y = Self.margin
        }

        func finish() {
            guard let page = current else { return }
            let text = (document["footer"] as? String ?? "") + " · " + String(number)
            let paint = paint(size: 9, bold: false, color: Self.muted)
            let width = paint.measureText(text)
            canvas?.drawText(text, Float(Self.pageWidth) - Self.margin - width, Float(Self.pageHeight) - Self.margin + Float(12), paint)
            pdf.finishPage(page)
            current = nil
            canvas = nil
        }

        func ensureRoom(_ height: Float) {
            if y + height > bottom { begin() }
        }

        // MARK: Blocks

        /// A step of the plan: number and clock time on the left, the name,
        /// its details and ingredients beside, a hairline below.
        func drawStep(_ block: [String: Any]) {
            let numberWidth = Float(22)
            let timeWidth = Float(78)
            let textX = Self.margin + numberWidth + timeWidth
            let textWidth = contentWidth - numberWidth - timeWidth
            let name = block["text"] as? String ?? ""
            let details = block["details"] as? String ?? ""
            let ingredients = block["ingredients"] as? String ?? ""
            var height = Float(layout(name, size: 11, bold: true, width: textWidth).height)
            if !details.isEmpty { height += Float(layout(details, size: 9, bold: false, width: textWidth).height) }
            if !ingredients.isEmpty { height += Float(layout(ingredients, size: 9, bold: false, width: textWidth).height) }
            ensureRoom(height + Float(10))
            let top = y
            drawAt(block["number"] as? String ?? "", x: Self.margin, y: top, size: 10, bold: true, color: Self.accent, width: numberWidth)
            drawAt(block["time"] as? String ?? "", x: Self.margin + numberWidth, y: top + Float(1), size: 9, bold: false, color: Self.ink, width: timeWidth - Float(4))
            var rowY = top
            rowY += drawAt(name, x: textX, y: rowY, size: 11, bold: true, color: Self.ink, width: textWidth)
            if !details.isEmpty { rowY += drawAt(details, x: textX, y: rowY, size: 9, bold: false, color: Self.muted, width: textWidth) }
            if !ingredients.isEmpty { rowY += drawAt(ingredients, x: textX, y: rowY, size: 9, bold: false, color: Self.ink, width: textWidth) }
            y = rowY + Float(6)
            let line = android.graphics.Paint()
            line.color = Self.rule
            line.strokeWidth = Float(0.5)
            canvas?.drawLine(Self.margin, y - Float(3), Self.margin + contentWidth, y - Float(3), line)
        }

        /// Up to three pictures side by side, each with a line beneath.
        func drawPhotos(_ block: [String: Any]) {
            let paths = block["paths"] as? [Any] ?? []
            let captions = block["captions"] as? [Any] ?? []
            guard !paths.isEmpty else { return }
            let gap = Float(10)
            let side = (contentWidth - gap * Float(2)) / Float(3)
            ensureRoom(side + Float(30))
            let top = y
            var captionHeight = Float(0)
            for index in 0..<min(paths.count, 3) {
                let left = Self.margin + Float(index) * (side + gap)
                if let path = paths[index] as? String {
                    drawImage(path: path, left: left, top: top, side: side)
                }
                let caption = index < captions.count ? (captions[index] as? String ?? "") : ""
                if !caption.isEmpty {
                    captionHeight = max(captionHeight, drawAt(caption, x: left, y: top + side + Float(4), size: 9, bold: false, color: Self.muted, width: side))
                }
            }
            y = top + side + Float(8) + captionHeight
        }

        /// Ruled lines to write on, for the resolutions.
        func drawLines(_ count: Int) {
            let line = android.graphics.Paint()
            line.color = Self.rule
            line.strokeWidth = Float(0.8)
            for _ in 0..<count {
                ensureRoom(Float(30))
                y += Float(28)
                canvas?.drawLine(Self.margin, y, Self.margin + contentWidth, y, line)
            }
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

        func layout(_ text: String, size: Int, bold: Bool, width: Float, color: Int = Sheet.ink) -> android.text.StaticLayout {
            return android.text.StaticLayout.Builder.obtain(text, 0, text.count, paint(size: size, bold: bold, color: color), Int(max(width, Float(1))))
                .build()
        }

        func drawText(_ text: String, size: Int, bold: Bool, color: Int, indent: Float) {
            let width = contentWidth - indent
            let height = Float(layout(text, size: size, bold: bold, width: width, color: color).height)
            ensureRoom(height)
            drawAt(text, x: Self.margin + indent, y: y, size: size, bold: bold, color: color, width: width)
            y += height + Float(2)
        }

        /// Draws `text` at the point; its height.
        @discardableResult
        func drawAt(_ text: String, x: Float, y: Float, size: Int, bold: Bool, color: Int, width: Float) -> Float {
            let layout = layout(text, size: size, bold: bold, width: width, color: color)
            guard let canvas else { return Float(layout.height) }
            canvas.save()
            canvas.translate(x, y)
            layout.draw(canvas)
            canvas.restore()
            return Float(layout.height)
        }

        /// The picture filling a rounded square.
        func drawImage(path: String, left: Float, top: Float, side: Float) {
            guard let canvas, let bitmap = android.graphics.BitmapFactory.decodeFile(path) else { return }
            let frame = android.graphics.RectF(left, top, left + side, top + side)
            let scale = max(side / Float(bitmap.width), side / Float(bitmap.height))
            let drawWidth = Float(bitmap.width) * scale
            let drawHeight = Float(bitmap.height) * scale
            let target = android.graphics.RectF(left + (side - drawWidth) / 2, top + (side - drawHeight) / 2,
                                                left + (side + drawWidth) / 2, top + (side + drawHeight) / 2)
            let clip = android.graphics.Path()
            clip.addRoundRect(frame, Float(8), Float(8), android.graphics.Path.Direction.CW)
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
