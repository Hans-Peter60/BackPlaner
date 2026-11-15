//
//  PhotoMetadata.swift
//  BakePlannerCore
//
//  What a JPEG says about itself without any image framework: the date it
//  was taken (EXIF) and its title (IPTC, TIFF description, XMP). For the
//  baking history from photos on Android, where ImageIO is not at hand;
//  the iPhone reads the same fields through ImageIO and uses this for the
//  XMP title ImageIO leaves out.
//

import Foundation

public struct PhotoMetadata: Equatable {
    public var date: Date?
    public var title: String?

    public init(date: Date? = nil, title: String? = nil) {
        self.date = date
        self.title = title
    }

    /// Reads a JPEG's APP1 (EXIF and XMP) and APP13 (IPTC) segments; other
    /// file types give an empty result.
    public static func read(_ data: Data) -> PhotoMetadata {
        let bytes = [UInt8](data)
        guard bytes.count > 4, bytes[0] == 0xFF, bytes[1] == 0xD8 else { return PhotoMetadata() }
        var result = PhotoMetadata()
        var xmpTitle: String?
        var iptcTitle: String?
        var tiffDescription: String?

        var index = 2
        while index + 4 <= bytes.count, bytes[index] == 0xFF {
            let marker = bytes[index + 1]
            if marker == 0xDA || marker == 0xD9 { break }   // image data / end
            let length = Int(bytes[index + 2]) << 8 | Int(bytes[index + 3])
            guard length >= 2, index + 2 + length <= bytes.count else { break }
            let payload = Array(bytes[(index + 4)..<(index + 2 + length)])
            switch marker {
            case 0xE1:
                if payload.starts(with: Array("Exif\0\0".utf8)) {
                    let tiff = Array(payload.dropFirst(6))
                    let exif = readTIFF(tiff)
                    if result.date == nil { result.date = exif.date }
                    if tiffDescription == nil { tiffDescription = exif.description }
                } else if payload.starts(with: Array("http://ns.adobe.com/xap/1.0/".utf8)),
                          let text = String(bytes: payload, encoding: .utf8) {
                    if xmpTitle == nil { xmpTitle = xmpText(text) }
                    if result.date == nil { result.date = xmpDate(text) }
                }
            case 0xED:
                if payload.starts(with: Array("Photoshop 3.0\0".utf8)), iptcTitle == nil {
                    iptcTitle = iptcText(Array(payload.dropFirst(14)))
                }
            default:
                break
            }
            index += 2 + length
        }
        result.title = [iptcTitle, xmpTitle, tiffDescription].compactMap { $0 }.first
        return result
    }

    // MARK: EXIF

