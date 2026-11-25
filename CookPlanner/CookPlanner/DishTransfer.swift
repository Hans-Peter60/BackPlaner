//
//  DishTransfer.swift
//  CookPlanner
//
//  Dishes as a file (KitchenDishFile, extension .cookplanner): one dish
//  shared from its plan, all own dishes as a backup from the settings, and
//  the way back in — through the file picker, or by tapping such a file in
//  Mail, Messages or Files, which opens the app. Reading merges: dishes the
//  app already has stay untouched (KitchenDishTransfer.merge).
//

import BakePlannerCore
import CoreTransferable
import SwiftUI
import UniformTypeIdentifiers

extension UTType {
    /// Declared in Info.plist as an exported type, conforming to JSON.
    static let cookPlannerDishes = UTType(exportedAs: "de.hpm64625.CookPlanner.dishes")
}

/// The dishes to hand to the share sheet, written when it asks.
struct DishFileExport: Transferable {
    let dishes: [KitchenDish]

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(exportedContentType: .cookPlannerDishes) { export in
            SentTransferredFile(try export.writeFile())
        }
    }

    func writeFile() throws -> URL {
        let folder = try TemporaryExports.folder(prefix: "Export-")
        let url = folder.appendingPathComponent(KitchenDishTransfer.fileName(for: dishes))
        try KitchenDishFile(dishes: dishes).encoded().write(to: url, options: .atomic)
        return url
    }
}

extension DishLibrary {

    /// Reads the file at `url` and keeps the dishes that are new; answers
    /// with the sentence the alert shows.
    func importDishes(at url: URL) -> String {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        let file: KitchenDishFile
        do {
            file = try KitchenDishFile.decode(try Data(contentsOf: url))
        } catch KitchenDishFileError.unsupportedVersion {
            return String(localized: "Die Datei stammt aus einer neueren Version von CookPlanner. Bitte die App aktualisieren.")
        } catch {
            return String(localized: "Die Datei ist keine CookPlanner-Datei oder beschädigt.")
        }
        let result = KitchenDishTransfer.merge(file.kitchenDishes, into: dishes)
        var kept = 0
        for dish in result.added where save(dish) { kept += 1 }
        if kept == 0 && result.alreadyThere > 0 {
            return String(localized: "Alle \(result.alreadyThere) Gerichte waren schon da.")
        }
        if result.alreadyThere > 0 {
            return String(localized: "\(kept) Gerichte übernommen, \(result.alreadyThere) waren schon da.")
        }
        return String(localized: "\(kept) Gerichte übernommen.")
    }
}

/// Folders in tmp for files handed to the share sheet. The system empties
/// tmp only now and then; the folders of earlier shares with the same
/// prefix are removed before a new one is made, so they do not pile up.
enum TemporaryExports {
    static func folder(prefix: String) throws -> URL {
        let tmp = URL.temporaryDirectory
        let manager = FileManager.default
        for old in (try? manager.contentsOfDirectory(at: tmp, includingPropertiesForKeys: nil)) ?? []
        where old.lastPathComponent.hasPrefix(prefix) {
            try? manager.removeItem(at: old)
        }
        let folder = tmp.appendingPathComponent(prefix + UUID().uuidString, isDirectory: true)
        try manager.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }
}
