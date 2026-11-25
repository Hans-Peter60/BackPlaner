//
//  DishImportClient.swift
//  CookPlanner
//
//  The call to the Cloud Function analyzeDishSteps: the pasted recipe text
//  goes up, the work steps come back (CloudDishAnalysis). The function
//  wants a signed-in user and App Check; the user is anonymous, signed in
//  on first use.
//

import BakePlannerCore
import FirebaseAuth
@preconcurrency import FirebaseFunctions
import Foundation

final class DishImportClient: @unchecked Sendable {
    static let shared = DishImportClient()

    private let functions = Functions.functions(region: "europe-west1")

    private init() {}

    /// Reads a cooking recipe into work steps.
    func analyzeText(_ text: String) async throws -> CloudDishAnalysis {
        if Auth.auth().currentUser == nil {
            do {
                try await Auth.auth().signInAnonymously()
            } catch {
                throw DishImportError.from(error)
            }
        }
        let callable = functions.httpsCallable("analyzeDishSteps")
        callable.timeoutInterval = 250
        let result: HTTPSCallableResult
        do {
            result = try await callable.call(["text": text])
        } catch {
            throw DishImportError.from(error)
        }
        guard let payload = result.data as? [String: Any], JSONSerialization.isValidJSONObject(payload) else {
            throw DishImportError.invalidResponse
        }
        let data = try JSONSerialization.data(withJSONObject: payload)
        #if DEBUG
        Self.keepForTuning(data)
        #endif
        do {
            return try JSONDecoder().decode(CloudDishAnalysis.self, from: data)
        } catch {
            // The answer has a shape this build does not know: its own
            // words, not the decoder's English.
            throw DishImportError.invalidResponse
        }
    }

    #if DEBUG
    /// Development builds keep every answer as a file in Application
    /// Support/CookPlanner/imports, to read what the model made of a recipe
    /// and to sharpen the prompt against it.
    private static func keepForTuning(_ data: Data) {
        let folder = URL.applicationSupportDirectory.appendingPathComponent("CookPlanner/imports", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let stamp = ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "-")
        let pretty = (try? JSONSerialization.jsonObject(with: data))
            .flatMap { try? JSONSerialization.data(withJSONObject: $0, options: [.prettyPrinted, .sortedKeys]) } ?? data
        try? pretty.write(to: folder.appendingPathComponent("\(stamp).json"))
    }
    #endif
}

enum DishImportError: LocalizedError {
    case invalidResponse
    case hourlyLimit
    case monthlyLimit
    case offline
    case timedOut
    case notAllowed
    case other(String)

    static func from(_ error: Error) -> DishImportError {
        if error is CancellationError { return .other("") }
        let nsError = error as NSError
        if nsError.domain == NSURLErrorDomain {
            switch URLError.Code(rawValue: nsError.code) {
            case .notConnectedToInternet, .networkConnectionLost, .dataNotAllowed, .cannotFindHost,
                 .cannotConnectToHost, .dnsLookupFailed, .internationalRoamingOff:
                return .offline
            case .timedOut:
                return .timedOut
            default:
                break
            }
        }
        if nsError.domain == FunctionsErrorDomain {
            switch FunctionsErrorCode(rawValue: nsError.code) {
            case .resourceExhausted:
                let reason = (nsError.userInfo[FunctionsErrorDetailsKey] as? [String: Any])?["reason"] as? String
                return reason == "monthly-limit" ? .monthlyLimit : .hourlyLimit
            case .unavailable:
                return .offline
            case .deadlineExceeded:
                return .timedOut
            case .unauthenticated, .permissionDenied, .failedPrecondition:
                return .notAllowed
            default:
                break
            }
        }
        if nsError.domain == AuthErrorDomain {
            return AuthErrorCode(rawValue: nsError.code) == .networkError ? .offline : .notAllowed
        }
        return .other(error.localizedDescription)
    }

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return String(localized: "Die Antwort der Analyse war unvollständig.")
        case .hourlyLimit:
            return String(localized: "Das stündliche Analyse-Limit ist erreicht. Bitte später noch einmal.")
        case .monthlyLimit:
            return String(localized: "Die kostenlosen Importe dieses Monats sind aufgebraucht.")
        case .offline:
            return String(localized: "Keine Verbindung zum Analyse-Dienst. Bitte die Internetverbindung prüfen und noch einmal versuchen.")
        case .timedOut:
            return String(localized: "Die Analyse hat zu lange gedauert. Bitte noch einmal versuchen, bei langen Rezepten vielleicht in zwei Teilen.")
        case .notAllowed:
            return String(localized: "Der Analyse-Dienst hat die Anfrage nicht zugelassen. Bitte die App aktualisieren oder später noch einmal versuchen.")
        case .other(let message):
            return message
        }
    }
}