    private static func readTIFF(_ tiff: [UInt8]) -> (date: Date?, description: String?) {
        guard tiff.count >= 8 else { return (nil, nil) }
        let little = tiff[0] == 0x49 && tiff[1] == 0x49
        func u16(_ at: Int) -> Int {
            guard at + 2 <= tiff.count else { return 0 }
            return little ? Int(tiff[at]) | Int(tiff[at + 1]) << 8 : Int(tiff[at]) << 8 | Int(tiff[at + 1])
        }
        func u32(_ at: Int) -> Int {
            guard at + 4 <= tiff.count else { return 0 }
            return little
                ? Int(tiff[at]) | Int(tiff[at + 1]) << 8 | Int(tiff[at + 2]) << 16 | Int(tiff[at + 3]) << 24
                : Int(tiff[at]) << 24 | Int(tiff[at + 1]) << 16 | Int(tiff[at + 2]) << 8 | Int(tiff[at + 3])
        }
        func ascii(count: Int, at valueField: Int) -> String? {
            let start = count <= 4 ? valueField : u32(valueField)
            guard start >= 0, count > 0, start + count <= tiff.count else { return nil }
            let raw = Array(tiff[start..<(start + count)]).prefix { $0 != 0 }
            let text = String(decoding: raw, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
            return text.isEmpty ? nil : text
        }
        /// The ASCII tags of one IFD and the pointer to the EXIF sub-IFD.
        func readIFD(_ offset: Int) -> (tags: [Int: String], exifOffset: Int?) {
            var tags: [Int: String] = [:]
            var exifOffset: Int?
            guard offset + 2 <= tiff.count else { return (tags, nil) }
            let count = u16(offset)
            for n in 0..<min(count, 200) {
                let entry = offset + 2 + n * 12
                guard entry + 12 <= tiff.count else { break }
                let tag = u16(entry), type = u16(entry + 2), length = u32(entry + 4)
                if tag == 0x8769 { exifOffset = u32(entry + 8) }
                if type == 2, let text = ascii(count: length, at: entry + 8) { tags[tag] = text }
            }
            return (tags, exifOffset)
        }

        let ifd0 = readIFD(u32(4))
        var dates: [String] = []
        if let exifOffset = ifd0.exifOffset {
            let exif = readIFD(exifOffset)
            dates += [exif.tags[0x9003], exif.tags[0x9004]].compactMap { $0 }
        }
        if let datetime = ifd0.tags[0x0132] { dates.append(datetime) }
        let date = dates.lazy.compactMap { BakeHistoryPhotoImport.exifDate($0) }.first
        return (date, ifd0.tags[0x010E])
    }

    // MARK: IPTC

    /// Record 2: dataset 5 is the object name (title), 120 the caption.
    private static func iptcText(_ block: [UInt8]) -> String? {
        var title: String?
        var caption: String?
        var i = 0
        while i + 12 <= block.count {
            guard block[i] == 0x38, block[i + 1] == 0x42, block[i + 2] == 0x49, block[i + 3] == 0x4D else { break }
            let resource = Int(block[i + 4]) << 8 | Int(block[i + 5])
            let nameLength = Int(block[i + 6])
            var p = i + 7 + nameLength
            if (nameLength + 1) % 2 == 1 { p += 1 }
            guard p + 4 <= block.count else { break }
            let size = Int(block[p]) << 24 | Int(block[p + 1]) << 16 | Int(block[p + 2]) << 8 | Int(block[p + 3])
            p += 4
            guard p + size <= block.count else { break }
            if resource == 0x0404 {
                var q = p
                while q + 5 <= p + size, block[q] == 0x1C {
                    let record = block[q + 1], dataset = block[q + 2]
                    let length = Int(block[q + 3]) << 8 | Int(block[q + 4])
                    q += 5
                    guard q + length <= p + size else { break }
                    if record == 2 {
                        let text = String(decoding: block[q..<(q + length)], as: UTF8.self)
                            .trimmingCharacters(in: .whitespacesAndNewlines)
                        if !text.isEmpty {
                            if dataset == 5, title == nil { title = text }
                            if dataset == 120, caption == nil { caption = text }
                        }
                    }
                    q += length
                }
            }
            i = p + size + (size % 2)
        }
        return title ?? caption
    }

    // MARK: XMP

    /// dc:title, else dc:description, from the first rdf:li inside.
    private static func xmpText(_ xmp: String) -> String? {
        for element in ["dc:title", "dc:description"] {
            guard let open = xmp.range(of: "<\(element)"), let close = xmp.range(of: "</\(element)>", range: open.upperBound..<xmp.endIndex) else { continue }
            let inner = xmp[open.upperBound..<close.lowerBound]
            if let li = inner.range(of: "<rdf:li"), let liOpen = inner.range(of: ">", range: li.upperBound..<inner.endIndex),
               let liClose = inner.range(of: "</rdf:li>", range: liOpen.upperBound..<inner.endIndex) {
                let text = decodeEntities(String(inner[liOpen.upperBound..<liClose.lowerBound])).trimmingCharacters(in: .whitespacesAndNewlines)
                if !text.isEmpty { return text }
            }
        }
        return nil
    }

    /// photoshop:DateCreated or xmp:CreateDate, "2021-03-14T09:26:53".
    private static func xmpDate(_ xmp: String) -> Date? {
        for key in ["photoshop:DateCreated", "xmp:CreateDate", "exif:DateTimeOriginal"] {
            for pattern in ["\(key)=\"", "<\(key)>"] {
                guard let start = xmp.range(of: pattern) else { continue }
                let rest = xmp[start.upperBound...]
                let value = rest.prefix { $0 != "\"" && $0 != "<" }
                let text = String(value.prefix(19)).replacingOccurrences(of: "T", with: " ")
                if let date = BakeHistoryPhotoImport.exifDate(text) { return date }
            }
        }
        return nil
    }

    private static func decodeEntities(_ text: String) -> String {
        text.replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&apos;", with: "'")
    }
}
