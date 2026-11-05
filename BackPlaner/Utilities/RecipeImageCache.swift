//
//  RecipeImageCache.swift
//  BackPlaner
//
//  The pictures of the recipe list, ready when the list appears. Public
//  recipes keep their downloaded pictures on disk, so the next launch
//  shows them at once instead of after the download; the user's own
//  recipes get a small thumbnail made once per picture, so the list does
//  not decode every full-size photo for a 50-point row.
//

import BakePlannerCore
import CoreData
import Foundation
import ImageIO
import Observation
import UIKit

// MARK: - Public recipes

/// The pictures of public recipes: in memory for the views, on disk for the
/// next launch. `@Observable`, so a row that found no picture yet redraws
/// when the download arrives — before, the row kept its placeholder until
/// something else made it redraw. Read and changed on the main thread, as
/// the views and the Firebase callbacks are.
@Observable
final class PublicRecipeImages {

    static let shared = PublicRecipeImages()

    /// By recipe id.
    private(set) var images: [String: UIImage] = [:]

    private var preloaded = false
    private let queue = DispatchQueue(label: "de.hpm64625.BackPlaner.publicRecipeImages", qos: .utility)

    private static let folder = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("PublicRecipeImages", isDirectory: true)

    private static func file(for id: String) -> URL {
        folder.appendingPathComponent(id).appendingPathExtension("jpg")
    }

    /// Reads what the last run left on disk, off the main thread, and
    /// publishes the pictures in one go. A picture already downloaded in
    /// the meantime wins over the disk copy.
    func preload() {
        guard !preloaded else { return }
        preloaded = true
        queue.async {
            guard let files = try? FileManager.default.contentsOfDirectory(at: Self.folder, includingPropertiesForKeys: nil)
            else { return }
            var loaded: [String: UIImage] = [:]
            for file in files where file.pathExtension == "jpg" {
                if let data = try? Data(contentsOf: file), let image = UIImage(data: data) {
                    loaded[file.deletingPathExtension().lastPathComponent] = image
                }
            }
            guard !loaded.isEmpty else { return }
            DispatchQueue.main.async {
                self.images.merge(loaded) { current, _ in current }
            }
        }
    }

    /// Keeps a downloaded picture and writes it to disk for the next launch.
    /// The same bytes as on disk change nothing, so the rows do not redraw
    /// for a picture they already show.
    func store(_ data: Data, for id: String) {
        guard !id.isEmpty else { return }
        queue.async {
            let file = Self.file(for: id)
            let unchanged = (try? Data(contentsOf: file)) == data
            if !unchanged {
                try? FileManager.default.createDirectory(at: Self.folder, withIntermediateDirectories: true)
                try? data.write(to: file, options: .atomic)
            }
            guard let image = UIImage(data: data) else { return }
            DispatchQueue.main.async {
                if !unchanged || self.images[id] == nil {
                    self.images[id] = image
                }
            }
        }
    }

    /// Keeps a picture the user just chose for a public recipe of theirs.
    func store(_ image: UIImage, for id: String) {
        guard !id.isEmpty else { return }
        images[id] = image
        guard let data = image.jpegData(compressionQuality: 0.9) else { return }
        queue.async {
            try? FileManager.default.createDirectory(at: Self.folder, withIntermediateDirectories: true)
            try? data.write(to: Self.file(for: id), options: .atomic)
        }
    }

    /// Forgets the picture of a recipe that was deleted.
    func remove(id: String) {
        images[id] = nil
        queue.async {
            try? FileManager.default.removeItem(at: Self.file(for: id))
        }
    }
}

// MARK: - Own recipes

/// Small pictures for the rows of the user's own recipes. The stored
/// picture is full size; decoding it for every row made the list slow to
/// appear. The thumbnail is made once per picture, kept in memory and on
/// disk, keyed by the recipe's object id and the picture's length, so a new
/// picture gets a new thumbnail.
final class RecipeThumbnails {

    static let shared = RecipeThumbnails()

    /// 50 points at 3x, with room for the clipped fill.
    static let maxPixelSize = 300

    private var memory: [String: UIImage] = [:]
    private let queue = DispatchQueue(label: "de.hpm64625.BackPlaner.recipeThumbnails", qos: .utility)

    private static let folder = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("RecipeThumbnails", isDirectory: true)

    /// The thumbnail of the recipe's picture; nil for a recipe without one.
    /// Made on the spot the first time a picture is seen, read from disk on
    /// later launches.
    func image(for recipe: Recipe) -> UIImage? {
        let data = recipe.image
        guard !data.isEmpty else { return nil }

        let key = recipe.objectID.uriRepresentation().lastPathComponent + "-\(data.count)"
        if let cached = memory[key] { return cached }

        let file = Self.folder.appendingPathComponent(key).appendingPathExtension("jpg")
        if let small = try? Data(contentsOf: file), let image = UIImage(data: small) {
            memory[key] = image
            return image
        }

        guard let image = Self.downsampled(data, maxPixelSize: Self.maxPixelSize) else { return nil }
        memory[key] = image
        if let jpeg = image.jpegData(compressionQuality: 0.85) {
            queue.async {
                try? FileManager.default.createDirectory(at: Self.folder, withIntermediateDirectories: true)
                try? jpeg.write(to: file, options: .atomic)
            }
        }
        return image
    }

    /// The picture scaled down so its longer side is at most `maxPixelSize`
    /// pixels, decoded straight to that size (ImageIO), the orientation
    /// applied. Nil for data that is no picture.
    static func downsampled(_ data: Data, maxPixelSize: Int) -> UIImage? {
        let sourceOptions: [CFString: Any] = [kCGImageSourceShouldCache: false]
        guard let source = CGImageSourceCreateWithData(data as CFData, sourceOptions as CFDictionary) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
        ]
        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
        return UIImage(cgImage: cgImage)
    }
}
