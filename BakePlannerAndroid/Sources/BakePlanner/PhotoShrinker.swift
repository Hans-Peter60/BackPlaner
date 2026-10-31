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

    #if canImport(UIKit) || os(Android)
    /// The image scaled down to `longestEdge`, keeping its proportions; nil
    /// when it is that small already.
    private static func smallerImage(of image: UIImage) -> UIImage? {
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
