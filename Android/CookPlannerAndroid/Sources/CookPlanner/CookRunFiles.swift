import BakePlannerCore
import Foundation
import Observation
import SkipFuse

/// How the cook mode's clock runs (the iPhone's CookClockMode): Challenge
/// counts the budget down, Training runs a stopwatch, Relaxed shows no
/// clock at all.
enum CookClockMode: String, CaseIterable {
    case challenge, training, relaxed

    static let settingsKey = "settings.clockMode"

    static var stored: CookClockMode {
        SettingsFile.text(settingsKey).flatMap(CookClockMode.init(rawValue:)) ?? .challenge
    }

    var title: String {
        switch self {
        case .challenge: String(localized: "Challenge", bundle: .module)
        case .training: String(localized: "Training", bundle: .module)
        case .relaxed: String(localized: "Entspannt", bundle: .module)
        }
    }

    var explanation: String {
        switch self {
        case .challenge: String(localized: "Die Uhr zählt das Zeitbudget rückwärts, wie in der Sendung.", bundle: .module)
        case .training: String(localized: "Die Uhr läuft ab 0:00 – so lernst Du, wie lange das Gericht wirklich dauert.", bundle: .module)
        case .relaxed: String(localized: "Keine Uhr, kein Überfällig: Die Schritte kommen der Reihe nach, nur Topf und Ofen behalten ihre Zeit.", bundle: .module)
        }
    }

    var showsClock: Bool { self != .relaxed }
}

/// The run under way, kept in `cook-run.json` at every change (the
/// iPhone's CookRunState, which lives in UserDefaults there), so a run
/// survives the app being ended.
struct CookRunState: Codable, Equatable {
    struct Tick: Codable, Equatable {
        enum Kind: String, Codable { case done, hands }
        var id: String
        var kind: Kind
    }

    var dishID: String
    var startedAt: Date
    var pausedAt: Date?
    var pausedSeconds: Double
    var finished: [String: Int]
    var handsDone: [String: Int]
    var ticks: [Tick]
    var doneSeconds: [String: Int]
    var handsDoneSeconds: [String: Int]
    var startSeconds: [String: Int]
    var clockMode: String?

    /// A run older than this is not taken up again: the meal is long over.
    static let resumeWithin: Double = 6 * 60 * 60

    private static var url: URL {
        URL.applicationSupportDirectory.appendingPathComponent("cook-run.json")
    }

    static func load() -> CookRunState? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(CookRunState.self, from: data)
    }

    func save() {
        do {
            try FileManager.default.createDirectory(at: URL.applicationSupportDirectory, withIntermediateDirectories: true)
            try JSONEncoder().encode(self).write(to: Self.url, options: .atomic)
        } catch {
            logger.error("could not keep the run: \(error)")
        }
    }

    static func clear() {
        try? FileManager.default.removeItem(at: url)
    }

    var isResumable: Bool {
        Date().timeIntervalSince(startedAt) < Self.resumeWithin
    }
}

/// The stopwatch records of every cook, in `cook-runs.json` — the iPhone's
/// file format (KitchenCookRunFile), so a backup carries them both ways.
@Observable
@MainActor
final class CookRunLog {
    static let shared = CookRunLog()

    private(set) var runs: [KitchenCookRun] = []

    private var url: URL {
        URL.applicationSupportDirectory.appendingPathComponent("cook-runs.json")
    }

    /// The photos of the records, by file name, as on the iPhone ("Photos").
    var photoFolder: URL {
        URL.applicationSupportDirectory.appendingPathComponent("Photos", isDirectory: true)
    }

    func run(id: String) -> KitchenCookRun? {
        runs.first { $0.id == id }
    }

    /// The records' photos for a backup, by file name.
    func backupPhotos() -> [String: Data] {
        var photos = [String: Data]()
        for run in runs {
            guard let name = run.photoFileName, photos[name] == nil,
                  let data = try? Data(contentsOf: photoFolder.appendingPathComponent(name)) else { continue }
            photos[name] = data
        }
        return photos
    }

    /// Records from a backup: those not here yet, with their photos.
    func importRuns(_ incoming: [KitchenCookRun], photos: [String: Data]) -> (added: Int, alreadyThere: Int) {
        var added = 0
        var known = 0
        for run in incoming {
            if self.run(id: run.id) != nil {
                known += 1
                continue
            }
            if let name = run.photoFileName, let data = photos[name] {
                let target = photoFolder.appendingPathComponent(name)
                if !FileManager.default.fileExists(atPath: target.path) {
                    try? FileManager.default.createDirectory(at: photoFolder, withIntermediateDirectories: true)
                    try? data.write(to: target, options: .atomic)
                }
            }
            runs.append(run)
            added += 1
        }
        guard added > 0 else { return (0, known) }
        runs.sort { $0.startedAt > $1.startedAt }
        save()
        return (added, known)
    }

    init() {
        if let data = try? Data(contentsOf: url), let decoded = try? KitchenCookRunFile.decode(data) {
            runs = decoded.sorted { $0.startedAt > $1.startedAt }
        }
    }

    func runs(of dishID: String) -> [KitchenCookRun] {
        runs.filter { $0.dishID == dishID }
    }

    func add(_ run: KitchenCookRun) {
        runs.insert(run, at: 0)
        save()
    }

    func update(_ run: KitchenCookRun) {
        guard let index = runs.firstIndex(where: { $0.id == run.id }) else { return }
        runs[index] = run
        save()
    }

    func delete(id: String) {
        runs.removeAll { $0.id == id }
        save()
    }

    private func save() {
        do {
            try FileManager.default.createDirectory(at: URL.applicationSupportDirectory, withIntermediateDirectories: true)
            try KitchenCookRunFile(runs: runs).encoded().write(to: url, options: .atomic)
        } catch {
            logger.error("could not keep the cooking records: \(error)")
        }
    }
}
