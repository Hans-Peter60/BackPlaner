import BakePlannerCore
import Foundation

/// CookPlanner's settings on Android, kept in `settings.json` next to the
/// dish database. BakePlanner's Android app found that what it wrote into
/// UserDefaults was not read back, and was gone after a restart; so, as
/// there, the values live in a file of their own. The keys are the
/// iPhone's (`settings.budgetMinutes` …), so a later settings transfer can
/// use them unchanged.
enum SettingsFile {

    /// The values by kind, so they come back as what they were.
    struct Values: Codable {
        var integers: [String: Int] = [:]
        var flags: [String: Bool] = [:]
        var texts: [String: String] = [:]
        var numbers: [String: Double] = [:]
    }

    private static var url: URL {
        URL.applicationSupportDirectory.appendingPathComponent("settings.json")
    }

    nonisolated(unsafe) private static var values = Values()

    /// Reads the file. Called from the app delegate's onInit, before any
    /// view reads a setting.
    static func restore() {
        guard let data = try? Data(contentsOf: url) else { return }
        do {
            values = try JSONDecoder().decode(Values.self, from: data)
        } catch {
            // Kept beside the fresh file, not overwritten by the next save.
            logger.error("could not read the settings: \(error)")
            let aside = url.deletingPathExtension().appendingPathExtension("broken-\(Int(Date().timeIntervalSince1970)).json")
            try? FileManager.default.moveItem(at: url, to: aside)
        }
    }

    static func integer(_ key: String, default fallback: Int) -> Int {
        values.integers[key] ?? fallback
    }

    static func flag(_ key: String, default fallback: Bool) -> Bool {
        values.flags[key] ?? fallback
    }

    static func text(_ key: String) -> String? {
        values.texts[key]
    }

    static func number(_ key: String) -> Double? {
        values.numbers[key]
    }

    static func set(_ value: Int, forKey key: String) {
        values.integers[key] = value
        save()
    }

    static func set(_ value: Bool, forKey key: String) {
        values.flags[key] = value
        save()
    }

    static func set(_ value: String?, forKey key: String) {
        values.texts[key] = value
        save()
    }

    static func set(_ value: Double?, forKey key: String) {
        values.numbers[key] = value
        save()
    }

    private static func save() {
        do {
            try FileManager.default.createDirectory(at: URL.applicationSupportDirectory,
                                                    withIntermediateDirectories: true)
            try JSONEncoder().encode(values).write(to: url, options: .atomic)
        } catch {
            logger.error("could not keep the settings: \(error)")
        }
    }
}
