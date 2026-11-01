import BakePlannerCore
import Foundation
import UIKit

// Reading recipe pages lives in BakePlannerCore (RecipeWebPage.swift), so
// the Android app imports pages the same way. The iPhone adds the page's
// photo as a UIImage.
extension RecipeWebPageLoader {
    /// Downloads the page's recipe photo, if it offers one that is usable.
    static func loadImage(from url: URL?) async -> UIImage? {
        guard let data = await loadImageData(from: url),
              let image = UIImage(data: data),
              image.size.width >= minimumImageEdge, image.size.height >= minimumImageEdge else {
            return nil
        }
        return image
    }
}
