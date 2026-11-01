import BakePlannerCore
import Foundation

/// The settings of the Android app, kept in a file of their own and read
/// from there by the package as well.
///
/// On the iPhone the settings live in UserDefaults under the keys of
/// AppSettingsKeys, where the package reads them. On Android that failed
/// twice over: what the app wrote, the package did not read back (the
/// number of ovens stayed at 1), and after a restart every value was gone.
/// So the Android app keeps the values here, in `settings.json` next to
/// the recipe database, and hands the package a reader for them
/// (`AppSettings.settingsReader`) — no UserDefaults on either side.
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

    /// Reads the file and makes the package read its settings from here.
    /// Called from the app delegate's onInit, before any view or the model
    /// reads a setting.
    static func restore() {
        if let data = try? Data(contentsOf: url) {
            do {
                values = try JSONDecoder().decode(Values.self, from: data)
            } catch {
                logger.error("could not read the settings: \(error)")
            }
        }
        AppSettings.settingsReader = { key in SettingsFile.value(forKey: key) }
    }

    /// The stored value, nil when there is none (the default applies).
    static func value(forKey key: String) -> Any? {
        if let value = values.integers[key] { return value }
        if let value = values.flags[key] { return value }
        if let value = values.texts[key] { return value }
        return nil
    }

    static func set(_ value: Int, forKey key: String) {
        values.integers[key] = value
        save()
    }

    static func set(_ value: Bool, forKey key: String) {
        values.flags[key] = value
        save()
    }

    static func set(_ value: String, forKey key: String) {
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
