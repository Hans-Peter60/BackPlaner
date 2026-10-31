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
enum PhotoShrinker {
    /// Pixels on the longer side.
    static let longestEdge: CGFloat = 2048
    static let jpegQuality: CGFloat = 0.8

    /// The photo at most `longestEdge` pixels long, as JPEG. One already that
    /// small, or data that is no picture, stays exactly as it is.
    static func shrunk(_ data: Data) -> Data {
        #if canImport(UIKit) || os(Android)
        guard let image = UIImage(data: data), let smaller = smallerImage(of: image) else { return data }
        return smaller.jpegData(compressionQuality: jpegQuality) ?? data
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
        return kept.jpegData(compressionQuality: jpegQuality) ?? data
        #else
        return data
        #endif
    }

    #if canImport(UIKit) || os(Android)
    /// The image scaled down to `longestEdge`, keeping its proportions; nil
    /// when it is that small already.
    private static func smallerImage(of image: UIImage) -> UIImage? {
        let width = image.size.width * image.scale
        let height = image.size.height * image.scale
        let longest = max(width, height)
        guard longest > longestEdge else { return nil }
        let factor = longestEdge / longest
        let size = CGSize(width: (width * factor / image.scale).rounded(),
                          height: (height * factor / image.scale).rounded())
        return image.preparingThumbnail(of: size)
    }
    #endif
}
