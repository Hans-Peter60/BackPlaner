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
///         { "kind": "timeline", "minutes": 37,
///           "ticks": [{ "minute": 0, "label": "18:00", "strong": 1 }, …],
///           "lanes": [{ "name": "…", "color": [204, 107, 41], "tracks": 1,
///                       "bars": [{ "start": 0, "handsEnd": 2, "end": 6, "track": 0, "number": "1" }, …] }, …],
///           "legend": ["Hände", "läuft allein", "Zahl = Schritt im Ablauf"] },
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
                case "timeline": drawTimeline(block)
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

        /// The plan as a chart, as on the iPhone's PDF: one row per
        /// component, time running to the right, every bar from its start to
        /// its end with its step number; the hands-on part filled, the part
        /// that runs on its own light and striped. A legend beneath.
        func drawTimeline(_ block: [String: Any]) {
            guard let canvas else { return }
            let lanes = block["lanes"] as? [Any] ?? []
            let ticks = block["ticks"] as? [Any] ?? []
            let legend = block["legend"] as? [Any] ?? []
            let minutes = max(1, block["minutes"] as? Int ?? 1)
            let labelWidth = Float(92)
            let chartX = Self.margin + labelWidth
            let chartWidth = contentWidth - labelWidth
            let perMinute = chartWidth / Float(minutes)
            let trackHeight = Float(15)
            var laneHeights: [Float] = []
            for item in lanes {
                let lane = item as? [String: Any] ?? [:]
                laneHeights.append(Float(max(1, lane["tracks"] as? Int ?? 1)) * trackHeight + Float(8))
            }
            var lanesHeight = Float(0)
            for height in laneHeights { lanesHeight += height }
            ensureRoom(Float(22) + lanesHeight + Float(18))
            let page = self.canvas ?? canvas
            let top = y

            // Minute lines and their labels.
            let line = android.graphics.Paint()
            line.color = Self.rule
            for item in ticks {
                let tick = item as? [String: Any] ?? [:]
                let minute = tick["minute"] as? Int ?? 0
                let x = chartX + Float(minute) * perMinute
                line.strokeWidth = (tick["strong"] as? Int ?? 0) == 1 ? Float(0.8) : Float(0.4)
                page.drawLine(x, top + Float(16), x, top + Float(22) + lanesHeight, line)
                let label = tick["label"] as? String ?? ""
                let paint = paint(size: 7, bold: false, color: Self.muted)
                page.drawText(label, x - paint.measureText(label) / Float(2), top + Float(10), paint)
            }

            var laneTop = top + Float(22)
            for (index, item) in lanes.enumerated() {
                let lane = item as? [String: Any] ?? [:]
                let rgb = lane["color"] as? [Any] ?? []
                let red = rgb.count > 0 ? (rgb[0] as? Int ?? 0) : 0
                let green = rgb.count > 1 ? (rgb[1] as? Int ?? 0) : 0
                let blue = rgb.count > 2 ? (rgb[2] as? Int ?? 0) : 0
                drawAt(lane["name"] as? String ?? "", x: Self.margin, y: laneTop + Float(2), size: 8, bold: true, color: Self.ink, width: labelWidth - Float(6))
                for barItem in lane["bars"] as? [Any] ?? [] {
                    let bar = barItem as? [String: Any] ?? [:]
                    let start = bar["start"] as? Int ?? 0
                    let handsEnd = bar["handsEnd"] as? Int ?? start
                    let end = bar["end"] as? Int ?? start
                    let track = bar["track"] as? Int ?? 0
                    let left = chartX + Float(start) * perMinute
                    let width = max(Float(3), Float(end - start) * perMinute) - Float(1)
                    let barTop = laneTop + Float(4) + Float(track) * trackHeight
                    let rect = android.graphics.RectF(left, barTop, left + width, barTop + trackHeight - Float(3))
                    let hands = min(max(Float(0), Float(handsEnd - start) * perMinute), width)
                    let clip = android.graphics.Path()
                    clip.addRoundRect(rect, Float(2.5), Float(2.5), android.graphics.Path.Direction.CW)
                    page.save()
                    page.clipPath(clip)
                    let fill = android.graphics.Paint()
                    fill.isAntiAlias = true
                    if hands > Float(0) {
                        fill.color = android.graphics.Color.argb(191, red, green, blue)
                        page.drawRect(rect.left, rect.top, rect.left + hands, rect.bottom, fill)
                    }
                    if width - hands > Float(0.5) {
                        let aloneLeft = rect.left + hands
                        fill.color = android.graphics.Color.argb(46, red, green, blue)
                        page.drawRect(aloneLeft, rect.top, rect.right, rect.bottom, fill)
                        page.clipRect(aloneLeft, rect.top, rect.right, rect.bottom)
                        let stripes = android.graphics.Paint()
                        stripes.isAntiAlias = true
                        stripes.color = android.graphics.Color.argb(140, red, green, blue)
                        stripes.strokeWidth = Float(0.7)
                        let height = rect.bottom - rect.top
                        var stripe = aloneLeft - height
                        while stripe < rect.right {
                            page.drawLine(stripe, rect.bottom, stripe + height, rect.top, stripes)
                            stripe += Float(4)
                        }
                    }
                    page.restore()
                    let border = android.graphics.Paint()
                    border.isAntiAlias = true
                    border.style = android.graphics.Paint.Style.STROKE
                    border.strokeWidth = Float(0.6)
                    border.color = android.graphics.Color.rgb(red, green, blue)
                    page.drawRoundRect(rect, Float(2.5), Float(2.5), border)
                    let number = bar["number"] as? String ?? ""
                    if !number.isEmpty {
                        let small = width < Float(12)
                        let paint = paint(size: small ? 6 : 7, bold: true, color: Self.ink)
                        page.drawText(number, rect.centerX() - paint.measureText(number) / Float(2), rect.top + (small ? Float(8) : Float(9)), paint)
                    }
                }
                laneTop += laneHeights[index]
            }

            // The legend.
            let legendY = laneTop + Float(4)
            let swatch = android.graphics.Paint()
            swatch.color = android.graphics.Color.argb(191, 204, 107, 41)
            page.drawRect(chartX, legendY + Float(2), chartX + Float(12), legendY + Float(9), swatch)
            swatch.color = android.graphics.Color.argb(46, 204, 107, 41)
            page.drawRect(chartX + Float(80), legendY + Float(2), chartX + Float(92), legendY + Float(9), swatch)
            let offsets = [Float(16), Float(96), Float(200)]
            for index in 0..<min(3, legend.count) {
                let paint = paint(size: 7, bold: false, color: Self.muted)
                page.drawText(legend[index] as? String ?? "", chartX + offsets[index], legendY + Float(8), paint)
            }
            y = legendY + Float(22)
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
