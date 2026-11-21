//
//  CookRunLog.swift
//  CookPlanner
//
//  The stopwatch records of the cooked dishes, newest first, in one JSON
//  file in Application Support next to the dish database.
//

import BakePlannerCore
import Foundation
import Observation

@Observable @MainActor
final class CookRunLog {

    static let shared = CookRunLog()

    private(set) var runs: [KitchenCookRun] = []
    private let fileURL: URL

    private init() {
        let folder = URL.applicationSupportDirectory.appendingPathComponent("CookPlanner", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        fileURL = folder.appendingPathComponent("cook-runs.json")
        load()
    }

    func runs(of dishID: String) -> [KitchenCookRun] {
        runs.filter { $0.dishID == dishID }
    }

    func add(_ run: KitchenCookRun) {
        runs.insert(run, at: 0)
        save()
    }

    func delete(id: String) {
        runs.removeAll { $0.id == id }
        save()
    }

    private func load() {
        guard let data = try? Data(contentsOf: fileURL) else { return }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        runs = (try? decoder.decode([KitchenCookRun].self, from: data)) ?? []
    }

    private func save() {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(runs) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }
}
