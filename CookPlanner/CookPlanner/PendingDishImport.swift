//
//  PendingDishImport.swift
//  CookPlanner
//
//  The hand-off between the share extension and the app: the extension
//  parks the address of the shared page in the App Group container and
//  opens the app by its URL scheme; the app picks the address up and starts
//  the web import with it. The address travels twice on purpose — in the
//  deep link, the fast path, and in the container, which still works when
//  opening the app from the extension is refused. Compiled into both the
//  app and the share extension.
//

import Foundation

enum PendingDishImport {

    static let appGroupIdentifier = "group.de.hpm64625.CookPlanner"
    private static let fileName = "pending-web-import.json"

    /// The app's URL scheme, declared in the app target's Info.
    private static let scheme = "cookplanner"
    private static let deepLinkHost = "import-web"

    /// An address older than this is ignored: the cook gave up on it long
    /// ago, and the app must not surprise them with an import days later.
    private static let maximumAge: TimeInterval = 15 * 60

    private struct Payload: Codable {
        let url: URL
        let storedAt: Date
    }

    private static var fileURL: URL? {
        FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: appGroupIdentifier)?
            .appendingPathComponent(fileName)
    }

    /// Parks `url` for the app. Written by the extension.
    static func store(_ url: URL) throws {
        guard let fileURL else { throw CocoaError(.fileNoSuchFile) }
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(Payload(url: url, storedAt: Date())).write(to: fileURL, options: .atomic)
    }

    /// The waiting address, if there is a recent one. Removes it, so one
    /// hand-off starts one import and no more.
    static func takePending() -> URL? {
        guard let fileURL, let data = try? Data(contentsOf: fileURL) else { return nil }
        try? FileManager.default.removeItem(at: fileURL)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let payload = try? decoder.decode(Payload.self, from: data),
              Date().timeIntervalSince(payload.storedAt) < maximumAge else { return nil }
        return payload.url
    }

    /// `cookplanner://import-web?url=…` — opens the app on the web import.
    static func deepLink(for url: URL) -> URL? {
        var components = URLComponents()
        components.scheme = scheme
        components.host = deepLinkHost
        components.queryItems = [URLQueryItem(name: "url", value: url.absoluteString)]
        return components.url
    }

    /// The page address carried by a deep link, or nil when the link is
    /// something else.
    static func url(fromDeepLink link: URL) -> URL? {
        guard link.scheme?.lowercased() == scheme,
              link.host()?.lowercased() == deepLinkHost,
              let components = URLComponents(url: link, resolvingAgainstBaseURL: false),
              let value = components.queryItems?.first(where: { $0.name == "url" })?.value,
              let url = URL(string: value),
              let pageScheme = url.scheme?.lowercased(),
              pageScheme == "https" || pageScheme == "http" else { return nil }
        return url
    }
}
