//
//  CookRunLog.swift
//  CookPlanner
//
//  The stopwatch records of the cooked dishes, newest first, in one JSON
//  file in Application Support next to the dish database; the photos of
//  the results beside it in a folder "Photos", one JPEG per record.
//

import BakePlannerCore
import Foundation
import Observation
import ImageIO
import UIKit

@Observable @MainActor
final class CookRunLog {

    static let shared = CookRunLog()

    private(set) var runs: [KitchenCookRun] = []
    /// What went wrong with the file, for an alert; nil once shown.
    var lastError: String?
    /// True when the file is of a later version than this build knows: it
    /// is read as far as possible, never written.
    private(set) var isReadOnly = false
    private let fileURL: URL
    private let photoFolder: URL
    /// Small pictures for the lists, made once per photo.
    @ObservationIgnored private var thumbnails: [String: UIImage] = [:]

    private init() {
        let folder = URL.applicationSupportDirectory.appendingPathComponent("CookPlanner", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        fileURL = folder.appendingPathComponent("cook-runs.json")
        photoFolder = folder.appendingPathComponent("Photos", isDirectory: true)
        load()
    }

    func runs(of dishID: String) -> [KitchenCookRun] {
        runs.filter { $0.dishID == dishID }
    }

    func add(_ run: KitchenCookRun) {
        // Newest first; an entry made afterwards for an older day goes where its day is.
        runs.append(run)
        runs.sort { $0.startedAt > $1.startedAt }
        save()
        CloudSync.shared.runChanged(run.id)
    }

    func run(id: String) -> KitchenCookRun? {
        runs.first { $0.id == id }
    }

    /// Keeps a changed record: the rating, the note, the photo.
    func update(_ run: KitchenCookRun) {
        guard let index = runs.firstIndex(where: { $0.id == run.id }) else { return }
        runs[index] = run
        save()
        CloudSync.shared.runChanged(run.id)
    }

    func delete(id: String) {
        if let name = run(id: id)?.photoFileName { removePhotoFile(name) }
        runs.removeAll { $0.id == id }
        save()
        CloudSync.shared.runDeleted(id)
    }

    // MARK: From other devices

    /// A record another device added or changed, with its photo file as
    /// CloudKit handed it over; kept without being sent back.
    func applyRemote(_ run: KitchenCookRun, photoFile: URL?) {
        let previous = self.run(id: run.id)
        if let old = previous?.photoFileName, old != run.photoFileName { removePhotoFile(old) }
        if let name = run.photoFileName, let photoFile {
            try? FileManager.default.createDirectory(at: photoFolder, withIntermediateDirectories: true)
            let target = photoFolder.appendingPathComponent(name)
            try? FileManager.default.removeItem(at: target)
            try? FileManager.default.copyItem(at: photoFile, to: target)
            thumbnails[name] = nil
        }
        guard previous != run else { return }
        runs.removeAll { $0.id == run.id }
        runs.append(run)
        runs.sort { $0.startedAt > $1.startedAt }
        save()
    }

    /// A record another device deleted.
    func removeRemote(id: String) {
        guard let run = run(id: id) else { return }
        if let name = run.photoFileName { removePhotoFile(name) }
        runs.removeAll { $0.id == id }
        save()
    }

    /// Where the record's photo lies, when there is one.
    func photoURL(of run: KitchenCookRun) -> URL? {
        guard let name = run.photoFileName else { return nil }
        let url = photoFolder.appendingPathComponent(name)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    // MARK: Photos

    /// A photo read straight at a reduced size (ImageIO), so thirty camera
    /// photos at once do not fill the memory with full-size bitmaps.
    nonisolated static func downsampled(_ data: Data, maxPixels: CGFloat = 1600) -> UIImage? {
        let options = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let source = CGImageSourceCreateWithData(data as CFData, options) else { return nil }
        let thumbnailOptions = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixels,
        ] as CFDictionary
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, thumbnailOptions) else { return nil }
        return UIImage(cgImage: image)
    }

    /// Keeps `image` as the record's photo, at most 1600 points on its
    /// longer side, replacing an earlier one.
    func setPhoto(_ image: UIImage, for runID: String) {
        guard var run = run(id: runID) else { return }
        let longer = max(image.size.width, image.size.height)
        let scale = longer > 1600 ? 1600 / longer : 1
        let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let resized = UIGraphicsImageRenderer(size: size, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: size))
        }
        guard let data = resized.jpegData(compressionQuality: 0.8) else { return }
        do {
            try FileManager.default.createDirectory(at: photoFolder, withIntermediateDirectories: true)
            let name = runID + "-" + UUID().uuidString.prefix(8) + ".jpg"
            try data.write(to: photoFolder.appendingPathComponent(name), options: .atomic)
            if let old = run.photoFileName { removePhotoFile(old) }
            run.photoFileName = name
            update(run)
        } catch {
            return
        }
    }

    func removePhoto(of runID: String) {
        guard var run = run(id: runID), let name = run.photoFileName else { return }
        removePhotoFile(name)
        run.photoFileName = nil
        update(run)
    }

    func photo(of run: KitchenCookRun) -> UIImage? {
        guard let name = run.photoFileName else { return nil }
        return UIImage(contentsOfFile: photoFolder.appendingPathComponent(name).path)
    }

    func thumbnail(of run: KitchenCookRun) -> UIImage? {
        guard let name = run.photoFileName else { return nil }
        if let cached = thumbnails[name] { return cached }
        // The shorter side at 160 points, so a square crop of it stays sharp.
        guard let photo = photo(of: run), min(photo.size.width, photo.size.height) > 0 else { return nil }
        let scale = 160 / min(photo.size.width, photo.size.height)
        let thumbnail = photo.preparingThumbnail(of: CGSize(width: photo.size.width * scale,
                                                            height: photo.size.height * scale))
        thumbnails[name] = thumbnail
        return thumbnail
    }

    private func removePhotoFile(_ name: String) {
        thumbnails[name] = nil
        try? FileManager.default.removeItem(at: photoFolder.appendingPathComponent(name))
    }

    private func load() {
        guard let data = try? Data(contentsOf: fileURL) else { return }
        do {
            runs = try KitchenCookRunFile.decode(data)
        } catch KitchenCookRunFileError.unsupportedVersion {
            // Written by a newer build; whatever it holds stays as it is.
            isReadOnly = true
            lastError = String(localized: "Die Kochhistorie stammt von einer neueren Version von CookPlanner. Sie bleibt unverändert, bis die App aktualisiert ist.")
        } catch {
            // The file is not what this app writes. Nothing is thrown away:
            // the bytes move aside under a dated name, and the history
            // starts over rather than being overwritten by the next record.
            let stamp = ISO8601DateFormatter.string(from: Date(), timeZone: .current,
                                                    formatOptions: [.withFullDate, .withTime, .withColonSeparatorInTime])
                .replacingOccurrences(of: ":", with: "-")
            let aside = fileURL.deletingLastPathComponent().appendingPathComponent("cook-runs.broken-\(stamp).json")
            try? FileManager.default.moveItem(at: fileURL, to: aside)
            runs = []
            lastError = String(localized: "Die Kochhistorie konnte nicht gelesen werden. Die Datei liegt als Kopie „\(aside.lastPathComponent)“ im Ordner der App; die Historie beginnt leer.")
        }
    }

    private func save() {
        guard !isReadOnly else { return }
        do {
            try KitchenCookRunFile(runs: runs).encoded().write(to: fileURL, options: .atomic)
        } catch {
            lastError = String(localized: "Die Kochhistorie konnte nicht gesichert werden: \(error.localizedDescription)")
        }
    }
}
