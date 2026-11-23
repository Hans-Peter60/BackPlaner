//
//  BakeHistoryPhotoReader.swift
//  BackPlaner
//
//  What a photo tells about the bake on it: when it was taken (EXIF, else
//  the photo library's date) and what it was called (IPTC title or
//  caption, TIFF description); and which recipe picture it resembles,
//  measured with Vision's feature prints on the device. The matching of
//  titles to names lives in the package (BakeHistoryPhotoImport).
//

import BakePlannerCore
import Foundation
import ImageIO
import Photos
import UIKit
import Vision

enum BakeHistoryPhotoReader {

    struct Facts {
        var date: Date?
        var title: String?
    }

    /// Date and title from the picture's own metadata.
    static func facts(of data: Data) -> Facts {
        guard let source = CGImageSourceCreateWithData(data as CFData, [kCGImageSourceShouldCache: false] as CFDictionary),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any] else {
            return Facts()
        }
        var facts = Facts()
        let exif = properties[kCGImagePropertyExifDictionary] as? [CFString: Any]
        let tiff = properties[kCGImagePropertyTIFFDictionary] as? [CFString: Any]
        let iptc = properties[kCGImagePropertyIPTCDictionary] as? [CFString: Any]
        for text in [exif?[kCGImagePropertyExifDateTimeOriginal], exif?[kCGImagePropertyExifDateTimeDigitized], tiff?[kCGImagePropertyTIFFDateTime]] {
            if let text = text as? String, let date = BakeHistoryPhotoImport.exifDate(text) {
                facts.date = date
                break
            }
        }
        for text in [iptc?[kCGImagePropertyIPTCObjectName], iptc?[kCGImagePropertyIPTCCaptionAbstract], tiff?[kCGImagePropertyTIFFImageDescription]] {
            if let text = text as? String {
                let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty {
                    facts.title = trimmed
                    break
                }
            }
        }
        // A title kept only in XMP (dc:title), which ImageIO leaves out.
        if facts.title == nil || facts.date == nil {
            let packaged = PhotoMetadata.read(data)
            if facts.title == nil { facts.title = packaged.title }
            if facts.date == nil { facts.date = packaged.date }
        }
        return facts
    }

    /// The library's creation date for a picked photo, when the person
    /// lets the app read the library; nil otherwise.
    static func libraryDate(forAssetIdentifier identifier: String?) -> Date? {
        guard let identifier else { return nil }
        let status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        guard status == .authorized || status == .limited else { return nil }
        return PHAsset.fetchAssets(withLocalIdentifiers: [identifier], options: nil).firstObject?.creationDate
    }

    static func requestLibraryAccess() async -> Bool {
        let status = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
        return status == .authorized || status == .limited
    }

    // MARK: Likeness

    /// A recipe picture's feature print, computed once per import.
    struct RecipePrint {
        let recipeName: String
        let print: VNFeaturePrintObservation
    }

    static func featurePrint(of data: Data) -> VNFeaturePrintObservation? {
        // Downsampled first: the print does not need the full picture, and
        // a hundred photos must not take a hundred full decodes.
        guard let image = RecipeThumbnails.downsampled(data, maxPixelSize: 512)?.cgImage else { return nil }
        let request = VNGenerateImageFeaturePrintRequest()
        let handler = VNImageRequestHandler(cgImage: image, options: [:])
        guard (try? handler.perform([request])) != nil else { return nil }
        return request.results?.first
    }

    static func recipePrints(_ recipes: [(name: String, image: Data)]) -> [RecipePrint] {
        recipes.compactMap { recipe in
            featurePrint(of: recipe.image).map { RecipePrint(recipeName: recipe.name, print: $0) }
        }
    }

    /// The recipe whose picture the photo resembles most, with the
    /// distance (0 is the same picture); nil without prints.
    static func closest(_ photo: VNFeaturePrintObservation, among prints: [RecipePrint]) -> (recipeName: String, distance: Float)? {
        var best: (String, Float)?
        for candidate in prints {
            var distance: Float = 0
            guard (try? photo.computeDistance(&distance, to: candidate.print)) != nil else { continue }
            if best == nil || distance < best!.1 {
                best = (candidate.recipeName, distance)
            }
        }
        return best
    }

    /// Below this distance two bread pictures look alike enough to propose
    /// the recipe; below `strongLikeness` the import marks it as sure.
    static let likenessLimit: Float = 1.1
    static let strongLikeness: Float = 0.75
}
