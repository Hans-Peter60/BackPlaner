//
//  PhotoMetadataTests.swift
//  BakePlannerCoreTests
//

import Foundation
import Testing
@testable import BakePlannerCore

@Suite("A JPEG's date and title")
struct PhotoMetadataTests {

    private let zone = TimeZone(identifier: "Europe/Berlin")!

    /// A JPEG skeleton: SOI, the given segments, SOS marker.
    private func jpeg(_ segments: [(UInt8, [UInt8])]) -> Data {
        var bytes: [UInt8] = [0xFF, 0xD8]
        for (marker, payload) in segments {
            let length = payload.count + 2
            bytes += [0xFF, marker, UInt8(length >> 8), UInt8(length & 0xFF)] + payload
        }
        bytes += [0xFF, 0xDA, 0x00, 0x02]
        return Data(bytes)
    }

    /// A little-endian TIFF with IFD0 (ImageDescription, ExifIFD pointer)
    /// and an EXIF IFD (DateTimeOriginal).
    private func exifSegment(description: String, dateTimeOriginal: String) -> [UInt8] {
        func le16(_ v: Int) -> [UInt8] { [UInt8(v & 0xFF), UInt8(v >> 8)] }
        func le32(_ v: Int) -> [UInt8] { [UInt8(v & 0xFF), UInt8((v >> 8) & 0xFF), UInt8((v >> 16) & 0xFF), UInt8(v >> 24)] }
        let desc = Array(description.utf8) + [0]
        let date = Array(dateTimeOriginal.utf8) + [0]
        // Layout: header 8, IFD0 at 8 (2 + 2*12 + 4 = 30) → 38, description at 38, exif IFD after it, date after that.
        let descOffset = 38
        let exifOffset = descOffset + desc.count + (desc.count % 2)
        let dateOffset = exifOffset + 2 + 12 + 4
        var tiff: [UInt8] = [0x49, 0x49, 0x2A, 0x00] + le32(8)
        tiff += le16(2)
        tiff += le16(0x010E) + le16(2) + le32(desc.count) + le32(descOffset)
        tiff += le16(0x8769) + le16(4) + le32(1) + le32(exifOffset)
        tiff += le32(0)
        tiff += desc
        if desc.count % 2 == 1 { tiff.append(0) }
        tiff += le16(1)
        tiff += le16(0x9003) + le16(2) + le32(date.count) + le32(dateOffset)
        tiff += le32(0)
        tiff += date
        return Array("Exif\0\0".utf8) + tiff
    }

    private func iptcSegment(title: String) -> [UInt8] {
        let text = Array(title.utf8)
        let dataset: [UInt8] = [0x1C, 0x02, 0x05, UInt8(text.count >> 8), UInt8(text.count & 0xFF)] + text
        var block: [UInt8] = Array("8BIM".utf8) + [0x04, 0x04] + [0x00, 0x00]   // resource, empty name (padded to 2)
        block += [UInt8(dataset.count >> 24), UInt8((dataset.count >> 16) & 0xFF), UInt8((dataset.count >> 8) & 0xFF), UInt8(dataset.count & 0xFF)]
        block += dataset
        if dataset.count % 2 == 1 { block.append(0) }
        return Array("Photoshop 3.0\0".utf8) + block
    }

    private func xmpSegment(title: String, date: String?) -> [UInt8] {
        var xml = "<x:xmpmeta xmlns:x=\"adobe:ns:meta/\"><rdf:RDF><rdf:Description"
        if let date { xml += " photoshop:DateCreated=\"\(date)\"" }
        xml += "><dc:title><rdf:Alt><rdf:li xml:lang=\"x-default\">\(title)</rdf:li></rdf:Alt></dc:title></rdf:Description></rdf:RDF></x:xmpmeta>"
        return Array("http://ns.adobe.com/xap/1.0/\0".utf8) + Array(xml.utf8)
    }

    private func components(_ date: Date?) -> DateComponents? {
        guard let date else { return nil }
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = zone
        return calendar.dateComponents([.year, .month, .day, .hour, .minute], from: date)
    }

    @Test("EXIF gives the date, IPTC the title before the TIFF description")
    func exifAndIptc() {
        let data = jpeg([(0xE1, exifSegment(description: "Beschreibung", dateTimeOriginal: "2021:03:14 09:26:53")),
                         (0xED, iptcSegment(title: "Bergkruste 2021"))])
        let meta = PhotoMetadata.read(data)
        #expect(meta.title == "Bergkruste 2021")
        let parts = components(meta.date)
        #expect(parts?.year == 2021 && parts?.month == 3 && parts?.day == 14)
    }

    @Test("Without IPTC the TIFF description is the title; without EXIF the XMP date counts")
    func fallbacks() {
        let onlyExif = PhotoMetadata.read(jpeg([(0xE1, exifSegment(description: "Dinkelbrot", dateTimeOriginal: "2022:11:02 17:00:00"))]))
        #expect(onlyExif.title == "Dinkelbrot")
        let onlyXMP = PhotoMetadata.read(jpeg([(0xE1, xmpSegment(title: "Baguette &amp; Co", date: "2020-05-01T08:15:00"))]))
        #expect(onlyXMP.title == "Baguette & Co")
        #expect(components(onlyXMP.date)?.year == 2020 && components(onlyXMP.date)?.hour == 8)
    }

    @Test("Not a JPEG, or a JPEG without metadata, gives nothing")
    func nothing() {
        #expect(PhotoMetadata.read(Data([0x89, 0x50, 0x4E, 0x47])) == PhotoMetadata())
        #expect(PhotoMetadata.read(jpeg([])) == PhotoMetadata())
        #expect(PhotoMetadata.read(Data()) == PhotoMetadata())
    }
}
