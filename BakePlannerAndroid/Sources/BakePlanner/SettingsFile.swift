import Foundation

/// The settings of the Android app, kept in a file of their own.
///
/// The package reads the settings from `UserDefaults.standard` under the
/// iPhone's keys (AppSettings.stored…), and the app writes them there. On
/// Android, Foundation's UserDefaults keeps them only while the app runs:
/// after a restart the number of ovens, the day window and the rest were
/// back at their defaults. So every value is also written to
/// `settings.json` next to the recipe database, and put back into
/// UserDefaults when the app starts (`restore`, from the app delegate's
/// onInit, before any view or the model reads a setting).
enum SettingsFile {

    /// The values by kind, so they come back as what they were: a Bool
    /// read back from JSON as a number would not be one to Swift on Android.
    struct Values: Codable {
        var integers: [String: Int] = [:]
        var flags: [String: Bool] = [:]
        var texts: [String: String] = [:]
    }

    private static var url: URL {
        URL.applicationSupportDirectory.appendingPathComponent("settings.json")
    }

    nonisolated(unsafe) private static var values = Values()

    /// Reads the file and puts every value into UserDefaults.
    static func restore() {
        guard let data = try? Data(contentsOf: url),
              let stored = try? JSONDecoder().decode(Values.self, from: data) else { return }
        values = stored
        let defaults = UserDefaults.standard
        for (key, value) in stored.integers { defaults.set(value, forKey: key) }
        for (key, value) in stored.flags { defaults.set(value, forKey: key) }
        for (key, value) in stored.texts { defaults.set(value, forKey: key) }
    }

    static func set(_ value: Int, forKey key: String) {
        UserDefaults.standard.set(value, forKey: key)
        values.integers[key] = value
        save()
    }

    static func set(_ value: Bool, forKey key: String) {
        UserDefaults.standard.set(value, forKey: key)
        values.flags[key] = value
        save()
    }

    static func set(_ value: String, forKey key: String) {
        UserDefaults.standard.set(value, forKey: key)
        values.texts[key] = value
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
