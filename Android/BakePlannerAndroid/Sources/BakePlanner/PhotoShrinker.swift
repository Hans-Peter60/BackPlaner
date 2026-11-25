import Foundation
#if canImport(UIKit)
import UIKit
#elseif os(Android)
// SkipFuseUI brings UIImage along on Android.
import SwiftUI
#endif

/// Photos as the app keeps them: no longer edge than looks sharp on the
/// largest screen they are shown on, instead of the camera's 12 or 48
/// megapixels — the rule the iPhone applies to the bake photos of a backup
/// (BackupPhoto in RecipeExport.swift). On Android the photos live in the
/// app's SQLite file, so they are made small as soon as they are picked;
/// the backup then finds them small already.
///
/// CGFloat and CGSize are never named here: on Android, Foundation and
/// SkipFuseUI each define them, and naming one is ambiguous. The sizes are
/// worked out in Double and the types inferred where SkipFuseUI wants them.
enum PhotoShrinker {
    /// Pixels on the longer side.
    static let longestEdge = 2048.0
    static let jpegQuality = 0.8

    /// The photo at most `longestEdge` pixels long, as JPEG. One already that
    /// small, or data that is no picture, stays exactly as it is.
    static func shrunk(_ data: Data) -> Data {
        #if canImport(UIKit) || os(Android)
        guard let image = UIImage(data: data), let smaller = smallerImage(of: image) else { return data }
        return smaller.jpegData(compressionQuality: .init(jpegQuality)) ?? data
        #else
        return data
        #endif
    }

    /// A picked file as the app keeps it: JPEG — whatever the camera wrote,
    /// HEIC, PNG or JPEG — and no longer than `longestEdge`. Nil for a file
    /// that is no picture.
    static func pickedPhoto(_ data: Data) -> Data? {
        #if canImport(UIKit) || os(Android)
        guard let image = UIImage(data: data) else { return nil }
        let kept = smallerImage(of: image) ?? image
        return kept.jpegData(compressionQuality: .init(jpegQuality)) ?? data
        #else
        return data
        #endif
    }

    /// A small square-ish version for a list row, `edge` pixels on the
    /// longer side; nil for data that is no picture.
    static func thumbnail(_ data: Data, edge: Double = 160) -> Data? {
        #if canImport(UIKit) || os(Android)
        guard let image = UIImage(data: data) else { return nil }
        let small = smallerImage(of: image, longestEdge: edge) ?? image
        return small.jpegData(compressionQuality: .init(0.7))
        #else
        return nil
        #endif
    }

    /// A picture as it is published with a recipe, the iPhone's upload
    /// size: 1024 pixels on the longer side, JPEG 0.5. Nil for data that
    /// is no picture.
    static func uploadPhoto(_ data: Data) -> Data? {
        #if canImport(UIKit) || os(Android)
        guard let image = UIImage(data: data) else { return nil }
        let small = smallerImage(of: image, longestEdge: 1024) ?? image
        return small.jpegData(compressionQuality: .init(0.5))
        #else
        return nil
        #endif
    }

    // MARK: Pages for the cloud AI

    /// What the Cloud Function analyzeRecipeImages accepts per page, as the
    /// iPhone prepares its pages (FirebaseFunctionsClient): 2000 pixels on
    /// the longer side, JPEG 0.72, at most 3 MB.
    static let analysisLongestEdge = 2000.0
    static let analysisJPEGQuality = 0.72
    static let analysisMaximumBytes = 3 * 1024 * 1024

    /// A photographed page as it goes to the cloud AI: JPEG, no longer than
    /// `analysisLongestEdge`, and under the function's size limit — made
    /// smaller and coarser until it fits. Nil for data that is no picture,
    /// or one that will not fit even then.
    static func analysisPhoto(_ data: Data) -> Data? {
        #if canImport(UIKit) || os(Android)
        guard let image = UIImage(data: data) else { return nil }
        var edge = analysisLongestEdge
        var quality = analysisJPEGQuality
        for _ in 0..<4 {
            let kept = smallerImage(of: image, longestEdge: edge) ?? image
            if let jpeg = kept.jpegData(compressionQuality: .init(quality)),
               jpeg.count <= analysisMaximumBytes {
                return jpeg
            }
            edge *= 0.75
            quality = max(0.4, quality - 0.1)
        }
        return nil
        #else
        return data
        #endif
    }

    #if canImport(UIKit) || os(Android)
    /// The image scaled down to `longestEdge`, keeping its proportions; nil
    /// when it is that small already.
    private static func smallerImage(of image: UIImage, longestEdge: Double = PhotoShrinker.longestEdge) -> UIImage? {
        let scale = Double(image.scale)
        let width = Double(image.size.width) * scale
        let height = Double(image.size.height) * scale
        let longest = max(width, height)
        guard longest > longestEdge else { return nil }
        let factor = longestEdge / longest
        return image.preparingThumbnail(of: .init(width: (width * factor / scale).rounded(),
                                                  height: (height * factor / scale).rounded()))
    }
    #endif
}
